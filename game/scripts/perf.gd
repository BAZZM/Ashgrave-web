extends Node
## On-screen performance readout, for measuring stutter on a real device.
##
## Off by default and then costs nothing: no processing, no nodes.
## Turn on with ?perf=1 on the page URL, or --perf as a user arg.
## Other code can report a costly event with Perf.mark("chunk build", usec).

## Frame-time window for fps / avg / p95 / worst.
const WINDOW_USEC := 5_000_000
## Stutters are counted over this long.
const STUTTER_WINDOW_USEC := 60_000_000
const STUTTER_USEC := 50_000
const BAD_STUTTER_USEC := 100_000
## Frames longer than this are the tab being hidden, not stutter.
const IGNORE_USEC := 5_000_000
const REFRESH_USEC := 250_000
## Marks shorter than this are not worth listing.
const MARK_MIN_USEC := 8_000
const MARK_KEEP := 4
const FONT_SIZE := 16

var enabled := false

var _last := 0
var _next_refresh := 0
var _times := PackedInt64Array()
var _durs := PackedInt64Array()
var _head := 0
var _stutters := PackedInt64Array()
var _bad := PackedInt64Array()
var _marks: Array = []
var _label: Label
var _bg: ColorRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	var on := "--perf" in OS.get_cmdline_user_args()
	if not on and OS.has_feature("web"):
		var q: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('perf') || ''", true)
		on = q is String and q != "" and q != "0"
	if on:
		_enable()


func _enable() -> void:
	enabled = true
	var layer := CanvasLayer.new()
	layer.layer = 128
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	# Bottom left, in the gap between the duel's dodge and block buttons.
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.85)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bg.offset_left = 222
	bg.offset_right = 222 + 330
	bg.offset_bottom = -6
	bg.offset_top = -6 - 112
	root.add_child(bg)
	_bg = bg
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.offset_left = 6
	_label.offset_top = 3
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_constant_override("line_spacing", 0)
	_label.add_theme_color_override("font_color", Color(0.75, 1.0, 0.75))
	_label.clip_text = true
	_label.text = "perf..."
	bg.add_child(_label)
	_last = Time.get_ticks_usec()
	set_process(true)


## Report a costly event. Ignored while the readout is off.
func mark(label: String, usec: int) -> void:
	if not enabled or usec < MARK_MIN_USEC:
		return
	_marks.append("%s %.1f ms" % [label, usec / 1000.0])
	if _marks.size() > MARK_KEEP:
		_marks.pop_front()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := now - _last
	_last = now
	if dt < IGNORE_USEC:
		_times.append(now)
		_durs.append(dt)
		if dt > BAD_STUTTER_USEC:
			_bad.append(now)
		elif dt > STUTTER_USEC:
			_stutters.append(now)
	if now >= _next_refresh:
		_next_refresh = now + REFRESH_USEC
		_refresh(now)


func _refresh(now: int) -> void:
	while _head < _times.size() and _times[_head] < now - WINDOW_USEC:
		_head += 1
	if _head > 512:
		_times = _times.slice(_head)
		_durs = _durs.slice(_head)
		_head = 0
	_stutters = _trim(_stutters, now)
	_bad = _trim(_bad, now)
	var n := _durs.size() - _head
	var fps := 0.0
	var avg := 0.0
	var p95 := 0.0
	var worst := 0.0
	if n > 0:
		var w := _durs.slice(_head)
		var sum := 0
		for d in w:
			sum += d
		avg = sum / float(n) / 1000.0
		fps = 1000.0 / avg if avg > 0.0 else 0.0
		w.sort()
		p95 = w[mini(n - 1, int(n * 0.95))] / 1000.0
		worst = w[n - 1] / 1000.0
	var scene := get_tree().current_scene
	var win := DisplayServer.window_get_size()
	var vp := get_viewport().get_visible_rect().size
	var t := "%.0f fps   nodes %d\n" % [fps, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))]
	t += "ms avg %.1f  p95 %.1f  max %.1f\n" % [avg, p95, worst]
	t += "stutter 60s: >50ms %d  >100ms %d\n" % [_stutters.size() + _bad.size(), _bad.size()]
	t += "draw %d  obj %d  prim %d\n" % [
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))]
	t += "%s  vp %dx%d  win %dx%d" % [scene.name if scene else "-", vp.x, vp.y, win.x, win.y]
	for m in _marks:
		t += "\n! " + m
	_label.text = t
	_bg.offset_top = -6 - (22.0 * (5 + _marks.size()) + 6.0)


func _trim(a: PackedInt64Array, now: int) -> PackedInt64Array:
	var i := 0
	while i < a.size() and a[i] < now - STUTTER_WINDOW_USEC:
		i += 1
	return a.slice(i) if i > 0 else a
