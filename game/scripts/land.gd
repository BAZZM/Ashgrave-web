class_name Land
extends RefCounted

const X_MAX := 220.0
const Z_MIN := -262.0
const Z_MAX := 200.0
const CHUNK := 40.0
const VILLAGE := Vector2(0, 20)
const VILLAGE_R := 44.0
const START := Vector3(0, 0, 34)
const TOWER := Vector2(0, -236)
const TOWER_GATE := Vector2(0, -212)
const LAKE := Vector2(126, 132)
const LAKE_R := 38.0
const BRIDGE := Rect2(66, -6, 28, 6)
const STONES_Z := -150.0
const WATER_Y := -0.55

const ROADS := [
	[Vector2(0, 20), Vector2(0, -210)],
	[Vector2(0, 16), Vector2(60, -3), Vector2(100, -3), Vector2(126, -14)],
	[Vector2(126, -14), Vector2(132, -90), Vector2(124, -170)],
	[Vector2(0, 20), Vector2(-70, 6), Vector2(-150, -10)],
	[Vector2(0, 24), Vector2(-30, 90), Vector2(-90, 140)],
	[Vector2(8, 30), Vector2(70, 90), Vector2(96, 118)],
]

## Region colour scripts, Art Bible section 3 (G1). Colours are sRGB hex. ground: vertex colour of the
## terrain; fog: fog and horizon colour; key: sun colour by day; amb: flat ambient colour.
## The Meadows, The Scar and The Old Ruins have no bible row: the Meadows sit a little cooler than
## Hearthvale, the Scar is Hearthvale's earth with the green taken out, the Ruins are a grey-blue stone.
const BIOMES := {
	"village": {"name": "Hearthvale", "ground": Color("#5E6B38"), "fog": Color("#8A8F88"), "key": Color("#FFE2B8"), "amb": Color("#8795A8"), "foe": ""},
	"meadow": {"name": "The Meadows", "ground": Color("#5A6B3C"), "fog": Color("#818E88"), "key": Color("#F5E6C4"), "amb": Color("#7E8FA4"), "foe": "thrall", "beast": "deer"},
	"forest": {"name": "Greywood", "ground": Color("#2F3F2C"), "fog": Color("#4A5F54"), "key": Color("#DDE8C4"), "amb": Color("#55685E"), "foe": "bandit", "alt": "poacher", "beast": "deer"},
	"marsh": {"name": "Mirefen", "ground": Color("#4A4634"), "fog": Color("#66756E"), "key": Color("#E6E2D0"), "amb": Color("#6A7C82"), "foe": "wight", "alt": "hexer", "beast": "boar"},
	"quarry": {"name": "The Scar", "ground": Color("#5A5248"), "fog": Color("#76706A"), "key": Color("#F0E2C8"), "amb": Color("#77716E"), "foe": "brute"},
	"ruins": {"name": "The Old Ruins", "ground": Color("#4F4F4A"), "fog": Color("#5F6068"), "key": Color("#D9DDE6"), "amb": Color("#5E6472"), "foe": "keeper", "alt": "seer"},
	"ashlands": {"name": "The Ashlands", "ground": Color("#332B2B"), "fog": Color("#4D332E"), "key": Color("#DDB8A4"), "amb": Color("#4A3A40"), "foe": "pyre"},
}

## Road and shore blends in ground_color_with: Dirt trail light (bible 2.1) and a muddy shore.
const ROAD_COLOR := Color("#6B5A40")
const SHORE_COLOR := Color("#5A5238")

const FOES := {
	"thrall": {"name": "Field Thrall", "arche": 1, "hp": 0.36, "dmg": 0.7, "level": 2, "style": "knight", "scale": 1.1, "body": Color(0.5, 0.48, 0.4), "accent": Color(0.7, 0.6, 0.2), "drop": "bone"},
	"bandit": {"name": "Greywood Bandit", "arche": 2, "hp": 0.5, "dmg": 0.85, "level": 8, "style": "duelist", "scale": 1.15, "body": Color(0.3, 0.36, 0.26), "accent": Color(0.5, 0.75, 0.3), "drop": "hide"},
	"wight": {"name": "Bog Wight", "arche": 4, "hp": 0.5, "dmg": 1.0, "level": 16, "style": "sentinel", "scale": 1.2, "body": Color(0.22, 0.32, 0.3), "accent": Color(0.4, 0.9, 0.7), "drop": "bone"},
	"brute": {"name": "Stone Brute", "arche": 3, "hp": 0.6, "dmg": 1.0, "level": 24, "style": "brute", "scale": 1.5, "body": Color(0.45, 0.42, 0.38), "accent": Color(0.8, 0.5, 0.2), "drop": "hide"},
	"keeper": {"name": "Ruin Keeper", "arche": 4, "hp": 1.0, "dmg": 1.45, "level": 38, "style": "knight", "scale": 1.4, "body": Color(0.3, 0.3, 0.4), "accent": Color(0.6, 0.7, 1.0), "drop": "cinder"},

	"poacher": {"name": "Greywood Poacher", "arche": 2, "hp": 0.4, "dmg": 0.85, "level": 12, "style": "duelist", "scale": 1.1, "body": Color(0.36, 0.3, 0.2), "accent": Color(0.6, 0.5, 0.2), "drop": "hide", "ranged": "archer"},
	"hexer": {"name": "Mire Hexer", "arche": 4, "hp": 0.42, "dmg": 1.05, "level": 20, "style": "duelist", "scale": 1.15, "body": Color(0.28, 0.2, 0.34), "accent": Color(0.75, 0.4, 1.0), "drop": "bone", "ranged": "caster"},
	"seer": {"name": "Ruin Seer", "arche": 4, "hp": 0.8, "dmg": 1.5, "level": 40, "style": "duelist", "scale": 1.3, "body": Color(0.2, 0.22, 0.34), "accent": Color(0.5, 0.8, 1.0), "drop": "cinder", "ranged": "caster"},
	"pyre": {"name": "Pyre Guard", "arche": 5, "hp": 0.75, "dmg": 1.6, "level": 46, "style": "boss", "scale": 1.3, "body": Color(0.16, 0.14, 0.16), "accent": Color(1.0, 0.45, 0.1), "drop": "cinder"},
}

const NODES := {
	"oak": {"skill": "woodcutting", "level": 1, "mat": "oak_log", "xp": 22, "charges": 4, "verb": "CHOP", "label": "Oak", "tool": "axe"},
	"pine": {"skill": "woodcutting", "level": 15, "mat": "pine_log", "xp": 55, "charges": 4, "verb": "CHOP", "label": "Pine", "tool": "axe"},
	"ashwood": {"skill": "woodcutting", "level": 40, "mat": "ash_log", "xp": 130, "charges": 3, "verb": "CHOP", "label": "Ashwood", "tool": "axe"},
	"copper": {"skill": "mining", "level": 1, "mat": "copper_ore", "xp": 24, "charges": 4, "verb": "MINE", "label": "Copper rock", "tool": "pick"},
	"iron": {"skill": "mining", "level": 15, "mat": "iron_ore", "xp": 58, "charges": 4, "verb": "MINE", "label": "Iron rock", "tool": "pick"},
	"ember": {"skill": "mining", "level": 40, "mat": "ember_ore", "xp": 140, "charges": 3, "verb": "MINE", "label": "Ember vein", "tool": "pick"},
	"trout": {"skill": "fishing", "level": 1, "mat": "trout", "xp": 26, "charges": 6, "verb": "FISH", "label": "Trout run", "tool": ""},
	"pike": {"skill": "fishing", "level": 20, "mat": "pike", "xp": 65, "charges": 6, "verb": "FISH", "label": "Pike shallows", "tool": ""},
	"cinderfish": {"skill": "fishing", "level": 45, "mat": "cinderfish", "xp": 150, "charges": 5, "verb": "FISH", "label": "Cinderfish pool", "tool": ""},
	"marigold": {"skill": "foraging", "level": 1, "mat": "marigold", "xp": 20, "charges": 1, "verb": "PICK", "label": "Marigold", "tool": ""},
	"bogroot": {"skill": "foraging", "level": 20, "mat": "bogroot", "xp": 60, "charges": 1, "verb": "PICK", "label": "Bogroot", "tool": ""},
	"ashbloom": {"skill": "foraging", "level": 40, "mat": "ashbloom", "xp": 140, "charges": 1, "verb": "PICK", "label": "Ashbloom", "tool": ""},
}

const PLACES := [
	{"id": "smith", "type": "smith", "pos": Vector2(-14, 8), "label": "The Smith", "r": 4.0},
	{"id": "anvil", "type": "station", "skill": "smithing", "pos": Vector2(-19, 13), "label": "Anvil", "r": 2.0},
	{"id": "range", "type": "station", "skill": "cooking", "pos": Vector2(14, 6), "label": "Cooking fire", "r": 2.5},
	{"id": "alchemy", "type": "station", "skill": "alchemy", "pos": Vector2(20, 22), "label": "Alchemy table", "r": 2.5},
	{"id": "fletch", "type": "station", "skill": "fletching", "pos": Vector2(-22, 28), "label": "Fletching bench", "r": 2.5},
	{"id": "store", "type": "store", "pos": Vector2(12, 36), "label": "Trader", "r": 3.0},
	{"id": "task", "type": "task", "pos": Vector2(-8, 40), "label": "Taskmaster", "r": 3.0},
	{"id": "hearth", "type": "brazier", "pos": Vector2(0, 22), "label": "Hearth", "r": 3.0},
	{"id": "camp_fire", "type": "station", "skill": "cooking", "pos": Vector2(104, 112), "label": "Fisher's fire", "r": 3.0},
	{"id": "scar_anvil", "type": "station", "skill": "smithing", "pos": Vector2(132, -22), "label": "Quarry anvil", "r": 3.0},
	{"id": "stones", "type": "stones", "pos": Vector2(60, -150), "label": "Stepping stones", "r": 3.0},
	{"id": "tower", "type": "tower", "pos": TOWER_GATE, "label": "The Ashgrave", "r": 8.0},

	{"id": "elder", "type": "npc", "pos": Vector2(5, 27), "label": "Elder Maren", "r": 2.5},
	{"id": "alchemist", "type": "npc", "pos": Vector2(23, 25), "label": "Sister Wren", "r": 2.5},
	{"id": "fisher", "type": "npc", "pos": Vector2(100, 115), "label": "Old Tam", "r": 2.5},
	{"id": "ranger", "type": "npc", "pos": Vector2(-146, -7), "label": "Warden Isolde", "r": 3.0},
	{"id": "shrine", "type": "spot", "pos": Vector2(-92, 143), "label": "Mire shrine", "r": 4.0},
	{"id": "altar", "type": "spot", "pos": Vector2(126, -174), "label": "Broken altar", "r": 4.0},
	{"id": "circle", "type": "spot", "pos": Vector2(44, 104), "label": "Standing stones", "r": 7.0},
	{"id": "watch", "type": "spot", "pos": Vector2(-64, -72), "label": "Fallen watchtower", "r": 5.0},
]

const HOUSES := [Vector2(-26, 0), Vector2(26, -2), Vector2(30, 30), Vector2(-30, 40), Vector2(-4, 52), Vector2(22, 50), Vector2(-34, 20)]


static func river_x(z: float) -> float:
	return 80.0 + 20.0 * sin(z / 55.0)


static func river_dist(x: float, z: float) -> float:
	return absf(x - river_x(z))


static func lake_dist(x: float, z: float) -> float:
	return Vector2(x, z).distance_to(LAKE)


static func on_bridge(x: float, z: float) -> bool:
	return BRIDGE.has_point(Vector2(x, z))


static func is_water(x: float, z: float) -> bool:
	if on_bridge(x, z):
		return false
	if river_dist(x, z) > 10.0 and lake_dist(x, z) > LAKE_R + 4.0:
		return false
	return height(x, z) < WATER_Y + 0.15


static func road_dist(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := 9999.0
	for road in ROADS:
		for i in road.size() - 1:
			var a: Vector2 = road[i]
			var b: Vector2 = road[i + 1]
			var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
			best = minf(best, p.distance_to(a + (b - a) * t))
	return best


static func biome(x: float, z: float) -> String:
	var wx := x + 9.0 * sin(z * 0.06) + 5.0 * sin(z * 0.17 + 1.0)
	var wz := z + 9.0 * sin(x * 0.055 + 2.0) + 5.0 * sin(x * 0.15)
	if Vector2(x, z).distance_to(VILLAGE) < VILLAGE_R:
		return "village"
	var east := x > river_x(z) + 8.0
	if east and wz < -128.0:
		return "ruins"
	if wz < -118.0 and absf(wx) < 100.0:
		return "ashlands"
	if east and wz < 62.0:
		return "quarry"
	if wx < -52.0 and wz < 66.0:
		return "forest"
	if wx < 4.0 and wz >= 66.0:
		return "marsh"
	return "meadow"


static func height(x: float, z: float) -> float:
	return height_in(x, z, biome(x, z))


## height() for a point whose biome the caller already has.
static func height_in(x: float, z: float, b: String) -> float:
	var h := (sin(x * 0.045) * 0.9 + sin(z * 0.038 + 1.3) * 0.9 + sin((x + z) * 0.09) * 0.35) * 0.8 + 1.3
	if b == "quarry":
		h += 1.4 * sin(x * 0.12) * sin(z * 0.1) + 0.8
	elif b == "marsh":
		h = 0.35 + (h - 1.3) * 0.2
	elif b == "ashlands":
		h += 0.5 * sin(x * 0.2 + z * 0.13)

	h = lerpf(0.8, h, smoothstep(VILLAGE_R - 14.0, VILLAGE_R + 16.0, Vector2(x, z).distance_to(VILLAGE)))
	h = lerpf(0.8, h, smoothstep(6.0, 30.0, Vector2(x, z).distance_to(TOWER_GATE)))

	h = lerpf(-1.9, h, smoothstep(3.0, 9.0, river_dist(x, z)))
	h = lerpf(-2.1, h, smoothstep(LAKE_R - 6.0, LAKE_R + 3.0, lake_dist(x, z)))
	return h


static func walk_height(x: float, z: float) -> float:
	if on_bridge(x, z):
		return 0.75
	return maxf(height(x, z), WATER_Y)


static func ground_color(x: float, z: float) -> Color:
	return ground_color_with(x, z, biome(x, z), road_segments_near(Rect2(x, z, 0, 0), 3.2))


## The road segments, as [from, to] pairs, that come within `margin` of a box. A road
## changes the ground colour only within 3.2 of it, so a chunk needs only these.
static func road_segments_near(box: Rect2, margin: float) -> Array:
	var out: Array = []
	var lo := box.position - Vector2(margin, margin)
	var hi := box.end + Vector2(margin, margin)
	for road in ROADS:
		for i in road.size() - 1:
			var a: Vector2 = road[i]
			var b: Vector2 = road[i + 1]
			if maxf(a.x, b.x) < lo.x or minf(a.x, b.x) > hi.x or maxf(a.y, b.y) < lo.y or minf(a.y, b.y) > hi.y:
				continue
			out.append([a, b])
	return out


## ground_color() for a point whose biome the caller already has, with the road segments
## that can matter (road_segments_near of a box holding the point and a margin of 3.2).
static func ground_color_with(x: float, z: float, b: String, segs: Array) -> Color:
	var c: Color = BIOMES[b].ground
	var n := 0.5 + 0.5 * sin(x * 0.7 + sin(z * 0.9)) * sin(z * 0.6)
	c = c.darkened(0.12 * n)
	var p := Vector2(x, z)
	var rd := 9999.0
	for seg in segs:
		var a: Vector2 = seg[0]
		var d: Vector2 = seg[1] - a
		var t := clampf((p - a).dot(d) / d.length_squared(), 0.0, 1.0)
		rd = minf(rd, p.distance_to(a + d * t))
	if rd < 3.2:
		c = c.lerp(ROAD_COLOR, smoothstep(3.2, 1.2, rd))
	var wd := minf(river_dist(x, z) - 5.0, lake_dist(x, z) - LAKE_R + 3.0)
	if wd < 3.0:
		c = c.lerp(SHORE_COLOR, smoothstep(3.0, 0.0, wd))
	return c


static func foe_for(b: String, roll: float) -> String:
	var info: Dictionary = BIOMES[b]
	if info.has("alt") and roll < 0.32:
		return info.alt
	return info.foe


static func region_of(foe_id: String) -> String:
	for b in BIOMES:
		if BIOMES[b].foe == foe_id or BIOMES[b].get("alt", "") == foe_id:
			return BIOMES[b].name
	return "the land"


static func in_bounds(x: float, z: float) -> bool:
	return absf(x) < X_MAX and z > Z_MIN and z < Z_MAX


static func fish_at(x: float, z: float) -> String:
	if lake_dist(x, z) < LAKE_R + 8.0:
		return "pike"
	return "cinderfish" if z < -110.0 else "trout"


static func tree_at(x: float, z: float) -> String:
	match biome(x, z):
		"ashlands", "ruins": return "ashwood"
		"forest": return "pine" if x < -120.0 else "oak"
	return "oak"


static func rock_at(x: float, z: float) -> String:
	match biome(x, z):
		"ashlands", "ruins": return "ember"
		"quarry": return "iron" if x > 135.0 or z < -60.0 else "copper"
	return "copper"


static func herb_at(x: float, z: float) -> String:
	match biome(x, z):
		"ashlands", "ruins": return "ashbloom"
		"marsh": return "bogroot"
	return "marigold"
