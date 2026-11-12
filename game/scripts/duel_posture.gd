extends Node
## Posture (docs/COMBAT_SPEC.md 2.2). The foe's posture is `d.e_posture` (full at
## `d.def.break_max`): parries and clean defence fill it, it drains back when the
## pressure stops, and a full bar leaves the foe open for an execution.
## The player's posture is the shield bar read the other way: posture = shield_max - shield,
## so shield gear keeps its meaning as capacity. Numbers are in combat_tune.gd.

const Tune := preload("res://scripts/combat_tune.gd")

var d: Duel
var p_stunned := false
var _e_idle := 0.0
var _p_idle := 0.0


func _init(owner_duel: Duel) -> void:
	d = owner_duel


## A duel against a player whose game is older than Build 1 keeps the old guard rules.
func classic() -> bool:
	return not d.pvp.is_empty() and int(d.pvp.get("cv", 1)) < 2


func pvp_new() -> bool:
	return not d.pvp.is_empty() and int(d.pvp.get("cv", 1)) >= 2


func reset_foe() -> void:
	_e_idle = 0.0


## The player's posture as a percentage, for the other player's screen.
func p_percent() -> float:
	return clampf((1.0 - d.shield / maxf(d.shield_max, 1.0)) * 100.0, 0.0, 100.0)


## Called once a frame with game-time delta.
func tick(delta: float) -> void:
	_tick_player(delta)
	_tick_foe(delta)


func _tick_player(delta: float) -> void:
	_p_idle += delta
	if d.blocking or p_stunned:
		return
	if classic():
		d.shield = minf(d.shield + delta * float(Tune.B1.p_classic_rate), d.shield_max)
	elif _p_idle >= float(Tune.B1.p_drain_delay):
		d.shield = minf(d.shield + delta * float(Tune.B1.p_drain_rate), d.shield_max)


func _tick_foe(delta: float) -> void:
	_e_idle += delta
	if d.e_posture <= 0.0 or _e_idle < float(Tune.B1.drain_delay) or not d.pvp.is_empty():
		return
	if d.e_state in [Duel.EState.OPEN, Duel.EState.FINISHER, Duel.EState.DEAD, Duel.EState.INTRO] or d.chill > 0.0:
		return
	var rate := float(Tune.B1.drain_rate) * (float(Tune.B1.drain_hp_floor) + float(Tune.B1.drain_hp_weight) * clampf(d.e_hp / d.def.max_hp, 0.0, 1.0))
	if d.enraged:
		rate *= float(Tune.B1.drain_enrage)
	d.e_posture = maxf(d.e_posture - rate * delta, 0.0)


# ---------------------------------------------------------------- the foe's posture

## Add posture to the foe (scaled by the weapon's break_mult). True if it filled.
func e_gain(amount: float) -> bool:
	if not d.pvp.is_empty() or d.e_state in [Duel.EState.FINISHER, Duel.EState.DEAD, Duel.EState.INTRO]:
		return false
	if d.e_state == Duel.EState.OPEN and d.open_reason == "posture":
		return false
	_e_idle = 0.0
	d.e_posture = minf(d.e_posture + amount * d.break_mult, d.def.break_max)
	if d.e_posture < d.def.break_max:
		return false
	_e_full()
	return true


func _e_full() -> void:
	d.e_posture = d.def.break_max
	d.ai._open(float(Tune.B1.exec_window), "posture")
	d.hud.banner("POSTURE BROKEN", Color(1.0, 0.85, 0.3), 0.9)
	d.fx.posture_broken()
	d.fx._finisher_cam()
	if d.tutorial_hint == "" and not Run.data.flags.get("execute_hint", false):
		Run.data.flags["execute_hint"] = true
		d.tutorial_hint = "execute"


## The first swipe at a foe with a full bar. Kills ordinary foes; takes a share
## of an elite's or a guardian's health.
func execute(v: Vector2, letter: String, anim_dir: int) -> void:
	var share := float(Tune.B1.exec_share.get(d.def.kind, 1.0))
	var dmg := share * d.def.max_hp
	var lethal := dmg >= d.e_hp
	d.stats.execs += 1
	d.stats.sword_dmg += minf(dmg, d.e_hp)
	d.e_posture = 0.0
	_e_idle = 0.0
	d.tutorial_hint = ""
	d.p_state = Duel.PState.SWING
	d.p_timer = d.slash_lock
	d.player.play(&"slash", anim_dir, 0.1)
	d.enemy.play(&"hit", -1 if letter == "L" else 1, 0.12)
	d.enemy.flash(Color.WHITE)
	d.fx._recoil(letter)
	d.hud.slash_streak(v, true)
	d.hud.banner("EXECUTION", Color(1.0, 0.75, 0.3), 0.8)
	d.hud.float_text(str(int(round(dmg))), d.enemy.get_clash_point() + Vector3(0, 0.3, 0), Color(1.0, 0.55, 0.2), true)
	d.fx._burst(d.enemy.get_clash_point(), 28)
	d.fx._burst2(d.enemy.get_clash_point(), 28)
	d.fx._buzz(90)
	d._damage_enemy(dmg, true)
	if lethal:
		d.cinematic = 1.0
		d._finish()
		return
	d._shake = 1.2
	d.sfx.layer("L7")
	d.fx.deciding_blow()
	d.open_reason = "exec"
	d.ai._open(float(Tune.B1.exec_after_open), "broken")
	d.get_tree().create_timer(float(Tune.B1.push_time) + float(Tune.B1.push_freeze) + float(Tune.B1.push_slow_time), true, false, true).timeout.connect(func():
		if d.result == "" and d.e_state != Duel.EState.FINISHER:
			d.fx._cam_release())


## The window to execute closed: the foe recovers with half its posture.
func execution_missed() -> void:
	d.e_posture = d.def.break_max * float(Tune.B1.exec_miss_posture)
	_e_idle = 0.0
	d.fx._cam_release()


# ---------------------------------------------------------------- the player's posture

## Add pressure to the player's posture (it comes off the shield). Does nothing
## in a classic duel, where only blocking costs shield.
func p_gain(amount: float) -> void:
	if classic() or p_stunned:
		return
	_p_idle = 0.0
	d.shield = maxf(d.shield - amount, 0.0)


## Blocking: the shield pays in full, as it always has.
func p_block(amount: float) -> void:
	_p_idle = 0.0
	d.shield = maxf(d.shield - amount, 0.0)


## Percent of a full bar (used for the parried player in a duel between players).
func p_gain_pct(pct: float) -> void:
	p_gain(pct / 100.0 * d.shield_max)
	p_check_break()


## If the player's posture is full: banner, stun, and (between players) tell the other side.
## `from_block` is for the old rule: a classic duel only shows the banner.
func p_check_break(from_block := false) -> void:
	if classic():
		if from_block:
			d.hud.banner("GUARD BROKEN", Color(1.0, 0.5, 0.3), 0.8)
			if Run.set_bonus("warden"):
				d.shield = d.shield_max * 0.5
		return
	if p_stunned or d.shield > 0.0 or d.p_state == Duel.PState.DEAD or d.result != "":
		return
	p_stunned = true
	d.blocking = false
	d.shield = 0.0
	d.p_state = Duel.PState.HIT
	d.p_timer = float(Tune.B1.p_stun_warden) if Run.set_bonus("warden") else float(Tune.B1.p_stun)
	d.player.play(&"broken")
	d.hud.banner("GUARD BROKEN", Color(1.0, 0.5, 0.3), 0.8)
	d.hud.edge_flash(Tune.B1.pbreak_edge)
	d.sfx.layer("L4", float(Tune.B1.pbreak_pitch))
	d.fx._buzz(80)
	if pvp_new():
		d.pvp_net.send_pst()


## The stun is over: posture resets to half.
func stun_end() -> void:
	p_stunned = false
	d.shield = d.shield_max * float(Tune.B1.p_reset)
	_p_idle = 0.0
