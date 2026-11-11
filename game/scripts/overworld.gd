class_name Overworld
extends Node3D

const SPEED := 5.0
const LOAD_R := 2
const PROMPTS := {"smith": "TRADE", "store": "SELL", "task": "TALK", "brazier": "REST", "tower": "ENTER",
	"stones": "CROSS", "chest": "OPEN", "npc": "TALK", "spot": "LOOK", "beast": "SHOOT"}
const NPC_LOOKS := {
	"elder": {"style": "sentinel", "scale": 0.95, "body": Color(0.5, 0.48, 0.52), "accent": Color(0.75, 0.75, 0.9), "over": {"cape": 1.1, "wings": false}},
	"alchemist": {"style": "duelist", "scale": 0.95, "body": Color(0.3, 0.4, 0.32), "accent": Color(0.4, 0.9, 0.5), "over": {"focus": Color(0.4, 1.0, 0.5), "cape": 0.9}},
	"fisher": {"style": "duelist", "scale": 0.95, "body": Color(0.4, 0.42, 0.46), "accent": Color(0.3, 0.5, 0.7), "over": {"plume": false}},
	"ranger": {"style": "duelist", "scale": 1.05, "body": Color(0.26, 0.34, 0.22), "accent": Color(0.6, 0.45, 0.2), "over": {"back_bow": true, "cape": 0.9}},
	"villager": {"style": "duelist", "scale": 0.92, "body": Color(0.5, 0.42, 0.34), "accent": Color(0.55, 0.3, 0.2), "over": {"plume": false, "half_cape": false}},
}
const WALK_LOOPS := [
	[Vector2(-10, 14), Vector2(8, 12), Vector2(16, 30), Vector2(0, 44), Vector2(-18, 34)],
	[Vector2(20, 14), Vector2(26, 40), Vector2(4, 46), Vector2(-6, 30)],
	[Vector2(-24, 14), Vector2(-28, 30), Vector2(-12, 46), Vector2(-4, 20)],
]
const TABLES := {
	"meadow": [["tree", 0.07], ["tnode", 0.035], ["rock", 0.02], ["rnode", 0.014], ["herb", 0.05], ["foe", 0.03], ["beast", 0.022]],
	"forest": [["tree", 0.58], ["tnode", 0.1], ["herb", 0.03], ["foe", 0.04], ["rock", 0.02], ["beast", 0.02]],
	"marsh": [["reed", 0.4], ["dead", 0.07], ["herb", 0.09], ["foe", 0.045], ["tnode", 0.02], ["beast", 0.02]],
	"quarry": [["rock", 0.28], ["rnode", 0.13], ["foe", 0.045], ["dead", 0.02]],
	"ruins": [["wall", 0.22], ["rock", 0.08], ["rnode", 0.05], ["herb", 0.04], ["foe", 0.07], ["chest", 0.014], ["dead", 0.05], ["tnode", 0.03]],
	"ashlands": [["dead", 0.14], ["rock", 0.1], ["tnode", 0.05], ["rnode", 0.04], ["herb", 0.035], ["foe", 0.06]],
}

var is_land := true
var theme := {"name": "Hearthvale", "special": "open"}
var tier := 0
var hero: PlaceholderVisual
var hero_pos := Vector3.ZERO
var hero_yaw := 0.0
var cam: Camera3D
var cam_yaw := 0.0
var look_cool := 0.0
var stick := Vector2.ZERO
var ents: Array = []
var near := {}
var hud: WorldHud
var started := false
var gather_progress := -1.0
var gather_label := ""
var duel: Duel
var _duel_ents: Array = []
var _walkers: Array = []
var _remote := {}
var _pub_t := 0.0
var _pvp_ask_t := 0.0
var _pvp_pending := ""
var _reached := ""
var _rain: CPUParticles3D
var _raining := false
var _weather_t := 40.0


static var _meshes := {}
static var _mats := {}
static var map_tex: ImageTexture

var _chunks := {}
var _queue: Array = []
var _gather := {}
var _biome := ""
var _env: Environment
var _sky: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _day := 0.3
var _walked := 0.0
var _save_t := 0.0
var _last_safe := Vector3.ZERO
var _leaving := false
var _show_light: OmniLight3D
var _t := 0.0
var _bot := ""
var _bot_step := 0
var _bot_wait := 0.0
var _stuck := 0.0
var _shot_path := ""
var _shot_when := ""


func _ready() -> void:
	Run.ensure_loaded()
	var at := ""
	var direct_duel := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autoplay="):
			_bot = a.trim_prefix("--autoplay=")
			direct_duel = _bot not in ["tour", "gather", "pvp_a", "pvp_b"]
			if not Run.title_seen and not direct_duel:
				Run.no_save = true
				Run.data = Run.defaults()
				Run.data.skills_seeded = true
				Run.data.tutorial_done = true
				Run.title_seen = true
				if _bot.begins_with("pvp"):
					Run.data.gold = 500
				if _bot == "tour":
					for sk in Craft.COMBAT:
						Run.data.skills[sk] = Craft.xp_for(45)
		elif a.begins_with("--shot="):
			_shot_path = a.trim_prefix("--shot=")
			Run.no_save = true
		elif a.begins_with("--shot-when="):
			_shot_when = a.trim_prefix("--shot-when=")
		elif a.begins_with("--at="):
			at = a.trim_prefix("--at=")
		elif a.begins_with("--skills=") and not Run.title_seen:
			for sk in Craft.SKILLS:
				Run.data.skills[sk] = Craft.xp_for(int(a.trim_prefix("--skills=")))
		elif a.begins_with("--equip=") and not Run.title_seen:
			for id in a.trim_prefix("--equip=").split(","):
				Run.data.inventory.append(id)
				Run.equip(id)
	if direct_duel or _shot_when in ["windup", "open", "result", "tutorial"]:
		get_tree().change_scene_to_file.call_deferred("res://scenes/duel.tscn")
		return
	var tower_shot := _shot_when in ["world", "shop", "bag", "towermap"]
	if tower_shot or (Run.data.in_tower and at == ""):
		if tower_shot:
			Run.data.in_tower = true
		get_tree().change_scene_to_file.call_deferred("res://scenes/world.tscn")
		return
	if _shot_path != "" and _shot_when != "title":
		Run.title_seen = true
		Run.data.gold = 500
		for m in ["copper_ore", "iron_ore", "oak_log", "pine_log", "trout", "marigold", "hide"]:
			Run.data.mats[m] = 6
	Engine.time_scale = 4.0 if _bot in ["tour", "gather"] else 1.0
	AudioServer.set_bus_mute(0, not Run.data.sound)
	Online.start()
	Online.message.connect(_net_message)
	Run.apply_web_settings(get_viewport())
	Run.encounter = {}

	hero_pos = Vector3(float(Run.data.ow_x), 0, float(Run.data.ow_z))
	if at != "":
		var parts := at.split(",")
		hero_pos = Vector3(float(parts[0]), 0, float(parts[1]))
	if not Land.in_bounds(hero_pos.x, hero_pos.z) or Land.is_water(hero_pos.x, hero_pos.z):
		hero_pos = Land.START
	hero_pos.y = Land.walk_height(hero_pos.x, hero_pos.z)
	_last_safe = hero_pos
	_build_sky()
	_build_tower()

	hero = PlaceholderVisual.new()
	hero.has_shield = true
	add_child(hero)
	hero.configure(Run.look())
	hero.position = hero_pos
	cam = Camera3D.new()
	cam.fov = 60.0
	cam.far = 260.0
	add_child(cam)
	cam.make_current()
	_show_light = OmniLight3D.new()
	_show_light.position = Vector3(-0.6, 0.6, 0.2)
	_show_light.light_energy = 3.0
	_show_light.omni_range = 7.0
	_show_light.visible = false
	cam.add_child(_show_light)
	add_child(Sfx.new())

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = WorldHud.new()
	hud.world = self
	layer.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in WALK_LOOPS.size():
		var wv := PlaceholderVisual.new()
		add_child(wv)
		var look: Dictionary = NPC_LOOKS.villager.duplicate()
		look.body = [Color(0.5, 0.42, 0.34), Color(0.36, 0.4, 0.5), Color(0.45, 0.5, 0.36)][i]
		wv.configure(look)
		var start: Vector2 = WALK_LOOPS[i][0]
		_walkers.append({"id": "villager", "type": "npc", "pos": Vector3(start.x, Land.walk_height(start.x, start.y), start.y), "label": "Villager",
			"height": 2.2, "node": wv, "loop": WALK_LOOPS[i], "at": 0, "pause": 0.0})
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
	add_child(_rain)
	started = Run.title_seen
	if Run.resumed:
		Run.resumed = false
		Run.captions.append("Picked up where you left off.")

	_update_chunks(true)
	_update_camera(1.0)
	if _bot != "":
		print("LAND at=%d,%d combat=%d gold=%d" % [hero_pos.x, hero_pos.z, Run.combat_level(), Run.data.gold])


func begin() -> void:
	if started:
		return
	started = true
	Run.title_seen = true
	if Run.total_level() <= Craft.SKILLS.size() + 2:
		Run.captions.append("Hearthvale. The tower stands to the north. You will need to be far stronger before you climb it.")
		Run.captions.append("Chop, mine, fish and forage out in the land. Forge and cook in the village. Every skill grows as you use it.")
	Run.save()


func place_name() -> String:
	return Land.BIOMES[_biome].name if _biome != "" else "Hearthvale"


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


func _part(parent: Node3D, m: Mesh, pos: Vector3, material: Material, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	mi.material_override = material
	parent.add_child(mi)
	return mi


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
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 45.0
	add_child(_sun)
	_apply_light(1.0)


func _build_tower() -> void:
	var dark := mat("tower", Color(0.11, 0.1, 0.12), 0.85)
	var base := Vector3(Land.TOWER.x, 0.8, Land.TOWER.y)
	_part(self, MeshKit.lathe([[17.0, -2.0], [15.0, 6.0], [12.5, 40.0], [11.5, 95.0], [14.0, 104.0], [14.0, 110.0], [9.0, 112.0], [0.0, 126.0]], 14), base, dark)
	var fire := SphereMesh.new()
	fire.radius = 5.0
	fire.height = 9.0
	_part(self, fire, base + Vector3(0, 116, 0), mat("pyre", Color(1.0, 0.45, 0.1), 0.5, 5.0))
	var beacon := OmniLight3D.new()
	beacon.position = base + Vector3(0, 60, 16)
	beacon.light_color = Color(1.0, 0.5, 0.2)
	beacon.light_energy = 4.0
	beacon.omni_range = 70.0
	add_child(beacon)
	var g := Vector3(Land.TOWER_GATE.x, 0.8, Land.TOWER_GATE.y)
	var post := BoxMesh.new()
	post.size = Vector3(1.4, 8.0, 1.4)
	_part(self, post, g + Vector3(-3.4, 4, -5), dark)
	_part(self, post, g + Vector3(3.4, 4, -5), dark)
	var lintel := BoxMesh.new()
	lintel.size = Vector3(9.0, 1.4, 1.8)
	_part(self, lintel, g + Vector3(0, 8.4, -5), dark)
	var veil := StandardMaterial3D.new()
	veil.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	veil.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	veil.albedo_color = Color(1.0, 0.45, 0.15, 0.4)
	veil.cull_mode = BaseMaterial3D.CULL_DISABLED
	var q := QuadMesh.new()
	q.size = Vector2(5.4, 7.6)
	_part(self, q, g + Vector3(0, 3.8, -5), veil)


func _chunk_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / Land.CHUNK), floori(p.z / Land.CHUNK))


func _update_chunks(build_all := false) -> void:
	var c := _chunk_of(hero_pos)
	for dx in range(-LOAD_R, LOAD_R + 1):
		for dz in range(-LOAD_R, LOAD_R + 1):
			var k := c + Vector2i(dx, dz)
			if not _chunks.has(k) and not _queue.has(k):
				_queue.append(k)

	_queue.sort_custom(func(a, b): return (a - c).length_squared() < (b - c).length_squared())
	while not _queue.is_empty():
		var k2: Vector2i = _queue.pop_front()
		if absi(k2.x - c.x) <= LOAD_R + 1 and absi(k2.y - c.y) <= LOAD_R + 1:
			_build_chunk(k2)
			if not build_all:
				break
	var changed := false
	for k3 in _chunks.keys():
		if absi(k3.x - c.x) > LOAD_R + 1 or absi(k3.y - c.y) > LOAD_R + 1:
			for e in _chunks[k3].ents:
				if e.get("node") != null and e.type == "foe":
					(e.node as Node).queue_free()
			(_chunks[k3].root as Node).queue_free()
			_chunks.erase(k3)
			changed = true
	if changed or build_all:
		_collect_ents()


func _collect_ents() -> void:
	ents = []
	ents.append_array(_walkers)
	ents.append_array(_remote.values())
	for k in _chunks:
		ents.append_array(_chunks[k].ents)


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
	add_child(root)
	var chunk := {"root": root, "ents": [], "obstacles": []}
	_chunks[k] = chunk
	var centre := origin + Vector2(Land.CHUNK, Land.CHUNK) * 0.5
	if not Land.in_bounds(clampf(centre.x, -Land.X_MAX - 30, Land.X_MAX + 30), centre.y) and absf(centre.x) > Land.X_MAX + 30:
		return
	_part(root, _ground_mesh(origin), Vector3.ZERO, mat("ground", Color.WHITE, 0.95, 0.0, true))
	if Land.river_dist(centre.x, centre.y) < 44.0 or Land.lake_dist(centre.x, centre.y) < Land.LAKE_R + 30.0:
		var wm := StandardMaterial3D.new() if not _mats.has("water") else null
		if wm:
			wm.albedo_color = Color(0.12, 0.32, 0.42, 0.72)
			wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			wm.metallic = 0.5
			wm.roughness = 0.08
			_mats["water"] = wm
		var plane := PlaneMesh.new()
		plane.size = Vector2(Land.CHUNK, Land.CHUNK)
		_part(root, plane, Vector3(centre.x, Land.WATER_Y, centre.y), _mats["water"])

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
			_add_house(chunk, h)
	for pl in Land.PLACES:
		if Rect2(origin, Vector2(Land.CHUNK, Land.CHUNK)).has_point(pl.pos):
			_add_place(chunk, pl)
	if Rect2(origin, Vector2(Land.CHUNK, Land.CHUNK)).has_point(Land.BRIDGE.get_center()):
		var deck := BoxMesh.new()
		deck.size = Vector3(Land.BRIDGE.size.x, 0.4, Land.BRIDGE.size.y)
		_part(root, deck, Vector3(Land.BRIDGE.get_center().x, 0.55, Land.BRIDGE.get_center().y), mat("wood", Color(0.34, 0.22, 0.12)))
		for side in [-1.0, 1.0]:
			var rail := BoxMesh.new()
			rail.size = Vector3(Land.BRIDGE.size.x, 0.15, 0.15)
			_part(root, rail, Vector3(Land.BRIDGE.get_center().x, 1.6, Land.BRIDGE.get_center().y + side * (Land.BRIDGE.size.y * 0.5 - 0.1)), mat("wood", Color.WHITE))
	for key in multi:
		var data: Array = multi[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh(String(key).get_slice("|", 0))
		mm.instance_count = data[0].size()
		for i in data[0].size():
			mm.set_instance_transform(i, data[0][i])
			mm.set_instance_color(i, data[1][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = data[2]
		root.add_child(mmi)
	_collect_ents()


func _scatter(multi: Dictionary, mesh_key: String, mat_key: String, tint: Color, p: Vector2, spin: float, size: float, squash := 1.0) -> void:
	var key := mesh_key + "|" + mat_key
	if not multi.has(key):
		multi[key] = [[], [], mat("mm_" + mat_key, Color.WHITE, 0.9, 0.0, true)]
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
			_part(n, box, Vector3(0, 0.35, 0), mat("wood", Color(0.34, 0.22, 0.12)))
			var band := BoxMesh.new()
			band.size = Vector3(0.14, 0.76, 0.76)
			_part(n, band, Vector3(0, 0.36, 0), mat("goldtrim", Color(0.9, 0.7, 0.3), 0.3))
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
			var bark := mat("bark_solo", Color(0.3, 0.2, 0.12))
			if node_id == "ashwood":
				_part(full, mesh("dead"), Vector3.ZERO, mat("ashbark", Color(0.2, 0.12, 0.1)), Vector3.ZERO, Vector3.ONE * size * 1.2)
				_part(full, mesh("ore"), Vector3(0, 2.2 * size, 0), mat("ashglow", Color(1.0, 0.4, 0.1), 0.5, 3.0), Vector3.ZERO, Vector3(2, 3, 2))
			else:
				_part(full, mesh("trunk"), Vector3.ZERO, bark, Vector3.ZERO, Vector3.ONE * size)
				var pine := node_id == "pine"
				_part(full, mesh("pine" if pine else "oak"), Vector3.ZERO, mat("leaf_" + node_id, Color(0.1, 0.3, 0.2) if pine else Color(0.3, 0.5, 0.14)), Vector3.ZERO, Vector3.ONE * size)
			_part(empty, mesh("stump"), Vector3.ZERO, bark)
		"mining":
			radius = 1.1
			var stone := mat("stone_solo", Color(0.4, 0.38, 0.36))
			_part(full, mesh("rock"), Vector3.ZERO, stone, Vector3.ZERO, Vector3(1.1, 1.2, 1.1))
			var ore_col: Color = {"copper": Color(0.9, 0.5, 0.25), "iron": Color(0.6, 0.68, 0.8), "ember": Color(1.0, 0.3, 0.08)} [node_id]
			var om := mat("ore_" + node_id, ore_col, 0.3, 3.0 if node_id == "ember" else 0.6)
			for i in 5:
				var a := TAU * i / 5.0
				_part(full, mesh("ore"), Vector3(cos(a) * 0.7, 0.5 + (i % 2) * 0.35, sin(a) * 0.7), om, Vector3(30 * cos(a), 0, 30 * sin(a)), Vector3.ONE * 1.3)
			_part(empty, mesh("rock"), Vector3.ZERO, stone, Vector3.ZERO, Vector3(1.1, 1.2, 1.1))
		"foraging":
			radius = 0.0
			var hc: Color = {"marigold": Color(1.0, 0.8, 0.15), "bogroot": Color(0.6, 0.35, 0.8), "ashbloom": Color(1.0, 0.45, 0.15)} [node_id]
			var hm := mat("herb_" + node_id, hc, 0.6, 2.5 if node_id == "ashbloom" else 0.4)
			for i in 3:
				_part(full, mesh("herb"), Vector3(cos(i * 2.1) * 0.25, 0, sin(i * 2.1) * 0.25), hm, Vector3.ZERO, Vector3.ONE * 1.5)
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
	var hide := mat("hide_" + kind, Color(0.5, 0.36, 0.22) if deer else Color(0.24, 0.2, 0.18))
	var h := 0.85 if deer else 0.55
	_part(n, MeshKit.tube(PackedVector3Array([Vector3(0, h, 0.65), Vector3(0, h + 0.05, 0.35), Vector3(0, h + 0.05, -0.3), Vector3(0, h, -0.6)]),
		PackedFloat32Array([0.1, 0.27, 0.29, 0.15]) if deer else PackedFloat32Array([0.14, 0.32, 0.36, 0.2]), 8), Vector3.ZERO, hide)
	for sx in [-1.0, 1.0]:
		for sz in [-0.42, 0.45]:
			_part(n, MeshKit.lathe([[0.03, 0.0], [0.05, h * 0.5], [0.07, h]], 5), Vector3(0.15 * sx, 0, sz), hide)
	var head_at := Vector3(0, h + (0.55 if deer else 0.1), -0.85)
	_part(n, MeshKit.tube(PackedVector3Array([Vector3(0, h, -0.5), head_at]), PackedFloat32Array([0.14, 0.09]), 6), Vector3.ZERO, hide)
	_part(n, MeshKit.tube(PackedVector3Array([head_at + Vector3(0, 0.02, 0.1), head_at + Vector3(0, 0, -0.1), head_at + Vector3(0, -0.06, -0.32)]),
		PackedFloat32Array([0.09, 0.11, 0.05]), 6), Vector3.ZERO, hide)
	if deer:
		for sx in [-1.0, 1.0]:
			_part(n, MeshKit.horn(Vector3.ZERO, Vector3(0.28 * sx, 0.5, 0.05), Vector3(0.1 * sx, 0, 0.12), 0.025, 5), head_at + Vector3(0.06 * sx, 0.08, 0.05), mat("antler", Color(0.8, 0.75, 0.62)))
	return n


func _add_fishing(chunk: Dictionary, eid: String, p: Vector2) -> void:
	var to_water := Vector2(Land.river_x(p.y) - p.x, 0).normalized()
	if Land.lake_dist(p.x, p.y) < Land.LAKE_R + 10.0:
		to_water = (Land.LAKE - p).normalized()
	var spot := p + to_water * 5.0
	var n := Node3D.new()
	n.position = Vector3(spot.x, Land.WATER_Y + 0.05, spot.y)
	chunk.root.add_child(n)
	var rm := mat("ripple", Color(0.75, 0.9, 1.0), 0.3, 1.2)
	_part(n, mesh("ripple"), Vector3.ZERO, rm)
	_part(n, mesh("ripple"), Vector3.ZERO, rm, Vector3.ZERO, Vector3(1.8, 1, 1.8))
	var node_id := Land.fish_at(p.x, p.y)
	var pos := Vector3(p.x, Land.walk_height(p.x, p.y), p.y)
	var e := {"id": eid, "type": "node", "node_id": node_id, "pos": pos, "label": Land.NODES[node_id].label, "height": 1.6,
		"node": n, "full": n, "empty": Node3D.new(), "charges": int(Land.NODES[node_id].charges), "depleted": false}
	n.add_child(e.empty)
	if not Run.respawn_due(eid):
		e.depleted = true
		n.visible = false
	chunk.ents.append(e)


func _add_house(chunk: Dictionary, h: Vector2) -> void:
	var n := Node3D.new()
	n.position = Vector3(h.x, Land.height(h.x, h.y), h.y)
	n.rotation.y = atan2(Land.VILLAGE.x - h.x, Land.VILLAGE.y - h.y)
	chunk.root.add_child(n)
	_part(n, mesh("house"), Vector3(0, 1.6, 0), mat("plaster", Color(0.62, 0.56, 0.45)))
	_part(n, mesh("roof"), Vector3(0, 3.2, 0), mat("thatch", Color(0.4, 0.22, 0.14)), Vector3(0, 45, 0), Vector3(1.0, 1.0, 0.86))
	var door := BoxMesh.new()
	door.size = Vector3(1.1, 2.0, 0.1)
	_part(n, door, Vector3(0, 1.0, 3.02), mat("wood", Color(0.34, 0.22, 0.12)))
	var win := BoxMesh.new()
	win.size = Vector3(0.9, 0.8, 0.1)
	_part(n, win, Vector3(2.2, 1.8, 3.02), mat("window", Color(1.0, 0.8, 0.4), 0.5, 2.0))
	chunk.obstacles.append(Vector3(h.x, h.y, 4.4))


func _add_place(chunk: Dictionary, pl: Dictionary) -> void:
	var p: Vector2 = pl.pos
	var pos := Vector3(p.x, Land.walk_height(p.x, p.y), p.y)
	var n := Node3D.new()
	n.position = pos
	chunk.root.add_child(n)
	var e := {"id": pl.id, "type": pl.type, "pos": pos, "label": pl.label, "height": 2.4, "node": n}
	var stone := mat("stone_solo", Color(0.4, 0.38, 0.36))
	var wood := mat("wood", Color(0.34, 0.22, 0.12))
	match pl.type:
		"smith", "store", "task":
			var look: Dictionary = {
				"smith": {"style": "knight", "scale": 1.0, "body": Color(0.45, 0.32, 0.2), "accent": Color(0.9, 0.7, 0.3)},
				"store": {"style": "duelist", "scale": 1.0, "body": Color(0.5, 0.42, 0.3), "accent": Color(0.3, 0.6, 0.3)},
				"task": {"style": "sentinel", "scale": 1.05, "body": Color(0.3, 0.3, 0.36), "accent": Color(0.8, 0.25, 0.2)},
			} [pl.type]
			var v := PlaceholderVisual.new()
			n.add_child(v)
			v.configure(look)
			v.rotation.y = atan2(- (Land.VILLAGE.x - p.x), - (Land.VILLAGE.y - p.y))
			var stall := BoxMesh.new()
			stall.size = Vector3(2.6, 1.0, 0.9)
			_part(n, stall, Vector3(0, 0.5, 0).rotated(Vector3.UP, 0) + Vector3(sin(v.rotation.y) * -1.2, 0, cos(v.rotation.y) * -1.2), wood, Vector3(0, rad_to_deg(v.rotation.y), 0))
		"station":
			e.skill = pl.skill
			match pl.skill:
				"smithing":
					var blk := BoxMesh.new()
					blk.size = Vector3(0.7, 0.7, 0.7)
					_part(n, blk, Vector3(0, 0.35, 0), wood)
					_part(n, MeshKit.lathe([[0.3, 0.0], [0.2, 0.12], [0.2, 0.3], [0.5, 0.42], [0.5, 0.55], [0.0, 0.56]], 4, 1.7, 0.8), Vector3(0, 0.7, 0), mat("anvil", Color(0.2, 0.2, 0.23), 0.4))
				"cooking":
					_part(n, MeshKit.lathe([[0.9, 0.0], [0.8, 0.25], [0.0, 0.3]], 8), Vector3.ZERO, stone)
					var fire := SphereMesh.new()
					fire.radius = 0.4
					fire.height = 0.9
					_part(n, fire, Vector3(0, 0.6, 0), mat("fire", Color(1.0, 0.55, 0.15), 0.5, 4.0))
					_fire_light(n)
				"alchemy":
					var tbl := BoxMesh.new()
					tbl.size = Vector3(1.8, 0.9, 0.9)
					_part(n, tbl, Vector3(0, 0.45, 0), wood)
					for i in 3:
						_part(n, MeshKit.lathe([[0.0, 0.0], [0.12, 0.02], [0.14, 0.16], [0.05, 0.26], [0.05, 0.36], [0.0, 0.37]], 8), Vector3(-0.5 + i * 0.5, 0.9, 0),
							mat("vial%d" % i, [Color(0.3, 1.0, 0.5), Color(0.8, 0.4, 1.0), Color(1.0, 0.6, 0.2)][i], 0.2, 2.0))
				"fletching":
					var bench := BoxMesh.new()
					bench.size = Vector3(2.0, 0.8, 0.8)
					_part(n, bench, Vector3(0, 0.4, 0), wood)
					_part(n, MeshKit.horn(Vector3(0, -0.6, 0), Vector3(0, 0.6, 0), Vector3(0, 0, 0.25), 0.03, 9), Vector3(0, 1.0, 0), wood, Vector3(0, 0, 80))
		"brazier":
			_part(n, MeshKit.lathe([[1.2, 0.0], [1.1, 0.3], [0.0, 0.35]], 10), Vector3.ZERO, stone)
			var f2 := SphereMesh.new()
			f2.radius = 0.55
			f2.height = 1.3
			_part(n, f2, Vector3(0, 0.8, 0), mat("fire", Color(1.0, 0.55, 0.15), 0.5, 4.0))
			_fire_light(n)
		"stones":
			e.height = 1.5
			for i in 5:
				_part(n, mesh("rock"), Vector3(4.0 + i * 3.4, Land.WATER_Y - 0.35 - pos.y, sin(i * 1.7) * 0.8), stone, Vector3.ZERO, Vector3(0.9, 0.5, 0.9))

			var far := Vector3(Land.river_x(Land.STONES_Z) + 9.0, 0, Land.STONES_Z)
			far.y = Land.walk_height(far.x, far.z)
			chunk.ents.append({"id": "stones_east", "type": "stones", "pos": far, "label": pl.label, "height": 1.5, "node": n})
		"tower":
			e.height = 4.0
		"npc":
			var nv := PlaceholderVisual.new()
			n.add_child(nv)
			nv.configure(NPC_LOOKS[pl.id])
			nv.rotation.y = atan2(- (Land.VILLAGE.x - p.x), - (Land.VILLAGE.y - p.y))
		"spot":
			match pl.id:
				"shrine", "altar":
					_part(n, MeshKit.lathe([[1.3, 0.0], [1.2, 0.35], [0.5, 0.5], [0.45, 1.5], [0.7, 1.7], [0.0, 1.75]], 6), Vector3.ZERO, stone)
					var glow_c := Color(0.4, 1.0, 0.7) if pl.id == "shrine" else Color(1.0, 0.5, 0.2)
					_part(n, mesh("ore"), Vector3(0, 1.9, 0), mat("glow_" + pl.id, glow_c, 0.4, 4.0), Vector3.ZERO, Vector3(1.6, 1.8, 1.6))
					var sl := OmniLight3D.new()
					sl.position = Vector3(0, 2.4, 0)
					sl.light_color = glow_c
					sl.light_energy = 2.0
					sl.omni_range = 9.0
					n.add_child(sl)
				"circle":
					for i in 9:
						var a := TAU * i / 9.0
						_part(n, mesh("rock"), Vector3(cos(a) * 5.0, 0, sin(a) * 5.0), stone, Vector3(0, rad_to_deg(a), 0), Vector3(0.7, 2.6 + (i % 3) * 0.5, 0.5))
				"watch":
					var tw := BoxMesh.new()
					tw.size = Vector3(4.0, 7.0, 4.0)
					_part(n, tw, Vector3(0, 3.2, -3.0), stone, Vector3(0, 12, 8))
					_part(n, mesh("wall"), Vector3(3.0, 1.0, 0.5), stone, Vector3(0, 40, 70))
					chunk.obstacles.append(Vector3(p.x, p.y - 3.0, 2.8))
	chunk.ents.append(e)
	if pl.type in ["station", "brazier", "npc"]:
		chunk.obstacles.append(Vector3(p.x, p.y, 0.9))


func _fire_light(n: Node3D) -> void:
	var l := OmniLight3D.new()
	l.position = Vector3(0, 1.6, 0)
	l.light_color = Color(1.0, 0.6, 0.25)
	l.light_energy = 2.5
	l.omni_range = 10.0
	n.add_child(l)


func _blocked(p: Vector3) -> bool:
	if not Land.in_bounds(p.x, p.z) or Land.is_water(p.x, p.z):
		return true
	if Vector2(p.x, p.z).distance_to(Land.TOWER) < 17.5:
		return true
	var c := _chunk_of(p)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var ch: Variant = _chunks.get(c + Vector2i(dx, dz))
			if ch == null:
				continue
			for o in ch.obstacles:
				if Vector2(p.x - o.x, p.z - o.y).length() < float(o.z) + 0.35:
					return true
	return false


func _process(delta: float) -> void:
	if hero == null:
		return
	_publish(delta)
	if duel != null:
		return
	_tick_remote(delta)
	_t += delta
	_day = fmod(_day + delta / 480.0, 1.0)
	_take_shot_if_due()
	_update_chunks()
	_apply_light(clampf(delta * 0.8, 0.0, 1.0))
	if not started or hud.screen != "" or _leaving:
		hero.set_walk(0.0)
		if hud.screen in ["bag", "shop"]:
			hero.rotation.y = cam_yaw + PI + sin(_t * 0.9) * 0.6
		_update_camera(delta)
		return
	var input := stick
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): input.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): input.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): input.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): input.x += 1.0
	var dir := Vector3.ZERO
	if _bot != "":
		dir = _bot_dir(delta)
	elif input.length() > 0.12:
		input = input.limit_length(1.0)
		var f := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
		var r := Vector3(cos(cam_yaw), 0, -sin(cam_yaw))
		dir = r * input.x - f * input.y
	var amount := minf(dir.length(), 1.0)
	if amount > 0.05:
		_gather = {}
		gather_progress = -1.0
		var speed := SPEED * (1.0 + 0.0035 * (Run.skill("agility") - 1))
		var step := dir.limit_length(1.0) * speed * delta
		var before := hero_pos
		if not _blocked(hero_pos + Vector3(step.x, 0, 0)):
			hero_pos.x += step.x
		if not _blocked(hero_pos + Vector3(0, 0, step.z)):
			hero_pos.z += step.z
		var moved := Vector2(hero_pos.x - before.x, hero_pos.z - before.z).length()
		_stuck = _stuck + delta if moved < step.length() * 0.3 else 0.0
		_walked += moved
		if _walked >= 40.0:
			_walked = 0.0
			Run.train("agility", 8)
		hero_yaw = lerp_angle(hero_yaw, atan2(-dir.x, -dir.z), minf(delta * 10.0, 1.0))
		look_cool -= delta
		if look_cool <= 0.0:
			cam_yaw = lerp_angle(cam_yaw, hero_yaw, minf(delta * 1.1, 1.0))
	hero_pos.y = lerpf(hero_pos.y, Land.walk_height(hero_pos.x, hero_pos.z), clampf(delta * 12.0, 0.0, 1.0))
	hero.set_walk(amount)
	hero.position = hero_pos
	hero.rotation.y = hero_yaw
	_update_camera(delta)
	_tick_gather(delta)
	_check_surroundings(delta)
	var b := Land.biome(hero_pos.x, hero_pos.z)
	if b != _biome:
		_biome = b
		theme.name = place_name()
		hud.announce(theme.name)
	_tick_walkers(delta)
	_weather_t -= delta
	if _weather_t <= 0.0:
		_raining = not _raining and randf() < 0.45
		_weather_t = randf_range(50.0, 90.0) if _raining else randf_range(90.0, 200.0)
		_rain.emitting = _raining
		if _raining:
			hud.announce("Rain")
	_rain.position = hero_pos + Vector3(0, 14, 0)
	_env.fog_density = lerpf(_env.fog_density, 0.012 if _raining else 0.0045, clampf(delta * 0.5, 0.0, 1.0))

	_save_t += delta
	if _save_t > 5.0:
		_save_t = 0.0
		Run.data.ow_x = _last_safe.x
		Run.data.ow_z = _last_safe.z
		Run.save()


func _apply_light(k: float) -> void:
	var light := clampf(sin(_day * TAU) * 1.3 + 0.5, 0.0, 1.0)
	_sun.rotation_degrees = Vector3(-25.0 - 40.0 * light, 140.0 + _day * 60.0, 0)
	_sun.light_energy = lerpf(0.25, 1.7, light)
	_sun.light_color = Color(0.6, 0.7, 1.0).lerp(Color(1.0, 0.95, 0.85), light)
	var fog: Color = Land.BIOMES[_biome if _biome != "" else "village"].fog
	fog = fog * lerpf(0.16, 0.8, light)
	fog.a = 1.0
	_env.fog_light_color = _env.fog_light_color.lerp(fog, k)
	_env.ambient_light_energy = lerpf(0.5, 1.3, light)
	_sky.sky_top_color = Color(0.02, 0.03, 0.08).lerp(Color(0.2, 0.38, 0.7), light)
	_sky.sky_horizon_color = _env.fog_light_color
	_sky.ground_horizon_color = _env.fog_light_color
	_sky.ground_bottom_color = _env.fog_light_color.darkened(0.5)


func _update_camera(delta: float) -> void:
	var showcase: bool = hud != null and hud.screen in ["bag", "shop"]
	var yaw := cam_yaw + (PI + 0.55 + sin(_t * 0.25) * 0.35 if not started else 0.0)
	var back := Vector3(sin(yaw), 0, cos(yaw))
	var d := 3.3 if showcase else 6.6
	var want := hero_pos + back * d + Vector3(0, 1.35 if showcase else 3.3, 0)
	want.y = maxf(want.y, Land.height(want.x, want.z) + 1.0)
	cam.position = cam.position.lerp(want, clampf(delta * 8.0, 0.0, 1.0))
	cam.look_at(hero_pos + Vector3(0, 1.15 if showcase else 1.6, 0))
	cam.h_offset = lerpf(cam.h_offset, 1.45 if showcase else 0.0, clampf(delta * 8.0, 0.0, 1.0))
	if _show_light:
		_show_light.visible = showcase


func _check_surroundings(delta: float) -> void:
	near = {}
	var best := 3.0
	var foe_close := false
	var now := Time.get_ticks_msec()
	for e in ents:
		var d: float = Vector2(e.pos.x - hero_pos.x, e.pos.z - hero_pos.z).length()
		if e.type == "foe":
			if e.node == null and d < 60.0:
				var v := PlaceholderVisual.new()
				add_child(v)
				var f: Dictionary = Land.FOES[e.wild]
				v.configure(EnemyDef.make_wild(e.wild).look)
				v.position = e.pos
				e.node = v
			elif e.node != null and d > 75.0:
				(e.node as Node).queue_free()
				e.node = null
			if e.node == null:
				continue
			var v2: PlaceholderVisual = e.node
			var home_d: float = (e.pos as Vector3).distance_to(e.home)
			var walking := 0.0
			if d < 11.0 and home_d < 30.0 and _bot not in ["gather", "pvp_a", "pvp_b"]:
				var to: Vector3 = (hero_pos - e.pos)
				to.y = 0
				e.pos += to.normalized() * 2.6 * delta
				v2.rotation.y = atan2(-to.x, -to.z)
				walking = 0.7
			elif home_d > 1.0 and d > 16.0:
				var back: Vector3 = (e.home - e.pos)
				back.y = 0
				e.pos += back.normalized() * 1.8 * delta
				v2.rotation.y = atan2(-back.x, -back.z)
				walking = 0.5
			e.pos.y = Land.walk_height(e.pos.x, e.pos.z)
			v2.position = e.pos
			v2.set_walk(walking)
			if d < 8.0:
				foe_close = true
			if d < 2.5 and _bot not in ["gather", "pvp_a", "pvp_b"]:
				_start_duel(e)
				return
		elif e.type == "beast":
			_tick_beast(e, d, delta)
		elif e.type == "node":
			if e.depleted and Run.respawn_due(e.id):
				e.depleted = false
				e.charges = int(Land.NODES[e.node_id].charges)
				(e.full as Node3D).visible = true
				(e.empty as Node3D).visible = false
			if not e.depleted and d < best:
				best = d
				near = e
		elif d < best:
			best = d
			near = e
	if near.is_empty() and _can_shoot():
		var shot := 17.0
		for e in ents:
			if e.type == "beast":
				var bd: float = (e.pos as Vector3).distance_to(hero_pos)
				if bd < shot:
					shot = bd
					near = e
	var here: String = near.get("id", "") if near.get("type", "") in ["spot", "tower"] else ""
	if here != _reached:
		_reached = here
		if here != "":
			Quests.on_reach(here)
	if not foe_close:
		_last_safe = hero_pos


func ground_y(p: Vector3) -> float:
	return Land.walk_height(p.x, p.z)


func in_zone() -> bool:
	return _biome == "ashlands"


func _publish(delta: float) -> void:
	_pub_t -= delta / maxf(Engine.time_scale, 0.05)
	if _pub_t > 0.0 or not started:
		return
	_pub_t = 0.3 if stick.length() > 0.1 or _bot != "" else 1.5
	Online.publish_state(_my_state())


func _tick_remote(delta: float) -> void:
	var changed := false
	for id in Online.players:
		var p: Dictionary = Online.players[id]
		if p.get("tw", false) or not p.has("x"):
			continue
		var target := Vector3(float(p.x), 0, float(p.z))
		target.y = Land.walk_height(target.x, target.z)
		if not _remote.has(id):
			if target.distance_to(hero_pos) > 95.0:
				continue
			var v := PlaceholderVisual.new()
			v.has_shield = true
			add_child(v)
			v.position = target
			_remote[id] = {"id": id, "type": "player", "pos": target, "node": v, "label": "", "height": 2.4, "eq": ""}
			changed = true
		var e: Dictionary = _remote[id]
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
		if node.get_parent() != self:
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
	for id in _remote.keys():
		var gone: bool = not Online.players.has(id) or Online.players[id].get("tw", false)
		if gone or (_remote[id].pos as Vector3).distance_to(hero_pos) > 110.0:
			if (_remote[id].node as Node).get_parent() == self:
				(_remote[id].node as Node).queue_free()
				_remote.erase(id)
				changed = true
	if changed:
		_collect_ents()
	if _bot == "pvp_a" and duel == null and not _remote.is_empty():
		_pvp_ask_t -= delta
		if _pvp_ask_t <= 0.0:
			_pvp_ask_t = 3.0
			_challenge(_remote.values()[0])


func _my_state() -> Dictionary:
	return {"x": snappedf(hero_pos.x, 0.01), "z": snappedf(hero_pos.z, 0.01), "yw": snappedf(hero_yaw, 0.01),
		"cl": Run.combat_level(), "eq": Run.data.equipped, "up": Run.upgrade_level(Run.data.equipped.weapon),
		"w": Run.data.pvp_w, "l": Run.data.pvp_l, "d": duel != null, "tw": false, "zone": in_zone()}


func _my_card() -> Dictionary:
	var st := Run.stats()
	return {"hp": st.max_hp, "cl": Run.combat_level()}


func _challenge(e: Dictionary) -> void:
	if e.get("busy", false):
		Run.captions.append("They are already fighting.")
		return
	var forced: bool = in_zone() and e.get("zone", false)
	_pvp_pending = e.id
	Online.send_to(e.id, {"k": "attack" if forced else "challenge", "card": _my_card(), "st": _my_state()})
	Run.captions.append("You fall on them, sword out." if forced else "Challenge sent. Waiting for their answer.")


func _busy() -> bool:
	return duel != null or hud.screen != "" or _leaving or not started


func _net_message(from: String, m: Dictionary) -> void:
	if m.get("st") is Dictionary and not Online.players.has(from):
		var st: Dictionary = m.st
		st.seen = Time.get_ticks_msec()
		st.n = m.get("n", "?")
		Online.players[from] = st
	if duel != null and not duel.pvp.is_empty():
		return
	var who := String(m.get("n", "Someone")).left(16)
	match String(m.get("k", "")):
		"challenge":
			if _busy() and _bot == "":
				Online.send_to(from, {"k": "busy"})
			elif _bot == "pvp_b":
				pvp_answer("pvp:accept:" + from, m.get("card", {}))
			else:
				_pending_card = m.get("card", {})
				hud.talk({"name": who, "lines": ["%s, combat level %d, challenges you to a duel. Nothing is at stake but honour." % [who, int(m.get("card", {}).get("cl", 1))]],
					"choices": [["Accept.", "pvp:accept:" + from], ["Decline.", "pvp:decline:" + from]]})
		"attack":
			if _busy() or not in_zone():
				Online.send_to(from, {"k": "busy"})
			else:
				Online.send_to(from, {"k": "accept", "card": _my_card(), "zone": true})
				hud.announce("%s attacks!" % who)
				_start_pvp(from, who, m.get("card", {}), false, true)
		"accept":
			if from == _pvp_pending and duel == null:
				_pvp_pending = ""
				_start_pvp(from, who, m.get("card", {}), true, m.get("zone", false))
		"decline":
			if from == _pvp_pending:
				_pvp_pending = ""
				Run.captions.append("%s declines." % who)
		"busy":
			if from == _pvp_pending:
				_pvp_pending = ""
				Run.captions.append("%s cannot fight right now." % who)

var _pending_card := {}


func pvp_answer(action: String, card := {}) -> void:
	var parts := action.split(":")
	var from := parts[2]
	if card.is_empty():
		card = _pending_card
	if parts[1] != "accept" or duel != null:
		Online.send_to(from, {"k": "decline"})
		return
	Online.send_to(from, {"k": "accept", "card": _my_card(), "zone": false})
	var who := String(Online.players.get(from, {}).get("n", "Challenger"))
	_start_pvp(from, who, card, false, false)


func _start_pvp(id: String, who: String, card: Dictionary, i_go_first: bool, zone: bool) -> void:
	if duel != null:
		return
	if not _remote.has(id):
		_tick_remote(0.0)
	if not _remote.has(id):
		return
	_gather = {}
	gather_progress = -1.0
	stick = Vector2.ZERO
	hero.set_walk(0.0)
	var e: Dictionary = _remote[id]
	(e.node as PlaceholderVisual).set_walk(0.0)
	duel = Duel.new()
	duel.host = self
	duel.player = hero
	duel.foes = [{"node": e.node, "def": null, "enc": {}}]
	duel.pvp = {"id": id, "name": who, "first": i_go_first, "zone": zone, "max_hp": float(card.get("hp", 100.0))}
	hud.screen = ""
	hud.visible = false
	add_child(duel)


func _pvp_done(won: bool, d: Duel) -> void:
	hero.play(&"idle")
	hero.rotation = Vector3(0, hero_yaw, 0)
	var e: Dictionary = _remote.get(d.pvp.id, {})
	if not e.is_empty() and is_instance_valid(e.node):
		(e.node as PlaceholderVisual).play(&"idle")
		(e.node as PlaceholderVisual).rotation = Vector3.ZERO
	if won or not d.pvp.zone:
		hero_pos = hero.global_position
	else:
		hero_pos = Land.START
		cam_yaw = 0.0
		Run.captions.append("You wake by the hearth. %s took %d of your gold." % [d.pvp.name, int(d.reward.get("lost_gold", 0))])
	hero_pos.y = Land.walk_height(hero_pos.x, hero_pos.z)
	hero.position = hero_pos
	_last_safe = hero_pos
	_update_camera(1.0)
	Run.data.ow_x = hero_pos.x
	Run.data.ow_z = hero_pos.z
	Run.save()
	if _bot.begins_with("pvp"):
		print("PVP done won=%s gold=%d record=%d-%d" % [won, Run.data.gold, Run.data.pvp_w, Run.data.pvp_l])
		get_tree().create_timer(1.0).timeout.connect(func(): get_tree().quit())


func _tick_walkers(delta: float) -> void:
	for w in _walkers:
		var v: PlaceholderVisual = w.node
		if float(w.pause) > 0.0 or hud.screen == "talk":
			w.pause = float(w.pause) - delta
			v.set_walk(0.0)
			continue
		var goal: Vector2 = w.loop[int(w.at)]
		var to := Vector3(goal.x - w.pos.x, 0, goal.y - w.pos.z)
		if to.length() < 0.6:
			w.at = (int(w.at) + 1) % (w.loop as Array).size()
			w.pause = randf_range(1.0, 5.0)
			continue
		w.pos += to.normalized() * 1.5 * delta
		w.pos.y = Land.walk_height(w.pos.x, w.pos.z)
		v.position = w.pos
		v.rotation.y = lerp_angle(v.rotation.y, atan2(-to.x, -to.z), clampf(delta * 6.0, 0.0, 1.0))
		v.set_walk(0.45)


func _tick_beast(e: Dictionary, d: float, delta: float) -> void:
	var n: Node3D = e.node
	var speed := 1.3
	if d < 7.0 and float(e.flee) <= 0.0:
		var away: Vector3 = e.pos - hero_pos
		away.y = 0
		e.goal = e.pos + away.normalized() * 22.0
		e.flee = 2.6
	if float(e.flee) > 0.0:
		e.flee = float(e.flee) - delta
		speed = 6.4
	var to: Vector3 = e.goal - e.pos
	to.y = 0
	if to.length() < 0.5:
		e.wait = float(e.wait) - delta
		if float(e.wait) <= 0.0:
			e.wait = randf_range(2.0, 6.0)
			e.goal = e.home + Vector3(randf_range(-9, 9), 0, randf_range(-9, 9))
		return
	var next: Vector3 = e.pos + to.normalized() * speed * delta
	if _blocked(next):
		e.goal = e.pos
		return
	e.pos = next
	e.pos.y = Land.walk_height(e.pos.x, e.pos.z) + absf(sin(_t * (14.0 if speed > 2.0 else 6.0))) * 0.06
	n.position = e.pos
	n.rotation.y = lerp_angle(n.rotation.y, atan2(-to.x, -to.z), clampf(delta * 8.0, 0.0, 1.0))


func _can_shoot() -> bool:
	var r: String = Run.data.equipped.get("ranged", "")
	return r == "throwing_knives" or (r == "hunters_bow" and Run.mat("arrow") > 0)


func _shoot(e: Dictionary) -> void:
	var d: float = (e.pos as Vector3).distance_to(hero_pos)
	var to: Vector3 = e.pos - hero_pos
	hero_yaw = atan2(-to.x, -to.z)
	hero.play(&"slash", 3, 0.15)
	if Run.data.equipped.ranged == "hunters_bow":
		Run.add_mat("arrow", -1)
	var chance := clampf(0.5 + 0.02 * Run.skill("archery") - d * 0.012, 0.2, 0.95)
	if randf() > chance:
		Run.xp_log.append("Missed")
		Run.train("archery", 6)
		e.flee = 0.0
		_tick_beast(e, 0.0, 0.0)
		return
	Run.train("archery", 34 if e.beast == "deer" else 46)
	Run.add_mat("raw_meat", 1)
	Run.add_mat("hide", 1 + (randi() % 2))
	Run.xp_log.append("Raw meat and hide")
	Run.set_respawn(e.id, 120000)
	(e.node as Node3D).queue_free()
	for k in _chunks:
		_chunks[k].ents.erase(e)
	_collect_ents()
	near = {}


func _start_duel(e: Dictionary) -> void:
	if duel != null:
		return
	_gather = {}
	gather_progress = -1.0
	stick = Vector2.ZERO
	hero.set_walk(0.0)
	var group: Array = [e]
	for o in ents:
		if o.type == "foe" and o != e and o.node != null and group.size() < 3 and (o.pos as Vector3).distance_to(e.pos) < 11.0:
			group.append(o)
	var foes: Array = []
	for g in group:
		(g.node as FighterVisual).set_walk(0.0)
		foes.append({"node": g.node, "def": EnemyDef.make_wild(g.wild), "enc": {"id": g.id, "wild": g.wild, "biome": g.biome}})
	_duel_ents = group
	Run.data.ow_x = _last_safe.x
	Run.data.ow_z = _last_safe.z
	Run.save()
	duel = Duel.new()
	duel.host = self
	duel.player = hero
	duel.foes = foes
	hud.visible = false
	add_child(duel)


func duel_done(won: bool, d: Duel) -> void:
	duel = null
	hud.visible = true
	cam.make_current()
	Engine.time_scale = 4.0 if _bot in ["tour", "gather"] else 1.0
	if not d.pvp.is_empty():
		_pvp_done(won, d)
		return
	for rec in d.slain:
		for e in _duel_ents:
			if e.node == rec.node:
				for k in _chunks:
					_chunks[k].ents.erase(e)
				(e.node as Node).queue_free()
				e.node = null
	for e in _duel_ents:
		if e.node != null:
			var v: FighterVisual = e.node
			v.set_tell(Color.BLACK, 0.1)
			v.play(&"idle")
			e.pos = e.home
			v.position = e.pos
	_duel_ents = []
	_collect_ents()
	hero.play(&"idle")
	hero.rotation = Vector3(0, hero_yaw, 0)
	if won:
		hero_pos = hero.global_position
	else:
		hero_pos = Land.START
		cam_yaw = 0.0
	hero_pos.y = Land.walk_height(hero_pos.x, hero_pos.z)
	hero.position = hero_pos
	_last_safe = hero_pos
	_update_camera(1.0)
	Run.data.ow_x = hero_pos.x
	Run.data.ow_z = hero_pos.z
	Run.save()
	if _bot == "tour" and not won:
		print("TOUR hero fell in the land")


func prompt() -> String:
	if near.is_empty() or not _gather.is_empty():
		return ""
	if near.type == "node":
		return Land.NODES[near.node_id].verb
	if near.type == "player":
		return "ATTACK" if in_zone() and near.get("zone", false) else "DUEL"
	if near.type == "station":
		return {"smithing": "FORGE", "cooking": "COOK", "alchemy": "BREW", "fletching": "FLETCH"} [near.skill]
	return PROMPTS.get(near.type, "")


func interact() -> void:
	if near.is_empty() or _leaving:
		return
	var e := near
	match e.type:
		"node":
			var def: Dictionary = Land.NODES[e.node_id]
			if Run.skill(def.skill) < int(def.level):
				Run.captions.append("%s needs %s level %d. Yours is %d." % [def.label, Craft.SKILLS[def.skill].name, def.level, Run.skill(def.skill)])
				return
			_gather = {"e": e, "t": 0.0}
			gather_label = def.verb
			var to: Vector3 = e.pos - hero_pos
			if e.node != null and def.skill == "fishing":
				to = (e.node as Node3D).position - hero_pos
			hero_yaw = atan2(-to.x, -to.z)
		"smith":
			var said := Quests.talk("smith")
			if said.lines.is_empty():
				hud.open("shop")
			else:
				said.choices.append(["Show me your wares.", "shop"])
				hud.talk(said)
		"npc":
			var words := Quests.talk(e.id)
			if words.lines.is_empty():
				words.lines = ["Good day to you."]
			hud.talk(words)
		"beast":
			_shoot(e)
		"player":
			_challenge(e)
			return
		"spot":
			match e.id:
				"circle":
					if int(Run.data.potions) < 2:
						Run.data.potions = 2
					Run.captions.append("The standing stones hum underfoot. You feel rested; your flasks are full.")
				"watch": Run.captions.append("A watchtower, long fallen. From its stump you can see the whole of Greywood.")
				"shrine": Run.captions.append("A shrine of marsh-stone. A green light burns in it.")
				"altar": Run.captions.append("The broken altar. Thirty names are cut into its side, all in one hand.")
		"station":
			hud.open_craft(e.skill)
		"store":
			hud.open("store")
		"task":
			_task_talk()
		"brazier":
			if int(Run.data.potions) < 2:
				Run.data.potions = 2
				Run.captions.append("You rest by the hearth. Your flasks are refilled.")
			else:
				Run.captions.append("The hearth is warm. Meals cooked on a fire give extra health in your next fight.")
		"chest":
			Run.data.ow_opened.append(e.id)
			Run.data.gold += int(e.gold)
			Run.add_mat("cinder", 1)
			Run.captions.append("The chest holds %d gold and a cinder shard." % e.gold)
			(e.node as Node3D).queue_free()
			for k in _chunks:
				_chunks[k].ents.erase(e)
			_collect_ents()
			near = {}
		"stones":
			if Run.skill("agility") < 10:
				Run.captions.append("The stones are slick. Agility level 10 would see you across. Yours is %d." % Run.skill("agility"))
				return
			var east := hero_pos.x < Land.river_x(Land.STONES_Z)
			hero_pos = Vector3(Land.river_x(Land.STONES_Z) + (9.0 if east else -9.0), 0, Land.STONES_Z)
			Run.train("agility", 60)
		"tower":
			_leaving = true
			Run.data.in_tower = true
			Run.data.floor = 1
			Run.spawn = "entrance"
			Run.data.tower_slain = []
			Run.captions.append(Story.inscription(1, int(Run.data.bloodline)))
			if Run.combat_level() < 12:
				Run.captions.append("Everything here is far stronger than the land outside. Leave by the gate behind you if it is too much.")
			Run.data.ow_x = hero_pos.x
			Run.data.ow_z = hero_pos.z + 6.0
			Run.save()
			get_tree().change_scene_to_file.call_deferred("res://scenes/world.tscn")
			return
	Run.save()


func _tick_gather(delta: float) -> void:
	if _gather.is_empty():
		gather_progress = -1.0
		return
	var e: Dictionary = _gather.e
	var def: Dictionary = Land.NODES[e.node_id]
	var tool_tier := int(Run.data.tools.get(def.tool, 0)) if def.tool != "" else 0
	var period := (0.7 if def.skill == "foraging" else 1.6) / (1.0 + 0.3 * tool_tier)
	if _gather.t == 0.0:
		hero.play(&"slash", 3 if def.skill != "fishing" else 2, period * 0.5)
	_gather.t += delta
	gather_progress = _gather.t / period
	if _gather.t < period:
		return
	_gather.t = 0.0
	var lvl := Run.skill(def.skill)
	var chance := clampf(0.5 + 0.02 * (lvl - int(def.level)) + 0.1 * tool_tier, 0.3, 0.97)
	if def.skill == "foraging" or randf() < chance:
		Run.add_mat(def.mat, 1)
		Run.train(def.skill, int(def.xp))
		e.charges -= 1
	if e.charges <= 0:
		e.depleted = true
		Run.set_respawn(e.id, 45000 if def.skill == "foraging" else 60000)
		(e.full as Node3D).visible = false
		(e.empty as Node3D).visible = true
		_gather = {}
		gather_progress = -1.0
		hero.play(&"idle")
		Run.save()


func _task_talk() -> void:
	var task: Dictionary = Run.data.task
	if task.is_empty():
		var options: Array = []
		for id in Land.FOES:
			if int(Land.FOES[id].level) <= Run.combat_level() * 2 + 6:
				options.append(id)
		var pick: String = options[maxi(options.size() - 1 - (randi() % 2), 0)]
		var f: Dictionary = Land.FOES[pick]
		Run.data.task = {"foe": pick, "need": 3, "have": 0, "gold": int(f.level) * 12 + 40, "xp": int(f.level) * 14 + 40}
		var where := Land.region_of(pick)
		Run.captions.append("Taskmaster: \"Bring down three of the %ss in %s. There is %d gold in it.\"" % [f.name, where, Run.data.task.gold])
	elif int(task.have) >= int(task.need):
		Run.data.gold += int(task.gold)
		Run.train("slaying", int(task.xp))
		Run.captions.append("Taskmaster: \"Clean work. Here is your %d gold. Come back for another.\"" % task.gold)
		Run.data.task = {}
	else:
		Run.captions.append("Taskmaster: \"%d of %d %ss so far. Keep at it.\"" % [task.have, task.need, Land.FOES[task.foe].name])


func refresh_hero() -> void:
	hero.configure(Run.look())
	hero.flash(Color(1.0, 0.85, 0.5))


static func build_map() -> ImageTexture:
	if map_tex == null:
		var w := int(Land.X_MAX * 2.0 / 4.0)
		var h := int((Land.Z_MAX - Land.Z_MIN) / 4.0)
		var img := Image.create(w, h, false, Image.FORMAT_RGB8)
		for py in h:
			for px in w:
				var x := -Land.X_MAX + px * 4.0 + 2.0
				var z := Land.Z_MIN + py * 4.0 + 2.0
				var c := Land.ground_color(x, z).lightened(0.12)
				if Land.is_water(x, z):
					c = Color(0.2, 0.42, 0.6)
				img.set_pixel(px, py, c)
		map_tex = ImageTexture.create_from_image(img)
	return map_tex


func _walk_to(target: Vector3, delta: float) -> Vector3:
	var to := target - hero_pos
	to.y = 0
	if _stuck > 0.4:
		to = to.rotated(Vector3.UP, 1.3)
		if _stuck > 1.5:
			_stuck = 0.0
	return to.normalized()


func _bot_dir(delta: float) -> Vector3:
	if _bot.begins_with("pvp"):
		return Vector3.ZERO
	if _bot == "tour":
		var gate := Vector3(Land.TOWER_GATE.x, 0, Land.TOWER_GATE.y + 2.0)
		if not near.is_empty() and near.type == "tower":
			interact()
			return Vector3.ZERO
		return _walk_to(gate, delta)

	if not _gather.is_empty():
		return Vector3.ZERO
	_bot_wait -= delta
	if _bot_wait > 0.0:
		return Vector3.ZERO
	if _bot_step >= 3:
		var made: Array = []
		for r in Craft.RECIPES:
			if Craft.make(r):
				made.append(r.name)
		_task_talk()
		print("GATHER mats=%s made=%s total_level=%d task=%s" % [Run.data.mats, made, Run.total_level(), Run.data.task.get("foe", "")])
		get_tree().quit()
		return Vector3.ZERO
	var best := {}
	var bd := 9999.0
	for e in ents:
		if e.type == "node" and not e.depleted and Run.skill(Land.NODES[e.node_id].skill) >= int(Land.NODES[e.node_id].level):
			var d: float = (e.pos as Vector3).distance_to(hero_pos)
			if d < bd:
				bd = d
				best = e
	if best.is_empty():
		return _walk_to(hero_pos + Vector3(-30, 0, 0), delta)
	if bd < 2.8:
		near = best
		interact()
		_bot_step += 1
		_bot_wait = 0.5
		return Vector3.ZERO
	return _walk_to(best.pos, delta)


func _take_shot_if_due() -> void:
	if _shot_path == "":
		return
	if _shot_when == "pvp":
		return
	if _shot_when == "players" and hud.screen == "" and _t > 3.0:
		hud.open("players")
	if _shot_when in ["players", "online"] and _t < 4.5:
		return
	if _shot_when == "fight":
		for e in ents:
			if e.type == "foe" and e.node != null and _t > 0.5:
				hero_pos = e.pos + Vector3(0, 0, 2.2)
				_shot_path = ""
				return
		return
	if _shot_when in ["skills", "store", "map", "quests", "perks"] and hud.screen == "" and _t > 0.4:
		hud.open(_shot_when)
	if _shot_when == "talk" and hud.screen == "" and _t > 0.4:
		hud.talk(Quests.talk("elder"))
		hud._talk.i = 1
	if _shot_when == "craft" and hud.screen == "" and _t > 0.4:
		hud.open_craft("smithing")
	if _t < 1.6:
		return
	var path := _shot_path
	_shot_path = ""
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
