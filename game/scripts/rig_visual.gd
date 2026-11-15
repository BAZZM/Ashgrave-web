extends FighterVisual
## A fighter built on KayKit's shared 41-joint skeleton (docs/RIG_PLAN.md, stage R1).
## Same contract as PlaceholderVisual (fighter_visual.gd): the duel code decides everything and
## calls play() with its own durations; this only shows it, landing each key pose when asked.
## Nothing in the game creates one yet: only the --looktest=rig debug scene does. No class_name:
## load with preload("res://scripts/rig_visual.gd").
##
## Shared by every instance: the AnimationLibrary (anims.glb, loaded once), the meshes, the atlas and the
## shader. Per instance: two small ShaderMaterials made from the shared one (body and gear: tint, flash;
## weapon: tint, tell). Not instance uniforms: on the web renderer their buffer ran out (4096 slots, the
## rig check hit "Too many instances using shader instance variables"). Also per instance: the skeleton and its
## AnimationPlayer, which runs in manual mode and is advanced by tick() from _process.
##
## Rules for the stages that put it in the game (R2 on): create one only when RigVisual.allowed() (quality
## "models"; Safe has none) and use PlaceholderVisual otherwise; nothing here uses physics (Build 19 stops
## the physics servers). Meshes, gear, clips, atlas and shader are loaded once per run (static caches).

const Clips := preload("res://scripts/rig_clips.gd")
const RigLooks := preload("res://scripts/rig_looks.gd")
const DIR := "res://assets/rig/"
const TIP_1H := 1.41  # 1H_Sword: tip along its bone's +Y (mesh AABB end)
const TIP_SKELETON_BLADE := 1.17  # Skeleton_Blade mesh AABB end (Skeleton_Blade.gltf)
## Loose gear in gear.glb (tools/pack_characters.py GEAR), hung on a bone at run time.
const LOOSE := {"Skeleton_Blade": {"bone": "handslot.r", "tip": TIP_SKELETON_BLADE}, "Dagger": {"bone": "handslot.r", "tip": -1.0}}

## Style -> base character and gear. The `gear` key of configure() overrides any of these.
const LOOKS := {
	"hero": {"base": "knight", "sword": "1H_Sword", "shield": "Badge_Shield", "helmet": true, "cape": true},
	"knight": {"base": "knight", "sword": "1H_Sword", "shield": "Rectangle_Shield", "helmet": true, "cape": false},
	"sentinel": {"base": "knight", "sword": "1H_Sword", "shield": "Rectangle_Shield", "helmet": true, "cape": true},
	"duelist": {"base": "knight", "sword": "1H_Sword", "shield": "", "helmet": false, "cape": false},
	"skeleton": {"base": "skeleton_warrior", "sword": "Skeleton_Blade", "shield": "", "helmet": true, "cape": false},
	"brute": {"base": "skeleton_warrior", "sword": "meshkit", "shield": "", "helmet": true, "cape": false},
	"boss": {"base": "knight", "sword": "2H_Sword", "shield": "Spike_Shield", "helmet": true, "cape": true},
}
const SHIELDS := ["Badge_Shield", "Rectangle_Shield", "Round_Shield", "Spike_Shield"]
const SWORDS := ["1H_Sword", "2H_Sword"]
const HELMETS := ["Knight_Helmet", "Skeleton_Warrior_Helmet"]
## Emission lift: PlaceholderVisual uses 0.5; on the KayKit atlas that washed the steel out to near white
## (knight on grass 1.76x the ground); 0.32 measured 1.20x. 0.45 keeps some of the steel's blue at 1.5x or more.
const FACE_SHADE := 0.4  # albedo of the face swatches (their lift is cut too): faces in shadow
const LIFT := 0.45
const CHEST_YAW := 20.0
const HIT_YAW := 16.0

const SHADER := "
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D atlas : source_color, filter_linear, repeat_disable;
uniform float rim_amount = 0.35;
uniform float metallic_k = 0.35;
uniform float lift = 0.5;
uniform float face_shade = 0.4;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 cloth : source_color = vec4(0.15, 0.3, 0.75, 1.0);
uniform vec4 glow : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 flash : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 tell : source_color = vec4(0.0, 0.0, 0.0, 1.0);
void fragment() {
	// The atlas alpha is a class mask per swatch (tools/pack_characters.py): 60 face skin, 120 cloth, 190 keep, 255 metal.
	vec4 t = texture(atlas, UV);
	vec3 c = t.rgb;
	float face = 1.0 - smoothstep(0.30, 0.40, t.a);
	float clo = smoothstep(0.30, 0.40, t.a) * (1.0 - smoothstep(0.55, 0.65, t.a));
	float met = smoothstep(0.87, 0.95, t.a);
	float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
	vec3 alb = mix(c, c * tint.rgb, met);
	alb = mix(alb, cloth.rgb * clamp(lum / 0.34, 0.4, 1.6), clo);
	alb *= mix(1.0, face_shade, face);  // faces in shadow (owner decision, 13 Nov)
	ALBEDO = alb;
	METALLIC = met * metallic_k;
	ROUGHNESS = mix(0.85, 0.45, met);
	// The same lift and rim as PlaceholderVisual (Build 16 lighting: fighters read at 1.5x the ground or more); a face gets little lift.
	EMISSION = mix(alb, vec3(1.0), 0.3) * lift * mix(1.0, 0.15, face) + flash.rgb + tell.rgb * 2.5 + glow.rgb * met;
	RIM = rim_amount;
	RIM_TINT = 0.3;
}
"

static var _lib: AnimationLibrary
static var _mat: ShaderMaterial
static var _bases := {}
static var _loose := {}
static var loads := 0  # resources loaded by the static caches (the rig check proves it stays flat)

@export var has_shield := false
var style := "hero"
var body_color := Color(0.5, 0.53, 0.6)
var accent_color := Color(0.85, 0.35, 0.12)
## Debug (look test, rig-contract check): when true, _process does not advance; the caller calls tick().
var manual_clock := false

var _over := {}
var _gear := {}
var _eq := {}
var _mapped := {}
var _speed := 0.0  # measured ground speed (u/s) of this node
var _gp := Vector3.INF
var _owed := 0.0  # time skipped while hidden or off screen
## The owner's decision (docs/DECISIONS.md, 13 Nov): KayKit heads at 0.85, faces in shadow.
var _head_scale := 0.85
var _rig: Node3D
var _sk: Skeleton3D
var _ap: AnimationPlayer
var _skinned: Array[GeometryInstance3D] = []
var _rigid: Array[GeometryInstance3D] = []
var _weapon: GeometryInstance3D
var _body_mat: ShaderMaterial
var _weapon_mat: ShaderMaterial
var _tip: Node3D
var _head_bone := -1
var _chest_off := Quaternion.IDENTITY  # the chest yaw last added on top of the clip (undone before the next advance)
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


## Whether the game may build one (quality "models"); a caller falls back to PlaceholderVisual otherwise.
static func allowed() -> bool:
	return Run.quality_allows("models")


## Free the four static caches (clips, meshes, gear, atlas and shader). Call it when quality drops to Safe, once the rigs are
## gone (a rig that is still alive keeps what it uses until it is freed): the game then holds no rig resource.
static func release() -> void:
	_lib = null
	_mat = null
	_bases.clear()
	_loose.clear()


static func library() -> AnimationLibrary:
	if _lib == null:
		loads += 1
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
		loads += 2
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		_mat.set_shader_parameter("atlas", load(DIR + "atlas.png"))
		for k in ["flash", "tell"]:
			_mat.set_shader_parameter(k, Color.BLACK)
		_mat.set_shader_parameter("tint", Color.WHITE)
	return _mat


static func _base(name_: String) -> PackedScene:
	if not _bases.has(name_):
		loads += 1
		_bases[name_] = load(DIR + name_ + ".glb")
	return _bases[name_]


static func _loose_mesh(name_: String) -> Mesh:
	if _loose.is_empty():
		loads += 1
		var g: Node = (load(DIR + "gear.glb") as PackedScene).instantiate()
		for mi in g.find_children("*", "MeshInstance3D"):
			_loose[str(mi.name)] = (mi as MeshInstance3D).mesh
		g.free()
	return _loose.get(name_)


func _ready() -> void:
	_build()


func configure(cfg: Dictionary) -> void:
	style = cfg.get("style", style)
	body_color = cfg.get("body", body_color)
	accent_color = cfg.get("accent", accent_color)
	_over = cfg.get("over", {})
	has_shield = cfg.get("shield", has_shield)
	_gear = cfg.get("gear", {})
	_eq = cfg.get("eq", {})
	_head_scale = cfg.get("head", _head_scale)
	var s: float = cfg.get("scale", absf(scale.y))
	scale = Vector3(signf(scale.x) * s, s, signf(scale.z) * s)
	if is_inside_tree():
		_build()


func _look() -> Dictionary:
	var look: Dictionary = (LOOKS.get(style, LOOKS.hero) as Dictionary).duplicate()
	if style == "hero":
		# The hero follows what is equipped (rig_looks.gd); other styles keep the LOOKS table until R4.
		_mapped = RigLooks.map({"over": _over, "eq": _eq, "body": body_color, "accent": accent_color}, has_shield)
		look.merge(_mapped, true)
	look.merge(_gear, true)
	if style != "hero" and not has_shield and not _gear.has("shield"):
		look.shield = ""
	return look


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_kill_tweens()


func _kill_tweens() -> void:
	for tw in [_flash_tw, _tell_tw]:
		if tw != null and tw.is_valid():
			tw.kill()
	_flash_tw = null
	_tell_tw = null


func _build() -> void:
	_kill_tweens()
	# Only the parts this visual made (a caller may hang its own nodes on it: world.gd hangs the hero's lantern). Freed at
	# once, not queued, so a rebuild leaves nothing behind for a frame and the leak check can count exactly.
	for c in [_rig, _trail]:
		if c != null and is_instance_valid(c):
			remove_child(c)
			c.free()
	_rig = null
	_trail = null
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
	_body_mat = material().duplicate() as ShaderMaterial  # shares the shader and the atlas
	_weapon_mat = material().duplicate() as ShaderMaterial
	var mat := _body_mat
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
				keep = look.helmet is bool and look.helmet or str(look.helmet) == att.name
			elif att.name == "Knight_Cape":
				keep = look.cape
			if not keep:
				att.free()
				continue
			mi2.material_override = mat
			mi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if att.name == "Knight_Cape" else mi2.cast_shadow
			_rigid.append(mi2)
			if att.name in SHIELDS and look.get("shield_scale", 1.0) != 1.0:
				mi2.scale *= float(look.shield_scale)
			if att.name in SWORDS:
				mi2.material_override = _weapon_mat
				_weapon = mi2
				_tip = Node3D.new()
				_tip.position = mi2.transform * Vector3(0, TIP_1H * (1.25 if att.name == "2H_Sword" else 1.0), 0)
				att.add_child(_tip)
	if look.sword == "meshkit":
		_attach_blade(1.2, 0.1)
	elif LOOSE.has(look.sword):
		_attach_loose(look.sword, _weapon_mat)
	_head_bone = _sk.find_bone("head")
	_chest_bone = _sk.find_bone("chest")
	_hand_bone = _sk.find_bone("hand.r")
	_extras(look)
	# Colours: a mapped (hero) look brings its own steel tint, accent and weapon tint; other styles get the old hue steer.
	var tint: Color = look.get("metal", Color.WHITE)
	if not look.has("metal"):
		var bc := body_color.lightened(0.25)
		tint = Color.WHITE.lerp(bc / maxf(maxf(bc.r, bc.g), maxf(bc.b, 0.01)), 0.5)
	var rim: float = PlaceholderVisual.RIM_HERO if style == "hero" else (PlaceholderVisual.RIM_ENEMY if absf(scale.y) >= PlaceholderVisual.ENEMY_MIN_SCALE else PlaceholderVisual.RIM_OTHER)
	for m in [_body_mat, _weapon_mat]:
		m.set_shader_parameter("rim_amount", rim)
		m.set_shader_parameter("metallic_k", PlaceholderVisual.METAL_METALLIC)
		m.set_shader_parameter("lift", LIFT)
		m.set_shader_parameter("face_shade", FACE_SHADE)
		m.set_shader_parameter("cloth", look.get("cloth", accent_color))
	_body_mat.set_shader_parameter("tint", tint)
	_weapon_mat.set_shader_parameter("tint", look.get("weapon_tint", tint))
	_weapon_mat.set_shader_parameter("glow", look.get("glow", Color.BLACK))
	_rig.scale = Vector3(float(look.get("bulk", 1.0)), 1.0, float(look.get("bulk", 1.0)))
	_ap = AnimationPlayer.new()
	_ap.name = "Anim"
	_rig.add_child(_ap)
	_ap.root_node = NodePath("..")
	_ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_ap.add_animation_library(&"", library())
	_build_trail()
	_chest_off = Quaternion.IDENTITY
	_segs.clear()
	_seg = {}
	_action = &""
	play(&"idle")
	tick(0.0)


## The hero's gear KayKit has no (or no packed) mesh for, and the back and belt items: built here from MeshKit and the
## gear.glb meshes, hung on bone attachments (head, chest, hips) so they follow the animation. Offsets are in the bone's frame.
func _extras(look: Dictionary) -> void:
	var steel := StandardMaterial3D.new()  # code-built steel: the same family as PlaceholderVisual's metal
	steel.albedo_color = (look.get("metal", Color.WHITE) as Color) * Color(0.62, 0.65, 0.72)
	steel.metallic = PlaceholderVisual.METAL_METALLIC
	steel.roughness = 0.45
	steel.cull_mode = BaseMaterial3D.CULL_DISABLED
	steel.rim_enabled = true
	steel.rim = 0.9
	steel.emission_enabled = true
	steel.emission = steel.albedo_color * 0.4
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = (look.get("cloth", accent_color) as Color).darkened(0.2)
	cloth.roughness = 0.9
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	cloth.emission_enabled = true
	cloth.emission = cloth.albedo_color * 0.3
	match str(look.get("helmet", "")):
		"great":
			var h := _on_bone("head", "GreatHelm")
			_mesh_on(h, MeshKit.lathe([[0.0, 0.47], [0.1, 0.46], [0.175, 0.4], [0.195, 0.28], [0.19, 0.12], [0.175, 0.02], [0.2, -0.03], [0.0, -0.03]], 16, 0.95, 1.05), Vector3(0, -0.06, 0), steel, 2.75)
			if look.get("fin", false):
				_mesh_on(h, MeshKit.lathe([[0.0, 0.0], [0.05, 0.03], [0.16, 0.16], [0.1, 0.3], [0.0, 0.36]], 10, 0.14, 1.3), Vector3(0, 1.2, 0.1), steel, 1.7)
		"hood":
			var h2 := _on_bone("head", "Hood")
			_mesh_on(h2, MeshKit.lathe([[0.0, 0.5], [0.12, 0.46], [0.2, 0.34], [0.22, 0.16], [0.2, 0.0], [0.24, -0.12], [0.0, -0.1]], 16, 1.0, 1.1), Vector3(0, -0.12, 0.03), cloth, 2.6)
	if look.get("spikes", false):
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.12, 0.12, 0.14)
		dark.metallic = 0.3
		dark.roughness = 0.6
		for side in ["l", "r"]:
			var a := _on_bone("upperarm." + side, "Spikes" + side)
			var sg := 1.0 if side == "l" else -1.0
			for k in 3:
				var dir := Vector3(sg * 0.5, 0.85, (k - 1) * 0.5).normalized()
				_mesh_on(a, MeshKit.horn(Vector3.ZERO, dir * 0.3, Vector3.ZERO, 0.05), Vector3(0, 0.12, (k - 1) * 0.1), dark, 1.6)
	if look.get("back_blade", false):
		var a2 := _on_bone("chest", "BackBlade")
		var m := MeshInstance3D.new()
		m.mesh = _loose_mesh("Dagger")
		m.material_override = _weapon_mat
		m.transform = Transform3D(Basis.from_euler(Vector3(0, 0, deg_to_rad(-30))) * Basis(Vector3.UP, PI), Vector3(0.15, 0.05, -0.5))
		a2.add_child(m)
		_rigid.append(m)
	if look.get("back_crossbow", false):
		var a3 := _on_bone("chest", "BackCrossbow")
		var m2 := MeshInstance3D.new()
		m2.mesh = _loose_mesh("Crossbow")
		m2.material_override = _body_mat
		m2.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(90), 0, deg_to_rad(20))) * 0.7, Vector3(-0.05, 0.1, -0.55))
		a3.add_child(m2)
		_rigid.append(m2)
	if look.get("knife_belt", false):
		var a4 := _on_bone("hips", "KnifeBelt")
		for k in 3:
			_mesh_on(a4, MeshKit.blade(0.2, 0.035, 0.012, 0.07), Vector3(-0.2 + k * 0.2, -0.1, 0.45), steel, 2.0)
	var focus: Color = look.get("focus", Color.BLACK)
	if focus != Color.BLACK:
		var a5 := _on_bone("hips", "SpellOrb")
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color.BLACK
		fm.emission_enabled = true
		fm.emission = focus
		fm.emission_energy_multiplier = 4.0
		var sph := SphereMesh.new()
		sph.radius = 0.07
		sph.height = 0.14
		_mesh_on(a5, sph, Vector3(0.55, 0.0, 0.1), fm, 2.2)


func _on_bone(bone: String, name_: String) -> BoneAttachment3D:
	var att := BoneAttachment3D.new()
	att.name = name_
	att.bone_name = bone
	_sk.add_child(att)
	return att


func _mesh_on(att: Node3D, mesh: Mesh, pos: Vector3, mat: Material, k: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.scale = Vector3.ONE * k
	mi.material_override = mat
	att.add_child(mi)
	_rigid.append(mi)


## Gear from gear.glb on its bone, placed as KayKit places 1H_Sword on handslot.r (0.033 up, turned 180 degrees).
func _attach_loose(name_: String, mat: Material) -> void:
	var spec: Dictionary = LOOSE[name_]
	var att := BoneAttachment3D.new()
	att.name = name_
	att.bone_name = spec.bone
	_sk.add_child(att)
	var mi := MeshInstance3D.new()
	mi.mesh = _loose_mesh(name_)
	mi.material_override = mat
	mi.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.0333, 0))
	att.add_child(mi)
	_rigid.append(mi)
	_weapon = mi
	_tip = Node3D.new()
	var tip_y: float = spec.tip if spec.tip > 0.0 else mi.mesh.get_aabb().end.y
	_tip.position = mi.transform * Vector3(0, tip_y, 0)
	att.add_child(_tip)


## A non-KayKit weapon on the right-hand slot: a MeshKit blade on handslot.r (the bone 1H_Sword hangs from).
func _attach_blade(length: float, width: float) -> void:
	var att := BoneAttachment3D.new()
	att.name = "MeshKitBlade"
	att.bone_name = "handslot.r"
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
	if manual_clock or _ap == null:
		return
	# Hidden or off screen: nothing to see, so no pose is computed. The time is owed (a windup that began off screen still
	# ends on time) and the speed reading starts again.
	if not is_visible_in_tree() or not _on_screen():
		_owed = minf(_owed + delta, 0.5)
		_gp = Vector3.INF
		return
	tick(delta + _owed)
	_owed = 0.0


func _on_screen() -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return true
	var k := absf(scale.y)
	var p := global_position
	if p.distance_to(cam.global_position) < 4.0 * k:
		return true
	for h in [0.0, 1.0, 2.2]:
		if cam.is_position_in_frustum(p + Vector3(0, h * k, 0)):
			return true
	return false


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
	# A chain that has reached its idle loop is over: locomotion may take the legs again (without this a hero that
	# slashed, or shot, and then walked off would glide: _action never came back to idle).
	if s.loop and s.clip == Clips.IDLE:
		_action = &"idle"
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
	_track_speed(dt)
	_undo_offsets()
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
	_undo_offsets()
	if absf(yaw) > 0.01:
		_chest_off = Quaternion(Vector3.UP, deg_to_rad(yaw))
		_sk.set_bone_pose_rotation(_chest_bone, _chest_off * _sk.get_bone_pose_rotation(_chest_bone))
	if _head_scale != 1.0:
		_sk.set_bone_pose_scale(_head_bone, Vector3.ONE * _head_scale)


## Take the last chest yaw off again, so a clip without a chest track (stripped as constant on import)
## does not pile yaw up frame after frame.
func _undo_offsets() -> void:
	if _chest_off != Quaternion.IDENTITY:
		_sk.set_bone_pose_rotation(_chest_bone, _chest_off.inverse() * _sk.get_bone_pose_rotation(_chest_bone))
		_chest_off = Quaternion.IDENTITY


func _yaw(to: float, over: float, back := -1.0) -> void:
	_yaw_from = _yaw_now()
	_yaw_to = to
	_yaw_t = 0.0
	_yaw_dur = maxf(over, 0.001)
	_yaw_back = back


## Ground speed of this node (u/s), read from how far it moved since the last tick; a jump (teleport, reparent) is ignored.
func _track_speed(dt: float) -> void:
	var p := global_position
	if dt > 0.0001 and _gp.x < 1.0e8:
		var v := Vector2(p.x - _gp.x, p.z - _gp.z).length() / dt
		if v < 60.0:
			_speed = lerpf(_speed, v, 1.0 - exp(-dt * 20.0))
	_gp = p


## Walk or run, with the clip's rate set from the real ground speed so the planted foot stays put on the ground. No cap on
## the rate (owner decision, 13 Nov). The speed is the node's own movement; a caller that only calls set_walk and set_pace
## (nothing moves it) gets the speed those two imply (walk x pace x the game's walk speed).
func _locomotion() -> void:
	var moving := _walk > 0.05 and _action == &"idle"
	var v := _speed if _speed > 0.3 else _walk * _pace * Clips.WALK_REF
	var vs := v / maxf(absf(scale.y), 0.1)  # in this rig's own units
	var want: StringName = &""
	if moving:
		want = Clips.RUN if vs >= Clips.RUN_AT * (0.85 if _loco == Clips.RUN else 1.0) else Clips.WALK
	if want != _loco:
		_loco = want
		if want == &"":
			_ap.speed_scale = 1.0
			_start(_loop_of(Clips.IDLE, 1.0, 0.2))
		else:
			_start(_loop_of(want, 1.0, 0.2))
	if want == Clips.WALK:
		_ap.speed_scale = clampf(vs / Clips.WALK_NATURAL, 0.1, 12.0)
	elif want == Clips.RUN:
		_ap.speed_scale = clampf(vs / Clips.RUN_NATURAL, 0.1, 12.0)


# ---------------------------------------------------------------- the contract

func play(action: StringName, dir: int = 0, duration: float = 0.3) -> void:
	if _ap == null:
		return
	var known := true
	match action:
		&"idle", &"recover":
			action = &"idle"  # `recover` is dead (docs/RIG_PLAN.md section 1) but must not leave _action on a name nothing resets
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
			var t3: float = Clips.STRIKE_TIME  # plan section 3: S in 0.05 s whatever `duration` says
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
	var from: Color = _weapon_mat.get_shader_parameter("tell") if _weapon.material_override == _weapon_mat else Color.BLACK
	if _weapon.material_override != _weapon_mat:
		var bm := _weapon.material_override as StandardMaterial3D
		bm.emission_enabled = true
		_tell_tw = create_tween()
		_tell_tw.tween_property(bm, "emission", color, maxf(t, 0.01))
		return
	_tell_tw = create_tween()
	_tell_tw.tween_method(func(c: Color) -> void: _weapon_mat.set_shader_parameter("tell", c), from, color, maxf(t, 0.01))


func flash(color: Color) -> void:
	if _flash_tw:
		_flash_tw.kill()
	_flash_tw = create_tween()
	_flash_tw.tween_method(_set_flash, color, Color.BLACK, 0.18)


func _set_flash(c: Color) -> void:
	_body_mat.set_shader_parameter("flash", c)


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
	_undo_offsets()
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
