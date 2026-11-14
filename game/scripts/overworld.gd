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
	# Debug only: `--looktest=tex` replaces the world with the texture look-test scene (docs/TEXTURE_LOOK.md).
	if "--looktest=tex" in OS.get_cmdline_user_args():
		add_child((load("res://scripts/tex_looktest.gd") as GDScript).new())
		return
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
	# A saved spot can lie in a tree or a house (all chunks around it are built just above).
	if bots.golden == "" and _assettest == null and _shot_path == "":
		mover.settle_position("load")
		Run.data.ow_x = hero_pos.x
		Run.data.ow_z = hero_pos.z
	mover.reset_motion()
	mover._update_camera(1.0)
	if _assettest != null:
		_assettest_setup()
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
