class_name FighterVisual
extends Node3D


func play(_action: StringName, _dir: int = 0, _duration: float = 0.3) -> void:
	pass


func configure(_cfg: Dictionary) -> void:
	pass


func set_tell(_color: Color, _t: float) -> void:
	pass


func set_walk(_amount: float) -> void:
	pass


func flash(_color: Color) -> void:
	pass


func get_clash_point() -> Vector3:
	return global_position + Vector3(0, 1.4 * scale.y, 0)
