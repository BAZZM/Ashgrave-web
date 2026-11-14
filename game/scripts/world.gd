class_name World
extends Node3D

const SPEED := 4.6
const GoldenBot := preload("res://scripts/overworld_bot.gd")
const WallBot := preload("res://scripts/world_bot.gd")
## Longest single move test (units): about one 60 fps walking step (4.6 / 60), so a long
## frame moves the hero as that many short frames would. That is well under the thinnest
## blocked strip between walkable areas (0.5, on tier 2), so a long frame cannot carry the
## hero across a wall or stop them a whole long step short of one. At 60 fps it is one test.
const SUB_STEP := 0.08
## Spacing (units) at which room edges are sampled to lay the walls.
const WALL_RES := 0.05
## Game seconds pushed without moving before the safety net checks for a way out.
const STUCK_AFTER := 0.5
## Art Bible section 4, Tower column (G1). Ambient is the tier's flat colour (Tiers.THEMES amb).
const LIGHT_AMBIENT := 0.4
const LIGHT_FOG_DENSITY := 0.03
const LIGHT_MOON := 0.35
const LIGHT_MOON_OPEN := 0.6  # the Rookery, which is open to the sky
const LIGHT_SHADOW_DISTANCE := 24.0
const LIGHT_TORCH_ENERGY := 2.8
const LIGHT_TORCH_RANGE := 7.0
const PROMPTS := {"chest": "OPEN", "smith": "TRADE", "brazier": "REST", "relic": "TAKE", "exit": "ASCEND", "entry": "DESCEND"}

var is_land := false
var gather_progress := -1.0
var gather_label := ""
var duel: Duel
var _duel_ents: Array = []
var _pub_t := 0.0
var tier := 1
var theme: Dictionary
var rects: Array = []
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

var _bot := ""
var _shot_path := ""
var _shot_when := ""
var _t := 0.0
var _last_safe := Vector3.ZERO
var _leaving := false
var _stone: StandardMaterial3D
var _show_light: OmniLight3D
## Tower wall test bot (`--towerbot=walls`, see world_bot.gd); null in normal play.
var _wbot: RefCounted
var quest_run := false
var _stuck_t := 0.0
## Recent safe spots the hero walked through on this tier (oldest first), for unstuck().
var _trail: Array = []
## Where the hero stood when the current duel began (walkable), for putting them back after.
var _pre_duel := Vector3.ZERO
## Times the safety net or unstuck() moved the hero (the test bot reads it).
var unstuck_count := 0


func _ready() -> void:
	Run.ensure_loaded()
	Online.start()
	Run.data.in_tower = true
	var direct_duel := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autoplay="):
			_bot = a.trim_prefix("--autoplay=")
			direct_duel = _bot != "tour"
			if _bot == "tour" and not Run.title_seen:
				Run.no_save = true
				Run.data = Run.defaults()
				Run.data.tutorial_done = true
				Run.title_seen = true
		elif a.begins_with("--floor=") and not Run.title_seen:
			Run.data.floor = int(a.trim_prefix("--floor="))
			Run.data.unlocked = maxi(int(Run.data.unlocked), int(Run.data.floor))
		elif a.begins_with("--shot="):
			_shot_path = a.trim_prefix("--shot=")
			Run.no_save = true
		elif a.begins_with("--equip=") and not Run.title_seen:
			for id in a.trim_prefix("--equip=").split(","):
				Run.data.inventory.append(id)
				Run.equip(id)
				if Items.WEAPONS.has(id):
					Run.data.upgrades[id] = 2
		elif a.begins_with("--shot-when="):
			_shot_when = a.trim_prefix("--shot-when=")
		elif a.begins_with("--golden="):
			GoldenBot.golden_world(self, a.trim_prefix("--golden="))
		elif a.begins_with("--towerbot="):
			_wbot = WallBot.new(self, a.trim_prefix("--towerbot="))
		elif a.begins_with("--questbot=") and a.trim_prefix("--questbot=") == "act1":
			# The quest bot (world_bot.gd, mode act1) drives the tower with the tour bot's movement.
			_wbot = WallBot.new(self, "act1")
			direct_duel = false
			quest_run = true
	if quest_run:
		direct_duel = false
		_bot = "tour"
	if direct_duel or _shot_when in ["windup", "open", "result", "tutorial"]:
		get_tree().change_scene_to_file.call_deferred("res://scenes/duel.tscn")
		return
	if _shot_path != "" and _shot_when != "title":
		Run.title_seen = true
		Run.data.gold = 700
	Engine.time_scale = 4.0 if _bot == "tour" else 1.0
	AudioServer.set_bus_mute(0, not Run.data.sound)
	Run.apply_web_settings(get_viewport())

	tier = int(Run.data.floor)
	theme = Tiers.THEMES[tier]
	rects = Tiers.rects(tier)
	_build_env()
	_build_geometry()
	_spawn_entities()

	hero = PlaceholderVisual.new()
	hero.has_shield = true
	add_child(hero)
	hero.configure(Run.look())
	if Run.spawn is Vector3:
		hero_pos = _settle(Run.spawn)
	elif Run.spawn == "exit":
		hero_pos = Tiers.EXIT + Vector3(0, 0, 4.0)
		hero_yaw = PI
		cam_yaw = PI
	else:
		hero_pos = Tiers.ENTRANCE
	if _shot_path != "" and _shot_when == "world":
		hero_pos = Vector3(0, 0, -4.0)
	_last_safe = hero_pos
	hero.position = hero_pos
	hero.rotation.y = hero_yaw

	var lantern := OmniLight3D.new()
	lantern.position = Vector3(0, 2.6, 0.6)
	lantern.light_color = Color(1.0, 0.92, 0.8)
	lantern.light_energy = 1.3
	lantern.omni_range = 7.0
	hero.add_child(lantern)

	cam = Camera3D.new()
	cam.fov = 60.0
	add_child(cam)
	cam.make_current()

	_show_light = OmniLight3D.new()
	_show_light.position = Vector3(-0.6, 0.6, 0.2)
	_show_light.light_color = Color(1.0, 0.95, 0.88)
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
	started = Run.title_seen
	_update_camera(1.0)
	if _bot == "tour":
		print("WORLD tier=%d loop=%d bloodline=%d combat=%d gold=%d" % [tier, Run.data.loop, Run.data.bloodline, Run.combat_level(), Run.data.gold])
		if int(Run.data.loop) >= 1:
			print("TOUR DONE")
			get_tree().quit()


func place_name() -> String:
	return theme.name


func begin() -> void:
	if started:
		return
	started = true
	Run.title_seen = true
	Run.captions.append(Story.inscription(tier, int(Run.data.bloodline)))
	Story.read_inscription(tier, int(Run.data.bloodline))
	Run.save()


func _build_env() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = theme.sky_top
	sky_mat.sky_horizon_color = theme.sky_low
	sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.03)
	sky_mat.ground_horizon_color = (theme.sky_low as Color).darkened(0.3)
	sky_mat.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	Run.quality_tune_sky(sky)
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = theme.amb
	env.ambient_light_energy = LIGHT_AMBIENT
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = not OS.has_feature("web")
	env.fog_enabled = true
	env.fog_light_color = theme.fog
	env.fog_density = LIGHT_FOG_DENSITY
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-52, 140, 0)
	moon.light_color = Color(0.7, 0.78, 1.0)
	moon.light_energy = LIGHT_MOON if theme.special != "open" else LIGHT_MOON_OPEN
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = LIGHT_SHADOW_DISTANCE
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	Run.quality_tune_light(moon)
	add_child(moon)


func _mesh(mesh: Mesh, pos: Vector3, mat: Material, parent: Node3D = null, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot
	mi.material_override = mat
	(parent if parent else self).add_child(mi)
	return mi


func _glow_mat(c: Color, energy := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


func _torch(pos: Vector3, energy := LIGHT_TORCH_ENERGY, rng := LIGHT_TORCH_RANGE) -> void:
	var post := MeshKit.lathe([[0.12, 0.0], [0.05, 0.1], [0.045, 1.9], [0.16, 2.0], [0.2, 2.15]], 8)
	_mesh(post, pos, _stone)
	var orb := SphereMesh.new()
	orb.radius = 0.14
	orb.height = 0.28
	_mesh(orb, pos + Vector3(0, 2.25, 0), _glow_mat(theme.light))
	var l := OmniLight3D.new()
	l.position = pos + Vector3(0, 2.5, 0)
	l.light_color = theme.light
	l.light_energy = energy
	l.omni_range = rng
	add_child(l)


func _build_geometry() -> void:
	_stone = StandardMaterial3D.new()
	_stone.albedo_color = theme.stone
	_stone.roughness = 0.92
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = (theme.stone as Color).lightened(0.08)
	floor_mat.roughness = 0.85
	var wall_h: float = theme.wall
	var wall_xf: Array = []
	for i in rects.size():
		var r: Rect2 = rects[i]
		var slab := BoxMesh.new()
		slab.size = Vector3(r.size.x, 0.5, r.size.y)
		_mesh(slab, Vector3(r.get_center().x, -0.25 - i * 0.003, r.get_center().y), floor_mat)

	for piece in _wall_layout():
		var fp: Rect2 = piece
		var c := fp.get_center()
		wall_xf.append(Transform3D(Basis.from_scale(Vector3(fp.size.x, 1, fp.size.y)), Vector3(c.x, wall_h * 0.5, c.y)))
	var wall := BoxMesh.new()
	wall.size = Vector3(1.0, wall_h, 1.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = wall
	mm.instance_count = wall_xf.size()
	for i in wall_xf.size():
		mm.set_instance_transform(i, wall_xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _stone
	add_child(mmi)

	var m := Tiers.mirror(tier)

	if theme.special != "open":
		var col := MeshKit.lathe([[0.55, 0.0], [0.5, 0.25], [0.36, 0.4], [0.33, wall_h - 0.5], [0.5, wall_h - 0.2], [0.55, wall_h]], 10)
		for p in [Vector3(-5, 0, -4), Vector3(5, 0, -4), Vector3(-5, 0, 4), Vector3(5, 0, 4), Vector3(-7, 0, -33), Vector3(7, 0, -33), Vector3(-7, 0, -43), Vector3(7, 0, -43)]:
			_mesh(col, p, _stone)
	for p in [Vector3(-6, 0, 0), Vector3(6, 0, -3), Vector3(-4.5, 0, -21.5), Vector3(4.5, 0, -14.5), Vector3(-8, 0, -38), Vector3(8, 0, -38), Vector3(-15 * m, 0, -15)]:
		_torch(p)
	match theme.special:
		"water":
			var water := StandardMaterial3D.new()
			water.albedo_color = Color(0.1, 0.4, 0.42, 0.45)
			water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			water.metallic = 0.6
			water.roughness = 0.08
			for r2 in [rects[2], rects[8]]:
				var pm := PlaneMesh.new()
				pm.size = (r2 as Rect2).size
				_mesh(pm, Vector3(r2.get_center().x, 0.06, r2.get_center().y), water)
		"forge":
			var lava := _glow_mat(Color(1.0, 0.35, 0.05), 2.5)
			for z in [-10.0, -27.0]:
				for sx in [-1.0, 1.0]:
					var strip := BoxMesh.new()
					strip.size = Vector3(0.35, 0.06, 8.0)
					_mesh(strip, Vector3(1.6 * sx, 0.02, z), lava)
			var anvil := BoxMesh.new()
			anvil.size = Vector3(1.4, 0.9, 0.7)
			_mesh(anvil, Vector3(14 * m, 0.45, -21.5), _stone)
		"throne":
			var seat := BoxMesh.new()
			seat.size = Vector3(2.6, 1.0, 1.6)
			_mesh(seat, Vector3(6.5, 0.5, -43.5), _stone)
			var back := BoxMesh.new()
			back.size = Vector3(2.6, 5.0, 0.5)
			_mesh(back, Vector3(6.5, 2.5, -44.4), _stone)
			var pyre := SphereMesh.new()
			pyre.radius = 1.1
			pyre.height = 2.6
			_mesh(pyre, Vector3(-6.5, 1.0, -43.5), _glow_mat(Color(1.0, 0.45, 0.1), 4.0))
			var fl := OmniLight3D.new()
			fl.position = Vector3(-6.5, 3.0, -43)
			fl.light_color = Color(1.0, 0.5, 0.15)
			fl.light_energy = 5.0
			fl.omni_range = 16.0
			add_child(fl)


## Point on edge `edge` (0 top, 1 bottom, 2 left, 3 right) of r, `along` from its start,
## moved `out` along the edge's outward normal.
func _edge_point(r: Rect2, edge: int, along: float, out: float) -> Vector2:
	match edge:
		0: return Vector2(r.position.x + along, r.position.y - out)
		1: return Vector2(r.position.x + along, r.end.y + out)
		2: return Vector2(r.position.x - out, r.position.y + along)
	return Vector2(r.end.x + out, r.position.y + along)


## Footprints (x, z) of the wall pieces: along every room edge, a wall covers exactly the
## stretches the hero cannot walk across (sampled every WALL_RES), so what is drawn is what
## blocks; it stands outside the edge, up to 0.7 thick, thinner where another room is near.
func _wall_layout() -> Array:
	var out: Array = []
	for r: Rect2 in rects:
		for edge in 4:
			var length := r.size.x if edge < 2 else r.size.y
			var n := int(ceil(length / WALL_RES))
			var h := length / n
			var run := -1
			for k in n + 1:
				var p := _edge_point(r, edge, (k + 0.5) * h, -0.01) if k < n else Vector2.ZERO
				var closed := k < n and not _walkable(Vector3(p.x, 0, p.y))
				if closed and run < 0:
					run = k
				elif not closed and run >= 0:
					out.append(_wall_piece(r, edge, run * h, k * h))
					run = -1
	return out


func _wall_piece(r: Rect2, edge: int, a0: float, a1: float) -> Rect2:
	var thick := 0.7
	for i in range(1, 8):
		var s := i * 0.1
		for a in [a0 + 0.02, (a0 + a1) * 0.5, a1 - 0.02]:
			if _inside(_edge_point(r, edge, a, s)):
				thick = minf(thick, maxf(s - 0.05, 0.05))
	var p0 := _edge_point(r, edge, a0, 0.0)
	var p1 := _edge_point(r, edge, a1, thick)
	return Rect2(Vector2(minf(p0.x, p1.x), minf(p0.y, p1.y)), (p1 - p0).abs())


func _gate(pos: Vector3, sealed: bool) -> Node3D:
	var g := Node3D.new()
	g.position = pos
	add_child(g)
	var post := BoxMesh.new()
	post.size = Vector3(0.7, 4.2, 0.7)
	_mesh(post, Vector3(-1.7, 2.1, 0), _stone, g)
	_mesh(post, Vector3(1.7, 2.1, 0), _stone, g)
	var lintel := BoxMesh.new()
	lintel.size = Vector3(4.6, 0.7, 0.9)
	_mesh(lintel, Vector3(0, 4.3, 0), _stone, g)
	var veil := StandardMaterial3D.new()
	veil.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	veil.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	veil.albedo_color = Color(1.0, 0.15, 0.1, 0.55) if sealed else Color(1.0, 0.85, 0.5, 0.3)
	veil.cull_mode = BaseMaterial3D.CULL_DISABLED
	var q := QuadMesh.new()
	q.size = Vector2(2.7, 3.9)
	_mesh(q, Vector3(0, 1.95, 0), veil, g)
	return g


func _spawn_entities() -> void:
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.9, 0.7, 0.3)
	gold.metallic = 0.9
	gold.roughness = 0.3
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.3, 0.19, 0.1)
	for src in Tiers.entities(tier):
		var e: Dictionary = src.duplicate()
		var node: Node3D = null
		match e.type:
			"foe":
				if Run.is_slain(e.id):
					continue
				var def := EnemyDef.make_encounter(e.kind, tier, int(Run.data.loop))
				var v := PlaceholderVisual.new()
				add_child(v)
				v.configure(def.look)
				v.rotation.y = PI
				node = v
				e.label = def.display_name
				e.height = 2.1 * float(def.look.scale)
			"smith":
				var s := PlaceholderVisual.new()
				add_child(s)
				s.configure({"style": "knight", "scale": 1.0, "body": Color(0.45, 0.32, 0.2), "accent": Color(0.9, 0.7, 0.3)})
				s.rotation.y = PI * 0.5 * Tiers.mirror(tier)
				node = s
				e.label = "The Smith"
				e.height = 2.3
			"brazier":
				node = Node3D.new()
				add_child(node)
				_mesh(MeshKit.lathe([[0.35, 0.0], [0.12, 0.15], [0.1, 0.8], [0.45, 1.0], [0.5, 1.15], [0.0, 1.05]], 12), Vector3.ZERO, _stone, node)
				var fire := SphereMesh.new()
				fire.radius = 0.3
				fire.height = 0.7
				_mesh(fire, Vector3(0, 1.35, 0), _glow_mat(Color(1.0, 0.6, 0.2), 4.0), node)
				var l := OmniLight3D.new()
				l.position = Vector3(0, 1.8, 0)
				l.light_color = Color(1.0, 0.6, 0.25)
				l.light_energy = 2.5
				l.omni_range = 8.0
				node.add_child(l)
				e.label = "Brazier"
				e.height = 2.0
			"chest":
				if Run.data.opened.has(e.id):
					continue
				node = Node3D.new()
				add_child(node)
				var box := BoxMesh.new()
				box.size = Vector3(1.1, 0.6, 0.7)
				_mesh(box, Vector3(0, 0.3, 0), wood, node)
				_mesh(MeshKit.lathe([[0.0, -0.56], [0.36, -0.55], [0.36, 0.55], [0.0, 0.56]], 10), Vector3(0, 0.6, 0), wood, node, Vector3(0, 0, 90))
				var band := BoxMesh.new()
				band.size = Vector3(0.12, 0.98, 0.76)
				_mesh(band, Vector3(0, 0.48, 0), gold, node)
				e.label = "Chest"
				e.height = 1.4
			"relic":
				if Run.data.relics.has(float(tier)) or Run.data.relics.has(tier):
					continue
				node = Node3D.new()
				add_child(node)
				_mesh(MeshKit.lathe([[0.0, -0.3], [0.18, 0.0], [0.0, 0.3]], 4), Vector3(0, 1.2, 0), _glow_mat(Color(0.7, 0.9, 1.0), 3.0), node)
				_mesh(MeshKit.lathe([[0.4, 0.0], [0.3, 0.1], [0.25, 0.7], [0.32, 0.8]], 8), Vector3.ZERO, _stone, node)
				var rl := OmniLight3D.new()
				rl.position = Vector3(0, 1.4, 0)
				rl.light_color = Color(0.6, 0.85, 1.0)
				rl.light_energy = 1.6
				rl.omni_range = 6.0
				node.add_child(rl)
				e.label = "Relic"
				e.height = 2.0
			"exit":
				node = _gate(e.pos + Vector3(0, 0, -0.7), int(Run.data.unlocked) <= tier)
				e.label = "Gate to " + (Tiers.THEMES[tier + 1].name if tier < Run.FLOORS else "the summit")
				e.height = 3.0
				if tier >= Run.FLOORS:
					node.queue_free()
					continue
			"entry":
				node = _gate(e.pos + Vector3(0, 0, 0.2), false)
				e.label = "Gate to " + (Tiers.THEMES[tier - 1].name if tier > 1 else "the land outside")
				e.height = 3.0
		if e.type != "exit" and e.type != "entry":
			node.position = e.pos
		e.node = node
		ents.append(e)


func _inside(p: Vector2) -> bool:
	for r in rects:
		if (r as Rect2).has_point(p):
			return true
	return false


func _walkable(p: Vector3) -> bool:
	var q := Vector2(p.x, p.z)
	var count := 0
	for r in rects:
		if (r as Rect2).grow(-0.45).has_point(q):
			return true
		if (r as Rect2).has_point(q):
			count += 1
	if count < 2:
		return false
	return true


func _process(delta: float) -> void:
	if hero == null:
		return
	if _wbot != null:
		_wbot.tick(delta)
	_pub_t -= delta
	if _pub_t <= 0.0:
		_pub_t = 3.0
		Online.publish_state({"cl": Run.combat_level(), "w": Run.data.pvp_w, "l": Run.data.pvp_l, "tw": true})
	if duel != null:
		return
	_t += delta
	_take_shot_if_due()
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
	if _bot == "tour":
		dir = _bot_dir()
	elif input.length() > 0.12:
		input = input.limit_length(1.0)
		var f := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
		var r := Vector3(cos(cam_yaw), 0, -sin(cam_yaw))
		dir = r * input.x - f * input.y
	var amount := minf(dir.length(), 1.0)
	var was := hero_pos
	if amount > 0.05:
		_move_hero(dir, delta)
		hero_yaw = lerp_angle(hero_yaw, atan2(-dir.x, -dir.z), minf(delta * 10.0, 1.0))
		look_cool -= delta
		if look_cool <= 0.0:
			cam_yaw = lerp_angle(cam_yaw, hero_yaw, minf(delta * 1.1, 1.0))
	_guard(delta, amount > 0.05, was)
	hero.set_walk(amount)
	hero.position = hero_pos
	hero.rotation.y = hero_yaw
	_update_camera(delta)
	_check_surroundings()


## One frame of walking: each axis separately (so the hero slides along a wall), in
## sub-steps of at most SUB_STEP so a long frame behaves like several short ones.
func _move_hero(dir: Vector3, delta: float, speed := SPEED) -> void:
	var step := dir.limit_length(1.0) * speed * delta
	var n := maxi(1, int(ceil(step.length() / SUB_STEP)))
	var part := step / n
	for i in n:
		if _walkable(hero_pos + Vector3(part.x, 0, 0)):
			hero_pos.x += part.x
		if _walkable(hero_pos + Vector3(0, 0, part.z)):
			hero_pos.z += part.z


## The nearest walkable point to p (p itself if it is walkable), searched outward in rings
## up to 3 units; failing that the last safe spot, failing that p.
func _settle(p: Vector3) -> Vector3:
	p.y = 0.0
	if _walkable(p):
		return p
	var r := 0.1
	while r <= 3.0:
		for k in 32:
			var q := p + Vector3(sin(TAU * k / 32.0), 0, cos(TAU * k / 32.0)) * r
			if _walkable(q):
				return q
		r += 0.1
	return _last_safe if _walkable(_last_safe) else p


## Where to put a hero who stood at `from` (walkable) and was moved to `to` (a duel's stand
## point): the last walkable point on the straight line from `from` toward `to`, so they
## never end up across a wall or in another room. Only if `from` is not walkable, the
## nearest walkable point to `to`.
func _settle_from(from: Vector3, to: Vector3) -> Vector3:
	from.y = 0.0
	to.y = 0.0
	if not _walkable(from):
		return _settle(to)
	var n := int(ceil(from.distance_to(to) / 0.05))
	var last := from
	for i in range(1, n + 1):
		var q := from.lerp(to, float(i) / n)
		if not _walkable(q):
			break
		last = q
	return last


func _can_move() -> bool:
	for k in 8:
		var d := Vector3(sin(TAU * k / 8.0), 0, cos(TAU * k / 8.0)) * 0.1
		if _walkable(hero_pos + Vector3(d.x, 0, 0)) or _walkable(hero_pos + Vector3(0, 0, d.z)):
			return true
	return false


## Safety net, every walking frame: a hero standing in blocked space is moved to the nearest
## free spot at once; one pushed for STUCK_AFTER seconds without moving, with no direction
## open, is walked back along the trail. Neither can pass a sealed gate or an unbeaten
## guardian: the gate only opens by interaction, and the trail holds only places already
## walked, away from foes. Not reached during a duel (_process returns before this).
func _guard(delta: float, pushed: bool, was: Vector3) -> void:
	if not _walkable(hero_pos):
		_free("inside")
		return
	if not pushed or hero_pos.distance_squared_to(was) > 1e-8:
		_stuck_t = 0.0
		return
	_stuck_t += delta
	if _stuck_t >= STUCK_AFTER:
		_stuck_t = 0.0
		if not _can_move():
			_free("boxed")


func _trail_back(from: Vector3) -> Vector3:
	for i in range(_trail.size() - 1, -1, -1):
		var p: Vector3 = _trail[i]
		if p.distance_to(from) >= 1.0 and _walkable(p):
			return p
	if _last_safe.distance_to(from) >= 1.0 and _walkable(_last_safe):
		return _last_safe
	return from


func _free(why: String) -> bool:
	var from := hero_pos
	var to := _settle(from)
	if to.distance_to(from) < 0.001:
		to = _trail_back(from)
	if to.distance_to(from) < 0.001:
		return false
	hero_pos = to
	hero.position = to
	_stuck_t = 0.0
	unstuck_count += 1
	print("UNSTUCK tier=%d from=(%.2f,%.2f) to=(%.2f,%.2f) why=%s" % [tier, from.x, from.z, to.x, to.z, why])
	return true


## Manual way out, for a HUD button: frees a hero in blocked space to the nearest free spot,
## otherwise returns them to the latest safe spot on this tier at least 1 unit back along
## where they walked (never further: with no such spot they stay put). Returns whether the
## hero moved. Refuses (false, nothing moves) before the tier has started, during a duel or
## when a foe is close enough to start one, while a screen is open, or while leaving.
func unstuck() -> bool:
	if hero == null or not started or duel != null or _leaving or (hud != null and hud.screen != ""):
		return false
	for e in ents:
		if e.type == "foe" and (e.pos as Vector3).distance_to(hero_pos) < 2.6:
			return false
	return _free("manual")


func _update_camera(delta: float) -> void:
	var yaw := cam_yaw + (PI + 0.55 + sin(_t * 0.25) * 0.35 if not started else 0.0)
	var back := Vector3(sin(yaw), 0, cos(yaw))
	var showcase: bool = hud != null and hud.screen in ["bag", "shop"]

	var want := hero_pos + back * 0.9 + Vector3(0, 3.4, 0)
	var dists: Array = [3.3, 2.6, 2.0] if showcase else [5.2, 4.2, 3.2, 2.4, 1.6]
	for d: float in dists:
		var c := hero_pos + back * d
		if theme.special == "open" or _inside(Vector2(c.x, c.z)):
			want = c + Vector3(0, 1.35 if showcase else 1.7 + d * 0.24, 0)
			break
	cam.position = cam.position.lerp(want, clampf(delta * 8.0, 0.0, 1.0))
	cam.look_at(hero_pos + Vector3(0, 1.15 if showcase else 1.5, 0))

	cam.h_offset = lerpf(cam.h_offset, 1.45 if showcase else 0.0, clampf(delta * 8.0, 0.0, 1.0))
	_show_light.visible = showcase


func _check_surroundings() -> void:
	near = {}
	var best := 2.4
	var foe_close := false
	for e in ents:
		var d: float = (e.pos as Vector3).distance_to(hero_pos)
		if e.type == "foe":
			if d < 14.0:
				var to: Vector3 = hero_pos - e.pos
				(e.node as Node3D).rotation.y = atan2(-to.x, -to.z)
			if d < 6.0:
				foe_close = true
			if d < 2.6:
				_start_duel(e)
				return
		elif d < best:
			best = d
			near = e
	if not foe_close and _walkable(hero_pos):
		_last_safe = hero_pos
		if _trail.is_empty() or (_trail[-1] as Vector3).distance_to(hero_pos) >= 2.0:
			_trail.append(hero_pos)
			if _trail.size() > 8:
				_trail.pop_front()


func ground_y(_p: Vector3) -> float:
	return 0.0


func _start_duel(e: Dictionary) -> void:
	if duel != null:
		return
	stick = Vector2.ZERO
	hero.set_walk(0.0)
	var group: Array = [e]
	for o in ents:
		if o.type == "foe" and o != e and group.size() < 3 and (o.pos as Vector3).distance_to(e.pos) < 8.0:
			group.append(o)
	var foes: Array = []
	for g in group:
		foes.append({"node": g.node, "def": EnemyDef.make_encounter(g.kind, tier, int(Run.data.loop)), "enc": {"id": g.id, "kind": g.kind}})
	_duel_ents = group
	_pre_duel = hero_pos
	Run.spawn = _last_safe
	duel = Duel.new()
	duel.host = self
	duel.player = hero
	duel.foes = foes
	hud.visible = false
	add_child(duel)


func duel_done(won: bool, d: Duel) -> void:
	duel = null
	Engine.time_scale = 4.0 if _bot == "tour" else 1.0
	var guardian_fell := false
	for rec in d.slain:
		if rec.enc.get("kind", "") == "guardian":
			guardian_fell = true
	if not won:
		_leaving = true
		get_tree().change_scene_to_file.call_deferred("res://scenes/overworld.tscn")
		return
	if guardian_fell:
		_leaving = true
		Run.spawn = _settle_from(_pre_duel, hero.global_position) if not d.reward.get("cleared", false) else "entrance"
		get_tree().reload_current_scene.call_deferred()
		return
	hud.visible = true
	cam.make_current()
	for rec in d.slain:
		for e in _duel_ents:
			if e.node == rec.node:
				(e.node as Node).queue_free()
				ents.erase(e)
	_duel_ents = []
	hero.play(&"idle")
	hero_pos = _settle_from(_pre_duel, hero.global_position)
	hero.position = hero_pos
	hero.rotation = Vector3(0, hero_yaw, 0)
	_last_safe = hero_pos
	Run.save()


func prompt() -> String:
	if near.is_empty():
		return ""
	if near.type == "exit" and int(Run.data.unlocked) <= tier:
		return "SEALED"
	if near.type == "entry" and tier == 1:
		return "LEAVE"
	return PROMPTS.get(near.type, "")


func interact() -> void:
	if near.is_empty() or _leaving:
		return
	var e := near
	match e.type:
		"chest":
			Run.data.opened.append(e.id)
			Run.data.gold += int(e.gold)
			var msg := "The chest holds %d gold" % e.gold
			var item: String = e.get("item", "")
			if item != "" and not Run.data.inventory.has(item):
				Run.data.inventory.append(item)
				msg += " and the %s" % Items.info(item).name
			Run.captions.append(msg + ".")
			_remove(e)
		"smith":
			hud.open("shop")
		"brazier":
			if int(Run.data.potions) < 2:
				Run.data.potions = 2
				Run.captions.append("You rest by the fire. Your flasks are refilled.")
			else:
				Run.captions.append("The fire is warm. There is nothing more it can give you.")
		"relic":
			Run.data.relics.append(tier)
			var rel: Dictionary = Story.RELICS[tier]
			Run.captions.append("%s. %s" % [rel.name, rel.text])
			Story.found("relic%d" % tier)
			Quests.sync()
			if Run.data.relics.size() >= Run.FLOORS:
				Run.captions.append(Story.TRUTH)
			_remove(e)
		"exit":
			if int(Run.data.unlocked) > tier:
				_travel(tier + 1, "entrance")
			else:
				Run.captions.append("Sealed. The guardian of this tier holds the way.")
		"entry":
			if tier > 1:
				_travel(tier - 1, "exit")
			else:
				_leaving = true
				Run.data.in_tower = false
				Run.save()
				get_tree().change_scene_to_file.call_deferred("res://scenes/overworld.tscn")
				return
	Run.save()


func refresh_hero() -> void:
	hero.configure(Run.look())
	hero.flash(Color(1.0, 0.85, 0.5))


func _remove(e: Dictionary) -> void:
	(e.node as Node3D).queue_free()
	ents.erase(e)
	near = {}


func _travel(to: int, at: String) -> void:
	_leaving = true
	Run.travel(to, at)
	get_tree().reload_current_scene.call_deferred()


func _bot_dir() -> Vector3:
	if quest_run:
		return _wbot.quest_dir()
	var target := Tiers.EXIT
	if not Run.is_slain("t%d_guardian" % tier):
		target = Vector3(0, 0, -40)
	elif not near.is_empty() and near.type == "exit":
		interact()
		return Vector3.ZERO
	var to := target - hero_pos
	if absf(hero_pos.x) > 0.4 and absf(to.z) > 1.0:
		to = Vector3(-hero_pos.x, 0, 0) + Vector3(0, 0, signf(to.z) * 0.3)
	to.y = 0
	return to.normalized()


func _take_shot_if_due() -> void:
	if _shot_path == "":
		return
	if _shot_when in ["shop", "bag", "map"] and hud.screen == "" and _t > 0.4:
		hud.open(_shot_when)
	if _t < 1.4:
		return
	var path := _shot_path
	_shot_path = ""
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
