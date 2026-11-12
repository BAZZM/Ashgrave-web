extends Node

const SPEED := 5.0

var ow: Overworld
var _walked := 0.0


func _init(owner_world: Overworld) -> void:
	ow = owner_world


func _move_hero(delta: float) -> void:
	var input := ow.stick
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): input.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): input.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): input.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): input.x += 1.0
	var dir := Vector3.ZERO
	if ow._bot != "":
		dir = ow.bots._bot_dir(delta)
	elif input.length() > 0.12:
		input = input.limit_length(1.0)
		var f := Vector3(-sin(ow.cam_yaw), 0, -cos(ow.cam_yaw))
		var r := Vector3(cos(ow.cam_yaw), 0, -sin(ow.cam_yaw))
		dir = r * input.x - f * input.y
	var amount := minf(dir.length(), 1.0)
	if amount > 0.05:
		ow._gather = {}
		ow.gather_progress = -1.0
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
	ow.hero_pos.y = lerpf(ow.hero_pos.y, Land.walk_height(ow.hero_pos.x, ow.hero_pos.z), clampf(delta * 12.0, 0.0, 1.0))
	ow.hero.set_walk(amount)
	ow.hero.position = ow.hero_pos
	ow.hero.rotation.y = ow.hero_yaw


func _update_camera(delta: float) -> void:
	var showcase: bool = ow.hud != null and ow.hud.screen in ["bag", "shop"]
	var yaw := ow.cam_yaw + (PI + 0.55 + sin(ow._t * 0.25) * 0.35 if not ow.started else 0.0)
	var back := Vector3(sin(yaw), 0, cos(yaw))
	var d := 3.3 if showcase else 6.6
	var want := ow.hero_pos + back * d + Vector3(0, 1.35 if showcase else 3.3, 0)
	want.y = maxf(want.y, Land.height(want.x, want.z) + 1.0)
	ow.cam.position = ow.cam.position.lerp(want, clampf(delta * 8.0, 0.0, 1.0))
	ow.cam.look_at(ow.hero_pos + Vector3(0, 1.15 if showcase else 1.6, 0))
	ow.cam.h_offset = lerpf(ow.cam.h_offset, 1.45 if showcase else 0.0, clampf(delta * 8.0, 0.0, 1.0))
	if ow._show_light:
		ow._show_light.visible = showcase
