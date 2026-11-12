extends Node

var ow: Overworld
var _bot_step := 0
var _bot_wait := 0.0

## Golden Shots (tools/shots.js), `--golden=<name>`: a fixed time of day, no weather, no
## movement, the hero at a fixed spot and the camera at a fixed spot. Positions are in a frame
## anchored at `at` (x,z) and turned by `rot`; the y of an offset is the height above the
## ground there. The game prints "GOLDEN ready <name>" once the terrain is built and settled.
const GOLDEN_DAY := 0.3
const GOLDEN := {
	"road-wide": {"at": Vector2(0, -80), "hero_yaw": 0.0, "cam": Vector3(0, 4.5, 16.0), "look": Vector3(0, 4.0, -40.0), "hud": false},
	"hero-close": {"at": Vector2(-3, 14), "hero_yaw": PI, "cam": Vector3(1.0, 1.45, 3.4), "look": Vector3(0, 1.05, 0), "hud": false},
	"terrain-graze": {"at": Vector2(40, -45), "hero_yaw": 0.0, "cam": Vector3(1.2, 0.45, 7.0), "look": Vector3(0, 0.7, -40.0), "hud": false},
	"wall-close": {"at": Vector2(26, -2), "rot": -0.868, "hero": Vector3(-3.0, 0, 5.0), "hero_yaw": PI, "cam": Vector3(1.1, 1.5, 7.6), "look": Vector3(1.1, 1.5, 3.0), "hud": false},
}
var golden := ""
var _g := {}
var _g_ok := 0
var _g_said := false


func _init(owner_world: Overworld) -> void:
	ow = owner_world


func _walk_to(target: Vector3, delta: float) -> Vector3:
	var to := target - ow.hero_pos
	to.y = 0
	if ow._stuck > 0.4:
		to = to.rotated(Vector3.UP, 1.3)
		if ow._stuck > 1.5:
			ow._stuck = 0.0
	return to.normalized()


func _bot_dir(delta: float) -> Vector3:
	if ow._bot.begins_with("pvp"):
		return Vector3.ZERO
	if ow._bot == "tour":
		var gate := Vector3(Land.TOWER_GATE.x, 0, Land.TOWER_GATE.y + 2.0)
		if not ow.near.is_empty() and ow.near.type == "tower":
			ow.interaction.interact()
			return Vector3.ZERO
		return _walk_to(gate, delta)

	if not ow._gather.is_empty():
		return Vector3.ZERO
	_bot_wait -= delta
	if _bot_wait > 0.0:
		return Vector3.ZERO
	if _bot_step >= 3:
		var made: Array = []
		for r in Craft.RECIPES:
			if Craft.make(r):
				made.append(r.name)
		ow.interaction._task_talk()
		print("GATHER mats=%s made=%s total_level=%d task=%s" % [Run.data.mats, made, Run.total_level(), Run.data.task.get("foe", "")])
		ow.get_tree().quit()
		return Vector3.ZERO
	var best := {}
	var bd := 9999.0
	for e in ow.ents:
		if e.type == "node" and not e.depleted and Run.skill(Land.NODES[e.node_id].skill) >= int(Land.NODES[e.node_id].level):
			var d: float = (e.pos as Vector3).distance_to(ow.hero_pos)
			if d < bd:
				bd = d
				best = e
	if best.is_empty():
		return _walk_to(ow.hero_pos + Vector3(-30, 0, 0), delta)
	if bd < 2.8:
		ow.near = best
		ow.interaction.interact()
		_bot_step += 1
		_bot_wait = 0.5
		return Vector3.ZERO
	return _walk_to(best.pos, delta)


func golden_begin(shot_name: String) -> void:
	golden = shot_name
	Run.no_save = true
	Run.title_seen = true
	if shot_name == "tower-hall":
		ow._shot_when = "world"
		return
	if shot_name.begins_with("duel-"):
		ow._shot_when = "windup"
		return
	if not GOLDEN.has(shot_name):
		print("GOLDEN unknown ", shot_name)
		return
	Run.data = Run.defaults()
	Run.data.skills_seeded = true
	Run.data.tutorial_done = true
	_g = GOLDEN[shot_name]
	var hp := _golden_at(_g, _g.get("hero", Vector3.ZERO), true)
	Run.data.ow_x = hp.x
	Run.data.ow_z = hp.z
	RenderingServer.frame_pre_draw.connect(_golden_cam)


static func _golden_at(spec: Dictionary, off: Vector3, walk: bool) -> Vector3:
	var a: Vector2 = spec.at
	var w := Vector3(a.x, 0, a.y) + Basis(Vector3.UP, float(spec.get("rot", 0.0))) * Vector3(off.x, 0, off.z)
	w.y = (Land.walk_height(w.x, w.z) if walk else Land.height(w.x, w.z)) + (0.0 if walk else off.y)
	return w


func _golden_tick() -> void:
	if _g.is_empty():
		return
	var yaw := float(_g.hero_yaw) + float(_g.get("rot", 0.0))
	ow._leaving = true
	ow.sky._day = GOLDEN_DAY
	ow.hero_pos = _golden_at(_g, _g.get("hero", Vector3.ZERO), true)
	ow.hero_yaw = yaw
	ow.cam_yaw = yaw
	ow.hero.position = ow.hero_pos
	ow.hero.rotation.y = yaw
	ow._biome = Land.biome(ow.hero_pos.x, ow.hero_pos.z)
	ow.sky._apply_light(1.0)
	ow.hud.visible = bool(_g.hud)
	if not _g_said and ow._t > 1.0 and ow.terrain._queue.is_empty() and ow.terrain._job.is_empty():
		_g_ok += 1
		if _g_ok >= 8:
			_g_said = true
			print("GOLDEN ready ", golden)


func _golden_cam() -> void:
	if ow.cam == null or _g.is_empty():
		return
	ow.cam.position = _golden_at(_g, _g.cam, false)
	ow.cam.look_at(_golden_at(_g, _g.look, false))
	ow.cam.h_offset = 0.0
	ow.cam.fov = 60.0


## The tower interior (world.gd) calls this from its argument parsing.
static func golden_world(w: Node3D, shot_name: String) -> void:
	Run.no_save = true
	Run.title_seen = true
	Run.data = Run.defaults()
	Run.data.tutorial_done = true
	Run.data.in_tower = true
	w._leaving = true
	var st := {"n": 0}
	RenderingServer.frame_pre_draw.connect(func():
		if w.hero == null or w.cam == null:
			return
		w.hero_pos = Vector3(0, 0, -1.5)
		w.hero.position = w.hero_pos
		w.hero.rotation.y = 0.0
		w.hud.visible = false
		w.cam.position = Vector3(0.0, 2.7, 4.3)
		w.cam.look_at(Vector3(0.0, 1.6, -10.0))
		w.cam.h_offset = 0.0
		st.n += 1
		if st.n == 40:
			print("GOLDEN ready ", shot_name))


func _take_shot_if_due() -> void:
	if golden != "":
		_golden_tick()
	if ow._shot_path == "":
		return
	if ow._shot_when == "pvp":
		return
	if ow._shot_when == "players" and ow.hud.screen == "" and ow._t > 3.0:
		ow.hud.open("players")
	if ow._shot_when in ["players", "online"] and ow._t < 4.5:
		return
	if ow._shot_when == "fight":
		for e in ow.ents:
			if e.type == "foe" and e.node != null and ow._t > 0.5:
				ow.hero_pos = e.pos + Vector3(0, 0, 2.2)
				ow._shot_path = ""
				return
		return
	if ow._shot_when in ["skills", "store", "map", "quests", "perks"] and ow.hud.screen == "" and ow._t > 0.4:
		ow.hud.open(ow._shot_when)
	if ow._shot_when == "talk" and ow.hud.screen == "" and ow._t > 0.4:
		ow.hud.talk(Quests.talk("elder"))
		ow.hud._talk.i = 1
	if ow._shot_when == "craft" and ow.hud.screen == "" and ow._t > 0.4:
		ow.hud.open_craft("smithing")
	if ow._t < 1.6:
		return
	var path := ow._shot_path
	ow._shot_path = ""
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	ow.get_viewport().get_texture().get_image().save_png(path)
	ow.get_tree().quit()
