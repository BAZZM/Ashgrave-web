extends SceneTree
## Casino core test runner. Run through tools/casino_tests/run.sh, which copies
## the scripts into a throwaway project so the repo's game/.godot is never touched.
## User args (after --): --export=<file> for the Python cross-checks, --quick
## for smaller property runs, --write-vectors=<dir> to regenerate the golden
## vectors, --only=<name,...> to run just those modules (for iterating),
## --skip=<name,...> to leave modules out, --fail-fast to stop after the first module with a failure (mutation runs).

const MODULES := [
	preload("res://tests/t_core.gd"),
	preload("res://tests/t_eval.gd"),
	preload("res://tests/t_vectors.gd"),
	preload("res://tests/t_blackjack.gd"),
	preload("res://tests/t_roulette.gd"),
	preload("res://tests/t_holdem.gd"),
	preload("res://tests/t_props.gd"),
]

var passes := 0
var fails := 0
var group := ""
var export_path := ""
var quick := false
var write_vectors := ""
var only: PackedStringArray = []
var fail_fast := false
var skip: PackedStringArray = []
var hands_per_sec := 0.0
var _group_fails := 0


func check(cond: bool, name: String) -> bool:
	if cond:
		passes += 1
	else:
		fails += 1
		_group_fails += 1
		if _group_fails <= 25:
			print("  FAIL [%s] %s" % [group, name])
	return cond


func eq(a: Variant, b: Variant, name: String) -> bool:
	var same: bool = typeof(a) == typeof(b) and a == b
	if not same and typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		same = a == b
	if not same:
		return check(false, "%s: got %s, want %s" % [name, str(a), str(b)])
	return check(true, name)


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--export="):
			export_path = a.substr(9)
		elif a == "--quick":
			quick = true
		elif a.begins_with("--write-vectors="):
			write_vectors = a.substr(16)
		elif a.begins_with("--skip="):
			skip = a.substr(7).split(",")
		elif a == "--fail-fast":
			fail_fast = true
		elif a.begins_with("--only="):
			only = a.substr(7).split(",")
	var t_all := Time.get_ticks_msec()
	for m in MODULES:
		var inst = m.new()
		if (not only.is_empty() and not (inst.NAME in only)) or inst.NAME in skip:
			continue
		var t0 := Time.get_ticks_msec()
		var p0 := passes
		var f0 := fails
		group = inst.NAME
		_group_fails = 0
		inst.run(self)
		print("%-12s %6d checks, %d failed  (%.1f s)" % [group, passes - p0 + fails - f0, fails - f0,
			(Time.get_ticks_msec() - t0) / 1000.0])
		if fail_fast and fails > 0:
			print("fail-fast: stopping after %s" % group)
			break
	print("GDSCRIPT TOTAL: %d checks, %d failed, %.1f s" % [passes + fails, fails,
		(Time.get_ticks_msec() - t_all) / 1000.0])
	quit(1 if fails > 0 else 0)
