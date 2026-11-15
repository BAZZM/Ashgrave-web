extends Node3D
## Debug only: the --looktest=rig* scenes (loaded by overworld.gd's look test, nothing else).
##   rig            a RigVisual knight beside a PlaceholderVisual hero, both facing the duel camera as
##                  the foe does, play RigCheck.SEQUENCE together on one clock. --looktest-seek=T
##                  freezes both at T seconds into the sequence (the step table is printed).
##   rig-check      runs the contract check (RIGCHECK lines).
##   rig-heads      head scale 1.0 and 0.85 side by side (idle; seek freezes).
##   rig-gear       gear variants and the MeshKit blade on handslot.r: overhead windup, then a slash
##                  at 0.6 s (seek freezes). A "-close" suffix moves the camera in (rig-gear-close).
##   rig-perf=N, ph-perf=N   N RigVisual or N PlaceholderVisual fighters idling, for the Perf numbers
##                  (rig18 = rig-perf=18). Prints a LOOKTEST perf_result line: frame time, draw calls, memory.
##   rig-shots      knight and skeleton warrior, each from the front and three-quarter, frozen in SHOTS one
##                  after another (tools/rig_shots.js advances with window.__lt_next), then the knight alone
##                  and the empty ground for the luminance measure (tools/g3_measure.py).

const RigVisual := preload("res://scripts/rig_visual.gd")
const RigCheck := preload("res://scripts/rig_check.gd")
const SUB := 1.0 / 60.0

var mode := ""
var seek := -1.0
var rigs: Array = []
var phs: Array = []
var _t := 0.0
var _step := -1
var _step_t := 0.0
var _starts: Array = []
var _frozen := false
var _seq := false
var _shot := -1
var _shot_wait := 0.0
var _perf_n := -1
var _perf_t := 0.0
var _perf_frames := 0
var _perf_sum := 0.0
var _perf_max := 0.0
var _perf_rss0 := 0.0

## [name, action, dir, duration, seconds after the call to freeze, walk amount]
const SHOTS := [
	["idle", &"idle", 0, 0.3, 0.6, 0.0],
	["slash", &"slash", 1, 0.35, 0.2, 0.0],
	["windup-over", &"windup", 2, 1.0, 0.7, 0.0],
	["parry", &"parry", -1, 0.3, 0.07, 0.0],
	["stagger", &"stagger", 0, 0.3, 0.3, 0.0],
	["death", &"death", 0, 0.3, 1.3, 0.0],
	["walk", &"idle", 0, 0.3, 0.55, 0.6],
	["lum-knight", &"idle", 0, 0.3, 0.6, 0.0],
	["lum-knight_empty", &"idle", 0, 0.3, 0.6, 0.0],
]


func setup(p_mode: String, p_seek: float) -> void:
	mode = p_mode
	seek = p_seek
	var t := 0.0
	for s in RigCheck.SEQUENCE:
		_starts.append(t)
		t += s[3]
	if mode == "rig":
		_seq = true
		rigs.append(_rig({"style": "hero", "shield": true}, Vector3(-1.1, 0, -2.5)))
		phs.append(_ph(Vector3(1.1, 0, -2.5)))
		var lines := []
		for i in RigCheck.SEQUENCE.size():
			var s: Array = RigCheck.SEQUENCE[i]
			lines.append("%d:%s(%d,%.2f)@%.2f" % [i, s[0], s[1], s[2], _starts[i]])
		print("LOOKTEST rig sequence (step:action(dir,duration)@start) %s total=%.2f" % [" ".join(lines), t])
	elif mode == "rig-check":
		var chk := RigCheck.new(self)
		var ok := chk.run()
		print("LOOKTEST rig-check ok=%s" % ok)
		for c in get_children():
			c.visible = false
	elif mode == "rig-gait":
		var chk2 := RigCheck.new(self)
		chk2.base = RigCheck.snap()
		var ok2 := chk2.gait()
		print("LOOKTEST rig-gait ok=%s" % ok2)
		for c in get_children():
			c.visible = false
	elif mode.begins_with("rig-heads"):
		rigs.append(_rig({"style": "hero", "shield": true, "head": 1.0}, Vector3(-0.7, 0, -2.5)))
		rigs.append(_rig({"style": "hero", "shield": true}, Vector3(0.7, 0, -2.5)))  # the default, 0.85
		for r in rigs:
			r.play(&"idle")
	elif mode.begins_with("rig-gear"):
		var looks := [
			{"style": "hero", "shield": true},
			{"style": "duelist"},
			{"style": "boss", "shield": true},
			{"style": "hero", "gear": {"sword": "meshkit", "helmet": false, "cape": false}},
		]
		for i in looks.size():
			rigs.append(_rig(looks[i], Vector3(-2.1 + 1.4 * i, 0, -3.2)))
		for r in rigs:
			r.play(&"windup", AttackDef.Dir.OVER, 1.0)
	elif mode == "rig-shots":
		var specs := [[{"style": "hero", "shield": true}, 0.0], [{"style": "hero", "shield": true}, -0.75],
			[{"style": "skeleton"}, 0.0], [{"style": "skeleton"}, -0.75]]
		for i in specs.size():
			var r := _rig(specs[i][0], Vector3(-2.4 + 1.6 * i, 0, -1.0))
			rigs.append(r)
			r.rotation.y = PI + specs[i][1]
		var cam := Camera3D.new()
		cam.fov = 50.0
		add_child(cam)
		cam.position = Vector3(0, 1.35, 4.3)
		cam.look_at(to_global(Vector3(0, 0.95, -1.0)))
		cam.make_current()
		_shot_go(0)
	elif mode == "rig18":
		mode = "rig-perf=18"
	if mode.begins_with("rig-perf=") or mode.begins_with("ph-perf="):
		var n := int(mode.get_slice("=", 1))
		var cols := 4
		for i in n:
			var pos := Vector3(-2.4 + 1.6 * (i % cols), 0, -2.5 - 2.0 * (i / cols))
			if mode.begins_with("rig"):
				var r: Node3D = _rig({"style": "hero", "shield": true}, pos)
				r.set("manual_clock", false)
			else:
				_ph(pos)
		print("LOOKTEST perf fighters=%d kind=%s" % [n, mode.get_slice("=", 0)])
		_perf_n = n
	if mode.ends_with("-close"):
		var cam := get_viewport().get_camera_3d()
		cam.position = Vector3(0, 1.5, 0.6)
		cam.look_at(get_parent().to_global(Vector3(0, 1.1, -3.0)))
	if seek >= 0.0 and mode != "rig-shots" and not mode.begins_with("rig-perf") and not mode.begins_with("ph-perf") and mode != "rig-check":
		_advance(seek)
		_frozen = true
		print("LOOKTEST frozen t=%.3f step=%d %s" % [_t, _step, str(RigCheck.SEQUENCE[_step]) if _seq and _step >= 0 else ""])


func _rig(cfg: Dictionary, pos: Vector3) -> Node3D:
	var r: FighterVisual = RigVisual.new()
	r.set("manual_clock", true)
	add_child(r)
	r.position = pos
	r.rotation.y = PI  # faces the camera, as the duel foe does
	r.configure(cfg)
	return r


func _ph(pos: Vector3) -> PlaceholderVisual:
	var p := PlaceholderVisual.new()
	p.has_shield = true
	add_child(p)
	p.configure({"style": "hero"})
	p.position = pos
	p.rotation.y = PI
	if not mode.begins_with("ph-perf"):
		p.process_mode = Node.PROCESS_MODE_DISABLED  # its tweens and _process run on our clock
	phs.append(p)
	return p


func _process(delta: float) -> void:
	if _perf_n >= 0:
		_perf_tick(delta)
	if _shot >= 0:
		_shot_poll(delta)
	if not _frozen and not rigs.is_empty() and (_seq or mode.begins_with("rig-heads") or mode.begins_with("rig-gear")):
		_advance(minf(delta, 0.1))


func _advance(dt: float) -> void:
	var left := dt
	while left > 1e-6:
		var h := minf(SUB, left)
		if _seq:
			if _step < 0 or _step_t + h > RigCheck.SEQUENCE[_step][3] and _step < RigCheck.SEQUENCE.size() - 1:
				if _step >= 0:
					h = maxf(RigCheck.SEQUENCE[_step][3] - _step_t, 0.0)
					_tick(h)
					left -= h
				_step += 1
				_step_t = 0.0
				var s: Array = RigCheck.SEQUENCE[_step]
				for v in rigs + phs:
					v.play(s[0], s[1], s[2])
				continue
		elif mode.begins_with("rig-gear") and _t < 0.6 and _t + h >= 0.6:
			for r in rigs:
				r.play(&"slash", 1, 0.35)
		_tick(h)
		left -= h


func _tick(h: float) -> void:
	_t += h
	_step_t += h
	for r in rigs:
		r.call("tick", h)
	for p in phs:
		if p.process_mode != Node.PROCESS_MODE_DISABLED:
			continue
		for n in ["_tw", "_glow_tw", "_fall_tw", "_flash_tw"]:
			var tw: Tween = p.get(n)
			if tw != null and tw.is_valid():
				tw.custom_step(h)
		p._process(h)


# ---- rig-shots: one frozen pose after another, advanced by the page (window.__lt_next = next index)

func _shot_go(i: int) -> void:
	_shot = i
	_shot_wait = 0.0
	var sh: Array = SHOTS[i]
	for k in rigs.size():
		var r: Node3D = rigs[k]
		r.visible = not (sh[0] == "lum-knight_empty" or sh[0] == "lum-knight" and k >= 2)
		r.call("set_walk", 0.0)
		r.play(&"idle")
		_tick_rig(r, 0.5)
		r.call("set_walk", sh[5])
		r.play(sh[1], sh[2], sh[3])
		_tick_rig(r, sh[4])
	print("LOOKTEST cam %s" % sh[0])


func _tick_rig(r: Node3D, t: float) -> void:
	var left := t
	while left > 1e-6:
		var h := minf(SUB, left)
		r.call("tick", h)
		left -= h


func _shot_poll(delta: float) -> void:
	_shot_wait += delta
	if _shot_wait < 0.5 or not OS.has_feature("web"):
		return
	_shot_wait = 0.0
	var v := int(JavaScriptBridge.eval("window.__lt_next === undefined ? -1 : window.__lt_next", true))
	if v > _shot and v < SHOTS.size():
		_shot_go(v)


# ---- rig-perf: frame time over 4 s after 4 s of warm-up, then the render monitors

func _perf_tick(delta: float) -> void:
	_perf_t += delta
	if _perf_t < 4.0:
		return
	if _perf_frames == 0:
		_perf_rss0 = Performance.get_monitor(Performance.MEMORY_STATIC)
	_perf_frames += 1
	_perf_sum += delta
	_perf_max = maxf(_perf_max, delta)
	if _perf_t >= 8.0:
		print("LOOKTEST perf_result kind=%s n=%d frames=%d frame_ms_avg=%.1f frame_ms_max=%.1f draw_calls=%d objects=%d primitives=%d tex_mem=%d buf_mem=%d vid_mem=%d static_mem=%d wasm_heap=%d" % [
			mode.get_slice("=", 0), _perf_n, _perf_frames, 1000.0 * _perf_sum / _perf_frames, 1000.0 * _perf_max,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)),
			int(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)), int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
			int(Performance.get_monitor(Performance.MEMORY_STATIC)),
			int(JavaScriptBridge.eval("window.__ag ? window.__ag.heap() : -1", true)) if OS.has_feature("web") else -1])
		_perf_n = -1
