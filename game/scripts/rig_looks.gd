extends RefCounted
## Maps the game's own look data to what RigVisual shows (docs/RIG_PLAN.md section 2, docs/RIG_R2.md). No class_name: loaded by
## rig_visual.gd, so a game that never makes a RigVisual never loads this.
##
## Input: the hero's cfg (FighterVisual.hero_cfg(): Items.hero_look's style, body, accent, over, plus `eq`, the equipped ids)
## and whether a shield is carried. Output: gear names (nodes of knight.glb, meshes of gear.glb, or code-built fallbacks the
## visual makes itself), colours for the shader and a few flags. Every key has a default, so a cfg without `eq` still maps
## (the weapon is then read from the blade length in `over`).
##
## KayKit meshes used: 1H_Sword, 2H_Sword, Badge/Round/Rectangle_Shield, Knight_Helmet, Knight_Cape (knight.glb); Dagger
## and Crossbow (gear.glb, from the Rogue's pack). Code-built where KayKit has no mesh: the Watcher's great helm, the
## Duelist's hood (the Rogue's hooded head is not packed yet), shoulder spikes, the throwing-knife belt, the spell orb.

const STEEL_LUM := 0.65  # the luminance of the worn plate's steel body colour (items.gd hero_look)

## Weapon family -> gear. One-handed clips for every weapon (owner question 4, orchestrator's call while the owner is away).
const SWORDS := {
	"longsword": {"sword": "1H_Sword", "scale": 1.0, "back": false},
	"twin": {"sword": "Dagger", "scale": 1.0, "back": true},
	"greatsword": {"sword": "2H_Sword", "scale": 1.0, "back": false},
}
## Shield item -> gear: Badge_Shield for the heater, Round_Shield for the buckler (smaller), Rectangle_Shield for the tower shield (bigger).
const SHIELDS := {
	"heater": {"shield": "Badge_Shield", "scale": 1.0},
	"buckler": {"shield": "Round_Shield", "scale": 0.8},
	"tower_shield": {"shield": "Rectangle_Shield", "scale": 1.25},
}
const SHIELD_OF_KIND := {"heater": "heater", "buckler": "buckler", "tower": "tower_shield"}


static func map(cfg: Dictionary, has_shield: bool) -> Dictionary:
	var over: Dictionary = cfg.get("over", {})
	var eq: Dictionary = cfg.get("eq", {})
	var body: Color = cfg.get("body", Color(0.62, 0.65, 0.72))
	var accent: Color = cfg.get("accent", Color(0.15, 0.3, 0.75))
	var out := {"base": "knight"}

	# Weapon: by item when the equipped ids came with the cfg, else by blade length.
	var family := "longsword"
	var wid: String = eq.get("weapon", "")
	if wid != "" and Items.WEAPONS.has(wid):
		family = Items.WEAPONS[wid].family
	elif over.has("blade"):
		var len_: float = (over.blade as Array)[0]
		family = "greatsword" if len_ > 1.3 else ("twin" if len_ < 0.95 else "longsword")
	var sw: Dictionary = SWORDS[family]
	out.sword = sw.sword
	out.sword_scale = sw.scale
	out.back_blade = sw.back
	out.weapon_tint = Color.WHITE.lerp(over.get("blade_tint", Color(0.86, 0.88, 0.92)), 0.45)  # a tint multiplies the atlas steel, so soften it
	# Rune glow of an elemental or upgraded weapon: the code hero's rune colour, as an emission on the blade's steel.
	out.glow = Color.BLACK
	if over.get("runes", false):
		var c: Color = over.get("rune_color", Color(1.0, 0.9, 0.6))
		out.glow = c * (0.15 + 0.07 * float(over.get("rune_power", 2.0)))

	# Shield.
	var sid: String = eq.get("shield", "")
	if sid == "" or not SHIELDS.has(sid):
		sid = SHIELD_OF_KIND.get(over.get("shield_kind", "heater"), "heater")
	out.shield = SHIELDS[sid].shield if has_shield else ""
	out.shield_scale = SHIELDS[sid].scale

	# Helm. Every helm is KayKit's sallet for now: the code-built great helm and hood were closed shapes (hood hid the face, helm
	# a blank capsule) and wait for a later stage. `helm_style` records what the hero wears for that stage.
	var hid: String = eq.get("helm", "")
	var helm := "Knight_Helmet"
	out.helm_style = "sallet"
	if hid == "watchers_helm" or over.get("helm", "") == "great":
		out.helm_style = "great"
	elif hid == "duelists_hood" or (hid == "" and over.get("half_cape", false) and not over.get("slim", false)):
		out.helm_style = "hood"
	out.helmet = helm
	out.fin = bool(over.get("fin", false))

	# Body. The knight's plates take the steel tint: body colour steers the hue and, for the blackened plate, darkens. Armour
	# KayKit has no body for (the Rogue's leathers) wears the same plates in the leather colour, until R4 packs the Rogue.
	var bn := body.lightened(0.25)
	# Steel-coloured bodies steer the hue a little; a coloured body (the Duelist's brown leathers) takes its colour.
	var sat := (maxf(maxf(body.r, body.g), body.b) - minf(minf(body.r, body.g), body.b)) / maxf(maxf(body.r, body.g), maxf(body.b, 0.01))
	var hue := Color.WHITE.lerp(bn / maxf(maxf(bn.r, bn.g), maxf(bn.b, 0.01)), clampf(0.35 + sat * 1.5, 0.35, 1.0))
	var lum := body.r * 0.2126 + body.g * 0.7152 + body.b * 0.0722
	var k := 1.0 - 0.55 * clampf(1.0 - lum / STEEL_LUM, 0.0, 1.0)
	out.metal = Color(hue.r * k, hue.g * k, hue.b * k)
	out.cloth = accent
	out.bulk = float(over.get("bulk", 1.0))
	out.spikes = bool(over.get("spikes", false))
	out.cape = float(over.get("cape", 1.0)) > 0.01 and not over.get("half_cape", false)

	# Back and belt items.
	out.back_crossbow = bool(over.get("back_bow", false))  # the Hunter's Bow is shown as a crossbow
	out.knife_belt = bool(over.get("knife_belt", false))
	out.focus = over.get("focus", Color.BLACK)
	return out
