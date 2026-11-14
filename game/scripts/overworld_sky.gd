extends Node

## Art Bible section 4 (G1): the sky is always overcast, so there is no blue noon. Each table below is
## [night, dusk, day]; `light` (0 to 1, from the time of day) runs night -> dusk at DUSK_AT -> day.
const DUSK_AT := 0.35
const SUN_ENERGY := [0.15, 0.3, 0.32]
const SUN_PITCH := [-25.0, -12.0, -50.0]  # degrees; the day key stands at 50 degrees at most
const SUN_NIGHT := Color("#99B2FF")
const SUN_DUSK := Color("#FF9A5A")  # the day key is the region's own colour (Land.BIOMES key)
const AMB_ENERGY := [0.3, 0.4, 0.75]
const AMB_NIGHT := Color("#3A4064")
const AMB_DUSK := Color("#5A5F86")  # the day ambient is the region's own colour (Land.BIOMES amb)
const FOG_MULT := [0.16, 0.5, 0.8]  # region fog colour times this
const FOG_DENSITY := 0.006
const FOG_SKY_AFFECT := 0.7
const SKY_TOP := [Color(0.02, 0.03, 0.08), Color("#3A3550"), Color("#56637A")]
## Rain: sun x 0.6, fog denser and half way to a wet grey, sky greyer, colour drained.
const RAIN_SUN := 0.6
const RAIN_FOG_DENSITY := 0.018
const RAIN_FOG_SKY_AFFECT := 0.9
const RAIN_FOG_TO := Color("#59646B")
const RAIN_SKY_TOP := Color("#3E454D")
const RAIN_DROPS := 200
## Region blend: how fast fog, key and ambient colour follow the biome the hero stands in
## (a fraction of the frame's blend step; 0.5 is about a 2.5 s time constant).
const REGION_BLEND := 0.5
## Colour grade (bible 4, `adjustment_*`): NOT applied. Measured in the Golden Shots it adds a 2.3 MB
## render buffer (texture memory 4.3 -> 6.6 MB, video memory +2.3 MB) in every scene. The palette
## is already drained instead (bible fallback: palette S x 0.9), and rain greys through fog and sky.
## Ashlands ground haze (bible 4, fog_height 6 m, fog_height_density 0.08): NOT applied. Tried in the
## Ashlands shot: no visible change under the region's already heavy fog colour.

var ow: Overworld
var _rain: CPUParticles3D
var _raining := false
var _weather_t := 40.0
var _env: Environment
var _sky: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _day := 0.3
var _wet := 0.0
var _r_fog := Color("#8A8F88")
var _r_key := Color("#FFE2B8")
var _r_amb := Color("#8795A8")
var _r_ak := 1.0


func _init(owner_world: Overworld) -> void:
	ow = owner_world


func _build_sky() -> void:
	_env = Environment.new()
	_sky = ProceduralSkyMaterial.new()
	_sky.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = _sky
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.glow_enabled = not OS.has_feature("web")
	_env.fog_enabled = true
	_env.fog_density = FOG_DENSITY
	_env.fog_sky_affect = FOG_SKY_AFFECT
	var we := WorldEnvironment.new()
	we.environment = _env
	ow.add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.shadow_normal_bias = 3.0
	_sun.directional_shadow_max_distance = 32.0
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	ow.add_child(_sun)
	_apply_light(1.0)


func _build_rain() -> void:
	_rain = CPUParticles3D.new()
	_rain.amount = RAIN_DROPS
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


## Night, dusk, day: the table value at `light`.
func _key(t: Array, light: float) -> Variant:
	if light < DUSK_AT:
		return lerp(t[0], t[1], light / DUSK_AT)
	return lerp(t[1], t[2], (light - DUSK_AT) / (1.0 - DUSK_AT))


func _apply_light(k: float) -> void:
	var light := clampf(sin(_day * TAU) * 1.3 + 0.5, 0.0, 1.0)
	var bio: Dictionary = Land.BIOMES[ow._biome if ow._biome != "" else "village"]
	var kr := 1.0 if k >= 1.0 else k * REGION_BLEND
	_r_fog = _r_fog.lerp(bio.fog, kr)
	_r_key = _r_key.lerp(bio.key, kr)
	_r_amb = _r_amb.lerp(bio.amb, kr)
	_r_ak = lerpf(_r_ak, float(bio.get("amb_k", 1.0)), kr)
	var day_w := clampf((light - DUSK_AT) / (1.0 - DUSK_AT), 0.0, 1.0)
	var night_w := clampf(1.0 - light / DUSK_AT, 0.0, 1.0)
	_sun.rotation_degrees = Vector3(_key(SUN_PITCH, light), 140.0 + _day * 60.0, 0)
	_sun.light_energy = _key(SUN_ENERGY, light) * lerpf(1.0, RAIN_SUN, _wet)
	var low: Color = SUN_NIGHT.lerp(SUN_DUSK, 1.0 - night_w)
	_sun.light_color = SUN_DUSK.lerp(_r_key, day_w) if light >= DUSK_AT else low
	var amb_low: Color = AMB_NIGHT.lerp(AMB_DUSK, 1.0 - night_w)
	_env.ambient_light_color = AMB_DUSK.lerp(_r_amb, day_w) if light >= DUSK_AT else amb_low
	_env.ambient_light_energy = _key(AMB_ENERGY, light) * lerpf(1.0, _r_ak, day_w)
	var mult: float = _key(FOG_MULT, light)
	var fog: Color = _r_fog * mult
	fog = fog.lerp(RAIN_FOG_TO * (mult / FOG_MULT[2]), 0.5 * _wet)
	fog.a = 1.0
	_env.fog_light_color = fog
	_env.fog_density = lerpf(FOG_DENSITY, RAIN_FOG_DENSITY, _wet)
	_env.fog_sky_affect = lerpf(FOG_SKY_AFFECT, RAIN_FOG_SKY_AFFECT, _wet)
	var sky_top: Color = _key(SKY_TOP, light)
	sky_top = sky_top.lerp(_r_fog * 0.9, 0.35 * day_w)  # the sky takes a little of the region fog: Hearthvale warm
	_sky.sky_top_color = sky_top.lerp(RAIN_SKY_TOP, _wet * clampf(light * 2.0, 0.0, 1.0))
	_sky.sky_horizon_color = fog
	_sky.ground_horizon_color = fog
	_sky.ground_bottom_color = fog.darkened(0.5)


func _tick_weather(delta: float) -> void:
	_weather_t -= delta
	if _weather_t <= 0.0:
		_raining = not _raining and randf() < 0.45
		_weather_t = randf_range(50.0, 90.0) if _raining else randf_range(90.0, 200.0)
		_rain.emitting = _raining
		if _raining:
			ow.hud.announce("Rain")
	_rain.position = ow.hero_pos + Vector3(0, 14, 0)
	# One smooth 0..1 value drives every rain change in _apply_light (fog, sun, sky), so rain fades in and out.
	_wet = lerpf(_wet, 1.0 if _raining else 0.0, clampf(delta * 0.5, 0.0, 1.0))
