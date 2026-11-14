## Act 1 quest data, pasted verbatim from docs/story/ACT1.md (schema: docs/STORY_BIBLE.md section 9).
## Do not edit the story text here; edit ACT1.md and regenerate.
extends RefCounted

const QUESTS := {
	"a1_thirty_first": {
		"name": "The Thirty-First",
		"act": 1,
		"order": 10,
		"giver": "elder",
		"requires": [],
		"offer": [
			{
				"if": [
					[
						"bloodline>=2",
						"Another of the blood. I stopped counting at thirty, and I will not start again for you."
					]
				],
				"else": "So. The thirty-first. You have the walk of the thirtieth, and I watched him go."
			},
			"Before I send you north, ask Brannoc what came back down the stair. Then ask Sister Wren what did not."
		],
		"accept": "I will ask them.",
		"decline": "Not now.",
		"steps": [
			{
				"do": "talk",
				"to": "smith",
				"text": "Ask Brannoc the Smith what came back down the stair.",
				"track": "Ask Brannoc what came down",
				"say": [
					"The arms you were given belonged to the heir before you. Sword, sallet, plate, shield. I changed the straps and nothing else.",
					"Each time one of you falls, they are at the gate by morning. Laid out. Cleaned. The blade comes down better than it went up.",
					"I do not know who lays them there. I fit them to the next of you, and I do not ask."
				]
			},
			{
				"do": "talk",
				"to": "alchemist",
				"text": "Ask Sister Wren what did not come back down.",
				"track": "Ask Sister Wren what did not",
				"say": [
					"A body. In all the years of the oath, the tower has not sent down one. I have a shelf of folded cloaks and nothing to put in them.",
					"The thirtieth left this with me, and not with the elder. Think on why before you read it.",
					"'To my heir: Maren will offer you a ring. Before you take it, count the names on the altar. Then count the spaces.'"
				]
			},
			{
				"do": "talk",
				"to": "elder",
				"text": "Return to Elder Maren by the hearth.",
				"track": "Return to Elder Maren",
				"say": [
					"Arms and no body. Now you know as much as the village does.",
					"The tower wants the next of you armed. I have never learned why it troubles to be kind."
				]
			}
		],
		"finish": [
			"Walk the land before you walk the stair. The forge, the lake, the wood, the mire. Each will tell you something I cannot.",
			{
				"if": [
					[
						"quest:oath",
						"You wear the ring already. Then you have read the altar, and you know why I do not hurry you."
					]
				],
				"else": "The ring comes last. It always does."
			}
		],
		"reward": {
			"gold": 30,
			"xp": {
				"vitality": 60
			},
			"lore": [
				"letter_thirtieth"
			]
		},
		"journal": "Thirty went up. Their arms came back cleaned, and never a body. The thirtieth left his letter with Sister Wren, not with Maren."
	},
	"a1_bone": {
		"name": "What Walks South",
		"act": 1,
		"order": 20,
		"giver": "smith",
		"requires": [
			"quest:forge"
		],
		"offer": [
			"Since the forge was lit, the field thralls come closer at night. They stand at the edge of the light and do nothing.",
			"Put two of them down and bring me the bone. I want to see what they are made of."
		],
		"accept": "I will bring it.",
		"decline": "Not now.",
		"steps": [
			{
				"do": "bring",
				"to": "smith",
				"mats": {
					"bone": 2
				},
				"text": "Bring Brannoc 2 old bones. Field Thralls in the Meadows carry them.",
				"track": "Bring Brannoc 2 old bones"
			}
		],
		"finish": [
			"Burnt through. This did not die this year, or this age. This died in the Burning.",
			"They are not hunting. They walk south each night, toward the hearth, the way a cold man walks toward a window.",
			"I will tell Maren. Maren will say what Maren always says. Leave them be."
		],
		"reward": {
			"gold": 40,
			"xp": {
				"slaying": 80,
				"smithing": 60
			}
		},
		"journal": "The thralls of the Meadows are the dead of the Burning. They walk south toward the hearth and stop at the edge of its light."
	},
	"a1_tam": {
		"name": "Sixty Winters",
		"act": 1,
		"order": 30,
		"giver": "fisher",
		"requires": [
			"quest:line"
		],
		"offer": [
			"You cook like one of your line. I have fed a few of them at this fire, going north.",
			"Go and stand in the stone ring west of here. Then come back and tell me what you hear."
		],
		"accept": "I will listen.",
		"decline": "Not now.",
		"steps": [
			{
				"do": "reach",
				"place": "circle",
				"text": "Stand in the standing stones, west of the Fisher's fire.",
				"track": "Stand in the standing stones",
				"say": [
					"The hum is not in the stones. It comes up through your boots, and it comes from the north."
				]
			},
			{
				"do": "talk",
				"to": "fisher",
				"text": "Return to Old Tam at the lake.",
				"track": "Return to Old Tam",
				"say": [
					"From the north. It was fainter when I was a boy. Each time one of you goes up, it is a little louder after."
				]
			}
		],
		"finish": [
			"Here is another thing sixty years will show you. Maren was old when I was a boy. Same cloak. Same hands.",
			"I have buried my father, my wife and two dogs. The elder has not aged a day I could swear to.",
			"I do not say it is wrong. I say look at the hands."
		],
		"reward": {
			"gold": 40,
			"xp": {
				"fishing": 80
			},
			"mats": {
				"meal_trout": 2
			}
		},
		"journal": "The ground hums from the north, louder after every heir. Old Tam says Elder Maren was already old sixty years ago."
	},
	"a1_struck": {
		"name": "The Struck Name",
		"act": 1,
		"order": 40,
		"giver": "ranger",
		"requires": [
			"quest:poach"
		],
		"offer": [
			{
				"if": [
					[
						"flag:poach=bribe",
						"You sold my forest for three hundred gold. Good. Then you will follow the next thing better than most."
					]
				],
				"else": "You gave up coin for a list of names. So I will give you a name for nothing."
			},
			"Go to the fallen watchtower, north-east through the wood. Read the stump. Then come and say it to my face."
		],
		"accept": "I will read it.",
		"decline": "Not now.",
		"steps": [
			{
				"do": "reach",
				"place": "watch",
				"text": "Find the fallen watchtower in Greywood, north-east of Warden Isolde.",
				"track": "Find the fallen watchtower",
				"say": [
					"Cut in the stump, small and neat: ISOLDE. Through it, one deep stroke from a different knife."
				]
			},
			{
				"do": "talk",
				"to": "ranger",
				"text": "Return to Warden Isolde at the end of the forest road.",
				"track": "Return to Warden Isolde",
				"say": [
					"My name, in the elder's cutting. I was to be the thirtieth. I struck it out myself and came here.",
					"The oath went looking and took the next of us instead. You know who went. You were handed his sword.",
					"Bandits have killed me four times since. Each time I wake by the hearth, sore but whole, and walk back. None of the blood can die out here."
				]
			}
		],
		"finish": [
			"So here is my counsel, and it is the opposite of Maren's. Do not go. The oath cannot kill you unless you climb.",
			"And if you go anyway, do not go for me. I have enough of your line on my account."
		],
		"reward": {
			"xp": {
				"slaying": 150,
				"archery": 100
			},
			"mats": {
				"arrow": 20
			}
		},
		"journal": "Isolde was named the thirtieth and struck her own name out. Another went in her place. None of the blood can die outside the tower."
	},
	"a1_diggers": {
		"name": "Still Digging",
		"act": 1,
		"order": 50,
		"giver": "alchemist",
		"requires": [
			"quest:mire"
		],
		"offer": [
			"The shrine burns green again. You should know what you relit. It is a waymark, and it points at the tower.",
			"My order cut the cisterns into the Ashgrave to drown the pyre. They failed, and they did not all come home.",
			"Some walk the fen as wights. Lay two down, and I will tell you what they dug toward."
		],
		"accept": "I will lay them down.",
		"decline": "Not now.",
		"steps": [
			{
				"do": "kill",
				"foes": [
					"wight"
				],
				"need": 2,
				"text": "Defeat 2 Bog Wights in Mirefen.",
				"track": "Defeat 2 Bog Wights",
				"say": [
					"The wight folds into the water. Its hands keep moving a moment longer, as if at a spade."
				]
			},
			{
				"do": "talk",
				"to": "alchemist",
				"text": "Return to Sister Wren in Hearthvale.",
				"track": "Return to Sister Wren",
				"say": [
					"Sisters, once. They dug until the water took them, and after. That is what an oath does with a person."
				]
			}
		],
		"finish": [
			"They failed because they dug in secret, and alone. I will not make their mistake. I mean to ask one of the blood.",
			"Maren will tell you the fire keeps us. Ask what it keeps, and watch which fire the elder looks at."
		],
		"reward": {
			"gold": 60,
			"xp": {
				"alchemy": 150
			},
			"mats": {
				"bogroot": 2
			}
		},
		"journal": "The Sisters dug the cisterns to drown the pyre, and failed. Wren means to try again, and she wants one of the blood beside her."
	},
	"a1_hand": {
		"name": "In One Hand",
		"act": 1,
		"order": 60,
		"giver": "elder",
		"auto": true,
		"requires": [
			"quest:oath",
			"quest:a1_thirty_first"
		],
		"steps": [
			{
				"do": "reach",
				"place": "altar",
				"text": "The thirtieth wrote: count the names, then the spaces. Go back to the broken altar.",
				"track": "Count the names on the altar",
				"say": [
					"Thirty names, all in one neat hand. Below the last, a thirty-first space has been dressed smooth.",
					"The stone dust in it is new."
				]
			},
			{
				"do": "choose",
				"to": "elder",
				"text": "Return to Elder Maren by the hearth.",
				"track": "Return to Elder Maren",
				"say": [
					"You went back to the altar. The thirtieth told you to, I suppose. He counted too.",
					"Well. You have seen the space. Ask what you came to ask."
				],
				"choices": [
					[
						"Whose hand cut the names?",
						"ask"
					],
					[
						"You have cut my place already.",
						"accuse"
					]
				],
				"reply": {
					"ask": [
						"Mine. Every name on the altar, and every one on the gate. I cut each when the ring comes back down."
					],
					"accuse": [
						"I dressed that stone the day you came into the vale. I have never once needed to leave a space empty."
					]
				}
			}
		],
		"finish": [
			"I cut them so that someone does. The tower sends down arms. It does not send down names.",
			"But I have never passed the gate. One letter that came down spoke of a tablet inside: the oath, and all your names under it.",
			"I did not cut that one. I have wanted for a long time to know who did."
		],
		"reward": {
			"xp": {
				"vitality": 150
			}
		},
		"journal": "Maren cut every name on the altar and the gate, and has dressed a space for yours. Someone inside the tower keeps a list too."
	},
	"a1_stair": {
		"name": "The First Stair",
		"act": 1,
		"order": 70,
		"giver": "elder",
		"requires": [
			"quest:a1_hand"
		],
		"offer": [
			"I will ask a thing of you that I asked of none of the thirty. Not to reach the top. Only to pass the gate and read.",
			"Find the tablet. Face the Warden on the first stair. Then come down and tell me what he said. None of the thirty did."
		],
		"accept": "I will pass the gate.",
		"decline": "Not yet.",
		"steps": [
			{
				"do": "find",
				"relic": 1,
				"text": "Enter the Ashgrave. Find the tablet in the side chamber off the entry hall.",
				"track": "Find the tablet inside the gate",
				"say": [
					"Small, neat letters. It is the hand from the altar. But Maren has never passed the gate."
				]
			},
			{
				"do": "win",
				"tier": 1,
				"text": "Defeat the Cinder Warden, guardian of the first stair.",
				"track": "Defeat the Cinder Warden",
				"say": [
					"You were asked to carry word down. Leave by the gate behind you."
				]
			},
			{
				"do": "choose",
				"to": "elder",
				"text": "Go down to Hearthvale and tell Elder Maren what you found.",
				"track": "Tell Maren what you found",
				"say": [
					"You came back down. No one who faced the Warden has, in all my years. The tablet, then the Warden. What did he say?"
				],
				"choices": [
					[
						"Tell Maren everything.",
						"all"
					],
					[
						"Keep back the Warden's words.",
						"keep"
					]
				],
				"reply": {
					"all": [
						"'He will be glad of you.' Glad. Then he is still himself, somewhere in it."
					],
					"keep": [
						"Nothing you will repeat. Very well. Keep it. I have kept worse."
					]
				}
			}
		],
		"finish": [
			"The hand on the tablet is the hand on the altar. It would be. We learned our letters at one table, he and I.",
			"My brother carved it. He went up before your line had a name, and I have been sending you after him ever since.",
			"Do not ask me yet whether you are to bring him down or keep him company. I have had longer than anyone to decide.",
			"Brannoc found a second sword at the gate this morning, cleaned and laid out. The Warden's. Take it. He meant it for you."
		],
		"reward": {
			"gold": 150,
			"xp": {
				"blade": 200,
				"vitality": 200
			},
			"item": "wardens_brand",
			"flags": {
				"act": "2"
			}
		},
		"journal": "The tablet is in the hand of Maren's brother, who went up before the line had a name. Maren has sent heirs after him ever since. It is the Warden who lays the arms at the gate."
	}
}

const LORE := {
	"letter_thirtieth": {
		"name": "Letter of the Thirtieth",
		"text": "To my heir: Maren will offer you a ring. Before you take it, count the names on the altar. Then count the spaces."
	}
}

const BARKS := {
	"Sworn Blade": {
		"intro": "I swore to him when he was a boy. I know no other thing.",
		"enrage": "The Warden is too gentle with you!",
		"death": "Tell the Warden... I held as long as he asked."
	},
	"Ash Thrall": {
		"intro": [
			"...the gate... is warm...",
			"...whose name?...",
			""
		],
		"death": "...warm..."
	},
	"Field Thrall": {
		"intro": [
			"...south...",
			"...a light...",
			""
		],
		"death": "...cold again..."
	},
	"Bog Wight": {
		"intro": [
			"...deeper...",
			"...almost through...",
			""
		],
		"death": "...Sister... is it out?..."
	},
	"Mire Hexer": {
		"intro": [
			"The shrine gave freely. I only took more.",
			"Wren sent you. She sends everyone."
		],
		"enrage": "It was ours before it was hers!",
		"death": "...ask her... what the cisterns cost..."
	},
	"Greywood Bandit": {
		"intro": [
			"Purse first. Then we can both go home.",
			"The warden cannot be everywhere. You can."
		],
		"death": "...she will only... get up again..."
	},
	"Greywood Poacher": {
		"intro": [
			"Deer do not carry coin. You do.",
			""
		],
		"death": "...the tally... burn it..."
	}
}

const IDLE := {
	"elder": {
		"if": [
			[
				"loop>=1",
				"You reached the top, and the fire still burns. Sit. I am not surprised. Only sorry."
			],
			[
				"bloodline>=2",
				"You have the last one's hands already. The hearth is quick about that."
			]
		],
		"else": "The hearth is lit. That is all the news I trust."
	},
	"alchemist": {
		"if": [
			[
				"bloodline>=2",
				"Another cloak for the shelf. I folded it myself."
			]
		],
		"else": "Marigold for one flask. Bogroot for two. The mire is generous to the patient."
	},
	"fisher": {
		"if": [
			[
				"bloodline>=2",
				"A new face and the same cast. I have stopped being surprised."
			]
		],
		"else": "The pike are biting. They do not care who climbs."
	},
	"ranger": {
		"if": [
			[
				"bloodline>=2",
				"You went, then. And here you are again, with someone else's eyes."
			]
		],
		"else": "One warden. Count the trees and tell me if it is enough."
	},
	"villager": {
		"if": [
			[
				"quest:a1_stair",
				"They say someone came back down. My mother would not have believed it."
			],
			[
				"quest:a1_bone",
				"Brannoc says leave the thralls be. Brannoc does not hang washing by the north wall."
			]
		],
		"else": ""
	}
}
