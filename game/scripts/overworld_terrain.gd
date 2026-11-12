extends Node

const Kit := preload("res://scripts/overworld_kit.gd")
const LOAD_R := 2
const TABLES := {
	"meadow": [["tree", 0.07], ["tnode", 0.035], ["rock", 0.02], ["rnode", 0.014], ["herb", 0.05], ["foe", 0.03], ["beast", 0.022]],
	"forest": [["tree", 0.58], ["tnode", 0.1], ["herb", 0.03], ["foe", 0.04], ["rock", 0.02], ["beast", 0.02]],
	"marsh": [["reed", 0.4], ["dead", 0.07], ["herb", 0.09], ["foe", 0.045], ["tnode", 0.02], ["beast", 0.02]],
	"quarry": [["rock", 0.28], ["rnode", 0.13], ["foe", 0.045], ["dead", 0.02]],
	"ruins": [["wall", 0.22], ["rock", 0.08], ["rnode", 0.05], ["herb", 0.04], ["foe", 0.07], ["chest", 0.014], ["dead", 0.05], ["tnode", 0.03]],
	"ashlands": [["dead", 0.14], ["rock", 0.1], ["tnode", 0.05], ["rnode", 0.04], ["herb", 0.035], ["foe", 0.06]],
}

var ow: Overworld
var _queue: Array = []


func _init(owner_world: Overworld) -> void:
	ow = owner_world


func _chunk_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / Land.CHUNK), floori(p.z / Land.CHUNK))


func _update_chunks(build_all := false) -> void:
	var c := _chunk_of(ow.hero_pos)
	for dx in range(-LOAD_R, LOAD_R + 1):
		for dz in range(-LOAD_R, LOAD_R + 1):
			var k := c + Vector2i(dx, dz)
			if not ow._chunks.has(k) and not _queue.has(k):
				_queue.append(k)

	_queue.sort_custom(func(a, b): return (a - c).length_squared() < (b - c).length_squared())
	while not _queue.is_empty():
		var k2: Vector2i = _queue.pop_front()
		if absi(k2.x - c.x) <= LOAD_R + 1 and absi(k2.y - c.y) <= LOAD_R + 1:
			_build_chunk(k2)
			if not build_all:
				break
	var changed := false
	for k3 in ow._chunks.keys():
		if absi(k3.x - c.x) > LOAD_R + 1 or absi(k3.y - c.y) > LOAD_R + 1:
			for e in ow._chunks[k3].ents:
				if e.get("node") != null and e.type == "foe":
					(e.node as Node).queue_free()
			(ow._chunks[k3].root as Node).queue_free()
			ow._chunks.erase(k3)
			changed = true
	if changed or build_all:
		ow._collect_ents()


func _ground_mesh(origin: Vector2) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var n := 10
	var step := Land.CHUNK / n
	for iz in n + 1:
		for ix in n + 1:
			var x := origin.x + ix * step
			var z := origin.y + iz * step
			st.set_color(Land.ground_color(x, z))
			st.add_vertex(Vector3(x, Land.height(x, z), z))
	for iz in n:
		for ix in n:
			var a := iz * (n + 1) + ix
			for idx in [a, a + 1, a + n + 1, a + 1, a + n + 2, a + n + 1]:
				st.add_index(idx)
	st.generate_normals()
	return st.commit()


func _build_chunk(k: Vector2i) -> void:
	var origin := Vector2(k.x * Land.CHUNK, k.y * Land.CHUNK)
	var root := Node3D.new()
	ow.add_child(root)
	var chunk := {"root": root, "ents": [], "obstacles": []}
	ow._chunks[k] = chunk
	var centre := origin + Vector2(Land.CHUNK, Land.CHUNK) * 0.5
	if not Land.in_bounds(clampf(centre.x, -Land.X_MAX - 30, Land.X_MAX + 30), centre.y) and absf(centre.x) > Land.X_MAX + 30:
		return
	Kit._part(root, _ground_mesh(origin), Vector3.ZERO, Kit.mat("ground", Color.WHITE, 0.95, 0.0, true))
	if Land.river_dist(centre.x, centre.y) < 44.0 or Land.lake_dist(centre.x, centre.y) < Land.LAKE_R + 30.0:
		var wm := StandardMaterial3D.new() if not Kit._mats.has("water") else null
		if wm:
			wm.albedo_color = Color(0.12, 0.32, 0.42, 0.72)
			wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			wm.metallic = 0.5
			wm.roughness = 0.08
			Kit._mats["water"] = wm
		var plane := PlaneMesh.new()
		plane.size = Vector2(Land.CHUNK, Land.CHUNK)
		Kit._part(root, plane, Vector3(centre.x, Land.WATER_Y, centre.y), Kit._mats["water"])

	var multi := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(k.x * 7919 + 13, k.y * 104729 + 7))
	var cells := 5
	var cs := Land.CHUNK / cells
	for cz in cells:
		for cx in cells:
			var p := origin + Vector2((cx + rng.randf_range(0.15, 0.85)) * cs, (cz + rng.randf_range(0.15, 0.85)) * cs)
			var roll := rng.randf()
			var spin := rng.randf() * TAU
			var size := rng.randf_range(0.8, 1.3)
			var eid := "%d_%d_%d" % [k.x, k.y, cz * cells + cx]
			if not Land.in_bounds(p.x, p.y):
				continue
			var b := Land.biome(p.x, p.y)
			if b == "village" or Land.road_dist(p.x, p.y) < 3.6 or Land.on_bridge(p.x, p.y):
				continue
			if p.distance_to(Land.TOWER) < 26.0 or p.distance_to(Land.TOWER_GATE) < 12.0:
				continue
			var crowded := false
			for pl in Land.PLACES:
				if p.distance_to(pl.pos) < float(pl.r) + 2.0:
					crowded = true
			if crowded:
				continue

			var bank := minf(Land.river_dist(p.x, p.y) - 5.0, Land.lake_dist(p.x, p.y) - Land.LAKE_R + 3.0)
			if bank < 0.0:
				continue
			if bank < 4.0:
				if roll < 0.3:
					_add_fishing(chunk, eid, p)
				elif roll < 0.6:
					_scatter(multi, "reed", "reed", Color(0.4, 0.5, 0.25), p, spin, size)
				continue
			var acc := 0.0
			for row in TABLES[b]:
				acc += float(row[1])
				if roll < acc:
					_place(chunk, multi, row[0], b, eid, p, spin, size, rng)
					break
	for h in Land.HOUSES:
		if Rect2(origin, Vector2(Land.CHUNK, Land.CHUNK)).has_point(h):
			ow.places._add_house(chunk, h)
	for pl in Land.PLACES:
		if Rect2(origin, Vector2(Land.CHUNK, Land.CHUNK)).has_point(pl.pos):
			ow.places._add_place(chunk, pl)
	if Rect2(origin, Vector2(Land.CHUNK, Land.CHUNK)).has_point(Land.BRIDGE.get_center()):
		var deck := BoxMesh.new()
		deck.size = Vector3(Land.BRIDGE.size.x, 0.4, Land.BRIDGE.size.y)
		Kit._part(root, deck, Vector3(Land.BRIDGE.get_center().x, 0.55, Land.BRIDGE.get_center().y), Kit.mat("wood", Color(0.34, 0.22, 0.12)))
		for side in [-1.0, 1.0]:
			var rail := BoxMesh.new()
			rail.size = Vector3(Land.BRIDGE.size.x, 0.15, 0.15)
			Kit._part(root, rail, Vector3(Land.BRIDGE.get_center().x, 1.6, Land.BRIDGE.get_center().y + side * (Land.BRIDGE.size.y * 0.5 - 0.1)), Kit.mat("wood", Color.WHITE))
	for key in multi:
		var data: Array = multi[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = Kit.mesh(String(key).get_slice("|", 0))
		mm.instance_count = data[0].size()
		for i in data[0].size():
			mm.set_instance_transform(i, data[0][i])
			mm.set_instance_color(i, data[1][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = data[2]
		root.add_child(mmi)
	ow._collect_ents()


func _scatter(multi: Dictionary, mesh_key: String, mat_key: String, tint: Color, p: Vector2, spin: float, size: float, squash := 1.0) -> void:
	var key := mesh_key + "|" + mat_key
	if not multi.has(key):
		multi[key] = [[], [], Kit.mat("mm_" + mat_key, Color.WHITE, 0.9, 0.0, true)]
	var basis := Basis(Vector3.UP, spin).scaled(Vector3(size, size * squash, size))
	multi[key][0].append(Transform3D(basis, Vector3(p.x, Land.height(p.x, p.y) - 0.05, p.y)))
	multi[key][1].append(tint)


func _place(chunk: Dictionary, multi: Dictionary, kind: String, b: String, eid: String, p: Vector2, spin: float, size: float, rng: RandomNumberGenerator) -> void:
	var pos := Vector3(p.x, Land.height(p.x, p.y), p.y)
	match kind:
		"tree":
			var pine := Land.tree_at(p.x, p.y) == "pine"
			_scatter(multi, "trunk", "bark", Color(0.3, 0.2, 0.12), p, spin, size)
			var leaf := Color(0.12, 0.28, 0.16) if pine else Color(0.2, 0.42, 0.16).lerp(Color(0.34, 0.45, 0.14), rng.randf())
			_scatter(multi, "pine" if pine else "oak", "leaf", leaf, p, spin, size)
			chunk.obstacles.append(Vector3(p.x, p.y, 0.55 * size))
		"dead":
			_scatter(multi, "dead", "bark", Color(0.16, 0.13, 0.12) if b != "marsh" else Color(0.25, 0.24, 0.18), p, spin, size)
			chunk.obstacles.append(Vector3(p.x, p.y, 0.5 * size))
		"rock":
			var tint := Color(0.22, 0.19, 0.19) if b in ["ashlands", "ruins"] else Color(0.45, 0.43, 0.4)
			_scatter(multi, "rock", "stone", tint.darkened(rng.randf() * 0.2), p, spin, size * 1.3, rng.randf_range(0.7, 1.6))
			chunk.obstacles.append(Vector3(p.x, p.y, 1.2 * size))
		"reed":
			for i in 4:
				_scatter(multi, "reed", "reed", Color(0.36, 0.44, 0.22), p + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5)), spin, size)
		"wall":
			_scatter(multi, "wall", "stone", Color(0.38, 0.37, 0.36).darkened(rng.randf() * 0.25), p, spin, 1.0, rng.randf_range(0.5, 1.5))
			chunk.obstacles.append(Vector3(p.x, p.y, 1.5))
		"tnode":
			_add_node(chunk, eid, Land.tree_at(p.x, p.y), pos, size)
		"rnode":
			_add_node(chunk, eid, Land.rock_at(p.x, p.y), pos, size)
		"herb":
			_add_node(chunk, eid, Land.herb_at(p.x, p.y), pos, size)
		"foe":
			if Land.BIOMES[b].foe == "":
				return

			if int(Land.FOES[Land.BIOMES[b].foe].level) >= 8 and rng.randf() < 0.3 and Run.respawn_due(eid + "b"):
				var w2 := Land.foe_for(b, rng.randf())
				var f2: Dictionary = Land.FOES[w2]
				var p2 := pos + Vector3(4.0, 0, 1.5)
				p2.y = Land.walk_height(p2.x, p2.z)
				if not Land.is_water(p2.x, p2.z):
					chunk.ents.append({"id": eid + "b", "type": "foe", "kind": "wild", "wild": w2, "biome": b, "pos": p2, "home": p2,
						"label": "%s  Lv %d" % [f2.name, f2.level], "height": 2.2 * float(f2.scale), "node": null})
			var wild := Land.foe_for(b, rng.randf())
			if not Run.respawn_due(eid):
				return
			var f: Dictionary = Land.FOES[wild]
			chunk.ents.append({"id": eid, "type": "foe", "kind": "wild", "wild": wild, "biome": b, "pos": pos, "home": pos,
				"label": "%s  Lv %d" % [f.name, f.level], "height": 2.2 * float(f.scale), "node": null})
		"beast":
			if not Run.respawn_due(eid):
				return
			var bkind: String = Land.BIOMES[b].get("beast", "deer")
			var bn := _build_beast(bkind)
			bn.position = pos
			chunk.root.add_child(bn)
			chunk.ents.append({"id": eid, "type": "beast", "beast": bkind, "pos": pos, "home": pos, "label": bkind.capitalize(), "height": 1.9,
				"node": bn, "goal": pos, "wait": rng.randf_range(1.0, 5.0), "flee": 0.0})
		"chest":
			if Run.data.ow_opened.has(eid):
				return
			var n := Node3D.new()
			n.position = pos
			n.rotation.y = spin
			chunk.root.add_child(n)
			var box := BoxMesh.new()
			box.size = Vector3(1.1, 0.7, 0.7)
			Kit._part(n, box, Vector3(0, 0.35, 0), Kit.mat("wood", Color(0.34, 0.22, 0.12)))
			var band := BoxMesh.new()
			band.size = Vector3(0.14, 0.76, 0.76)
			Kit._part(n, band, Vector3(0, 0.36, 0), Kit.mat("goldtrim", Color(0.9, 0.7, 0.3), 0.3))
			chunk.ents.append({"id": eid, "type": "chest", "pos": pos, "label": "Old chest", "height": 1.5, "node": n, "gold": 60 + rng.randi_range(0, 140)})
			chunk.obstacles.append(Vector3(p.x, p.y, 0.7))


func _add_node(chunk: Dictionary, eid: String, node_id: String, pos: Vector3, size: float) -> void:
	var def: Dictionary = Land.NODES[node_id]
	var n := Node3D.new()
	n.position = pos
	chunk.root.add_child(n)
	var full := Node3D.new()
	var empty := Node3D.new()
	n.add_child(full)
	n.add_child(empty)
	var radius := 0.6
	match def.skill:
		"woodcutting":
			var bark := Kit.mat("bark_solo", Color(0.3, 0.2, 0.12))
			if node_id == "ashwood":
				Kit._part(full, Kit.mesh("dead"), Vector3.ZERO, Kit.mat("ashbark", Color(0.2, 0.12, 0.1)), Vector3.ZERO, Vector3.ONE * size * 1.2)
				Kit._part(full, Kit.mesh("ore"), Vector3(0, 2.2 * size, 0), Kit.mat("ashglow", Color(1.0, 0.4, 0.1), 0.5, 3.0), Vector3.ZERO, Vector3(2, 3, 2))
			else:
				Kit._part(full, Kit.mesh("trunk"), Vector3.ZERO, bark, Vector3.ZERO, Vector3.ONE * size)
				var pine := node_id == "pine"
				Kit._part(full, Kit.mesh("pine" if pine else "oak"), Vector3.ZERO, Kit.mat("leaf_" + node_id, Color(0.1, 0.3, 0.2) if pine else Color(0.3, 0.5, 0.14)), Vector3.ZERO, Vector3.ONE * size)
			Kit._part(empty, Kit.mesh("stump"), Vector3.ZERO, bark)
		"mining":
			radius = 1.1
			var stone := Kit.mat("stone_solo", Color(0.4, 0.38, 0.36))
			Kit._part(full, Kit.mesh("rock"), Vector3.ZERO, stone, Vector3.ZERO, Vector3(1.1, 1.2, 1.1))
			var ore_col: Color = {"copper": Color(0.9, 0.5, 0.25), "iron": Color(0.6, 0.68, 0.8), "ember": Color(1.0, 0.3, 0.08)} [node_id]
			var om := Kit.mat("ore_" + node_id, ore_col, 0.3, 3.0 if node_id == "ember" else 0.6)
			for i in 5:
				var a := TAU * i / 5.0
				Kit._part(full, Kit.mesh("ore"), Vector3(cos(a) * 0.7, 0.5 + (i % 2) * 0.35, sin(a) * 0.7), om, Vector3(30 * cos(a), 0, 30 * sin(a)), Vector3.ONE * 1.3)
			Kit._part(empty, Kit.mesh("rock"), Vector3.ZERO, stone, Vector3.ZERO, Vector3(1.1, 1.2, 1.1))
		"foraging":
			radius = 0.0
			var hc: Color = {"marigold": Color(1.0, 0.8, 0.15), "bogroot": Color(0.6, 0.35, 0.8), "ashbloom": Color(1.0, 0.45, 0.15)} [node_id]
			var hm := Kit.mat("herb_" + node_id, hc, 0.6, 2.5 if node_id == "ashbloom" else 0.4)
			for i in 3:
				Kit._part(full, Kit.mesh("herb"), Vector3(cos(i * 2.1) * 0.25, 0, sin(i * 2.1) * 0.25), hm, Vector3.ZERO, Vector3.ONE * 1.5)
	var e := {"id": eid, "type": "node", "node_id": node_id, "pos": pos, "label": def.label, "height": 1.2 if def.skill == "foraging" else 3.2,
		"node": n, "full": full, "empty": empty, "charges": int(def.charges), "depleted": false}
	if not Run.respawn_due(eid):
		e.depleted = true
	full.visible = not e.depleted
	empty.visible = e.depleted
	chunk.ents.append(e)
	if radius > 0.0:
		chunk.obstacles.append(Vector3(pos.x, pos.z, radius))


func _build_beast(kind: String) -> Node3D:
	var n := Node3D.new()
	var deer := kind == "deer"
	var hide := Kit.mat("hide_" + kind, Color(0.5, 0.36, 0.22) if deer else Color(0.24, 0.2, 0.18))
	var h := 0.85 if deer else 0.55
	Kit._part(n, MeshKit.tube(PackedVector3Array([Vector3(0, h, 0.65), Vector3(0, h + 0.05, 0.35), Vector3(0, h + 0.05, -0.3), Vector3(0, h, -0.6)]),
		PackedFloat32Array([0.1, 0.27, 0.29, 0.15]) if deer else PackedFloat32Array([0.14, 0.32, 0.36, 0.2]), 8), Vector3.ZERO, hide)
	for sx in [-1.0, 1.0]:
		for sz in [-0.42, 0.45]:
			Kit._part(n, MeshKit.lathe([[0.03, 0.0], [0.05, h * 0.5], [0.07, h]], 5), Vector3(0.15 * sx, 0, sz), hide)
	var head_at := Vector3(0, h + (0.55 if deer else 0.1), -0.85)
	Kit._part(n, MeshKit.tube(PackedVector3Array([Vector3(0, h, -0.5), head_at]), PackedFloat32Array([0.14, 0.09]), 6), Vector3.ZERO, hide)
	Kit._part(n, MeshKit.tube(PackedVector3Array([head_at + Vector3(0, 0.02, 0.1), head_at + Vector3(0, 0, -0.1), head_at + Vector3(0, -0.06, -0.32)]),
		PackedFloat32Array([0.09, 0.11, 0.05]), 6), Vector3.ZERO, hide)
	if deer:
		for sx in [-1.0, 1.0]:
			Kit._part(n, MeshKit.horn(Vector3.ZERO, Vector3(0.28 * sx, 0.5, 0.05), Vector3(0.1 * sx, 0, 0.12), 0.025, 5), head_at + Vector3(0.06 * sx, 0.08, 0.05), Kit.mat("antler", Color(0.8, 0.75, 0.62)))
	return n


func _add_fishing(chunk: Dictionary, eid: String, p: Vector2) -> void:
	var to_water := Vector2(Land.river_x(p.y) - p.x, 0).normalized()
	if Land.lake_dist(p.x, p.y) < Land.LAKE_R + 10.0:
		to_water = (Land.LAKE - p).normalized()
	var spot := p + to_water * 5.0
	var n := Node3D.new()
	n.position = Vector3(spot.x, Land.WATER_Y + 0.05, spot.y)
	chunk.root.add_child(n)
	var rm := Kit.mat("ripple", Color(0.75, 0.9, 1.0), 0.3, 1.2)
	Kit._part(n, Kit.mesh("ripple"), Vector3.ZERO, rm)
	Kit._part(n, Kit.mesh("ripple"), Vector3.ZERO, rm, Vector3.ZERO, Vector3(1.8, 1, 1.8))
	var node_id := Land.fish_at(p.x, p.y)
	var pos := Vector3(p.x, Land.walk_height(p.x, p.y), p.y)
	var e := {"id": eid, "type": "node", "node_id": node_id, "pos": pos, "label": Land.NODES[node_id].label, "height": 1.6,
		"node": n, "full": n, "empty": Node3D.new(), "charges": int(Land.NODES[node_id].charges), "depleted": false}
	n.add_child(e.empty)
	if not Run.respawn_due(eid):
		e.depleted = true
		n.visible = false
	chunk.ents.append(e)


func _blocked(p: Vector3) -> bool:
	if not Land.in_bounds(p.x, p.z) or Land.is_water(p.x, p.z):
		return true
	if Vector2(p.x, p.z).distance_to(Land.TOWER) < 17.5:
		return true
	var c := _chunk_of(p)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var ch: Variant = ow._chunks.get(c + Vector2i(dx, dz))
			if ch == null:
				continue
			for o in ch.obstacles:
				if Vector2(p.x - o.x, p.z - o.y).length() < float(o.z) + 0.35:
					return true
	return false
