extends Node

var d: Duel
var _cam_tw: Tween


func _init(owner_duel: Duel) -> void:
	d = owner_duel


func _cam_to(pos: Vector3, look: Vector3, t: float) -> void:
	if _cam_tw:
		_cam_tw.kill()
	_cam_tw = d.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_cam_tw.tween_property(d.cam, "position", pos, t)
	_cam_tw.tween_property(d, "_look", look, t)


func _make_sparks() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 28
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 6.5
	p.gravity = Vector3(0, -9, 0)
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(1.0, 0.85, 0.5)
	q.material = m
	p.mesh = q
	return p


func _update_camera(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.05)
	d._shake = move_toward(d._shake, 0.0, real * 2.2)
	var sway := Vector3.ZERO
	if not d.started:
		sway = Vector3(sin(d._t * 0.25) * 0.5, sin(d._t * 0.4) * 0.08, 0)
	d.cam.look_at(d.to_global(d._look + sway))
	d.cam.h_offset = d._cam_offset_x + randf_range(-1, 1) * d._shake * 0.12
	d.cam.v_offset = randf_range(-1, 1) * d._shake * 0.12
	d.cam.fov = move_toward(d.cam.fov, 55.0, real * 30.0)


func _burst(pos: Vector3, amount: int) -> void:
	d.sparks.global_position = pos
	d.sparks.initial_velocity_max = 3.0 + amount * 0.14
	d.sparks.restart()
	d.sparks.emitting = true


func _buzz(ms: int) -> void:
	Input.vibrate_handheld(ms)


func _restore_time() -> void:
	d._time_token += 1
	d._tutorial_slowed = false
	Engine.time_scale = d._base_time


func _slow(scale_f: float, real_seconds: float) -> void:
	d._time_token += 1
	var token := d._time_token
	Engine.time_scale = d._base_time * scale_f
	d.get_tree().create_timer(real_seconds, true, false, true).timeout.connect(func():
		if token == d._time_token:
			Engine.time_scale = d._base_time)


func _hitstop(real_seconds: float) -> void:
	if Engine.time_scale < d._base_time * 0.9:
		return
	_slow(0.05, real_seconds)
