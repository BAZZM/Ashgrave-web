## The five quests that shipped before Act 1, in the quest schema (docs/STORY_BIBLE.md section 9).
## Their ids, steps, step text, say lines, choices, finish lines and rewards are exactly as they were in
## quests.gd, so a save made on an older build finds itself at the same step. Added keys: act, order, requires
## (none: they are open from the start) and `track`, the short tracker line for each step.
extends RefCounted

const QUESTS := {
	"forge": {
		"name": "The Cold Forge", "giver": "smith", "act": 1, "order": 15, "requires": [],
		"offer": ["My forge has been cold since the mine road went bad.", "Bring me four lumps of copper ore and two oak logs and I will light it again. I will make it worth your while."],
		"steps": [{"do": "bring", "to": "smith", "mats": {"copper_ore": 4, "oak_log": 2}, "text": "Bring Brannoc 4 copper ore and 2 oak logs. Copper rock lies in the Meadows and the Scar; oaks grow everywhere.", "track": "Bring Brannoc 4 copper, 2 oak"}],
		"finish": ["There she goes. Hear that? A forge wants to be fed.", "Take these. A copper axe and pick, the first things off it. The anvil is yours to use whenever you like."],
		"reward": {"gold": 40, "xp": {"smithing": 150}, "tools": 1},
	},
	"line": {
		"name": "A Line in the Water", "giver": "fisher", "act": 1, "order": 25, "requires": [],
		"offer": ["Sixty years on this lake and my hands have given out.", "Catch me three trout from the river and I will show you what a fire is for."],
		"steps": [
			{"do": "bring", "to": "fisher", "mats": {"trout": 3}, "text": "Bring Old Tam 3 raw trout. Fish where ripples show on the river.", "track": "Bring Old Tam 3 raw trout", "say": ["Fine fish. Now grill one on my fire here and bring it over. Mind you do not burn it."]},
			{"do": "bring", "to": "fisher", "mats": {"meal_trout": 1}, "text": "Cook a trout on the Fisher's fire and bring it to Old Tam.", "track": "Bring Old Tam a grilled trout"},
		],
		"finish": ["That is supper. A cooked meal before a fight puts strength in you; remember that when you go north.", "The pike in my lake bite for anyone patient enough."],
		"reward": {"gold": 80, "xp": {"fishing": 200, "cooking": 150}},
	},
	"poach": {
		"name": "Poachers in Greywood", "giver": "ranger", "act": 1, "order": 35, "requires": [],
		"offer": ["Greywood was a king's forest once. Now it is bandits and poachers, and I am one warden.", "Put down three of them. Bandit or poacher, I am not particular."],
		"steps": [
			{"do": "kill", "foes": ["bandit", "poacher"], "need": 3, "text": "Defeat 3 bandits or poachers in Greywood.", "track": "Defeat 3 bandits or poachers"},
			{"do": "choose", "to": "ranger", "text": "Return to Warden Isolde at the end of the forest road.", "track": "Return to Warden Isolde",
				"say": ["Three fewer. One of them carried this tally of every deer they sold, and to whom. Some names in Hearthvale are on it.", "They will have offered you coin to lose it. What did you do?"],
				"choices": [["I kept the tally. Here it is.", "tally"], ["I took their coin. The tally burned.", "bribe"]]},
		],
		"finish": ["The forest remembers who stood for it."],
		"reward": {"xp": {"slaying": 250}},
	},
	"mire": {
		"name": "What the Mire Keeps", "giver": "alchemist", "act": 1, "order": 45, "requires": [],
		"offer": ["The mire shrine has gone dark, and hexers gather where it stood.", "Bring me three bogroot for the rite. Then we shall see what you are made of."],
		"steps": [
			{"do": "bring", "to": "alchemist", "mats": {"bogroot": 3}, "text": "Bring Sister Wren 3 bogroot from Mirefen. Foraging 20 is needed to pick it.", "track": "Bring Sister Wren 3 bogroot", "say": ["Good roots. I have steeped them. Carry the draught to the shrine at the end of the marsh road and pour it out."]},
			{"do": "reach", "place": "shrine", "text": "Go to the Mire shrine at the end of the south-west road.", "track": "Go to the Mire shrine", "say": ["You pour the draught over the stone. Something in the reeds takes notice."]},
			{"do": "kill", "foes": ["hexer"], "need": 1, "text": "Defeat a Mire Hexer. Dodge its bolts, or parry at the last instant to send one back.", "track": "Defeat a Mire Hexer"},
			{"do": "talk", "to": "alchemist", "text": "Return to Sister Wren in Hearthvale.", "track": "Return to Sister Wren"},
		],
		"finish": ["It burns again; I felt it from here.", "The hexers stole their craft from that shrine. Take a little of it back: this binds a foe in frost."],
		"reward": {"gold": 120, "xp": {"alchemy": 300, "sorcery": 200}, "item": "frost_bind"},
	},
	"oath": {
		"name": "The First Oath", "giver": "elder", "act": 1, "order": 100, "requires": [],
		"offer": ["You have the look of your line. They all came to me before they went north.", "Before you climb, see what you are climbing for. Stand at the tower gate. Then find the broken altar in the Old Ruins, where the oath was first sworn."],
		"steps": [
			{"do": "reach", "place": "tower", "text": "Walk the north road to the gate of the Ashgrave.", "track": "Walk to the tower gate", "say": ["The gate is warm to the touch. Your family name is cut into the stone, again and again, in the same hand."]},
			{"do": "reach", "place": "altar", "text": "Find the broken altar in the Old Ruins, north-east beyond the river.", "track": "Find the broken altar", "say": ["Under the moss: 'While one of us tends the fire, none of us need burn.' Below it, a second line, scratched later: 'A lie.'"]},
			{"do": "choose", "to": "elder", "text": "Return to Elder Maren by the hearth.", "track": "Return to Elder Maren",
				"say": ["So you have read it. Both lines.", "I have sent thirty of your blood up that road. Tell me what you believe, and I will stop pretending I know better."],
				"choices": [["The oath must be kept.", "keep"], ["The oath must end.", "end"]]},
		],
		"finish": ["Then go with your eyes open. That is more than the others had.", "Take this ring. It was the first heir's. It has come back down the stair thirty times."],
		"reward": {"xp": {"vitality": 300}, "item": "oath_ring"},
	},
}
