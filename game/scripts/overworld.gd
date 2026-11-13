class_name Overworld
extends Node3D

const OverworldTerrain := preload("res://scripts/overworld_terrain.gd")
const OverworldPlaces := preload("res://scripts/overworld_places.gd")
const OverworldSky := preload("res://scripts/overworld_sky.gd")
const OverworldHero := preload("res://scripts/overworld_hero.gd")
const OverworldInteract := preload("res://scripts/overworld_interact.gd")
const OverworldRemote := preload("res://scripts/overworld_remote.gd")
const OverworldDuels := preload("res://scripts/overworld_duels.gd")
const OverworldBot := preload("res://scripts/overworld_bot.gd")
const OverworldTravel := preload("res://scripts/overworld_travel.gd")

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
var _walkers: Array = []
var _remote := {}


static var map_tex: ImageTexture

var _chunks := {}
var _gather := {}
var _biome := ""
var _save_t := 0.0
var _last_safe := Vector3.ZERO
var _leaving := false
var _show_light: OmniLight3D
var _t := 0.0
var _bot := ""
var _stuck := 0.0
var _shot_path := ""
var _shot_when := ""
var _assettest: Variant = null  # debug: "--assettest" or "--assettest=SECONDS" (freeze the pose there)
var _assettest_anim: AnimationPlayer
var _looktest: Variant = null  # debug: "--looktest=MODE" (wide|close|compare|swing|empty), "--looktest-seek=SECONDS"
var _looktest_seek := -1.0
var _looktest_hide := ""

var terrain: OverworldTerrain
var places: OverworldPlaces
var sky: OverworldSky
var mover: OverworldHero
var interaction: OverworldInteract
var remotes: OverworldRemote
var duels: OverworldDuels
var bots: OverworldBot
var travel: OverworldTravel


func _ready() -> void:
	terrain = OverworldTerrain.new(self)
	places = OverworldPlaces.new(self)
	sky = OverworldSky.new(self)
	mover = OverworldHero.new(self)
	interaction = OverworldInteract.new(self)
	remotes = OverworldRemote.new(self)
	duels = OverworldDuels.new(self)
	bots = OverworldBot.new(self)
	travel = OverworldTravel.new(self)
	for part in [terrain, places, sky, mover, interaction, remotes, duels, bots, travel]:
		add_child(part)
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
		elif a.begins_with("--assettest"):
			_assettest = a.trim_prefix("--assettest").trim_prefix("=")
			Run.no_save = true
			Run.title_seen = true
		elif a.begins_with("--looktest-hide="):
			_looktest_hide = a.trim_prefix("--looktest-hide=")
		elif a.begins_with("--looktest-seek="):
			_looktest_seek = float(a.trim_prefix("--looktest-seek="))
		elif a.begins_with("--looktest"):
			_looktest = a.trim_prefix("--looktest").trim_prefix("=")
			if str(_looktest) == "":
				_looktest = "wide"
			Run.no_save = true
			Run.title_seen = true
		elif a.begins_with("--at="):
			at = a.trim_prefix("--at=")
		elif a.begins_with("--golden="):
			bots.golden_begin(a.trim_prefix("--golden="))
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
	Online.message.connect(duels._net_message)
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
	sky._build_sky()
	places._build_tower()

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
	places._spawn_walkers()
	sky._build_rain()
	started = Run.title_seen
	if Run.resumed:
		Run.resumed = false
		Run.captions.append("Picked up where you left off.")

	terrain._update_chunks(true)
	mover._update_camera(1.0)
	if _assettest != null:
		_assettest_setup()
	if _looktest != null:
		_looktest_setup()
	if _bot != "":
		print("LAND at=%d,%d combat=%d gold=%d" % [hero_pos.x, hero_pos.z, Run.combat_level(), Run.data.gold])


func _assettest_setup() -> void:
	var path := "res://assets/test/assettest.glb"
	print("ASSETTEST exists=%s" % ResourceLoader.exists(path))
	var model: Node3D = (load(path) as PackedScene).instantiate()
	var fwd := Vector3(sin(cam_yaw), 0, cos(cam_yaw))
	model.position = hero_pos - fwd * 2.2 + fwd.cross(Vector3.UP) * 1.6
	model.position.y = Land.walk_height(model.position.x, model.position.z)
	model.scale = Vector3.ONE * 1.5
	add_child(model)
	_assettest_anim = model.find_children("*", "AnimationPlayer")[0]
	var anims := _assettest_anim.get_animation_list()
	_assettest_anim.play(anims[0])
	if str(_assettest) != "":
		_assettest_anim.seek(float(_assettest), true)
		_assettest_anim.pause()
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D")[0]
	var mat: StandardMaterial3D = (model.find_children("*", "MeshInstance3D")[0] as MeshInstance3D).get_active_material(0)
	var img: Image = mat.albedo_texture.get_image()
	print("ASSETTEST anims=%s loop=%s bones=%d tex=%s %dx%d fmt=%d mips=%s" % [anims, _assettest_anim.get_animation(anims[0]).loop_mode, sk.get_bone_count(), mat.albedo_texture.get_class(), img.get_width(), img.get_height(), img.get_format(), img.has_mipmaps()])
	get_tree().create_timer(4.0).timeout.connect(_assettest_report)


func _assettest_report() -> void:
	var vp := get_viewport()
	print("ASSETTEST renderer method=%s driver=%s setting=%s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name(), ProjectSettings.get_setting("rendering/renderer/rendering_method")])
	print("ASSETTEST adapter=%s vendor=%s driver_info=%s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(), OS.get_video_adapter_driver_info()])
	print("ASSETTEST window=%s visible_rect=%s scale3d=%s msaa=%s shadow_atlas=%s" % [DisplayServer.window_get_size(), vp.get_visible_rect().size, vp.scaling_3d_scale, vp.msaa_3d, vp.positional_shadow_atlas_size])
	print("ASSETTEST anim_pos=%.3f playing=%s" % [_assettest_anim.current_animation_position, _assettest_anim.is_playing()])


# ---- debug only: --looktest[=wide|close|skeleton|compare|swing|empty] [--looktest-seek=SECONDS] ----
# --looktest=rig|rig-check|rig-heads|rig-gear|rig-perf=N|ph-perf=N: RigVisual scenes in rig_looktest.gd.
# KayKit adventurer vs skeleton in the duel framing (duel.gd CAM_POS/CAM_LOOK, fov 55, 2.5 apart),
# a short dungeon wall with floor and a lit torch behind. Local frame as in a duel: the player at the
# origin facing -Z, the enemy 2.5 further along -Z facing +Z (offset sideways so the chunky knight does not hide it). `empty` builds only the camera (baseline).
const LT_DIR := "res://assets/kaykit/"
const LT_SWORD := "1H_Sword"
const LT_SHIELD := "Badge_Shield"


func _lt_aabb(root: Node3D, skip: Array = []) -> AABB:
	var box := AABB()
	var first := true
	var inv := root.global_transform.affine_inverse()
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.name in skip or mi.mesh == null:
			continue
		var b: AABB = (inv * mi.global_transform) * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _lt_load(file: String, parent: Node3D, pos: Vector3, yaw := 0.0) -> Node3D:
	var n: Node3D = (load(LT_DIR + file) as PackedScene).instantiate()
	parent.add_child(n)
	n.position = pos
	n.rotation.y = yaw
	return n


func _lt_actor(file: String, parent: Node3D, pos: Vector3, facing_z: float, keep: Array, clip: String) -> Node3D:
	# glTF fronts face +Z; the duel player faces -Z.
	var m := _lt_load(file, parent, pos, 0.0 if facing_z > 0.0 else PI)
	var sk: Skeleton3D = m.find_children("*", "Skeleton3D")[0]
	var weapons: Array = []
	for n in m.find_children("*", "MeshInstance3D", true, false):
		var par := n.get_parent()
		if par is BoneAttachment3D:
			weapons.append("%s on %s" % [n.name, (par as BoneAttachment3D).bone_name])
			n.visible = n.name in keep
	for n in m.find_children("*", "MeshInstance3D", true, false):
		if _looktest_hide != "" and n.name in _looktest_hide.split(","):
			n.visible = false
	if _looktest_hide == "list":
		for n in m.find_children("*", "MeshInstance3D", true, false):
			var mi2 := n as MeshInstance3D
			print("LOOKTEST mesh %s surfaces=%d mat0=%s visible=%s aabb=%s" % [n.name, mi2.mesh.get_surface_count(), mi2.get_active_material(0).resource_name, mi2.visible, mi2.mesh.get_aabb()])
	var ap: AnimationPlayer = m.find_children("*", "AnimationPlayer")[0]
	var anim := ap.get_animation(clip)
	anim.loop_mode = Animation.LOOP_LINEAR
	ap.play(clip)
	if _looktest_seek >= 0.0:
		ap.seek(_looktest_seek, true)
		ap.pause()
	var h := _lt_aabb(m, ["Knight_Cape"])
	var mats := {}
	var tris := 0
	for n in m.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			mats[mi.get_active_material(i)] = true
		if mi.visible:
			for i in mi.mesh.get_surface_count():
				tris += mi.mesh.surface_get_array_len(i) / 3 if mi.mesh.surface_get_array_index_len(i) == 0 else mi.mesh.surface_get_array_index_len(i) / 3
	print("LOOKTEST %s bones=%d skeleton=%s clips=%d clip=%s len=%.2f aabb_y=%.3f..%.3f size=%s materials=%d visible_tris=%d weapons=%s" % [file, sk.get_bone_count(), sk.name, ap.get_animation_list().size(), clip, anim.length, h.position.y, h.end.y, h.size, mats.size(), tris, weapons])
	return m


func _looktest_setup() -> void:
	var mode := str(_looktest)
	var root := Node3D.new()
	root.name = "LookTest"
	add_child(root)
	# A spot near the start with no world entity (chest, node, foe) close by.
	_collect_ents()
	var best := -1.0
	root.position = hero_pos + Vector3(0, 0, -10)
	for off in [Vector2(0, -10), Vector2(10, -6), Vector2(-10, -6), Vector2(6, 10), Vector2(-6, 10), Vector2(14, 0), Vector2(-14, 0), Vector2(0, -16), Vector2(12, -14), Vector2(-12, -14), Vector2(18, 8), Vector2(-18, 8)]:
		var c := hero_pos + Vector3(off.x, 0, off.y)
		var nearest := 1e9
		for e in ents:
			if e.has("pos"):
				nearest = minf(nearest, Vector2(e.pos.x - c.x, e.pos.z - c.z).length())
		if nearest > best:
			best = nearest
			root.position = c
	print("LOOKTEST site=%s nearest_entity=%.1f" % [root.position, best])
	root.position.y = Land.walk_height(root.position.x, root.position.z)
	hud.visible = false
	var cam2 := Camera3D.new()
	cam2.fov = 55.0
	cam2.far = 260.0
	root.add_child(cam2)
	var cpos := Vector3(0.55, 1.9, 4.4)
	var clook := Vector3(0.2, 1.8, -0.8)
	if mode == "close":
		cpos = Vector3(-2.3, 1.45, -1.8)
		clook = Vector3(-0.45, 1.25, -0.1)
	elif mode == "skeleton":
		cpos = Vector3(2.6, 1.6, -1.2)
		clook = Vector3(0.2, 1.2, -2.5)
	cam2.position = cpos
	cam2.look_at(root.to_global(clook))
	cam2.make_current()
	var hbox := _lt_aabb(hero)
	print("LOOKTEST code hero height=%.3f aabb_y=%.3f..%.3f width=%.3f" % [hbox.size.y, hbox.position.y, hbox.end.y, hbox.size.x])
	for n in hero.find_children("*", "MeshInstance3D", true, false):
		var mb: AABB = (hero.global_transform.affine_inverse() * (n as MeshInstance3D).global_transform) * (n as MeshInstance3D).mesh.get_aabb()
		if mb.position.y < -0.3:
			print("LOOKTEST hero mesh below ground: %s y=%.2f..%.2f size=%s" % [n.name, mb.position.y, mb.end.y, mb.size])
	if mode != "compare":
		hero.visible = false
	if mode.begins_with("rig") or mode.begins_with("ph-perf"):
		# RigVisual (docs/RIG_PLAN.md R1): loaded only here, so a normal start never touches it.
		var lt: Node3D = load("res://scripts/rig_looktest.gd").new()
		root.add_child(lt)
		lt.call("setup", mode, _looktest_seek)
		get_tree().create_timer(6.0).timeout.connect(_looktest_report)
		return
	if mode != "empty":
		var knight := _lt_actor("knight.glb", root, Vector3(-0.45, 0, 0), -1.0, [LT_SWORD, LT_SHIELD, "Knight_Helmet", "Knight_Cape", "Knight_Body", "Knight_Head", "Knight_ArmLeft", "Knight_ArmRight", "Knight_LegLeft", "Knight_LegRight"], "1H_Melee_Attack_Slice_Diagonal" if mode == "swing" else "Idle")
		_lt_actor("skeleton_warrior.glb", root, Vector3(0.2, 0, -2.5), 1.0, ["Skeleton_Warrior_Helmet"], "1H_Melee_Attack_Slice_Horizontal" if mode == "swing" else "Idle_Combat")
		if mode == "compare":
			hero_pos = root.position + Vector3(-1.7, 0, 0)  # the mover keeps placing the hero at hero_pos
			hero_yaw = 0.0
			hero.visible = true
			knight.position = Vector3(-0.1, 0, 0)
		# Dungeon (4 x 4 grid pieces): floor tiles, a wall of five pieces with the doorway in the middle,
		# two pillars, a barrel, a lit torch on the floor with a warm light.
		var wz := -2.5 - 1.7
		for i in range(-2, 3):
			for z in [2.0, -2.0]:
				_lt_load("d_floor_tile_large.glb", root, Vector3(i * 4.0, -0.05, z))
			_lt_load("d_wall_doorway.glb" if i == 0 else "d_wall.glb", root, Vector3(i * 4.0, 0, wz))
		for x in [-2.0, 2.0]:
			_lt_load("d_pillar.glb", root, Vector3(x, 0, wz + 0.9))
		_lt_load("d_torch_lit.glb", root, Vector3(-1.4, 0.395, wz + 1.0))
		_lt_load("d_barrel_large.glb", root, Vector3(3.4, 0, wz + 1.0))
		var tl := OmniLight3D.new()
		tl.position = Vector3(-1.4, 1.4, wz + 1.2)
		tl.light_color = Color(1.0, 0.62, 0.28)
		tl.light_energy = 2.2
		tl.omni_range = 7.0
		root.add_child(tl)
	get_tree().create_timer(6.0).timeout.connect(_looktest_report)


func _looktest_report() -> void:
	print("LOOKTEST stats mode=%s draw_calls=%d objects=%d primitives=%d nodes=%d tex_mem=%d vid_mem=%d" % [str(_looktest),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)), int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))])


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


func _collect_ents() -> void:
	ents = []
	ents.append_array(_walkers)
	ents.append_array(_remote.values())
	for k in _chunks:
		ents.append_array(_chunks[k].ents)


func _process(delta: float) -> void:
	if hero == null:
		return
	remotes._publish(delta)
	if duel != null:
		return
	remotes._tick_remote(delta)
	_t += delta
	sky._day = fmod(sky._day + delta / 480.0, 1.0)
	bots._take_shot_if_due()
	terrain._update_chunks()
	sky._apply_light(clampf(delta * 0.8, 0.0, 1.0))
	if not started or hud.screen != "" or _leaving:
		hero.set_walk(0.0)
		if hud.screen in ["bag", "shop"]:
			hero.rotation.y = cam_yaw + PI + sin(_t * 0.9) * 0.6
		mover._update_camera(delta)
		return
	mover._move_hero(delta)
	mover._update_camera(delta)
	interaction._tick_gather(delta)
	interaction._check_surroundings(delta)
	var b := Land.biome(hero_pos.x, hero_pos.z)
	if b != _biome:
		_biome = b
		theme.name = place_name()
		hud.announce(theme.name)
	places._tick_walkers(delta)
	sky._tick_weather(delta)

	_save_t += delta
	if _save_t > 5.0:
		_save_t = 0.0
		Run.data.ow_x = _last_safe.x
		Run.data.ow_z = _last_safe.z
		Run.save()


func ground_y(p: Vector3) -> float:
	return Land.walk_height(p.x, p.z)


func in_zone() -> bool:
	return _biome == "ashlands"


func prompt() -> String:
	return interaction.prompt()


func interact() -> void:
	interaction.interact()


func pvp_answer(action: String, card := {}) -> void:
	duels.pvp_answer(action, card)


func duel_done(won: bool, d: Duel) -> void:
	duels.duel_done(won, d)


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
