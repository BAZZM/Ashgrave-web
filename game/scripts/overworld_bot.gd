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
