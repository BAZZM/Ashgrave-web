class_name PlaceholderVisual
extends FighterVisual

@export var body_color := Color(0.5, 0.53, 0.6)
@export var accent_color := Color(0.85, 0.35, 0.12)
@export var has_shield := false

@export var style := "hero"

const HAND := Vector3(0.42, 1.3, -0.25)
const OFF_HAND := Vector3(-0.4, 1.0, -0.2)
const SHIELD_REST := Vector3(-0.5, 1.15, -0.28)
const IDLE_ROT := Vector3(-35, 0, -12)
const HIP_Y := 0.86
const FOOT_L := Vector3(-0.2, 0.0, -0.32)
const FOOT_R := Vector3(0.24, 0.0, 0.3)

const STYLES := {
	"hero": {"bulk": 1.0, "blade": [1.1, 0.085], "helm": "sallet", "cape": 0.95, "plume": true},
	"knight": {"bulk": 1.08, "blade": [1.2, 0.1], "helm": "great", "tabard": true, "fin": true},
	"sentinel": {"bulk": 1.1, "blade": [1.25, 0.1], "helm": "great", "tabard": true, "wings": true, "cape": 0.8},
	"duelist": {"bulk": 0.84, "blade": [1.35, 0.04], "helm": "sallet", "plume": true, "half_cape": true, "slim": true},
	"brute": {"bulk": 1.38, "blade": [1.25, 0.34], "helm": "pot", "horns": 0.3, "spikes": true, "cleaver": true, "fur": true, "hunch": 10.0},
	"boss": {"bulk": 1.18, "blade": [1.5, 0.15], "helm": "great", "horns": 0.55, "crown": true, "cape": 1.25, "core": true, "runes": true},
}

var _body: Node3D
var _torso: Node3D
var _sword: Node3D
var _shield: Node3D
var _off: Node3D
var _tip: Node3D
var _sh := {}
var _limbs := {}
var _joints := {}
var _feet := {}
var _armour: StandardMaterial3D
var _blade_mat: StandardMaterial3D
var _tw: Tween
var _glow_tw: Tween
var _flash_tw: Tween
var _fall_tw: Tween
var _trail: MultiMeshInstance3D
var _trail_mm: MultiMesh
static var _cloth_shader: Shader

## Art Bible sections 5 and 7 (G1). Metal reads as its own colour, not a mirrored sky.
const METAL_ROUGH := 0.45
const METAL_METALLIC := 0.60
const TRIM_ROUGH := 0.40
const TRIM_METALLIC := 0.70
const BLADE_ROUGH := 0.30
const BLADE_METALLIC := 0.85
## Rim light: the hero and a duel enemy get a strong one, everyone else keeps today's.
## Enemies are told from villagers and NPCs by scale (enemies are 1.1 and up).
const RIM_HERO := 0.5
const RIM_ENEMY := 0.7
const RIM_OTHER := 0.35
const RIM_TINT := 0.3
const ENEMY_MIN_SCALE := 1.08
var _rim_amt := RIM_OTHER
var _trail_pts: Array = []
var _trail_time := 0.0
var _trail_color := Color(1, 0.9, 0.7)
var _breath := 0.0
var _bulk := 1.0
var _hunch := 0.0
var _feet_follow := false
var _over := {}
var _walk := 0.0
var _walk_phase := 0.0
var _pace := 1.0


func _ready() -> void:
	_build()


func configure(cfg: Dictionary) -> void:
	style = cfg.get("style", style)
	body_color = cfg.get("body", body_color)
	accent_color = cfg.get("accent", accent_color)
	_over = cfg.get("over", {})
	var s: float = cfg.get("scale", absf(scale.y))
	scale = Vector3(signf(scale.x) * s, s, signf(scale.z) * s)
	_build()


func _metal(color: Color, rough := METAL_ROUGH, metallic := METAL_METALLIC) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	m.rim_enabled = true
	m.rim = _rim_amt
	m.rim_tint = RIM_TINT
	return m


func _cloth(color: Color) -> ShaderMaterial:
	if _cloth_shader == null:
		_cloth_shader = Shader.new()
		_cloth_shader.code = "\nshader_type spatial;\nrender_mode cull_disabled;\nuniform vec4 tint : source_color = vec4(0.3, 0.1, 0.1, 1.0);\nuniform float sway = 0.06;\nvoid vertex() {\n\tfloat w = UV.y * UV.y;\n\tVERTEX.z += (sin(TIME * 2.3 + UV.x * 5.0 + UV.y * 4.0) * sway + sway) * w;\n\tVERTEX.x += sin(TIME * 1.7 + UV.y * 6.0) * sway * 0.5 * w;\n}\nvoid fragment() {\n\tfloat fold = 0.82 + 0.18 * sin(UV.x * 34.0 + sin(UV.y * 5.0));\n\tfloat edge = smoothstep(1.0, 0.82, UV.y + 0.06 * sin(UV.x * 40.0));\n\tALBEDO = tint.rgb * fold;\n\tROUGHNESS = 0.95;\n\tif (edge < 0.5) { discard; }\n}\n"

	var m := ShaderMaterial.new()
	m.shader = _cloth_shader
	m.set_shader_parameter("tint", color)
	return m


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _free_part(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := _part(self, mesh, Vector3.ZERO, mat)
	mi.top_level = true
	return mi


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_trail_pts.clear()
	_feet_follow = false
	var st: Dictionary = (STYLES.get(style, STYLES.hero) as Dictionary).duplicate()
	st.merge(_over, true)
	_bulk = st.bulk
	_hunch = st.get("hunch", 0.0)
	var b := _bulk
	var slim: bool = st.get("slim", false)

	_rim_amt = RIM_HERO if style == "hero" else (RIM_ENEMY if absf(scale.y) >= ENEMY_MIN_SCALE else RIM_OTHER)
	_armour = _metal(body_color)
	var trim := _metal(accent_color.lerp(Color(1.0, 0.8, 0.4), 0.35), TRIM_ROUGH, TRIM_METALLIC)
	var dark := _metal(body_color.darkened(0.6), 0.75, 0.3)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color.BLACK
	glow.emission_enabled = true
	glow.emission = accent_color if style != "hero" else Color(0.5, 0.75, 1.0)
	glow.emission_energy_multiplier = 3.5 if style != "hero" else 0.6

	_body = Node3D.new()
	add_child(_body)

	_part(_body, MeshKit.lathe([[0.0, HIP_Y - 0.12], [0.17 * b, HIP_Y - 0.1], [0.2 * b, HIP_Y + 0.04], [0.0, HIP_Y + 0.08]], 12, 1.0, 0.8), Vector3.ZERO, dark)
	var fauld := _metal(body_color.darkened(0.15))
	fauld.cull_mode = BaseMaterial3D.CULL_DISABLED
	_part(_body, MeshKit.lathe([[0.215 * b, HIP_Y + 0.07], [0.25 * b, HIP_Y - 0.02], [0.31 * b, HIP_Y - 0.2], [0.33 * b, HIP_Y - 0.3]], 14, 1.0, 0.82), Vector3.ZERO, fauld)
	var belt := TorusMesh.new()
	belt.inner_radius = 0.2 * b
	belt.outer_radius = 0.25 * b
	_part(_body, belt, Vector3(0, HIP_Y + 0.06, 0), trim).scale = Vector3(1, 0.7, 0.82)
	if st.get("tabard", false):
		var tab := QuadMesh.new()
		tab.size = Vector2(0.26 * b, 0.62)
		tab.subdivide_depth = 6
		_part(_body, tab, Vector3(0, HIP_Y - 0.28, -0.275 * b), _cloth(accent_color.darkened(0.25)), Vector3(8, 180, 0))

	_torso = Node3D.new()
	_torso.position = Vector3(0, HIP_Y + 0.04, 0)
	_body.add_child(_torso)
	var chest_w := 0.86 if slim else 1.0
	_part(_torso, MeshKit.lathe([[0.0, -0.03], [0.2 * b, 0.0], [0.22 * b, 0.1], [0.26 * b, 0.26], [0.31 * b, 0.42],
		[0.32 * b, 0.52], [0.27 * b, 0.62], [0.13 * b, 0.68], [0.1, 0.76], [0.0, 0.77]], 16, chest_w, 0.74), Vector3.ZERO, _armour)

	if not st.get("core", false):
		_part(_torso, MeshKit.lathe([[0.0, 0.1], [0.05, 0.14], [0.07, 0.4], [0.05, 0.58], [0.0, 0.6]], 8, 1.0, 0.6), Vector3(0, 0, -0.2 * b), trim)
	var collar := TorusMesh.new()
	collar.inner_radius = 0.1
	collar.outer_radius = 0.16
	_part(_torso, collar, Vector3(0, 0.69, 0), trim)
	if st.get("core", false):
		var core := SphereMesh.new()
		core.radius = 0.09
		core.height = 0.18
		_part(_torso, core, Vector3(0, 0.44, -0.23 * b), glow)
	if st.get("fur", false):
		var fur := _metal(Color(0.16, 0.12, 0.1), 1.0, 0.0)
		_part(_torso, MeshKit.lathe([[0.0, 0.5], [0.3 * b, 0.54], [0.4 * b, 0.64], [0.3 * b, 0.76], [0.12, 0.8]], 12, 1.0, 0.85), Vector3.ZERO, fur)

	for side in [-1.0, 1.0]:
		var anchor := Node3D.new()
		anchor.position = Vector3(0.33 * b * side * chest_w, 0.6, 0)
		_torso.add_child(anchor)
		_sh[side] = anchor
		if slim and side < 0.0:
			continue
		var pr := 0.19 * b
		var dome := [[pr, -0.08], [pr * 1.02, 0.0], [pr * 0.85, 0.08], [pr * 0.5, 0.13], [0.0, 0.15]]
		_part(anchor, MeshKit.lathe(dome, 12, 1.15, 1.0), Vector3(0.04 * side, 0.0, 0), _armour, Vector3(0, 0, -22 * side))
		_part(anchor, MeshKit.lathe([[pr * 1.1, -0.16], [pr * 1.12, -0.09], [pr * 0.9, -0.03]], 12, 1.15, 1.0), Vector3(0.07 * side, 0, 0), trim, Vector3(0, 0, -26 * side))
		if st.get("spikes", false):
			for k in 3:
				var dir := Vector3(side * 0.6, 0.8, (k - 1) * 0.5).normalized()
				_part(anchor, MeshKit.horn(Vector3.ZERO, dir * 0.26, Vector3.ZERO, 0.045), Vector3(0.05 * side, 0.08, (k - 1) * 0.1), dark)

	var head_y := 0.78
	match st.helm:
		"great":
			_part(_torso, MeshKit.lathe([[0.0, 0.47], [0.1, 0.46], [0.175, 0.4], [0.195, 0.28], [0.19, 0.12], [0.175, 0.02], [0.2, -0.03], [0.0, -0.03]], 16, 0.95, 1.05), Vector3(0, head_y, 0), _armour)
			_part(_torso, MeshKit.lathe([[0.2, 0.25], [0.205, 0.27], [0.2, 0.29]], 16, 0.95, 1.05), Vector3(0, head_y, 0), trim)
		"pot":
			_part(_torso, MeshKit.lathe([[0.0, 0.42], [0.14, 0.4], [0.21, 0.3], [0.22, 0.14], [0.24, 0.0], [0.2, -0.03], [0.0, -0.03]], 14), Vector3(0, head_y, 0), _armour)
		_:
			_part(_torso, MeshKit.lathe([[0.0, 0.46], [0.09, 0.44], [0.17, 0.36], [0.19, 0.24], [0.185, 0.14], [0.21, 0.08], [0.13, 0.0], [0.0, -0.02]], 16, 0.92, 1.12), Vector3(0, head_y, 0), _armour)
	var slit := BoxMesh.new()
	slit.size = Vector3(0.25, 0.035, 0.08)
	_part(_torso, slit, Vector3(0, head_y + 0.25, -0.175), glow)
	if st.get("fin", false):
		_part(_torso, MeshKit.lathe([[0.0, 0.0], [0.05, 0.03], [0.16, 0.16], [0.1, 0.3], [0.0, 0.36]], 10, 0.14, 1.3), Vector3(0, head_y + 0.36, 0.03), trim)
	if st.get("plume", false):
		var plume := MeshKit.horn(Vector3.ZERO, Vector3(0, -0.02, 0.34), Vector3(0, 0.14, 0), 0.055, 8)
		_part(_torso, plume, Vector3(0, head_y + 0.42, 0.02), _metal(accent_color, 1.0, 0.0))
	if st.get("wings", false):
		for side in [-1.0, 1.0]:
			_part(_torso, MeshKit.lathe([[0.0, 0.0], [0.07, 0.05], [0.12, 0.22], [0.06, 0.4], [0.0, 0.46]], 8, 1.0, 0.12),
				Vector3(0.19 * side, head_y + 0.26, 0.04), trim, Vector3(-18, 0, -24 * side))
	var horns: float = st.get("horns", 0.0)
	if horns > 0.0:
		for side in [-1.0, 1.0]:
			_part(_torso, MeshKit.horn(Vector3.ZERO, Vector3(side * horns * 0.7, horns, -horns * 0.25), Vector3(side * horns * 0.5, -horns * 0.15, 0), 0.06),
				Vector3(0.15 * side, head_y + 0.3, 0), _metal(Color(0.85, 0.8, 0.7), 0.6, 0.1))
	if st.get("crown", false):
		for k in 7:
			var a := TAU * k / 7.0
			_part(_torso, MeshKit.horn(Vector3.ZERO, Vector3(0, 0.18, 0), Vector3.ZERO, 0.03, 3),
				Vector3(cos(a) * 0.17, head_y + 0.38, sin(a) * 0.18), trim)

	var cape_len: float = st.get("cape", 0.0)
	if cape_len > 0.0:
		var cape := QuadMesh.new()
		cape.size = Vector2(0.72 * b, cape_len)
		cape.subdivide_width = 8
		cape.subdivide_depth = 10
		_part(_torso, cape, Vector3(0, 0.62 - cape_len * 0.5, 0.27 * b), _cloth(accent_color.darkened(0.45)), Vector3(-9, 0, 0))
	if st.get("half_cape", false):
		var hc := QuadMesh.new()
		hc.size = Vector2(0.42, 0.8)
		hc.subdivide_width = 6
		hc.subdivide_depth = 8
		_part(_torso, hc, Vector3(-0.26, 0.26, 0.16), _cloth(accent_color.darkened(0.2)), Vector3(-6, 28, 0))

	_build_weapon(st, trim, dark, glow)

	if st.get("back_blade", false):
		var bm := _metal(st.get("blade_tint", Color(0.86, 0.88, 0.92)), BLADE_ROUGH, BLADE_METALLIC)
		bm.cull_mode = BaseMaterial3D.CULL_DISABLED
		_part(_torso, MeshKit.blade(0.82, 0.06, 0.035, 0.14), Vector3(-0.12, 0.05, 0.24 * b), bm, Vector3(0, 0, -28))
		_part(_torso, MeshKit.lathe([[0.0, -0.16], [0.025, -0.15], [0.025, 0.0], [0.0, 0.01]], 6), Vector3(-0.12, 0.05, 0.24 * b), dark, Vector3(0, 0, -28))
	if st.get("back_bow", false):
		var wood := _metal(Color(0.35, 0.22, 0.1), 0.8, 0.0)
		_part(_torso, MeshKit.horn(Vector3(0, -0.5, 0), Vector3(0, 0.5, 0), Vector3(0, 0, 0.22), 0.028, 9), Vector3(0.1, 0.3, 0.3 * b), wood, Vector3(0, 0, 24))
		_part(_torso, MeshKit.lathe([[0.0, -0.3], [0.06, -0.29], [0.07, 0.3], [0.0, 0.31]], 8), Vector3(-0.16, 0.3, 0.26 * b), wood, Vector3(0, 0, -20))
	if st.get("knife_belt", false):
		for k in 3:
			_part(_body, MeshKit.blade(0.2, 0.035, 0.012, 0.07), Vector3(0.1 + k * 0.07, HIP_Y - 0.16, -0.2 * b), _metal(Color(0.85, 0.87, 0.9), BLADE_ROUGH, BLADE_METALLIC), Vector3(180, 0, 0))
	if st.has("focus"):
		var orb := SphereMesh.new()
		orb.radius = 0.07
		orb.height = 0.14
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color.BLACK
		fm.emission_enabled = true
		fm.emission = st.focus
		fm.emission_energy_multiplier = 4.0
		_part(_body, orb, Vector3(-0.26 * b, HIP_Y - 0.05, -0.12), fm)

	_off = Node3D.new()
	_off.position = OFF_HAND
	_body.add_child(_off)
	_shield = null
	if has_shield:
		_shield = Node3D.new()
		_shield.position = SHIELD_REST
		_body.add_child(_shield)
		var sm := _metal(accent_color.darkened(0.25), 0.45, 0.6)
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		var rimm := _metal(Color(0.8, 0.78, 0.7))
		rimm.cull_mode = BaseMaterial3D.CULL_DISABLED
		match st.get("shield_kind", "heater"):
			"buckler":
				_part(_shield, MeshKit.lathe([[0.0, 0.07], [0.12, 0.05], [0.27, 0.0]], 16), Vector3.ZERO, sm, Vector3(-90, 0, 0))
				_part(_shield, MeshKit.lathe([[0.27, 0.0], [0.3, 0.0], [0.3, -0.02]], 16), Vector3.ZERO, rimm, Vector3(-90, 0, 0))
			"tower":
				_part(_shield, MeshKit.shield(0.74, 1.25, 0.16), Vector3(0, -0.1, 0), sm)
				_part(_shield, MeshKit.shield(0.8, 1.32, 0.16), Vector3(0, -0.1, 0.012), rimm)
			_:
				_part(_shield, MeshKit.shield(0.62, 0.86, 0.12), Vector3.ZERO, sm)
				_part(_shield, MeshKit.shield(0.68, 0.93, 0.12), Vector3(0, 0, 0.012), rimm)
		var boss_m := SphereMesh.new()
		boss_m.radius = 0.09
		boss_m.height = 0.12
		_part(_shield, boss_m, Vector3(0, 0.08, -0.13), trim)

	var ar := 0.075 * b * (0.85 if slim else 1.0)
	var lr := 0.105 * b * (0.85 if slim else 1.0)
	for side in [-1.0, 1.0]:
		_limbs["ua%d" % side] = _free_part(MeshKit.limb(ar * 1.15, ar * 1.05, ar * 0.9), dark)
		_limbs["fa%d" % side] = _free_part(MeshKit.limb(ar * 0.95, ar * 1.25, ar * 1.05), _armour)
		_limbs["th%d" % side] = _free_part(MeshKit.limb(lr * 1.2, lr * 1.1, lr * 0.85), dark)
		_limbs["sh%d" % side] = _free_part(MeshKit.limb(lr * 0.85, lr * 1.15, lr * 0.75), _armour)
		var cap := SphereMesh.new()
		cap.radius = ar * 1.05
		cap.height = ar * 2.1
		_joints["el%d" % side] = _free_part(cap, trim)
		var knee := SphereMesh.new()
		knee.radius = lr * 0.95
		knee.height = lr * 1.9
		_joints["kn%d" % side] = _free_part(knee, _armour)
		var fist := SphereMesh.new()
		fist.radius = ar * 1.2
		fist.height = ar * 2.4
		var fist_mat: Material = _armour
		if side > 0.0 and st.has("ring_glow"):
			var rg := StandardMaterial3D.new()
			rg.albedo_color = body_color
			rg.emission_enabled = true
			rg.emission = st.ring_glow
			rg.emission_energy_multiplier = 2.5
			fist_mat = rg
		_joints["hd%d" % side] = _free_part(fist, fist_mat)
		var boot := MeshKit.tube(PackedVector3Array([Vector3(0, 0.05, 0.1), Vector3(0, 0.06, 0.02), Vector3(0, 0.05, -0.16), Vector3(0, 0.03, -0.24)]),
			PackedFloat32Array([0.04 * b, 0.075 * b, 0.065 * b, 0.02]), 8, 1.0, 0.8)
		_feet[side] = _free_part(boot, _armour)

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
	_torso.rotation_degrees.x = -_hunch
	_solve()


func _build_weapon(st: Dictionary, trim: Material, dark: Material, glow: Material) -> void:
	_sword = Node3D.new()
	_sword.position = HAND
	_sword.rotation_degrees = IDLE_ROT
	_body.add_child(_sword)
	var length: float = st.blade[0]
	var width: float = st.blade[1]
	_blade_mat = _metal(st.get("blade_tint", Color(0.86, 0.88, 0.92)), BLADE_ROUGH, BLADE_METALLIC)
	_blade_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_blade_mat.emission_enabled = true
	_blade_mat.emission = Color.BLACK
	_blade_mat.emission_energy_multiplier = 2.5
	if st.get("cleaver", false):
		_part(_sword, MeshKit.cleaver(length, width, 0.05), Vector3(0, 0.12, 0), _blade_mat)
	else:
		_part(_sword, MeshKit.blade(length, width, 0.03 + width * 0.12, width * 2.2), Vector3(0, 0.12, 0), _blade_mat)
	if st.get("runes", false):
		var strip := BoxMesh.new()
		strip.size = Vector3(0.025, length * 0.6, 0.05)
		var rune: Material = glow
		if st.has("rune_color"):
			var rm := StandardMaterial3D.new()
			rm.albedo_color = Color.BLACK
			rm.emission_enabled = true
			rm.emission = st.rune_color
			rm.emission_energy_multiplier = float(st.get("rune_power", 3.0))
			rune = rm
		_part(_sword, strip, Vector3(0, 0.12 + length * 0.36, 0), rune)

	var gw := maxf(width * 1.9, 0.16)
	var guard := MeshKit.tube(PackedVector3Array([Vector3(-gw, 0.17, 0), Vector3(-gw * 0.6, 0.12, 0), Vector3(0, 0.11, 0), Vector3(gw * 0.6, 0.12, 0), Vector3(gw, 0.17, 0)]),
		PackedFloat32Array([0.012, 0.024, 0.032, 0.024, 0.012]), 8)
	_part(_sword, guard, Vector3.ZERO, trim)
	if st.get("slim", false):
		var ring := TorusMesh.new()
		ring.inner_radius = 0.075
		ring.outer_radius = 0.095
		_part(_sword, ring, Vector3(0, 0.07, -0.02), trim, Vector3(70, 0, 0))
	_part(_sword, MeshKit.lathe([[0.0, -0.17], [0.022, -0.16], [0.027, -0.02], [0.022, 0.1], [0.0, 0.11]], 8), Vector3.ZERO, dark)
	var pommel := SphereMesh.new()
	pommel.radius = 0.04
	pommel.height = 0.08
	_part(_sword, pommel, Vector3(0, -0.19, 0), trim)
	_tip = Node3D.new()
	_tip.position = Vector3(0, 0.12 + length, 0)
	_sword.add_child(_tip)


func _process(delta: float) -> void:
	if _body == null:
		return
	_breath += delta
	_walk_phase += delta * 9.5 * _walk * _pace
	_torso.position.y = HIP_Y + 0.04 + sin(_breath * 2.2) * 0.012 + absf(sin(_walk_phase)) * 0.03 * _walk
	_solve()
	_update_trail(delta)


func _place(limb: MeshInstance3D, a: Vector3, b: Vector3, s: float) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.001:
		return
	var y := d / length
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y)
	limb.global_transform = Transform3D(Basis(x * s, y * length, z * s), a + d * 0.5)


func _bend(a: Vector3, b: Vector3, l1: float, l2: float, pole: Vector3) -> Vector3:
	var dv := b - a
	var d := dv.length()
	if d >= (l1 + l2) * 0.999 or d < 0.001:
		return a + dv * (l1 / (l1 + l2))
	var along := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - along * along, 0.0))
	var dir := dv / d
	var p := pole - dir * pole.dot(dir)
	p = p.normalized() if p.length() > 0.001 else Vector3.UP
	return a + dir * along + p * h


func _solve() -> void:
	var gb := global_transform.basis
	var s := absf(gb.get_scale().y)
	var bb := _body.global_transform.basis.orthonormalized()
	for side in [-1.0, 1.0]:
		var shoulder: Vector3 = (_sh[side] as Node3D).global_position
		var hand_node: Node3D = _sword if side > 0.0 else (_shield if _shield else _off)
		var hand := hand_node.global_position
		if side < 0.0 and _shield:
			hand += bb * Vector3(0, 0, 0.1) * s
		var pole := bb * Vector3(side * 0.7, -1.0, 0.6)
		var elbow := _bend(shoulder, hand, 0.36 * s, 0.36 * s, pole)
		_place(_limbs["ua%d" % side], shoulder, elbow, s)
		_place(_limbs["fa%d" % side], elbow, hand, s)
		(_joints["el%d" % side] as Node3D).global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), elbow)
		(_joints["hd%d" % side] as Node3D).global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), hand)

		var hip := _body.global_transform * Vector3(0.15 * _bulk * side, HIP_Y, 0)
		var foot_local: Vector3 = (FOOT_L if side < 0.0 else FOOT_R) * Vector3(_bulk, 1, 1)
		if _walk > 0.01:
			var ph := _walk_phase + (0.0 if side < 0.0 else PI)
			foot_local = Vector3(foot_local.x, maxf(sin(ph), 0.0) * 0.16 * _walk, lerpf(foot_local.z, -cos(ph) * 0.36 * (1.0 + (_pace - 1.0) * 0.4), _walk))
		var src: Transform3D = _body.global_transform if _feet_follow else global_transform
		var foot := src * foot_local
		var ankle := foot + src.basis.y.normalized() * 0.1 * s
		var knee := _bend(hip, ankle, 0.42 * s, 0.42 * s, src.basis.orthonormalized() * Vector3(side * 0.25, 0.2, -1.0))
		_place(_limbs["th%d" % side], hip, knee, s)
		_place(_limbs["sh%d" % side], knee, ankle, s)
		(_joints["kn%d" % side] as Node3D).global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), knee)
		var fb := src.basis.orthonormalized() * Basis(Vector3.UP, -0.25 * side)
		(_feet[side] as Node3D).global_transform = Transform3D(fb.scaled(Vector3.ONE * s), foot)


func _update_trail(delta: float) -> void:
	if _trail_time > 0.0:
		_trail_time -= delta
		_trail_pts.append([_sword.global_position.lerp(_tip.global_position, 0.25), _tip.global_position])
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


func _pose(sword_rot: Vector3, sword_pos: Vector3, torso_rot: Vector3, t: float,
		body_pos := Vector3.ZERO, ease_type := Tween.EASE_OUT) -> void:
	if _tw:
		_tw.kill()
	t = maxf(t, 0.01)
	_tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(ease_type)
	_tw.tween_property(_sword, "rotation_degrees", sword_rot, t)
	_tw.tween_property(_sword, "position", sword_pos, t)
	_tw.tween_property(_torso, "rotation_degrees", torso_rot - Vector3(_hunch, 0, 0), t)
	_tw.tween_property(_body, "position", body_pos + Vector3(0, -0.03, 0), t)
	if _shield:
		_tw.tween_property(_shield, "position", SHIELD_REST, t)
		_tw.tween_property(_shield, "rotation_degrees", Vector3(0, 25, 0), t)


func _glow(color: Color, t: float) -> void:
	if _glow_tw:
		_glow_tw.kill()
	_glow_tw = create_tween()
	_glow_tw.tween_property(_blade_mat, "emission", color, maxf(t, 0.01))


func _swing_trail(color: Color, t := 0.22) -> void:
	_trail_color = color
	_trail_time = t


func play(action: StringName, dir: int = 0, duration: float = 0.3) -> void:
	if _body == null:
		return
	match action:
		&"idle", &"recover":
			_rise()
			_glow(Color.BLACK, 0.15)
			_pose(IDLE_ROT, HAND, Vector3.ZERO, maxf(duration, 0.25), Vector3.ZERO, Tween.EASE_IN_OUT)
		&"taunt":
			_pose(Vector3(10, 0, -60), HAND + Vector3(0.35, 0.35, 0), Vector3(12, 0, 0), 0.5)
		&"windup":
			match dir:
				AttackDef.Dir.LEFT:
					_pose(Vector3(15, 0, -80), HAND + Vector3(0.15, 0.2, 0.1), Vector3(5, -20, 0), duration, Vector3(0, 0, 0.12))
				AttackDef.Dir.RIGHT:
					_pose(Vector3(15, 0, 80), HAND + Vector3(-0.75, 0.2, 0.05), Vector3(5, 25, 0), duration, Vector3(0, 0, 0.12))
				AttackDef.Dir.OVER:
					_pose(Vector3(40, 0, 0), HAND + Vector3(-0.2, 0.6, 0.1), Vector3(12, 0, 0), duration, Vector3(0, 0, 0.12))
				_:
					_pose(Vector3(-90, 0, 0), HAND + Vector3(0, -0.1, 0.45), Vector3(4, -15, 0), duration, Vector3(0, 0, 0.18))
		&"feint":
			var back := _sword.rotation_degrees + Vector3(10, 0, 0)
			_pose(back, _sword.position + Vector3(0, 0.06, 0.08), _torso.rotation_degrees + Vector3(_hunch, 0, 0), duration, _body.position + Vector3(0, 0.03, 0))
		&"strike":
			_glow(Color.BLACK, 0.3)
			_swing_trail(Color(1.0, 0.45, 0.2))
			var lunge := Vector3(0, -0.06, -0.38)
			match dir:
				AttackDef.Dir.LEFT:
					_pose(Vector3(-80, 0, 70), HAND + Vector3(-0.5, 0, -0.45), Vector3(-16, 28, 0), duration, lunge, Tween.EASE_IN)
				AttackDef.Dir.RIGHT:
					_pose(Vector3(-80, 0, -70), HAND + Vector3(0.1, 0, -0.45), Vector3(-16, -28, 0), duration, lunge, Tween.EASE_IN)
				AttackDef.Dir.OVER:
					_pose(Vector3(-115, 0, 0), HAND + Vector3(-0.2, -0.2, -0.5), Vector3(-24, 0, 0), duration, lunge, Tween.EASE_IN)
				_:
					_pose(Vector3(-90, 0, 0), HAND + Vector3(-0.1, 0, -0.95), Vector3(-12, 10, 0), duration, lunge * 1.3, Tween.EASE_IN)
		&"stagger":
			_glow(Color.BLACK, 0.1)
			_pose(Vector3(30, 0, -110), HAND + Vector3(0.3, -0.3, 0.2), Vector3(20, 0, 8), 0.2, Vector3(0, -0.05, 0.25))
		&"broken":
			_glow(Color.BLACK, 0.1)
			_pose(Vector3(70, 0, -120), HAND + Vector3(0.3, -0.5, 0.1), Vector3(-30, 0, 0), 0.3, Vector3(0, -0.36, 0.1))
		&"hit":
			_pose(_sword.rotation_degrees, _sword.position,
				Vector3((_torso.rotation_degrees.x + _hunch) * 0.6 + 8.0, 16.0 * dir, 7.0 * dir), duration, _body.position + Vector3(0, 0.03, 0))
		&"guard":
			_pose(Vector3(-10, 0, 60), HAND + Vector3(-0.4, 0.1, -0.2), Vector3.ZERO, 0.08)
		&"slash":
			_swing_trail(Color(1.0, 0.95, 0.8))
			var lunge2 := Vector3(0, -0.05, -0.28)
			if dir == 2:
				_sword.rotation_degrees = Vector3(-140, 0, 15)
				_sword.position = HAND + Vector3(-0.1, -0.5, -0.3)
				_pose(Vector3(-20, 0, -10), HAND + Vector3(-0.15, 0.45, -0.45), Vector3(8, 0, 0), duration, lunge2)
			elif dir == 3:
				_sword.rotation_degrees = Vector3(30, 0, 0)
				_sword.position = HAND + Vector3(-0.15, 0.55, -0.1)
				_pose(Vector3(-125, 0, 0), HAND + Vector3(-0.15, -0.3, -0.5), Vector3(-18, 0, 0), duration, lunge2)
			else:
				var sd := 1.0 if dir >= 0 else -1.0
				_sword.rotation_degrees = Vector3(-50, 0, 75 * sd)
				_sword.position = HAND + Vector3(-0.2 - 0.3 * sd, 0.15, -0.2)
				_pose(Vector3(-85, 0, -75 * sd), HAND + Vector3(-0.2 + 0.3 * sd, 0, -0.5), Vector3(-8, -20 * sd, 0), duration, lunge2)
		&"parry":
			_swing_trail(Color(1.0, 1.0, 0.9), 0.12)
			var p := 1.0 if dir >= 0 else -1.0
			_pose(Vector3(-20, 0, 55 * -p), HAND + Vector3(-0.2 + 0.25 * p, 0.25, -0.35), Vector3(-4, 0, 0), 0.06)
		&"block":
			_pose(Vector3(-20, 0, -30), HAND + Vector3(0.1, -0.1, 0), Vector3(-6, 0, 0), 0.1, Vector3(0, -0.06, 0))
			if _shield:
				_tw.tween_property(_shield, "position", Vector3(-0.12, 1.38, -0.55), 0.1)
				_tw.tween_property(_shield, "rotation_degrees", Vector3(-8, 0, 0), 0.1)
		&"dodge":
			_pose(IDLE_ROT, HAND, Vector3(0, 0, -16.0 * dir), 0.12, Vector3(0, -0.2, 0))
		&"death":
			_glow(Color.BLACK, 0.1)
			_feet_follow = true
			_pose(Vector3(80, 0, -100), HAND + Vector3(0.3, -0.6, 0.3), Vector3(25, 0, 6), 0.9, Vector3(0, 0, 0.3), Tween.EASE_IN)
			if _fall_tw:
				_fall_tw.kill()
			_fall_tw = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			_fall_tw.tween_property(_body, "rotation_degrees:x", 82.0, 1.0)
		&"victory":
			_pose(Vector3(5, 0, -8), HAND + Vector3(0, 0.6, 0), Vector3(6, 0, 0), 0.5)


## Undo the death fall. Without this a fighter that went down stays tipped
## over for good, since no other pose touches the body's rotation.
func _rise() -> void:
	if _fall_tw:
		_fall_tw.kill()
		_fall_tw = null
	_body.rotation_degrees.x = 0.0
	_feet_follow = false


func set_walk(amount: float) -> void:
	_walk = clampf(amount, 0.0, 1.0)


## Speed relative to a plain walk (1 = walk): quickens the leg cycle and lengthens the stride.
func set_pace(mult: float) -> void:
	_pace = clampf(mult, 1.0, 2.5)


func set_tell(color: Color, t: float) -> void:
	_glow(color, t)


func flash(color: Color) -> void:
	if _flash_tw:
		_flash_tw.kill()
	_armour.emission_enabled = true
	_armour.emission = color
	_flash_tw = create_tween()
	_flash_tw.tween_property(_armour, "emission", Color.BLACK, 0.18)
