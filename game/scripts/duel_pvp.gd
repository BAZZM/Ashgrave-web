extends Node

const Tune := preload("res://scripts/combat_tune.gd")

var d: Duel
var _pvp_cool := 0.0
var _pvp_idle := 0.0
var _pvp_quiet := 0.0
var _pvp_ping := 0.0
var _pvp_turn_due := false
var _pvp_wait := 0.0
## Posture between players (both games at combat version 2 or more).
var _opp_q := -1
var _my_q := 0
var _my_pst_until := 0
var _last_letter := "L"
var _atk_queue: Array = []


func _init(owner_duel: Duel) -> void:
	d = owner_duel


func _pvp_my_turn() -> void:
	d.pvp_turn = "attack"
	d.pvp_left = 3
	_pvp_cool = 0.7
	_pvp_idle = 0.0
	d.hud.banner("YOUR ATTACK", Color(1.0, 0.8, 0.4), 0.9)


func _pvp_their_turn(tell_them := true) -> void:
	d.pvp_turn = "defend"
	d.pvp_left = 0
	_pvp_wait = 0.0
	if tell_them:
		Online.send_to(d.pvp.id, {"k": "turn"})
	d.hud.banner("DEFEND", Color(0.6, 0.8, 1.0), 0.9)


func _pvp_tick(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.05)
	if d.e_state == Duel.EState.INTRO:
		d.e_timer -= delta
		if d.e_timer <= 0.0:
			d.e_state = Duel.EState.IDLE
			d.enemy.play(&"idle")
			if d.pvp.first:
				_pvp_my_turn()
			else:
				_pvp_their_turn(false)
		return
	_pvp_cool -= delta
	if d.e_state == Duel.EState.IDLE and not _atk_queue.is_empty() and d.p_state != Duel.PState.DEAD:
		_begin_defence(_atk_queue.pop_front())
	_pvp_quiet += real
	_pvp_ping += real
	if _pvp_ping > 3.0:
		_pvp_ping = 0.0
		var ping := {"k": "ping", "hp": d.p_hp}
		if d.posture.pvp_new():
			ping["po"] = roundi(d.posture.p_percent())
		Online.send_to(d.pvp.id, ping)
	if _pvp_quiet > 14.0 and d.result == "":
		d.hud.banner("%s has left" % d.pvp.name, Color(1, 1, 1), 1.2)
		d.reward.left = true
		d._end("win")
		return
	if d.pvp_turn == "defend":
		_pvp_wait += real

		if d.e_state == Duel.EState.IDLE and d.p_state != Duel.PState.DEAD and (_pvp_turn_due or _pvp_wait > 9.0):
			_pvp_turn_due = false
			_pvp_my_turn()
	if d.pvp_turn == "attack":
		_pvp_idle += real
		if (d.pvp_left <= 0 and _pvp_cool <= -0.9) or _pvp_idle > 6.0:
			_pvp_their_turn()
	if d._bot == "pvp":
		d.bots._pvp_bot()


func _begin_defence(incoming: AttackDef) -> void:
	d.cur_attack = incoming
	d.combo = [d.cur_attack]
	d.combo_i = 0
	d.ai._begin_attack()


func _pvp_attack(letter: String) -> void:
	# While the other player's posture is broken, the next swing is an execution,
	# even out of turn and with no swings left.
	var exec: bool = d.posture.pvp_new() and Time.get_ticks_msec() < d.pvp_exec_until
	if exec:
		if _pvp_cool > 0.0 or d.p_state != Duel.PState.READY:
			return
		d.pvp_left = maxi(d.pvp_left, 1)
		d.pvp_exec_until = 0
	elif d.pvp_turn != "attack" or d.pvp_left <= 0 or _pvp_cool > 0.0 or d.p_state != Duel.PState.READY:
		return
	_last_letter = letter
	d.pvp_left -= 1
	_pvp_cool = 1.25
	_pvp_idle = 0.0

	var dir: int = {"L": AttackDef.Dir.LEFT, "R": AttackDef.Dir.RIGHT, "D": AttackDef.Dir.OVER, "U": AttackDef.Dir.THRUST} [letter]
	var atk := {"k": "atk", "dir": dir, "dmg": d.slash_damage * (2.6 if dir == AttackDef.Dir.OVER else 2.0)}
	if exec:
		atk["x"] = 1
		print("PVP exec sent")
	Online.send_to(d.pvp.id, atk)
	d.p_state = Duel.PState.SWING
	d.p_timer = 0.5
	d.player.play(&"slash", {"L": -1, "R": 1, "U": 2, "D": 3} [letter] as int, 0.35)
	d.sfx.play("whoosh", -6.0)


func _pvp_report(outcome: String, riposte := 0.0, perfect := false) -> void:
	if d.pvp.is_empty():
		return
	var res := {"k": "res", "o": outcome, "hp": maxf(d.p_hp, 0.0), "rip": riposte}
	if d.posture.pvp_new():
		res["po"] = roundi(d.posture.p_percent())
		if perfect:
			res["pf"] = 1
	Online.send_to(d.pvp.id, res)


## My posture just filled: the other player's next swing is an execution.
func send_pst() -> void:
	_my_q += 1
	_my_pst_until = Time.get_ticks_msec() + int(float(Tune.B1.pvp_broken_time) * 1000.0)
	Online.send_to(d.pvp.id, {"k": "pst", "po": 100, "pb": float(Tune.B1.pvp_broken_time), "q": _my_q})


## An execution lands on me: unavoidable, a share of my own health.
func _exec_hit(dir: int) -> void:
	_my_pst_until = 0
	print("PVP exec taken dir=%d hp=%.0f" % [dir, d.p_hp])
	d.enemy.play(&"strike", dir, 0.1)
	d.hud.banner("EXECUTED", Color(1.0, 0.5, 0.3), 0.8)
	d._hurt(d.player_max_hp * float(Tune.B1.pvp_exec_share), dir)
	_pvp_report("exec")


static func _swipe_vec(letter: String) -> Vector2:
	match letter:
		"L": return Vector2(-1, 0)
		"R": return Vector2(1, 0)
		"U": return Vector2(0, -1)
	return Vector2(0, 1)


func _pvp_message(from: String, m: Dictionary) -> void:
	if from != String(d.pvp.id):
		return
	if d.result != "":
		# The duel is over here, but the attacker still gets one answer per attack.
		if String(m.get("k", "")) == "atk":
			_pvp_report("dodged")
		return
	_pvp_quiet = 0.0
	if m.has("hp"):
		d.e_hp = clampf(float(m.hp), 0.0, d.def.max_hp)
	if m.has("po") and d.posture.pvp_new():
		d.e_posture = clampf(float(m.po), 0.0, 100.0) / 100.0 * d.def.break_max
	match String(m.get("k", "")):
		"pst":
			var q := int(m.get("q", 0))
			if d.posture.pvp_new() and q > _opp_q:
				_opp_q = q
				print("PVP pst heard q=%d" % q)
				d.e_posture = d.def.break_max
				d.pvp_exec_until = Time.get_ticks_msec() + int(clampf(float(m.get("pb", 2.5)), 0.0, 3.0) * 1000.0)
				d.hud.banner("POSTURE BROKEN", Color(1.0, 0.85, 0.3), 0.9)
				d.fx.posture_broken()
		"atk":
			if int(m.get("x", 0)) == 1 and d.posture.pvp_new() and Time.get_ticks_msec() < _my_pst_until + int(float(Tune.B1.pvp_grace) * 1000.0):
				_exec_hit(int(m.dir))
				return
			if d.e_state == Duel.EState.INTRO:
				d.e_state = Duel.EState.IDLE
			d.pvp_turn = "defend"
			_pvp_wait = 0.0
			_pvp_turn_due = false
			var incoming := AttackDef.make(int(m.dir), 0.9, float(m.dmg))
			if d.e_state == Duel.EState.WINDUP:
				# An attack is already being defended (an execution that came too late, say):
				# this one waits its turn, so every attack still gets its own answer.
				_atk_queue.append(incoming)
				return
			_begin_defence(incoming)
		"res":
			var at := d.enemy.get_clash_point() + Vector3(randf_range(-0.3, 0.3), 0.4, 0)
			match String(m.o):
				"hit":
					d.enemy.play(&"hit", [-1, 1].pick_random(), 0.12)
					d.enemy.flash(Color(1.0, 0.9, 0.7))
					d.fx.cut_landed(_swipe_vec(_last_letter), _last_letter, false)
					d.hud.float_text("HIT", at, Color(1.0, 0.9, 0.5), true)
					d.stats.sword_dmg += 12.0
				"exec":
					d.enemy.play(&"hit", [-1, 1].pick_random(), 0.12)
					d.enemy.flash(Color.WHITE)
					d.sfx.layer("L7")
					d.fx._burst(d.enemy.get_clash_point(), 28)
					d.fx._burst2(d.enemy.get_clash_point(), 28)
					d.fx._hitstop(float(Tune.B1.fin_freeze))
					d._shake = 1.2
					d.hud.banner("EXECUTION", Color(1.0, 0.75, 0.3), 0.8)
					d.hud.float_text("EXECUTED", at, Color(1.0, 0.55, 0.2), true)
					d.stats.execs += 1
					d.stats.sword_dmg += d.def.max_hp * float(Tune.B1.pvp_exec_share)
				"dodged": d.hud.float_text("DODGED", at, Color(0.7, 0.85, 1.0))
				"blocked":
					d.sfx.layer("L6")
					d.hud.float_text("BLOCKED", at, Color(0.7, 0.8, 1.0))
				"parried":
					var pf := int(m.get("pf", 0)) == 1
					if pf:
						d.sfx.layer("L3")
					else:
						d.sfx.play("clang")
					d.fx._burst(d.player.get_clash_point().lerp(d.enemy.get_clash_point(), 0.5), 24)
					d.hud.banner("PARRIED!", Color(1.0, 0.5, 0.4), 0.7)
					d.pvp_turn = "defend"
					d.pvp_left = 0
					# Being parried costs me posture (the defender's blow, perfect or not, fills my bar).
					if d.posture.pvp_new():
						d.posture.p_gain_pct(float(Tune.B1.pvp_parried_base) * float(Tune.B1.gain_perfect if pf else Tune.B1.gain_parry))
					d._hurt(float(m.get("rip", 10.0)), AttackDef.Dir.LEFT)
		"turn":
			_pvp_turn_due = true
		"dead":
			var won := int(m.get("gold", 0))
			Run.data.gold += won
			Run.data.pvp_w += 1
			d.reward.gold = won
			d.e_hp = 0.0
			d.e_state = Duel.EState.DEAD
			d.enemy.play(&"death")
			d.player.play(&"victory")
			d.sfx.layer("L7")
			d.fx._hitstop(float(Tune.B1.fin_freeze))
			d._shake = 1.2
			d._end("win")
