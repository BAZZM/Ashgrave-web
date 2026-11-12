extends Node

const Tune := preload("res://scripts/combat_tune.gd")

var d: Duel

## Camera. The position is tweened here (not on the Camera3D) so it can be kept
## above the ground on the open land before it is applied.
var fov_base := 55.0
var _cam_tw: Tween
var _cam_pos := Vector3.ZERO
var _cam_driven := false
var _clamp_ground := false
var _kick := Vector2.ZERO
var _recoil_tw: Tween

## Time scale: a freeze (hit-stop) and a slow motion can both be running. The
## stronger one wins, and when a freeze ends the slow motion it interrupted resumes.
const FREEZE_SCALE := 0.05
var _freeze_end := 0
var _slow_end := 0
var _slow_scale := 1.0


func _init(owner_duel: Duel) -> void:
	d = owner_duel


# ---------------------------------------------------------------- camera

func _cam_to(pos: Vector3, look: Vector3, t: float, fov := 55.0) -> void:
	if not _cam_driven:
		_cam_pos = d.cam.position
		_cam_driven = true
	if _cam_tw:
		_cam_tw.kill()
	_cam_tw = d.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_cam_tw.tween_property(self, "_cam_pos", pos, t)
	_cam_tw.tween_property(d, "_look", look, t)
	_cam_tw.tween_property(self, "fov_base", fov, t)


## The low side shot used when a foe waits to be finished or executed. The side
## is the one away from any other foes; the camera stays above the ground.
func _finisher_cam() -> void:
	var side := _free_side()
	var mid_z := (d.player.position.z + d.enemy.position.z) * 0.5
	var pos := Vector3(d.enemy.position.x + side * float(Tune.B1.fin_x), float(Tune.B1.fin_y), mid_z + float(Tune.B1.fin_z_off))
	_clamp_ground = true
	# _look is in this node's space; the clash point is in world space.
	_cam_to(pos, d.to_local(d.enemy.get_clash_point()), float(Tune.B1.fin_time), float(Tune.B1.fin_fov))


## On the deciding swipe: push in toward the foe.
func _push_in() -> void:
	var look := d.to_local(d.enemy.get_clash_point())
	var pos := _cam_pos.lerp(look, float(Tune.B1.push_frac))
	d.cam.fov = float(Tune.B1.push_fov)
	_cam_to(pos, look, float(Tune.B1.push_time), float(Tune.B1.push_fov))


## Ease back to the normal camera.
func _cam_release(t := -1.0) -> void:
	if t < 0.0:
		t = float(Tune.B1.ease_back)
	_cam_to(Duel.CAM_POS, Duel.CAM_LOOK, t)
	_cam_tw.chain().tween_callback(func(): _clamp_ground = false)


## +1 or -1: the x side of the foe with fewer other foes on it (+1 when equal).
func _free_side() -> float:
	var n := 0.0
	for o in d.others:
		n += float(o.side)
	return -1.0 if n > 0.0 else 1.0


func _update_camera(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.05)
	d._shake = move_toward(d._shake, 0.0, real * 2.2)
	_kick = _kick.move_toward(Vector2.ZERO, real * float(Tune.B1.cut_kick) / float(Tune.B1.cut_kick_time))
	if _cam_driven:
		var p := _cam_pos
		if _clamp_ground and d.host != null:
			var wp := d.to_global(p)
			var floor_y := d.stage._ground(wp) + float(Tune.B1.fin_ground_clear)
			if wp.y < floor_y:
				p.y += floor_y - wp.y
		d.cam.position = p
	var sway := Vector3.ZERO
	if not d.started:
		sway = Vector3(sin(d._t * 0.25) * 0.5, sin(d._t * 0.4) * 0.08, 0)
	d.cam.look_at(d.to_global(d._look + sway))
	d.cam.h_offset = d._cam_offset_x + _kick.x + randf_range(-1, 1) * d._shake * 0.12
	d.cam.v_offset = _kick.y + randf_range(-1, 1) * d._shake * 0.12
	d.cam.fov = move_toward(d.cam.fov, fov_base, real * 30.0)


## A short camera push toward the swipe direction (v in screen terms).
func _kick_toward(v: Vector2) -> void:
	var dir := v.normalized()
	_kick = Vector2(dir.x, -dir.y) * float(Tune.B1.cut_kick)


# ---------------------------------------------------------------- sparks and buzz

func _make_sparks(color := Color(1.0, 0.85, 0.5), size := 0.05, amount := 28) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 6.5
	p.gravity = Vector3(0, -9, 0)
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = color
	q.material = m
	p.mesh = q
	return p


func _burst(pos: Vector3, amount: int) -> void:
	d.sparks.global_position = pos
	d.sparks.initial_velocity_max = 3.0 + amount * 0.14
	d.sparks.restart()
	d.sparks.emitting = true


## The second emitter: larger, hotter sparks for chain enders, perfect parries and executions.
func _burst2(pos: Vector3, amount: int) -> void:
	d.sparks2.global_position = pos
	d.sparks2.initial_velocity_max = 4.0 + amount * 0.14
	d.sparks2.restart()
	d.sparks2.emitting = true


func _buzz(ms: int) -> void:
	Input.vibrate_handheld(ms)


# ---------------------------------------------------------------- time

func _restore_time() -> void:
	d._time_token += 1
	_freeze_end = 0
	_slow_end = 0
	d._tutorial_slowed = false
	Engine.time_scale = d._base_time


## Work out the time scale from the freeze and slow motion now running, and
## schedule the next change. Timers ignore time scale.
func _set_scale() -> void:
	var now := Time.get_ticks_msec()
	var f := 1.0
	var until := 0
	if now < _freeze_end:
		f = FREEZE_SCALE
		until = _freeze_end
	elif now < _slow_end:
		f = _slow_scale
		until = _slow_end
	Engine.time_scale = d._base_time * f
	d._time_token += 1
	if until > 0:
		var token: int = d._time_token
		d.get_tree().create_timer(maxf(float(until - now) / 1000.0, 0.001), true, false, true).timeout.connect(func():
			if token == d._time_token:
				_set_scale())


## Slow motion at `scale_f` for `real_seconds`. Begins after a freeze that is running.
func _slow(scale_f: float, real_seconds: float) -> void:
	var now := Time.get_ticks_msec()
	_slow_scale = scale_f
	_slow_end = maxi(now, _freeze_end) + int(real_seconds * 1000.0)
	_set_scale()


## Hit-stop: a near-total freeze for `real_seconds`, even inside slow motion.
func _hitstop(real_seconds: float) -> void:
	_freeze_end = maxi(_freeze_end, Time.get_ticks_msec() + int(real_seconds * 1000.0))
	_set_scale()


# ---------------------------------------------------------------- recoil

## Push the foe's body 0.12 along the cut and let it settle back. `letter` is
## the swipe: L, R, U (thrust, away from the player) or D (down).
func _recoil(letter: String) -> void:
	var off := Vector3.ZERO
	match letter:
		"L": off = Vector3(-1, 0, 0)
		"R": off = Vector3(1, 0, 0)
		"U": off = Vector3(0, 0, -1)
		"D": off = Vector3(0, -0.6, -0.4)
	_recoil_cancel()
	var node: Node3D = d.enemy
	var base := node.position
	_recoil_tw = d.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_recoil_tw.tween_property(node, "position", base + off * float(Tune.B1.cut_recoil), float(Tune.B1.cut_recoil_out))
	_recoil_tw.tween_property(node, "position", base, float(Tune.B1.cut_recoil_back))


## Stop a recoil in flight (the fighter is about to be placed somewhere).
func _recoil_cancel() -> void:
	if _recoil_tw:
		_recoil_tw.kill()
		_recoil_tw = null


# ---------------------------------------------------------------- feel packages

## A cut lands on an open foe.
func cut_landed(v: Vector2, letter: String, ender: bool) -> void:
	_recoil(letter)
	_kick_toward(v)
	d.hud.slash_streak(v, ender)
	if ender:
		d._shake = maxf(d._shake, float(Tune.B1.ender_shake))
		d.cam.fov = float(Tune.B1.ender_fov)
		d.enemy.flash(Tune.B1.ender_flash)
		d.sfx.layer("L2")
		_burst(d.enemy.get_clash_point(), 8)
		_burst2(d.enemy.get_clash_point(), int(Tune.B1.ender_sparks))
		_hitstop(float(Tune.B1.ender_freeze))
		_buzz(45)
	else:
		d._shake = maxf(d._shake, float(Tune.B1.cut_shake))
		d.sfx.layer("L1")
		_burst(d.enemy.get_clash_point(), 8)
		_hitstop(float(Tune.B1.cut_freeze))
		_buzz(15)


## A parry. The perfect one is a different event: freeze, then a long slow, a
## smaller field of view, a gold edge, a second spark burst and a layered chime.
func parried(perfect: bool, mid: Vector3) -> void:
	d._shake = maxf(d._shake, float(Tune.B1.parry_shake))
	_buzz(40)
	if perfect:
		d.cam.fov = float(Tune.B1.perfect_fov)
		d.sfx.layer("L3")
		_burst(mid, 28)
		_burst2(mid, int(Tune.B1.perfect_sparks))
		_hitstop(float(Tune.B1.perfect_freeze))
		_slow(float(Tune.B1.perfect_slow), float(Tune.B1.perfect_slow_time))
		d.hud.edge_flash(Tune.B1.perfect_edge)
		d.hud.posture_pulse()
	else:
		d.cam.fov = float(Tune.B1.parry_fov)
		d.sfx.play("clang")
		_burst(mid, 28)
		_slow(float(Tune.B1.parry_slow), float(Tune.B1.parry_slow_time))


## The foe's posture bar fills.
func posture_broken() -> void:
	d.sfx.layer("L4")
	d.hud.posture_pulse()
	_hitstop(float(Tune.B1.break_freeze))
	_slow(float(Tune.B1.break_slow), float(Tune.B1.break_slow_time))
	_burst2(d.enemy.get_clash_point(), 20)
	_buzz(60)


## The killing blow lands: freeze on contact, then the slow wait for the finish.
func killing_blow() -> void:
	_hitstop(float(Tune.B1.fin_freeze))
	_slow(float(Tune.B1.fin_slow), float(Tune.B1.fin_slow_time))
	d.cinematic = 1.0
	_finisher_cam()


## The deciding swipe (a finish or an execution): push in, freeze, slow, then ease back.
func deciding_blow() -> void:
	_push_in()
	_hitstop(float(Tune.B1.push_freeze))
	_slow(float(Tune.B1.push_slow), float(Tune.B1.push_slow_time))
