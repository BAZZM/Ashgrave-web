extends RefCounted
## Debug only (--looktest=rig-check, check.js `rig-contract`): drives one RigVisual through every
## contract action on a fixed 240 Hz clock (tick(), not frames, so the result does not depend on the
## 2-4 fps of software WebGL) and prints RIGCHECK lines. A second, hidden RigVisual is the reference:
## it is posed straight from the clip at the key time, so "reached its key pose" means the hand,
## sword tip, shield hand and head of the driven rig are where the clip puts them at that moment.

const RigVisual := preload("res://scripts/rig_visual.gd")
const Clips := preload("res://scripts/rig_clips.gd")
const DT := 1.0 / 240.0
const TOL_T := 0.05
const BONES := ["hand.r", "hand.l", "head"]

## The look-test sequence: [action, dir, duration, seconds until the next call]. Durations are those
## the duel code passes (docs/RIG_PLAN.md section 1 call sites): windups are AttackDef windups (0.55-1.25),
## strike 0.1 (duel_enemy.gd:192), feint 0.42 (duel_enemy.gd:94, e_speed 1), hit 0.15 / 0.12
## (duel.gd:426, 608), slash 0.12 (duel.gd:546, 718, 820) and 0.35 (duel_pvp.gd:114); the rest pass none.
const SEQUENCE := [
	[&"idle", 0, 0.3, 0.8],
	[&"taunt", 0, 0.3, 1.4],
	[&"windup", 0, 0.9, 0.9], [&"strike", 0, 0.1, 0.6],
	[&"windup", 1, 0.6, 0.6], [&"strike", 1, 0.1, 0.6],
	[&"windup", 2, 1.15, 0.6325], [&"feint", 0, 0.42, 0.9375], [&"strike", 2, 0.1, 0.6],
	[&"windup", 3, 1.25, 1.25], [&"strike", 3, 0.1, 1.0],
	[&"stagger", 0, 0.3, 0.8], [&"idle", 0, 0.3, 0.5],
	[&"broken", 0, 0.3, 1.0], [&"idle", 0, 0.3, 0.5],
	[&"hit", -1, 0.15, 0.6], [&"hit", 1, 0.12, 0.6],
	[&"guard", 0, 0.3, 0.6], [&"idle", 0, 0.3, 0.4],
	[&"slash", -1, 0.12, 0.6], [&"slash", 1, 0.35, 0.7], [&"slash", 2, 0.12, 0.6], [&"slash", 3, 0.12, 0.6],
	[&"parry", -1, 0.3, 0.5], [&"parry", 1, 0.3, 0.5],
	[&"block", 0, 0.3, 0.8], [&"idle", 0, 0.3, 0.4],
	[&"dodge", -1, 0.3, 0.6], [&"dodge", 1, 0.3, 0.6],
	[&"death", 0, 0.3, 1.6], [&"idle", 0, 0.3, 0.6],
	[&"victory", 0, 0.3, 1.5],
]

var rig: FighterVisual
var ref: FighterVisual
var ph: PlaceholderVisual
var fails: Array = []
var _parent: Node3D


func _init(parent: Node3D) -> void:
	_parent = parent


func _say(s: String) -> void:
	print("RIGCHECK " + s)


func _fail(s: String) -> void:
	fails.append(s)
	_say("FAIL " + s)


func _make(cfg: Dictionary, pos: Vector3) -> FighterVisual:
	var v: FighterVisual = RigVisual.new()
	v.set("manual_clock", true)
	_parent.add_child(v)
	v.position = pos
	v.configure(cfg)
	return v


func _pose_of(v: FighterVisual) -> Array:
	var out: Array = []
	for b in BONES:
		out.append(v.call("debug_bone", b))
	out.append(v.call("debug_tip"))
	return out


func _dist(a: Array, b: Array) -> float:
	var m := 0.0
	for i in a.size():
		m = maxf(m, (a[i] as Vector3).distance_to(b[i]))
	return m


func _ref_pose(key: Dictionary, t: float) -> Array:
	var ct: float = key.t
	if key.get("moving", false):
		var len_: float = RigVisual.library().get_animation(key.clip).length
		ct = fposmod(key.t + key.get("speed", 1.0) * t, len_)
	ref.call("debug_pose", key.clip, ct, key.get("yaw", 0.0))
	return _pose_of(ref)


## Play one action and step until past its key time. Returns {t_key, dmin, at, pose_at_end}.
func _measure(action: StringName, dir: int, dur: float, until: float, tweens: Array = []) -> Dictionary:
	rig.play(action, dir, dur)
	var key: Dictionary = rig.call("debug_key").duplicate()
	var at: float = key.at
	var horizon := maxf(until, at + 0.1)
	var t := 0.0
	var best := INF
	var samples: Array = []
	var static_ref: Array = [] if key.get("moving", false) else _ref_pose(key, 0.0)
	while t < horizon - 1e-6:
		var step := DT
		if t < at and t + step > at:
			step = at - t
		if step < 1e-6:
			step = DT
		rig.call("tick", step)
		for tw in tweens:
			if (tw as Tween).is_valid():
				(tw as Tween).custom_step(step)
		t += step
		var r: Array = static_ref if not static_ref.is_empty() else _ref_pose(key, t)
		var d := _dist(_pose_of(rig), r)
		samples.append([t, d])
		best = minf(best, d)
	var t_key := -1.0
	for s in samples:
		if s[1] <= best + 0.0005:
			t_key = s[0]
			break
	return {"key": key, "t_key": t_key, "dmin": best, "at": at, "end": _pose_of(rig)}


func _check_timing(label: String, m: Dictionary) -> void:
	var err: float = m.t_key - m.at
	# A looping clip (idle, block) is a moving target: arriving early (already in it) is fine.
	var ok: bool = (absf(err) <= TOL_T or m.key.get("moving", false) and err < 0.0) and m.dmin < 0.01
	_say("action %-16s clip=%s key_t=%.3f want=%.3f got=%.3f err=%+.3f dmin=%.4f %s" % [label, m.key.clip, m.key.t, m.at, m.t_key, err, m.dmin, "ok" if ok else "BAD"])
	if not ok:
		_fail("%s key pose at %.3f s, wanted %.3f (dmin %.4f)" % [label, m.t_key, m.at, m.dmin])


func run() -> bool:
	var cfg := {"style": "hero", "shield": true}
	rig = _make(cfg, Vector3.ZERO)
	ref = _make(cfg, Vector3(0, -50, 0))
	ref.visible = false
	ph = PlaceholderVisual.new()
	ph.has_shield = true
	_parent.add_child(ph)
	ph.configure({"style": "hero"})
	ph.position = Vector3.ZERO
	ph.visible = false
	var t0 := Time.get_ticks_msec()

	# 1. Every action of the sequence, timed against its key pose; the four windups held to the end.
	var windup_end := {}
	var clash := 0.0
	for i in SEQUENCE.size():
		var s: Array = SEQUENCE[i]
		var label := "%s(%d,%.2f)" % [s[0], s[1], s[2]]
		var m := _measure(s[0], s[1], s[2], s[3])
		_check_timing(label, m)
		if s[0] == &"windup":
			# still in the key pose when the duel strikes (end of the windup, or of the feint's resume)
			var held := _dist(m.end, _ref_pose(m.key, 0.0))
			windup_end[s[1]] = [rig.call("debug_bone", "hand.r"), rig.call("debug_tip")]
			if s[3] >= s[2] - 1e-3:
				_say("windup %d held at %.2f s: pose error %.4f" % [s[1], s[2], held])
				if held > 0.004:
					_fail("windup %d not held at the strike (%.4f)" % [s[1], held])
		ph.play(s[0], s[1], s[2])
		clash = maxf(clash, rig.get_clash_point().distance_to(ph.get_clash_point()))

	# 2. Windup directions: weapon hand and tip at the end of each windup, in the fighter's frame
	# (x > 0 is the fighter's right; the enemy faces the player, so that is the player's screen left).
	var names := {0: "LEFT", 1: "RIGHT", 2: "OVER", 3: "THRUST"}
	var mind := INF
	var mint := INF
	for a in windup_end:
		_say("windup_pose %-6s hand=(%.2f, %.2f, %.2f) tip=(%.2f, %.2f, %.2f)" % [names[a], windup_end[a][0].x, windup_end[a][0].y, windup_end[a][0].z, windup_end[a][1].x, windup_end[a][1].y, windup_end[a][1].z])
		for b in windup_end:
			if b > a:
				mind = minf(mind, (windup_end[a][0] as Vector3).distance_to(windup_end[b][0]))
				mint = minf(mint, (windup_end[a][1] as Vector3).distance_to(windup_end[b][1]))
	_say("windup_distinct min_hand_pair=%.3f min_tip_pair=%.3f" % [mind, mint])
	if windup_end.size() != 4 or mind < 0.25:
		_fail("windup hand positions too close (min %.3f u)" % mind)

	# 3. get_clash_point() against PlaceholderVisual at the same place and scale.
	for sc in [1.0, 1.45]:
		rig.configure({"style": "hero", "shield": true, "scale": sc})
		ph.configure({"style": "hero", "scale": sc})
		rig.position = Vector3(1.2, 0.3, -2.5)
		ph.position = rig.position
		clash = maxf(clash, rig.get_clash_point().distance_to(ph.get_clash_point()))
	rig.configure(cfg)
	rig.position = Vector3.ZERO
	_say("clash_point max_distance=%.4f" % clash)
	if clash > 0.3:
		_fail("clash point %.3f u from PlaceholderVisual" % clash)

	# 4. Unknown actions change nothing.
	rig.play(&"windup", 2, 1.0)
	rig.call("tick", 0.3)
	var before: Dictionary = rig.call("debug_state")
	var pose0 := _pose_of(rig)
	rig.play(&"no_such_action", 1, 0.5)
	rig.play(&"recover_typo", -1, 0.1)
	var after: Dictionary = rig.call("debug_state")
	var same: bool = before.action == after.action and before.clip == after.clip and absf(before.pos - after.pos) < 1e-6 and _dist(pose0, _pose_of(rig)) < 1e-5
	_say("unknown_action ignored=%s" % same)
	if not same:
		_fail("an unknown action changed the visual: %s -> %s" % [before, after])

	# 5. Reparent mid-windup (new parent turned and moved), then tween position and yaw through a strike.
	rig.play(&"idle")
	rig.call("tick", 0.5)
	rig.play(&"windup", 1, 1.0)
	rig.call("tick", 0.3)
	var holder := Node3D.new()
	_parent.add_child(holder)
	holder.position = Vector3(3, 0.5, -1)
	holder.rotation.y = 0.7
	rig.reparent(holder, true)
	var m2 := _measure_rest(0.3)
	_check_timing("reparent+windup", m2)
	var tw := rig.create_tween().set_parallel(true)
	tw.tween_property(rig, "position", rig.position + Vector3(1.0, 0, -0.4), 0.3)
	tw.tween_property(rig, "rotation:y", rig.rotation.y + 0.5, 0.3)
	tw.pause()
	var g0: Vector3 = rig.global_position
	var m3 := _measure(&"strike", 1, 0.1, 0.4, [tw])
	_check_timing("tween+strike", m3)
	var moved: float = rig.global_position.distance_to(g0)
	_say("tween moved=%.2f u (pose measured in the fighter's frame)" % moved)
	if moved < 0.9:
		_fail("position tween did not run (%.2f)" % moved)
	rig.reparent(_parent, false)
	rig.position = Vector3.ZERO
	rig.rotation = Vector3.ZERO
	holder.queue_free()

	# 6. A MeshKit blade on handslot.r follows the hand through a swing.
	var mk := _make({"style": "hero", "gear": {"sword": "meshkit"}}, Vector3(4, 0, 0))
	mk.play(&"slash", 1, 0.35)
	var dmin := INF
	var dmax := 0.0
	var path := 0.0
	var lag := 0.0
	mk.call("debug_sync_attachments")
	var prev: Vector3 = mk.call("debug_tip_global")
	var blade: Node3D = mk.find_child("MeshKitBlade", true, false)
	var tip_local: Vector3 = (blade.get_child(0) as Node3D).position + Vector3(0, 1.2, 0)
	for k in 120:
		mk.call("tick", DT)
		mk.call("debug_sync_attachments")
		var tip: Vector3 = blade.global_transform * tip_local  # the attached node itself
		var hand: Vector3 = mk.to_global(mk.call("debug_bone", "handslot.r"))
		var dd := tip.distance_to(hand)
		lag = maxf(lag, tip.distance_to(mk.call("debug_tip_global")))
		dmin = minf(dmin, dd)
		dmax = maxf(dmax, dd)
		path += tip.distance_to(prev)
		prev = tip
	_say("meshkit_blade tip_to_handslot min=%.4f max=%.4f tip_path=%.2f u node_vs_bone=%.4f" % [dmin, dmax, path, lag])
	if dmax - dmin > 0.002 or path < 1.0:
		_fail("MeshKit blade does not follow the hand (spread %.4f, path %.2f)" % [dmax - dmin, path])
	mk.queue_free()

	_say("done ok=%s fails=%d actions=%d secs=%.1f" % [fails.is_empty(), fails.size(), SEQUENCE.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	return fails.is_empty()


## After a reparent part-way through a windup: step to the end of the same windup and time its key.
func _measure_rest(already: float) -> Dictionary:
	var key: Dictionary = rig.call("debug_key").duplicate()
	var at: float = key.at - already
	var static_ref := _ref_pose(key, 0.0)
	var t := 0.0
	var best := INF
	var samples: Array = []
	while t < at + 0.2:
		var step := DT
		if t < at and t + step > at:
			step = at - t
		if step < 1e-6:
			step = DT
		rig.call("tick", step)
		t += step
		var d := _dist(_pose_of(rig), static_ref)
		samples.append([t, d])
		best = minf(best, d)
	var t_key := -1.0
	for s in samples:
		if s[1] <= best + 0.0005:
			t_key = s[0]
			break
	return {"key": key, "t_key": t_key, "dmin": best, "at": at, "end": _pose_of(rig)}
