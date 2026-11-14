class_name Run
extends RefCounted

const SAVE_PATH := "user://save.json"
const FLOORS := 5

const BUILD := 13

const BOONS := {
	"edge": {"name": "Keen Edge", "desc": "+15% sword damage", "max": 6},
	"vitality": {"name": "Vitality", "desc": "+20 maximum health", "max": 6},
	"bulwark": {"name": "Bulwark", "desc": "+25 shield strength", "max": 4},
	"ember": {"name": "Ember Heart", "desc": "Surge fills 30% faster", "max": 3},
	"quick": {"name": "Quick Hands", "desc": "Wider parry timing", "max": 3},
	"fleet": {"name": "Fleet Foot", "desc": "+1 dodge charge", "max": 2},
	"leech": {"name": "Blood Oath", "desc": "Each parry heals 6 health", "max": 3},
}


static var data: Dictionary = {}
static var loaded := false
static var title_seen := false
static var no_save := false


static var encounter := {}
static var session_slain: Array = []
static var spawn: Variant = "entrance"
static var captions: Array = []
static var xp_log: Array = []
static var resumed := false


static func apply_web_settings(vp: Viewport) -> void:
	if not OS.has_feature("web"):
		return
	var px := float(DisplayServer.window_get_size().y)
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.scaling_3d_scale = clampf(640.0 / maxf(px, 1.0), 0.45, 1.0)
	RenderingServer.directional_shadow_atlas_set_size(1024, true)


static func defaults() -> Dictionary:
	return {
		"bloodline": 1, "loop": 0, "floor": 1, "level": 1, "xp": 0,
		"best_floor": 1, "kills": 0, "boons": {},
		"tutorial_done": false, "assist": true, "sound": true,

		"version": SAVE_VERSION, "gold": 0, "cinders": 0,
		"inventory": Items.STARTING.values().filter(func(x): return x != ""),
		"equipped": Items.STARTING.duplicate(),

		"potions": 1, "unlocked": 1, "relics": [], "slain": [], "opened": [], "met": [],
		"upgrades": {},

		"skills": {}, "mats": {}, "tools": {"axe": 0, "pick": 0},
		"ow_x": Land.START.x, "ow_z": Land.START.z, "in_tower": false,
		"task": {}, "ow_opened": [], "skills_seeded": false, "visited": [],

		"respawn": {}, "tower_slain": [], "stamp": 0, "mastery": {}, "perks": {}, "quests": {}, "flags": {},

		"pid": "", "pname": "", "online": true, "pvp_w": 0, "pvp_l": 0,
	}

const WEB_KEY := "ashgrave_save_v1"
const SAVE_VERSION := 3


static func ensure_loaded() -> void:
	if loaded:
		return
	loaded = true
	data = defaults()
	var text := ""

	if OS.has_feature("web"):
		var v: Variant = JavaScriptBridge.eval(
			"(function(){try{return localStorage.getItem('%s')||''}catch(e){return ''}})()" % WEB_KEY, true)
		if v is String:
			text = v
	if text == "" and FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f:
			text = f.get_as_text()
	if text != "":
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			for k in parsed:
				if data.has(k) and typeof(parsed[k]) == typeof(data[k]) or k in INT_KEYS or k in FLOAT_KEYS:
					data[k] = parsed[k]

	for k in INT_KEYS:
		data[k] = maxi(int(data[k]), 0 if k in ["loop", "xp", "kills", "gold", "cinders", "potions", "stamp", "pvp_w", "pvp_l"] else 1)
	data.floor = clampi(int(data.floor), 1, FLOORS)
	_migrate()

	if now() - int(data.stamp) < 240000 and int(data.stamp) > 0:
		title_seen = true
		resumed = true


static func _migrate() -> void:
	data.version = SAVE_VERSION

	if not data.skills_seeded:
		data.skills_seeded = true
		var head := Craft.xp_for(maxi(int(data.level), 1))
		for sk in ["blade", "guard", "vitality"]:
			data.skills[sk] = maxi(int(data.skills.get(sk, 0)), head)
	for sk in data.skills:
		data.skills[sk] = int(data.skills[sk])
	for m in data.mats:
		data.mats[m] = int(data.mats[m])
	for t in ["axe", "pick"]:
		data.tools[t] = int(data.tools.get(t, 0))
	data.gold = maxi(int(data.gold), 0)
	data.cinders = maxi(int(data.cinders), 0)
	var inv: Array = []
	for id in data.inventory:
		if id is String and Items.exists(id) and not inv.has(id):
			inv.append(id)
	for slot in Items.SLOTS:
		var id: String = str(data.equipped.get(slot, ""))
		if id != "" and (not Items.exists(id) or Items.slot_of(id) != slot):
			id = ""
		if id == "" and Items.STARTING[slot] != "":
			id = Items.STARTING[slot]
		data.equipped[slot] = id
		if id != "" and not inv.has(id):
			inv.append(id)
	data.inventory = inv


static func add_item(id: String) -> void:
	if Items.exists(id) and not data.inventory.has(id):
		data.inventory.append(id)
		save()


static func equip(id: String) -> bool:
	if not data.inventory.has(id):
		return false
	data.equipped[Items.slot_of(id)] = id
	save()
	return true


static func perk(id: String) -> bool:
	return data.perks.has(id)


static func perk_points() -> int:
	var total := int(combat_level() / 4)
	for id in data.mastery:
		total += mastery_level(id)
	return total - data.perks.size()


static func buy_perk(id: String) -> String:
	var p: Dictionary = Craft.PERKS[id]
	if perk(id):
		return "Already learned."
	if p.needs != "" and not perk(p.needs):
		return "Learn %s first." % Craft.PERKS[p.needs].name
	if perk_points() <= 0:
		return "No perk points. Gain combat levels or master a weapon."
	data.perks[id] = true
	save()
	return "Learned %s." % p.name


static func upgrade_level(id: String) -> int:
	return int(data.upgrades.get(id, 0))


static func look() -> Dictionary:
	return Items.hero_look(data.equipped, data.upgrades)


static func stats_with(id: String) -> Dictionary:
	var slot := Items.slot_of(id)
	var old: String = data.equipped[slot]
	data.equipped[slot] = id
	var st := stats()
	data.equipped[slot] = old
	return st


static func set_counts() -> Dictionary:
	var out := {}
	for slot in ["helm", "armour", "shield"]:
		var s: String = Items.info(data.equipped[slot]).get("set", "")
		if s != "":
			out[s] = int(out.get(s, 0)) + 1
	return out


static func stats() -> Dictionary:
	var w: Dictionary = Items.info(data.equipped.weapon)
	var blade := skill("blade")
	var guard := skill("guard")
	var st := {
		"max_hp": 100.0 + 5.0 * (skill("vitality") - 1) + 20.0 * boon("vitality"),
		"damage": 7.0 * (1.0 + 0.035 * (blade - 1) + 0.15 * boon("edge")) * float(w.damage) * (1.0 + 0.15 * upgrade_level(data.equipped.weapon)) * (1.0 + 0.03 * mastery_level(data.equipped.weapon)),
		"shield_max": 1.2 * (guard - 1) + 25.0 * boon("bulwark"),
		"surge_rate": 1.0 + 0.3 * boon("ember"),
		"parry_window": 0.3 + minf(0.0012 * (guard - 1), 0.08) + 0.04 * boon("quick") + float(w.window),
		"dodge_max": 3 + boon("fleet"),
		"dodge_regen": 0.6 * (1.0 + 0.006 * (skill("agility") - 1)),
		"leech": 6.0 * boon("leech"),
		"slash_lock": float(w.lock),
		"break_mult": float(w.break_mult),
		"perfect_block": 0.2,
		"family": w.family, "element": w.element,
		"ranged_mult": 1.0 + 0.03 * (skill("archery") - 1),
		"spell_mult": 1.0 + 0.03 * (skill("sorcery") - 1),
		"mana_rate": 4.5 * (1.0 + 0.01 * (skill("sorcery") - 1)),
	}
	if perk("b1"):
		st.damage *= 1.1
	if perk("g1"):
		st.shield_max += 15.0
	if perk("g2"):
		st.dodge_max += 1
	if perk("a2"):
		st.mana_rate *= 1.3
	if perk("a3"):
		st.surge_rate *= 1.25
	for slot in ["helm", "armour", "shield", "ring"]:
		var a: Dictionary = Items.info(data.equipped[slot])
		st.max_hp += float(a.get("hp", 0))
		st.shield_max += float(a.get("shield", 0))
		st.parry_window += float(a.get("window", 0.0))
		st.dodge_max += int(a.get("dodge", 0))
		st.dodge_regen *= float(a.get("dodge_regen", 1.0))
		st.surge_rate *= float(a.get("surge", 1.0))
		st.leech += float(a.get("leech", 0))
		if a.has("perfect_block"):
			st.perfect_block = float(a.perfect_block)
	return st

const INT_KEYS := ["bloodline", "loop", "floor", "level", "xp", "best_floor", "kills", "gold", "cinders", "version", "potions", "unlocked", "stamp", "pvp_w", "pvp_l"]
const FLOAT_KEYS := ["ow_x", "ow_z"]


static func now() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


static func respawn_due(id: String) -> bool:
	return now() >= int(data.respawn.get(id, 0))


static func set_respawn(id: String, msec: int) -> void:
	data.respawn[id] = now() + msec


static func mastery_level(id: String) -> int:
	return mini(int(int(data.mastery.get(id, 0)) / 1500), 5)


static func gain_mastery(sword_damage: int) -> void:
	var id: String = data.equipped.weapon
	var before := mastery_level(id)
	data.mastery[id] = int(data.mastery.get(id, 0)) + sword_damage
	if mastery_level(id) > before:
		captions.append("%s mastery %d of 5." % [Items.info(id).name, mastery_level(id)])


static func save() -> void:
	if no_save:
		return
	data.stamp = now()
	var t := now()
	for id in data.respawn.keys():
		if int(data.respawn[id]) < t:
			data.respawn.erase(id)
	var text := JSON.stringify(data)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try{localStorage.setItem('%s', %s)}catch(e){}" % [WEB_KEY, JSON.stringify(text)], true)
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()


static func boon(id: String) -> int:
	return int(data.boons.get(id, 0))


static func add_boon(id: String) -> void:
	data.boons[id] = boon(id) + 1
	save()


static func roll_boons() -> Array:
	var pool: Array = []
	for id in BOONS:
		if boon(id) < int(BOONS[id].max):
			pool.append(id)
	pool.shuffle()
	return pool.slice(0, 3)


static func xp_needed() -> int:
	return 80 + 40 * int(data.level)


static func add_xp(amount: int) -> int:
	var gained := 0
	data.xp += amount
	while data.xp >= xp_needed():
		data.xp -= xp_needed()
		data.level += 1
		gained += 1
	return gained


static func skill_xp(id: String) -> int:
	return int(data.skills.get(id, 0))


static func skill(id: String) -> int:
	return Craft.level_for(skill_xp(id))


static func combat_level() -> int:
	var total := 0
	for sk in Craft.COMBAT:
		total += skill(sk)
	return maxi(int(round(float(total) / Craft.COMBAT.size())), 1)


static func total_level() -> int:
	var total := 0
	for sk in Craft.SKILLS:
		total += skill(sk)
	return total


static func train(id: String, amount: int) -> bool:
	if amount <= 0:
		return false
	var before := skill(id)
	data.skills[id] = skill_xp(id) + amount
	xp_log.append("+%d %s" % [amount, Craft.SKILLS[id].name])
	var after := skill(id)
	if after > before:
		captions.append("%s is now level %d." % [Craft.SKILLS[id].name, after])
		return true
	return false


static func mat(id: String) -> int:
	return int(data.mats.get(id, 0))


static func add_mat(id: String, n: int) -> void:
	data.mats[id] = maxi(mat(id) + n, 0)


static func eat_meal() -> int:
	for id in ["meal_cinder", "meal_pike", "meal_meat", "meal_trout"]:
		if mat(id) > 0:
			add_mat(id, -1)
			return int(Craft.MATS[id].meal)
	return 0


static func is_slain(id: String) -> bool:
	return data.slain.has(id) or data.tower_slain.has(id)


static func set_bonus(set_id: String) -> bool:
	return int(set_counts().get(set_id, 0)) >= 3


static func on_win(bonus_gold: int) -> Dictionary:
	var out := {"gold": 0, "cleared": false, "kind": "wild", "drops": []}
	if encounter.has("wild"):
		var f: Dictionary = Land.FOES[encounter.wild]
		out.gold = int(6 + int(f.level) * 1.6) + bonus_gold
		if randf() < 0.7:
			add_mat(f.drop, 1)
			out.drops.append(Craft.MATS[f.drop].name)
		set_respawn(encounter.get("id", ""), 150000)
		Quests.on_kill(encounter.wild)
		if data.task.get("foe", "") == encounter.wild and int(data.task.have) < int(data.task.need):
			data.task.have = int(data.task.have) + 1
			if int(data.task.have) >= int(data.task.need):
				captions.append("Hunt complete. Return to the Taskmaster.")
		data.gold += int(out.gold)
		data.kills += 1
		save()
		return out
	var kind: String = encounter.get("kind", "guardian")
	var id: String = encounter.get("id", "")
	var tier := int(data.floor)
	out.kind = kind
	out.gold = int(60 * tier * (1 + int(data.loop)) * {"lesser": 0.5, "elite": 1.0, "guardian": 1.6} [kind]) + bonus_gold
	data.gold += int(out.gold)
	data.kills += 1
	if kind == "lesser":
		data.tower_slain.append(id)
	elif id != "" and not data.slain.has(id):
		data.slain.append(id)
	if kind == "guardian":
		if tier >= FLOORS:
			out.cleared = true
			data.cinders += 1
			data.loop += 1
			data.floor = 1
			data.unlocked = 1
			data.slain = []
			data.opened = []
			data.tower_slain = []
			spawn = "entrance"
			captions.append(Story.TRUTH if data.relics.size() >= FLOORS else Story.CLEARED)
		else:
			data.unlocked = maxi(int(data.unlocked), tier + 1)
			captions.append("The way up is open.")
	data.best_floor = maxi(int(data.best_floor), int(data.unlocked) + FLOORS * int(data.loop))
	save()
	return out


static func on_lose() -> void:
	if data.in_tower:
		captions.append(Story.heir_letter(int(data.bloodline)))
		data.bloodline += 1
		data.floor = 1
		data.tower_slain = []
		spawn = "entrance"
	else:
		captions.append("You wake by the hearth in Hearthvale, sore but whole.")
	data.in_tower = false
	data.ow_x = Land.START.x
	data.ow_z = Land.START.z
	save()


static func home_scene() -> String:
	return "res://scenes/world.tscn" if data.in_tower else "res://scenes/overworld.tscn"


static func travel(to_tier: int, arrive_at: String) -> void:
	data.floor = clampi(to_tier, 1, FLOORS)
	data.tower_slain = []
	spawn = arrive_at
	captions.append(Story.inscription(int(data.floor), int(data.bloodline)))
	save()
