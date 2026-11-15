extends Node

const Tune := preload("res://scripts/combat_tune.gd")

var d: Duel


func _init(owner_duel: Duel) -> void:
	d = owner_duel


func _ground(world_pos: Vector3) -> float:
	if d.host != null and d.host.has_method("ground_y"):
		return d.host.ground_y(world_pos)
	return d.global_position.y


## Where the hero and the foe stand in the duel's frame, and how far a sidestep
## (duel.gd input_dodge) carries the hero along that frame's x.
const PLAYER_STAND := Vector3(-1.2, 0, 2.0)
const FOE_STAND := Vector3(0, 0, -0.75)
const DODGE_REACH := 1.0


func _place_in_world() -> void:
	var xf := frame_for(d.host, d.player.global_position, d.enemy.global_position)
	xf.origin.y = _ground(xf.origin)
	d.global_transform = xf
	for f in [d.player, d.enemy]:
		_adopt(f)
	_stand(d.player, PLAYER_STAND, 0.0)
	_stand(d.enemy, FOE_STAND, PI)


## The duel's frame (y 0): the midpoint of hero and foe, facing the foe. In the tower (a
## host with _walkable) it is slid and, if that is not enough, turned (both fighters are
## stood afresh, so only the facing changes), the least that works, until the hero's stand
## point, both sidestep ends and the foe's stand point are walkable, so no fighter is drawn
## in a wall. The camera rides in this frame, so its framing is unchanged. Open land and
## standalone duels (no _walkable) are not moved.
static func frame_for(host: Node, hp: Vector3, ep: Vector3) -> Transform3D:
	var dir := ep - hp
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.FORWARD
	var mid := hp.lerp(ep, 0.5)
	mid.y = 0.0
	var xf := Transform3D(Basis.looking_at(dir, Vector3.UP), mid)
	if host == null or not host.has_method("_walkable"):
		return xf
	var best := xf
	var best_cost := INF
	for ir in [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6]:
		var turn := deg_to_rad(15.0 * ir)
		if absf(turn) * 2.0 >= best_cost:
			continue
		var turned := Transform3D(Basis(Vector3.UP, turn) * xf.basis, mid)
		for ix in range(-10, 11):
			for iz in range(-3, 4):
				var shift := Vector3(ix * 0.25, 0, iz * 0.5)
				var cost := shift.length() + absf(turn) * 2.0
				if cost >= best_cost:
					continue
				var t := turned.translated_local(shift)
				var ok := true
				for p in [PLAYER_STAND, PLAYER_STAND + Vector3(DODGE_REACH, 0, 0), PLAYER_STAND - Vector3(DODGE_REACH, 0, 0), FOE_STAND]:
					if not host._walkable(t * p):
						ok = false
						break
				if ok:
					best = t
					best_cost = cost
	return best


func _adopt(f: Node3D) -> void:
	if f.get_parent() != d:
		f.set_meta("duel_parent", f.get_parent())
		f.reparent(d)


func _stand(f: Node3D, local: Vector3, yaw: float, glide := 0.0) -> void:
	if f == d.enemy:
		d.fx._recoil_cancel()
	var world := d.to_global(local)
	local.y = _ground(world) - d.global_position.y
	if glide > 0.0:
		var tw := d.create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(f, "position", local, glide)
		tw.tween_property(f, "rotation:y", yaw, glide)
	else:
		f.position = local
		f.rotation = Vector3(0, yaw, 0)


func _seat(o: Dictionary, glide := 0.0) -> void:
	_adopt(o.node)
	_stand(o.node, Vector3(3.3 * float(o.side), 0, -0.1), PI - 0.75 * float(o.side), glide)
	(o.node as FighterVisual).play(&"idle")


func _release() -> void:
	var all: Array = [d.player, d.enemy]
	for o in d.others:
		all.append(o.node)
	for r in d.slain:
		all.append(r.node)
	for f in all:
		if is_instance_valid(f) and f.has_meta("duel_parent") and f.get_parent() == d:
			var parent: Node = f.get_meta("duel_parent")
			if is_instance_valid(parent):
				f.reparent(parent)
			f.remove_meta("duel_parent")


func switch_target(i: int) -> void:
	if i < 0 or i >= d.others.size() or d.result != "" or d.p_state == Duel.PState.DEAD:
		return
	if d.e_state in [Duel.EState.FINISHER, Duel.EState.DEAD, Duel.EState.INTRO]:
		return
	var next: Dictionary = d.others[i]
	if float(next.tell) > 0.0:
		(next.node as FighterVisual).set_tell(Color.BLACK, 0.1)
	var prev := {"node": d.enemy, "def": d.def, "enc": d._enc, "hp": d.e_hp, "pst": d.e_posture, "enr": d.enraged, "spd": d.e_speed,
		"side": next.side, "timer": 5.0, "tell": 0.0}
	d.others[i] = prev
	d.enemy.set_tell(Color.BLACK, 0.1)
	_seat(prev, 0.45)
	_face(next, 0.45)
	d.hud.banner(d.def.display_name, Color(1.0, 0.8, 0.5), 0.9)


func _face(rec: Dictionary, glide: float) -> void:
	d.enemy = rec.node
	d.def = rec.def
	d._enc = rec.enc
	Run.encounter = d._enc
	d.e_hp = rec.get("hp", d.def.max_hp)
	d.e_posture = rec.get("pst", 0.0)
	if d.e_posture >= d.def.break_max:
		d.e_posture = d.def.break_max * float(Tune.B1.exec_miss_posture)
	d.posture.reset_foe()
	d.fx._cam_release(glide)
	d.enraged = rec.get("enr", false)
	d.e_speed = rec.get("spd", d.def.speed)
	d.burn = 0.0
	d.chill = 0.0
	d.hit_combo = 0
	_stand(d.enemy, Vector3(0, 0, -0.75), PI, glide)
	d.enemy.play(&"idle")
	d.e_state = Duel.EState.IDLE
	d.e_timer = 1.0
	d.open_reason = ""
	d.can_spare = false
