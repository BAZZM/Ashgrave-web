extends Node

var d: Duel
var _bot_decided := false

## Golden Shots (tools/shots.js): `--golden=duel-mid` / `duel-hud` play a fixed fresh-save duel at a
## slowed pace (fine time steps on a slow machine), then stop time at the same moment of the
## enemy's first attack and print "GOLDEN ready <name>". duel-mid hides the HUD, duel-hud shows it
## with the bars part way down.
var golden := ""
var _gname := ""
var _g_set := false


func _init(owner_duel: Duel) -> void:
	d = owner_duel


func _pvp_bot() -> void:
	if Time.get_ticks_msec() < d.pvp_exec_until and d.pvp_net._pvp_cool <= 0.0 and d.p_state == Duel.PState.READY:
		# The other player's posture is broken: execute, whatever the turn.
		d.pvp_net._pvp_attack(["L", "R", "D", "U"].pick_random())
	elif d.pvp_turn == "attack" and d.pvp_net._pvp_cool <= 0.0 and d.pvp_left > 0 and d.p_state == Duel.PState.READY and d.e_state != Duel.EState.WINDUP:
		d.pvp_net._pvp_attack(["L", "R", "D", "U"].pick_random())
	elif d.e_state == Duel.EState.WINDUP and d.e_timer <= d.parry_window * 0.6 and d.p_state == Duel.PState.READY and not _bot_decided:
		_bot_decided = true
		if randf() < 0.45 and d.cur_attack.dir != AttackDef.Dir.THRUST:
			d.input_swipe([Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1)][d.cur_attack.dir])
	if d.e_state != Duel.EState.WINDUP:
		_bot_decided = false


func golden_begin(shot_name: String) -> void:
	golden = shot_name
	_gname = shot_name
	Run.no_save = true
	Run.title_seen = true
	Run.data = Run.defaults()
	Run.data.tutorial_done = true
	Run.encounter = {"id": "test", "wild": "thrall"}
	d._base_time = 0.5
	seed(7)


func _golden_tick() -> void:
	if not d.started or d.cinematic > 0.0:
		return
	if not _g_set:
		_g_set = true
		if golden == "duel-hud":
			d.p_hp = d.player_max_hp * 0.7
			d.shield = d.shield_max * 0.8
			d.e_hp = d.def.max_hp * 0.55
			d.e_posture = 30.0
	if d.e_state == Duel.EState.WINDUP and d.e_timer <= d.windup_total * 0.4:
		d.hud.visible = _gname == "duel-hud"
		Engine.time_scale = 0.0
		golden = ""
		for i in 8:
			await RenderingServer.frame_post_draw
		print("GOLDEN ready ", _gname)


func _take_shot_if_due() -> void:
	if golden != "":
		_golden_tick()
		return
	if d._shot_path == "":
		return
	var due := false
	match d._shot_when:
		"title": due = d._t > 1.0
		"open": due = d.e_state == Duel.EState.OPEN and d.hit_combo >= 2
		"result": due = (d.result == "win" or d.result == "lose") and d.hud._result_age > 1.6
		_: due = d.e_state == Duel.EState.WINDUP and d.e_timer <= 0.6
	if d._shot_when == "open" and d.e_state == Duel.EState.WINDUP and d.e_timer < 0.15:
		d.input_swipe([Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2.ZERO][d.cur_attack.dir])
	if d._shot_when == "open" and d.e_state == Duel.EState.OPEN:
		d.input_swipe(Vector2([-1, 1][d.hit_combo % 2], 0))
	if d._shot_when == "result" and d.result == "":
		d._damage_enemy(9999.0)
		if d.e_state == Duel.EState.FINISHER:
			d._finish()
	if due:
		var path := d._shot_path
		d._shot_path = ""
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		d.get_viewport().get_texture().get_image().save_png(path)
		d.get_tree().quit()


## Test aid for looking at a moment in screenshots: `--hold=exec,fin,stun,push` stops the
## game's logic for 5 s of real time when the posture bar fills, when the killing blow
## lands and (push) freezes everything just after the deciding swipe. Prints DUELHOLD <what>.
func _hold_check() -> void:
	if d._hold_for.is_empty():
		return
	var now := Time.get_ticks_msec()
	if "exec" in d._hold_for and d.e_state == Duel.EState.OPEN and d.open_reason == "posture":
		d._hold_for.remove_at(d._hold_for.find("exec"))
		d._hold_until = now + 9000
		print("DUELHOLD exec")
	elif "fin" in d._hold_for and d.e_state == Duel.EState.FINISHER:
		d._hold_for.remove_at(d._hold_for.find("fin"))
		d._hold_until = now + 9000
		print("DUELHOLD fin")
	elif "push" in d._hold_for and d.e_state == Duel.EState.DEAD:
		d._hold_for.remove_at(d._hold_for.find("push"))
		d.get_tree().create_timer(0.7, true, false, true).timeout.connect(func():
			d.fx._restore_time()
			Engine.time_scale = 0.0
			print("DUELHOLD push"))


## Called at the moment something happens that a test may want to look at.
func hold_now(what: String) -> void:
	if what in d._hold_for:
		d._hold_for.remove_at(d._hold_for.find(what))
		d._hold_until = Time.get_ticks_msec() + 9000
		print("DUELHOLD ", what)


func _tick_bot() -> void:
	if d._bot == "idle" or not d.pvp.is_empty():
		return
	if d.p_hp < d.player_max_hp * 0.4:
		d.input_potion()
	if d.mana >= 100.0:
		d.input_spell()
	if d.shots > 0 and d.e_state == Duel.EState.WINDUP and d.cur_attack.dir == AttackDef.Dir.THRUST and d.e_timer < 0.4:
		d.input_ranged()
	if d._bot == "block":
		if not d.blocking:
			d.input_block(true)
		return
	if d.super_meter >= 100.0:
		d.input_super()
	for o in d.others:
		if float(o.tell) > 0.0 and float(o.tell) < 0.12 and d.p_state == Duel.PState.READY:
			d.input_dodge(1)
			return
	match d.e_state:
		Duel.EState.WINDUP:
			var dd := d.cur_attack.dir
			if d._bot == "dodge" or dd == AttackDef.Dir.THRUST:
				if d.e_timer <= 0.12 and d._feint_hold <= 0.0:
					d.input_dodge(1 if dd == AttackDef.Dir.LEFT else -1)
			elif d._bot == "perfect" and d.e_timer <= d.parry_window and d._feint_hold <= 0.0 and d.p_state == Duel.PState.READY:
				# Test bot: lands every parry inside the perfect window (the plain bot almost never does).
				d.e_timer = minf(d.e_timer, Duel.PERFECT_PARRY * 0.5)
				d.input_swipe([Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1)][dd])
			elif d._bot != "perfect" and d.e_timer <= d.parry_window * 0.6 and d._feint_hold <= 0.0 and d.p_state == Duel.PState.READY:
				d.input_swipe([Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1)][dd])
		Duel.EState.OPEN, Duel.EState.FINISHER:
			if d.p_state == Duel.PState.READY:
				d.input_swipe(Vector2([-1, 1][d.hit_combo % 2], 0.2))
