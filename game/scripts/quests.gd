class_name Quests
extends RefCounted

const NPCS := {
	"smith": "Brannoc the Smith", "elder": "Elder Maren", "alchemist": "Sister Wren",
	"fisher": "Old Tam", "ranger": "Warden Isolde", "villager": "Villager",
}

const QUESTS := {
	"forge": {
		"name": "The Cold Forge", "giver": "smith",
		"offer": ["My forge has been cold since the mine road went bad.", "Bring me four lumps of copper ore and two oak logs and I will light it again. I will make it worth your while."],
		"steps": [{"do": "bring", "to": "smith", "mats": {"copper_ore": 4, "oak_log": 2}, "text": "Bring Brannoc 4 copper ore and 2 oak logs. Copper rock lies in the Meadows and the Scar; oaks grow everywhere."}],
		"finish": ["There she goes. Hear that? A forge wants to be fed.", "Take these. A copper axe and pick, the first things off it. The anvil is yours to use whenever you like."],
		"reward": {"gold": 40, "xp": {"smithing": 150}, "tools": 1},
	},
	"line": {
		"name": "A Line in the Water", "giver": "fisher",
		"offer": ["Sixty years on this lake and my hands have given out.", "Catch me three trout from the river and I will show you what a fire is for."],
		"steps": [
			{"do": "bring", "to": "fisher", "mats": {"trout": 3}, "text": "Bring Old Tam 3 raw trout. Fish where ripples show on the river.", "say": ["Fine fish. Now grill one on my fire here and bring it over. Mind you do not burn it."]},
			{"do": "bring", "to": "fisher", "mats": {"meal_trout": 1}, "text": "Cook a trout on the Fisher's fire and bring it to Old Tam."},
		],
		"finish": ["That is supper. A cooked meal before a fight puts strength in you; remember that when you go north.", "The pike in my lake bite for anyone patient enough."],
		"reward": {"gold": 80, "xp": {"fishing": 200, "cooking": 150}},
	},
	"poach": {
		"name": "Poachers in Greywood", "giver": "ranger",
		"offer": ["Greywood was a king's forest once. Now it is bandits and poachers, and I am one warden.", "Put down three of them. Bandit or poacher, I am not particular."],
		"steps": [
			{"do": "kill", "foes": ["bandit", "poacher"], "need": 3, "text": "Defeat 3 bandits or poachers in Greywood."},
			{"do": "choose", "to": "ranger", "text": "Return to Warden Isolde at the end of the forest road.",
				"say": ["Three fewer. One of them carried this tally of every deer they sold, and to whom. Some names in Hearthvale are on it.", "They will have offered you coin to lose it. What did you do?"],
				"choices": [["I kept the tally. Here it is.", "tally"], ["I took their coin. The tally burned.", "bribe"]]},
		],
		"finish": ["The forest remembers who stood for it."],
		"reward": {"xp": {"slaying": 250}},
	},
	"mire": {
		"name": "What the Mire Keeps", "giver": "alchemist",
		"offer": ["The mire shrine has gone dark, and hexers gather where it stood.", "Bring me three bogroot for the rite. Then we shall see what you are made of."],
		"steps": [
			{"do": "bring", "to": "alchemist", "mats": {"bogroot": 3}, "text": "Bring Sister Wren 3 bogroot from Mirefen. Foraging 20 is needed to pick it.", "say": ["Good roots. I have steeped them. Carry the draught to the shrine at the end of the marsh road and pour it out."]},
			{"do": "reach", "place": "shrine", "text": "Go to the Mire shrine at the end of the south-west road.", "say": ["You pour the draught over the stone. Something in the reeds takes notice."]},
			{"do": "kill", "foes": ["hexer"], "need": 1, "text": "Defeat a Mire Hexer. Dodge its bolts, or parry at the last instant to send one back."},
			{"do": "talk", "to": "alchemist", "text": "Return to Sister Wren in Hearthvale."},
		],
		"finish": ["It burns again; I felt it from here.", "The hexers stole their craft from that shrine. Take a little of it back: this binds a foe in frost."],
		"reward": {"gold": 120, "xp": {"alchemy": 300, "sorcery": 200}, "item": "frost_bind"},
	},
	"oath": {
		"name": "The First Oath", "giver": "elder",
		"offer": ["You have the look of your line. They all came to me before they went north.", "Before you climb, see what you are climbing for. Stand at the tower gate. Then find the broken altar in the Old Ruins, where the oath was first sworn."],
		"steps": [
			{"do": "reach", "place": "tower", "text": "Walk the north road to the gate of the Ashgrave.", "say": ["The gate is warm to the touch. Your family name is cut into the stone, again and again, in the same hand."]},
			{"do": "reach", "place": "altar", "text": "Find the broken altar in the Old Ruins, north-east beyond the river.", "say": ["Under the moss: 'While one of us tends the fire, none of us need burn.' Below it, a second line, scratched later: 'A lie.'"]},
			{"do": "choose", "to": "elder", "text": "Return to Elder Maren by the hearth.",
				"say": ["So you have read it. Both lines.", "I have sent thirty of your blood up that road. Tell me what you believe, and I will stop pretending I know better."],
				"choices": [["The oath must be kept.", "keep"], ["The oath must end.", "end"]]},
		],
		"finish": ["Then go with your eyes open. That is more than the others had.", "Take this ring. It was the first heir's. It has come back down the stair thirty times."],
		"reward": {"xp": {"vitality": 300}, "item": "oath_ring"},
	},
}

const SMALL_TALK := [
	"The tower was quieter when I was young. Or I was.",
	"Tam at the lake says the pike are biting.",
	"Brannoc will forge anything if you bring the ore.",
	"Do not go into Mirefen without a flask or two.",
	"They say the stones east of the bridge hum at night.",
]


static func state(id: String) -> Dictionary:
	return Run.data.quests.get(id, {})


static func active(id: String) -> bool:
	return Run.data.quests.has(id) and not state(id).get("done", false)


static func step(id: String) -> Dictionary:
	return QUESTS[id].steps[int(state(id).step)]


static func progress(id: String) -> String:
	if state(id).get("done", false):
		return "Complete"
	var st := step(id)
	var text: String = st.text
	if st.do == "kill":
		text += "  (%d of %d)" % [int(state(id).get("count", 0)), st.need]
	return text


static func marker(npc: String) -> String:
	for id in QUESTS:
		var q: Dictionary = QUESTS[id]
		if not Run.data.quests.has(id):
			if q.giver == npc:
				return "!"
		elif active(id) and step(id).get("to", "") == npc:
			return "!"
	return ""


static func _has_mats(mats: Dictionary) -> bool:
	for m in mats:
		if Run.mat(m) < int(mats[m]):
			return false
	return true


static func _advance(id: String) -> Array:
	var st := state(id)
	var said: Array = step(id).get("say", [])
	st.step = int(st.step) + 1
	st.count = 0
	if int(st.step) >= QUESTS[id].steps.size():
		return said + _complete(id)
	Run.save()
	return said


static func _complete(id: String) -> Array:
	var q: Dictionary = QUESTS[id]
	state(id).done = true
	var r: Dictionary = q.reward
	var got: Array = []
	if r.has("gold"):
		Run.data.gold += int(r.gold)
		got.append("%d gold" % r.gold)
	for sk in r.get("xp", {}):
		Run.train(sk, int(r.xp[sk]))
	if r.has("item"):
		Run.add_item(r.item)
		got.append(Items.info(r.item).name)
	if r.has("tools"):
		Run.data.tools.axe = maxi(int(Run.data.tools.axe), int(r.tools))
		Run.data.tools.pick = maxi(int(Run.data.tools.pick), int(r.tools))
		got.append("copper axe and pick")
	Run.captions.append("Quest complete: %s.%s" % [q.name, ("  Received " + ", ".join(got) + ".") if not got.is_empty() else ""])
	Run.save()
	return q.finish


static func talk(npc: String) -> Dictionary:
	var out := {"name": NPCS.get(npc, npc), "lines": [], "choices": []}
	for id in QUESTS:
		var q: Dictionary = QUESTS[id]
		if not Run.data.quests.has(id):
			if q.giver == npc:
				out.lines = q.offer
				out.choices = [["I will do it.", "accept:" + id], ["Not now.", "bye"]]
				return out
			continue
		if not active(id):
			continue
		var st := step(id)
		if st.get("to", "") != npc:
			if q.giver == npc:
				out.lines = [progress(id)]
				return out
			continue
		match st.do:
			"bring":
				if _has_mats(st.mats):
					for m in st.mats:
						Run.add_mat(m, -int(st.mats[m]))
					out.lines = _advance(id)
				else:
					out.lines = [st.text]
			"talk":
				out.lines = _advance(id)
			"choose":
				out.lines = st.say
				for c in st.choices:
					out.choices.append([c[0], "choose:%s:%s" % [id, c[1]]])
		return out
	if npc == "villager":
		out.lines = [SMALL_TALK[randi() % SMALL_TALK.size()]]
	return out


static func act(action: String) -> Array:
	var parts := action.split(":")
	match parts[0]:
		"accept":
			Run.data.quests[parts[1]] = {"step": 0, "count": 0, "done": false}
			Run.captions.append("Quest started: %s." % QUESTS[parts[1]].name)
			Run.save()
			return [QUESTS[parts[1]].steps[0].text]
		"choose":
			var id := parts[1]
			Run.data.flags[id] = parts[2]
			match action:
				"choose:poach:tally":
					Run.add_item("hunters_bow")
					Run.add_mat("arrow", 30)
					Run.captions.append("Isolde gives you a Hunter's Bow and 30 arrows.")
				"choose:poach:bribe":
					Run.data.gold += 300
					Run.captions.append("You keep the poachers' 300 gold. Isolde says nothing.")
			return _advance(id)
	return []


static func on_kill(foe: String) -> void:
	for id in QUESTS:
		if active(id) and step(id).do == "kill" and foe in step(id).foes:
			state(id).count = int(state(id).get("count", 0)) + 1
			if int(state(id).count) >= int(step(id).need):
				for line in _advance(id):
					Run.captions.append(line)
				if active(id):
					Run.captions.append("%s: %s" % [QUESTS[id].name, step(id).text])


static func on_reach(place: String) -> void:
	for id in QUESTS:
		if active(id) and step(id).do == "reach" and step(id).place == place:
			for line in _advance(id):
				Run.captions.append(line)
			if active(id):
				Run.captions.append("%s: %s" % [QUESTS[id].name, step(id).text])
