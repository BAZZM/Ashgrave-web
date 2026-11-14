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


## Quest bot, `--autoplay=gather --questbot=act1|save [--pick=N]` (see quest_bot notes below).
var questbot := ""
var _qb_pick := 0
var _qb_started := false


func _init(owner_world: Overworld) -> void:
	ow = owner_world
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--questbot="):
			questbot = a.trim_prefix("--questbot=")
		elif a.begins_with("--pick="):
			_qb_pick = int(a.trim_prefix("--pick="))
	agility = "--agility" in OS.get_cmdline_user_args()
	agreal = "--agility-real" in OS.get_cmdline_user_args()


func _walk_to(target: Vector3, delta: float) -> Vector3:
	var to := target - ow.hero_pos
	to.y = 0
	if ow._stuck > 0.4:
		to = to.rotated(Vector3.UP, 1.3)
		if ow._stuck > 1.5:
			ow._stuck = 0.0
	return to.normalized()


func _bot_dir(delta: float) -> Vector3:
	if questbot != "":
		return Vector3.ZERO
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


## ---- Agility test (tools/check.js scenario `agility`): `--autoplay=gather --agility`. The
## gather bot keeps foes from chasing; the hero then moves by the real movement code (speed
## tiers, sprint, dash) fed with a scripted stick on a cleared lane. Everything is measured in
## game time, one movement slice at a time, so it does not depend on the frame rate. Prints one
## "AGILITY <name> key=value ..." line per measurement and "AGILITY done" at the end.
const AG_PHASES := ["sprint", "stop", "walk", "turn_run", "turn_walk", "turn_sprint60", "turn_sprint120",
	"sprint_slow", "sprint_block", "dash", "dash_wall", "dash_water", "road"]
const AG_TURNS := {
	"turn_run": {"hold": Vector2(0, -1), "hold_t": 0.7, "to": Vector2(1, 0), "deg": 90.0},
	"turn_walk": {"hold": Vector2(0, -0.5), "hold_t": 0.8, "to": Vector2(0.5, 0), "deg": 90.0},
	"turn_sprint60": {"hold": Vector2(0, -1), "hold_t": 1.8, "to": Vector2(0.866, -0.5), "deg": 60.0},
	"turn_sprint120": {"hold": Vector2(0, -1), "hold_t": 1.8, "to": Vector2(0.866, 0.5), "deg": 120.0},
}
const AG_DASH_TRIES := [0.0, 0.10, 0.30, 0.40, 0.80, 1.20, 1.60, 1.85]
const AG_LANE_LEN := 160.0
var agility := false
var _ag_i := -1
var _ag_t := 0.0
var _ag_all := 0.0
var _ag := {}
var _ag_lane := {}
var _ag_wall := Vector3.ZERO
var _ag_wall_on := false


func agility_active() -> bool:
	return agility and ow._bot == "gather"


func _ag_ok(p: Vector3) -> bool:
	if not Land.in_bounds(p.x, p.z) or Vector2(p.x, p.z).distance_to(Land.TOWER) < 45.0:
		return false
	return not Land.is_water(p.x, p.z) and Land.road_dist(p.x, p.z) > 6.0


## A straight lane of AG_LANE_LEN units with no water, road, tower or bounds on it (obstacles are
## cleared while testing), nearest the start of the game.
func _ag_find_lane() -> Dictionary:
	var origins: Array = []
	for x in range(-200, 201, 20):
		for z in range(-240, 181, 20):
			origins.append(Vector3(x, 0, z))
	origins.sort_custom(func(a, b): return a.distance_to(Land.START) < b.distance_to(Land.START))
	for o in origins:
		for k in 8:
			var dir := Vector3(cos(k * PI / 4.0), 0, sin(k * PI / 4.0))
			var perp := Vector3(-dir.z, 0, dir.x)
			var good := true
			var s := 0.0
			while s <= AG_LANE_LEN and good:
				var p: Vector3 = o + dir * s
				good = _ag_ok(p) and _ag_ok(p + perp * 3.0) and _ag_ok(p - perp * 3.0)
				s += 4.0
			if good:
				return {"o": o, "d": dir}
	return {}


## Stand at a point (x, z) facing `dir`, camera frozen behind, all movement state cleared.
func _ag_place(pos: Vector3, dir: Vector3) -> void:
	pos.y = Land.walk_height(pos.x, pos.z)
	ow.hero_pos = pos
	var yaw := atan2(-dir.x, -dir.z)
	ow.hero_yaw = yaw
	ow.cam_yaw = yaw
	ow.look_cool = 1e9
	ow.hero.position = pos
	var m = ow.mover
	m.reset_motion()
	m._pips = m._pip_max
	m._lock = 0.0
	m._end_xz = Vector2(pos.x, pos.z)
	_ag_wall_on = false
	_ag = {"o": pos, "d": dir, "yaw": yaw, "log": []}


func _ag_s() -> float:
	return (ow.hero_pos - (_ag.o as Vector3)).dot(_ag.d)


func _ag_clear_obstacles() -> void:
	for k in ow._chunks:
		ow._chunks[k].obstacles.clear()
	if _ag_wall_on:
		var ch: Variant = ow._chunks.get(ow.terrain._chunk_of(_ag_wall))
		if ch != null:
			ch.obstacles.append(Vector3(_ag_wall.x, _ag_wall.z, 0.5))


func _ag_say(name: String, kv: String) -> void:
	print("AGILITY %s %s" % [name, kv])


func _ag_next() -> void:
	_ag_i += 1
	_ag_t = 0.0
	if _ag_i >= AG_PHASES.size():
		print("AGILITY done")
		ow.get_tree().quit()
		return
	var name: String = AG_PHASES[_ag_i]
	var o: Vector3 = _ag_lane.o
	var d: Vector3 = _ag_lane.d
	if name == "stop":
		_ag.release_t = 0.0
		_ag.release_s = _ag_s()
		return
	if name == "road":
		_ag_place(Vector3(0, 0, -25), Vector3(0, 0, -1))
	elif name == "dash_water":
		_ag_place_shore()
	else:
		_ag_place(o, d)
	_ag.name = name
	_ag.max_look = 0.0
	_ag.max_fov = 0.0
	_ag.said = false
	if name == "dash":
		_ag.dashes = []
		_ag.tries = []
		_ag.fl = []
	if name == "dash_wall":
		_ag_wall = ow.hero_pos + d * 2.0
		_ag_wall_on = true


func _ag_place_shore() -> void:
	for a in range(0, 360, 30):
		var dir := Vector3(-cos(deg_to_rad(a)), 0, -sin(deg_to_rad(a)))
		var from := Vector3(Land.LAKE.x, 0, Land.LAKE.y) - dir * 70.0
		var x := 0.0
		while x < 70.0:
			var p: Vector3 = from + dir * x
			if Land.in_bounds(p.x, p.z) and Land.is_water(p.x, p.z):
				var start: Vector3 = from + dir * (x - 2.0)
				if _ag_ok(start) and Land.in_bounds(from.x, from.z):
					_ag_place(start, dir)
					return
				break
			x += 0.5
	_ag_place(_ag_lane.o, _ag_lane.d)


func agility_input(dt: float) -> Vector2:
	if _ag_i < 0:
		Engine.time_scale = 3.0
		_ag_lane = _ag_find_lane()
		if _ag_lane.is_empty():
			print("AGILITY fail no clear lane")
			ow.get_tree().quit()
			return Vector2.ZERO
		_ag_say("lane", "x=%.0f z=%.0f dir=%.2f,%.2f" % [_ag_lane.o.x, _ag_lane.o.z, _ag_lane.d.x, _ag_lane.d.z])
		_ag_next()
	_ag_clear_obstacles()
	_ag_t += dt
	_ag_all += dt
	var m = ow.mover
	var name: String = AG_PHASES[_ag_i] if _ag_i < AG_PHASES.size() else ""
	var out := Vector2.ZERO
	var s := _ag_s() if _ag.has("o") else 0.0
	if name != "":
		_ag.max_look = maxf(float(_ag.get("max_look", 0.0)), m._look.length())
		_ag.max_fov = maxf(float(_ag.get("max_fov", 0.0)), ow.cam.fov)
	match name:
		"sprint":
			out = Vector2(0, -1)
			var ev: Dictionary = _ag
			if not ev.has("t_run") and m._spd >= 9.4:
				ev.t_run = _ag_t
			if not ev.has("t_sprint") and m._sprinting:
				ev.t_sprint = _ag_t
			if not ev.has("t_top") and m._spd >= 12.4:
				ev.t_top = _ag_t
			if not ev.has("t100") and s >= 100.0:
				ev.t100 = _ag_t
			ev.top = maxf(float(ev.get("top", 0.0)), m._spd)
			if s >= 135.0 or _ag_t > 14.0:
				_ag_say("sprint", "run_t=%.2f sprint_t=%.2f top_t=%.2f top=%.2f t100=%.2f dist=%.1f look_max=%.2f fov_max=%.1f" % [
					ev.get("t_run", -1.0), ev.get("t_sprint", -1.0), ev.get("t_top", -1.0), ev.top, ev.get("t100", -1.0), s, ev.max_look, ev.max_fov])
				_ag_next()
		"stop":
			if _ag_t > 2.0 or (m._spd < 0.01 and _ag_t > 0.02):
				_ag_say("stop", "time=%.2f distance=%.2f" % [_ag_t, _ag_s() - float(_ag.release_s)])
				_ag_next()
		"walk":
			out = Vector2(0, -0.7)
			if not _ag.has("t95") and m._spd >= 0.95 * 3.85:
				_ag.t95 = _ag_t
			if _ag_t >= 1.5:
				_ag_say("walk", "stick=0.7 speed=%.2f t95=%.2f look_max=%.2f fov=%.1f" % [m._spd, _ag.get("t95", -1.0), _ag.max_look, ow.cam.fov])
				_ag_next()
		"turn_run", "turn_walk", "turn_sprint60", "turn_sprint120":
			var tt: Dictionary = AG_TURNS[name]
			out = tt.hold
			if _ag_t > float(tt.hold_t):
				if not _ag.has("sw_t"):
					_ag.sw_t = _ag_t
					_ag.sw_spd = m._spd
					_ag.sw_sprint = m._sprinting
					_ag.target = float(_ag.yaw) - deg_to_rad(float(tt.deg))
				out = tt.to
				var el: float = _ag_t - float(_ag.sw_t)
				if not _ag.has("t_yaw") and absf(angle_difference(ow.hero_yaw, float(_ag.target))) < deg_to_rad(2.0):
					_ag.t_yaw = el
				if not _ag.has("t_lost") and not m._sprinting:
					_ag.t_lost = el
				if el >= 0.8:
					var ty: float = _ag.get("t_yaw", -1.0)
					_ag_say(name, "deg=%.0f t_yaw=%.3f rate=%.0f sprint_before=%s sprint_after=%s t_lost=%.3f speed_before=%.2f speed_after=%.2f" % [
						tt.deg, ty, (float(tt.deg) - 2.0) / ty if ty > 0.0 else -1.0, _ag.sw_sprint, m._sprinting, _ag.get("t_lost", -1.0), _ag.sw_spd, m._spd])
					_ag_next()
		"sprint_slow":
			out = Vector2(0, -1)
			if _ag_t > 1.8:
				if not _ag.has("sw_t"):
					_ag.sw_t = _ag_t
					_ag.before = m._sprinting
				out = Vector2(0, -0.7)
				if not _ag.has("t_lost") and not m._sprinting:
					_ag.t_lost = _ag_t - float(_ag.sw_t)
				if _ag_t - float(_ag.sw_t) >= 0.6:
					_ag_say("sprint_slow", "sprint_before=%s sprint_after=%s t_lost=%.3f speed_after=%.2f" % [_ag.before, m._sprinting, _ag.get("t_lost", -1.0), m._spd])
					_ag_next()
		"sprint_block":
			out = Vector2(0, -1)
			if _ag_t > 1.8:
				var ahead: Vector3 = ow.hero_pos + (_ag.d as Vector3) * 4.0
				if not _ag.has("sw_t") and ow._chunks.has(ow.terrain._chunk_of(ahead)):
					_ag.sw_t = _ag_t
					_ag.before = m._sprinting
					_ag.spd_before = m._spd
					_ag_wall = ahead
					_ag_wall_on = true
				if _ag.has("sw_t") and not _ag.has("t_lost") and not m._sprinting:
					_ag.t_lost = _ag_t - float(_ag.sw_t)
				if _ag.has("sw_t") and _ag_t - float(_ag.sw_t) >= 1.0:
					_ag_say("sprint_block", "sprint_before=%s sprint_after=%s t_lost=%.3f speed_before=%.2f speed_after=%.2f stopped_short=%.2f" % [
						_ag.before, m._sprinting, _ag.get("t_lost", -1.0), _ag.spd_before, m._spd, (_ag_wall - (_ag.o as Vector3)).dot(_ag.d) - _ag_s()])
					_ag_wall_on = false
					_ag_next()
		"dash":
			out = Vector2(0, -1)
			var dashing_now: bool = m.dashing()
			# The end of a dash is seen here, one step after it happened.
			if _ag.get("in_dash", false) and not dashing_now:
				var dd: Dictionary = _ag.cur
				dd.dur = float(_ag.prev_t) - float(dd.t0)
				dd.dist = (ow.hero_pos - (dd.p0 as Vector3)).dot(_ag.d)
				dd.pips_after = m._pips
				_ag.dashes.append(dd)
				_ag.in_dash = false
			if dashing_now and _ag.dashes.is_empty():
				_ag.fl.append([m._dash_t, m.dash_iframes()])
			# Tries are timed from 0.5 s into the run, which is when the first dash is made.
			var idx: int = _ag.tries.size()
			if idx < AG_DASH_TRIES.size() and _ag_t - 0.5 >= float(AG_DASH_TRIES[idx]):
				var pb: float = m._pips
				var p0: Vector3 = ow.hero_pos
				var ok: bool = m.try_dash()
				_ag.tries.append([ok, pb])
				if ok:
					_ag.cur = {"t0": _ag_t - dt, "p0": p0, "pips_before": pb}
					_ag.in_dash = true
			_ag.prev_t = _ag_t
			if _ag_t > 2.9:
				var res := ""
				var pr := ""
				for tr in _ag.tries:
					res += "T" if tr[0] else "F"
					pr += "%.2f," % tr[1]
				var lt := 0.0
				var ff := -1.0
				for f in _ag.fl:
					if f[1]:
						lt = maxf(lt, float(f[0]))
					elif ff < 0.0:
						ff = float(f[0])
				var d1: Dictionary = _ag.dashes[0] if not _ag.dashes.is_empty() else {}
				_ag_say("dash", "n=%d tries=%s pips_at_try=%s dist=%.2f dur=%.3f pips_before=%.2f pips_after=%.2f iframe_last=%.3f iframe_off=%.3f fov_max=%.1f" % [
					_ag.dashes.size(), res, pr, d1.get("dist", -1.0), d1.get("dur", -1.0), d1.get("pips_before", -1.0), d1.get("pips_after", -1.0), lt, ff, _ag.max_fov])
				for q in _ag.dashes.size():
					_ag_say("dash_each", "i=%d dist=%.2f dur=%.3f" % [q, _ag.dashes[q].dist, _ag.dashes[q].dur])
				_ag_next()
		"dash_wall", "dash_water":
			var wall_ready: bool = name == "dash_water" or ow._chunks.has(ow.terrain._chunk_of(_ag_wall))
			if not _ag.has("tried") and _ag_t > 0.3 and wall_ready:
				_ag.tried = true
				_ag.p0 = ow.hero_pos
				_ag.ok = m.try_dash()
			if _ag.has("tried") and not m.dashing() and _ag_t > 0.6:
				var dist: float = (ow.hero_pos - (_ag.p0 as Vector3)).length()
				var bad: bool = ow.terrain._blocked(ow.hero_pos)
				var in_water := Land.is_water(ow.hero_pos.x, ow.hero_pos.z)
				_ag_say(name, "started=%s dist=%.2f stopped=%s hero_blocked=%s in_water=%s" % [_ag.ok, dist, m.dash_stopped, bad, in_water])
				_ag_wall_on = false
				_ag_next()
		"road":
			out = Vector2(0, -1)
			if not _ag.has("run") and _ag_t >= 0.9:
				_ag.run = m._spd
			if s >= 100.0 or _ag_t > 9.0:
				_ag_say("road", "run=%.2f sprint=%.2f sprinting=%s t=%.2f" % [_ag.get("run", -1.0), m._spd, m._sprinting, _ag_t])
				_ag_next()
	return out


## ---- Real-path movement test (tools/check.js scenario `agility-real`): `--autoplay=gather
## --agility-real`. The land keeps all its obstacles. The game's own movement (_move_hero: the safety
## net, slicing, _try_move, the dash) is stepped by hand in slices of 1/60, 1/30 and 1/20 s, so the
## numbers are game time and do not depend on how fast the machine draws. Prints "AGREAL <name> k=v".
const AR_FPS := [60, 30, 20]
var agreal := false
var _ar_on := false
var _ar_in := false
var _ar_surr := false
var _ar_clock := 0.0
var _ar_started := false


func agreal_intercept(delta: float) -> bool:
	if _ar_on and not _ar_in:
		ow._t -= delta  # the frame's own time is not ours: the test keeps its own clock
		return true
	return false


func agreal_hold() -> bool:
	return _ar_on and not _ar_surr


func _process(_delta: float) -> void:
	if questbot != "":
		if not _qb_started and ow.hero != null and ow.hud != null and ow.duel == null:
			_qb_started = true
			ow.started = true
			Run.title_seen = true
			if questbot == "save":
				_qs_main()
			elif questbot == "touch":
				_qt_main()
			elif questbot.begins_with("shot-"):
				_qshot_main(questbot.trim_prefix("shot-"))
			else:
				_qb_main()
		qb_poll()
		return
	if agreal and not _ar_started and ow.hero != null and ow.started and ow.hud != null and ow.duel == null:
		_ar_started = true
		_ar_on = true
		_ar_main()


func _ar_say(name: String, kv: String) -> void:
	print("AGREAL %s %s" % [name, kv])


func _ar_frame() -> void:
	await ow.get_tree().process_frame


## One slice of the real movement code with this stick.
func _ar_step(dt: float, stick: Vector2, surroundings := false) -> void:
	ow._t += dt
	_ar_clock += dt
	ow.stick = stick
	var keep := ow._bot
	ow._bot = ""
	_ar_in = true
	ow.mover._move_hero(dt)
	_ar_in = false
	ow._bot = keep
	if surroundings:
		_ar_surr = true
		ow.interaction._check_surroundings(dt)
		_ar_surr = false
	ow.stick = Vector2.ZERO


## Run for `seconds` of game time in slices of 1/fps. until is an optional Callable returning
## true to stop early; returns the game time used.
func _ar_run(seconds: float, fps: int, stick: Vector2, until := Callable(), surroundings := false) -> float:
	var dt := 1.0 / fps
	var t := 0.0
	var n := 0
	while t < seconds - 1e-6:
		_ar_step(dt, stick, surroundings)
		t += dt
		n += 1
		if until.is_valid() and until.call():
			break
		if ow.duel != null:
			break
		if n % 90 == 0:
			await _ar_frame()
	return t


func _ar_get(obj: Object, prop: String, fallback: Variant) -> Variant:
	var v: Variant = obj.get(prop)
	return fallback if v == null else v


func _ar_unstuck() -> int:
	return int(_ar_get(ow.mover, "unstuck_count", 0))


func _ar_ready(p: Vector3) -> void:
	# Let the land stream in around p by the game's own path (frames), as it does in play.
	var guard := 0
	ow.terrain._update_chunks()
	while guard < 900:
		var c: Vector2i = ow.terrain._chunk_of(p)
		var ok := true
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				if not ow._chunks.has(c + Vector2i(dx, dz)):
					ok = false
		if ok:
			return
		guard += 1
		await _ar_frame()


func _ar_put(p: Vector3, yaw := 0.0) -> void:
	p.y = Land.walk_height(p.x, p.z)
	ow.hero_pos = p
	ow.hero_yaw = yaw
	ow.cam_yaw = yaw
	ow.look_cool = 1e9
	ow.hero.position = p
	ow.mover.reset_motion()
	ow.mover._pips = ow.mover._pip_max
	ow.mover._lock = 0.0
	ow.mover._end_xz = Vector2(p.x, p.z)
	ow._last_safe = p
	ow._gather = {}


func _ar_obstacles(near: Vector3, radius: float) -> Array:
	var out: Array = []
	for k in ow._chunks:
		for o in ow._chunks[k].obstacles:
			if Vector2(o.x - near.x, o.y - near.z).length() < radius:
				out.append({"chunk": ow._chunks[k], "o": o})
	return out


func _ar_free_disc(p: Vector3, r: float) -> bool:
	for i in 12:
		var a := TAU * i / 12.0
		if not ow.mover.is_free(p + Vector3(cos(a) * r, 0, sin(a) * r)):
			return false
	return ow.mover.is_free(p)


## A straight lane, nothing on it, 40 u long and 3 u each side, nearest the start.
func _ar_lane() -> Dictionary:
	var origins: Array = []
	for x in range(-60, 61, 10):
		for z in range(0, 90, 10):
			origins.append(Vector3(x, 0, z))
	origins.sort_custom(func(a, b): return a.distance_to(Land.START) < b.distance_to(Land.START))
	for o in origins:
		for k in 8:
			var dir := Vector3(cos(k * PI / 4.0), 0, sin(k * PI / 4.0))
			var good := true
			var q := 0.0
			while q <= 40.0 and good:
				good = _ar_free_disc(o + dir * q, 2.5) and _ag_ok(o + dir * q)
				q += 2.0
			if good:
				return {"o": o, "d": dir}
	return {}


func _ar_main() -> void:
	Engine.time_scale = 1.0
	for sk in Craft.COMBAT:
		Run.data.skills[sk] = Craft.xp_for(45)
	await _ar_ready(ow.hero_pos)
	await _ar_frame()
	var lane := _ar_lane()
	if lane.is_empty():
		print("AGREAL fail no free lane")
		ow.get_tree().quit()
		return
	_ar_say("lane", "x=%.0f z=%.0f dir=%.2f,%.2f" % [lane.o.x, lane.o.z, lane.d.x, lane.d.z])
	await _ar_trap(lane)
	await _ar_slide()
	await _ar_dash_obstacle(lane)
	await _ar_manual(lane)
	await _ar_xp(lane)
	await _ar_duels()
	await _ar_iframes(lane)
	await _ar_tower()
	print("AGREAL done")
	ow.get_tree().quit()


## Findings 1: put the hero in a tree, a rock and a house; the net must get it out within 1 s.
func _ar_trap(lane: Dictionary) -> void:
	var here: Vector2i = ow.terrain._chunk_of(Land.START)
	var cand := {"tree": null, "rock": null, "house": null}
	for e in _ar_obstacles(Land.START, 70.0):
		var o: Vector3 = e.o
		var k: Vector2i = ow.terrain._chunk_of(Vector3(o.x, 0, o.y))
		if absi(k.x - here.x) > 1 or absi(k.y - here.y) > 1:
			continue
		var kind := ""
		if o.z <= 0.8:
			kind = "tree"
		elif o.z >= 1.1 and o.z <= 2.0:
			kind = "rock"
		elif absf(o.z - 4.4) < 0.05:
			kind = "house"
		if kind != "" and cand[kind] == null and ow.mover.is_free(Vector3(o.x + o.z + 1.0, 0, o.y)):
			cand[kind] = o
	for kind in ["tree", "rock", "house"]:
		for fps in AR_FPS:
			if cand[kind] == null:
				_ar_say("trap", "kind=%s fps=%d missing=true" % [kind, fps])
				continue
			var o: Vector3 = cand[kind]
			await _ar_trap_case(kind, fps, Vector3(o.x, 0, o.y), "")


func _ar_trap_case(kind: String, fps: int, p: Vector3, extra: String) -> void:
	ow.hero_pos = p
	await _ar_ready(p)
	_ar_put(p)
	ow._last_safe = p  # as the game leaves it after a duel: the same blocked spot
	var c0 := _ar_unstuck()
	var blocked0: bool = ow.terrain._blocked(ow.hero_pos)
	var t := await _ar_run(1.0, fps, Vector2.ZERO, func(): return not ow.terrain._blocked(ow.hero_pos))
	var free: bool = not ow.terrain._blocked(ow.hero_pos)
	_ar_say("trap", "kind=%s fps=%d start_blocked=%s free=%s t=%.3f unstuck=%d moved=%.1f%s" % [
		kind, fps, blocked0, free, t, _ar_unstuck() - c0, (ow.hero_pos - p).length(), extra])


func _ar_tower() -> void:
	var p := Vector3(Land.TOWER.x, 0, Land.TOWER.y + 12.0)
	ow.hero_pos = p
	ow.terrain._update_chunks()
	for fps in AR_FPS:
		await _ar_trap_case("tower", fps, p, "")
	_ar_put(Land.START)
	ow.terrain._update_chunks()


## Finding 2: a slide along a house wall keeps its speed (1.0 s from rest, stick 0.7).
func _ar_slide() -> void:
	var here: Vector2i = ow.terrain._chunk_of(Land.START)
	var houses: Array = []
	for e in _ar_obstacles(Land.START, 70.0):
		var o: Vector3 = e.o
		var k: Vector2i = ow.terrain._chunk_of(Vector3(o.x, 0, o.y))
		if absf(o.z - 4.4) < 0.05 and absi(k.x - here.x) <= 1 and absi(k.y - here.y) <= 1:
			houses.append(e)
	for deg in [45, 60]:
		var sa := sin(deg_to_rad(deg))
		var ca := cos(deg_to_rad(deg))
		var stick := Vector2(sa, ca) * 0.7
		for fps in AR_FPS:
			var ratio := -1.0
			var wall_d := -1.0
			var open_d := -1.0
			for h in houses:
				var o: Vector3 = h.o
				var start := Vector3(o.x - (o.z + 0.35) - 0.03, 0, o.y + 0.3)
				if not ow.mover.is_free(start) or not ow.mover.is_free(start + Vector3(0, 0, 4.0)):
					continue
				var chunk: Dictionary = h.chunk
				chunk.obstacles.erase(o)
				_ar_put(start, 0.0)
				ow.hero_yaw = atan2(-stick.x, -stick.y)
				await _ar_run(1.0, fps, stick)
				open_d = (ow.hero_pos - start).length()
				chunk.obstacles.append(o)
				_ar_put(start, 0.0)
				ow.hero_yaw = atan2(-stick.x, -stick.y)
				await _ar_run(1.0, fps, stick)
				wall_d = (ow.hero_pos - start).length()
				ratio = wall_d / open_d if open_d > 0.1 else -1.0
				if open_d > 2.0:
					break
			_ar_say("slide", "deg=%d fps=%d open=%.2f wall=%.2f ratio=%.3f" % [deg, fps, open_d, wall_d, ratio])


## Finding 3: dashes at an obstacle 0.3, 0.6, 1.0 and 3 u ahead.
func _ar_dash_obstacle(lane: Dictionary) -> void:
	var d: Vector3 = lane.d
	var m = ow.mover
	for fps in AR_FPS:
		for dist in [0.3, 0.6, 1.0, 3.0]:
			var o: Vector3 = lane.o
			_ar_put(o, atan2(-d.x, -d.z))
			m._pips = 2.0
			var wall: Vector3 = o + d * (float(dist) + 0.5 + 0.35)
			var chunk: Dictionary = ow._chunks.get(ow.terrain._chunk_of(wall), {})
			if chunk.is_empty():
				_ar_say("dash_obstacle", "dist=%.1f fps=%d missing=true" % [dist, fps])
				continue
			var ob := Vector3(wall.x, wall.z, 0.5)
			chunk.obstacles.append(ob)
			var before: float = m.dash_pips()
			var ok: bool = m.try_dash()
			var t := await _ar_run(0.6, fps, Vector2.ZERO)
			var moved := (ow.hero_pos - o).dot(d)
			var inside: bool = ow.terrain._blocked(ow.hero_pos)
			var after: float = m.dash_pips()
			chunk.obstacles.erase(ob)
			_ar_say("dash_obstacle", "dist=%.1f fps=%d started=%s moved=%.2f pips_before=%.2f pips_after=%.2f t=%.2f inside=%s" % [
				dist, fps, ok, moved, before, after, t, inside])


## Manual Unstuck: moves, cooldown, and the refusals.
func _ar_manual(lane: Dictionary) -> void:
	var m = ow.mover
	if not m.has_method("manual_unstuck"):
		_ar_say("manual", "missing=true")
		return
	var d: Vector3 = lane.d
	var o: Vector3 = lane.o
	var far := o + d * 30.0
	_ar_put(far)
	ow._last_safe = o + d * 20.0
	ow.duels.last_fight_t = -99.0
	ow.duels._pvp_pending = "x"
	var r_pvp: Dictionary = m.manual_unstuck()
	ow.duels._pvp_pending = ""
	ow.duels.last_fight_t = ow._t - 1.0
	var r_fight: Dictionary = m.manual_unstuck()
	ow.duels.last_fight_t = -99.0
	var foe := _ar_foe(far + d * 5.0)
	ow.ents.append(foe)
	var r_foe: Dictionary = m.manual_unstuck()
	ow.ents.erase(foe)
	(foe.node as Node).queue_free()
	var at0 := ow.hero_pos
	var c0 := _ar_unstuck()
	var r1: Dictionary = m.manual_unstuck()
	var moved1 := (ow.hero_pos - at0).length()
	await _ar_run(0.5, 30, Vector2.ZERO)
	var at1 := ow.hero_pos
	var r2: Dictionary = m.manual_unstuck()
	await _ar_run(9.0, 30, Vector2.ZERO)
	var r3: Dictionary = m.manual_unstuck()
	await _ar_run(0.6, 30, Vector2.ZERO)
	var at2 := ow.hero_pos
	var r4: Dictionary = m.manual_unstuck()
	var moved4 := (ow.hero_pos - at2).length()
	_ar_say("manual", "refuse_pvp=%s refuse_fight=%s refuse_foe=%s first_ok=%s moved=%.1f free=%s count=%d second_ok=%s at_9_5=%s at_10_1=%s moved_again=%.1f free_again=%s" % [
		not r_pvp.ok, not r_fight.ok, not r_foe.ok, r1.ok, moved1, not ow.terrain._blocked(at1), _ar_unstuck() - c0, r2.ok, r3.ok, r4.ok, moved4, not ow.terrain._blocked(ow.hero_pos)])


func _ar_foe(pos: Vector3) -> Dictionary:
	var v := PlaceholderVisual.new()
	ow.add_child(v)
	v.configure(EnemyDef.make_wild("thrall").look)
	pos.y = Land.walk_height(pos.x, pos.z)
	v.position = pos
	return {"id": "agreal_foe", "type": "foe", "kind": "wild", "wild": "thrall", "biome": "hearthvale", "pos": pos, "home": pos + Vector3(40, 0, 0),
		"node": v, "label": "Test", "height": 2.4}


func _ar_wait_duel() -> void:
	var guard := 0
	while ow.duel != null and guard < 6000:
		guard += 1
		await _ar_frame()
	await _ar_frame()


## Finding 1(b): a duel that ends with the hero on the stand point inside an obstacle.
func _ar_duels() -> void:
	var here: Vector2i = ow.terrain._chunk_of(Land.START)
	var picks: Array = []
	for e in _ar_obstacles(Land.START, 70.0):
		var o: Vector3 = e.o
		var k: Vector2i = ow.terrain._chunk_of(Vector3(o.x, 0, o.y))
		if absi(k.x - here.x) <= 1 and absi(k.y - here.y) <= 1:
			picks.append(o)
	var want := {"tree": [0.0, 0.8], "house": [4.35, 4.45]}
	for kind in ["tree", "house"]:
		var o_found = null
		var h_found = null
		var f_found = null
		for o in picks:
			if o.z < want[kind][0] or o.z > want[kind][1]:
				continue
			var gap := 3.0 if kind == "tree" else 16.0
			for a in 8:
				var dir := Vector3(cos(a * PI / 4.0), 0, sin(a * PI / 4.0))
				var b := Basis.looking_at(dir, Vector3.UP)
				var mid := Vector3(o.x, 0, o.y) - b * Vector3(-1.2, 0, 2.0)
				var hp := mid - dir * gap * 0.5
				if ow.mover.is_free(hp):
					o_found = o
					h_found = hp
					f_found = mid + dir * gap * 0.5
					break
			if o_found != null:
				break
		if o_found == null:
			_ar_say("duel", "kind=%s missing=true" % kind)
			continue
		await _ar_ready(h_found)
		_ar_put(h_found)
		var foe := _ar_foe(f_found)
		var c0 := _ar_unstuck()
		ow.duels._start_duel(foe)
		await _ar_wait_duel()
		var saved := Vector3(float(Run.data.ow_x), 0, float(Run.data.ow_z))
		var at_start: bool = ow.hero_pos.distance_to(Land.START) < 1.0
		_ar_say("duel", "kind=%s hero_blocked=%s saved_blocked=%s at_start=%s unstuck=%d stand_dist=%.1f" % [
			kind, ow.terrain._blocked(ow.hero_pos), ow.terrain._blocked(saved), at_start, _ar_unstuck() - c0,
			ow.hero_pos.distance_to(Vector3(o_found.x, 0, o_found.y))])
		if is_instance_valid(foe.node):
			(foe.node as Node).queue_free()
		Engine.time_scale = 1.0
		_ar_put(Land.START)
		await _ar_ready(Land.START)


## Finding 4: no duel in the first 0.18 s of a dash through a foe's trigger; one after.
func _ar_iframes(lane: Dictionary) -> void:
	var d: Vector3 = lane.d
	var o: Vector3 = lane.o
	var m = ow.mover
	for fps in [30, 60]:
		_ar_put(o, atan2(-d.x, -d.z))
		var foe := _ar_foe(o + d * 4.0)
		ow.ents.append(foe)
		var keep := ow._bot
		ow._bot = "agreal"
		var ok: bool = m.try_dash()
		var t := 0.0
		var started := -1.0
		var dt: float = 1.0 / float(fps)
		while t < 1.0 and ow.duel == null:
			_ar_step(dt, Vector2.ZERO, true)
			t += dt
		if ow.duel != null:
			started = t
		var rest := ow.duel != null
		ow._bot = keep
		ow.ents.erase(foe)
		_ar_say("iframes", "fps=%d dash_ok=%s duel_at=%.3f" % [fps, ok, started])
		await _ar_wait_duel()
		if is_instance_valid(foe.node):
			(foe.node as Node).queue_free()
		Engine.time_scale = 1.0
		_ar_put(o, atan2(-d.x, -d.z))


## Agility XP per second (0.2 XP per unit counted) walking, running, sprinting on the road and
## spamming dashes. The cap is the old run speed: 8.5 u/s = 1.7 XP/s.
func _ar_xp(lane: Dictionary) -> void:
	var d: Vector3 = lane.d
	var m = ow.mover
	var out := {}
	for case in ["walk", "run", "sprint_road", "dash_spam"]:
		if case == "sprint_road":
			_ar_put(Vector3(0, 0, -25), Vector3(0, 0, -1).angle_to(Vector3.FORWARD))
			ow.hero_yaw = 0.0
		else:
			_ar_put(lane.o, atan2(-d.x, -d.z))
		var stick := Vector2.ZERO
		var secs := 5.0
		match case:
			"walk": stick = Vector2(0, -0.5)
			"run": stick = Vector2(0, -0.9)
			"sprint_road":
				stick = Vector2(0, -1.0)
				secs = 7.0
		if case != "sprint_road":
			# The stick is relative to the camera, which _ar_put turned to face the lane.
			pass
		var x0: float = float(_ar_get(m, "xp_dist", 0.0))
		if case == "dash_spam":
			var t := 0.0
			while t < secs:
				m._pips = m._pip_max
				m._lock = 0.0
				m.try_dash()
				t += await _ar_run(0.4, 30, Vector2.ZERO)
		else:
			await _ar_run(secs, 30, stick)
		out[case] = (float(_ar_get(m, "xp_dist", 0.0)) - x0) * 0.2 / secs
	_ar_say("xp", "walk=%.2f run=%.2f sprint_road=%.2f dash_spam=%.2f" % [out.walk, out.run, out.sprint_road, out.dash_spam])


# ================================================================ quest bot
## `--autoplay=gather --questbot=act1` plays Act 1 from a fresh save through the real hooks: it stands the hero
## beside each NPC or place (debug shortcut for travel time), presses E (Overworld.interact) and taps through the
## real dialogue boxes, takes `--pick`th choice at each choice, starts the duels itself with the real
## Duel and Quests.on_kill hooks, and (tower part, world_bot.gd) takes the relic and beats the Cinder Warden.
## Shortcuts: travel, combat skills at 45, raw materials for the bring steps (gathering is the `gather` scenario's
## business). It prints QUEST lines (start, step, done), CHECK and TEXT lines, and ACT1 DONE or ACT1 FAIL.
## `--questbot=save` loads whatever save the page has (a fixture) and prints QSAVE lines, see _qs_main.

static func qb_say(line: String) -> void:
	print(line)


static func qb_fail(msg: String) -> void:
	Engine.set_meta("qb_fails", int(Engine.get_meta("qb_fails", 0)) + 1)
	print("ACT1 FAIL %s" % msg)


static func qb_check(ok: bool, what: String) -> void:
	if ok:
		print("CHECK ok %s" % what)
	else:
		qb_fail("check: " + what)


## Print one line for every change in any quest's saved state since the last call.
static func qb_poll() -> void:
	var snap: Dictionary = Engine.get_meta("qb_snap", {})
	var t := (Time.get_ticks_msec() - int(Engine.get_meta("qb_t0", Time.get_ticks_msec()))) / 1000
	for id in Quests.ids():
		var st: Dictionary = Run.data.quests.get(id, {})
		var key := "" if st.is_empty() else "%d,%d,%s" % [int(st.step), int(st.count), str(st.done)]
		if snap.get(id, "") == key:
			continue
		var old: String = snap.get(id, "")
		snap[id] = key
		if st.is_empty():
			continue
		if old == "":
			print("QUEST start %s t=%d" % [id, t])
		if st.done:
			print("QUEST done %s t=%d" % [id, t])
		else:
			var steps: Array = Quests.QUESTS[id].steps
			var cur := int(st.step)
			if old == "" or int(old.split(",")[0]) != cur:
				print("QUEST step %s %d/%d %s t=%d" % [id, cur + 1, steps.size(), steps[cur].text.left(60), t])
	Engine.set_meta("qb_snap", snap)


func _qb_rows(text: String, size_px: int, width: float) -> int:
	return ow.hud.rows_for(text, size_px, width)


func _qb_lines_of(v: Variant) -> Array:
	var out: Array = []
	if v is String:
		if v != "":
			out.append(v)
	elif v is Array:
		for x in v:
			out.append_array(_qb_lines_of(x))
	elif v is Dictionary:
		for pair in v.get("if", []):
			out.append_array(_qb_lines_of(pair[1]))
		out.append_array(_qb_lines_of(v.get("else", "")))
	return out


func _qb_text_fail(kind: String, text: String, detail: String) -> void:
	qb_fail("TEXT overflow %s (%s): %s" % [kind, detail, text.left(70)])


func _qb_check_line(text: String, with_choices: bool, kind := "talk") -> void:
	var rows := _qb_rows(text, 22, ow.hud.talk_width(with_choices))
	var limit := 5
	if rows > limit:
		_qb_text_fail(kind, text, "%d rows, limit %d" % [rows, limit])


## Every line of Act 1 data measured against its box, whichever variant is shown.
func _qb_audit() -> void:
	var hud: WorldHud = ow.hud
	var n := 0
	var jw := hud._panel().size.x - 88.0
	for id in Quests.ids():
		var q: Dictionary = Quests.QUESTS[id]
		for l in _qb_lines_of(q.get("offer", [])) + _qb_lines_of(q.get("finish", [])):
			_qb_check_line(l, false, "%s offer/finish" % id)
			n += 1
		for lab in [q.get("accept", "I will do it."), q.get("decline", "Not now.")]:
			if hud.text_width(lab, 19) > 426.0:
				_qb_text_fail("choice", lab, id)
		var j := Quests.journal_text(id)
		if _qb_rows(j, 17, jw) > 3:
			_qb_text_fail("journal", j, id)
		for st in q.steps:
			var tr: String = "%s: %s" % [q.name, st.get("track", st.text)]
			if hud.text_width(tr, 15) > 520.0:
				_qb_text_fail("tracker", tr, id)
			if _qb_rows(st.text, 17, jw) > 3:
				_qb_text_fail("step", st.text, id)
			for l in _qb_lines_of(st.get("say", [])):
				_qb_check_line(l, st.do == "choose", "%s say" % id)
				n += 1
			for c in st.get("choices", []):
				if hud.text_width(c[0], 19) > 426.0:
					_qb_text_fail("choice", c[0], id)
			for k in st.get("reply", {}):
				for l in _qb_lines_of(st.reply[k]):
					_qb_check_line(l, false, "%s reply" % id)
					n += 1
	for npc in Story.Act1.IDLE:
		for l in _qb_lines_of(Story.Act1.IDLE[npc]):
			_qb_check_line(l, false, "idle " + npc)
			n += 1
	for nm in Story.Act1.BARKS:
		for m in Story.Act1.BARKS[nm]:
			for l in _qb_lines_of(Story.Act1.BARKS[nm][m]):
				if l.length() > 60:
					_qb_text_fail("bark", l, nm)
				n += 1
	for lid in Story.Act1.LORE:
		if _qb_rows(Story.Act1.LORE[lid].text, 17, jw) > 3:
			_qb_text_fail("lore", Story.Act1.LORE[lid].text, lid)
	print("TEXT audited %d lines" % n)


## Quest strings that reach the caption box through Run.captions (reach and kill steps).
func _qb_caption_scan() -> void:
	var seen: Dictionary = Engine.get_meta("qb_cap", {})
	var all: Array = Run.captions.duplicate()
	if ow.hud._caption != "":
		all.append(ow.hud._caption)
	for c in all:
		if seen.has(c):
			continue
		seen[c] = true
		var rows := _qb_rows(c, 22, 716.0)
		if rows > 3:
			_qb_text_fail("caption", c, "%d rows at 716 px" % rows)
	Engine.set_meta("qb_cap", seen)


func _qb_frames(n: int) -> void:
	for i in n:
		await _ar_frame()
		_qb_caption_scan()


func _qb_pos(id: String) -> Vector3:
	for pl in Land.PLACES:
		if pl.id == id:
			return Vector3(pl.pos.x, 0, pl.pos.y)
	return Vector3.ZERO


## Stand the hero beside a place or NPC until the game itself says it is the nearest thing (so the real
## prompt and hooks apply).
func _qb_stand(id: String) -> bool:
	var c := _qb_pos(id)
	_ar_put(c)
	await _ar_ready(c)
	# Free ground within reach of the thing, nearest first, starting on the village side (where the road is).
	var toward := atan2(Land.VILLAGE.y - c.z, Land.VILLAGE.x - c.x)
	var tried := 0
	for r in [1.4, 1.8, 2.2, 2.6, 2.9]:
		for k in 16:
			var a := toward + TAU * k / 16.0
			var at: Vector3 = c + Vector3(cos(a) * r, 0, sin(a) * r)
			if not ow.mover.is_free(at):
				continue
			tried += 1
			_ar_put(at)
			await _qb_frames(3)
			if ow.near.get("id", "") == id:
				return true
			if tried >= 4:
				break
		if tried >= 4:
			break
	var around: Array = []
	for e in ow.ents:
		var d: float = Vector2(e.pos.x - ow.hero_pos.x, e.pos.z - ow.hero_pos.z).length()
		if d < 12.0:
			around.append("%s/%s@%.1f" % [e.get("id", "?"), e.type, d])
	qb_fail("could not stand at %s: hero (%.1f,%.1f) wanted (%.1f,%.1f) near=%s ents=%s hud=%s" % [id, ow.hero_pos.x, ow.hero_pos.z, c.x, c.z, ow.near.get("id", "none"), str(around), ow.hud.screen])
	return false


func _qb_leave(place: String) -> void:
	# Away first so that arriving again counts as reaching it again.
	_ar_put(Vector3(0, 0, 30))
	await _qb_frames(3)


func _qb_reach(place: String) -> void:
	await _qb_leave(place)
	await _qb_stand(place)
	await _qb_frames(2)


## Press E at an NPC and tap through the box. Returns the lines shown.
func _qb_talk(npc: String) -> Array:
	var shown: Array = []
	if not await _qb_stand(npc):
		return shown
	ow.interact()
	await _qb_frames(2)
	var hud: WorldHud = ow.hud
	if hud.screen != "talk":
		if hud.screen != "":
			hud._close()
		return shown
	var guard := 0
	while hud.screen == "talk" and guard < 40:
		guard += 1
		var d: Dictionary = hud._talk
		var ls: Array = d.lines
		var i := int(d.i)
		var last := i >= ls.size() - 1
		var choices: Array = d.choices if last else []
		_qb_check_line(ls[i], not choices.is_empty())
		shown.append(ls[i])
		if not choices.is_empty():
			var pick := -1
			var nth := 0
			for k in choices.size():
				var act: String = choices[k][1]
				if hud.text_width(choices[k][0], 19) > 426.0:
					_qb_text_fail("choice", choices[k][0], "dialogue")
				if act.begins_with("accept:") and pick < 0:
					pick = k
				elif act.begins_with("choose:"):
					if nth == _qb_pick or k == choices.size() - 1:
						if pick < 0:
							pick = k
					nth += 1
			if pick < 0:
				pick = choices.size() - 1
			print("TALK %s picks '%s' (%s)" % [npc, choices[pick][0], choices[pick][1]])
			hud._press(0, hud.choice_center(pick))
			if hud.screen == "shop" or hud.screen == "store":
				hud._close()
		else:
			hud._press(0, hud.size * 0.5)
		await _qb_frames(1)
	if hud.screen != "":
		qb_fail("dialogue with %s did not close" % npc)
		hud._close()
	return shown


func _qb_spots(wilds: Array) -> Array:
	var out: Array = []
	for x in range(-200, 220, 20):
		for z in range(-250, 200, 20):
			if not Land.in_bounds(x, z) or Land.is_water(x, z):
				continue
			var b: Dictionary = Land.BIOMES[Land.biome(x, z)]
			if b.foe in wilds or b.get("alt", "") in wilds:
				out.append(Vector3(x, 0, z))
	out.sort_custom(func(a, b): return Land.START.distance_to(a) < Land.START.distance_to(b))
	return out


func _qb_foe(wilds: Array) -> Dictionary:
	var best := {}
	var bd := 1e9
	for e in ow.ents:
		if e.type == "foe" and e.wild in wilds and e.node != null:
			var d: float = (e.pos as Vector3).distance_to(ow.hero_pos)
			if d < bd:
				bd = d
				best = e
	return best


## Fight real land foes of these kinds, one duel at a time through Duel and Run.on_win, until done.call().
func _qb_kill(wilds: Array, done: Callable) -> void:
	var spots := _qb_spots(wilds)
	var si := 0
	var tries := 0
	while not done.call() and tries < 60:
		tries += 1
		var f := _qb_foe(wilds)
		if f.is_empty():
			if spots.is_empty():
				qb_fail("no land where %s live" % str(wilds))
				return
			var c: Vector3 = spots[si % spots.size()]
			si += 1
			_ar_put(c)
			await _ar_ready(c)
			await _qb_frames(8)
			continue
		var at: Vector3 = f.pos
		_ar_put(at + Vector3(0, 0, 3.0))
		await _qb_frames(2)
		if f.node == null or not is_instance_valid(f.node):
			continue
		print("KILL duel with %s" % f.wild)
		ow.duels._start_duel(f)
		await _ar_wait_duel()
		await _qb_frames(2)
		if "--reload" in OS.get_cmdline_user_args() and qb_rl_count() == 1 and _qb_state("poach") == 0 and int(Quests.state("poach").get("count", 0)) >= 1:
			qb_reload("midkill")
			while true:
				await _qb_frames(1)
	if not done.call():
		qb_fail("kills not completed for %s" % str(wilds))


func _qb_mats(m: Dictionary) -> void:
	for k in m:
		Run.add_mat(k, int(m[k]))


func _qb_cook() -> void:
	for r in Craft.RECIPES:
		if r.name == "Grilled trout":
			Run.add_mat("trout", 1)
			Craft.make(r)
			return


const OLD_FIVE := ["forge", "line", "poach", "mire", "oath"]
const ACT1_PRIOR := ["forge", "line", "poach", "mire", "oath", "a1_thirty_first", "a1_bone", "a1_tam", "a1_struck", "a1_diggers", "a1_hand"]


static func qb_rl_count() -> int:
	if not OS.has_feature("web"):
		return 0
	return int(JavaScriptBridge.eval("parseInt(sessionStorage.getItem('qb_rl')||'0')", true))


## Save, print the save (so a scenario can keep it as a fixture), and reload the page: the game then
## starts from what it wrote, as a player coming back would.
static func qb_reload(point: String) -> void:
	Run.save()
	print("SAVEDUMP %s %s" % [point, JSON.stringify(Run.data)])
	print("ACT1 reloading at %s" % point)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("sessionStorage.setItem('qb_rl','%d');setTimeout(function(){location.reload()},50)" % (qb_rl_count() + 1))


static func qb_seed(kind: String) -> void:
	Run.data.quests = {}
	for id in ACT1_PRIOR:
		Run.data.quests[id] = {"step": 0, "count": 0, "done": true}
	Run.data.flags = {"oath": "keep", "poach": "tally", "a1_hand": "ask"}
	if kind == "vet":
		Run.data.relics = [1]
		Run.data.unlocked = 2
		Run.data.best_floor = 2
	Quests.touch()


## The state a quest is in as a number: -1 not started, the step index, 99 done.
func _qb_state(id: String) -> int:
	if not Quests.started(id):
		return -1
	if Quests.state(id).get("done", false):
		return 99
	return int(Quests.state(id).get("step", -1))


func _qb_until(npc: String, quest: String, target: int, tries := 4) -> Array:
	var shown: Array = []
	var n := 0
	while _qb_state(quest) < target and n < tries:
		n += 1
		shown = await _qb_talk(npc)
	if _qb_state(quest) < target:
		qb_fail("%s did not reach state %d talking to %s (at %d)" % [quest, target, npc, _qb_state(quest)])
	return shown


func _qb_need(m: Dictionary) -> void:
	for k in m:
		if Run.mat(k) < int(m[k]):
			Run.add_mat(k, int(m[k]) - Run.mat(k))


func _qb_main() -> void:
	var resumed: bool = not Run.data.quests.is_empty()
	if not Engine.has_meta("qb_t0"):
		Engine.set_meta("qb_t0", Time.get_ticks_msec())
		Engine.set_meta("qb_fails", 0)
	var chk := not resumed
	var rl: bool = "--reload" in OS.get_cmdline_user_args()
	var seed_kind := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_kind = a.trim_prefix("--seed=")
	if rl:
		Run.no_save = false
	if seed_kind != "" and not resumed and not Engine.has_meta("qb_seeded"):
		Engine.set_meta("qb_seeded", true)
		qb_seed(seed_kind)
		chk = false
	var weak: bool = seed_kind == "die" and not Engine.has_meta("qb_died")
	for sk in Craft.COMBAT:
		Run.data.skills[sk] = Craft.xp_for(1 if weak else 45)
	Run.data.skills["foraging"] = Craft.xp_for(20)
	if weak:
		Run.data.potions = 0
	if resumed and Run.data.bloodline >= 2 and seed_kind != "die":
		pass
	print("ACT1 start pick=%d bloodline=%d combat=%d resumed=%s reloads=%d seed=%s" % [_qb_pick, Run.data.bloodline, Run.combat_level(), str(resumed), qb_rl_count(), seed_kind])
	if resumed and Quests.recent.is_empty():
		# Straight after a reload nothing has advanced this session: the tracker must still lead with the main line.
		var main_open := false
		for m in Quests.MAIN:
			if Quests.active(m):
				main_open = true
		var shows_main := false
		for tid in Quests.tracker_ids():
			if tid in Quests.MAIN:
				shows_main = true
		qb_check(not main_open or shows_main, "after the reload the tracker shows a main-line quest %s" % str(Quests.tracker_ids()))
	if chk:
		_qb_audit()
		for id in ["a1_bone", "a1_tam", "a1_struck", "a1_diggers", "a1_stair"]:
			qb_check(not Quests.offerable(id), "%s is not offered at the start" % id)
		qb_check(not Quests.started("a1_hand"), "a1_hand has not started")
	if seed_kind == "die" and Engine.has_meta("qb_died") and not Engine.has_meta("qb_died_checked"):
		Engine.set_meta("qb_died_checked", true)
		qb_check(int(Run.data.bloodline) == 2, "died in the tower: a new heir (bloodline 2)")
		qb_check(_qb_state("a1_stair") >= 0 and _qb_state("a1_stair") < 99, "a1_stair is still open after the death")
		qb_check(not Run.data.inventory.has("wardens_brand") and str(Run.data.flags.get("act", "")) != "2", "nothing from a1_stair was paid by the death")
		qb_check(int(Engine.get_meta("qb_stair_step", 0)) <= _qb_state("a1_stair"), "a1_stair did not go backwards (was %d, now %d)" % [int(Engine.get_meta("qb_stair_step", 0)), _qb_state("a1_stair")])
		Engine.set_meta("qb_gold_mark", int(Run.data.gold))

	if seed_kind == "":
		# 1. Maren: The Thirty-First, then The First Oath.
		await _qb_until("elder", "a1_thirty_first", 0)
		await _qb_until("elder", "oath", 0)
		# 2. The oath, before the thirty-first is finished: a1_hand must wait.
		if _qb_state("oath") == 0:
			await _qb_reach("tower")
		if _qb_state("oath") == 1:
			await _qb_reach("altar")
		if chk:
			var early := Quests.talk("elder")
			qb_check(early.choices.size() == 2 and _qb_state("oath") == 2, "oath choice waits at Maren")
		await _qb_until("elder", "oath", 99)
		if _qb_state("a1_thirty_first") < 99:
			qb_check(not Quests.started("a1_hand"), "a1_hand waits for a1_thirty_first")
		# 3. Brannoc, Wren, Maren: the thirty-first.
		await _qb_until("smith", "a1_thirty_first", 1)
		if rl and qb_rl_count() == 0:
			qb_reload("talkstep")
			return
		await _qb_until("alchemist", "a1_thirty_first", 2)
		var gold := int(Run.data.gold)
		await _qb_until("elder", "a1_thirty_first", 99)
		if chk:
			qb_check(int(Run.data.gold) >= gold + 30, "a1_thirty_first paid 30 gold")
			var premature := Quests.talk("elder")
			qb_check(premature.choices.is_empty() and _qb_state("a1_hand") == 0, "a1_hand cannot finish before the altar")
		qb_check(Run.data.lore.has("letter_thirtieth"), "letter_thirtieth is in the lore save key")
		qb_check(_qb_state("a1_hand") >= 0, "a1_hand started by itself")
		# 4. Brannoc: forge, then a1_bone.
		await _qb_until("smith", "forge", 0)
		if _qb_state("forge") == 0:
			if chk:
				await _qb_talk("smith")
				qb_check(_qb_state("forge") == 0, "forge waits for its materials")
			_qb_need({"copper_ore": 4, "oak_log": 2})
		await _qb_until("smith", "forge", 99)
		await _qb_until("smith", "a1_bone", 0)
		if _qb_state("a1_bone") == 0 and Run.mat("bone") < 2:
			await _qb_kill(["thrall"], func(): return Run.mat("bone") >= 2)
		await _qb_until("smith", "a1_bone", 99)
		# 5. Old Tam.
		await _qb_until("fisher", "line", 0)
		if _qb_state("line") == 0:
			_qb_need({"trout": 3})
		await _qb_until("fisher", "line", 1)
		if _qb_state("line") == 1 and Run.mat("meal_trout") < 1:
			_qb_cook()
		await _qb_until("fisher", "line", 99)
		await _qb_until("fisher", "a1_tam", 0)
		if _qb_state("a1_tam") == 0:
			await _qb_reach("circle")
		await _qb_until("fisher", "a1_tam", 99)
		# 6. Warden Isolde.
		await _qb_until("ranger", "poach", 0)
		if _qb_state("poach") == 0:
			await _qb_kill(["bandit", "poacher"], func(): return _qb_state("poach") >= 1)
		await _qb_until("ranger", "poach", 99)
		await _qb_until("ranger", "a1_struck", 0)
		if _qb_state("a1_struck") == 0:
			await _qb_reach("watch")
		await _qb_until("ranger", "a1_struck", 99)
		# 7. Sister Wren.
		await _qb_until("alchemist", "mire", 0)
		if _qb_state("mire") == 0:
			_qb_need({"bogroot": 3})
		await _qb_until("alchemist", "mire", 1)
		if _qb_state("mire") == 1:
			await _qb_reach("shrine")
		if _qb_state("mire") == 2:
			await _qb_kill(["hexer"], func(): return _qb_state("mire") >= 3)
		await _qb_until("alchemist", "mire", 99)
		await _qb_until("alchemist", "a1_diggers", 0)
		if _qb_state("a1_diggers") == 0:
			await _qb_kill(["wight"], func(): return _qb_state("a1_diggers") >= 1)
		await _qb_until("alchemist", "a1_diggers", 99)
		# 8. In One Hand.
		if _qb_state("a1_hand") < 99:
			qb_check(not Quests.offerable("a1_stair"), "a1_stair is not offered before a1_hand is done")
		if _qb_state("a1_hand") == 0:
			await _qb_reach("altar")
			qb_check(_qb_state("a1_hand") == 1, "a1_hand: altar read")
		await _qb_until("elder", "a1_hand", 99)

	# 9. The First Stair.
	var vet_lines: Array = []
	if _qb_state("a1_stair") < 0:
		vet_lines = await _qb_until("elder", "a1_stair", 0)
	if seed_kind == "vet":
		var want: String = Quests.QUESTS["a1_stair"].steps[2].text
		qb_check(_qb_state("a1_stair") == 2, "veteran: find and win passed at once, third step current")
		qb_check(not vet_lines.is_empty() and vet_lines[-1] == want, "veteran: the box shows only the new step text")
		var said: Array = []
		for st in Quests.QUESTS["a1_stair"].steps:
			said.append_array(Quests.lines(st.get("say", [])))
		var leaked := false
		for l in vet_lines:
			if l in said:
				leaked = true
		qb_check(not leaked, "veteran: narration lines are not spoken by Maren")
	if _qb_state("a1_stair") < 2:
		var n := int(Engine.get_meta("qb_attempt", 0)) + 1
		Engine.set_meta("qb_attempt", n)
		if n > 4:
			qb_fail("the tower did not yield a1_stair step 3 in 4 tries")
			_qb_end()
			return
		if seed_kind == "die" and Engine.has_meta("qb_died"):
			for sk in Craft.COMBAT:
				Run.data.skills[sk] = Craft.xp_for(45)
		elif seed_kind == "die":
			Engine.set_meta("qb_stair_step", _qb_state("a1_stair"))
			Engine.set_meta("qb_died", true)
		print("ACT1 entering the tower, attempt %d" % n)
		await _qb_stand("tower")
		ow.interact()
		return
	var gold1 := int(Run.data.gold)
	var vit1 := Run.skill_xp("vitality")
	await _qb_until("elder", "a1_stair", 99)
	qb_check(_qb_state("a1_stair") == 99, "a1_stair done")
	qb_check(int(Run.data.gold) - gold1 == 150, "a1_stair paid 150 gold exactly once (paid %d)" % (int(Run.data.gold) - gold1))
	qb_check(Run.skill_xp("vitality") - vit1 < 400, "a1_stair xp paid once")
	qb_check(Run.data.inventory.has("wardens_brand"), "Warden's Brand received")
	qb_check(str(Run.data.flags.get("act", "")) == "2", "flag act=2 set")
	qb_check(str(Run.data.flags.get("a1_stair", "")) in ["all", "keep"], "a1_stair choice stored")
	await _qb_talk("elder")
	qb_check(_qb_state("a1_stair") == 99, "a1_stair stays done")
	_qb_end()


func _qb_end() -> void:
	var hud: WorldHud = ow.hud
	var done := 0
	var total := 0
	for id in Quests.ids():
		if int(Quests.QUESTS[id].get("act", 0)) == 1:
			total += 1
			if _qb_state(id) == 99:
				done += 1
	var bad := hud.journal_check()
	if not bad.is_empty():
		qb_fail("journal text overflows for %s" % str(bad))
	hud.open("quests")
	print("JOURNAL pages=%d lore=%s" % [hud.journal_pages(), str(Run.data.lore)])
	var secs := (Time.get_ticks_msec() - int(Engine.get_meta("qb_t0", 0))) / 1000
	var fails := int(Engine.get_meta("qb_fails", 0))
	if done != total:
		qb_fail("only %d of %d Act 1 quests done" % [done, total])
		fails += 1
	if "--reload" in OS.get_cmdline_user_args() and qb_rl_count() < 3:
		qb_fail("only %d reloads happened" % qb_rl_count())
		fails += 1
	Run.save()
	print("ACT1 %s quests=%d/%d fails=%d reloads=%d bloodline=%d secs=%d" % ["DONE" if fails == 0 else "FAILED", done, total, fails, qb_rl_count(), Run.data.bloodline, secs])
	ow.get_tree().quit()


# ---------------------------------------------------------------- quest-save

## Prints every quest's saved state (also called from the tower scene when a save was made inside it).
static func qs_report() -> void:
	print("QSAVE gold=%d flags=%s relics=%s lore=%s loop=%d bloodline=%d in_tower=%s" % [Run.data.gold, JSON.stringify(Run.data.flags), JSON.stringify(Run.data.relics), JSON.stringify(Run.data.lore), Run.data.loop, Run.data.bloodline, str(Run.data.in_tower)])
	for id in Quests.ids():
		var st: Dictionary = Run.data.quests.get(id, {})
		if st.is_empty():
			print("QSAVE state %s none" % id)
			continue
		var text := "Complete" if st.done else str(Quests.step(id).text)
		print("QSAVE state %s step=%d count=%d done=%s text=%s" % [id, int(st.step), int(st.count), str(st.done), text])


## `--autoplay=gather --questbot=save` with a save from another build in localStorage: print the quests' state,
## then finish each open one of the five old quests as a player would: walk to the NPC, press E, tap through the
## box, take the choice, fight the foes, and check what was paid.
func _qs_main() -> void:
	Engine.set_meta("qb_t0", Time.get_ticks_msec())
	qs_report()
	for sk in Craft.COMBAT:
		Run.data.skills[sk] = Craft.xp_for(45)
	Run.data.skills["foraging"] = Craft.xp_for(20)
	for id in OLD_FIVE:
		if not Quests.active(id):
			continue
		var gold0 := int(Run.data.gold)
		var guard := 0
		while Quests.active(id) and guard < 14:
			guard += 1
			var st := Quests.step(id)
			var cur := _qb_state(id)
			match st.do:
				"bring":
					_qb_need(st.mats)
					await _qb_talk(st.to)
				"talk", "choose":
					await _qb_talk(st.to)
				"reach":
					await _qb_reach(st.place)
				"kill":
					await _qb_kill(st.foes, func(): return _qb_state(id) != cur)
				_:
					guard = 99
		var r: Dictionary = Quests.QUESTS[id].reward
		var paid := int(Run.data.gold) - gold0 >= int(r.get("gold", 0))
		var item_ok: bool = not r.has("item") or Run.data.inventory.has(r.item)
		print("QSAVE finished %s done=%s paid=%s item=%s" % [id, str(not Quests.active(id)), str(paid), str(item_ok)])
	Run.save()
	print("QSAVE END")
	ow.get_tree().quit()


# ---------------------------------------------------------------- duel touches

## `--autoplay=gather --questbot=touch`: a wild duel starts beside a quest NPC while the quest wants that NPC's
## answer, and taps land on the duel's dodge button and on the world HUD's act button. No quest state, material
## or gold from a quest may change, and no dialogue may open.
func _qt_main() -> void:
	for sk in Craft.COMBAT:
		Run.data.skills[sk] = Craft.xp_for(45)
	Run.data.quests = {"a1_thirty_first": {"step": 0, "count": 0, "done": false}}
	Run.data.mats = {"copper_ore": 4, "oak_log": 2, "bone": 2}
	Quests.touch()
	await _qb_stand("smith")
	var hud: WorldHud = ow.hud
	var snap := JSON.stringify([Run.data.quests, Run.data.mats, Run.data.flags, Run.data.lore])
	var qsnap := JSON.stringify([Run.data.quests, Run.data.flags, Run.data.lore])
	qb_check(ow.near.get("id", "") == "smith", "the smith is the nearest thing when the duel begins")
	var foe := _ar_foe(ow.hero_pos + Vector3(0, 0, 3.0))
	ow.duels._start_duel(foe)
	await _qb_frames(2)
	qb_check(ow.duel != null, "a duel is running")
	var spots: Array = [(hud._buttons().act as Rect2).get_center(), (ow.duel.hud._rects().dodge_r as Rect2).get_center(), (ow.duel.hud._rects().dodge_l as Rect2).get_center()]
	for rnd in 4:
		for pos in spots:
			if ow.duel == null:
				break
			for pressed in [true, false]:
				var ev := InputEventScreenTouch.new()
				ev.index = rnd
				ev.position = pos
				ev.pressed = pressed
				Input.parse_input_event(ev)
				hud._input(ev)
		await _qb_frames(1)
	qb_check(hud.screen == "", "no dialogue opened during the duel")
	qb_check(snap == JSON.stringify([Run.data.quests, Run.data.mats, Run.data.flags, Run.data.lore]), "no quest state, material or lore changed by taps during the duel")
	await _ar_wait_duel()
	await _qb_frames(3)
	qb_check(hud.screen == "", "no dialogue open after the duel")
	# (a won duel may drop a material, so only quests, flags and lore are compared here)
	qb_check(qsnap == JSON.stringify([Run.data.quests, Run.data.flags, Run.data.lore]), "quest state unchanged after the duel")
	# And a dialogue that is open when a duel starts is closed without paying anything.
	await _qb_stand("smith")
	ow.interact()
	await _qb_frames(2)
	qb_check(hud.screen == "talk", "a dialogue is open")
	var talk_snap := JSON.stringify([Run.data.quests, Run.data.mats])
	ow.duels._start_duel(_ar_foe(ow.hero_pos + Vector3(0, 0, 3.0)))
	await _qb_frames(2)
	qb_check(hud.screen == "", "starting a duel closes an open dialogue")
	qb_check(talk_snap == JSON.stringify([Run.data.quests, Run.data.mats]), "closing the dialogue granted and consumed nothing")
	await _ar_wait_duel()
	print("TOUCH %s fails=%d" % ["DONE" if int(Engine.get_meta("qb_fails", 0)) == 0 else "FAILED", int(Engine.get_meta("qb_fails", 0))])
	ow.get_tree().quit()


# ---------------------------------------------------------------- screenshots

## `--autoplay=gather --questbot=shot-dialogue|journal|tracker|inscription`: sets up a moment of Act 1 and prints
## "SHOT ready <name>" for tools that take a picture (screens for the review).
func _qshot_main(which: String) -> void:
	Engine.time_scale = 1.0
	var done := {"step": 0, "count": 0, "done": true}
	var q := {}
	for id in ["forge", "line", "poach", "mire", "oath", "a1_thirty_first", "a1_bone", "a1_tam", "a1_struck", "a1_diggers"]:
		q[id] = done.duplicate()
	Run.data.flags = {"oath": "keep", "poach": "tally"}
	Run.data.lore = ["letter_thirtieth", "insc1_0"]
	match which:
		"dialogue":
			q["a1_hand"] = {"step": 1, "count": 0, "done": false}
		"journal":
			q["a1_hand"] = done.duplicate()
			q["a1_stair"] = {"step": 1, "count": 0, "done": false}
			Run.data.relics = [1]
		"tracker":
			q.erase("a1_struck")
			q.erase("a1_diggers")
			q.erase("a1_tam")
			q["a1_hand"] = {"step": 0, "count": 0, "done": false}
			q["poach2"] = {}
			q.erase("poach2")
			q["poach"] = {"step": 0, "count": 1, "done": false}
			q["mire"] = {"step": 2, "count": 0, "done": false}
		"inscription":
			q["a1_hand"] = {"step": 0, "count": 0, "done": false}
	Run.data.quests = q
	Quests.touch()
	_ar_put(Vector3(0, 0, 34))
	await _qb_frames(10)
	match which:
		"dialogue":
			await _qb_stand("elder")
			ow.interact()
			await _qb_frames(2)
			var hud: WorldHud = ow.hud
			var guard := 0
			while hud.screen == "talk" and int(hud._talk.i) < (hud._talk.lines as Array).size() - 1 and guard < 20:
				guard += 1
				hud._press(0, hud.size * 0.5)
				await _qb_frames(1)
		"journal":
			ow.hud.open("quests")
		"tracker":
			await _qb_stand("elder")
		"inscription":
			await _qb_reach("altar")
			var g2 := 0
			while ow.hud._caption == "" and g2 < 100:
				g2 += 1
				await _qb_frames(1)
			ow.hud._caption_age = 0.4
	await _qb_frames(6)
	print("SHOT ready %s" % which)
