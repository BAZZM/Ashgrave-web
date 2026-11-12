extends Node

## ---- World agility (docs/COMBAT_RULES.md section 6). Every number a phone playtest may want
## to change is in this block. Units: u (world units), seconds, degrees.
## Speeds at full stick, before the road bonus and the agility skill.
const WALK_SPEED := 5.5
const RUN_SPEED := 9.5
const SPRINT_SPEED := 12.5
## Stick length (0-1) for running, and for starting a sprint. Below RUN_STICK a sprint is lost.
const RUN_STICK := 0.8
const SPRINT_STICK := 0.95
## Seconds to build up to a run, and to drop from a run back to a walk.
const RUN_BUILD := 0.25
const RUN_EASE := 0.2
## Sprint: seconds of running at SPRINT_STICK before it starts, seconds to build, seconds to
## drop. It is lost by a stick turn over SPRINT_TURN_LOSS degrees inside SPRINT_TURN_WINDOW s.
const SPRINT_AFTER := 1.0
const SPRINT_BUILD := 0.4
const SPRINT_EASE := 0.2
const SPRINT_TURN_LOSS := 90.0
const SPRINT_TURN_WINDOW := 0.25
## Speed change, units per second squared.
const ACCEL_UP := 40.0
const ACCEL_DOWN := 60.0
## How fast the hero turns, degrees per second. Below TURN_SNAP_SPEED (about standing still)
## the hero faces the stick at once.
const TURN_WALK := 720.0
const TURN_RUN := 540.0
const TURN_SPRINT := 300.0
const TURN_SNAP_SPEED := 0.6
## On a road (distance from its centre line, in units): speed multiplier bonus, road half-width,
## and how fast the bonus fades in and out (per second) so crossing the edge is smooth.
const ROAD_BONUS := 1.2
const ROAD_WIDTH := 2.0
const ROAD_BLEND := 6.0
## Dash: distance, duration, pips spent, lockout from the start of a dash, i-frames from the start.
## A dash ends early when a slice of it is cut short to less than DASH_STOP_FRAC of its length
## (any contact: "stops at obstacles").
const DASH_DIST := 4.5
const DASH_TIME := 0.22
const DASH_COST := 1.0
const DASH_LOCK := 0.35
const DASH_IFRAMES := 0.18
const DASH_STOP_FRAC := 0.98
## Camera: look-ahead (seconds of velocity, max units, ease per second), follow rate (per second)
## at a walk and extra added at a full run, distance and field of view (walking, sprinting, and the
## dash kick with seconds in and seconds out).
const LOOK_TIME := 0.25
const LOOK_MAX := 2.5
const LOOK_EASE := 4.0
const CAM_FOLLOW := 8.0
const CAM_FOLLOW_RUN := 4.0
const CAM_DIST := 6.6
const CAM_DIST_SPRINT := 7.4
const FOV := 60.0
const FOV_SPRINT := 66.0
const FOV_DASH := 70.0
const FOV_DASH_IN := 0.15
const FOV_DASH_OUT := 0.4
## Movement is stepped in slices no longer than this, so a slow frame cannot jump an obstacle.
const MAX_STEP := 1.0 / 30.0

## Walking speed of the old bots (tour, gather), which still move the old way.
const SPEED := 5.0

var ow: Overworld
var _walked := 0.0
var _pace := 1.0
var _road := 0.0
var _on_road := 0.0
var _run := 0.0
var _sprint := 0.0
var _sprinting := false
var _run_t := 0.0
var _spd := 0.0
var _vel := Vector2.ZERO
var _clock := 0.0
var _in_hist: Array = []
var _agi := 1.0
var _last_t := -99.0
var _end_xz := Vector2(1e9, 1e9)
var _amount := 0.0
var _in_dir := Vector3.ZERO
var _f_moved := 0.0
var _f_want := 0.0
var _look := Vector2.ZERO
var _cam_done := false
## Dash state: _dash_t is seconds into the dash, or -1 when not dashing.
var _dash_t := -1.0
var _dash_dir := Vector3.ZERO
var _dash_age := 99.0
var _lock := 0.0
var _pips := -1.0
var _pip_max := 3.0
var _regen := 0.6
var _stat_t := 0.0
var dash_count := 0
var dash_stopped := false


func _init(owner_world: Overworld) -> void:
	ow = owner_world


## True during the first DASH_IFRAMES seconds of a dash. Spec: no foe can start a duel then.
## overworld_interact.gd must ask this before starting one (a follow-up: it is not in this lane).
func dash_iframes() -> bool:
	return _dash_t >= 0.0 and _dash_t < DASH_IFRAMES


func dashing() -> bool:
	return _dash_t >= 0.0


func dash_pips() -> float:
	return maxf(_pips, 0.0)


func dash_pip_max() -> float:
	return _pip_max


func dash_ready() -> bool:
	return _dash_t < 0.0 and _lock <= 0.0 and _pips >= DASH_COST and _can_move()


func sprinting() -> bool:
	return _sprinting


func speed() -> float:
	return _spd


func _can_move() -> bool:
	return ow.started and ow.hud != null and ow.hud.screen == "" and not ow._leaving and ow.duel == null


## Stop all motion and states built up by moving (after a pause, a duel or a jump).
func reset_motion() -> void:
	_spd = 0.0
	_vel = Vector2.ZERO
	_run = 0.0
	_sprint = 0.0
	_sprinting = false
	_run_t = 0.0
	_dash_t = -1.0
	_dash_age = 99.0
	_in_hist.clear()
	_look = Vector2.ZERO
	_amount = 0.0
	_pace = 1.0


## Start a dash along the stick (or the way the hero faces). Returns whether it started.
func try_dash() -> bool:
	if not dash_ready():
		return false
	_pips -= DASH_COST
	_lock = DASH_LOCK
	_dash_t = 0.0
	_dash_age = 0.0
	dash_count += 1
	dash_stopped = false
	_dash_dir = _in_dir if _amount > 0.05 else Vector3(-sin(ow.hero_yaw), 0, -cos(ow.hero_yaw))
	ow.hero_yaw = atan2(-_dash_dir.x, -_dash_dir.z)
	ow._gather = {}
	ow.gather_progress = -1.0
	return true


func _refresh_stats(delta: float) -> void:
	_stat_t -= delta
	if _stat_t > 0.0 and _pips >= 0.0:
		return
	_stat_t = 1.0
	var st := Run.stats()
	_pip_max = float(st.dodge_max)
	_regen = float(st.dodge_regen)
	if _pips < 0.0:
		_pips = _pip_max
	_pips = minf(_pips, _pip_max)
	_agi = 1.0 + 0.0035 * (Run.skill("agility") - 1)


func _move_hero(delta: float) -> void:
	var scripted: bool = ow.bots.agility_active()
	if ow._bot != "" and not scripted:
		_move_bot(delta)
		return
	if ow._t - _last_t > delta * 1.5 + 0.05 or Vector2(ow.hero_pos.x, ow.hero_pos.z).distance_to(_end_xz) > 0.5:
		reset_motion()
	_refresh_stats(delta)
	var keys := Vector2.ZERO
	if not scripted:
		keys = ow.stick
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): keys.y -= 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): keys.y += 1.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): keys.x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): keys.x += 1.0
	_f_moved = 0.0
	_f_want = 0.0
	var n := clampi(ceili(delta / (1.0 / 60.0 if scripted else MAX_STEP)), 1, 120)
	var dt := delta / n
	for i in n:
		var stick := keys
		if scripted:
			stick = ow.bots.agility_input(dt)
		_step(dt, stick)
		if scripted:
			_camera(dt)
	_cam_done = scripted
	if _amount > 0.05:
		ow.look_cool -= delta
		if ow.look_cool <= 0.0:
			ow.cam_yaw = lerp_angle(ow.cam_yaw, ow.hero_yaw, minf(delta * 1.1, 1.0))
		ow._stuck = ow._stuck + delta if _f_moved < _f_want * 0.3 else 0.0
	ow.hero_pos.y = lerpf(ow.hero_pos.y, Land.walk_height(ow.hero_pos.x, ow.hero_pos.z), clampf(delta * 12.0, 0.0, 1.0))
	ow.hero.set_walk(1.0 if _dash_t >= 0.0 else clampf(_spd / WALK_SPEED, 0.0, 1.0))
	ow.hero.set_pace(_pace)
	ow.hero.position = ow.hero_pos
	ow.hero.rotation.y = ow.hero_yaw
	_last_t = ow._t
	_end_xz = Vector2(ow.hero_pos.x, ow.hero_pos.z)


## One slice of movement. stick is the stick or keys (x right, y down), before the dead zone.
func _step(dt: float, stick: Vector2) -> void:
	_clock += dt
	_pips = minf(_pips + dt * _regen, _pip_max)
	_lock = maxf(_lock - dt, 0.0)
	_dash_age += dt
	var stick_len := 0.0
	var want_dir := Vector3.ZERO
	if stick.length() > 0.12:
		stick = stick.limit_length(1.0)
		stick_len = stick.length()
		var f := Vector3(-sin(ow.cam_yaw), 0, -cos(ow.cam_yaw))
		var r := Vector3(cos(ow.cam_yaw), 0, -sin(ow.cam_yaw))
		want_dir = (r * stick.x - f * stick.y).normalized()
	var has_input := stick_len > 0.05
	_amount = stick_len
	if has_input:
		_in_dir = want_dir
	if _dash_t >= 0.0:
		_step_dash(dt)
		return
	if has_input:
		ow._gather = {}
		ow.gather_progress = -1.0
	elif not ow._gather.is_empty():
		_spd = 0.0
		_vel = Vector2.ZERO
		_run = 0.0
		_pace = 1.0
		return
	# Run and sprint states.
	var running := stick_len >= RUN_STICK
	_run = move_toward(_run, 1.0 if running else 0.0, dt / (RUN_BUILD if running else RUN_EASE))
	if not running:
		_sprinting = false
		_run_t = 0.0
	elif stick_len >= SPRINT_STICK:
		_run_t += dt
		if _run_t >= SPRINT_AFTER:
			_sprinting = true
	elif not _sprinting:
		_run_t = 0.0
	var want_yaw := ow.hero_yaw
	if has_input:
		want_yaw = atan2(-want_dir.x, -want_dir.z)
		_in_hist.append([_clock, want_yaw])
		while not _in_hist.is_empty() and _clock - float(_in_hist[0][0]) > SPRINT_TURN_WINDOW:
			_in_hist.pop_front()
		if _sprinting:
			for h in _in_hist:
				if absf(angle_difference(float(h[1]), want_yaw)) > deg_to_rad(SPRINT_TURN_LOSS):
					_sprinting = false
					_run_t = 0.0
					break
	else:
		_in_hist.clear()
	_sprint = move_toward(_sprint, 1.0 if _sprinting else 0.0, dt / (SPRINT_BUILD if _sprinting else SPRINT_EASE))
	_on_road = 1.0 if Land.road_dist(ow.hero_pos.x, ow.hero_pos.z) < ROAD_WIDTH else 0.0
	_road = move_toward(_road, _on_road, dt * ROAD_BLEND)
	var base := lerpf(lerpf(WALK_SPEED, RUN_SPEED, _run), SPRINT_SPEED, _sprint)
	var road_mult := 1.0 + (ROAD_BONUS - 1.0) * _road
	var target := base * stick_len * road_mult * _agi if has_input else 0.0
	_spd = move_toward(_spd, target, (ACCEL_UP if target > _spd else ACCEL_DOWN) * dt)
	# Heading.
	if has_input:
		if _spd < TURN_SNAP_SPEED:
			ow.hero_yaw = want_yaw
		else:
			var rate := lerpf(lerpf(TURN_WALK, TURN_RUN, _run), TURN_SPRINT, _sprint)
			ow.hero_yaw += clampf(angle_difference(ow.hero_yaw, want_yaw), -deg_to_rad(rate) * dt, deg_to_rad(rate) * dt)
	# Move along the heading.
	var fwd := Vector3(-sin(ow.hero_yaw), 0, -cos(ow.hero_yaw))
	var step := fwd * _spd * dt
	var moved := _try_move(step)
	_f_want += target * dt
	_f_moved += moved
	if step.length() > 0.0001 and moved < step.length() * 0.98:
		_spd = minf(_spd, moved / dt)
		if _sprinting and moved < step.length() * 0.3:
			_sprinting = false
			_run_t = 0.0
	_vel = Vector2(fwd.x, fwd.z) * _spd
	var rel := _spd / WALK_SPEED / _agi
	_pace = clampf(rel, 1.0, 2.5)
	_walked += moved
	if _walked >= 40.0:
		_walked = 0.0
		Run.train("agility", 8)


## Move by step with the obstacle test on each axis. Returns the distance moved.
func _try_move(step: Vector3) -> float:
	var before := ow.hero_pos
	if not ow.terrain._blocked(ow.hero_pos + Vector3(step.x, 0, 0)):
		ow.hero_pos.x += step.x
	if not ow.terrain._blocked(ow.hero_pos + Vector3(0, 0, step.z)):
		ow.hero_pos.z += step.z
	return Vector2(ow.hero_pos.x - before.x, ow.hero_pos.z - before.z).length()


func _dash_ease(u: float) -> float:
	return 1.0 - (1.0 - u) * (1.0 - u)


func _step_dash(dt: float) -> void:
	var u0 := clampf(_dash_t / DASH_TIME, 0.0, 1.0)
	_dash_t += dt
	var u1 := clampf(_dash_t / DASH_TIME, 0.0, 1.0)
	var dist := DASH_DIST * (_dash_ease(u1) - _dash_ease(u0))
	var moved := _try_move(_dash_dir * dist)
	_walked += moved
	_vel = Vector2(_dash_dir.x, _dash_dir.z) * (dist / dt)
	_pace = 2.5
	if dist > 0.0001 and moved < dist * DASH_STOP_FRAC:
		dash_stopped = true
		_dash_t = -1.0
	elif _dash_t >= DASH_TIME:
		_dash_t = -1.0
	if _dash_t < 0.0:
		# Carry on in the dash direction at the speed held before it.
		_vel = Vector2(_dash_dir.x, _dash_dir.z) * _spd


## The old way, kept for the tour and gather bots: instant speed, no sprint, no dash.
func _move_bot(delta: float) -> void:
	var dir: Vector3 = ow.bots._bot_dir(delta)
	var amount := minf(dir.length(), 1.0)
	if amount > 0.05:
		ow._gather = {}
		ow.gather_progress = -1.0
		_pace = 1.0
		var speed := SPEED * (1.0 + 0.0035 * (Run.skill("agility") - 1))
		var step := dir.limit_length(1.0) * speed * delta
		var before := ow.hero_pos
		if not ow.terrain._blocked(ow.hero_pos + Vector3(step.x, 0, 0)):
			ow.hero_pos.x += step.x
		if not ow.terrain._blocked(ow.hero_pos + Vector3(0, 0, step.z)):
			ow.hero_pos.z += step.z
		var moved := Vector2(ow.hero_pos.x - before.x, ow.hero_pos.z - before.z).length()
		ow._stuck = ow._stuck + delta if moved < step.length() * 0.3 else 0.0
		_walked += moved
		if _walked >= 40.0:
			_walked = 0.0
			Run.train("agility", 8)
		ow.hero_yaw = lerp_angle(ow.hero_yaw, atan2(-dir.x, -dir.z), minf(delta * 10.0, 1.0))
		ow.look_cool -= delta
		if ow.look_cool <= 0.0:
			ow.cam_yaw = lerp_angle(ow.cam_yaw, ow.hero_yaw, minf(delta * 1.1, 1.0))
	else:
		_pace = 1.0
	_spd = 0.0
	_vel = Vector2.ZERO
	ow.hero_pos.y = lerpf(ow.hero_pos.y, Land.walk_height(ow.hero_pos.x, ow.hero_pos.z), clampf(delta * 12.0, 0.0, 1.0))
	ow.hero.set_walk(amount)
	ow.hero.set_pace(_pace)
	ow.hero.position = ow.hero_pos
	ow.hero.rotation.y = ow.hero_yaw


func _update_camera(delta: float) -> void:
	if _cam_done:
		_cam_done = false
		return
	_camera(delta)


func _camera(delta: float) -> void:
	var showcase: bool = ow.hud != null and ow.hud.screen in ["bag", "shop"]
	var moving: bool = ow.started and ow.hud != null and ow.hud.screen == "" and not ow._leaving
	var yaw := ow.cam_yaw + (PI + 0.55 + sin(ow._t * 0.25) * 0.35 if not ow.started else 0.0)
	var back := Vector3(sin(yaw), 0, cos(yaw))
	# Look-ahead: the view leans toward where the hero is going.
	var ahead := (_vel * LOOK_TIME).limit_length(LOOK_MAX) if moving and not showcase else Vector2.ZERO
	if delta >= 1.0:
		_look = ahead
	else:
		_look = _look.lerp(ahead, clampf(delta * LOOK_EASE, 0.0, 1.0))
	var lean := Vector3(_look.x, 0, _look.y)
	var sprint := 0.0 if showcase else _sprint
	var kick := 0.0
	if not showcase and _dash_age < FOV_DASH_IN + FOV_DASH_OUT:
		kick = _dash_age / FOV_DASH_IN if _dash_age < FOV_DASH_IN else 1.0 - (_dash_age - FOV_DASH_IN) / FOV_DASH_OUT
	var d := 3.3 if showcase else lerpf(CAM_DIST, CAM_DIST_SPRINT, sprint)
	var want := ow.hero_pos + lean + back * d + Vector3(0, 1.35 if showcase else 3.3, 0)
	want.y = maxf(want.y, Land.height(want.x, want.z) + 1.0)
	ow.cam.position = ow.cam.position.lerp(want, clampf(delta * (CAM_FOLLOW + CAM_FOLLOW_RUN * _run), 0.0, 1.0))
	ow.cam.look_at(ow.hero_pos + lean + Vector3(0, 1.15 if showcase else 1.6, 0))
	ow.cam.fov = lerpf(lerpf(FOV, FOV_SPRINT, sprint), FOV_DASH, kick)
	ow.cam.h_offset = lerpf(ow.cam.h_offset, 1.45 if showcase else 0.0, clampf(delta * 8.0, 0.0, 1.0))
	if ow._show_light:
		ow._show_light.visible = showcase
