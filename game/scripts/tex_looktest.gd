extends Node3D
## Debug look-test scene (lane G2): `--looktest=tex --treatment=flat|grain|source`, optional `--ltcam=NAME`
## (one fixed camera; default runs from `--ltstart=NAME` (first camera if absent), advancing to camera index window.__lt_next)
## and `--ltmem` (print the memory line at every camera). Docs: docs/TEXTURE_LOOK.md.
## Deterministic: fixed sun, no weather, frozen water and banner time, fixed positions, frozen fighters.
## Prints "LOOKTEST ready ..." once textures and chunks are in, then "LOOKTEST cam NN name settled" per camera.
## Only loaded by overworld.gd when the argument is present; the normal game never reaches it.

const TexKit := preload("res://scripts/tex_kit.gd")
const Kit := preload("res://scripts/overworld_kit.gd")
const SkyConst := preload("res://scripts/overworld_sky.gd")

const S := Vector3(2000, 0, 2000)  # the 40 x 30 m stage sits far from the land so the two never overlap
const SETTLE_FRAMES := 14
const FROZEN_TIME := 3.0
const WATER_Y := -0.55
const BRASS := Color("#C9A24B")
const RED := Color("#8C2E26")
const PLASTER := Color("#8A7F68")
const LOAM := Color("#4A3A2A")
const BARK := Color(0.3, 0.2, 0.12)
const OAK_LEAF := Color(0.27, 0.43, 0.15)
const PINE_LEAF := Color(0.12, 0.28, 0.16)
const DEEP := Color("#20343A")
const SHALLOW := Color("#3E6A68")

var treatment := TexKit.FLAT
var only_cam := ""
var start_cam := ""
var _cams: Array = []
var _cam_i := 0
var _frames := 0
var _settled := false
var _mem_all := false
var _cam: Camera3D
var _env: Environment
var _sky: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _groups := {}
var _vistas := {}
var _hero: PlaceholderVisual
var _enemy: PlaceholderVisual
var _hero_flat := {}
var _enemy_flat := {}
var _banner: MeshInstance3D
var _ready_printed := false
var _water_mats: Array = []


func _ready() -> void:
	var tname := "flat"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--treatment="):
			tname = a.trim_prefix("--treatment=")
		elif a.begins_with("--ltcam="):
			only_cam = a.trim_prefix("--ltcam=")
		elif a.begins_with("--ltstart="):
			start_cam = a.trim_prefix("--ltstart=")
		elif a == "--ltmem":
			_mem_all = true
	treatment = TexKit.parse(tname)
	Run.ensure_loaded()
	Run.no_save = true
	Run.title_seen = true
	_build_env()
	_build_stage()
	_build_vista("hearthvale", "village", Vector2(0, 20))
	_build_vista("greywood", "forest", Vector2(-120, 20))
	_build_vista("ashlands", "ashlands", Vector2(0, -165))
	_build_fighters()
	_define_cams()
	_cam = Camera3D.new()
	_cam.far = 260.0
	add_child(_cam)
	_cam.make_current()
	for i in _cams.size():
		if _cams[i].name in [only_cam, start_cam] or _cams[i].id in [only_cam, start_cam]:
			_cam_i = i
	_goto(_cam_i)


# ------------------------------------------------------------------ lighting (overworld_sky.gd _apply_light at day, light = 1)
func _build_env() -> void:
	_env = Environment.new()
	_sky = ProceduralSkyMaterial.new()
	_sky.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = _sky
	Run.quality_tune_sky(sky)
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.fog_enabled = true
	_env.fog_density = SkyConst.FOG_DENSITY
	_env.fog_sky_affect = SkyConst.FOG_SKY_AFFECT
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.shadow_normal_bias = 3.0
	_sun.directional_shadow_max_distance = 32.0
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	Run.quality_tune_light(_sun)
	add_child(_sun)


func _set_region(b: String) -> void:
	var bio: Dictionary = Land.BIOMES[b]
	_sun.rotation_degrees = Vector3(SkyConst.SUN_PITCH[2], 158.0, 0)
	_sun.light_energy = SkyConst.SUN_ENERGY[2]
	_sun.light_color = bio.key
	_env.ambient_light_color = bio.amb
	_env.ambient_light_energy = SkyConst.AMB_ENERGY[2] * float(bio.get("amb_k", 1.0))
	var fog: Color = bio.fog * SkyConst.FOG_MULT[2]
	fog.a = 1.0
	_env.fog_light_color = fog
	_env.fog_density = SkyConst.FOG_DENSITY
	_env.fog_sky_affect = SkyConst.FOG_SKY_AFFECT
	var sky_top: Color = SkyConst.SKY_TOP[2]
	_sky.sky_top_color = sky_top.lerp(bio.fog * 0.9, 0.35)
	_sky.sky_horizon_color = fog
	_sky.ground_horizon_color = fog
	_sky.ground_bottom_color = fog.darkened(0.5)


# ------------------------------------------------------------------ the 40 x 30 m stage
func _gh(x: float, z: float) -> float:
	var h := 0.35 + 0.18 * sin(x * 0.21) * sin(z * 0.17 + 1.0)
	var bank := smoothstep(-3.0, 6.0, x) * smoothstep(-6.0, 0.0, z)
	return lerpf(h, -2.0, bank)


func _noise(x: float, z: float) -> float:
	return 0.5 + 0.5 * sin(x * 0.7 + sin(z * 0.9)) * sin(z * 0.6)


func _stage_f(x: float, z: float) -> Array:
	var vg: Color = Land.BIOMES.village.ground
	var mg: Color = Land.BIOMES.meadow.ground
	var fg: Color = Land.BIOMES.forest.ground
	var wf := smoothstep(14.0, 18.0, x)
	var c := vg.lerp(mg, smoothstep(-2.0, 2.0, x)).lerp(fg, wf)
	c = c.darkened(0.12 * _noise(x, z))
	var zm := smoothstep(-3.0, -1.0, z)
	var edge := 0.25 * sin(z * 0.9 + x * 0.3)
	var wp := zm * smoothstep(-11.5, -10.7, x + edge) * (1.0 - smoothstep(-7.5, -6.0, x + edge))
	var wm := zm * smoothstep(-7.5, -6.0, x + edge)
	var tint := c
	if treatment == TexKit.FLAT:
		tint = c.lerp(Land.ROAD_COLOR, wp).lerp(Land.SHORE_COLOR, wm)
	return [_gh(x, z), tint, wp, wm, wf]


func _pal(b: String) -> Dictionary:
	var fog: Color = Land.BIOMES[b].fog
	return {"path": Land.ROAD_COLOR, "mud": Land.SHORE_COLOR, "fog": fog, "deep": DEEP, "shallow": SHALLOW}


func _group(name: String, parent: Node3D = self) -> Node3D:
	var n := Node3D.new()
	n.name = name
	parent.add_child(n)
	_groups[name] = n
	return n


func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot
	parent.add_child(m)
	return m


func _build_stage() -> void:
	var stage := Node3D.new()
	stage.name = "stage"
	stage.position = S
	add_child(stage)
	_groups["stage"] = stage
	var pal := _pal("village")
	var tm := TexKit.terrain(treatment, pal)
	var ground := _group("ground", stage)
	_mi(ground, TexKit.build_ground(Vector2(-20, -15), Vector2(40, 30), Vector2i(80, 60), _stage_f), tm, Vector3.ZERO)
	# A coarser apron around the stage so its edge is not a cliff into the fog (outside the 40 x 30 m of the test).
	for r in [[Vector2(-100, -75), Vector2(80, 60)], [Vector2(20, -75), Vector2(80, 60)], [Vector2(-20, -75), Vector2(40, 60)],
			[Vector2(-100, 15), Vector2(80, 60)], [Vector2(20, 15), Vector2(80, 60)], [Vector2(-20, 15), Vector2(40, 60)],
			[Vector2(-100, -15), Vector2(80, 30)], [Vector2(20, -15), Vector2(80, 30)]]:
		_mi(ground, TexKit.build_ground(r[0], r[1], Vector2i(int(r[1].x / 2.0), int(r[1].y / 2.0)), _stage_f), tm, Vector3.ZERO)
	var water := _group("water", stage)
	var wmat := TexKit.water(treatment, pal)
	_mi(water, TexKit.build_water(Vector2(-4, -4), 96.0, 96, WATER_Y, func(x: float, z: float) -> float:
		return 1.0 - smoothstep(0.0, 1.6, WATER_Y - _gh(x, z))), wmat, Vector3.ZERO)
	_water_mats.append(wmat)
	if wmat is ShaderMaterial:
		(wmat as ShaderMaterial).set_shader_parameter("time_override", FROZEN_TIME)

	var fog: Color = Land.BIOMES.village.fog
	# Trees: a deciduous and a pine, each with and without cutout cards.
	var trees := _group("trees", stage)
	var cards := _group("cards", stage)
	_tree(trees, cards, Vector3(-8.5, _gh(-8.5, -9.0), -9.0), false, fog, 1.0, 0.7)
	_tree(trees, cards, Vector3(-2.5, _gh(-2.5, -9.0), -9.0), true, fog, 1.0, 2.1)
	# Stone wall with a plank door and a cobble apron.
	var wall := _group("wall", stage)
	var wy := _gh(12.0, -13.0)
	var stone := TexKit.solid("stone", treatment, PLASTER, fog)
	var wm := BoxMesh.new()
	wm.size = Vector3(8.0, 3.0, 0.9)
	_mi(wall, wm, stone, Vector3(12.0, wy + 1.2, -13.0))
	var door := BoxMesh.new()
	door.size = Vector3(1.1, 2.0, 0.1)
	_mi(wall, door, TexKit.solid("planks", treatment, LOAM, fog), Vector3(11.5, wy + 0.95, -12.52))
	var apron := BoxMesh.new()
	apron.size = Vector3(8.0, 0.16, 2.2)
	_mi(wall, apron, TexKit.solid("cobble", treatment, PLASTER * 0.9, fog), Vector3(12.0, wy + 0.0, -11.5))
	# A plank shed (the wooden house wall).
	var shed := _group("shed", stage)
	var sy := _gh(3.0, -12.0)
	var sb := BoxMesh.new()
	sb.size = Vector3(5.0, 2.6, 4.0)
	_mi(shed, sb, TexKit.solid("planks", treatment, LOAM, fog), Vector3(3.0, sy + 1.0, -12.0))
	var roof := BoxMesh.new()
	roof.size = Vector3(5.4, 0.2, 4.4)
	_mi(shed, roof, TexKit.flat_mat(Color("#5E4935")), Vector3(3.0, sy + 2.4, -12.0))
	# The banner: 0.8 x 2.2 m, swaying, on a pole.
	var ban := _group("banner", stage)
	var qm := QuadMesh.new()
	qm.size = Vector2(0.8, 2.2)
	qm.subdivide_depth = 8
	qm.subdivide_width = 3
	qm.orientation = PlaneMesh.FACE_Z
	var bmat := TexKit.banner(treatment, RED, BRASS)
	if bmat is ShaderMaterial:
		(bmat as ShaderMaterial).set_shader_parameter("time_override", FROZEN_TIME)
	var by := _gh(-14.0, -9.0)
	_banner = _mi(ban, qm, bmat, Vector3(-14.0, by + 2.6, -9.0))
	var pole := BoxMesh.new()
	pole.size = Vector3(1.1, 0.08, 0.08)
	_mi(ban, pole, TexKit.flat_mat(Color("#3D2E22")), Vector3(-14.0, by + 3.72, -9.0))
	var post := BoxMesh.new()
	post.size = Vector3(0.1, 3.8, 0.1)
	_mi(ban, post, TexKit.flat_mat(Color("#3D2E22")), Vector3(-14.55, by + 1.9, -9.0))
	_mi(ban, post, TexKit.flat_mat(Color("#3D2E22")), Vector3(-13.45, by + 1.9, -9.0))


## A tree: trunk and lathe canopy; the cutout cards are a separate group so a camera can leave them out.
func _tree(parent: Node3D, cards: Node3D, at: Vector3, pine: bool, fog: Color, size: float, seed_v: float) -> void:
	var t := Node3D.new()
	t.position = at
	t.scale = Vector3.ONE * size
	parent.add_child(t)
	_mi(t, Kit.mesh("trunk"), TexKit.solid("bark_pine" if pine else "bark_dec", treatment, BARK, fog), Vector3.ZERO)
	var leaf := PINE_LEAF if pine else OAK_LEAF
	_mi(t, Kit.mesh("pine" if pine else "oak"), TexKit.solid("leaf_pine" if pine else "leaf_broad", treatment, leaf, fog), Vector3.ZERO)
	var cm := TexKit.cards("leaf_pine" if pine else "leaf_broad", treatment, leaf, fog)
	if cm == null:
		return
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	var n := 6
	for i in n:
		var a := seed_v + TAU * i / n
		var r := 1.5 if pine else 1.9
		var y := (2.0 + (i % 3) * 0.7) if pine else (3.0 + (i % 3) * 0.5)
		var card := _mi(cards, q, cm, at + Vector3(cos(a) * r, y, sin(a) * r) * Vector3(size, size, size))
		card.rotation = Vector3(deg_to_rad(-25.0), -a + PI * 0.5, 0)
		card.rotation.y = atan2(cos(a), sin(a))


# ------------------------------------------------------------------ region vistas from the real land
func _build_vista(name: String, biome_key: String, centre: Vector2) -> void:
	var root := Node3D.new()
	root.name = "vista_" + name
	add_child(root)
	_vistas[name] = root
	var pal := _pal(biome_key)
	var tm := TexKit.terrain(treatment, pal)
	var fog: Color = Land.BIOMES[biome_key].fog
	var k0 := Vector2i(floori(centre.x / Land.CHUNK), floori(centre.y / Land.CHUNK))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 + name.length()
	var trees: Array = []
	var pines: Array = []
	var dead: Array = []
	var rocks: Array = []
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var o := Vector2((k0.x + dx) * Land.CHUNK, (k0.y + dz) * Land.CHUNK)
			var segs := Land.road_segments_near(Rect2(o, Vector2(Land.CHUNK, Land.CHUNK)), 3.2)
			var f := func(x: float, z: float) -> Array:
				var b := Land.biome(x, z)
				var flat: Color = Land.ground_color_with(x, z, b, segs)
				var base: Color = Land.BIOMES[b].ground.darkened(0.12 * _noise(x, z))
				var p := Vector2(x, z)
				var rd := 9999.0
				for seg in segs:
					var a: Vector2 = seg[0]
					var d: Vector2 = seg[1] - a
					var tt := clampf((p - a).dot(d) / d.length_squared(), 0.0, 1.0)
					rd = minf(rd, p.distance_to(a + d * tt))
				var wd := minf(Land.river_dist(x, z) - 5.0, Land.lake_dist(x, z) - Land.LAKE_R + 3.0)
				var wf := 0.0 if b in ["village", "meadow"] else 1.0
				return [Land.height_in(x, z, b), flat if treatment == TexKit.FLAT else base, smoothstep(3.2, 1.2, rd) if rd < 3.2 else 0.0,
					smoothstep(3.0, 0.0, wd) if wd < 3.0 else 0.0, wf]
			_mi(root, TexKit.build_ground(o, Vector2(Land.CHUNK, Land.CHUNK), Vector2i(12, 12), f), tm, Vector3.ZERO)
			# Scatter on a 5 x 5 grid like the land's, deterministic.
			for cz in 5:
				for cx in 5:
					var p := o + Vector2((cx + rng.randf_range(0.15, 0.85)) * 8.0, (cz + rng.randf_range(0.15, 0.85)) * 8.0)
					var roll := rng.randf()
					var b := Land.biome(p.x, p.y)
					if Land.road_dist(p.x, p.y) < 3.6 or Land.is_water(p.x, p.y):
						continue
					var pos := Vector3(p.x, Land.height_in(p.x, p.y, b), p.y)
					var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.3)), pos - Vector3(0, 0.05, 0))
					match b:
						"meadow", "village":
							if roll < 0.07 and Vector2(p.x, p.y).distance_to(Land.VILLAGE) > 18.0:
								trees.append(xf)
						"forest":
							if roll < 0.58:
								(pines if p.x < -120.0 else trees).append(xf)
						"ashlands":
							if roll < 0.14:
								dead.append(xf)
							elif roll < 0.24:
								rocks.append(xf)
	var lstone := TexKit.solid("stone", treatment, Color(0.22, 0.19, 0.19) if biome_key == "ashlands" else Color(0.45, 0.43, 0.4), fog)
	_mm(root, Kit.mesh("trunk"), TexKit.solid("bark_dec", treatment, BARK, fog), trees)
	_mm(root, Kit.mesh("oak"), TexKit.solid("leaf_broad", treatment, OAK_LEAF, fog), trees)
	_mm(root, Kit.mesh("trunk"), TexKit.solid("bark_pine", treatment, BARK, fog), pines)
	_mm(root, Kit.mesh("pine"), TexKit.solid("leaf_pine", treatment, PINE_LEAF, fog), pines)
	_mm(root, Kit.mesh("dead"), TexKit.solid("bark_dec", treatment, Color(0.16, 0.13, 0.12), fog), dead)
	_mm(root, Kit.mesh("rock"), lstone, rocks)
	if biome_key == "village":
		var hmat := TexKit.solid("stone", treatment, PLASTER, fog, 0.5)
		var tmat := TexKit.flat_mat(Color("#5E4935"))
		for h in Land.HOUSES:
			var n := Node3D.new()
			n.position = Vector3(h.x, Land.height(h.x, h.y), h.y)
			n.rotation.y = atan2(Land.VILLAGE.x - h.x, Land.VILLAGE.y - h.y)
			root.add_child(n)
			_mi(n, Kit.mesh("house"), hmat, Vector3(0, 1.6, 0))
			_mi(n, Kit.mesh("roof"), tmat, Vector3(0, 3.2, 0), Vector3(0, 45, 0)).scale = Vector3(1.0, 1.0, 0.86)
			var dm := BoxMesh.new()
			dm.size = Vector3(1.1, 2.0, 0.1)
			_mi(n, dm, TexKit.solid("planks", treatment, LOAM, fog), Vector3(0, 1.0, 3.02))
	# Cutout cards on the trees near the view, for the ragged edge.
	var cm_b := TexKit.cards("leaf_broad", treatment, OAK_LEAF, fog)
	var cm_p := TexKit.cards("leaf_pine", treatment, PINE_LEAF, fog)
	if cm_b != null:
		_card_mm(root, cm_b, trees, 1.9, 3.2, centre)
		_card_mm(root, cm_p, pines, 1.5, 2.2, centre)
	root.visible = false


func _mm(parent: Node3D, mesh: Mesh, mat: Material, xfs: Array) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	parent.add_child(mi)


func _card_mm(parent: Node3D, mat: Material, xfs: Array, r: float, y: float, centre: Vector2) -> void:
	var list: Array = []
	for xf in xfs:
		var o: Vector3 = xf.origin
		if Vector2(o.x, o.z).distance_to(centre) > 70.0:
			continue
		var s: float = xf.basis.get_scale().x
		for i in 5:
			var a: float = TAU * i / 5.0 + o.x
			var pos := o + Vector3(cos(a) * r, y + (i % 3) * 0.45, sin(a) * r) * s
			var b := Basis(Vector3.UP, atan2(cos(a), sin(a))) * Basis(Vector3.RIGHT, deg_to_rad(-25.0))
			list.append(Transform3D(b.scaled(Vector3.ONE * s), pos))
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	_mm(parent, q, mat, list)


# ------------------------------------------------------------------ fighters
func _build_fighters() -> void:
	var stage: Node3D = _groups["stage"]
	_hero = PlaceholderVisual.new()
	_hero.has_shield = true
	stage.add_child(_hero)
	_hero.configure(Run.look())
	var f: Dictionary = Land.FOES.thrall
	_enemy = PlaceholderVisual.new()
	stage.add_child(_enemy)
	_enemy.configure({"style": f.style, "scale": f.scale, "body": f.body, "accent": f.accent})
	for v in [_hero, _enemy]:
		v._process(0.016)
		v._process(0.016)
		v.set_process(false)
	_overlay(_hero, false)
	_overlay(_enemy, false)


## Swap the fighters' armour materials for the kit's detail overlay (or back). Only the main armour metal is
## touched (metallic 0.35 and roughness 0.45: not the blade, trim, helm trim or cloth).
func _overlay(v: PlaceholderVisual, on: bool) -> void:
	var store: Dictionary = _hero_flat if v == _hero else _enemy_flat
	var fog: Color = Land.BIOMES.village.fog
	for mi in v.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.material_override == null:
			continue
		if not store.has(m):
			if m.material_override is StandardMaterial3D:
				var sm := m.material_override as StandardMaterial3D
				if sm.rim_enabled and absf(sm.metallic - 0.35) < 0.01 and absf(sm.roughness - 0.45) < 0.01:
					store[m] = [sm, null]
			continue
		var pair: Array = store[m]
		if on:
			if pair[1] == null:
				pair[1] = TexKit.armour("steel" if v == _hero else "chain", treatment, pair[0], TexKit.D_HERO if v == _hero else TexKit.D_ENEMY, fog)
			m.material_override = pair[1]
		else:
			m.material_override = pair[0]


# ------------------------------------------------------------------ cameras (Art Bible section 10)
func _look_from(pos: Vector3, pitch_deg: float, dir: Vector3) -> Vector3:
	var d := dir.normalized()
	return pos + Vector3(d.x * cos(deg_to_rad(pitch_deg)), sin(deg_to_rad(pitch_deg)), d.z * cos(deg_to_rad(pitch_deg))) * 20.0


func _define_cams() -> void:
	var G := func(x: float, z: float, h: float) -> Vector3:
		return S + Vector3(x, _gh(x, z) + h, z)
	var p: Vector3
	_cams = []
	p = G.call(-20.0, -12.0, 0.6)
	_cams.append({"name": "v1-grass", "region": "village", "pos": p, "look": _look_from(p, -4.0, Vector3.RIGHT), "fov": 60.0, "show": []})
	p = G.call(-13.5, 6.0, 2.5)
	_cams.append({"name": "v2-trail-mud", "region": "village", "pos": p, "look": _look_from(p, -35.0, Vector3.RIGHT), "fov": 60.0, "show": []})
	p = G.call(-2.5, 14.5, 1.6)
	_cams.append({"name": "v3-water-edge", "region": "village", "pos": p, "look": _look_from(p, -15.0, Vector3.FORWARD), "fov": 60.0, "show": []})
	p = G.call(-5.5, 0.0, 1.7)
	_cams.append({"name": "v4-tree-cards", "region": "village", "pos": p, "look": S + Vector3(-5.5, 3.0, -9.0), "fov": 50.0, "show": ["trees", "cards", "hero"],
		"hero": [Vector3(-5.5, _gh(-5.5, -7.2), -7.2), 180.0]})
	_cams.append({"name": "v4b-tree-nocards", "region": "village", "pos": p, "look": S + Vector3(-5.5, 3.0, -9.0), "fov": 50.0, "show": ["trees", "hero"],
		"hero": [Vector3(-5.5, _gh(-5.5, -7.2), -7.2), 180.0]})
	p = G.call(12.0, -11.05, 1.6) - Vector3(0, _gh(12.0, -11.05) - _gh(12.0, -13.0), 0)
	_cams.append({"name": "v5a-wall-square", "region": "village", "pos": p, "look": S + Vector3(12.0, p.y - S.y - 0.1, -13.0), "fov": 60.0, "show": ["wall"]})
	p = Vector3(S.x + 12.75, p.y, S.z - 11.25)
	_cams.append({"name": "v5b-wall-30deg", "region": "village", "pos": p, "look": S + Vector3(11.5, p.y - S.y - 0.1, -12.55), "fov": 60.0, "show": ["wall"]})
	p = G.call(3.0, -8.5, 1.6)
	_cams.append({"name": "v5c-wood-wall", "region": "village", "pos": p, "look": S + Vector3(3.0, p.y - S.y - 0.15, -10.0), "fov": 60.0, "show": ["shed"]})
	p = G.call(14.5, -4.6, 1.5)
	var hp := Vector3(10.0, _gh(10.0, -9.0), -9.0)
	var ep := Vector3(13.4, _gh(13.4, -9.0), -9.0)
	for spec in [["v6a-duel-plain", false, true], ["v6b-duel-armour", true, true], ["v6z-duel-empty", false, false]]:
		_cams.append({"name": spec[0], "region": "village", "pos": p, "look": S + Vector3(11.7, p.y - S.y - 0.2, -9.0), "fov": 55.0,
			"show": ["wall"] + (["hero", "enemy"] if spec[2] else []), "overlay": spec[1],
			"hero": [hp, 90.0], "enemy": [ep, -90.0]})
	p = G.call(-14.0, -6.0, 1.6)
	_cams.append({"name": "v7-banner", "region": "village", "pos": p, "look": p + Vector3(0, sin(deg_to_rad(10.0)), -cos(deg_to_rad(10.0))) * 5.0, "fov": 60.0, "show": ["banner"]})
	var hv := Vector3(12, 0, 62)
	hv.y = Land.height(hv.x, hv.z) + 2.2
	_cams.append({"name": "w1-hearthvale", "region": "village", "vista": "hearthvale", "pos": hv, "look": Vector3(0, 3.5, 20), "fov": 60.0, "show": []})
	var gv := Vector3(-112, 0, 40)
	gv.y = Land.height(gv.x, gv.z) + 2.2
	_cams.append({"name": "w2-greywood", "region": "forest", "vista": "greywood", "pos": gv, "look": Vector3(-120, 3.5, 12), "fov": 60.0, "show": []})
	var av := Vector3(0, 0, -138)
	av.y = Land.height(av.x, av.z) + 2.5
	_cams.append({"name": "w3-ashlands", "region": "ashlands", "vista": "ashlands", "pos": av, "look": Vector3(0, 3.0, -175), "fov": 60.0, "show": []})
	for i in _cams.size():
		_cams[i].id = "%02d-%s" % [i + 1, _cams[i].name]


func _goto(i: int) -> void:
	_cam_i = i
	var c: Dictionary = _cams[i]
	_set_region(c.region)
	var vista: String = c.get("vista", "")
	(_groups["stage"] as Node3D).visible = vista == ""
	for k in _vistas:
		(_vistas[k] as Node3D).visible = k == vista
	for g in ["trees", "cards", "wall", "shed", "banner"]:
		(_groups[g] as Node3D).visible = g in c.show
	_hero.visible = "hero" in c.show
	_enemy.visible = "enemy" in c.show
	if c.has("hero"):
		_hero.position = c.hero[0]
		_hero.rotation_degrees.y = c.hero[1]
	if c.has("enemy"):
		_enemy.position = c.enemy[0]
		_enemy.rotation_degrees.y = c.enemy[1]
	if "hero" in c.show or "enemy" in c.show:
		_overlay(_hero, c.get("overlay", false))
		_overlay(_enemy, c.get("overlay", false))
	for v in [_hero, _enemy]:
		if v.visible:
			v._process(0.0)  # the limbs are placed in world space by _process, which is frozen: pose once after moving
			v._process(0.0)
	_cam.fov = c.fov
	_cam.global_position = c.pos
	_cam.look_at(c.look)
	_frames = 0
	_settled = false


func _process(_delta: float) -> void:
	_frames += 1
	if not _ready_printed and _frames >= 2:
		_ready_printed = true
		print("LOOKTEST ready treatment=%s textures=%d cams=%d" % [TexKit.NAMES[treatment], TexKit.loaded.size(), _cams.size()])
	if _settled or _frames < SETTLE_FRAMES:
		if _settled and only_cam == "":
			_poll_next()
		return
	_settled = true
	var c: Dictionary = _cams[_cam_i]
	print("LOOKTEST cam %s settled" % c.id)
	if only_cam != "" or _mem_all:
		_print_mem(c.id)


func _poll_next() -> void:
	if not OS.has_feature("web"):
		return
	var v := int(JavaScriptBridge.eval("window.__lt_next === undefined ? -1 : window.__lt_next", true))
	if v >= 0 and v != _cam_i:
		if v >= _cams.size():
			print("LOOKTEST done")
			set_process(false)
			return
		_goto(v)


func _print_mem(id: String) -> void:
	var ri := RenderingServer
	print("LOOKTEST mem cam=%s treatment=%s tex=%.2f buf=%.2f video=%.2f draws=%d prims=%d objs=%d textures_loaded=%d" % [id, TexKit.NAMES[treatment],
		ri.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0,
		ri.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED) / 1048576.0,
		ri.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
		ri.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		ri.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		ri.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME), TexKit.loaded.size()])
