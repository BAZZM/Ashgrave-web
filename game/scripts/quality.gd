extends RefCounted
## Quality levels: what each level turns off or lowers. Pure data and appliers: it does not read the
## save (Run does: Run.quality_level(), Run.quality_allows("textures")), so there is no load cycle.
##
## To add a level, add a row to LEVELS. To add a switch, name it in every row (later lanes: "textures",
## "models" already exist; gate loading on Run.quality_allows(name) so a gated resource is never loaded,
## not loaded and hidden). A name missing from a row is allowed in full and refused everywhere else, so a typo
## in a gate fails closed. Gated features are decided when a scene loads and are never loaded or unloaded
## mid-scene; a lane that wants to react to a change reads Run.quality_rev (it counts level changes).

const LEVELS := {
	"full": {
		"label": "Full", "textures": true, "models": true, "shadows": true,
		"scale_k": 1.0, "radiance": Sky.RADIANCE_SIZE_256, "atlas": 1024, "dpr_cap": 2.0,
	},
	"safe": {
		"label": "Safe", "textures": false, "models": false, "shadows": false,
		"scale_k": 0.75, "radiance": Sky.RADIANCE_SIZE_64, "atlas": 0, "dpr_cap": 1.5,
	},
}
const DEFAULT := "full"


static func valid(level: String) -> bool:
	return LEVELS.has(level)


static func allows(level: String, feature: String) -> bool:
	var row: Dictionary = LEVELS.get(level, LEVELS["safe"])
	return bool(row.get(feature, level == DEFAULT))


static func value(level: String, key: String, fallback: Variant) -> Variant:
	var row: Dictionary = LEVELS.get(level, LEVELS["safe"])
	return row.get(key, fallback)


## Shadows on a light follow the level, and come back when the level does: the light's own wish is
## remembered the first time it is seen.
static func tune_light(l: Light3D, level: String) -> void:
	if not l.has_meta("q_shadow"):
		l.set_meta("q_shadow", l.shadow_enabled)
	l.shadow_enabled = bool(l.get_meta("q_shadow")) and allows(level, "shadows")


static func tune_sky(sky: Sky, level: String) -> void:
	if sky != null:
		sky.radiance_size = value(level, "radiance", Sky.RADIANCE_SIZE_256)


## Settings that live on the viewport and the engine (web only), then every light and sky already in
## the tree. Safe to call again whenever the level changes.
static func apply(vp: Viewport, level: String) -> void:
	if OS.has_feature("web"):
		# The shorter side: a load in portrait (before the phone is turned) must not pick a lower scale.
		var sz := DisplayServer.window_get_size()
		var px := float(mini(sz.x, sz.y))
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.scaling_3d_scale = clampf(clampf(640.0 / maxf(px, 1.0), 0.45, 1.0) * float(value(level, "scale_k", 1.0)), 0.3, 1.0)
		# With shadows off the atlas is released (size 0), not left allocated. The pixel-ratio cap (dpr_cap) is read by
		# index.html before the engine starts; a level change reaches it at the next launch.
		RenderingServer.directional_shadow_atlas_set_size(int(value(level, "atlas", 1024)), true)
	var tree := vp.get_tree()
	if tree == null:
		return
	var stack: Array = [tree.root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is Light3D:
			tune_light(n as Light3D, level)
		elif n is WorldEnvironment and n.environment != null:
			tune_sky(n.environment.sky, level)
