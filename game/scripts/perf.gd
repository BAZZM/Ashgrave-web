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
## --perflog: print every mark and a stats line every few seconds to the console
## (for measuring here, where there is no one to read the panel). --perfdump adds
## a one-off breakdown of the scene by category, found by hiding each in turn.
var logging := false
var _dump := false
var _world := false
var _live := false
var _bench := false
var _seen := {}
var _log_next := 0
var _dump_next := 0

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
	var args := OS.get_cmdline_user_args()
	_dump = "--perfdump" in args
	_world = "--worlddump" in args
	_live = "--worldlive" in args
	_bench = "--terrainbench" in args
	logging = "--perflog" in args or _dump or _world or _live or _bench
	if on:
		_enable()
	elif logging:
		set_process(true)
		_last = Time.get_ticks_usec()
		_dump_next = _last + 14_000_000


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
	if logging:
		print("MARK %s %.2f ms" % [label, usec / 1000.0])
	if not enabled or usec < MARK_MIN_USEC:
		return
	_marks.append("%s %.1f ms" % [label, usec / 1000.0])
	if _marks.size() > MARK_KEEP:
		_marks.pop_front()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := now - _last
	_last = now
	if enabled and dt < IGNORE_USEC:
		_times.append(now)
		_durs.append(dt)
		if dt > BAD_STUTTER_USEC:
			_bad.append(now)
		elif dt > STUTTER_USEC:
			_stutters.append(now)
	if logging and now >= _log_next:
		_log_next = now + 3_000_000
		print(_stats_line())
	if _live:
		_world_live()
	if (_dump or _world or _bench) and now >= _dump_next:
		_dump_next = now + 1_000_000_000_000
		if _bench:
			_terrain_bench()
		elif _world:
			_world_dump()
		else:
			_breakdown()
	if enabled and now >= _next_refresh:
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


func _monitors() -> Array:
	return [int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))]


func _stats_line() -> String:
	var m := _monitors()
	var sc := get_tree().current_scene
	var pos: Variant = sc.get("hero_pos") if sc else null
	var chunks: Variant = sc.get("_chunks") if sc else null
	return "PERFLOG pos=%s chunks=%s draw=%d obj=%d prim=%d nodes=%d" % [
		"%d,%d" % [pos.x, pos.z] if pos is Vector3 else "-", chunks.size() if chunks is Dictionary else "-", m[0], m[1], m[2], m[3]]


## Which part of the scene a mesh node belongs to, for the breakdown.
func _category(n: Node, owned: Dictionary, roots: Dictionary, scene: Node) -> String:
	var up: Node = n
	while up != null and up != scene:
		if owned.has(up):
			return owned[up]
		if roots.has(up.get_parent()):
			if up == n:
				if n is MultiMeshInstance3D:
					return "scatter"
				if (n as MeshInstance3D).mesh is PlaneMesh:
					return "water"
				if (n as MeshInstance3D).mesh is ArrayMesh:
					return "ground"
				return "bridge"
			return "places"
		up = up.get_parent()
	if scene.get("hero") != null and scene.hero.is_ancestor_of(n):
		return "hero"
	return "other"


func _breakdown() -> void:
	var scene := get_tree().current_scene
	if scene == null or scene.get("ents") == null:
		return
	var owned := {}
	for e in scene.ents:
		if e.get("node") != null and is_instance_valid(e.node):
			owned[e.node] = _ent_category(e.type)
	var roots := {}
	for k in scene._chunks:
		roots[scene._chunks[k].root] = true
	var groups := {}
	var stack: Array = [scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if not (n is MeshInstance3D or n is MultiMeshInstance3D):
			continue
		if not (n as Node3D).is_visible_in_tree():
			continue
		var c := _category(n, owned, roots, scene)
		if not groups.has(c):
			groups[c] = {"nodes": [], "meshes": 0, "inst": 0}
		var g: Dictionary = groups[c]
		g.nodes.append(n)
		if n is MultiMeshInstance3D:
			var mm: MultiMesh = n.multimesh
			g.meshes += 1
			g.inst += mm.instance_count
		else:
			g.meshes += 1
			g.inst += 1
	var base: Array = await _sample()
	print("BREAKDOWN base mean of 6 frames: draw %.0f obj %.0f prim %.0f nodes %.0f (shadow passes included); each row below is what hiding that category removes" % base)
	for c in groups:
		var g: Dictionary = groups[c]
		for n in g.nodes:
			n.visible = false
		var m: Array = await _sample()
		for n in g.nodes:
			if is_instance_valid(n):
				n.visible = true
		# The counts drift as things move, so compare with the visible scene sampled just before and after.
		var after: Array = await _sample()
		var ref: Array = [(base[0] + after[0]) * 0.5, (base[1] + after[1]) * 0.5, (base[2] + after[2]) * 0.5]
		base = after
		print("BREAKDOWN %-10s meshnodes=%4d instances=%6d | draw %5.0f  obj %5.0f  prim %7.0f" % [c, g.meshes, g.inst, ref[0] - m[0], ref[1] - m[1], ref[2] - m[2]])
	var sun: Variant = scene.sky._sun if scene.get("sky") != null else null
	if sun is DirectionalLight3D:
		sun.shadow_enabled = false
		var m2: Array = await _sample()
		sun.shadow_enabled = true
		var after2: Array = await _sample()
		print("BREAKDOWN %-10s (sun shadows off)                     | draw %5.0f  obj %5.0f  prim %7.0f" % ["shadows", (base[0] + after2[0]) * 0.5 - m2[0], (base[1] + after2[1]) * 0.5 - m2[1], (base[2] + after2[2]) * 0.5 - m2[2]])
	print("BREAKDOWN done")


func _ent_category(t: String) -> String:
	match t:
		"foe", "beast", "node", "chest":
			return t
		"npc", "player", "smith", "store", "task":
			return "figures"
	return "places"


## Mean of the monitors over several frames: draw counts wobble from frame to frame.
func _sample() -> Array:
	await _settle()
	var sum := [0, 0, 0, 0]
	for i in 6:
		await get_tree().process_frame
		var m := _monitors()
		for j in 4:
			sum[j] += m[j]
	return [sum[0] / 6.0, sum[1] / 6.0, sum[2] / 6.0, sum[3] / 6.0]


func _settle() -> void:
	for i in 4:
		await get_tree().process_frame


## One line describing a chunk's entities and obstacles, for comparing builds.
func _chunk_line(k: Vector2i, chunk: Dictionary) -> String:
	var text := ""
	for e in chunk.ents:
		text += "%s|%s|%.3f,%.3f,%.3f|%s|%s|%s|%s|%s|%s|%s;" % [e.id, e.type, e.pos.x, e.pos.y, e.pos.z, e.get("wild", ""), e.get("node_id", ""), e.get("beast", ""), e.get("gold", ""), e.get("label", ""), e.get("height", ""), e.get("charges", "")]
	var otext := ""
	for o in chunk.obstacles:
		otext += "%.3f,%.3f,%.3f;" % [o.x, o.y, o.z]
	return "%d,%d ents=%d obstacles=%d ents_hash=%d obst_hash=%d" % [k.x, k.y, chunk.ents.size(), chunk.obstacles.size(), text.hash(), otext.hash()]


## --worlddump: build every chunk of the land in turn and print one line per chunk.
## --worldlive: print a line for each chunk the running game loads (walk with a bot).
## Debug only.
func _world_dump() -> void:
	var scene := get_tree().current_scene
	if scene == null or scene.get("terrain") == null:
		return
	var total := 0
	for kz in range(-7, 5):
		for kx in range(-6, 6):
			var k := Vector2i(kx, kz)
			scene.terrain._build_chunk(k)
			var chunk: Dictionary = scene._chunks[k]
			print("WORLD " + _chunk_line(k, chunk) + " ground_hash=%d" % _ground_hash(scene, k))
			total += chunk.ents.size()
			chunk.root.queue_free()
			scene._chunks.erase(k)
	print("WORLD done ents=%d" % total)


## Hash of the ground heights and colours of a chunk: from the terrain's own function if
## it has one, else computed from Land directly (the reference).
func _ground_hash(scene: Node, k: Vector2i) -> int:
	var origin := Vector2(k.x * Land.CHUNK, k.y * Land.CHUNK)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	if scene.terrain.has_method("_ground_arrays"):
		var a: Array = scene.terrain._ground_arrays(origin)
		verts = a[0]
		cols = a[1]
	else:
		var step := Land.CHUNK / 10
		for iz in 11:
			for ix in 11:
				var x := origin.x + ix * step
				var z := origin.y + iz * step
				cols.append(Land.ground_color(x, z))
				verts.append(Vector3(x, Land.height(x, z), z))
	return hash(verts) * 31 + hash(cols)


func _world_live() -> void:
	var scene := get_tree().current_scene
	if scene == null or scene.get("_chunks") == null:
		return
	for k in scene._chunks:
		if not _seen.has(k):
			_seen[k] = true
			print("WORLD " + _chunk_line(k, scene._chunks[k]))


## --terrainbench: time building every chunk of the land whole, three passes (the first
## includes one-off costs, the later ones are the typical). Debug only.
func _terrain_bench() -> void:
	var scene := get_tree().current_scene
	if scene == null or scene.get("terrain") == null:
		return
	for pass_no in 3:
		var times: Array = []
		var worst := ""
		var worst_t := 0
		for kz in range(-7, 5):
			for kx in range(-6, 6):
				var k := Vector2i(kx, kz)
				var t := Time.get_ticks_usec()
				scene.terrain._build_chunk(k)
				var dt := Time.get_ticks_usec() - t
				times.append(dt)
				if dt > worst_t:
					worst_t = dt
					worst = str(k)
				scene._chunks[k].root.queue_free()
				scene._chunks.erase(k)
		var sorted := times.duplicate()
		sorted.sort()
		var sum := 0
		for v in times:
			sum += v
		print("BENCH pass %d chunks=%d mean %.2f ms  median %.2f  p90 %.2f  max %.2f (chunk %s)" % [pass_no, times.size(), sum / 1000.0 / times.size(),
			sorted[sorted.size() / 2] / 1000.0, sorted[int(sorted.size() * 0.9)] / 1000.0, sorted[-1] / 1000.0, worst])
		await get_tree().process_frame
	print("BENCH done")
