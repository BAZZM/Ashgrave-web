extends RefCounted
## Debug only (--looktest=rig-check, check.js `rig`): drives one RigVisual through every
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
	[&"guard", 0, 0.3, 0.3], [&"idle", 0, 0.3, 0.4],
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
## Counts taken before the first rig, before the 20 rebuilds, and the texture budget of the first two rigs.
var base: Dictionary = {}
var before_rebuilds: Dictionary = {}
const TEX_BUDGET := 1048576  # docs/RIG_PLAN.md section 6 row R1: two rigs add at most 1 MB of texture


func _init(parent: Node3D) -> void:
	_parent = parent


## What a leak would move: objects, resources, nodes, orphan nodes, texture and video memory. (MEMORY_STATIC reads 0 in the
## web export, so it cannot show a leak.)
static func snap() -> Dictionary:
	return {
		"obj": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"res": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orph": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"tex": int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)),
		"vid": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
	}


static func delta(a: Dictionary, b: Dictionary) -> Dictionary:
	var d := {}
	for k in a:
		d[k] = int(a[k]) - int(b[k])
	return d


static func fmt(d: Dictionary) -> String:
	return "objects=%+d resources=%+d nodes=%+d orphans=%+d tex=%+d B vid=%+d B" % [d.obj, d.res, d.nodes, d.orph, d.tex, d.vid]


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
	ph = PlaceholderVisual.new()
	ph.has_shield = true
	_parent.add_child(ph)
	ph.configure({"style": "hero"})
	ph.position = Vector3.ZERO
	ph.visible = false
	base = snap()
	rig = _make(cfg, Vector3.ZERO)
	var one := delta(snap(), base)
	ref = _make(cfg, Vector3(0, -50, 0))
	ref.visible = false
	var two := delta(snap(), base)
	_say("budget first_rig %s | two_rigs tex=%+d B (budget %d B) vid=%+d B" % [fmt(one), two.tex, TEX_BUDGET, two.vid])
	if two.tex > TEX_BUDGET:
		_fail("two rigs add %d B of texture (plan budget %d B)" % [two.tex, TEX_BUDGET])
	if one.tex <= 0:
		_fail("the first rig added no texture: the monitor does not measure (tex %d)" % one.tex)
	var t0 := Time.get_ticks_msec()

	# 1. Every action of the sequence, timed against its key pose; the four windups held to the end.
	var windup_end := {}
	var clash := 0.0
	for i in SEQUENCE.size():
		var s: Array = SEQUENCE[i]
		var label := "%s(%d,%.2f)" % [s[0], s[1], s[2]]
		var m := _measure(s[0], s[1], s[2], s[3])
		_check_timing(label, m)
		if s[0] == &"strike":
			# Plan section 3: contact (the end of S) 0.05 +- 0.02 s after the call, whatever `duration` is.
			var c_ok: bool = absf(m.t_key - 0.05) <= 0.02
			_say("contact %s at %.3f s after strike (want 0.05 +- 0.02) %s" % [label, m.t_key, "ok" if c_ok else "BAD"])
			if not c_ok:
				_fail("%s contact at %.3f s" % [label, m.t_key])
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

	_say("dbg1 " + fmt(delta(snap(), base)))
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
	# Tip side per direction as the player sees a foe facing them: the fighter's +x is the player's screen
	# left. LEFT: tip to screen left; RIGHT: screen right; OVER: above the head; THRUST: near the middle.
	if windup_end.size() == 4:
		var head_y: float = rig.call("debug_bone", "head").y
		var tl: Vector3 = windup_end[0][1]
		var tr: Vector3 = windup_end[1][1]
		var to: Vector3 = windup_end[2][1]
		var tt: Vector3 = windup_end[3][1]
		var side := {"LEFT": tl.x > 0.3, "RIGHT": tr.x < -0.3, "OVER": to.y > head_y + 0.2, "THRUST": tt.z < windup_end[3][0].z - 0.5 and absf(tt.x) < 0.7}
		_say("windup_side screen LEFT=%s (x %.2f) RIGHT=%s (x %.2f) OVER=%s (tip y %.2f, head %.2f) THRUST=%s (x %.2f, z %.2f: point toward the player)" % [
			side.LEFT, tl.x, side.RIGHT, tr.x, side.OVER, to.y, head_y, side.THRUST, tt.x, tt.z])
		for k in side:
			if not side[k]:
				_fail("windup %s tip on the wrong side" % k)
	if windup_end.size() != 4 or mind < 0.25:
		_fail("windup hand positions too close (min %.3f u)" % mind)

	# 3. get_clash_point() against PlaceholderVisual at the same place and scale.
	# (a fresh one: reconfiguring the one that played would free parts its own tweens still target)
	ph.free()
	ph = PlaceholderVisual.new()
	ph.has_shield = true
	_parent.add_child(ph)
	ph.visible = false
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

	_say("dbg3 " + fmt(delta(snap(), base)))
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
	holder.free()

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
	mk.free()

	# 7. Skeleton_Blade (KayKit skeleton gear from its own file) on handslot.r of the skeleton warrior.
	var sb := _make({"style": "skeleton"}, Vector3(-4, 0, 0))
	sb.play(&"slash", 1, 0.35)
	var sb_node: Node3D = sb.find_child("Skeleton_Blade", true, false)
	var sb_spread := [INF, 0.0]
	var sb_path := 0.0
	sb.call("debug_sync_attachments")
	var sb_prev: Vector3 = sb.call("debug_tip_global")
	for k in 120:
		sb.call("tick", DT)
		sb.call("debug_sync_attachments")
		var tip2: Vector3 = sb_node.to_global((sb_node.get_child(1) as Node3D).position) if sb_node != null else Vector3.ZERO
		var hand2: Vector3 = sb.to_global(sb.call("debug_bone", "handslot.r"))
		sb_spread[0] = minf(sb_spread[0], tip2.distance_to(hand2))
		sb_spread[1] = maxf(sb_spread[1], tip2.distance_to(hand2))
		sb_path += tip2.distance_to(sb_prev)
		sb_prev = tip2
	_say("skeleton_blade attached=%s tip_to_handslot min=%.4f max=%.4f tip_path=%.2f u" % [sb_node != null, sb_spread[0], sb_spread[1], sb_path])
	if sb_node == null or sb_spread[1] - sb_spread[0] > 0.002 or sb_path < 1.0:
		_fail("Skeleton_Blade does not follow the hand")

	# 8. The bases agree: knight and skeleton warrior posed from the same clip times put every deform bone
	# within 1 mm (toe bones and the IK/control helpers excluded: the plan found the toes differ).
	var kn: FighterVisual = _make({"style": "hero"}, Vector3(0, 0, 10))
	sb.position = Vector3(0, 0, 10)
	sb.rotation = Vector3.ZERO
	var sk: Skeleton3D = kn.find_children("*", "Skeleton3D", true, false)[0]
	var sk2: Skeleton3D = sb.find_children("*", "Skeleton3D", true, false)[0]
	var worst := 0.0
	var worst_bone := ""
	var n_bones := 0
	for clip in [Clips.IDLE, Clips.SLICE, Clips.CHOP, Clips.STAB, Clips.WALK, Clips.DEATH, Clips.HIT_HEAVY]:
		var len3: float = RigVisual.library().get_animation(clip).length
		for f in [0.0, 0.3, 0.6, 0.9]:
			kn.call("debug_pose", clip, len3 * f)
			sb.call("debug_pose", clip, len3 * f)
			n_bones = 0
			for bi in sk.get_bone_count():
				var bn := sk.get_bone_name(bi)
				if bn.begins_with("toes") or "IK" in bn or bn.begins_with("control") or sk2.find_bone(bn) < 0:
					continue
				n_bones += 1
				var d3: float = (kn.call("debug_bone", bn) as Vector3).distance_to(sb.call("debug_bone", bn))
				if d3 > worst:
					worst = d3
					worst_bone = "%s %s@%.2f" % [bn, clip, len3 * f]
	_say("bases_agree knight_vs_skeleton_warrior bones=%d worst=%.5f m (%s)" % [n_bones, worst, worst_bone])
	if worst > 0.001:
		_fail("bases disagree by %.4f m at %s" % [worst, worst_bone])
	sb.free()
	kn.free()

	_say("dbg8 " + fmt(delta(snap(), base)))
	# 9. The static caches: rebuilding and creating rigs loads nothing again, and nothing leaks (objects, resources, nodes,
	# orphan nodes, texture and video memory; compared again by final() once the freed nodes are gone).
	var loads0: int = RigVisual.loads
	before_rebuilds = snap()
	for k in 20:
		rig.configure({"style": "skeleton" if k % 2 else "hero", "shield": true})
		var tmp := _make({"style": "knight", "shield": true}, Vector3(8, 0, 0))
		tmp.free()
	rig.configure(cfg)
	_say("caches loads_before=%d loads_after=%d (20 rebuilds, 20 new rigs)" % [loads0, RigVisual.loads])
	if RigVisual.loads != loads0:
		_fail("a rig resource was loaded again (%d -> %d)" % [loads0, RigVisual.loads])

	# 10. A slash (a gather swing) or a strike chain that runs out, then walking: the legs must walk (the chain's end
	# returns the visual to idle; before the fix _action stayed on slash and the hero glided).
	for chain in [[&"slash", 1, 0.35], [&"strike", 1, 0.1], [&"hit", 1, 0.12], [&"recover", 0, 0.3]]:
		rig.play(&"idle")
		rig.call("tick", 0.4)
		rig.play(chain[0], chain[1], chain[2])
		for k in 240:
			rig.call("tick", DT)  # one second
		rig.set_walk(0.2)
		rig.set_pace(1.0)
		for k in 24:
			rig.call("tick", DT)
		var st: Dictionary = rig.call("debug_state")
		var walks: bool = str(st.clip) == str(Clips.WALK)
		_say("walk_after %s clip=%s action=%s %s" % [chain[0], st.clip, st.action, "ok" if walks else "BAD"])
		if not walks:
			_fail("walking after %s plays %s, not %s (action %s)" % [chain[0], st.clip, Clips.WALK, st.action])
		rig.set_walk(0.0)
	rig.play(&"idle")

	# 11. The counts, with no frame in between (the freeing is immediate, and the world around the look test builds its chunks
	# frame by frame, so nothing else moves while this runs).
	leak_after_rebuilds()
	gait()
	leak_after_release()
	_say("done ok=%s fails=%d actions=%d secs=%.1f" % [fails.is_empty(), fails.size(), SEQUENCE.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	return fails.is_empty()


## The counts must be what they were before the 20 rebuilds and 20 extra rigs. Returns whether they are.
func leak_after_rebuilds() -> bool:
	var d := delta(snap(), before_rebuilds)
	_say("leak_after_rebuilds %s (20 rebuilds + 20 rigs made and freed)" % fmt(d))
	var ok: bool = absi(d.obj) <= 8 and absi(d.res) <= 8 and absi(d.nodes) <= 2 and d.orph <= 0 and absi(d.tex) <= 4096 and absi(d.vid) <= 65536
	if not ok:
		_fail("rebuilds leak: %s" % fmt(d))
	return ok


## The Safe path: free every rig and call RigVisual.release() (what quality Safe does), then build one rig, free it and release
## again. That whole cycle must leave the counts exactly as it found them (objects, resources, nodes, orphan nodes, texture and
## video memory): a Safe session holds no rig resource. Against the counts from before the first rig, resources and texture
## memory must also be back (the objects and nodes of the other fighters in this scene differ, so those are not compared).
func leak_after_release() -> bool:
	for v in [rig, ref]:
		if is_instance_valid(v):
			v.free()
	RigVisual.release()
	var a := snap()
	var v1: FighterVisual = _make({"style": "hero", "shield": true}, Vector3(2, 0, 0))
	var b := snap()
	v1.free()
	RigVisual.release()
	var c := snap()
	var d := delta(c, a)
	var vs_base := delta(c, base)
	_say("leak_after_release load=%s | after free+release %s | against the start: resources=%+d tex=%+d B" % [fmt(delta(b, a)), fmt(d), vs_base.res, vs_base.tex])
	var ok: bool = absi(d.obj) <= 2 and d.res == 0 and d.nodes == 0 and d.orph == 0 and absi(d.tex) <= 4096 and absi(d.vid) <= 65536 and vs_base.res <= 0 and vs_base.tex <= 4096
	if not ok:
		_fail("release leaves rig memory: %s" % fmt(d))
	return ok


## Natural ground speed of a locomotion clip: in the character's frame the planted (lower) foot moves back at the speed the
## ground would move under it. Returns the median over the samples where a foot is planted.
func natural_speed(clip: StringName) -> float:
	var v: FighterVisual = _make({"style": "hero"}, Vector3(0, 0, 30))
	var len_: float = RigVisual.library().get_animation(clip).length
	var n := 240
	var prev := Vector2.ZERO
	var zs: Array = []
	var ys: Array = []
	for i in n + 1:
		v.call("debug_pose", clip, len_ * float(i) / n)
		var l: Vector3 = v.call("debug_bone", "foot.l")
		var r: Vector3 = v.call("debug_bone", "foot.r")
		zs.append([l.z, r.z])
		ys.append([l.y, r.y])
	var vs: Array = []
	var ymin := 9.0
	for y in ys:
		ymin = minf(ymin, minf(y[0], y[1]))
	for i in n:
		var side := 0 if ys[i][0] < ys[i][1] else 1
		if ys[i][side] < ymin + 0.06 and ys[i + 1][side] < ymin + 0.06:
			vs.append((zs[i + 1][side] - zs[i][side]) / (len_ / n))
	vs.sort()
	var zmin := 9.0
	var zmax := -9.0
	var ylo := 9.0
	var yhi := -9.0
	for i in n + 1:
		zmin = minf(zmin, zs[i][0])
		zmax = maxf(zmax, zs[i][0])
		ylo = minf(ylo, ys[i][0])
		yhi = maxf(yhi, ys[i][0])
	_say("gait_clip %s length=%.3f s foot.l z %.3f..%.3f (stride %.3f) y %.3f..%.3f planted_samples=%d" % [clip, len_, zmin, zmax, zmax - zmin, ylo, yhi, vs.size()])
	v.free()
	return float(vs[vs.size() / 2]) if not vs.is_empty() else 0.0


## Foot slide through the real locomotion path: a rig moved at `speed` along its forward (-Z) with set_walk and set_pace as the
## overworld mover gives them; the lower foot's world speed while it is planted is the slide. Returns [mean, p95] in u/s.
func slide_at(speed: float) -> Array:
	var v: FighterVisual = _make({"style": "hero"}, Vector3(0, 0, 40))
	v.set("manual_clock", true)
	var dt := 1.0 / 60.0
	var w := clampf(speed / 5.5, 0.0, 1.0)
	var pace := maxf(speed / 5.5, 1.0)
	var prev := [Vector3.ZERO, Vector3.ZERO]
	var vs: Array = []
	var ymin := 9.0
	var samples: Array = []
	for i in 60 + 240:
		v.position += Vector3(0, 0, -speed * dt)
		v.set_walk(w)
		v.set_pace(pace)
		v.call("tick", dt)
		var l: Vector3 = v.to_global(v.call("debug_bone", "foot.l"))
		var r: Vector3 = v.to_global(v.call("debug_bone", "foot.r"))
		if i >= 60:
			samples.append([l, r])
			ymin = minf(ymin, minf(l.y, r.y))
	for i in samples.size() - 1:
		var side := 0 if samples[i][0].y < samples[i][1].y else 1
		if samples[i][side].y < ymin + 0.03 and samples[i + 1][side].y < ymin + 0.03:
			var d: Vector3 = samples[i + 1][side] - samples[i][side]
			vs.append(Vector2(d.x, d.z).length() / dt)
	vs.sort()
	var clip: String = str(v.call("debug_state").clip)
	v.free()
	var mean := 0.0
	for x in vs:
		mean += x
	mean /= maxf(vs.size(), 1)
	_say("gait speed=%.1f clip=%s planted=%d slide_mean=%.2f u/s (%.0f%% of speed) slide_p95=%.2f" % [speed, clip, vs.size(), mean, 100.0 * mean / speed, vs[int(vs.size() * 0.95)] if not vs.is_empty() else -1.0])
	return [mean, vs[int(vs.size() * 0.95)] if not vs.is_empty() else 99.0, speed]


func gait() -> bool:
	_say("natural walk=%.3f run=%.3f u/s (rig_clips.gd WALK_NATURAL, RUN_NATURAL)" % [natural_speed(Clips.WALK), natural_speed(Clips.RUN)])
	for sp in [1.0, 2.0, 5.5, 9.5, 12.5]:
		var r := slide_at(sp)
		# The run clip (from 1.5 u/s up) keeps its planted foot within 15% of the speed; the walk clip (slower than that, where
		# nobody looks) slides more because its ankle rolls while planted.
		if r[0] > (0.15 if sp >= 2.0 else 0.6) * sp:
			_fail("feet slide %.2f u/s at speed %.1f" % [r[0], sp])
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
