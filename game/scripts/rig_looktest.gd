extends Node3D
## Debug only: the --looktest=rig* scenes (loaded by overworld.gd's look test, nothing else).
##   rig            a RigVisual knight beside a PlaceholderVisual hero, both facing the duel camera as
##                  the foe does, play RigCheck.SEQUENCE together on one clock. --looktest-seek=T
##                  freezes both at T seconds into the sequence (the step table is printed).
##   rig-check      runs the contract check (RIGCHECK lines).
##   rig-heads      head scale 1.0 and 0.85 side by side (idle; seek freezes).
##   rig-gear       gear variants and the MeshKit blade on handslot.r: overhead windup, then a slash
##                  at 0.6 s (seek freezes). A "-close" suffix moves the camera in (rig-gear-close).
##   rig-perf=N, ph-perf=N   N RigVisual or N PlaceholderVisual fighters idling, for the Perf numbers.

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
		var ok := RigCheck.new(self).run()
		print("LOOKTEST rig-check ok=%s" % ok)
		for c in get_children():
			c.visible = false
	elif mode.begins_with("rig-heads"):
		rigs.append(_rig({"style": "hero", "shield": true}, Vector3(-0.7, 0, -2.5)))
		rigs.append(_rig({"style": "hero", "shield": true, "head": 0.85}, Vector3(0.7, 0, -2.5)))
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
	elif mode.begins_with("rig-perf=") or mode.begins_with("ph-perf="):
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
	if mode.ends_with("-close"):
		var cam := get_viewport().get_camera_3d()
		cam.position = Vector3(0, 1.5, 0.6)
		cam.look_at(get_parent().to_global(Vector3(0, 1.1, -3.0)))
	if seek >= 0.0 and not mode.begins_with("rig-perf") and not mode.begins_with("ph-perf") and mode != "rig-check":
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
