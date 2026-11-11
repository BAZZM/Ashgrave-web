class_name AnimPackVisual
extends FighterVisual

@export var animation_map: Dictionary = {}

@export var timed_actions: PackedStringArray = ["windup", "strike"]
@export var blend_time := 0.12

@export var clash_node: NodePath

var _player: AnimationPlayer
var _meshes: Array[MeshInstance3D] = []
var _flash_tw: Tween
var _flash_mat: StandardMaterial3D


func _ready() -> void:
	_player = _find_player(self)
	if _player == null:
		push_warning("AnimPackVisual: no AnimationPlayer found under %s" % name)
	_collect_meshes(self)
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.albedo_color = Color(1, 1, 1, 0)
	play(&"idle")


func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_player(c)
		if r:
			return r
	return null


func _collect_meshes(n: Node) -> void:
	if n is MeshInstance3D:
		_meshes.append(n)
	for c in n.get_children():
		_collect_meshes(c)


func _suffix(action: StringName, dir: int) -> String:
	if action == &"windup" or action == &"strike":
		return ["left", "right", "over", "thrust"][clampi(dir, 0, 3)]
	if dir == 2:
		return "up"
	if dir == 3:
		return "down"
	return "left" if dir < 0 else "right"


func play(action: StringName, dir: int = 0, duration: float = 0.3) -> void:
	if _player == null:
		return
	var key := "%s_%s" % [action, _suffix(action, dir)]
	var anim: String = animation_map.get(key, animation_map.get(String(action), ""))
	if anim == "" and action == &"recover":
		anim = animation_map.get("idle", "")
	if anim == "" or not _player.has_animation(anim):
		return
	var speed := 1.0
	if String(action) in timed_actions and duration > 0.0:
		speed = _player.get_animation(anim).length / duration
	_player.play(anim, blend_time, speed)
	if action == &"hit" or action == &"slash" or action == &"strike":
		_player.seek(0.0, true)


func flash(color: Color) -> void:
	if _flash_tw:
		_flash_tw.kill()
	_flash_mat.albedo_color = Color(color.r, color.g, color.b, 0.6)
	for m in _meshes:
		m.material_overlay = _flash_mat
	_flash_tw = create_tween()
	_flash_tw.tween_property(_flash_mat, "albedo_color:a", 0.0, 0.18)
	_flash_tw.tween_callback(func():
		for m in _meshes:
			m.material_overlay = null)


func get_clash_point() -> Vector3:
	if not clash_node.is_empty() and has_node(clash_node):
		return (get_node(clash_node) as Node3D).global_position
	return super.get_clash_point()
