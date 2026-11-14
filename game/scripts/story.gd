class_name Story
extends RefCounted

const Act1 := preload("res://scripts/quest_data_act1.gd")

const INSCRIPTIONS := {
	1: ["Here the oath was first spoken. Here it is still owed.", "Ash keeps what fire forgets.", "Your father's name is on this gate. So is his father's."],
	2: ["The cisterns were dug to drown the pyre. They failed.", "Still water remembers every face that looked into it."],
	3: ["Every blade that fell in this tower was reforged here.", "The Foundry does not ask whose steel it melts."],
	4: ["The rooks left when the Regent stopped sleeping.", "From here you can see how far your line has climbed, and no farther."],
	5: ["The fire is not his. He only tends it.", "Put it out, and learn what it was keeping warm."],
}

const BARKS := {
	"The Cinder Warden": {"intro": "Another of the blood. Turn back, child.", "again": "You again, in a new face.", "enrage": "I held this stair before your line had a name!", "death": "He will be glad of you. That is the horror of it."},
	"Ashbound Duelist": {"intro": "Show me what they taught you.", "again": "Your grandmother was faster.", "enrage": "Good. Now I am awake.", "death": "Ask him... why the oath has no ending."},
	"Gravemaul": {"intro": "SMALL.", "again": "SMALL. AGAIN.", "enrage": "BREAK.", "death": "...small things... keep coming..."},
	"Keeper of the Grave Gate": {"intro": "I buried every heir who reached me. I kept their swords.", "again": "I know that sword. I buried its last owner.", "enrage": "None have passed!", "death": "Then pass. And forgive us."},
	"The Hollow Regent": {"intro": "You have my eyes. They all do.", "again": "Come. Feed the fire again.", "enrage": "I swore the first oath! I AM the oath!", "death": "It will need a keeper. It always needs a keeper."},
}

const HEIR_LETTERS := [
	"To my heir: the stair is steep, but our cause is just. Finish it.",
	"To my heir: I got further than my mother. Get further than me.",
	"To my heir: the guardians know our name. Ask yourself why.",
	"To my heir: I saw his face under the helm. I will not write what I saw.",
	"To my heir: do not swear the oath as I did. Read it first.",
	"To my heir: if you can stop climbing, stop. I could not.",
]

const RELICS := {
	1: {"name": "The First Vow", "text": "A cracked tablet. The oath is carved in one hand; every heir's name beneath it is carved in the same hand."},
	2: {"name": "Drowned Crown", "text": "A plain iron circlet, child-sized. The Regent was crowned before he could lift a sword."},
	3: {"name": "Unfinished Blade", "text": "A sword left in the forge for an age. The maker's mark is your family's."},
	4: {"name": "Rook's Letter", "text": "'Brother, the fire only burns while one of us tends it. I will go up. Send no one after me.'"},
	5: {"name": "The Pyre Ember", "text": "It is warm, and it knows your name. The Regent was the first of your line. The oath keeps him alive, and you keep the oath."},
}

const CLEARED := "The tower falls silent. Then, far below, a gate opens for the next of your blood."
const TRUTH := "You hold all five relics. The fire was never his to keep. Next time, you may stay your hand."


static func inscription(tier: int, bloodline: int) -> String:
	var pool: Array = INSCRIPTIONS.get(tier, [""])
	return pool[(bloodline - 1) % pool.size()]


static func bark(enemy_name: String, moment: String, met_before := false) -> String:
	var b: Dictionary = BARKS.get(enemy_name, Act1.BARKS.get(enemy_name, {}))
	if moment == "intro" and met_before and b.has("again"):
		return b.again
	var v: Variant = b.get(moment, "")
	if v is Array:
		return v[randi() % v.size()] if not v.is_empty() else ""
	return v


## Lore found so far is kept in Run.data.lore (ids). "insc<tier>_<n>" is a tower inscription, "relic<n>" a
## relic; anything else is a key of Act1.LORE. Returns true if it was new.
static func found(id: String) -> bool:
	if Run.data.lore.has(id):
		return false
	Run.data.lore.append(id)
	Quests.touch()
	return true


static func lore_entry(id: String) -> Dictionary:
	if id.begins_with("insc"):
		var p := id.substr(4).split("_")
		var pool: Array = INSCRIPTIONS.get(int(p[0]), [""])
		return {"name": "Inscription: %s" % Tiers.THEMES[int(p[0])].name, "text": pool[int(p[1]) % pool.size()]}
	if id.begins_with("relic"):
		return RELICS.get(int(id.substr(5)), {"name": id, "text": ""})
	return Act1.LORE.get(id, {"name": id, "text": ""})


## Record a tower inscription as read.
static func read_inscription(tier: int, bloodline: int) -> void:
	var n: int = INSCRIPTIONS.get(tier, [""]).size()
	found("insc%d_%d" % [tier, (bloodline - 1) % n])


static func heir_letter(bloodline: int) -> String:
	return HEIR_LETTERS[mini(bloodline - 1, HEIR_LETTERS.size() - 1)]
