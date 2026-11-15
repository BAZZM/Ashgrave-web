class_name Tiers
extends RefCounted

## Art Bible section 3, tower rows. "amb" is the flat ambient colour of the tier (new in G1);
## "light" is the tier's key and torch colour (Foundry and Pyre Court were moved to the bible's).
const THEMES := {
	1: {"name": "Ash Gate", "amb": Color("#5A4442"), "stone": Color(0.24, 0.22, 0.23), "light": Color(1.0, 0.55, 0.25), "sky_top": Color(0.03, 0.03, 0.07), "sky_low": Color(0.32, 0.18, 0.14), "fog": Color(0.13, 0.09, 0.09), "wall": 4.5, "special": ""},
	2: {"name": "The Cisterns", "amb": Color("#2E4A4D"), "stone": Color(0.16, 0.22, 0.24), "light": Color(0.4, 0.85, 0.8), "sky_top": Color(0.01, 0.03, 0.05), "sky_low": Color(0.08, 0.2, 0.22), "fog": Color(0.05, 0.12, 0.13), "wall": 5.0, "special": "water"},
	3: {"name": "The Foundry", "amb": Color("#5A3326"), "stone": Color(0.2, 0.15, 0.13), "light": Color("#FF5514"), "sky_top": Color(0.05, 0.02, 0.01), "sky_low": Color(0.45, 0.16, 0.05), "fog": Color(0.2, 0.08, 0.04), "wall": 5.0, "special": "forge"},
	4: {"name": "The Rookery", "amb": Color("#5A5F7A"), "stone": Color(0.3, 0.31, 0.36), "light": Color(0.7, 0.8, 1.0), "sky_top": Color(0.05, 0.08, 0.2), "sky_low": Color(0.45, 0.4, 0.5), "fog": Color(0.2, 0.2, 0.28), "wall": 1.1, "special": "open"},
	5: {"name": "The Pyre Court", "amb": Color("#4A2E2A"), "stone": Color(0.14, 0.12, 0.14), "light": Color("#FFB84D"), "sky_top": Color(0.04, 0.01, 0.02), "sky_low": Color(0.5, 0.2, 0.08), "fog": Color(0.16, 0.07, 0.05), "wall": 6.0, "special": "throne"},
}

const LESSER_NAMES := ["Ash Thrall", "Cistern Lurker", "Forge Hand", "Rook Sentry", "Pyre Guard"]
const ENTRANCE := Vector3(0, 0, 2.0)
const EXIT := Vector3(0, 0, -44.5)


static func mirror(tier: int) -> float:
	return 1.0 if tier % 2 == 1 else -1.0


static func rects(tier: int) -> Array:
	var m := mirror(tier)
	var out := [
		_r(0, 0, 14, 12),
		_r(0, -10, 4, 9),
		_r(0, -18, 12, 10),
		_r(-8 * m, -18, 6, 4), _r(-14 * m, -18, 10, 9),
		_r(8 * m, -18, 6, 4), _r(14 * m, -18, 10, 9),
		_r(0, -27, 4, 9),
		_r(0, -38, 18, 15),
		_r(9 * m, 1, 6, 3), _r(13.5 * m, 1, 5, 6),
	]
	match tier:
		2:
			out.append(_r(4.5 * m, -8, 6, 3))
			out.append(_r(8.5 * m, -10, 4, 10))
		3:
			out.append(_r(-9 * m, -36, 6, 3))
			out.append(_r(-14 * m, -36, 6, 7))
			out.append(_r(-4.5 * m, -27, 6, 3))
			out.append(_r(-8.5 * m, -27, 5, 9))
		4:
			out.append(_r(11 * m, -36, 6, 3))
			out.append(_r(15.5 * m, -36, 6, 6))
			out.append(_r(-9 * m, -36, 6, 3))
			out.append(_r(-14 * m, -36, 6, 7))
			out.append(_r(-14 * m, -27, 3, 13))
		5:
			out.append(_r(0, -38, 26, 12))
			out.append(_r(-9 * m, -36, 6, 3))
			out.append(_r(-14 * m, -36, 6, 7))
			out.append(_r(9 * m, -1, 6, 3))
	return out


static func _r(cx: float, cz: float, w: float, d: float) -> Rect2:
	return Rect2(cx - w * 0.5, cz - d * 0.5, w, d)


static func entities(tier: int) -> Array:
	var m := mirror(tier)
	var p := "t%d_" % tier
	var out := [
		{"id": p + "guardian", "type": "foe", "kind": "guardian", "pos": Vector3(0, 0, -40)},
		{"id": p + "elite", "type": "foe", "kind": "elite", "pos": Vector3(-15 * m, 0, -18)},
		{"id": p + "lesser1", "type": "foe", "kind": "lesser", "pos": Vector3(0, 0, -11)},
		{"id": p + "smith", "type": "smith", "pos": Vector3(16 * m, 0, -19.5)},
		{"id": p + "brazier", "type": "brazier", "pos": Vector3(12 * m, 0, -15.5)},
		{"id": p + "chest1", "type": "chest", "pos": Vector3(-17.5 * m, 0, -20.5), "gold": 60 * tier},
		{"id": p + "relic", "type": "relic", "pos": Vector3(14 * m, 0, 2)},
		{"id": p + "exit", "type": "exit", "pos": EXIT},
	]
	out.append({"id": p + "entry", "type": "entry", "pos": Vector3(0, 0, 5.6)})
	if tier >= 2:
		out.append({"id": p + "lesser2", "type": "foe", "kind": "lesser", "pos": Vector3(3, 0, -27)})
	if tier >= 3:
		out.append({"id": p + "chest2", "type": "chest", "pos": Vector3(-15 * m, 0, -37), "gold": 90 * tier, "item": ["", "", "duelists_hood", "watchers_helm", "oath_ring"][tier - 1]})
	if tier >= 4:
		out.append({"id": p + "lesser3", "type": "foe", "kind": "lesser", "pos": Vector3(-3, 0, -17)})
	if tier == 2:
		out.append({"id": p + "chest2", "type": "chest", "pos": Vector3(8.5 * m, 0, -13.5), "gold": 110, "item": "ember_ring"})
	if tier == 3:
		out.append({"id": p + "lesser3", "type": "foe", "kind": "lesser", "pos": Vector3(-8.5 * m, 0, -27)})
	if tier == 4:
		out.append({"id": p + "chest3", "type": "chest", "pos": Vector3(16.5 * m, 0, -36), "gold": 260, "item": "throwing_knives"})
	return out
