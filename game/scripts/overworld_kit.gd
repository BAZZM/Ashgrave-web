extends RefCounted

static var _meshes := {}
static var _mats := {}


static func mat(key: String, color: Color, rough := 0.9, glow := 0.0, tinted := false) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = rough
		m.vertex_color_use_as_albedo = tinted
		if glow > 0.0:
			m.emission_enabled = true
			m.emission = color
			m.emission_energy_multiplier = glow
		_mats[key] = m
	return _mats[key]


## Material for meshes whose colours are baked into their vertices (`MeshKit.merge`).
static func baked_mat() -> StandardMaterial3D:
	if not _mats.has("baked"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color.WHITE
		m.roughness = 0.9
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		_mats["baked"] = m
	return _mats["baked"]


const ORE_COLORS := {"copper": Color(0.9, 0.5, 0.25), "iron": Color(0.6, 0.68, 0.8), "ember": Color(1.0, 0.3, 0.08)}


static func ore_mat(node_id: String) -> StandardMaterial3D:
	return mat("ore_" + node_id, ORE_COLORS[node_id], 0.3, 3.0 if node_id == "ember" else 0.6)


static func mesh(key: String) -> Mesh:
	if _meshes.has(key):
		return _meshes[key]
	var keep := MeshKit.keep_arrays
	MeshKit.keep_arrays = true
	var m: Mesh
	match key:
		"trunk": m = MeshKit.lathe([[0.34, 0.0], [0.23, 0.4], [0.18, 2.2], [0.1, 3.0], [0.0, 3.1]], 7)
		"oak": m = MeshKit.lathe([[0.0, 1.8], [1.5, 2.3], [2.0, 3.4], [1.6, 4.6], [0.7, 5.3], [0.0, 5.5]], 8)
		"pine": m = MeshKit.lathe([[0.0, 1.3], [1.6, 1.5], [0.9, 3.0], [1.2, 3.1], [0.55, 4.7], [0.75, 4.8], [0.0, 6.6]], 7)
		"dead": m = MeshKit.lathe([[0.32, 0.0], [0.2, 1.0], [0.15, 3.0], [0.2, 3.3], [0.05, 4.8], [0.0, 4.9]], 6)
		"stump": m = MeshKit.lathe([[0.36, 0.0], [0.3, 0.5], [0.0, 0.52]], 7)
		"rock": m = MeshKit.lathe([[0.0, 0.0], [1.0, 0.05], [0.92, 0.6], [0.5, 1.1], [0.0, 1.25]], 6)
		"ore": m = MeshKit.lathe([[0.0, 0.0], [0.2, 0.15], [0.0, 0.42]], 4)
		"reed": m = MeshKit.lathe([[0.05, 0.0], [0.035, 1.3], [0.07, 1.45], [0.0, 1.7]], 4)
		"herb": m = MeshKit.lathe([[0.0, 0.0], [0.05, 0.05], [0.03, 0.34], [0.17, 0.42], [0.0, 0.5]], 6)
		"roof": m = MeshKit.lathe([[5.6, 0.0], [0.0, 2.9]], 4)
		"wall":
			var b := BoxMesh.new()
			b.size = Vector3(3.2, 3.0, 0.9)
			m = b
		"house":
			var h := BoxMesh.new()
			h.size = Vector3(7.0, 3.2, 6.0)
			m = h
		# A gatherable tree: trunk and crown in one surface with baked colours.
		"node_oak", "node_pine":
			var pine := key == "node_pine"
			m = MeshKit.merge([[
				[mesh("trunk"), Transform3D.IDENTITY, Color(0.3, 0.2, 0.12)],
				[mesh("pine" if pine else "oak"), Transform3D.IDENTITY, Color(0.1, 0.3, 0.2) if pine else Color(0.3, 0.5, 0.14)]]], true)
		# A gatherable rock: the rock (surface 0) and its five ore crystals (surface 1).
		"node_copper", "node_iron", "node_ember":
			var ores: Array = []
			for i in 5:
				var a := TAU * i / 5.0
				var rot := Vector3(deg_to_rad(30.0 * cos(a)), 0, deg_to_rad(30.0 * sin(a)))
				ores.append([mesh("ore"), Transform3D(Basis.from_euler(rot).scaled(Vector3.ONE * 1.3), Vector3(cos(a) * 0.7, 0.5 + (i % 2) * 0.35, sin(a) * 0.7)), Color.WHITE])
			var rock_part := [mesh("rock"), Transform3D(Basis.from_scale(Vector3(1.1, 1.2, 1.1)), Vector3.ZERO), Color.WHITE]
			var rm := MeshKit.merge([[rock_part], ores])
			rm.surface_set_material(0, mat("stone_solo", Color(0.4, 0.38, 0.36)))
			rm.surface_set_material(1, ore_mat(key.trim_prefix("node_")))
			m = rm
		# A herb plant: three sprigs.
		"node_herb":
			var sprigs: Array = []
			for i in 3:
				sprigs.append([mesh("herb"), Transform3D(Basis.from_scale(Vector3.ONE * 1.5), Vector3(cos(i * 2.1) * 0.25, 0, sin(i * 2.1) * 0.25)), Color.WHITE])
			m = MeshKit.merge([sprigs])
		"beast_deer", "beast_boar":
			m = _beast_mesh(key == "beast_deer")
		"ripple":
			var t := TorusMesh.new()
			t.inner_radius = 0.7
			t.outer_radius = 0.85
			m = t
	MeshKit.keep_arrays = keep
	_meshes[key] = m
	return m


## A deer or boar in one mesh: hide (surface 0) and, for the deer, antlers (surface 1).
static func _beast_mesh(deer: bool) -> ArrayMesh:
	var h := 0.85 if deer else 0.55
	var id := Transform3D.IDENTITY
	var body: Array = [[MeshKit.tube(PackedVector3Array([Vector3(0, h, 0.65), Vector3(0, h + 0.05, 0.35), Vector3(0, h + 0.05, -0.3), Vector3(0, h, -0.6)]),
		PackedFloat32Array([0.1, 0.27, 0.29, 0.15]) if deer else PackedFloat32Array([0.14, 0.32, 0.36, 0.2]), 8), id, Color.WHITE]]
	for sx in [-1.0, 1.0]:
		for sz in [-0.42, 0.45]:
			body.append([MeshKit.lathe([[0.03, 0.0], [0.05, h * 0.5], [0.07, h]], 5), Transform3D(Basis.IDENTITY, Vector3(0.15 * sx, 0, sz)), Color.WHITE])
	var head_at := Vector3(0, h + (0.55 if deer else 0.1), -0.85)
	body.append([MeshKit.tube(PackedVector3Array([Vector3(0, h, -0.5), head_at]), PackedFloat32Array([0.14, 0.09]), 6), id, Color.WHITE])
	body.append([MeshKit.tube(PackedVector3Array([head_at + Vector3(0, 0.02, 0.1), head_at + Vector3(0, 0, -0.1), head_at + Vector3(0, -0.06, -0.32)]),
		PackedFloat32Array([0.09, 0.11, 0.05]), 6), id, Color.WHITE])
	var groups: Array = [body]
	if deer:
		var antlers: Array = []
		for sx in [-1.0, 1.0]:
			antlers.append([MeshKit.horn(Vector3.ZERO, Vector3(0.28 * sx, 0.5, 0.05), Vector3(0.1 * sx, 0, 0.12), 0.025, 5),
				Transform3D(Basis.IDENTITY, head_at + Vector3(0.06 * sx, 0.08, 0.05)), Color.WHITE])
		groups.append(antlers)
	var m := MeshKit.merge(groups)
	var kind := "deer" if deer else "boar"
	m.surface_set_material(0, mat("hide_" + kind, Color(0.5, 0.36, 0.22) if deer else Color(0.24, 0.2, 0.18)))
	if deer:
		m.surface_set_material(1, mat("antler", Color(0.8, 0.75, 0.62)))
	return m


static func _part(parent: Node3D, m: Mesh, pos: Vector3, material: Material, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	mi.material_override = material
	parent.add_child(mi)
	return mi
