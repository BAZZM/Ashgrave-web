extends RefCounted

## Tower wall test bot, `--towerbot=walls` or `--towerbot=net` (with `--shot-when=towermap`
## so the land hands straight over to the tower). Prints `TOWERBOT ...` lines and quits.
##
## walls: stress-walks every tier layout in logic steps (the tier's rects are swapped in,
##   the hero is moved with World._move_hero exactly as play does): pushes into walls at
##   shallow and steep angles from points along every wall and a grid, reverses, slides
##   both ways, at walk and run speed and frame steps of 1/60, 0.1, 0.25 and 0.5 s. Counts
##   "inside" (hero ends a step in blocked space), "stuck" (pushed, and no direction can
##   move, for more than 0.5 s of game time) and "clip" (a step passed through blocked
##   space, as a long frame could before moves were sub-stepped).
##   Then checks tier arrival points, where a duel would put the hero for every foe and
##   approach angle (and whether the hero can walk away from there at 60 fps), and runs
##   one real duel on this tier and walks away from where it left the hero.
## net: puts the hero inside walls and checks the safety net frees them within 1 s, then
##   exercises World.unstuck().

const ANGLES := 8
## [speed multiplier, frame delta]: walk and run (the land's 1.7x, in case the tower gets
## it) at 60 fps, and phone hitches of 0.1, 0.25 and 0.5 s.
const COMBOS := [[1.0, 1.0 / 60.0], [1.7, 1.0 / 60.0], [1.0, 0.1], [1.7, 0.25], [1.7, 0.5]]
const BUDGET_USEC := 150000
const SHOW := 4

var w: Node3D
var mode := ""
var phase := "setup"
var counts := {"inside": 0, "stuck": 0, "clip": 0, "spawn_bad": 0, "duel_raw_inside": 0, "duel_stuck": 0, "real_duel_stuck": 0}
var _shown := {}
var _jobs: Array = []
var _job_i := 0
var _tier_i := 1
var _steps := 0
var _wait := 0.0
var _frames := 0
var _real_spot := Vector3.INF
var _real_foe := {}
var _predict := Vector3.ZERO
var _net_cases: Array = []
var _net_from := Vector3.ZERO
var _net_t := 0.0
var _net_ok := 0
var _net_bad := 0
var _manual := "untested"
var _real := "untested"


func _init(world: Node3D, which: String) -> void:
	w = world
	mode = which


func tick(delta: float) -> void:
	_frames += 1
	match phase:
		"setup":
			Run.no_save = true
			Run.title_seen = true
			Run.data.tutorial_done = true
			w.started = true
			w.stick = Vector2.ZERO
			print("TOWERBOT start mode=%s tier=%d" % [mode, w.tier])
			phase = "spawns" if mode == "walls" else "net"
			_tier_i = 1
			_jobs = []
		"sweep":
			_sweep()
		"spawns":
			_spawns()
			_placements()
			phase = "real"
		"sweep_done":
			_finish()
		"real":
			_real_duel()
		"real_wait":
			_real_wait()
		"net":
			_net(delta)
		"manual":
			_manual_test()
			_finish()


func _event(kind: String, tier: int, pos: Vector3, speed: float, delta: float, extra := "") -> void:
	counts[kind] = int(counts[kind]) + 1
	_shown[kind] = int(_shown.get(kind, 0)) + 1
	if int(_shown[kind]) <= SHOW:
		print("TOWERBOT EVENT %s tier=%d pos=(%.2f,%.2f) speed=%.2f delta=%.3f %s" % [kind, tier, pos.x, pos.z, speed, delta, extra])


# ---------------------------------------------------------------- layout sweep

func _starts(rects: Array) -> Array:
	var out: Array = []
	for r: Rect2 in rects:
		var g := r.grow(-0.6)
		if g.size.x <= 0.0 or g.size.y <= 0.0:
			continue
		for edge in 4:
			var length := g.size.x if edge < 2 else g.size.y
			var n := maxi(1, int(ceil(length / 2.0)))
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
				phase = "sweep_done"
				break
			w.rects = Tiers.rects(_tier_i)
			_jobs = []
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


# ---------------------------------------------------------------- arrivals and duels

func _settled(p: Vector3) -> Vector3:
	return w._settle(p) if w.has_method("_settle") else p


func _spawns() -> void:
	var keep_rects: Array = w.rects
	for t in range(1, Run.FLOORS + 1):
		w.rects = Tiers.rects(t)
		var pts := [Tiers.ENTRANCE, Tiers.EXIT + Vector3(0, 0, 4.0)]
		for p: Vector3 in pts:
			if not w._walkable(p):
				_event("spawn_bad", t, p, 1.0, 0.0)
	w.rects = keep_rects
	print("TOWERBOT spawns spawn_bad=%d" % counts.spawn_bad)


## Where Duel's stage (duel_stage.gd _place_in_world) stands the hero: midpoint of hero and
## foe, then (-1.2, 0, 2.0) in a frame facing the foe; a dodge adds +-1.0 on that frame's x.
static func duel_spot(hero: Vector3, foe: Vector3, dodge := 0.0) -> Vector3:
	var dir := foe - hero
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.FORWARD
	var mid := hero.lerp(foe, 0.5)
	var xf := Transform3D(Basis.looking_at(dir, Vector3.UP), mid)
	var p := xf * Vector3(-1.2 + dodge, 0, 2.0)
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
				for dodge in [0.0, -1.0, 1.0]:
					tried += 1
					var raw := duel_spot(hs, e.pos, dodge)
					if not w._walkable(raw):
						counts.duel_raw_inside += 1
						if t == int(w.tier) and dodge == 0.0 and e.kind == "lesser" and _real_spot == Vector3.INF:
							_real_spot = hs
							_real_foe = e
					var p := _settled(raw)
					w.hero_pos = p
					if not w._walkable(p) or not _any_move(1.0 / 60.0, 1.0):
						_event("duel_stuck", t, p, 1.0, 1.0 / 60.0, "foe=%s from=(%.2f,%.2f) dodge=%.0f" % [e.id, hs.x, hs.z, dodge])
	w.rects = keep_rects
	w.hero_pos = keep_pos
	print("TOWERBOT duels placements=%d raw_inside=%d duel_stuck=%d" % [tried, counts.duel_raw_inside, counts.duel_stuck])


func _real_duel() -> void:
	if _real_spot == Vector3.INF:
		_real = "no-spot"
		phase = "sweep"
		return
	for e in w.ents:
		if e.type == "foe" and e.id != _real_foe.id:
			e.pos = Vector3(0, 0, 500)
	w.hero_pos = _real_spot
	w.hero.position = _real_spot
	_predict = duel_spot(_real_spot, _real_foe.pos)
	phase = "real_wait"
	_wait = 0.0


func _real_wait() -> void:
	if w.duel == null:
		_wait += 1.0
		if _wait > 30.0:
			_real = "no-duel"
			phase = "sweep"
		return
	var d: Node = w.duel
	var placed: Vector3 = w.hero.global_position
	placed.y = 0.0
	d.slain.append({"node": d.enemy, "enc": d._enc})
	d.stage._release()
	w.duel_done(true, d)
	d.queue_free()
	var at: Vector3 = w.hero_pos
	var free: bool = w._walkable(at) and _any_move(1.0 / 60.0, 1.0)
	if not free:
		counts.real_duel_stuck += 1
	_real = "placed=(%.2f,%.2f) predicted=(%.2f,%.2f) placed_walkable=%s after=(%.2f,%.2f) can_walk=%s" % [
		placed.x, placed.z, _predict.x, _predict.z, w._walkable(placed), at.x, at.z, free]
	print("TOWERBOT realduel foe=%s %s" % [_real_foe.id, _real])
	phase = "sweep"
	_tier_i = 1
	_jobs = []


# ---------------------------------------------------------------- safety net and unstuck()

func _net(delta: float) -> void:
	if _net_cases.is_empty() and _net_ok + _net_bad == 0:
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
	for p in [Vector3(0, 0, 2.0), Vector3(-3, 0, 0), Vector3(-3, 0, -3.5), Vector3(1.0, 0, -5.0)]:
		w.hero_pos = p
		w._check_surroundings()
	var before: Vector3 = w.hero_pos
	var moved: bool = w.unstuck()
	var at: Vector3 = w.hero_pos
	_manual = "ok" if moved and w._walkable(at) and at.distance_to(before) >= 1.0 else "bad"
	print("TOWERBOT manual unstuck from=(%.2f,%.2f) to=(%.2f,%.2f) result=%s" % [before.x, before.z, at.x, at.z, _manual])
	# From inside a wall it frees in place rather than walking back.
	w.hero_pos = Vector3(-2.4, 0, -9.0)
	moved = w.unstuck()
	at = w.hero_pos
	var ok2: bool = moved and w._walkable(at) and at.distance_to(Vector3(-2.4, 0, -9.0)) < 1.5
	print("TOWERBOT manual unstuck from_wall to=(%.2f,%.2f) ok=%s" % [at.x, at.z, ok2])
	if not ok2:
		_manual = "bad"


func _finish() -> void:
	var c := counts
	if mode == "walls":
		print("TOWERBOT DONE mode=walls inside=%d stuck=%d clip=%d spawn_bad=%d duel_raw_inside=%d duel_stuck=%d real_duel_stuck=%d real=%s" % [
			c.inside, c.stuck, c.clip, c.spawn_bad, c.duel_raw_inside, c.duel_stuck, c.real_duel_stuck, "ok" if _real.begins_with("placed") else _real])
	else:
		print("TOWERBOT DONE mode=net net_ok=%d net_bad=%d manual=%s" % [_net_ok, _net_bad, _manual])
	phase = "done"
	w.get_tree().quit()
