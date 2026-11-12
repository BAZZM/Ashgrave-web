extends Node

var d: Duel
var _pvp_cool := 0.0
var _pvp_idle := 0.0
var _pvp_quiet := 0.0
var _pvp_ping := 0.0
var _pvp_turn_due := false
var _pvp_wait := 0.0


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
	_pvp_quiet += real
	_pvp_ping += real
	if _pvp_ping > 3.0:
		_pvp_ping = 0.0
		Online.send_to(d.pvp.id, {"k": "ping", "hp": d.p_hp})
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


func _pvp_attack(letter: String) -> void:
	if d.pvp_turn != "attack" or d.pvp_left <= 0 or _pvp_cool > 0.0 or d.p_state != Duel.PState.READY:
		return
	d.pvp_left -= 1
	_pvp_cool = 1.25
	_pvp_idle = 0.0

	var dir: int = {"L": AttackDef.Dir.LEFT, "R": AttackDef.Dir.RIGHT, "D": AttackDef.Dir.OVER, "U": AttackDef.Dir.THRUST} [letter]
	Online.send_to(d.pvp.id, {"k": "atk", "dir": dir, "dmg": d.slash_damage * (2.6 if dir == AttackDef.Dir.OVER else 2.0)})
	d.p_state = Duel.PState.SWING
	d.p_timer = 0.5
	d.player.play(&"slash", {"L": -1, "R": 1, "U": 2, "D": 3} [letter] as int, 0.35)
	d.sfx.play("whoosh", -6.0)


func _pvp_report(outcome: String, riposte := 0.0) -> void:
	if d.pvp.is_empty():
		return
	Online.send_to(d.pvp.id, {"k": "res", "o": outcome, "hp": maxf(d.p_hp, 0.0), "rip": riposte})


func _pvp_message(from: String, m: Dictionary) -> void:
	if from != String(d.pvp.id) or d.result != "":
		return
	_pvp_quiet = 0.0
	if m.has("hp"):
		d.e_hp = clampf(float(m.hp), 0.0, d.def.max_hp)
	match String(m.get("k", "")):
		"atk":
			if d.e_state == Duel.EState.INTRO:
				d.e_state = Duel.EState.IDLE
			d.pvp_turn = "defend"
			_pvp_wait = 0.0
			_pvp_turn_due = false
			d.cur_attack = AttackDef.make(int(m.dir), 0.9, float(m.dmg))
			d.combo = [d.cur_attack]
			d.combo_i = 0
			d.ai._begin_attack()
		"res":
			var at := d.enemy.get_clash_point() + Vector3(randf_range(-0.3, 0.3), 0.4, 0)
			match String(m.o):
				"hit":
					d.enemy.play(&"hit", [-1, 1].pick_random(), 0.12)
					d.enemy.flash(Color(1.0, 0.9, 0.7))
					d.sfx.play("hit")
					d.fx._burst(d.enemy.get_clash_point(), 10)
					d.hud.float_text("HIT", at, Color(1.0, 0.9, 0.5), true)
					d.fx._hitstop(0.05)
					d.stats.sword_dmg += 12.0
				"dodged": d.hud.float_text("DODGED", at, Color(0.7, 0.85, 1.0))
				"blocked":
					d.sfx.play("block")
					d.hud.float_text("BLOCKED", at, Color(0.7, 0.8, 1.0))
				"parried":
					d.sfx.play("clang")
					d.fx._burst(d.player.get_clash_point().lerp(d.enemy.get_clash_point(), 0.5), 24)
					d.hud.banner("PARRIED!", Color(1.0, 0.5, 0.4), 0.7)
					d.pvp_turn = "defend"
					d.pvp_left = 0
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
			d.sfx.play("finish", 2.0, 0.0)
			d._shake = 1.2
			d._end("win")
