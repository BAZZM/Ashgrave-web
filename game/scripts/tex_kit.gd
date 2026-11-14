extends RefCounted
## Texture kit (lane G2, docs/TEXTURE_LOOK.md): shared, cached materials and shader strings that put the
## owner's textures on the world in one of three colour treatments. The real game uses GRAIN for ground and water
## only (overworld_terrain.gd, lane G3); everything else here is for the debug look-test scene
## (tex_looktest.gd, `--looktest=tex`).
##
##   FLAT    today's look: flat or vertex colour, no texture is loaded (the control).
##   GRAIN   Art Bible 2: a luminance-only grain (channel-packed, res://assets/textures/packed/) recoloured
##           by a two-colour palette ramp, `mix(dark, light, grain)`, light = tint * (1 + d), dark = tint * (1 - d)
##           mixed 10% toward region fog; d + 0.10 where the tint's V < 0.25.
##   SOURCE  the colour textures themselves, graded: desaturate, take the ratio to the texture's own mean colour
##           (raised to a contrast), multiply by the palette tint, and blend that over the raw texture by `k`.
##
## Every texture is loaded through tex(), which asks Run.quality_allows("textures") first and never loads
## when it says no; every material function then returns the flat material (today's look) instead.
## Palette colours are used raw (no colour-space conversion) everywhere, as today's vertex colours are and as
## StandardMaterial3D's albedo_color behaves in the Compatibility renderer (measured: a flat plaster wall and a
## textured one only agree in mean brightness this way), so a textured surface has the mean colour of the flat one.
## Shaders are strings, one per (kind, treatment), cached; materials are cached by kind, treatment and colours.

const FLAT := 0
const GRAIN := 1
const SOURCE := 2
const NAMES := ["flat", "grain", "source"]
const DIR := "res://assets/textures/"

## World units per texture repeat (Art Bible 2.1: 512 px = 4 m, 128 texels per unit on ground, stone and water).
const TILE_GROUND := 4.0
const TILE_GROUND_2 := 9.2   # the second, larger, rotated sample that breaks repetition
const TILE_WATER := 4.0
const TILE_WATER_2 := 6.5
const TILE_STONE := 4.0
const TILE_PLANKS := 2.0
const TILE_BARK := 2.0
const TILE_LEAF := 1.6
const TILE_ARMOUR := 0.5
## SOURCE grading per texture: [desaturation, k toward the palette tint, contrast on the ratio to the mean colour].
const GRADE := {
	"grass_lush": [0.30, 0.75, 0.55], "forest_floor": [0.25, 0.75, 0.55], "dirt_trail": [0.25, 0.80, 0.55],
	"mud_wetland": [0.25, 0.80, 0.55], "water_deep": [0.30, 0.80, 0.55], "water_shallow": [0.30, 0.80, 0.55],
	"castle_stone": [0.20, 0.80, 0.55], "cobblestone": [0.20, 0.80, 0.55], "planks": [0.20, 0.80, 0.55],
	"bark_deciduous": [0.25, 0.80, 0.55], "bark_pine": [0.25, 0.80, 0.55],
	"leaf_broadleaf": [0.30, 0.80, 0.55], "leaf_evergreen": [0.30, 0.80, 0.55],
	"steel_plate": [0.10, 0.80, 0.55], "chainmail": [0.10, 0.80, 0.55], "gambeson": [0.25, 0.80, 0.55],
	"heraldic_cloth": [0.10, 0.25, 0.60],
}
## Mean colour of each colour texture as stored, not linearised (tools/pack_textures.py prints these): the Compatibility
## renderer hands texels over as stored, like every other colour here.
const TEX_MEAN := {
	"chainmail": Color(0.2931, 0.2623, 0.2285),
	"gambeson": Color(0.4248, 0.3193, 0.2242),
	"steel_plate": Color(0.4024, 0.3879, 0.3781),
	"bark_deciduous": Color(0.4186, 0.3607, 0.2857),
	"bark_pine": Color(0.4676, 0.3297, 0.2601),
	"heraldic_cloth": Color(0.4628, 0.1919, 0.1182),
	"leaf_broadleaf": Color(0.3383, 0.4175, 0.1060),
	"leaf_evergreen": Color(0.2896, 0.3492, 0.1235),
	"cobblestone": Color(0.3632, 0.3271, 0.2655),
	"dirt_trail": Color(0.4561, 0.3924, 0.2151),
	"forest_floor": Color(0.3751, 0.2994, 0.2020),
	"grass_lush": Color(0.3153, 0.3738, 0.0820),
	"grass_meadow": Color(0.3747, 0.3651, 0.1105),
	"mud_wetland": Color(0.3528, 0.2846, 0.1993),
	"castle_stone": Color(0.3773, 0.3662, 0.3244),
	"water_deep": Color(0.0708, 0.2984, 0.3422),
	"water_shallow": Color(0.3740, 0.4871, 0.3664),
	"planks": Color(0.3969, 0.3178, 0.2511),
}
## Grain depth d per grain (Art Bible 2.1 table).
const D_GROUND := 0.18
const D_FOREST := 0.20
const D_MUD := 0.20
const D_PATH := 0.28
const D_PATH_EDGE := 0.18   # the trail's grain depth falls from D_PATH in its middle to this at its edges
const D_ASH := 0.12         # Ashlands ground grain depth, with highlights capped at CAP_ASH (G3 critic fix 4)
const CAP_ASH := 0.62
const D_WATER := 0.15
const D_STONE := 0.28
const D_COBBLE := 0.22
const D_WOOD := 0.25
const D_LEAF := 0.25
const D_HERO := 0.30
const D_ENEMY := 0.20

## The real game's palette for textured ground and water (G3, critic fixes 2 to 5). Raw colours, like every tint here.
const PATH_LIGHT := Color("#6E5238")   # trail: warm dry earth, about 1.2 times the grass's luminance (G3 round 2: the Critic's #6B5A40 mixed into the ground made the trail vanish)
const PATH_ASH := Color("#746A60")     # the Ashlands' trail: pale warm grey-brown, about 1.35 times the ground (whose tint is TINT_GRAIN.ashlands), not gold
const WATER_DEEP := Color("#20343A")
const WATER_SHALLOW := Color("#3E6A68")  # only within about 1 m of the shore
const WORLD_FOG := Color("#6E7470")      # the ramp mixes 10% of this into the dark end; one material serves every region
## Ground tints that differ from Land.BIOMES' flat colours when textured (docs/TEXTURE_LOOK.md, G3).
## forest (Greywood): the flat colour renders a saturated emerald (rendered saturation about 0.39) under the region's green ambient;
## this tint is less saturated (hue near the palette's #2F3F2C) at about the luminance Greywood has today (an earlier lighting review).
## ashlands: lifted so the grain (mean a few percent below the flat colour, highlights capped) lands near today's luminance.
## village and meadow: darker (10% and 18%) so a fighter reads at 1.45 times the ground or more in the real duel (flat today: 1.12;
## measured with tools/g3_measure.py).
const TINT_GRAIN := {"forest": Color("#566253"), "ashlands": Color("#605C5B"), "village": Color("#596635"), "meadow": Color("#4A5831")}

static var _tex := {}
static var _shaders := {}
static var _mats := {}
## Paths loaded so far (for the memory report).
static var loaded := []


static func parse(name: String) -> int:
	var i := NAMES.find(name.to_lower())
	return i if i >= 0 else FLAT


## A texture under res://assets/textures/, or null when the quality level forbids textures (then nothing is
## loaded at all). Cached.
static func tex(rel: String) -> Texture2D:
	if _tex.has(rel):
		return _tex[rel]
	if not Run.quality_allows("textures"):
		return null
	# The release pack holds only what ground and water sample (tools/build.py); the look test's other textures are
	# absent there, and its materials then fall back to flat.
	if not ResourceLoader.exists(DIR + rel + ".png"):
		_tex[rel] = null
		return null
	var t := load(DIR + rel + ".png") as Texture2D
	_tex[rel] = t
	loaded.append(rel)
	return t


## The textures the real game's ground samples are loaded (false when the level forbids textures or the pack lacks them).
static func ground_ready() -> bool:
	return tex("packed/terrain_a") != null and tex("packed/terrain_b") != null


## Likewise for the water (ripple map and the shared terrain_b grain).
static func water_ready() -> bool:
	return tex("packed/ripple") != null and tex("packed/terrain_b") != null


## The palette dictionary of the real game's ground and water materials (one material of each serves every region).
static func world_pal() -> Dictionary:
	return {"path": PATH_LIGHT, "path_ash": PATH_ASH, "mud": Land.SHORE_COLOR, "fog": WORLD_FOG, "deep": WATER_DEEP, "shallow": WATER_SHALLOW}


static func _shader(key: String, code: String) -> Shader:
	if not _shaders.has(key):
		var s := Shader.new()
		s.code = code
		_shaders[key] = s
	return _shaders[key]


static func _sm(shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	return m


## Today's flat material: albedo colour, or the mesh's vertex colour when `vertex_colour`.
static func flat_mat(color: Color, vertex_colour := false, rough := 0.9, glow := 0.0) -> StandardMaterial3D:
	var key := "flat|%s|%s|%s" % [color.to_html(), vertex_colour, rough]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = rough
		m.vertex_color_use_as_albedo = vertex_colour
		_mats[key] = m
	return _mats[key]


## Raw colour as a vec3: the terrain's convention (today's vertex colours are used as they are).
static func _vec(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


## Shared GLSL: the ramp (GRAIN), the grade (SOURCE), the macro noise (both).
const COMMON := """
const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
vec3 ramp(vec3 tint, float g, float d, vec3 fog) {
	float dd = d + (max(tint.r, max(tint.g, tint.b)) < 0.25 ? 0.10 : 0.0);
	vec3 light = tint * (1.0 + dd);
	vec3 dark = mix(tint * (1.0 - dd), fog, 0.10);
	return mix(dark, light, g);
}
// p = (desaturation, k toward the palette, contrast). cn: the texel's chroma (colour divided by its luminance),
// desaturated; gain: brightness against the texture's own mean, softened by `contrast` and clamped. k = 0 keeps the
// source's hue at the palette's brightness; k = 1 is the palette hue (tint) with only the texture's local variation.
vec3 grade(vec3 c, vec3 mean_c, vec3 tint, vec3 p) {
	float l = max(dot(c, LUMA), 1e-4);
	float lm = dot(mean_c, LUMA);
	vec3 cn = mix(c / l, vec3(1.0), p.x);
	vec3 mn = mix(mean_c / lm, vec3(1.0), p.x);
	vec3 hue = clamp(cn / mn, vec3(0.6), vec3(1.6));
	float gain = clamp(1.0 + (l / lm - 1.0) * p.z, 0.3, 1.8);
	return gain * mix(cn * dot(tint, LUMA), tint * hue, p.y);
}
float macro(vec2 p) {
	return 1.0 + 0.08 * (0.5 * sin(p.x * 0.1698 + sin(p.y * 0.1131) * 1.7) + 0.5 * sin(p.y * 0.1698 + sin(p.x * 0.0905) * 1.3));
}
float both(float a, float b) {
	return clamp(0.5 + ((a - 0.5) + (b - 0.5)) * 0.7071, 0.0, 1.0);
}
"""

const SAMP_REPEAT := ": filter_linear_mipmap_anisotropic, repeat_enable"
## No `source_color` hint on the colour textures: the stored values are used undecoded on every device, like the palette
## colours, so the means in TEX_MEAN hold wherever the sampler would otherwise decide per device.
const SAMP_REPEAT_SRGB := ": filter_linear_mipmap_anisotropic, repeat_enable"


## ---- terrain: world-space, four layers by per-vertex weights --------------------------------------------
## Vertex data (build_ground): COLOR.rgb = the biome tint, UV = (path weight, mud weight), UV2 = (forest weight, Ashlands weight).
## GRAIN reads terrain_a and terrain_b twice (two scales) = 4 reads; SOURCE reads grass, forest floor, trail, mud once = 4.
static func _terrain_code(t: int) -> String:
	var head := "shader_type spatial;\nrender_mode specular_disabled;\n" + COMMON + """
varying vec3 wp;
uniform vec3 path_col;
uniform vec3 path_ash;
uniform vec3 mud_col;
uniform vec3 fog_col;
uniform float tile = 4.0;
uniform float tile2 = 9.2;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
"""
	if t == GRAIN:
		return head + """
uniform sampler2D tex_a""" + SAMP_REPEAT + """;
uniform sampler2D tex_b""" + SAMP_REPEAT + """;
uniform float d_base = 0.18;
uniform float d_forest = 0.20;
uniform float d_path = 0.28;
uniform float d_path_edge = 0.18;
uniform float d_mud = 0.20;
uniform float d_ash = 0.12;
uniform float cap_ash = 0.62;
// Vertex data (TexKit.build_ground): COLOR = the region's ground tint, UV = (trail weight, mud weight),
// UV2 = (forest-floor weight, Ashlands weight). The trail is its own colour (path_col, or path_ash in the Ashlands) with grain: its depth is
// d_path at the trail's middle and falls to d_path_edge at its edges; the Ashlands use their own trail colour, a shallower
// ground grain (d_ash) and no grain highlights above cap_ash (the pale scratch lines of the forest-floor map read as frost).
void fragment() {
	vec2 p = wp.xz;
	vec2 u1 = p / tile;
	vec2 u2 = (mat2(vec2(0.866, -0.5), vec2(0.5, 0.866)) * p) / tile2 + vec2(0.37, 0.61);
	vec4 a1 = texture(tex_a, u1); vec4 a2 = texture(tex_a, u2);
	vec4 b1 = texture(tex_b, u1); vec4 b2 = texture(tex_b, u2);
	float nm = smoothstep(0.35, 0.65, 0.5 + 0.5 * sin(p.x * 0.071 + sin(p.y * 0.053) * 2.0) * sin(p.y * 0.047 + 1.0));
	float g_grass = both(mix(a1.r, a1.g, nm), mix(a2.r, a2.g, nm));
	float ash = UV2.y;
	float g_forest = both(b1.r, b2.r);
	g_forest = mix(g_forest, min(g_forest, cap_ash), ash);
	float g_path = both(a1.b, a2.b);
	float g_mud = both(a1.a, a2.a);
	vec3 tint = COLOR.rgb;
	vec3 col = mix(ramp(tint, g_grass, d_base, fog_col), ramp(tint, g_forest, mix(d_forest, d_ash, ash), fog_col), UV2.x);
	float dp = mix(d_path_edge, d_path, UV.x);
	vec3 pcol = ramp(mix(path_col, path_ash, ash), g_path, dp, fog_col);
	col = mix(col, pcol, UV.x);
	col = mix(col, ramp(mud_col, g_mud, d_mud, fog_col), UV.y);
	ALBEDO = col * macro(p);
	ROUGHNESS = 1.0;
}
"""
	return head + """
uniform sampler2D t_grass""" + SAMP_REPEAT_SRGB + """;
uniform sampler2D t_forest""" + SAMP_REPEAT_SRGB + """;
uniform sampler2D t_path""" + SAMP_REPEAT_SRGB + """;
uniform sampler2D t_mud""" + SAMP_REPEAT_SRGB + """;
uniform vec3 m_grass; uniform vec3 m_forest; uniform vec3 m_path; uniform vec3 m_mud;
uniform vec3 g_grass; uniform vec3 g_forest; uniform vec3 g_path; uniform vec3 g_mud;
void fragment() {
	vec2 p = wp.xz;
	vec2 q = p + 1.3 * vec2(sin(p.y * 0.31), sin(p.x * 0.27));
	vec2 u = q / tile;
	vec3 tint = COLOR.rgb;
	vec3 col = mix(grade(texture(t_grass, u).rgb, m_grass, tint, g_grass), grade(texture(t_forest, u).rgb, m_forest, tint, g_forest), UV2.x);
	col = mix(col, grade(texture(t_path, u).rgb, m_path, path_col, g_path), UV.x);
	col = mix(col, grade(texture(t_mud, u).rgb, m_mud, mud_col, g_mud), UV.y);
	ALBEDO = col * macro(p);
	ROUGHNESS = 1.0;
}
"""


static func _g(name: String) -> Vector3:
	var g: Array = GRADE[name]
	return Vector3(g[0], g[1], g[2])


static func _m(name: String) -> Vector3:
	return _vec(TEX_MEAN[name])


## pal: {path: Color, mud: Color, fog: Color, path_ash: Color (optional)}. The mesh must come from build_ground().
static func terrain(t: int, pal: Dictionary) -> Material:
	var key := "terrain|%d|%s|%s|%s|%s" % [t, pal.path.to_html(), pal.mud.to_html(), pal.fog.to_html(), pal.get("path_ash", pal.path).to_html()]
	if _mats.has(key):
		return _mats[key]
	var m: Material
	var a: Texture2D = tex("packed/terrain_a") if t == GRAIN else (tex("ground/grass_lush") if t == SOURCE else null)
	if t == FLAT or a == null:
		m = flat_mat(Color.WHITE, true, 0.95)
	else:
		var sm := _sm(_shader("terrain%d" % t, _terrain_code(t)))
		sm.set_shader_parameter("path_col", _vec(pal.path))
		sm.set_shader_parameter("path_ash", _vec(pal.get("path_ash", pal.path)))
		sm.set_shader_parameter("mud_col", _vec(pal.mud))
		sm.set_shader_parameter("fog_col", _vec(pal.fog))
		sm.set_shader_parameter("tile", TILE_GROUND)
		sm.set_shader_parameter("tile2", TILE_GROUND_2)
		if t == GRAIN:
			sm.set_shader_parameter("tex_a", a)
			sm.set_shader_parameter("tex_b", tex("packed/terrain_b"))
			sm.set_shader_parameter("d_base", D_GROUND)
			sm.set_shader_parameter("d_forest", D_FOREST)
			sm.set_shader_parameter("d_path", D_PATH)
			sm.set_shader_parameter("d_path_edge", D_PATH_EDGE)
			sm.set_shader_parameter("d_mud", D_MUD)
			sm.set_shader_parameter("d_ash", D_ASH)
			sm.set_shader_parameter("cap_ash", CAP_ASH)
		else:
			for pair in [["grass", "grass_lush", "ground/"], ["forest", "forest_floor", "ground/"], ["path", "dirt_trail", "ground/"], ["mud", "mud_wetland", "ground/"]]:
				sm.set_shader_parameter("t_" + pair[0], tex(pair[2] + pair[1]))
				sm.set_shader_parameter("m_" + pair[0], _m(pair[1]))
				sm.set_shader_parameter("g_" + pair[0], _g(pair[1]))
		m = sm
	_mats[key] = m
	return m


## A ground mesh over [origin, origin + size] with n.x by n.y cells. f(x, z) -> [height, tint Color, w_path, w_mud, w_forest, w_ash (optional)].
static func build_ground(origin: Vector2, size: Vector2, n: Vector2i, f: Callable) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var step := Vector2(size.x / n.x, size.y / n.y)
	for iz in n.y + 1:
		for ix in n.x + 1:
			var x := origin.x + ix * step.x
			var z := origin.y + iz * step.y
			var r: Array = f.call(x, z)
			st.set_color(r[1])
			st.set_uv(Vector2(r[2], r[3]))
			st.set_uv2(Vector2(r[4], r[5] if r.size() > 5 else 0.0))
			st.add_vertex(Vector3(x, r[0], z))
	for iz in n.y:
		for ix in n.x:
			var a := iz * (n.x + 1) + ix
			for i in [a, a + 1, a + n.x + 1, a + 1, a + n.x + 2, a + n.x + 1]:
				st.add_index(i)
	st.generate_normals()
	return st.commit()


## ---- water: two scrolling samples, deep to shallow by a baked shore factor -----------------------------
## Vertex data (build_water): UV.x = shallow factor 0 (deep) .. 1 (at the shore). No depth or screen texture.
static func _water_code(t: int) -> String:
	var head := "shader_type spatial;\nrender_mode specular_disabled, cull_back;\n" + COMMON + """
varying vec3 wp;
uniform vec3 deep_col;
uniform vec3 shallow_col;
uniform vec3 fog_col;
uniform float tile = 4.0;
uniform float tile2 = 6.5;
uniform float a_deep = 0.80;
uniform float a_shallow = 0.72;
uniform float time_override = -1.0;
uniform float ripple_k = 0.15;
uniform sampler2D ripple""" + SAMP_REPEAT + """;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
"""
	var body := """
	float T = time_override < 0.0 ? TIME : time_override;
	vec2 p = wp.xz;
	// Two ripple samples turned to different non-right angles against each other and to the texture's own diagonal
	// (its lines run at 45 degrees; two samples 20 degrees apart made a regular crosshatch, which stretched to horizontal
	// stripes on far water). The normals are turned back with their samples. Ripples fade out by 15 m from the camera.
	const float A1 = -0.35;
	const float A2 = 0.12;
	mat2 r1 = mat2(vec2(cos(A1), -sin(A1)), vec2(sin(A1), cos(A1)));
	mat2 r2 = mat2(vec2(cos(A2), -sin(A2)), vec2(sin(A2), cos(A2)));
	vec2 d1 = vec2(0.94, 0.34) * 0.04 * T;
	vec2 d2 = vec2(0.77, 0.64) * 0.025 * T;
	vec2 pr = r2 * (p * vec2(1.0, 1.0));
	vec2 pq = r1 * p;
	float dist = length(VERTEX);
	float rf = 1.0 - smoothstep(6.0, 15.0, dist);
	vec2 n1 = (texture(ripple, (pq + d1) / 3.0).rg - 0.5) * 2.0 * r1;
	vec2 n2 = (texture(ripple, (pr + d2) / 4.7).ba - 0.5) * 2.0 * r2;
	vec2 nxy = (n1 + n2) * ripple_k * rf;
	vec3 nw = normalize(vec3(-nxy.x, 1.0, -nxy.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	// Shallow tint only at the shore: the baked factor reaches 1 at the shore line and 0 about a metre out.
	float s = smoothstep(0.35, 0.95, clamp(UV.x, 0.0, 1.0));
	float farf = smoothstep(10.0, 40.0, dist);
	ALPHA = mix(mix(a_deep, a_shallow, s), 0.92, farf);
	ROUGHNESS = mix(0.10, 0.35, farf);
	METALLIC = 0.0;
	SPECULAR = 0.25 * (1.0 - 0.8 * farf);
"""
	if t == GRAIN:
		return head + """
uniform sampler2D tex_b""" + SAMP_REPEAT + """;
uniform float d = 0.15;
void fragment() {
""" + body + """
	vec2 w1 = (pq + d1) / tile;
	vec2 w2 = (pr + d2) / tile2;
	vec4 b1 = texture(tex_b, w1); vec4 b2 = texture(tex_b, w2);
	float gf = 1.0 - smoothstep(25.0, 60.0, dist);   // far water: the mean, not a pattern
	float g_deep = mix(0.5, both(b1.b, b2.b), gf);
	float g_sh = mix(0.5, both(b1.g, b2.g), gf);
	ALBEDO = mix(ramp(deep_col, g_deep, d, fog_col), ramp(shallow_col, g_sh, d, fog_col), s) * (1.0 - 0.12 - 0.40 * farf);
}
"""
	return head + """
uniform sampler2D t_deep""" + SAMP_REPEAT_SRGB + """;
uniform sampler2D t_shallow""" + SAMP_REPEAT_SRGB + """;
uniform vec3 m_deep; uniform vec3 m_shallow; uniform vec3 g_deep; uniform vec3 g_shallow;
void fragment() {
""" + body + """
	vec2 w1 = (p + d1) / tile;
	vec2 w2 = (pr + d2) / tile2;
	vec3 cd = 0.5 * (texture(t_deep, w1).rgb + texture(t_deep, w2).rgb);
	vec3 cs = texture(t_shallow, w1).rgb;
	ALBEDO = mix(grade(cd, m_deep, deep_col, g_deep), grade(cs, m_shallow, shallow_col, g_shallow), s);
}
"""


## pal: {deep: Color, shallow: Color, fog: Color}. FLAT is today's translucent plane.
static func water(t: int, pal: Dictionary) -> Material:
	var key := "water|%d|%s|%s" % [t, pal.deep.to_html(), pal.shallow.to_html()]
	if _mats.has(key):
		return _mats[key]
	var m: Material
	var a: Texture2D = tex("packed/ripple") if t != FLAT else null
	if t == FLAT or a == null:
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(0.12, 0.32, 0.42, 0.72)
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.metallic = 0.5
		fm.roughness = 0.08
		m = fm
	else:
		var sm := _sm(_shader("water%d" % t, _water_code(t)))
		sm.set_shader_parameter("ripple", a)
		sm.set_shader_parameter("deep_col", _vec(pal.deep))
		sm.set_shader_parameter("shallow_col", _vec(pal.shallow))
		sm.set_shader_parameter("fog_col", _vec(pal.fog))
		sm.set_shader_parameter("tile", TILE_WATER)
		sm.set_shader_parameter("tile2", TILE_WATER_2)
		if t == GRAIN:
			sm.set_shader_parameter("tex_b", tex("packed/terrain_b"))
			sm.set_shader_parameter("d", D_WATER)
		else:
			sm.set_shader_parameter("t_deep", tex("water/water_deep"))
			sm.set_shader_parameter("t_shallow", tex("water/water_shallow"))
			sm.set_shader_parameter("m_deep", _m("water_deep"))
			sm.set_shader_parameter("m_shallow", _m("water_shallow"))
			sm.set_shader_parameter("g_deep", _g("water_deep"))
			sm.set_shader_parameter("g_shallow", _g("water_shallow"))
		m = sm
	_mats[key] = m
	return m


## A water surface over [origin, origin + size] at height y. f(x, z) -> shallow factor 0..1.
static func build_water(origin: Vector2, size: float, n: int, y: float, f: Callable) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := size / n
	for iz in n + 1:
		for ix in n + 1:
			var x := origin.x + ix * step
			var z := origin.y + iz * step
			st.set_uv(Vector2(f.call(x, z), 0.0))
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(x, y, z))
	for iz in n:
		for ix in n:
			var a := iz * (n + 1) + ix
			for i in [a, a + 1, a + n + 1, a + 1, a + n + 2, a + n + 1]:
				st.add_index(i)
	return st.commit()


## ---- triplanar solids: walls, wood, bark, canopy ---------------------------------------------------------
## Object-space triplanar (a rotated house keeps its courses level), texture-up = object up. `hard` picks the
## dominant axis (1 read: right for boxes); otherwise three reads blended by the normal (trunks, lathe canopies).
static func _tri_code(t: int, hard: bool) -> String:
	var head := "shader_type spatial;\nrender_mode specular_disabled;\n" + COMMON + """
varying vec3 lp;
varying vec3 ln;
varying vec3 wp;
uniform vec3 tint;
uniform vec3 fog_col;
uniform float tile = 4.0;
uniform float k_rough = 0.9;
void vertex() { lp = VERTEX; ln = NORMAL; wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
"""
	var w := "vec3 w = abs(ln);\n"
	var sample_gr := ""
	var sample_src := ""
	if hard:
		w += "\tbool bx = w.x > w.y && w.x > w.z;\n\tbool by = !bx && w.y > w.z;\n\tvec2 uvh = (bx ? lp.zy : (by ? lp.xz : lp.xy)) / tile;\n"
		sample_gr = "float g = dot(texture(tex, uvh), mask);\n"
		sample_src = "vec3 c = texture(tex, uvh).rgb;\n"
	else:
		w += "\tw = pow(w, vec3(4.0)); w /= (w.x + w.y + w.z);\n"
		sample_gr = "float g = dot(texture(tex, lp.zy / tile), mask) * w.x + dot(texture(tex, lp.xz / tile), mask) * w.y + dot(texture(tex, lp.xy / tile), mask) * w.z;\n"
		sample_src = "vec3 c = texture(tex, lp.zy / tile).rgb * w.x + texture(tex, lp.xz / tile).rgb * w.y + texture(tex, lp.xy / tile).rgb * w.z;\n"
	if t == GRAIN:
		return head + "uniform sampler2D tex" + SAMP_REPEAT + ";\nuniform vec4 mask;\nuniform float d = 0.25;\nvoid fragment() {\n\t" + w + "\t" + sample_gr + """
	ALBEDO = ramp(tint, g, d, fog_col) * macro(wp.xz);
	ROUGHNESS = k_rough;
}
"""
	return head + "uniform sampler2D tex" + SAMP_REPEAT_SRGB + ";\nuniform vec3 mean_c;\nuniform vec3 grd;\nvoid fragment() {\n\t" + w + "\t" + sample_src + """
	ALBEDO = grade(c, mean_c, tint, grd) * macro(wp.xz);
	ROUGHNESS = k_rough;
}
"""


## kind: stone, cobble, planks, bark_dec, bark_pine, leaf_broad, leaf_pine.
const SOLIDS := {
	"stone": {"pack": "packed/build", "mask": Vector4(1, 0, 0, 0), "src": "walls/castle_stone", "key": "castle_stone", "tile": TILE_STONE, "d": D_STONE, "hard": true},
	"cobble": {"pack": "packed/terrain_b", "mask": Vector4(0, 0, 0, 1), "src": "ground/cobblestone", "key": "cobblestone", "tile": TILE_STONE, "d": D_COBBLE, "hard": true},
	"planks": {"pack": "packed/build", "mask": Vector4(0, 1, 0, 0), "src": "wood/planks", "key": "planks", "tile": TILE_PLANKS, "d": D_WOOD, "hard": true},
	"bark_pine": {"pack": "packed/build", "mask": Vector4(0, 0, 1, 0), "src": "bark/bark_pine", "key": "bark_pine", "tile": TILE_BARK, "d": D_WOOD, "hard": false},
	"bark_dec": {"pack": "packed/build", "mask": Vector4(0, 0, 0, 1), "src": "bark/bark_deciduous", "key": "bark_deciduous", "tile": TILE_BARK, "d": D_WOOD, "hard": false},
	"leaf_broad": {"pack": "packed/foliage", "mask": Vector4(1, 0, 0, 0), "src": "foliage/leaf_broadleaf", "key": "leaf_broadleaf", "tile": TILE_LEAF, "d": D_LEAF, "hard": false},
	"leaf_pine": {"pack": "packed/foliage", "mask": Vector4(0, 1, 0, 0), "src": "foliage/leaf_evergreen", "key": "leaf_evergreen", "tile": TILE_LEAF, "d": D_LEAF, "hard": false},
}


## d_scale: the Art Bible's "half d" for kit buildings is passed as 0.5.
static func solid(kind: String, t: int, tint: Color, fog: Color, d_scale := 1.0) -> Material:
	var key := "solid|%s|%d|%s|%s|%s" % [kind, t, tint.to_html(), fog.to_html(), d_scale]
	if _mats.has(key):
		return _mats[key]
	var def: Dictionary = SOLIDS[kind]
	var m: Material
	var a: Texture2D = tex(def.pack if t == GRAIN else def.src) if t != FLAT else null
	if t == FLAT or a == null:
		m = flat_mat(tint)
	else:
		var sm := _sm(_shader("tri%d%s" % [t, "h" if def.hard else "b"], _tri_code(t, def.hard)))
		sm.set_shader_parameter("tex", a)
		sm.set_shader_parameter("tint", _vec(tint))
		sm.set_shader_parameter("fog_col", _vec(fog))
		sm.set_shader_parameter("tile", def.tile)
		if t == GRAIN:
			sm.set_shader_parameter("mask", def.mask)
			sm.set_shader_parameter("d", def.d * d_scale)
		else:
			sm.set_shader_parameter("mean_c", _m(def.key))
			sm.set_shader_parameter("grd", _g(def.key))
		m = sm
	_mats[key] = m
	return m


## ---- foliage cutout cards: alpha scissor, no blending ----------------------------------------------------
static func _card_code(t: int) -> String:
	var head := "shader_type spatial;\nrender_mode specular_disabled, cull_disabled;\n" + COMMON + """
uniform vec3 tint;
uniform vec3 fog_col;
"""
	if t == GRAIN:
		return head + "uniform sampler2D tex" + SAMP_REPEAT + """;
uniform vec4 lmask;
uniform vec4 amask;
uniform float d = 0.25;
void fragment() {
	vec4 v = texture(tex, UV);
	ALPHA = dot(v, amask);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALBEDO = ramp(tint, dot(v, lmask), d, fog_col);
	ROUGHNESS = 1.0;
}
"""
	return head + "uniform sampler2D tex" + SAMP_REPEAT_SRGB + """;
uniform vec3 mean_c;
uniform vec3 grd;
void fragment() {
	vec4 v = texture(tex, UV);
	ALPHA = v.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALBEDO = grade(v.rgb, mean_c, tint, grd);
	ROUGHNESS = 1.0;
}
"""


## kind: leaf_broad or leaf_pine. Use on QuadMesh cards (UV 0..1).
static func cards(kind: String, t: int, tint: Color, fog: Color) -> Material:
	var key := "cards|%s|%d|%s" % [kind, t, tint.to_html()]
	if _mats.has(key):
		return _mats[key]
	var def: Dictionary = SOLIDS[kind]
	var broad := kind == "leaf_broad"
	var m: Material
	var a: Texture2D = tex(def.pack if t == GRAIN else def.src) if t != FLAT else null
	if t == FLAT or a == null:
		m = null
	else:
		var sm := _sm(_shader("card%d" % t, _card_code(t)))
		sm.set_shader_parameter("tex", a)
		sm.set_shader_parameter("tint", _vec(tint))
		sm.set_shader_parameter("fog_col", _vec(fog))
		if t == GRAIN:
			sm.set_shader_parameter("lmask", Vector4(1, 0, 0, 0) if broad else Vector4(0, 1, 0, 0))
			sm.set_shader_parameter("amask", Vector4(0, 0, 1, 0) if broad else Vector4(0, 0, 0, 1))
			sm.set_shader_parameter("d", D_LEAF)
		else:
			sm.set_shader_parameter("mean_c", _m(def.key))
			sm.set_shader_parameter("grd", _g(def.key))
		m = sm
	_mats[key] = m
	return m


## ---- fighter armour: palette colour plus a small tiling detail overlay ----------------------------------
## Object-space (rest pose) coordinates, so the overlay rides with each rigid part and does not swim. Keeps the
## fighters' rim and self-light exactly as placeholder_visual.gd's _metal() sets them.
static func _armour_code(t: int) -> String:
	var head := "shader_type spatial;\n" + "render_mode specular_disabled;\n" + COMMON + """
varying vec3 lp;
varying vec3 ln;
uniform vec3 base_col;
uniform vec3 emit_col;
uniform vec3 fog_col;
uniform float tile = 0.5;
uniform float metal = 0.35;
uniform float rough = 0.45;
uniform float rim_amt = 0.9;
uniform float rim_tint = 0.3;
void vertex() { lp = VERTEX; ln = NORMAL; }
"""
	var tri := """
	vec3 w = pow(abs(ln), vec3(4.0)); w /= (w.x + w.y + w.z);
"""
	if t == GRAIN:
		return head + "uniform sampler2D tex" + SAMP_REPEAT + """;
uniform vec4 mask;
uniform float d = 0.3;
void fragment() {""" + tri + """
	float g = dot(texture(tex, lp.zy / tile), mask) * w.x + dot(texture(tex, lp.xz / tile), mask) * w.y + dot(texture(tex, lp.xy / tile), mask) * w.z;
	ALBEDO = ramp(base_col, g, d, fog_col);
	METALLIC = metal;
	ROUGHNESS = clamp(rough + (g - 0.5) * 0.24, 0.05, 1.0);
	RIM = rim_amt;
	RIM_TINT = rim_tint;
	EMISSION = emit_col;
}
"""
	return head + "uniform sampler2D tex" + SAMP_REPEAT_SRGB + """;
uniform vec3 mean_c;
uniform vec3 grd;
void fragment() {""" + tri + """
	vec3 c = texture(tex, lp.zy / tile).rgb * w.x + texture(tex, lp.xz / tile).rgb * w.y + texture(tex, lp.xy / tile).rgb * w.z;
	float l = dot(c, LUMA);
	ALBEDO = grade(c, mean_c, base_col, grd);
	METALLIC = metal;
	ROUGHNESS = clamp(rough + (l / max(dot(mean_c, LUMA), 0.01) - 1.0) * 0.12, 0.05, 1.0);
	RIM = rim_amt;
	RIM_TINT = rim_tint;
	EMISSION = emit_col;
}
"""


const ARMOUR := {
	"steel": {"mask": Vector4(1, 0, 0, 0), "src": "armour/steel_plate", "key": "steel_plate"},
	"chain": {"mask": Vector4(0, 1, 0, 0), "src": "armour/chainmail", "key": "chainmail"},
	"gambeson": {"mask": Vector4(0, 0, 1, 0), "src": "armour/gambeson", "key": "gambeson"},
}


## A material that replaces a fighter's armour StandardMaterial3D `old` (same colour, metal, rim, self-light).
## kind: steel, chain or gambeson. d: D_HERO or D_ENEMY. Returns `old` unchanged when FLAT or not allowed.
static func armour(kind: String, t: int, old: StandardMaterial3D, d: float, fog: Color) -> Material:
	if t == FLAT:
		return old
	var def: Dictionary = ARMOUR[kind]
	var a: Texture2D = tex("packed/detail" if t == GRAIN else def.src)
	if a == null:
		return old
	var sm := _sm(_shader("armour%d" % t, _armour_code(t)))
	sm.set_shader_parameter("tex", a)
	sm.set_shader_parameter("base_col", _vec(old.albedo_color))
	sm.set_shader_parameter("emit_col", _vec(old.emission) * old.emission_energy_multiplier)
	sm.set_shader_parameter("fog_col", _vec(fog))
	sm.set_shader_parameter("tile", TILE_ARMOUR)
	sm.set_shader_parameter("metal", old.metallic)
	sm.set_shader_parameter("rough", old.roughness)
	sm.set_shader_parameter("rim_amt", old.rim)
	sm.set_shader_parameter("rim_tint", old.rim_tint)
	if t == GRAIN:
		sm.set_shader_parameter("mask", def.mask)
		sm.set_shader_parameter("d", d)
	else:
		sm.set_shader_parameter("mean_c", _m(def.key))
		sm.set_shader_parameter("grd", _g(def.key))
	return sm


## ---- banner cloth: used once (UV placed), never tiled; sways like the fighters' cloth ------------------
static func _banner_code(t: int) -> String:
	var head := "shader_type spatial;\nrender_mode cull_disabled, specular_disabled;\n" + COMMON + """
uniform vec3 dark_col;
uniform vec3 light_col;
uniform float sway = 0.05;
uniform float time_override = -1.0;
// The banner is 0.8 x 2.2 m: show the 512 px cloth once, cropped to that aspect (never tiled), not stretched.
const vec2 CROP = vec2(1.0, 0.364);
const vec2 OFF = vec2(0.0, 0.30);
void vertex() {
	float T = time_override < 0.0 ? TIME : time_override;
	float w = UV.y * UV.y;
	VERTEX.z += (sin(T * 1.9 + UV.x * 4.0 + UV.y * 3.0) * sway) * w;
	VERTEX.x += sin(T * 1.4 + UV.y * 5.0) * sway * 0.4 * w;
}
"""
	if t == GRAIN:
		return head + "uniform sampler2D tex" + SAMP_REPEAT.replace(", repeat_enable", ", repeat_disable") + """;
void fragment() {
	float g = texture(tex, OFF + UV * CROP).a;
	ALBEDO = mix(dark_col, light_col, g);
	ROUGHNESS = 0.9;
}
"""
	return head + "uniform sampler2D tex" + SAMP_REPEAT_SRGB.replace(", repeat_enable", ", repeat_disable") + """;
uniform vec3 mean_c;
uniform vec3 grd;
void fragment() {
	vec3 c = texture(tex, OFF + UV * CROP).rgb;
	ALBEDO = grade(c, mean_c, dark_col, grd);
	ROUGHNESS = 0.9;
}
"""


## dark: the heraldry colour (GRAIN: dark end of the ramp; SOURCE: the colour the cloth is graded toward);
## light: Brass (GRAIN only).
static func banner(t: int, dark: Color, light: Color) -> Material:
	var key := "banner|%d|%s|%s" % [t, dark.to_html(), light.to_html()]
	if _mats.has(key):
		return _mats[key]
	var m: Material
	var a: Texture2D = tex("packed/detail" if t == GRAIN else "cloth/heraldic_cloth") if t != FLAT else null
	if t == FLAT or a == null:
		m = flat_mat(dark, false, 0.9)
	else:
		var sm := _sm(_shader("banner%d" % t, _banner_code(t)))
		sm.set_shader_parameter("tex", a)
		sm.set_shader_parameter("dark_col", _vec(dark))
		sm.set_shader_parameter("light_col", _vec(light))
		if t == SOURCE:
			sm.set_shader_parameter("mean_c", _m("heraldic_cloth"))
			sm.set_shader_parameter("grd", _g("heraldic_cloth"))
		m = sm
	_mats[key] = m
	return m


## Free everything cached (the look test calls this when it ends; textures are released with their last user).
static func clear() -> void:
	_mats.clear()
	_shaders.clear()
	_tex.clear()
	loaded.clear()
