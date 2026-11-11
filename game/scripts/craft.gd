class_name Craft
extends RefCounted

const SKILLS := {
	"blade": {"name": "Blade", "group": "Combat"},
	"guard": {"name": "Guard", "group": "Combat"},
	"archery": {"name": "Archery", "group": "Combat"},
	"sorcery": {"name": "Sorcery", "group": "Combat"},
	"vitality": {"name": "Vitality", "group": "Combat"},
	"slaying": {"name": "Slaying", "group": "Combat"},
	"mining": {"name": "Mining", "group": "Gathering"},
	"woodcutting": {"name": "Woodcutting", "group": "Gathering"},
	"fishing": {"name": "Fishing", "group": "Gathering"},
	"foraging": {"name": "Foraging", "group": "Gathering"},
	"smithing": {"name": "Smithing", "group": "Making"},
	"cooking": {"name": "Cooking", "group": "Making"},
	"alchemy": {"name": "Alchemy", "group": "Making"},
	"fletching": {"name": "Fletching", "group": "Making"},
	"agility": {"name": "Agility", "group": "Other"},
}
const COMBAT := ["blade", "guard", "archery", "sorcery", "vitality"]
const MAX_LEVEL := 99

const MATS := {
	"copper_ore": {"name": "Copper ore", "price": 4},
	"iron_ore": {"name": "Iron ore", "price": 10},
	"ember_ore": {"name": "Ember ore", "price": 28},
	"oak_log": {"name": "Oak log", "price": 3},
	"pine_log": {"name": "Pine log", "price": 8},
	"ash_log": {"name": "Ashwood log", "price": 22},
	"trout": {"name": "Raw trout", "price": 4},
	"pike": {"name": "Raw pike", "price": 11},
	"cinderfish": {"name": "Raw cinderfish", "price": 26},
	"marigold": {"name": "Marigold", "price": 3},
	"bogroot": {"name": "Bogroot", "price": 9},
	"ashbloom": {"name": "Ashbloom", "price": 24},
	"meal_trout": {"name": "Grilled trout", "price": 9, "meal": 20},
	"meal_pike": {"name": "Pike stew", "price": 24, "meal": 45},
	"meal_cinder": {"name": "Cinderfish feast", "price": 60, "meal": 80},
	"tonic": {"name": "Surge tonic", "price": 40},
	"arrow": {"name": "Arrow", "price": 1},
	"raw_meat": {"name": "Raw meat", "price": 6},
	"meal_meat": {"name": "Roast meat", "price": 16, "meal": 30},
	"bone": {"name": "Old bone", "price": 5},
	"hide": {"name": "Rough hide", "price": 7},
	"cinder": {"name": "Cinder shard", "price": 18},
}

const RECIPES := [
	{"skill": "smithing", "level": 1, "name": "Copper axe", "in": {"copper_ore": 3, "oak_log": 1}, "out": {"tool": ["axe", 1]}, "xp": 30},
	{"skill": "smithing", "level": 1, "name": "Copper pick", "in": {"copper_ore": 3, "oak_log": 1}, "out": {"tool": ["pick", 1]}, "xp": 30},
	{"skill": "smithing", "level": 5, "name": "Duelist's Buckler", "in": {"copper_ore": 4, "oak_log": 2}, "out": {"item": "buckler"}, "xp": 60},
	{"skill": "smithing", "level": 8, "name": "Watcher's Helm", "in": {"iron_ore": 4}, "out": {"item": "watchers_helm"}, "xp": 110},
	{"skill": "smithing", "level": 10, "name": "Duelist's Hood", "in": {"copper_ore": 3, "hide": 3}, "out": {"item": "duelists_hood"}, "xp": 110},
	{"skill": "smithing", "level": 12, "name": "Twin Fangs", "in": {"iron_ore": 6, "oak_log": 2}, "out": {"item": "twin_fangs"}, "xp": 180},
	{"skill": "smithing", "level": 14, "name": "Duelist's Leathers", "in": {"hide": 6, "copper_ore": 2}, "out": {"item": "duelists_leathers"}, "xp": 170},
	{"skill": "smithing", "level": 15, "name": "Warden's Brand", "in": {"iron_ore": 8, "pine_log": 3}, "out": {"item": "wardens_brand"}, "xp": 220},
	{"skill": "smithing", "level": 18, "name": "Warden's Tower Shield", "in": {"iron_ore": 7, "oak_log": 3}, "out": {"item": "tower_shield"}, "xp": 230},
	{"skill": "smithing", "level": 20, "name": "Iron axe", "in": {"iron_ore": 4, "pine_log": 2}, "out": {"tool": ["axe", 2]}, "xp": 200},
	{"skill": "smithing", "level": 20, "name": "Iron pick", "in": {"iron_ore": 4, "pine_log": 2}, "out": {"tool": ["pick", 2]}, "xp": 200},
	{"skill": "smithing", "level": 22, "name": "Warden's Plate", "in": {"iron_ore": 10}, "out": {"item": "wardens_plate"}, "xp": 300},
	{"skill": "smithing", "level": 25, "name": "Pyre Greatsword", "in": {"iron_ore": 10, "pine_log": 4, "cinder": 2}, "out": {"item": "pyre_greatsword"}, "xp": 380},
	{"skill": "smithing", "level": 28, "name": "Oath Ring", "in": {"iron_ore": 4, "bogroot": 3}, "out": {"item": "oath_ring"}, "xp": 320},
	{"skill": "smithing", "level": 30, "name": "Frostbite Pair", "in": {"iron_ore": 8, "bogroot": 5}, "out": {"item": "frostbite_pair"}, "xp": 450},
	{"skill": "smithing", "level": 35, "name": "Ember Ring", "in": {"ember_ore": 3}, "out": {"item": "ember_ring"}, "xp": 480},
	{"skill": "smithing", "level": 45, "name": "Ember axe", "in": {"ember_ore": 4, "ash_log": 2}, "out": {"tool": ["axe", 3]}, "xp": 700},
	{"skill": "smithing", "level": 45, "name": "Ember pick", "in": {"ember_ore": 4, "ash_log": 2}, "out": {"tool": ["pick", 3]}, "xp": 700},
	{"skill": "smithing", "level": 48, "name": "Stormcleaver", "in": {"ember_ore": 8, "ash_log": 6, "cinder": 4}, "out": {"item": "stormcleaver"}, "xp": 1100},
	{"skill": "cooking", "level": 1, "name": "Grilled trout", "in": {"trout": 1}, "out": {"mat": "meal_trout", "n": 1}, "xp": 25},
	{"skill": "cooking", "level": 8, "name": "Roast meat", "in": {"raw_meat": 1}, "out": {"mat": "meal_meat", "n": 1}, "xp": 40},
	{"skill": "cooking", "level": 20, "name": "Pike stew", "in": {"pike": 1, "marigold": 1}, "out": {"mat": "meal_pike", "n": 1}, "xp": 70},
	{"skill": "cooking", "level": 45, "name": "Cinderfish feast", "in": {"cinderfish": 1, "bogroot": 1}, "out": {"mat": "meal_cinder", "n": 1}, "xp": 160},
	{"skill": "alchemy", "level": 1, "name": "Flask", "in": {"marigold": 2}, "out": {"flask": 1}, "xp": 30},
	{"skill": "alchemy", "level": 20, "name": "Twin flasks", "in": {"bogroot": 2}, "out": {"flask": 2}, "xp": 80},
	{"skill": "alchemy", "level": 35, "name": "Surge tonic", "in": {"ashbloom": 1, "marigold": 2}, "out": {"mat": "tonic", "n": 1}, "xp": 150},
	{"skill": "fletching", "level": 1, "name": "Arrows (10)", "in": {"oak_log": 1, "copper_ore": 1}, "out": {"mat": "arrow", "n": 10}, "xp": 25},
	{"skill": "fletching", "level": 10, "name": "Throwing Knives", "in": {"iron_ore": 2, "oak_log": 1}, "out": {"item": "throwing_knives"}, "xp": 120},
	{"skill": "fletching", "level": 15, "name": "Hunter's Bow", "in": {"pine_log": 6, "hide": 2}, "out": {"item": "hunters_bow"}, "xp": 220},
	{"skill": "fletching", "level": 25, "name": "Iron arrows (20)", "in": {"pine_log": 1, "iron_ore": 1}, "out": {"mat": "arrow", "n": 20}, "xp": 60},
]

const TOOL_NAMES := ["Worn", "Copper", "Iron", "Ember"]

const PERKS := {
	"b1": {"tree": "Blade", "name": "Heavy Hand", "desc": "+10% cut damage", "needs": ""},
	"b2": {"tree": "Blade", "name": "Opening", "desc": "Parried foes stay open longer", "needs": "b1"},
	"b3": {"tree": "Blade", "name": "Bloodletting", "desc": "Combo enders heal 5 health", "needs": "b2"},
	"g1": {"tree": "Guard", "name": "Bulwark", "desc": "+15 shield", "needs": ""},
	"g2": {"tree": "Guard", "name": "Light Feet", "desc": "+1 dodge charge", "needs": "g1"},
	"g3": {"tree": "Guard", "name": "Riposte", "desc": "Perfect parries land a free cut", "needs": "g2"},
	"a1": {"tree": "Hunter and Arcane", "name": "Deep Quiver", "desc": "+1 sidearm shot each fight", "needs": ""},
	"a2": {"tree": "Hunter and Arcane", "name": "Wellspring", "desc": "Mana fills 30% faster", "needs": "a1"},
	"a3": {"tree": "Hunter and Arcane", "name": "Kindling", "desc": "Surge fills 25% faster", "needs": "a2"},
}


static func xp_for(level: int) -> int:
	var n := level - 1
	return 40 * n * n + 20 * n


static func level_for(xp: int) -> int:
	var lvl := 1
	while lvl < MAX_LEVEL and xp >= xp_for(lvl + 1):
		lvl += 1
	return lvl


static func recipes_for(skill: String) -> Array:
	return RECIPES.filter(func(r): return r.skill == skill)


static func inputs_text(r: Dictionary) -> String:
	var parts: Array = []
	for m in r["in"]:
		parts.append("%d/%d %s" % [Run.mat(m), r["in"][m], MATS[m].name])
	return ",  ".join(parts)


static func already_has(r: Dictionary) -> bool:
	var out: Dictionary = r.out
	if out.has("item"):
		return Run.data.inventory.has(out.item)
	if out.has("tool"):
		return int(Run.data.tools.get(out.tool[0], 0)) >= int(out.tool[1])
	return false


static func blocker(r: Dictionary) -> String:
	if Run.skill(r.skill) < int(r.level):
		return "Needs %s %d" % [SKILLS[r.skill].name, r.level]
	if already_has(r):
		return "Already owned"
	for m in r["in"]:
		if Run.mat(m) < int(r["in"][m]):
			return "Missing materials"
	if r.out.has("flask") and int(Run.data.potions) >= Items.MAX_FLASKS:
		return "Flasks are full"
	return ""


static func make(r: Dictionary) -> bool:
	if blocker(r) != "":
		return false
	for m in r["in"]:
		Run.add_mat(m, -int(r["in"][m]))
	var out: Dictionary = r.out
	if out.has("mat"):
		Run.add_mat(out.mat, int(out.n))
	elif out.has("item"):
		Run.add_item(out.item)
	elif out.has("tool"):
		Run.data.tools[out.tool[0]] = int(out.tool[1])
	elif out.has("flask"):
		Run.data.potions = mini(int(Run.data.potions) + int(out.flask), Items.MAX_FLASKS)
	Run.train(r.skill, int(r.xp))
	Run.save()
	return true
