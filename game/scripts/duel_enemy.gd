extends Node

const Tune := preload("res://scripts/combat_tune.gd")

var d: Duel
var _feinted := false


func _init(owner_duel: Duel) -> void:
	d = owner_duel


func _tick_others(delta: float) -> void:
	for o in d.others:
		var node: FighterVisual = o.node
		if float(o.tell) > 0.0:
			o.tell = float(o.tell) - delta
			if float(o.tell) <= 0.0:
				_side_strike(o)
			continue
		o.timer = float(o.timer) - delta
		if float(o.timer) > 0.0:
			continue
		if d.e_state == Duel.EState.WINDUP or d.e_state in [Duel.EState.INTRO, Duel.EState.FINISHER, Duel.EState.DEAD] \
				or (d.e_state == Duel.EState.OPEN and d.open_reason == "posture"):
			o.timer = 0.6
			continue
		o.tell = 1.25
		node.play(&"windup", AttackDef.Dir.THRUST, 1.25)
		node.set_tell(Color(1.0, 0.15, 0.1), 0.6)
		d.sfx.play("tell", -8.0, 0.02)


func _side_strike(o: Dictionary) -> void:
	var node: FighterVisual = o.node
	node.play(&"strike", AttackDef.Dir.THRUST, 0.1)
	node.set_tell(Color.BLACK, 0.2)
	o.timer = randf_range(3.5, 5.0) if (o.def as EnemyDef).ranged else randf_range(6.0, 9.0)
	d.get_tree().create_timer(0.45).timeout.connect(func():
		if is_instance_valid(node) and d.others.has(o):
			node.play(&"idle"))
	d.sfx.play("whoosh", -6.0)
	var dmg: float = (o.def as EnemyDef).side_damage
	if d.p_state == Duel.PState.DODGE and d.dodge_elapsed <= Duel.DODGE_IFRAME:
		d.stats.dodges += 1
		return
	if d.blocking and d.p_state == Duel.PState.READY:
		d.stats.blocks += 1
		d.sfx.layer("L6")
		d.posture.p_block(dmg)
		if d.shield <= 0.0:
			d.blocking = false
			d.posture.p_check_break(true)
			d._hurt(dmg * 0.6, AttackDef.Dir.THRUST)
			d.posture.p_check_break()
		return
	d._hurt(dmg, AttackDef.Dir.RIGHT if float(o.side) > 0.0 else AttackDef.Dir.LEFT)


func _tick_enemy(delta: float) -> void:
	if not d.pvp.is_empty():
		var was_intro := d.e_state == Duel.EState.INTRO
		d.pvp_net._pvp_tick(delta)
		if was_intro or d.e_state == Duel.EState.IDLE:
			return
	d.chill = maxf(d.chill - delta, 0.0)
	if d.burn > 0.0 and d.e_state not in [Duel.EState.FINISHER, Duel.EState.DEAD, Duel.EState.INTRO]:
		d.burn -= delta
		d._burn_tick -= delta
		if d._burn_tick <= 0.0:
			d._burn_tick = 0.5
			var bd := d.slash_damage * 0.3 * d._element_mult()
			d.hud.float_text(str(int(ceil(bd))), d.enemy.get_clash_point() + Vector3(randf_range(-0.3, 0.3), 0.6, 0), Items.ELEMENT_COLORS.ember)
			d._damage_enemy(bd)
			if d.e_state == Duel.EState.FINISHER:
				return
	match d.e_state:
		Duel.EState.INTRO:
			d.e_timer -= delta
			if d.e_timer <= 0.0:
				_to_idle(0.6)
		Duel.EState.IDLE:
			d.e_timer -= delta
			if d.e_timer <= 0.0:
				_pick_combo()
				_begin_attack()
		Duel.EState.WINDUP:
			if d._feint_hold > 0.0:
				d._feint_hold -= delta
				return
			d.e_timer -= delta
			if d.cur_attack.feint and not _feinted and d.e_timer <= d.windup_total * 0.45:
				_feinted = true
				d._feint_hold = 0.42 / d.e_speed
				d.enemy.play(&"feint", 0, d._feint_hold)
				return
			if d.tutorial and d.combo.size() == 1 and not d._tutorial_slowed and d.e_timer <= d.parry_window * 0.85:
				d._tutorial_slowed = true
				d.fx._slow(0.07, 4.0)
			if d.e_timer <= 0.0:
				_resolve_strike()
		Duel.EState.RECOVER:
			d.e_timer -= delta
			if d.e_timer <= 0.0 and not d.pvp.is_empty():
				d.e_state = Duel.EState.IDLE
				d.enemy.play(&"idle")
			elif d.e_timer <= 0.0:
				d.combo_i += 1
				if d.combo_i < d.combo.size():
					_begin_attack()
				else:
					_open(d.def.winded_time / d.e_speed, "winded")
		Duel.EState.OPEN:
			d.e_timer -= delta
			if d.e_timer <= 0.0:
				if d.open_reason == "posture":
					d.posture.execution_missed()
				d.hit_combo = 0
				_to_idle(d.def.idle_gap / d.e_speed)
		Duel.EState.FINISHER:
			d.e_timer -= delta / maxf(Engine.time_scale, 0.05)
			if d.e_timer <= 0.0:
				d._finish()


func _pick_combo() -> void:
	d.combo_i = 0
	if not d._tutorial_queue.is_empty():
		var dd: int = d._tutorial_queue.pop_front()
		d.combo = [AttackDef.make(dd, 1.5, 10.0)]
		d.tutorial_hint = "dodge" if dd == AttackDef.Dir.THRUST else "parry"
		return
	if d.tutorial:
		d.tutorial = false
		d.tutorial_hint = ""
		Run.data.tutorial_done = true
		Run.save()
	var pool: Array = d.def.combos.duplicate()
	if d.enraged:
		pool.append_array(d.def.enraged_combos)
	d.combo = pool.pick_random()


func _to_idle(gap: float) -> void:
	d.e_state = Duel.EState.IDLE
	d.e_timer = gap
	d.open_reason = ""
	if d.tutorial_hint == "strike" or d.tutorial_hint == "execute":
		d.tutorial_hint = ""
	d.enemy.play(&"idle")


func _begin_attack() -> void:
	d.cur_attack = d.combo[d.combo_i]
	d.e_state = Duel.EState.WINDUP
	d.e_timer = d.cur_attack.windup / (d.e_speed * (0.8 if d.chill > 0.0 else 1.0))
	d.windup_total = d.e_timer
	_feinted = false
	d._feint_hold = 0.0
	d._tutorial_slowed = false
	d.enemy.play(&"windup", d.cur_attack.dir, d.e_timer)
	d.enemy.set_tell(d.tell_color(), d.e_timer * 0.6)
	d.sfx.play("tell", -14.0, 0.02)


func _open(duration: float, reason: String) -> void:
	# A foe whose posture is broken stays open for the execution; nothing shortens that.
	if d.e_state == Duel.EState.OPEN and d.open_reason == "posture" and reason != "posture":
		return
	d.e_state = Duel.EState.OPEN
	d.e_timer = duration
	d.open_reason = reason
	d.slash_seq.clear()
	d.enemy.set_tell(Color.BLACK, 0.1)
	d.enemy.play(&"broken" if reason in ["broken", "posture"] else &"stagger")
	if d.tutorial and reason != "posture":
		d.tutorial_hint = "strike"
		d.e_timer = maxf(duration, 2.6)


func _dodge_avoids(dir: int) -> bool:
	if d.p_state != Duel.PState.DODGE or d.dodge_elapsed > Duel.DODGE_IFRAME:
		return false
	match dir:
		AttackDef.Dir.LEFT: return d.dodge_dir > 0
		AttackDef.Dir.RIGHT: return d.dodge_dir < 0
	return true


func _resolve_strike() -> void:
	var a := d.cur_attack
	d.enemy.play(&"strike", a.dir, 0.1)
	d.e_state = Duel.EState.RECOVER
	d.e_timer = 0.35 / d.e_speed
	if d._tutorial_slowed:
		d.fx._restore_time()
	d.sfx.play("whoosh", -6.0)
	if _dodge_avoids(a.dir):
		d.pvp_net._pvp_report("dodged")
		d.stats.dodges += 1
		if d.dodge_elapsed <= Duel.PERFECT_DODGE:
			d._add_surge(10.0)
			d.posture.e_gain(float(Tune.B1.gain_perfect_dodge))
			d.dodge_charges = minf(d.dodge_charges + 1.0, d.dodge_max)
			d.hud.banner("PERFECT DODGE", Color(0.6, 0.9, 1.0), 0.6)
			d.fx._slow(0.35, 0.18)
			if Run.set_bonus("duelist"):
				var rd := d.slash_damage * 2.0
				d.hud.float_text("RIPOSTE %d" % int(rd), d.enemy.get_clash_point(), Color(0.4, 0.9, 0.8), true)
				d.e_hp = maxf(d.e_hp - rd, 1.0)
		return
	if d.blocking and d.p_state == Duel.PState.READY:
		d.stats.blocks += 1
		d.pvp_net._pvp_report.call_deferred("blocked")
		d._shake = maxf(d._shake, float(Tune.B1.block_shake))
		d.sfx.layer("L6")
		d.fx._burst(d.player.get_clash_point() + Vector3(0, 0, -0.5), 10)
		d.fx._buzz(25)
		if a.heavy:
			d.posture.p_block(a.damage)
			d.hud.banner("GUARD CRUSHED", Color(0.8, 0.45, 1.0), 0.8)
			d._hurt(a.damage, a.dir)
			d.posture.p_check_break()
		elif d.stats.time - d._block_time <= d.perfect_block:
			d._add_surge(8.0)
			d.posture.e_gain(float(Tune.B1.gain_perfect_block))
			d.hud.banner("PERFECT BLOCK", Color(0.6, 0.8, 1.0), 0.6)
		else:
			d.posture.p_block(a.damage)
			if d.shield <= 0.0:
				d.blocking = false
				d.posture.p_check_break(true)
				d._hurt(a.damage * 0.6, a.dir)
				d.posture.p_check_break()
		return
	d._hurt(a.damage, a.dir)
	d.pvp_net._pvp_report("hit")
