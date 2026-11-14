extends Node3D

## Art Bible section 4, Duel column (G1). Tower arenas use the tier theme; the outdoor arena uses the
## region's own colours under the same overcast sky as the land.
const MOON_ENERGY := 0.25
const MOON_ENERGY_OUTDOOR := 0.5
const AMBIENT_ENERGY := 0.45
const FOG_DENSITY := 0.045
const SHADOW_DISTANCE := 16.0
const FILL_ENERGY := 2.0
const RIM_ENERGY := 4.0
const RIM_COOL := Color(0.55, 0.7, 1.0)  # behind the enemy, opposite the key: cool against a warm key
const RIM_WARM := Color(1.0, 0.7, 0.45)  # ... and warm against a cool key
const OUTDOOR_SKY_TOP := Color("#56637A")
const OUTDOOR_FOG_MULT := 0.8
const TORCH_ENERGY := 2.2

var _torches: Array[OmniLight3D] = []
var _t := 0.0


func _ready() -> void:
	var env := Environment.new()

	Run.ensure_loaded()
	var th: Dictionary = Tiers.THEMES[int(Run.data.floor)]
	var outdoor: bool = Run.encounter.has("wild")
	if outdoor:
		var bio: Dictionary = Land.BIOMES[Run.encounter.get("biome", "meadow")]
		var fog_c: Color = (bio.fog as Color) * OUTDOOR_FOG_MULT
		fog_c.a = 1.0
		th = {"sky_top": OUTDOOR_SKY_TOP, "sky_low": fog_c, "fog": fog_c, "amb": bio.amb,
			"stone": (bio.ground as Color), "light": Color(1.0, 0.75, 0.45), "key": bio.key}
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = th.sky_top
	sky_mat.sky_horizon_color = th.sky_low
	sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.03)
	sky_mat.ground_horizon_color = Color(0.25, 0.14, 0.1)
	sky_mat.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	Run.quality_tune_sky(sky)
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = th.amb
	env.ambient_light_energy = AMBIENT_ENERGY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = not OS.has_feature("web")
	env.glow_intensity = 0.9
	env.glow_bloom = 0.15
	env.fog_enabled = true
	env.fog_light_color = th.fog
	env.fog_density = FOG_DENSITY
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-48, 150, 0)
	moon.light_color = Color(0.7, 0.78, 1.0)
	moon.light_energy = MOON_ENERGY_OUTDOOR if outdoor else MOON_ENERGY
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = SHADOW_DISTANCE
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	Run.quality_tune_light(moon)
	add_child(moon)

	var fill := OmniLight3D.new()
	fill.position = Vector3(0.5, 3.6, 2.2)
	fill.light_color = Color(1.0, 0.8, 0.65)
	fill.light_energy = FILL_ENERGY
	fill.omni_range = 9.0
	add_child(fill)

	var rim := OmniLight3D.new()
	rim.position = Vector3(-1.5, 4.0, -4.5)
	var key_c: Color = th.get("key", th.light)
	rim.light_color = RIM_COOL if key_c.r >= key_c.b else RIM_WARM
	rim.light_energy = RIM_ENERGY
	rim.omni_range = 10.0
	add_child(rim)

	var stone := StandardMaterial3D.new()
	stone.albedo_color = th.stone
	stone.roughness = 0.9
	var dark := StandardMaterial3D.new()
	dark.albedo_color = (th.stone as Color).darkened(0.45)
	dark.roughness = 1.0

	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = 9.0
	floor_mesh.bottom_radius = 9.0
	floor_mesh.height = 0.4
	floor_mesh.radial_segments = 48
	_mesh(floor_mesh, Vector3(0, -0.2, 0), stone)
	var inlay := CylinderMesh.new()
	inlay.top_radius = 3.2
	inlay.bottom_radius = 3.2
	inlay.height = 0.02
	inlay.radial_segments = 48
	_mesh(inlay, Vector3(0, 0.01, 0), dark)

	var ember := StandardMaterial3D.new()
	ember.albedo_color = th.light
	ember.emission_enabled = true
	ember.emission = th.light
	ember.emission_energy_multiplier = 3.0
	for i in (0 if outdoor else 10):
		var a := TAU * i / 10.0 + 0.3
		var p := Vector3(cos(a) * 7.5, 0, sin(a) * 7.5)
		var pillar := BoxMesh.new()
		pillar.size = Vector3(0.9, 6.0 + (i % 3) * 1.2, 0.9)
		_mesh(pillar, p + Vector3(0, pillar.size.y * 0.5, 0), stone)
		if i % 2 == 0:
			var bowl := SphereMesh.new()
			bowl.radius = 0.18
			bowl.height = 0.3
			var tp := Vector3(cos(a) * 6.6, 2.4, sin(a) * 6.6)
			_mesh(bowl, tp, ember)
			var l := OmniLight3D.new()
			l.position = tp
			l.light_color = th.light
			l.light_energy = TORCH_ENERGY
			l.omni_range = 9.0
			add_child(l)
			_torches.append(l)

	if outdoor:
		for i in 7:
			var a2 := TAU * i / 7.0 + 0.5
			var rock := MeshKit.lathe([[0.0, 0.0], [0.7, 0.05], [0.55, 1.2 + (i % 3) * 0.6], [0.2, 1.9 + (i % 3) * 0.7], [0.0, 2.0 + (i % 3) * 0.7]], 6)
			_mesh(rock, Vector3(cos(a2) * 7.5, 0, sin(a2) * 7.5), dark)
	var embers := CPUParticles3D.new()
	embers.amount = 40
	embers.lifetime = 5.0
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	embers.emission_box_extents = Vector3(6, 0.2, 6)
	embers.direction = Vector3.UP
	embers.spread = 25.0
	embers.gravity = Vector3(0, 0.25, 0)
	embers.initial_velocity_min = 0.2
	embers.initial_velocity_max = 0.6
	var q := QuadMesh.new()
	q.size = Vector2(0.035, 0.035)
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	em.albedo_color = Color(1.0, 0.55, 0.2)
	q.material = em
	embers.mesh = q
	add_child(embers)


func _mesh(mesh: Mesh, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	add_child(mi)


func _process(delta: float) -> void:
	_t += delta
	for i in _torches.size():
		_torches[i].light_energy = TORCH_ENERGY + sin(_t * 9.0 + i * 1.7) * 0.25 + sin(_t * 23.0 + i) * 0.15
