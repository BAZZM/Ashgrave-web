extends RefCounted

## Tower wall test bot, `--towerbot=walls|net|duelshot` (with `--shot-when=towermap` so the
## land hands straight over to the tower). Prints `TOWERBOT ...` lines; quits when done.
##
## walls:
##   spawns   tier arrival points are walkable.
##   walls    on every tier, walls are drawn exactly where the hero is blocked: points every
##            0.05 along each room edge, "blocked" (not walkable) against "inside a drawn
##            wall piece"; any disagreeing stretch over 0.15 is a wall_mismatch.
##   duels    for every foe and 36 approach angles, where Duel stands the hero (through
##            duel_stage.gd frame_for, the code the duel itself runs) and both sidestep
##            ends: duel_inside counts any in a wall; then where duel_done puts the hero
##            and whether they can walk from there at 60 fps (duel_stuck).
##   thin     _settle_from must not carry the hero across a synthetic 0.9 wall.
##   real     one real duel on this tier: its placement must match frame_for within 0.05.
##   sweep    every tier in logic steps (rects swapped in, World._move_hero as play does):
##            pushes into walls from points along every wall and a grid, reverses, slides
##            both ways, walk at 1/60 and 0.1 s frames, run (1.7x) at 0.25 and 0.5 s. "inside" (ends a
##            step in blocked space), "stuck" (no direction moves for over 0.5 s), "clip"
##            (a step passed through blocked space).
##   frames   the same pushes on this tier through World._process itself (stick input, the
##            safety net, surroundings): inside/stuck as above, and the net must never fire.
## net: puts the hero inside walls and checks the safety net frees them within 1 s, then
##   exercises World.unstuck() and its refusals.
## duelshot: starts a duel in the tier's first lesser corridor at the approach that used
##   to stand the hero deepest in a wall, then freezes time for screenshots.

const Stage := preload("res://scripts/duel_stage.gd")
const ANGLES := 8
## [speed multiplier, frame delta]: walk at 60 fps and a 0.1 s hitch; run (the land's 1.7x,
## in case the tower gets it) with phone hitches of 0.25 and 0.5 s.
const COMBOS := [[1.0, 1.0 / 60.0], [1.0, 0.1], [1.7, 0.25], [1.7, 0.5]]
const FRAME_COMBOS := [[1.0, 1.0 / 60.0], [1.0, 0.25], [1.0, 0.5]]
const BUDGET_USEC := 150000
const SHOW := 4

var w: Node3D
var mode := ""
var phase := "setup"
var counts := {"inside": 0, "stuck": 0, "clip": 0, "spawn_bad": 0, "wall_mismatch": 0, "duel_raw_inside": 0,
	"duel_inside": 0, "seat_inside": 0, "duel_stuck": 0, "real_duel_stuck": 0, "real_mismatch": 0, "thin_cross": 0,
	"frame_inside": 0, "frame_stuck": 0, "frame_unstuck": 0}
var _shown := {}
var _jobs: Array = []
var _job_i := 0
var _tier_i := 1
var _steps := 0
var _wait := 0.0
var _inner := false
var _real_spot := Vector3.INF
var _real_foe := {}
var _real_worst := 0.0
var _net_cases: Array = []
var _net_from := Vector3.ZERO
var _net_t := 0.0
var _net_ok := 0
var _net_bad := 0
var _manual := "untested"
var _real := "untested"
var _t0 := 0


func _init(world: Node3D, which: String) -> void:
	w = world
	mode = which


func tick(delta: float) -> void:
	if _inner:
		return
	if mode == "act1":
		_quest_tick()
		return
	if mode == "save":
		if phase == "setup":
			phase = "done"
			w.started = true
			Run.title_seen = true
			QBot.qs_report()
			Run.save()
			print("QSAVE END")
			w.get_tree().quit()
		return
	match phase:
		"setup":
			_t0 = Time.get_ticks_msec()
			Run.no_save = true
			Run.title_seen = true
			Run.data.tutorial_done = true
			w.started = true
			w.stick = Vector2.ZERO
			print("TOWERBOT start mode=%s tier=%d" % [mode, w.tier])
			match mode:
				"walls": phase = "spawns"
				"duelshot": phase = "shot"
				_: phase = "net"
		"spawns":
			_spawns()
			_wall_check()
			_placements()
			_thin_wall()
			phase = "real"
		"real":
			_real_duel()
		"real_wait":
			_real_wait()
		"sweep":
			_sweep()
		"frames_start":
			_begin_frames()
		"frames":
			_frames_pass()
		"sweep_done":
			_finish()
		"net":
			_net(delta)
		"manual":
			_manual_test()
			_finish()
		"shot":
			_shot_start()
		"shot_wait":
			_shot_wait(delta)


func _event(kind: String, tier: int, pos: Vector3, speed: float, delta: float, extra := "") -> void:
	counts[kind] = int(counts[kind]) + 1
	_shown[kind] = int(_shown.get(kind, 0)) + 1
	if int(_shown[kind]) <= SHOW:
		print("TOWERBOT EVENT %s tier=%d pos=(%.2f,%.2f) speed=%.2f delta=%.3f %s" % [kind, tier, pos.x, pos.z, speed, delta, extra])


# ---------------------------------------------------------------- arrivals, walls, duels

func _spawns() -> void:
	var keep_rects: Array = w.rects
	for t in range(1, Run.FLOORS + 1):
		w.rects = Tiers.rects(t)
		for p: Vector3 in [Tiers.ENTRANCE, Tiers.EXIT + Vector3(0, 0, 4.0)]:
			if not w._walkable(p):
				_event("spawn_bad", t, p, 1.0, 0.0)
	w.rects = keep_rects
	print("TOWERBOT spawns spawn_bad=%d" % counts.spawn_bad)


func _wall_check() -> void:
	var keep_rects: Array = w.rects
	var pieces_total := 0
	for t in range(1, Run.FLOORS + 1):
		w.rects = Tiers.rects(t)
		var pieces: Array = w._wall_layout()
		pieces_total += pieces.size()
		for r: Rect2 in w.rects:
			for edge in 4:
				var length := r.size.x if edge < 2 else r.size.y
				var n := int(ceil(length / 0.05))
				var bad := 0.0
				var bad_at := Vector2.ZERO
				for k in n:
					var a := (k + 0.5) * length / n
					var on: Vector2 = w._edge_point(r, edge, a, -0.01)
					var blocked: bool = not w._walkable(Vector3(on.x, 0, on.y))
					var probe: Vector2 = w._edge_point(r, edge, a, 0.03)
					var drawn := false
					for fp: Rect2 in pieces:
						if fp.has_point(probe):
							drawn = true
							break
					if blocked != drawn:
						if bad == 0.0:
							bad_at = on
						bad += length / n
					else:
						if bad > 0.15:
							_event("wall_mismatch", t, Vector3(bad_at.x, 0, bad_at.y), 0.0, 0.0, "length=%.2f" % bad)
						bad = 0.0
				if bad > 0.15:
					_event("wall_mismatch", t, Vector3(bad_at.x, 0, bad_at.y), 0.0, 0.0, "length=%.2f" % bad)
	w.rects = keep_rects
	print("TOWERBOT walls pieces=%d wall_mismatch=%d" % [pieces_total, counts.wall_mismatch])


## Hero stand point (plus a sidestep) of a duel between a hero at hs and a foe at fp, as
## Duel computes it: host null gives the frame without the tower's wall check.
func _stand(host: Node, hs: Vector3, fp: Vector3, dodge := 0.0) -> Vector3:
	var p: Vector3 = Stage.frame_for(host, hs, fp) * (Stage.PLAYER_STAND + Vector3(dodge * Stage.DODGE_REACH, 0, 0))
	p.y = 0.0
	return p


func _placements() -> void:
	var keep_rects: Array = w.rects
	var keep_pos: Vector3 = w.hero_pos
	var tried := 0
	for t in range(1, Run.FLOORS + 1):
		w.rects = Tiers.rects(t)
		for e in Tiers.entities(t):
			if e.type != "foe":
				continue
			for k in 36:
				var a := TAU * k / 36.0
				var hs: Vector3 = e.pos + Vector3(sin(a), 0, cos(a)) * 2.55
				if not w._walkable(hs):
					continue
				tried += 1
				var xf: Transform3D = Stage.frame_for(w, hs, e.pos)
				for dodge in [0.0, -1.0, 1.0]:
					var raw := _stand(null, hs, e.pos, dodge)
					if not w._walkable(raw):
						counts.duel_raw_inside += 1
						if t == int(w.tier) and e.kind == "lesser" and dodge == -1.0:
							var deep: float = raw.distance_to(w._settle(raw))
							if deep > _real_worst:
								_real_worst = deep
								_real_spot = hs
								_real_foe = e
					var p := _stand(w, hs, e.pos, dodge)
					if not w._walkable(p):
						_event("duel_inside", t, p, 1.0, 0.0, "foe=%s from=(%.2f,%.2f) dodge=%.0f" % [e.id, hs.x, hs.z, dodge])
				var foe_p: Vector3 = xf * Stage.FOE_STAND
				if not w._walkable(Vector3(foe_p.x, 0, foe_p.z)):
					_event("duel_inside", t, foe_p, 1.0, 0.0, "foe=%s stand from=(%.2f,%.2f)" % [e.id, hs.x, hs.z])
				for side in [-1.0, 1.0]:
					var seat: Vector3 = xf * Vector3(3.3 * side, 0, -0.1)
					if not w._walkable(Vector3(seat.x, 0, seat.z)):
						counts.seat_inside += 1
				var after: Vector3 = w._settle_from(hs, _stand(w, hs, e.pos))
				w.hero_pos = after
				if not w._walkable(after) or not _any_move(1.0 / 60.0, 1.0):
					_event("duel_stuck", t, after, 1.0, 1.0 / 60.0, "foe=%s from=(%.2f,%.2f)" % [e.id, hs.x, hs.z])
	w.rects = keep_rects
	w.hero_pos = keep_pos
	print("TOWERBOT duels approaches=%d raw_inside=%d duel_inside=%d seat_inside=%d duel_stuck=%d" % [
		tried, counts.duel_raw_inside, counts.duel_inside, counts.seat_inside, counts.duel_stuck])


## A thin wall between where the hero stood and where a duel left them: two rooms that only
## touch (a 0.9 blocked strip at x 4.55..5.45). The hero must come back on their own side.
func _thin_wall() -> void:
	var keep_rects: Array = w.rects
	w.rects = [Rect2(0, -2, 5, 4), Rect2(5, -2, 5, 4)]
	for to: Vector3 in [Vector3(6.0, 0, 0), Vector3(5.0, 0, 0.5), Vector3(8.0, 0, 1.0)]:
		var p: Vector3 = w._settle_from(Vector3(3, 0, 0), to)
		var ok: bool = w._walkable(p) and p.x < 4.6
		if not ok:
			counts.thin_cross += 1
		print("TOWERBOT thin from=(3.00,0.00) duel=(%.2f,%.2f) back=(%.2f,%.2f) nearest_only=(%.2f,%.2f) ok=%s" % [
			to.x, to.z, p.x, p.z, (w._settle(to) as Vector3).x, (w._settle(to) as Vector3).z, ok])
	w.rects = keep_rects


func _real_duel() -> void:
	if _real_spot == Vector3.INF:
		_real = "no-spot"
		_begin_sweep()
		return
	for e in w.ents:
		if e.type == "foe" and e.id != _real_foe.id:
			e.pos = Vector3(0, 0, 500)
	w.hero_pos = _real_spot
	w.hero.position = _real_spot
	phase = "real_wait"
	_wait = 0.0


func _real_wait() -> void:
	if w.duel == null:
		_wait += 1.0
		if _wait > 30.0:
			_real = "no-duel"
			_begin_sweep()
		return
	var d: Node = w.duel
	var placed: Vector3 = w.hero.global_position
	placed.y = 0.0
	var predict := _stand(w, w._pre_duel, _real_foe.pos)
	var raw := _stand(null, w._pre_duel, _real_foe.pos)
	if placed.distance_to(predict) > 0.05:
		counts.real_mismatch += 1
	d.slain.append({"node": d.enemy, "enc": d._enc})
	d.stage._release()
	w.duel_done(true, d)
	d.queue_free()
	var at: Vector3 = w.hero_pos
	var free: bool = w._walkable(at) and _any_move(1.0 / 60.0, 1.0)
	if not free or not w._walkable(placed):
		counts.real_duel_stuck += 1
	_real = "placed=(%.2f,%.2f) predicted=(%.2f,%.2f) unshifted=(%.2f,%.2f) placed_walkable=%s after=(%.2f,%.2f) can_walk=%s" % [
		placed.x, placed.z, predict.x, predict.z, raw.x, raw.z, w._walkable(placed), at.x, at.z, free]
	print("TOWERBOT realduel foe=%s %s" % [_real_foe.id, _real])
	_begin_sweep()


# ---------------------------------------------------------------- movement sweeps

func _begin_sweep() -> void:
	phase = "sweep"
	_tier_i = 1
	_jobs = []


func _starts(rects: Array) -> Array:
	var out: Array = []
	for r: Rect2 in rects:
		var g := r.grow(-0.6)
		if g.size.x <= 0.0 or g.size.y <= 0.0:
			continue
		for edge in 4:
			var length := g.size.x if edge < 2 else g.size.y
			var n := maxi(1, int(ceil(length / 2.5)))
			for k in n + 1:
				var a := length * k / n
				var p: Vector2
				match edge:
					0: p = Vector2(g.position.x + a, g.position.y)
					1: p = Vector2(g.position.x + a, g.end.y)
					2: p = Vector2(g.position.x, g.position.y + a)
					_: p = Vector2(g.end.x, g.position.y + a)
				out.append(Vector3(p.x, 0, p.y))
		var x := g.position.x + 1.5
		while x < g.end.x:
			var z := g.position.y + 1.5
			while z < g.end.y:
				out.append(Vector3(x, 0, z))
				z += 4.0
			x += 4.0
	return out


func _sweep() -> void:
	var t0 := Time.get_ticks_usec()
	var keep_rects: Array = w.rects
	var keep_pos: Vector3 = w.hero_pos
	while Time.get_ticks_usec() - t0 < BUDGET_USEC:
		if _jobs.is_empty() or _job_i >= _jobs.size():
			if not _jobs.is_empty():
				print("TOWERBOT sweep tier=%d runs=%d steps=%d inside=%d stuck=%d clip=%d" % [_tier_i, _jobs.size(), _steps, counts.inside, counts.stuck, counts.clip])
				_tier_i += 1
				_jobs = []
			if _tier_i > Run.FLOORS:
				phase = "frames_start"
				break
			w.rects = Tiers.rects(_tier_i)
			for s in _starts(w.rects):
				if not w._walkable(s):
					continue
				for a in ANGLES:
					for c in COMBOS:
						_jobs.append([s, a, c[0], c[1]])
			_job_i = 0
			_steps = 0
		w.rects = Tiers.rects(_tier_i)
		var batch := 0
		while _job_i < _jobs.size() and batch < 40:
			_run_job(_jobs[_job_i])
			_job_i += 1
			batch += 1
	w.rects = keep_rects
	w.hero_pos = keep_pos


func _run_job(j: Array) -> void:
	var start: Vector3 = j[0]
	var ang: float = TAU * float(j[1]) / ANGLES + deg_to_rad(4.0)
	var speed: float = j[2]
	var delta: float = j[3]
	var base := Vector3(sin(ang), 0, cos(ang))
	w.hero_pos = start
	var stuck_t := 0.0
	var n := clampi(int(ceil(2.5 / (speed * World.SPEED * delta))), 2, 45)
	for d: Vector3 in [base, -base, base.rotated(Vector3.UP, 1.4), base.rotated(Vector3.UP, -1.4), base.rotated(Vector3.UP, 0.15)]:
		for i in n:
			var before: Vector3 = w.hero_pos
			w._move_hero(d, delta, World.SPEED * speed)
			_steps += 1
			var after: Vector3 = w.hero_pos
			if not w._walkable(after):
				_event("inside", _tier_i, after, speed, delta, "from=(%.2f,%.2f)" % [before.x, before.z])
				return
			if before.distance_squared_to(after) < 1e-10:
				if not _any_move(delta, speed):
					stuck_t += delta
					if stuck_t > 0.5:
						_event("stuck", _tier_i, after, speed, delta)
						return
				continue
			stuck_t = 0.0
			if _crossed(before, d, delta, speed):
				_event("clip", _tier_i, after, speed, delta, "from=(%.2f,%.2f)" % [before.x, before.z])
			w.hero_pos = after


## Can a push in any of 8 directions move the hero from where they stand, at this step?
func _any_move(delta: float, speed: float) -> bool:
	var at: Vector3 = w.hero_pos
	for k in 8:
		var d := Vector3(sin(TAU * k / 8.0), 0, cos(TAU * k / 8.0))
		w._move_hero(d, delta, World.SPEED * speed)
		var moved: bool = at.distance_squared_to(w.hero_pos) > 1e-10
		w.hero_pos = at
		if moved:
			return true
	return false


## Did that move pass through blocked space? Replays it one World.SUB_STEP piece at a time
## (each piece is x then z, as _move_hero does it) and samples every 0.1 along each leg.
func _crossed(from: Vector3, d: Vector3, delta: float, speed: float) -> bool:
	var n := maxi(1, int(ceil(speed * World.SPEED * delta / World.SUB_STEP)))
	w.hero_pos = from
	for i in n:
		var a: Vector3 = w.hero_pos
		w._move_hero(d, delta / n, World.SPEED * speed)
		var b: Vector3 = w.hero_pos
		var mid := Vector3(b.x, 0, a.z)
		for leg in [[a, mid], [mid, b]]:
			var p: Vector3 = leg[0]
			var q: Vector3 = leg[1]
			var k := int(ceil(p.distance_to(q) / 0.1))
			for j in range(1, k):
				if not w._walkable(p.lerp(q, float(j) / k)):
					return true
	return false


## The per-frame pass: this tier's real scene, stick input into World._process.
func _begin_frames() -> void:
	phase = "frames"
	_jobs = []
	var starts := _starts(w.rects)
	for i in range(0, starts.size(), 2):
		if not w._walkable(starts[i]):
			continue
		for a in ANGLES:
			for c in FRAME_COMBOS:
				_jobs.append([starts[i], a, c[1]])
	_job_i = 0
	_steps = 0
	for e in w.ents:
		if e.type == "foe":
			e.pos = Vector3(0, 0, 500)


func _frames_pass() -> void:
	var t0 := Time.get_ticks_usec()
	var keep_pos: Vector3 = w.hero_pos
	var before_count: int = w.unstuck_count
	_inner = true
	while Time.get_ticks_usec() - t0 < BUDGET_USEC and _job_i < _jobs.size():
		var j: Array = _jobs[_job_i]
		_job_i += 1
		var ang: float = TAU * float(j[1]) / ANGLES + deg_to_rad(4.0)
		var delta: float = j[2]
		w.hero_pos = j[0]
		var stuck_t := 0.0
		var n := clampi(int(ceil(2.5 / (World.SPEED * delta))), 2, 45)
		for stick: Vector2 in [Vector2(sin(ang), cos(ang)), -Vector2(sin(ang), cos(ang)), Vector2(cos(ang), -sin(ang))]:
			for i in n:
				var before: Vector3 = w.hero_pos
				w._pub_t = 1e9
				w.stick = stick
				w._process(delta)
				_steps += 1
				if w.duel != null or w.hud.screen != "":
					break
				var after: Vector3 = w.hero_pos
				if not w._walkable(after):
					_event("frame_inside", int(w.tier), after, 1.0, delta)
					break
				if before.distance_squared_to(after) < 1e-10 and not _any_move(delta, 1.0):
					stuck_t += delta
					if stuck_t > 0.5:
						_event("frame_stuck", int(w.tier), after, 1.0, delta)
						break
				else:
					stuck_t = 0.0
	_inner = false
	w.stick = Vector2.ZERO
	counts.frame_unstuck = int(counts.frame_unstuck) + int(w.unstuck_count) - before_count
	if _job_i >= _jobs.size():
		print("TOWERBOT frames tier=%d runs=%d process_calls=%d inside=%d stuck=%d unstuck=%d" % [
			w.tier, _jobs.size(), _steps, counts.frame_inside, counts.frame_stuck, counts.frame_unstuck])
		w.hero_pos = Tiers.ENTRANCE
		phase = "sweep_done"
		return
	w.hero_pos = w.hero_pos if w._walkable(w.hero_pos) else keep_pos


# ---------------------------------------------------------------- safety net and unstuck()

func _net(delta: float) -> void:
	if _net_cases.is_empty() and _net_ok + _net_bad == 0 and _net_t == 0.0:
		var m := Tiers.mirror(int(w.tier))
		_net_cases = [Vector3(-7.6 * m, 0, -3), Vector3(0, 0, -47.5), Vector3(3.0, 0, -30.0), Vector3(-2.3, 0, -9.0)]
		_net_t = -1.0
	if _net_t < 0.0:
		if _net_cases.is_empty():
			phase = "manual"
			return
		_net_from = _net_cases.pop_front()
		w.hero_pos = _net_from
		w.stick = Vector2(0, -1) if _net_ok % 2 == 1 else Vector2.ZERO
		_net_t = 0.0
		print("TOWERBOT net place=(%.2f,%.2f) walkable=%s" % [_net_from.x, _net_from.z, w._walkable(_net_from)])
		return
	_net_t += delta
	var at: Vector3 = w.hero_pos
	if at.distance_to(_net_from) > 0.01 and w._walkable(at):
		var ok: bool = _net_t <= 1.0 and at.distance_to(_net_from) <= 3.0 and w.duel == null
		print("TOWERBOT net freed after=%.2fs to=(%.2f,%.2f) moved=%.2f ok=%s" % [_net_t, at.x, at.z, at.distance_to(_net_from), ok])
		if ok:
			_net_ok += 1
		else:
			_net_bad += 1
		w.stick = Vector2.ZERO
		_net_t = -1.0
	elif _net_t > 1.0:
		print("TOWERBOT net NOT freed after %.2fs at=(%.2f,%.2f)" % [_net_t, at.x, at.z])
		_net_bad += 1
		w.stick = Vector2.ZERO
		_net_t = -1.0


func _manual_test() -> void:
	if not w.has_method("unstuck"):
		_manual = "missing"
		return
	var fails: Array = []
	# Fresh arrival with no trail: stays put (never teleports to the entrance).
	w._trail = []
	w._last_safe = Vector3(0.5, 0, 2.2)
	w.hero_pos = Vector3(1.0, 0, 2.5)
	if w.unstuck() or w.hero_pos != Vector3(1.0, 0, 2.5):
		fails.append("no-trail moved")
	# Walk a trail, then step back along it.
	for p in [Vector3(0, 0, 2.0), Vector3(-3, 0, 0), Vector3(-3, 0, -3.5), Vector3(1.0, 0, -5.0)]:
		w.hero_pos = p
		w._check_surroundings()
	var before: Vector3 = w.hero_pos
	var moved: bool = w.unstuck()
	var at: Vector3 = w.hero_pos
	if not (moved and w._walkable(at) and at.distance_to(before) >= 1.0 and at.distance_to(before) <= 6.0):
		fails.append("trail back")
	print("TOWERBOT manual unstuck from=(%.2f,%.2f) to=(%.2f,%.2f)" % [before.x, before.z, at.x, at.z])
	# From inside a wall it frees in place rather than walking back.
	w.hero_pos = Vector3(-2.4, 0, -9.0)
	moved = w.unstuck()
	at = w.hero_pos
	if not (moved and w._walkable(at) and at.distance_to(Vector3(-2.4, 0, -9.0)) < 1.5):
		fails.append("from wall")
	# Refusals: a screen open, not started, a foe within duel range.
	w.hero_pos = Vector3(-2.4, 0, -9.0)
	w.hud.screen = "bag"
	if w.unstuck():
		fails.append("screen open")
	w.hud.screen = ""
	w.started = false
	if w.unstuck():
		fails.append("not started")
	w.started = true
	var foe := {"type": "foe", "pos": Vector3(-1.0, 0, -9.5), "id": "botfoe"}
	w.ents.append(foe)
	if w.unstuck():
		fails.append("foe close")
	w.ents.erase(foe)
	w.hero_pos = Vector3(0, 0, 2.0)
	_manual = "ok" if fails.is_empty() else "bad:" + ",".join(fails)
	print("TOWERBOT manual result=%s" % _manual)


# ---------------------------------------------------------------- duel screenshots

func _shot_start() -> void:
	_placements()
	if _real_spot == Vector3.INF:
		print("TOWERBOT shot no spot")
		phase = "done"
		return
	for e in w.ents:
		if e.type == "foe" and e.id != _real_foe.id:
			e.pos = Vector3(0, 0, 500)
	w.hero_pos = _real_spot
	w.hero.position = _real_spot
	print("TOWERBOT shot tier=%d foe=%s from=(%.2f,%.2f) unshifted=(%.2f,%.2f) left_dodge=(%.2f,%.2f)" % [w.tier, _real_foe.id,
		_real_spot.x, _real_spot.z, _stand(null, _real_spot, _real_foe.pos).x, _stand(null, _real_spot, _real_foe.pos).z,
		_stand(null, _real_spot, _real_foe.pos, -1.0).x, _stand(null, _real_spot, _real_foe.pos, -1.0).z])
	phase = "shot_wait"
	_wait = 0.0


func _shot_wait(delta: float) -> void:
	if w.duel == null:
		return
	_wait += delta
	if _wait > 2.5:
		var p: Vector3 = w.hero.global_position
		print("TOWERBOT shot frozen hero=(%.2f,%.2f) walkable=%s" % [p.x, p.z, w._walkable(Vector3(p.x, 0, p.z))])
		Engine.time_scale = 0.0
		phase = "done"


func _finish() -> void:
	var c := counts
	if mode == "walls":
		print("TOWERBOT DONE mode=walls inside=%d stuck=%d clip=%d spawn_bad=%d wall_mismatch=%d duel_raw_inside=%d duel_inside=%d seat_inside=%d duel_stuck=%d thin_cross=%d real_duel_stuck=%d real_mismatch=%d frame_inside=%d frame_stuck=%d frame_unstuck=%d real=%s secs=%d" % [
			c.inside, c.stuck, c.clip, c.spawn_bad, c.wall_mismatch, c.duel_raw_inside, c.duel_inside, c.seat_inside, c.duel_stuck,
			c.thin_cross, c.real_duel_stuck, c.real_mismatch, c.frame_inside, c.frame_stuck, c.frame_unstuck,
			"ok" if _real.begins_with("placed") else _real, (Time.get_ticks_msec() - _t0) / 1000])
	else:
		print("TOWERBOT DONE mode=net net_ok=%d net_bad=%d manual=%s" % [_net_ok, _net_bad, _manual])
	phase = "done"
	w.get_tree().quit()


# ---------------------------------------------------------------- quest bot, tower part (act1)

const QBot := preload("res://scripts/overworld_bot.gd")
var _q_checked := false


func _quest_tick() -> void:
	if phase == "setup":
		phase = "run"
		w.started = true
		Run.title_seen = true
		print("QBOT tower tier=%d relic=%s guardian_slain=%s" % [w.tier, str(Run.data.relics), str(Run.is_slain("t1_guardian"))])
	QBot.qb_poll()
	if phase == "reloading":
		return
	if "--reload" in OS.get_cmdline_user_args() and Run.data.relics.has(1) and QBot.qb_rl_count() == 2:
		phase = "reloading"
		QBot.qb_reload("find")
		return
	if not _q_checked and Run.data.relics.has(1) and Quests.state("a1_stair").get("step", 0) >= 1:
		_q_checked = true
		var tier_done := Quests.cond("tier:1")
		QBot.qb_check(tier_done or int(Quests.state("a1_stair").step) == 1, "tablet found, the Warden still stands, step 2 of a1_stair is current")


## Walk: the tablet, then the first guardian, then the way out. Presses E where the prompt appears.
func quest_dir() -> Vector3:
	var target := Vector3.ZERO
	if not Run.data.relics.has(1) and not Run.data.relics.has(1.0):
		if not w.near.is_empty() and w.near.type == "relic":
			w.interact()
			return Vector3.ZERO
		for e in w.ents:
			if e.type == "relic":
				target = e.pos
	elif not Run.is_slain("t1_guardian"):
		target = Vector3(0, 0, -40)
	else:
		if not w.near.is_empty() and w.near.type == "entry":
			w.interact()
			return Vector3.ZERO
		target = Vector3(0, 0, 5.6)
	var to: Vector3 = target - w.hero_pos
	if absf(w.hero_pos.x) > 0.4 and absf(to.z) > 1.0 and target.x == 0.0:
		to = Vector3(-w.hero_pos.x, 0, 0) + Vector3(0, 0, signf(to.z) * 0.3)
	to.y = 0
	return to.normalized()
