class_name Items
extends RefCounted

const SLOTS := ["weapon", "helm", "armour", "shield", "ring", "ranged", "spell"]

const STARTING := {"weapon": "iron_longsword", "helm": "plain_sallet", "armour": "worn_plate", "shield": "heater", "ring": "", "ranged": "", "spell": ""}

const WEAPONS := {
	"iron_longsword": {"name": "Iron Longsword", "family": "longsword", "element": "", "damage": 1.0, "lock": 0.24, "window": 0.0, "break_mult": 1.0, "price": 0},
	"wardens_brand": {"name": "Warden's Brand", "family": "longsword", "element": "ember", "damage": 1.2, "lock": 0.24, "window": 0.0, "break_mult": 1.0, "price": 320},
	"twin_fangs": {"name": "Twin Fangs", "family": "twin", "element": "", "damage": 0.72, "lock": 0.16, "window": -0.05, "break_mult": 0.9, "price": 450},
	"frostbite_pair": {"name": "Frostbite Pair", "family": "twin", "element": "frost", "damage": 0.82, "lock": 0.16, "window": -0.05, "break_mult": 0.9, "price": 900},
	"pyre_greatsword": {"name": "Pyre Greatsword", "family": "greatsword", "element": "ember", "damage": 1.6, "lock": 0.34, "window": 0.05, "break_mult": 1.4, "price": 600},
	"stormcleaver": {"name": "Stormcleaver", "family": "greatsword", "element": "storm", "damage": 1.8, "lock": 0.34, "window": 0.05, "break_mult": 1.4, "price": 1200},
}

const ARMOUR := {
	"plain_sallet": {"name": "Plain Sallet", "slot": "helm", "set": "", "price": 0},
	"watchers_helm": {"name": "Watcher's Helm", "slot": "helm", "set": "warden", "dodge": 1, "price": 280},
	"duelists_hood": {"name": "Duelist's Hood", "slot": "helm", "set": "duelist", "window": 0.03, "price": 380},
	"worn_plate": {"name": "Worn Plate", "slot": "armour", "set": "", "price": 0},
	"wardens_plate": {"name": "Warden's Plate", "slot": "armour", "set": "warden", "hp": 45, "dodge_regen": 0.8, "price": 420},
	"duelists_leathers": {"name": "Duelist's Leathers", "slot": "armour", "set": "duelist", "hp": 12, "dodge_regen": 1.3, "price": 420},
	"heater": {"name": "Heater Shield", "slot": "shield", "set": "", "shield": 60, "perfect_block": 0.2, "price": 0},
	"buckler": {"name": "Duelist's Buckler", "slot": "shield", "set": "duelist", "shield": 35, "perfect_block": 0.32, "price": 300},
	"tower_shield": {"name": "Warden's Tower Shield", "slot": "shield", "set": "warden", "shield": 105, "perfect_block": 0.12, "price": 360},
	"ember_ring": {"name": "Ember Ring", "slot": "ring", "set": "", "surge": 1.2, "price": 250},
	"oath_ring": {"name": "Oath Ring", "slot": "ring", "set": "", "leech": 4, "price": 250},
}

const RANGED := {
	"throwing_knives": {"name": "Throwing Knives", "slot": "ranged", "shots": 3, "power": 2.0, "price": 220},
	"hunters_bow": {"name": "Hunter's Bow", "slot": "ranged", "shots": 4, "power": 3.2, "price": 620},
}

const SPELLS := {
	"ember_bolt": {"name": "Ember Bolt", "slot": "spell", "desc": "Heavy fire damage and a long burn", "price": 420},
	"frost_bind": {"name": "Frost Bind", "slot": "spell", "desc": "Freezes the enemy open and slows it", "price": 520},
	"ward": {"name": "Ward", "slot": "spell", "desc": "The next blow that lands is absorbed", "price": 380},
}

const UPGRADE_MAX := 2

const SETS := {
	"warden": {"name": "Warden", "desc": "A broken guard restores half the shield"},
	"duelist": {"name": "Duelist", "desc": "Perfect dodges land a free hit"},
}


static func exists(id: String) -> bool:
	return WEAPONS.has(id) or ARMOUR.has(id) or RANGED.has(id) or SPELLS.has(id)


static func info(id: String) -> Dictionary:
	for table in [WEAPONS, ARMOUR, RANGED, SPELLS]:
		if table.has(id):
			return table[id]
	return {}


static func slot_of(id: String) -> String:
	if WEAPONS.has(id):
		return "weapon"
	return info(id).get("slot", "")


static func for_slot(slot: String) -> Array:
	var out: Array = []
	for table in [WEAPONS, ARMOUR, RANGED, SPELLS]:
		for id in table:
			if slot_of(id) == slot:
				out.append(id)
	return out


static func upgrade_price(id: String, level: int) -> int:
	return int(maxf(float(info(id).price), 250.0) * 0.6 * (level + 1))

const ELEMENT_COLORS := {"ember": Color(1.0, 0.45, 0.1), "frost": Color(0.4, 0.8, 1.0), "storm": Color(0.75, 0.6, 1.0), "grave": Color(0.4, 1.0, 0.5)}
const FLASK_PRICE := 60
const MAX_FLASKS := 3


static func describe(id: String) -> String:
	var d := info(id)
	var parts: Array = []
	if SPELLS.has(id):
		return d.desc
	if RANGED.has(id):
		return "%d shots a fight. Interrupts a windup" % d.shots
	if WEAPONS.has(id):
		parts.append({"longsword": "Balanced", "twin": "Fast cuts", "greatsword": "Heavy cuts"} [d.family])
		parts.append("%d%% damage" % int(round(float(d.damage) * 100.0)))
		if d.element != "":
			parts.append(String(d.element).capitalize())
		return ", ".join(parts)
	if d.has("hp"): parts.append("+%d health" % d.hp)
	if d.has("shield"): parts.append("%d shield" % d.shield)
	if d.has("perfect_block"): parts.append("%s perfect block" % ("wide" if d.perfect_block > 0.25 else ("tight" if d.perfect_block < 0.15 else "normal")))
	if d.has("dodge"): parts.append("+%d dodge" % d.dodge)
	if d.has("dodge_regen"): parts.append("dodge refills %s" % ("faster" if d.dodge_regen > 1.0 else "slower"))
	if d.has("window"): parts.append("wider parry")
	if d.has("surge"): parts.append("surge fills faster")
	if d.has("leech"): parts.append("parries heal %d" % d.leech)
	if d.get("set", "") != "":
		parts.append("%s set" % SETS[d.set].name)
	return ", ".join(parts) if not parts.is_empty() else "Plain but honest"


static func hero_look(eq: Dictionary, upgrades := {}) -> Dictionary:
	var w: Dictionary = info(eq.weapon)
	var lvl := int(upgrades.get(eq.weapon, 0))
	var over := {"shield_kind": {"buckler": "buckler", "tower_shield": "tower"}.get(eq.shield, "heater")}
	over["blade"] = {"longsword": [1.1, 0.085], "twin": [0.82, 0.06], "greatsword": [1.5, 0.14]} [w.family]
	over["back_blade"] = w.family == "twin"
	over["blade_tint"] = {"wardens_brand": Color(1.0, 0.75, 0.55), "frostbite_pair": Color(0.7, 0.9, 1.0),
		"pyre_greatsword": Color(0.35, 0.3, 0.3), "stormcleaver": Color(0.75, 0.7, 1.0), "twin_fangs": Color(0.95, 0.95, 0.85)}.get(eq.weapon, Color(0.86, 0.88, 0.92))
	if w.element != "" or lvl > 0:
		over["runes"] = true
		over["rune_color"] = ELEMENT_COLORS.get(w.element, Color(1.0, 0.9, 0.6))
		over["rune_power"] = 2.0 + 2.5 * lvl
	match eq.helm:
		"watchers_helm":
			over["helm"] = "great"
			over["fin"] = true
			over["plume"] = false
		"duelists_hood":
			over["plume"] = false
			over["half_cape"] = true
	var body := Color(0.62, 0.65, 0.72)
	var accent := Color(0.15, 0.3, 0.75)
	match eq.armour:
		"wardens_plate":
			body = Color(0.2, 0.2, 0.24)
			accent = Color(0.95, 0.35, 0.08)
			over["bulk"] = 1.14
			over["tabard"] = true
			over["spikes"] = true
		"duelists_leathers":
			body = Color(0.5, 0.36, 0.22)
			accent = Color(0.1, 0.65, 0.55)
			over["bulk"] = 0.88
			over["slim"] = true
			over["cape"] = 0.0
			over["half_cape"] = true
	if eq.ring != "":
		over["ring_glow"] = {"ember_ring": Color(1.0, 0.45, 0.1), "oath_ring": Color(0.9, 0.2, 0.25)}.get(eq.ring, Color.WHITE)
	if eq.get("ranged", "") != "":
		over["back_bow"] = eq.ranged == "hunters_bow"
		over["knife_belt"] = eq.ranged == "throwing_knives"
	if eq.get("spell", "") != "":
		over["focus"] = {"ember_bolt": ELEMENT_COLORS.ember, "frost_bind": ELEMENT_COLORS.frost, "ward": Color(0.6, 0.7, 1.0)} [eq.spell]
	return {"style": "hero", "body": body, "accent": accent, "over": over}
