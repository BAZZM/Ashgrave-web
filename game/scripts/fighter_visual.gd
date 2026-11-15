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


func set_pace(_mult: float) -> void:
	pass


func flash(_color: Color) -> void:
	pass


func get_clash_point() -> Vector3:
	return global_position + Vector3(0, 1.4 * scale.y, 0)


# ---------------------------------------------------------------- the rig switch (docs/RIG_R2.md)
# The hero is a RigVisual (KayKit) only when ALL hold: the flag is given (`--rig` as a user arg, or `?rig=1` in the page URL),
# the quality level allows models (not Safe), and the rig is in the pack. Otherwise it is the PlaceholderVisual, exactly as
# before. The quality gate comes first: Safe never loads the rig script or any rig asset. Nothing here names the rig script
# in a preload, so without the flag it is never loaded.
static var _rig_flag := -1
static var _rig_script: GDScript


static func rig_flag() -> bool:
	if _rig_flag < 0:
		_rig_flag = 0
		if "--rig" in OS.get_cmdline_user_args():
			_rig_flag = 1
		elif OS.has_feature("web"):
			var v: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('rig') || ''", true)
			if v is String and v in ["1", "true", "on"]:
				_rig_flag = 1
	return _rig_flag == 1


static func rig_wanted() -> bool:
	if not rig_flag():
		return false
	if not Run.quality_allows("models"):
		return false
	return ResourceLoader.exists("res://scripts/rig_visual.gd") and ResourceLoader.exists("res://assets/rig/knight.glb")


## A new hero visual for the world or the tower, carrying a shield: a RigVisual when rig_wanted(), else a PlaceholderVisual.
static func make_hero() -> FighterVisual:
	var v: FighterVisual
	if rig_wanted():
		if _rig_script == null:
			_rig_script = load("res://scripts/rig_visual.gd") as GDScript
		v = _rig_script.new()
	else:
		if not Run.quality_allows("models"):
			release_rig()
		v = PlaceholderVisual.new()
	v.set("has_shield", true)
	return v


## What configure() gets for the hero: Items.hero_look plus the equipped ids (the rig maps gear by item; the primitive hero ignores `eq`).
static func hero_cfg() -> Dictionary:
	var c := Run.look()
	c["eq"] = Run.data.equipped.duplicate()
	return c


## Free the rig's static caches (clips, meshes, gear, atlas, shader) and the script itself, once no rig is alive: called when
## quality drops to Safe, where TexKit.clear() is. A no-op when the rig was never loaded.
static func release_rig() -> void:
	if _rig_script != null:
		_rig_script.call(&"release")
		_rig_script = null


## Debug (tools/check.js `rig-cycle`): `--rigcycle=N` adds the scene-cycling counter to the scene that made its hero.
static func debug_cycle(scene: Node) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rigcycle=") and ResourceLoader.exists("res://scripts/rig_cycle.gd"):
			var c: Node = (load("res://scripts/rig_cycle.gd") as GDScript).new()
			c.set("total", int(a.trim_prefix("--rigcycle=")))
			scene.add_child(c)
