extends Node
## Debug only (--rigcycle=N, tools/check.js `rig-cycle`): enters and leaves the land and the tower N times each and prints the
## counts a leak would move after each arrival, so a run with --rig and one without can be compared. Not in the release pack.

const RigCheck := preload("res://scripts/rig_check.gd")
static var n := 0
var total := 3


func _ready() -> void:
	Run.no_save = true
	get_tree().create_timer(4.0).timeout.connect(_step)


func _step() -> void:
	var land := get_parent() is Overworld
	var s := RigCheck.snap()
	n += 1
	print("RIGCYCLE %d %s hero=%s rig_loaded=%s objects=%d resources=%d nodes=%d orphans=%d tex=%d vid=%d draws=%d" % [n, "land" if land else "tower",
		"primitive" if (get_parent().get("hero") is PlaceholderVisual) else "rig", FighterVisual._rig_script != null, s.obj, s.res, s.nodes, s.orph, s.tex, s.vid, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	if n >= total * 2:
		print("RIGCYCLE done")
		get_tree().quit()
		return
	Run.data.in_tower = land
	get_tree().change_scene_to_file("res://scenes/world.tscn" if land else "res://scenes/overworld.tscn")
