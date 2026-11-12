extends Node

var ow: Overworld
var _pub_t := 0.0
var _pvp_ask_t := 0.0


func _init(owner_world: Overworld) -> void:
	ow = owner_world


func _publish(delta: float) -> void:
	_pub_t -= delta / maxf(Engine.time_scale, 0.05)
	if _pub_t > 0.0 or not ow.started:
		return
	_pub_t = 0.3 if ow.stick.length() > 0.1 or ow._bot != "" else 1.5
	Online.publish_state(_my_state())


func _tick_remote(delta: float) -> void:
	var changed := false
	for id in Online.players:
		var p: Dictionary = Online.players[id]
		if p.get("tw", false) or not p.has("x"):
			continue
		var target := Vector3(float(p.x), 0, float(p.z))
		target.y = Land.walk_height(target.x, target.z)
		if not ow._remote.has(id):
			if target.distance_to(ow.hero_pos) > 95.0:
				continue
			var v := PlaceholderVisual.new()
			v.has_shield = true
			ow.add_child(v)
			v.position = target
			ow._remote[id] = {"id": id, "type": "player", "pos": target, "node": v, "label": "", "height": 2.4, "eq": ""}
			changed = true
		var e: Dictionary = ow._remote[id]
		var eq_key := JSON.stringify(p.get("eq", {})) + str(p.get("up", 0))
		if e.eq != eq_key and p.get("eq") is Dictionary:
			e.eq = eq_key
			var eq: Dictionary = Items.STARTING.duplicate()
			for slot in eq:
				var item := String((p.eq as Dictionary).get(slot, eq[slot]))
				if item == "" or (Items.exists(item) and Items.slot_of(item) == slot):
					eq[slot] = item
			(e.node as PlaceholderVisual).configure(Items.hero_look(eq, {eq.weapon: int(p.get("up", 0))}))
		e.label = "%s  Lv %d  (%d-%d)" % [String(p.get("n", "?")).left(16), int(p.get("cl", 1)), int(p.get("w", 0)), int(p.get("l", 0))]
		e.busy = p.get("d", false)
		e.zone = p.get("zone", false)
		var node: PlaceholderVisual = e.node
		if node.get_parent() != ow:
			continue
		var gap := Vector3(target.x - e.pos.x, 0, target.z - e.pos.z)
		if gap.length() > 12.0:
			e.pos = target
		elif gap.length() > 0.05:
			e.pos += gap * minf(delta * 7.0, 1.0)
		e.pos.y = Land.walk_height(e.pos.x, e.pos.z)
		node.position = e.pos
		node.rotation.y = lerp_angle(node.rotation.y, float(p.get("yw", 0.0)), minf(delta * 8.0, 1.0))
		node.set_walk(clampf(gap.length() * 1.2, 0.0, 1.0))
		# The eased gap settles near speed / 7, so a runner shows a bigger gap than a walker.
		e.pace = lerpf(float(e.get("pace", 1.0)), clampf(gap.length() * 7.0 / 5.0, 1.0, 2.0), minf(delta * 4.0, 1.0))
		node.set_pace(e.pace)
	for id in ow._remote.keys():
		var gone: bool = not Online.players.has(id) or Online.players[id].get("tw", false)
		if gone or (ow._remote[id].pos as Vector3).distance_to(ow.hero_pos) > 110.0:
			if (ow._remote[id].node as Node).get_parent() == ow:
				(ow._remote[id].node as Node).queue_free()
				ow._remote.erase(id)
				changed = true
	if changed:
		ow._collect_ents()
	if ow._bot == "pvp_a" and ow.duel == null and not ow._remote.is_empty():
		_pvp_ask_t -= delta
		if _pvp_ask_t <= 0.0:
			_pvp_ask_t = 3.0
			ow.duels._challenge(ow._remote.values()[0])


func _my_state() -> Dictionary:
	return {"x": snappedf(ow.hero_pos.x, 0.01), "z": snappedf(ow.hero_pos.z, 0.01), "yw": snappedf(ow.hero_yaw, 0.01),
		"cl": Run.combat_level(), "eq": Run.data.equipped, "up": Run.upgrade_level(Run.data.equipped.weapon),
		"w": Run.data.pvp_w, "l": Run.data.pvp_l, "d": ow.duel != null, "tw": false, "zone": ow.in_zone()}
