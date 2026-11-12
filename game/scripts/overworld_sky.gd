extends Node

var ow: Overworld
var _rain: CPUParticles3D
var _raining := false
var _weather_t := 40.0
var _env: Environment
var _sky: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _day := 0.3


func _init(owner_world: Overworld) -> void:
	ow = owner_world


func _build_sky() -> void:
	_env = Environment.new()
	_sky = ProceduralSkyMaterial.new()
	_sky.sun_angle_max = 8.0
	var sky := Sky.new()
	sky.sky_material = _sky
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.glow_enabled = not OS.has_feature("web")
	_env.fog_enabled = true
	_env.fog_density = 0.0045
	_env.fog_sky_affect = 0.35
	var we := WorldEnvironment.new()
	we.environment = _env
	ow.add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 45.0
	ow.add_child(_sun)
	_apply_light(1.0)


func _build_rain() -> void:
	_rain = CPUParticles3D.new()
	_rain.amount = 260
	_rain.lifetime = 0.8
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(16, 0.5, 16)
	_rain.direction = Vector3(0.1, -1, 0)
	_rain.spread = 2.0
	_rain.gravity = Vector3.ZERO
	_rain.initial_velocity_min = 22.0
	_rain.initial_velocity_max = 26.0
	var drop := QuadMesh.new()
	drop.size = Vector2(0.02, 0.55)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(0.8, 0.88, 1.0, 0.45)
	drop.material = dm
	_rain.mesh = drop
	_rain.emitting = false
	ow.add_child(_rain)


func _apply_light(k: float) -> void:
	var light := clampf(sin(_day * TAU) * 1.3 + 0.5, 0.0, 1.0)
	_sun.rotation_degrees = Vector3(-25.0 - 40.0 * light, 140.0 + _day * 60.0, 0)
	_sun.light_energy = lerpf(0.25, 1.7, light)
	_sun.light_color = Color(0.6, 0.7, 1.0).lerp(Color(1.0, 0.95, 0.85), light)
	var fog: Color = Land.BIOMES[ow._biome if ow._biome != "" else "village"].fog
	fog = fog * lerpf(0.16, 0.8, light)
	fog.a = 1.0
	_env.fog_light_color = _env.fog_light_color.lerp(fog, k)
	_env.ambient_light_energy = lerpf(0.5, 1.3, light)
	_sky.sky_top_color = Color(0.02, 0.03, 0.08).lerp(Color(0.2, 0.38, 0.7), light)
	_sky.sky_horizon_color = _env.fog_light_color
	_sky.ground_horizon_color = _env.fog_light_color
	_sky.ground_bottom_color = _env.fog_light_color.darkened(0.5)


func _tick_weather(delta: float) -> void:
	_weather_t -= delta
	if _weather_t <= 0.0:
		_raining = not _raining and randf() < 0.45
		_weather_t = randf_range(50.0, 90.0) if _raining else randf_range(90.0, 200.0)
		_rain.emitting = _raining
		if _raining:
			ow.hud.announce("Rain")
	_rain.position = ow.hero_pos + Vector3(0, 14, 0)
	_env.fog_density = lerpf(_env.fog_density, 0.012 if _raining else 0.0045, clampf(delta * 0.5, 0.0, 1.0))
