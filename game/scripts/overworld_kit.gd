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


static func mesh(key: String) -> Mesh:
	if _meshes.has(key):
		return _meshes[key]
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
		"ripple":
			var t := TorusMesh.new()
			t.inner_radius = 0.7
			t.outer_radius = 0.85
			m = t
	_meshes[key] = m
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
