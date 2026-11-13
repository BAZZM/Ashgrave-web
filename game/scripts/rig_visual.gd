extends FighterVisual
## A fighter built on KayKit's shared 41-joint skeleton (docs/RIG_PLAN.md, stage R1).
## Same contract as PlaceholderVisual (fighter_visual.gd): the duel code decides everything and
## calls play() with its own durations; this only shows it, landing each key pose when asked.
## Nothing in the game creates one yet: only the --looktest=rig debug scene does. No class_name:
## load with preload("res://scripts/rig_visual.gd").
##
## Shared by every instance: the AnimationLibrary (anims.glb, loaded once), the atlas, the shader and
## its one ShaderMaterial. Per instance: instance uniforms (tint, flash, tell), the skeleton and its
## AnimationPlayer, which runs in manual mode and is advanced by tick() from _process.

const Clips := preload("res://scripts/rig_clips.gd")
const DIR := "res://assets/rig/"
const TIP_1H := 1.41  # 1H_Sword: tip along its bone's +Y (mesh AABB end)

## Style -> base character and gear. The `gear` key of configure() overrides any of these.
const LOOKS := {
	"hero": {"base": "knight", "sword": "1H_Sword", "shield": "Badge_Shield", "helmet": true, "cape": true},
	"knight": {"base": "knight", "sword": "1H_Sword", "shield": "Rectangle_Shield", "helmet": true, "cape": false},
	"sentinel": {"base": "knight", "sword": "1H_Sword", "shield": "Rectangle_Shield", "helmet": true, "cape": true},
	"duelist": {"base": "knight", "sword": "1H_Sword", "shield": "", "helmet": false, "cape": false},
	"brute": {"base": "skeleton_warrior", "sword": "meshkit", "shield": "", "helmet": true, "cape": false},
	"boss": {"base": "knight", "sword": "2H_Sword", "shield": "Spike_Shield", "helmet": true, "cape": true},
}
const SHIELDS := ["Badge_Shield", "Rectangle_Shield", "Round_Shield", "Spike_Shield"]
const SWORDS := ["1H_Sword", "2H_Sword"]
const HELMETS := ["Knight_Helmet", "Skeleton_Warrior_Helmet"]
const CHEST_YAW := 20.0
const HIT_YAW := 16.0

const SHADER := "
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D atlas : source_color, filter_linear, repeat_disable;
uniform float rim_amount = 0.25;
instance uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
instance uniform vec4 flash : source_color = vec4(0.0, 0.0, 0.0, 1.0);
instance uniform vec4 tell : source_color = vec4(0.0, 0.0, 0.0, 1.0);
void fragment() {
	vec3 c = texture(atlas, UV).rgb;
	float hi = max(c.r, max(c.g, c.b));
	float sat = (hi - min(c.r, min(c.g, c.b))) / max(hi, 0.001);
	float metal = 1.0 - smoothstep(0.12, 0.3, sat);
	ALBEDO = mix(c, c * tint.rgb, metal);
	METALLIC = metal * 0.55;
	ROUGHNESS = mix(0.85, 0.45, metal);
	EMISSION = flash.rgb + tell.rgb * 2.5;
	RIM = rim_amount;
	RIM_TINT = 0.4;
}
"

static var _lib: AnimationLibrary
static var _mat: ShaderMaterial
static var _bases := {}

@export var has_shield := false
var style := "hero"
var body_color := Color(0.5, 0.53, 0.6)
var accent_color := Color(0.85, 0.35, 0.12)
## Debug (look test, rig-contract check): when true, _process does not advance; the caller calls tick().
var manual_clock := false

var _over := {}
var _gear := {}
var _head_scale := 1.0
var _rig: Node3D
var _sk: Skeleton3D
var _ap: AnimationPlayer
var _skinned: Array[GeometryInstance3D] = []
var _rigid: Array[GeometryInstance3D] = []
var _weapon: GeometryInstance3D
var _tip: Node3D
var _head_bone := -1
var _chest_bone := -1
var _hand_bone := -1
var _segs: Array = []
var _seg: Dictionary = {}
var _seg_left := 0.0
var _action := &"idle"
var _key := {}
var _since := 0.0
var _yaw_from := 0.0
var _yaw_to := 0.0
var _yaw_t := 0.0
var _yaw_dur := 0.0
var _yaw_back := -1.0
var _walk := 0.0
var _pace := 1.0
var _loco := &""
var _flash_tw: Tween
var _tell_tw: Tween
var _trail: MultiMeshInstance3D
var _trail_mm: MultiMesh
var _trail_pts: Array = []
var _trail_time := 0.0
var _trail_color := Color(1, 0.9, 0.7)


static func library() -> AnimationLibrary:
	if _lib == null:
		var src: Node = (load(DIR + "anims.glb") as PackedScene).instantiate()
		_lib = (src.find_children("*", "AnimationPlayer")[0] as AnimationPlayer).get_animation_library("")
		src.free()
		for n in _lib.get_animation_list():
			_lib.get_animation(n).loop_mode = Animation.LOOP_LINEAR if StringName(n) in Clips.LOOPS else Animation.LOOP_NONE
	return _lib


static func material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		_mat.set_shader_parameter("atlas", load(DIR + "atlas.png"))
	return _mat


static func _base(name_: String) -> PackedScene:
	if not _bases.has(name_):
		_bases[name_] = load(DIR + name_ + ".glb")
	return _bases[name_]


func _ready() -> void:
	_build()


func configure(cfg: Dictionary) -> void:
	style = cfg.get("style", style)
	body_color = cfg.get("body", body_color)
	accent_color = cfg.get("accent", accent_color)
	_over = cfg.get("over", {})
	has_shield = cfg.get("shield", has_shield)
	_gear = cfg.get("gear", {})
	_head_scale = cfg.get("head", _head_scale)
	var s: float = cfg.get("scale", absf(scale.y))
	scale = Vector3(signf(scale.x) * s, s, signf(scale.z) * s)
	if is_inside_tree():
		_build()


func _look() -> Dictionary:
	var look: Dictionary = (LOOKS.get(style, LOOKS.hero) as Dictionary).duplicate()
	look.merge(_gear, true)
	if not has_shield and not _gear.has("shield"):
		look.shield = ""
	return look


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_skinned.clear()
	_rigid.clear()
	_trail_pts.clear()
	_weapon = null
	var look := _look()
	_rig = _base(look.base).instantiate()
	_rig.rotation.y = PI  # glTF faces +Z; fighters face -Z
	add_child(_rig)
	_sk = _rig.find_children("*", "Skeleton3D")[0]
	var rig_node := _sk.get_parent()
	for c in rig_node.get_children():
		if c != _sk and c.get_child_count() == 0 and not (c is MeshInstance3D):
			c.free()  # the body parts the pack tool merged leave empty nodes
	var mat := material()
	for n in _sk.get_children():
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			mi.material_override = mat
			_skinned.append(mi)
		elif n is BoneAttachment3D:
			var att := n as BoneAttachment3D
			var mi2 := att.get_child(0) as MeshInstance3D
			var keep := false
			if att.name in SWORDS:
				keep = look.sword == att.name
			elif att.name in SHIELDS:
				keep = look.shield == att.name
			elif att.name in HELMETS:
				keep = look.helmet
			elif att.name == "Knight_Cape":
				keep = look.cape
			if not keep:
				att.free()
				continue
			mi2.material_override = mat
			mi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if att.name == "Knight_Cape" else mi2.cast_shadow
			_rigid.append(mi2)
			if att.name in SWORDS:
				_weapon = mi2
				_tip = Node3D.new()
				_tip.position = Vector3(0, TIP_1H * (1.25 if att.name == "2H_Sword" else 1.0), 0)
				att.add_child(_tip)
	if look.sword == "meshkit":
		_attach_blade(1.2, 0.1)
	_head_bone = _sk.find_bone("head")
	_chest_bone = _sk.find_bone("chest")
	_hand_bone = _sk.find_bone("hand.r")
	var tint := Color.WHITE.lerp(body_color.lightened(0.25), 0.6)
	for g in _skinned + _rigid:
		if g.material_override == mat:
			g.set_instance_shader_parameter("tint", tint)
	_ap = AnimationPlayer.new()
	_ap.name = "Anim"
	_rig.add_child(_ap)
	_ap.root_node = NodePath("..")
	_ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_ap.add_animation_library(&"", library())
	_build_trail()
	_segs.clear()
	_seg = {}
	_action = &""
	play(&"idle")
	tick(0.0)


## A non-KayKit weapon on the right-hand slot: a MeshKit blade on the 1H_Sword mount bone.
func _attach_blade(length: float, width: float) -> void:
	var att := BoneAttachment3D.new()
	att.name = "MeshKitBlade"
	att.bone_name = "1H_Sword"
	_sk.add_child(att)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.82, 0.84, 0.88)
	bm.metallic = 0.85
	bm.roughness = 0.25
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var blade := MeshInstance3D.new()
	blade.mesh = MeshKit.blade(length, width, 0.03 + width * 0.12, width * 2.2)
	blade.material_override = bm
	blade.position = Vector3(0, 0.12, 0)
	att.add_child(blade)
	var grip := MeshInstance3D.new()
	grip.mesh = MeshKit.lathe([[0.0, -0.17], [0.022, -0.16], [0.027, -0.02], [0.022, 0.1], [0.0, 0.11]], 8)
	grip.material_override = bm
	att.add_child(grip)
	_weapon = blade
	_tip = Node3D.new()
	_tip.position = Vector3(0, 0.12 + length, 0)
	att.add_child(_tip)


func _build_trail() -> void:
	_trail_mm = MultiMesh.new()
	_trail_mm.transform_format = MultiMesh.TRANSFORM_3D
	_trail_mm.use_colors = true
	_trail_mm.mesh = QuadMesh.new()
	_trail_mm.instance_count = 11
	_trail_mm.visible_instance_count = 0
	_trail = MultiMeshInstance3D.new()
	_trail.multimesh = _trail_mm
	_trail.top_level = true
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.vertex_color_use_as_albedo = true
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail.material_override = tm
	add_child(_trail)


func _process(delta: float) -> void:
	if not manual_clock and _ap != null:
		tick(delta)


# ---------------------------------------------------------------- playback

## One section of one clip: from `a` to `b` in clip seconds (b < a plays it backwards) at `speed`
## clip seconds per second. `hold` freezes on `a`; `loop` repeats the clip (a native loop).
func _seg_of(clip: StringName, a: float, b: float, speed: float, blend := -1.0) -> Dictionary:
	return {"clip": clip, "a": a, "b": b, "speed": maxf(speed, 0.001), "blend": blend, "hold": false, "loop": false}


func _hold_of(clip: StringName, t: float) -> Dictionary:
	return {"clip": clip, "a": t, "b": t, "speed": 0.0, "blend": 0.0, "hold": true, "loop": false}


func _loop_of(clip: StringName, rate: float, blend: float) -> Dictionary:
	return {"clip": clip, "a": 0.0, "b": 0.0, "speed": rate, "blend": blend, "hold": false, "loop": true}


func _run(segs: Array) -> void:
	_segs = segs
	_next()


func _next() -> void:
	if _segs.is_empty():
		if _seg.is_empty():
			return
		if _seg.get("repeat", false):
			_start(_seg)
			return
		_start(_hold_of(_seg.clip, _seg.b))
		return
	_start(_segs.pop_front())


func _start(s: Dictionary) -> void:
	_seg = s
	var blend: float = s.blend if s.blend >= 0.0 else Clips.BLEND
	if s.loop:
		_ap.play_section(s.clip, -1, -1, blend, s.speed)
		_seg_left = INF
	elif s.hold:
		_ap.play_section(s.clip, -1, -1, blend, 0.0)
		_ap.seek(s.a, false)
		_seg_left = INF
	else:
		var rev: bool = s.b < s.a
		_ap.play_section(s.clip, minf(s.a, s.b), maxf(s.a, s.b), blend, -s.speed if rev else s.speed, rev)
		_ap.seek(s.a, false)
		_seg_left = absf(s.b - s.a) / s.speed


## Advance by `dt` seconds: sections change exactly on their boundaries whatever the frame rate.
func tick(dt: float) -> void:
	if _ap == null:
		return
	_since += dt
	var left := dt
	for _guard in 16:
		if _seg_left > left:
			_ap.advance(left)
			_seg_left -= left
			break
		_ap.advance(_seg_left)
		left -= _seg_left
		_next()
	_locomotion()
	_offsets(dt)
	_update_trail(dt)


func _offsets(dt: float) -> void:
	_yaw_t += dt
	if _yaw_back >= 0.0 and _yaw_t >= _yaw_dur + _yaw_back:
		_yaw_from = _yaw_to
		_yaw_to = 0.0
		_yaw_t -= _yaw_dur + _yaw_back
		_yaw_dur = 0.25
		_yaw_back = -1.0
	var k := clampf(_yaw_t / _yaw_dur, 0.0, 1.0) if _yaw_dur > 0.0 else 1.0
	var yaw := lerpf(_yaw_from, _yaw_to, k)
	if absf(yaw) > 0.01:
		var q := _sk.get_bone_pose_rotation(_chest_bone)
		_sk.set_bone_pose_rotation(_chest_bone, Quaternion(Vector3.UP, deg_to_rad(yaw)) * q)
	if _head_scale != 1.0:
		_sk.set_bone_pose_scale(_head_bone, Vector3.ONE * _head_scale)


func _yaw(to: float, over: float, back := -1.0) -> void:
	_yaw_from = _yaw_now()
	_yaw_to = to
	_yaw_t = 0.0
	_yaw_dur = maxf(over, 0.001)
	_yaw_back = back


func _locomotion() -> void:
	var moving := _walk > 0.05 and _action == &"idle"
	var want: StringName = &""
	if moving:
		want = Clips.RUN if _pace >= 1.6 else Clips.WALK
	if want != _loco:
		_loco = want
		if want == &"":
			_ap.speed_scale = 1.0
			_start(_loop_of(Clips.IDLE, 1.0, 0.2))
		else:
			_start(_loop_of(want, 1.0, 0.2))
	if want == Clips.WALK:
		_ap.speed_scale = clampf(_walk * _pace * 1.6, 0.8, 2.2)
	elif want == Clips.RUN:
		_ap.speed_scale = clampf(_pace * 0.7, 1.0, 1.6)


# ---------------------------------------------------------------- the contract

func play(action: StringName, dir: int = 0, duration: float = 0.3) -> void:
	if _ap == null:
		return
	var known := true
	match action:
		&"idle", &"recover":
			var t := maxf(duration, 0.25)
			_yaw(0.0, t)
			_run([_loop_of(Clips.IDLE, 1.0, t)])
			_key = {"clip": Clips.IDLE, "t": 0.0, "at": t, "moving": true, "speed": 1.0}
		&"taunt":
			_one_shot(Clips.TAUNT, 0.0, Clips.KEY[&"taunt"], Clips.AT[&"taunt"], Clips.BLEND, false)
		&"windup":
			var at: Dictionary = Clips.ATTACK.get(dir, Clips.ATTACK[3])
			var w: Array = at.w
			var t2: float = duration * Clips.WINDUP_SHARE
			var sp := absf(w[1] - w[0]) / maxf(t2, 0.01)
			var yaw := 0.0
			if dir == AttackDef.Dir.LEFT:
				yaw = -CHEST_YAW
			elif dir == AttackDef.Dir.RIGHT:
				yaw = CHEST_YAW
			_yaw(yaw, t2)
			_run([_seg_of(at.clip, w[0], w[1], sp, Clips.BLEND_FAST if _from_attack() else Clips.BLEND)])
			_key = {"clip": at.clip, "t": w[1], "at": t2, "yaw": yaw}
		&"feint":
			var s := _seg.duplicate()
			var now := _ap.current_animation_position
			var sign_ := 1.0 if s.b >= s.a else -1.0
			var half := maxf(duration * 0.5, 0.01)
			var rest: Array = []
			rest.append(_seg_of(s.clip, now, now + Clips.FEINT_NUDGE * sign_, Clips.FEINT_NUDGE / half, 0.0))
			rest.append(_seg_of(s.clip, now + Clips.FEINT_NUDGE * sign_, now, Clips.FEINT_NUDGE / half, 0.0))
			if not s.hold and not s.loop and absf(s.b - now) > 0.0005:
				rest.append(_seg_of(s.clip, now, s.b, s.speed, 0.0))
			_run(rest)
			_key = {"clip": s.clip, "t": now + Clips.FEINT_NUDGE * sign_, "at": half, "yaw": _yaw_to}
			action = &"windup"  # the windup goes on after the feint
		&"strike":
			var at2: Dictionary = Clips.ATTACK.get(dir, Clips.ATTACK[3])
			var s2: Array = at2.s
			var r2: Array = at2.r
			var t3 := maxf(duration, 0.01)
			var cont: bool = _action == &"windup" and _seg.get("clip") == at2.clip
			var y0 := _yaw_now()
			_yaw(0.0, t3 + 0.2)
			_swing_trail(Color(1.0, 0.45, 0.2))
			_glow_tell(Color.BLACK, 0.3)
			_run([_seg_of(at2.clip, s2[0], s2[1], absf(s2[1] - s2[0]) / t3, 0.0 if cont else Clips.BLEND_FAST),
				_seg_of(at2.clip, r2[0], r2[1], 1.0, 0.0), _loop_of(Clips.IDLE, 1.0, 0.2)])
			_key = {"clip": at2.clip, "t": s2[1], "at": t3, "yaw": y0 * (1.0 - t3 / (t3 + 0.2))}
		&"slash":
			var d2: int = Clips.SLASH.get(dir, 1)
			var at3: Dictionary = Clips.ATTACK[d2]
			var s3: Array = at3.s
			var r3: Array = at3.r
			var t4 := maxf(duration, 0.01)
			_yaw(0.0, 0.1)
			_swing_trail(Color(1.0, 0.95, 0.8))
			_run([_seg_of(at3.clip, s3[0], s3[1], absf(s3[1] - s3[0]) / t4, Clips.BLEND_FAST),
				_seg_of(at3.clip, r3[0], r3[1], 1.4, 0.0), _loop_of(Clips.IDLE, 1.0, 0.2)])
			_key = {"clip": at3.clip, "t": s3[1], "at": t4, "yaw": 0.0}
		&"parry":
			var p := 1 if dir >= 0 else -1
			var t5: float = Clips.AT[&"parry"]
			_swing_trail(Color(1.0, 1.0, 0.9), 0.12)
			_yaw(0.0, 0.1)
			var a: float = 0.30 - t5 if p > 0 else 0.255
			var b: float = 0.30 if p > 0 else 0.20
			_run([_seg_of(Clips.SLICE, a, b, absf(b - a) / t5, Clips.BLEND_FAST), _timed_hold(Clips.SLICE, b, Clips.PARRY_HOLD),
				_loop_of(Clips.IDLE, 1.0, 0.15)])
			_key = {"clip": Clips.SLICE, "t": b, "at": t5, "yaw": 0.0}
		&"block":
			var t6: float = Clips.AT[&"block"]
			_yaw(0.0, t6)
			_run([_loop_of(Clips.BLOCKING, 1.0, t6)])
			_key = {"clip": Clips.BLOCKING, "t": 0.0, "at": t6, "moving": true, "speed": 1.0}
		&"guard":
			var k: float = Clips.KEY[&"guard"]
			var t7: float = Clips.AT[&"guard"]
			_yaw(0.0, t7)
			_run([_seg_of(Clips.BLOCK_HIT, 0.0, k, k / t7, Clips.BLEND_FAST), _seg_of(Clips.BLOCK_HIT, k, 0.35, 1.5, 0.0)])
			_key = {"clip": Clips.BLOCK_HIT, "t": k, "at": t7, "yaw": 0.0}
		&"hit":
			var k2: float = Clips.KEY[&"hit"]
			var t8 := maxf(duration, 0.01)
			var hy := HIT_YAW * (1.0 if dir >= 0 else -1.0)
			_yaw(hy, t8, 0.15)
			_run([_seg_of(Clips.HIT, 0.0, k2, k2 / t8, Clips.BLEND_FAST), _seg_of(Clips.HIT, k2, 0.667, 1.5, 0.0),
				_loop_of(Clips.IDLE, 1.0, 0.2)])
			_key = {"clip": Clips.HIT, "t": k2, "at": t8, "yaw": hy}
		&"stagger":
			_glow_tell(Color.BLACK, 0.1)
			_one_shot(Clips.HIT_HEAVY, 0.0, Clips.KEY[&"stagger"], Clips.AT[&"stagger"], Clips.BLEND_FAST, true)
		&"broken":
			_glow_tell(Color.BLACK, 0.1)
			_one_shot(Clips.PICKUP, 0.0, Clips.KEY[&"broken"], Clips.AT[&"broken"], Clips.BLEND, true)
		&"dodge":
			var clip := Clips.DODGE_R if dir > 0 else Clips.DODGE_L
			var sp2: float = 0.4 / Clips.DODGE_TIME
			_yaw(0.0, 0.1)
			_run([_seg_of(clip, 0.0, 0.4, sp2, Clips.BLEND_FAST), _loop_of(Clips.IDLE, 1.0, 0.15)])
			_key = {"clip": clip, "t": Clips.AT[&"dodge"] * sp2, "at": Clips.AT[&"dodge"], "yaw": 0.0}
		&"death":
			_glow_tell(Color.BLACK, 0.1)
			_one_shot(Clips.DEATH, 0.0, Clips.KEY[&"death"], Clips.AT[&"death"], Clips.BLEND, true)
		&"victory":
			_one_shot(Clips.CHEER, 0.0, Clips.KEY[&"victory"], Clips.AT[&"victory"], Clips.BLEND, true)
			var pump := _seg_of(Clips.CHEER, Clips.KEY[&"victory"], 1.0, 1.0, 0.0)
			pump.repeat = true
			_segs = [pump]
		_:
			known = false
	if known:
		_action = action
		_since = 0.0
		_loco = &""
		_ap.speed_scale = 1.0


func _timed_hold(clip: StringName, t: float, secs: float) -> Dictionary:
	return {"clip": clip, "a": t, "b": t + 0.0001, "speed": 0.0001 / secs, "blend": 0.0, "hold": false, "loop": false}


## Play `clip` from `from` so that clip time `key` lands `at` seconds from now; then hold there
## (`hold`) or play on at 1x and return to idle.
func _one_shot(clip: StringName, from: float, key: float, at: float, blend: float, hold: bool) -> void:
	_yaw(0.0, minf(at, 0.2))
	var segs: Array = [_seg_of(clip, from, key, absf(key - from) / maxf(at, 0.01), blend)]
	if not hold:
		var len_: float = library().get_animation(clip).length
		segs.append(_seg_of(clip, key, len_, 1.0, 0.0))
		segs.append(_loop_of(Clips.IDLE, 1.0, 0.25))
	_run(segs)
	_key = {"clip": clip, "t": key, "at": at, "yaw": 0.0}


func _from_attack() -> bool:
	return _action in [&"strike", &"slash", &"windup"]


func _yaw_now() -> float:
	var k := clampf(_yaw_t / _yaw_dur, 0.0, 1.0) if _yaw_dur > 0.0 else 1.0
	return lerpf(_yaw_from, _yaw_to, k)


func set_walk(amount: float) -> void:
	_walk = clampf(amount, 0.0, 1.0)


func set_pace(mult: float) -> void:
	_pace = clampf(mult, 1.0, 2.5)


func set_tell(color: Color, t: float) -> void:
	_glow_tell(color, t)


func _glow_tell(color: Color, t: float) -> void:
	if _weapon == null:
		return
	if _tell_tw:
		_tell_tw.kill()
	var from: Color = _weapon.get_instance_shader_parameter("tell") if _weapon.material_override == _mat else Color.BLACK
	if _weapon.material_override != _mat:
		var bm := _weapon.material_override as StandardMaterial3D
		bm.emission_enabled = true
		_tell_tw = create_tween()
		_tell_tw.tween_property(bm, "emission", color, maxf(t, 0.01))
		return
	_tell_tw = create_tween()
	_tell_tw.tween_method(func(c: Color) -> void: _weapon.set_instance_shader_parameter("tell", c), from, color, maxf(t, 0.01))


func flash(color: Color) -> void:
	if _flash_tw:
		_flash_tw.kill()
	_flash_tw = create_tween()
	_flash_tw.tween_method(_set_flash, color, Color.BLACK, 0.18)


func _set_flash(c: Color) -> void:
	for g in _skinned:
		g.set_instance_shader_parameter("flash", c)


func _swing_trail(color: Color, t := 0.22) -> void:
	_trail_color = color
	_trail_time = t


func _update_trail(delta: float) -> void:
	if _tip == null:
		return
	var base := _tip.get_parent() as Node3D
	if _trail_time > 0.0:
		_trail_time -= delta
		_trail_pts.append([base.global_position.lerp(_tip.global_position, 0.25), _tip.global_position])
		if _trail_pts.size() > 12:
			_trail_pts.pop_front()
	elif not _trail_pts.is_empty():
		_trail_pts.pop_front()
	var n := _trail_pts.size()
	if n < 2:
		if _trail_mm.visible_instance_count != 0:
			_trail_mm.visible_instance_count = 0
		return
	_trail_mm.visible_instance_count = n - 1
	for i in n - 1:
		var a0: Vector3 = _trail_pts[i][0]
		var a1: Vector3 = _trail_pts[i][1]
		var b0: Vector3 = _trail_pts[i + 1][0]
		var b1: Vector3 = _trail_pts[i + 1][1]
		var x := (b0 + b1 - a0 - a1) * 0.5
		var y := (a1 + b1 - a0 - b0) * 0.5
		var z := x.cross(y)
		z = z.normalized() * 0.001 if z.length() > 1e-06 else Vector3(0, 0, 0.001)
		_trail_mm.set_instance_transform(i, Transform3D(Basis(x, y, z), (a0 + a1 + b0 + b1) * 0.25))
		var col := _trail_color
		col.a = 0.7 * float(i + 1) / float(n - 1)
		_trail_mm.set_instance_color(i, col)


# ---------------------------------------------------------------- debug (look test and rig-contract only)

## What the last play() promised: clip, clip time of the key pose, seconds until it lands, chest yaw.
func debug_key() -> Dictionary:
	return _key


func debug_state() -> Dictionary:
	return {"action": _action, "clip": _ap.current_animation, "pos": _ap.current_animation_position, "segs": _segs.size(), "seg": _seg.duplicate()}


## Bone position in this visual's own frame divided by its scale (so moving, turning, reparenting
## or scaling the node does not change it).
func debug_bone(bone: String) -> Vector3:
	var i := _sk.find_bone(bone)
	var g := _sk.global_transform * _sk.get_bone_global_pose(i)
	return (global_transform.affine_inverse() * g.origin)


func debug_tip() -> Vector3:
	return global_transform.affine_inverse() * debug_tip_global()


## The weapon tip from the bone pose itself (a BoneAttachment3D only moves at the end of the frame).
func debug_tip_global() -> Vector3:
	if _tip == null:
		return global_position
	var att := _tip.get_parent() as BoneAttachment3D
	var i := _sk.find_bone(att.bone_name)
	return _sk.global_transform * _sk.get_bone_global_pose(i) * _tip.position


## Move the bone attachments now (they follow the skeleton once per frame on their own).
func debug_sync_attachments() -> void:
	for n in _sk.get_children():
		if n is BoneAttachment3D:
			(n as BoneAttachment3D).on_skeleton_update()


## Pose this (reference) rig at one clip time with a chest yaw, with no blending.
func debug_pose(clip: StringName, t: float, yaw := 0.0) -> void:
	_segs.clear()
	_ap.play(clip, 0.0, 0.0)
	_ap.seek(t, true)
	_seg = _hold_of(clip, t)
	_seg_left = INF
	_yaw_from = yaw
	_yaw_to = yaw
	_yaw_dur = 0.0
	_yaw_back = -1.0
	_offsets(0.0)
