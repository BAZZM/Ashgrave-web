# Ashgrave side quests, part one

As built (`game/scripts/quest_data_side.gd`). Layout and rules as `ACT2.md`. Nine quests, all written to the
review's rewrite notes. Every flag a quest writes is read in this slice; the table in section 2 says where.

## 1. Order of play

|#|id|Name|Giver|Opens when|State|
|---|---|---|---|---|---|
|1|`side_bread`|Hearth Bread|a villager|a1_stair done|NEW|
|2|`side_mine`|The Mine Road|Brannoc|a1_stair done, a1_bone done|NEW|
|3|`side_thralls`|Nan's Rows|Nan Harrow|a1_stair done|NEW|
|4|`side_marigold`|The Last Stake|Nan Harrow|a1_stair done, side_thralls done|NEW|
|5|`side_isolde`|Sore but Whole|Warden Isolde|a1_stair done, a1_struck done|NEW|
|6|`side_trader`|Trader's Tally|Warden Isolde|a1_stair done, poach done, flag:poach=tally, a1_struck done|NEW|
|7|`side_cloaks`|Wren's Cloaks|Sister Wren|a1_stair done, a1_diggers done, !active:side_hexer|NEW|
|8|`side_hexer`|A Hexer's Word|starts itself|a1_stair done, mire done, a2_flood done, !active:side_cloaks|NEW|
|9|`side_lie`|Who Wrote a Lie|Old Tam|a1_stair done, a1_tam done, a2_rune done|NEW|

Two pairs are mutually exclusive while one is active: `side_hexer` and `side_cloaks` both end at the Mire shrine,
so only one may be open at a time (`!active:`). `side_lie` waits for `a2_rune` so that Oswin is known and the
player holds cinder shards.

## 2. Choices and where they show

|Choice|Flag|Read in|
|---|---|---|
|Burn or bury the thralls' bone|`side_thralls`|`side_marigold` offer, step and finish; the quest's own journal|
|Post or hold the Trader's name|`side_trader`|villager and Isolde idle lines; the quest's own finish|
|Tell Wren what the hexer said, or stay silent|`side_hexer`|its own finish and journal; Wren's idle line|
|(Act 2 main) Tell or keep the Duelist's words|`a2_ending`|`a2_rune` finish; Maren's idle line|
|(Act 2 main) Read, give or keep the letter|`a2_letter`|`a2_letter` finish; Maren and Wren idle lines|

## 3. The quests

### 3.1 `side_bread`: Hearth Bread

```json
{
  "side_bread": {
    "name": "Hearth Bread",
    "act": 2,
    "order": 500,
    "giver": "villager",
    "requires": [
      "quest:a1_stair"
    ],
    "offer": [
      "My mother left bread on the hearthstone for the heirs going north. So do I. It never gets eaten.",
      "Sit and eat with me, once. Bring two grilled trout for the table, and I will cut the loaf."
    ],
    "accept": "I will bring the trout.",
    "decline": "Not now.",
    "steps": [
      {
        "do": "bring",
        "to": "villager",
        "mats": {
          "meal_trout": 2
        },
        "text": "Bring the villager 2 grilled trout for the hearthstone.",
        "track": "Bring 2 grilled trout",
        "say": [
          "Sit. Eat. I will watch the road, in case."
        ]
      },
      {
        "do": "talk",
        "to": "elder",
        "text": "Ask Elder Maren about the bread on the hearthstone.",
        "track": "Ask Maren about the bread",
        "say": [
          "The vale did not send you. I did. The bread is what the vale does with its hands.",
          "I did not ask them to leave it, and I did not ask them to stop."
        ]
      }
    ],
    "finish": [
      {
        "if": [
          [
            "bloodline>=2",
            "More loaves than I will say. I stopped counting them where I stopped counting you. Eat what they leave, while it is warm."
          ]
        ],
        "else": "Thirty loaves went out and none was eaten. I have counted those as well. Eat what they leave, while it is warm."
      }
    ],
    "reward": {
      "gold": 25,
      "xp": {
        "cooking": 60
      }
    },
    "journal": "Hearthvale leaves bread out for the heirs. Maren did not ask for it, and did not ask the village to stop."
  }
}
```

Trigger: a villager (the walker in Hearthvale) with `a1_stair` done. Bring two grilled trout, then tell Maren. The finish varies on `bloodline>=2`.

### 3.2 `side_mine`: The Mine Road

```json
{
  "side_mine": {
    "name": "The Mine Road",
    "act": 2,
    "order": 510,
    "giver": "smith",
    "requires": [
      "quest:a1_stair",
      "quest:a1_bone"
    ],
    "offer": [
      "The brutes have the mine road. I want iron and cannot get to it.",
      "Put three down on the Scar road. Bring me four iron ore from the rock they stand on. Mining 15 will take it."
    ],
    "accept": "I will clear the road.",
    "decline": "Not now.",
    "steps": [
      {
        "do": "kill",
        "foes": [
          "brute"
        ],
        "need": 3,
        "text": "Defeat 3 Stone Brutes on the mine road in the Scar.",
        "track": "Defeat 3 Stone Brutes",
        "say": [
          "A mark is struck into its back, small and deep. It is the mark under the grip of your own sword."
        ]
      },
      {
        "do": "bring",
        "to": "smith",
        "mats": {
          "iron_ore": 4
        },
        "text": "Bring Brannoc 4 iron ore. Mining 15 is needed; iron rock lies in the Scar.",
        "track": "Bring Brannoc 4 iron ore",
        "say": []
      }
    ],
    "finish": [
      {
        "if": [
          [
            "quest:a2_mark",
            "That mark again. Now I know where it is struck. I did not think a brute would carry one."
          ]
        ],
        "else": "That mark. I have felt it under every grip I ever refitted, and thought it was your family's pride. It was on a brute."
      },
      "A smith does not strike his mark on a thing he means to throw away. Whoever struck that did."
    ],
    "reward": {
      "gold": 70,
      "xp": {
        "mining": 120,
        "slaying": 100
      }
    },
    "journal": "Stone Brutes on the mine road carry the family's mark. Brannoc says no smith marks what he means to throw away."
  }
}
```

Trigger: talk to Brannoc with `a1_stair` and `a1_bone` done. Kill three brutes (the Scar), bring four iron ore. The finish varies on `quest:a2_mark`.

### 3.3 `side_thralls`: Nan's Rows

```json
{
  "side_thralls": {
    "name": "Nan's Rows",
    "act": 2,
    "order": 520,
    "giver": "nan",
    "requires": [
      "quest:a1_stair"
    ],
    "offer": [
      "Thralls walk my rows at night. They go along the furrows as if looking for a seed they dropped.",
      "Put three down, and bring me the bone. Then say what is to be done with it. I have never known."
    ],
    "accept": "I will clear them.",
    "decline": "Let them walk.",
    "steps": [
      {
        "do": "kill",
        "foes": [
          "thrall"
        ],
        "need": 3,
        "text": "Defeat 3 Field Thralls in the Meadows.",
        "track": "Defeat 3 Field Thralls",
        "say": [
          "It goes down between two furrows, face to the vale, as if it had been walking home."
        ]
      },
      {
        "do": "bring",
        "to": "nan",
        "mats": {
          "bone": 3
        },
        "text": "Bring Nan Harrow 3 old bone.",
        "track": "Bring Nan 3 old bone",
        "say": [
          "Three, and not a tooth missing. Leave them on the table. I have a fire and I have a spade, and I will want an answer."
        ]
      },
      {
        "do": "choose",
        "to": "nan",
        "text": "Tell Nan Harrow whether the bone is to be burned or buried.",
        "track": "Burn or bury the bone",
        "say": [
          "Well? Fire, or spade? Say which, and I will do it. I have never been sure of either."
        ],
        "choices": [
          [
            "Burn it on the fire.",
            "burn"
          ],
          [
            "Bury it in the rows.",
            "bury"
          ]
        ],
        "reply": {
          "burn": [
            "It burns slow, and smells of wet wool. The smoke leans south, toward the vale, like the rest of them."
          ],
          "bury": [
            "Buried, then. A stake over each, driven deep. Say a word over them if you like. They never answered me."
          ]
        }
      }
    ],
    "finish": [
      {
        "if": [
          [
            "flag:side_thralls=burn",
            "We will see what walks the rows tonight. Fire is quick, but the warmth is patient, and it calls."
          ]
        ],
        "else": "We will see what walks the rows tonight. A thing put in the ground sometimes stays there."
      }
    ],
    "reward": {
      "gold": 45,
      "xp": {
        "slaying": 90
      }
    },
    "journal": [
      {
        "if": [
          [
            "flag:side_thralls=burn",
            "The thralls' bone burned in Nan Harrow's fire. She does not expect them to stay gone."
          ]
        ],
        "else": "The thralls' bone lies in Nan Harrow's rows, a stake over each. She will see whether they stay down."
      }
    ]
  }
}
```

Trigger: talk to Nan Harrow (Meadows) with `a1_stair` done. Kill three thralls, bring three bone, then choose burn or bury. The choice is stored as `side_thralls` and read in `side_marigold` (four places) and its own offer text.

### 3.4 `side_marigold`: The Last Stake

```json
{
  "side_marigold": {
    "name": "The Last Stake",
    "act": 2,
    "order": 530,
    "giver": "nan",
    "requires": [
      "quest:a1_stair",
      "quest:side_thralls"
    ],
    "offer": [
      {
        "if": [
          [
            "flag:side_thralls=burn",
            "The burned ones have been back to the rows, thinner. They knocked over my last stake and stood a while."
          ]
        ],
        "else": "The buried ones have kept still. My stakes stand straight for the first time in years."
      },
      "I drive a stake wherever marigold stops. Every year it stops a row nearer the hearth, and ashbloom starts.",
      "Bring me three marigold for the last stake. Then ask Tam how far the warm reached when he was young."
    ],
    "accept": "I will fetch them.",
    "decline": "Not now.",
    "steps": [
      {
        "do": "bring",
        "to": "nan",
        "mats": {
          "marigold": 3
        },
        "text": "Bring Nan Harrow 3 marigold. It grows on open ground in the Meadows.",
        "track": "Bring Nan 3 marigold",
        "say": [
          "Set at the last stake. If they take, the line holds a year. If they do not, I drive another stake."
        ]
      },
      {
        "do": "talk",
        "to": "fisher",
        "text": "Ask Old Tam how far the warmth reached when he was young.",
        "track": "Ask Tam where the warmth ended",
        "say": [
          "Beans, past the stones, when I was a boy. Now I keep them in a pot by my fire. Tell her I could have told her for nothing."
        ]
      },
      {
        "do": "talk",
        "to": "nan",
        "text": "Return to Nan Harrow and tell her what Tam said.",
        "track": "Return to Nan Harrow",
        "say": [
          "Past the stones. That is farther back than any stake I have. I will drive one for his beans."
        ]
      }
    ],
    "finish": [
      "Marigold on this side of the stake, ashbloom on that. I did not choose where the line falls. I only mark it.",
      {
        "if": [
          [
            "flag:side_thralls=burn",
            "The burned ones stood at the stake again last night, thinner. The warmth does not forget them, and neither will I."
          ]
        ],
        "else": "The buried ones lie where I put them. It is the one thing in the Meadows I have managed to keep still."
      }
    ],
    "reward": {
      "gold": 50,
      "xp": {
        "foraging": 80
      }
    },
    "journal": "Nan stakes where marigold stops. The line moves a row nearer the hearth each year. Tam grew beans past the stones."
  }
}
```

Trigger: talk to Nan Harrow after `side_thralls`. Bring marigold, ask Old Tam, return to Nan. Reads `side_thralls`.

### 3.5 `side_isolde`: Sore but Whole

```json
{
  "side_isolde": {
    "name": "Sore but Whole",
    "act": 2,
    "order": 540,
    "giver": "ranger",
    "requires": [
      "quest:a1_stair",
      "quest:a1_struck"
    ],
    "offer": [
      "I stopped looking at the faces of the bandits on my road. After a while I began to know them.",
      "Put three down. Then go to Hearthvale and ask who woke on the hearthstone at dawn. Do not say why you ask."
    ],
    "accept": "I will go.",
    "decline": "Not now.",
    "steps": [
      {
        "do": "kill",
        "foes": [
          "bandit"
        ],
        "need": 3,
        "text": "Defeat 3 Greywood Bandits.",
        "track": "Defeat 3 Greywood Bandits",
        "say": [
          "It drops its knife and looks at your face. Not afraid. Only trying to place it."
        ]
      },
      {
        "do": "talk",
        "to": "villager",
        "text": "Ask a villager in Hearthvale who woke on the hearthstone at dawn.",
        "track": "Ask who woke on the hearthstone",
        "say": [
          "Three of them, at dawn, sore as if they had fallen off a roof. Strangers. They asked the way to Greywood and would not wait for bread.",
          "They had a look about them. Like someone I know. I could not say who."
        ]
      },
      {
        "do": "talk",
        "to": "ranger",
        "text": "Tell Warden Isolde what the villager said.",
        "track": "Return to Warden Isolde",
        "say": [
          "Three, and sore, and asking the road back to me. Yes.",
          "You put them down and they woke by the hearth. The same has happened to me four times."
        ]
      }
    ],
    "finish": [
      "They have your jaw. I have watched it come down this road at me for years, and I stopped looking.",
      "I refused the oath, and they took the road after me. That is what refusing costs. It is always another."
    ],
    "reward": {
      "gold": 40,
      "xp": {
        "archery": 80,
        "slaying": 100
      }
    },
    "journal": "Bandits put down in Greywood wake by the hearthstone. They have your jaw, and Isolde has stopped looking."
  }
}
```

Trigger: talk to Warden Isolde with `a1_struck` done. Kill three bandits (Greywood), talk to a villager, return to Isolde. No choice. Bandits wake on the hearthstone (see OWNER_QUESTIONS).

### 3.6 `side_trader`: Trader's Tally

```json
{
  "side_trader": {
    "name": "Trader's Tally",
    "act": 2,
    "order": 550,
    "giver": "ranger",
    "requires": [
      "quest:a1_stair",
      "quest:poach",
      "flag:poach=tally",
      "quest:a1_struck"
    ],
    "offer": [
      "The tally you gave me has a name I have kept quiet about. The Trader's. He bought the deer, and sold them back to the vale.",
      "I can post it or I can hold it. Ask the vale what it thinks of his venison. Then tell me which."
    ],
    "accept": "I will ask them.",
    "decline": "Not now.",
    "steps": [
      {
        "do": "talk",
        "to": "villager",
        "text": "Ask a villager in Hearthvale what the vale thinks of the Trader's venison.",
        "track": "Ask what the vale thinks",
        "say": [
          "The Trader's venison? Best in the vale, and half the price. Nobody asks where a bargain comes from."
        ]
      },
      {
        "do": "choose",
        "to": "ranger",
        "text": "Tell Warden Isolde: post the tally, or hold it over the Trader.",
        "track": "Post the tally or hold it",
        "say": [
          "Two uses for a list of names. Nail it where the vale can read it, or keep it and let him know we have it."
        ],
        "choices": [
          [
            "Post it on the hearthstone.",
            "post"
          ],
          [
            "Hold it over the Trader.",
            "hold"
          ]
        ],
        "reply": {
          "post": [
            "Then the vale reads what it has been eating. They will not thank me. They will not thank anyone."
          ],
          "hold": [
            "Then he pays in his own coin and goes on selling. I know what that makes us. I knew it when I took the tally."
          ]
        }
      }
    ],
    "finish": [
      {
        "if": [
          [
            "flag:side_trader=post",
            "It is on the stone. Come back in a week and see who has scratched it out."
          ]
        ],
        "else": "He will send me venison by the next full moon. I will not eat it. I will not say no, either."
      }
    ],
    "reward": {
      "gold": 60,
      "xp": {
        "archery": 60
      }
    },
    "journal": "The Trader's name was on the poachers' tally. You and Isolde settled what was to be done with it."
  }
}
```

Trigger: talk to Warden Isolde after `poach` was finished with the tally (`flag:poach=tally`) and `a1_struck` is done. A villager, then the choice to post the Trader's name or hold it. Stored as `side_trader`; read by the villagers' and Isolde's idle lines and by the quest's own text. Never offered after the bribe.

### 3.7 `side_cloaks`: Wren's Cloaks

```json
{
  "side_cloaks": {
    "name": "Wren's Cloaks",
    "act": 2,
    "order": 560,
    "giver": "alchemist",
    "requires": [
      "quest:a1_stair",
      "quest:a1_diggers",
      "!active:side_hexer"
    ],
    "offer": [
      "The moth has found my shelf, and it has started on the oldest cloak.",
      "Bring me four marigold. Laid in the wool, it keeps the moth out. They are all the shelf has to hold."
    ],
    "accept": "I will bring it.",
    "decline": "Not now.",
    "steps": [
      {
        "do": "bring",
        "to": "alchemist",
        "mats": {
          "marigold": 4
        },
        "text": "Bring Sister Wren 4 marigold. It grows on open ground in the Meadows.",
        "track": "Bring Wren 4 marigold",
        "say": [
          "Good. Between the folds, so. Now the part I cannot do myself. Take the newest cloak to the shrine and lay it in the water.",
          "The fen has no graves to give. The shrine is the nearest it comes."
        ]
      },
      {
        "do": "reach",
        "place": "shrine",
        "text": "Take the newest cloak to the Mire shrine and lay it in the water.",
        "track": "Go to the Mire shrine",
        "say": [
          "You lay the cloak in the shallows. It floats a while with the green light on it, and then goes down without a sound."
        ]
      },
      {
        "do": "talk",
        "to": "alchemist",
        "text": "Return to Sister Wren in Hearthvale.",
        "track": "Return to Sister Wren",
        "say": [
          "Gone down clean. I thought the reeds would catch it. Look at the shelf. There is one cloak more than I have heirs to put in it.",
          "New wool, cut to your shoulders. I did not ask. Do not look at it like that."
        ]
      }
    ],
    "finish": [
      "Maren dressed a stone for you. I cut cloth. Between the two of us you are very well provided for."
    ],
    "reward": {
      "gold": 50,
      "xp": {
        "alchemy": 100
      }
    },
    "journal": "The newest cloak lies in the Mire shrine. Wren's shelf holds one more than there are dead, cut to your measure."
  }
}
```

Trigger: talk to Sister Wren with `a1_diggers` done and no `side_hexer` active. Bring marigold, lay the cloak at the Mire shrine, return.

### 3.8 `side_hexer`: A Hexer's Word

```json
{
  "side_hexer": {
    "name": "A Hexer's Word",
    "act": 2,
    "order": 570,
    "giver": "alchemist",
    "auto": true,
    "requires": [
      "quest:a1_stair",
      "quest:mire",
      "quest:a2_flood",
      "!active:side_cloaks"
    ],
    "steps": [
      {
        "do": "reach",
        "place": "shrine",
        "text": "Go to the Mire shrine. Someone waits in the reeds who does not mean to fight.",
        "track": "Go to the Mire shrine",
        "say": [
          "A hexer waits by the shrine with her hands open. She was a Sister before she was this, and she will not fight today.",
          "'The flood wants a hand on the sluice, from inside. Whoever turns it stays. Ask Wren why she never said.'"
        ]
      },
      {
        "do": "choose",
        "to": "alchemist",
        "text": "Tell Sister Wren what the hexer said, or say nothing.",
        "track": "Tell Wren the hexer's word",
        "say": [
          "You smell of the fen, and you are quiet. Quiet means you heard something. Well?"
        ],
        "choices": [
          [
            "Tell her what the hexer said.",
            "tell"
          ],
          [
            "Say nothing of it.",
            "silent"
          ]
        ],
        "reply": {
          "tell": [
            "A hand on the sluice, from inside. Yes. The order would not write it down, and those who read it left.",
            "I said beside you, once. I should have said inside. I am sorry, and I am not yet sorry enough to stop."
          ],
          "silent": [
            "Nothing. As you like. The fen does not speak to everyone."
          ]
        }
      }
    ],
    "finish": [
      {
        "if": [
          [
            "flag:side_hexer=tell",
            "Do not carry it for me. I will ask when I am ready, or I will not ask at all."
          ]
        ],
        "else": "Keep your quiet, then. It is a kind of answer, and I will treat it as one."
      }
    ],
    "reward": {
      "gold": 40,
      "xp": {
        "sorcery": 120
      }
    },
    "journal": [
      {
        "if": [
          [
            "flag:side_hexer=tell",
            "A hexer at the shrine said the flood needs a hand on the sluice from inside. Wren said it was true."
          ]
        ],
        "else": "A hexer at the shrine said what the flood costs. You told Wren nothing of it."
      }
    ]
  }
}
```

Trigger: starts itself once `quest:mire` and `quest:a2_flood` are done and `side_cloaks` is not active. Reach the Mire shrine, then tell Wren what the hexer said or stay silent. Stored as `side_hexer`; read in its own finish and journal and in Wren's idle line.

### 3.9 `side_lie`: Who Wrote a Lie

```json
{
  "side_lie": {
    "name": "Who Wrote a Lie",
    "act": 2,
    "order": 580,
    "giver": "fisher",
    "requires": [
      "quest:a1_stair",
      "quest:a1_tam",
      "quest:a2_rune"
    ],
    "offer": [
      "I told you to look at the hands. Now look at a scratch. There is one under the oath at the altar, and I think I know the hand.",
      "Take a cinder shard and hold its edge to it. If it fits, show the shard to the elder, and watch him take it."
    ],
    "accept": "I will look.",
    "decline": "Not now.",
    "steps": [
      {
        "do": "reach",
        "place": "altar",
        "text": "Look at the scratch under the oath at the broken altar.",
        "track": "Look at the scratch",
        "say": [
          "A shallow scratch, wide at the start and thin at the end. The edge of a cinder shard would cut just so."
        ]
      },
      {
        "do": "bring",
        "to": "elder",
        "mats": {
          "cinder": 1
        },
        "text": "Bring Elder Maren a cinder shard. Ruin Keepers drop them; chests hold them.",
        "track": "Bring Maren a cinder shard",
        "say": [
          "Give it here. Edge down, thumb along the back. That is how it is held for cutting. I did not need to be shown.",
          "The tenth had gone up that spring. I sat at the stone with one of these until the light went, and cut two words I could not say aloud.",
          "Oswin will ask me why I did not cut it deeper. I will tell him the stone was already full."
        ]
      },
      {
        "do": "talk",
        "to": "fisher",
        "text": "Return to Old Tam at the lake.",
        "track": "Return to Old Tam",
        "say": [
          "His hand, then. I thought it might be. Sixty years, and I never said it, and nor did he."
        ]
      }
    ],
    "finish": [
      "He has never once sat at my fire. I will leave a trout out for him, in case.",
      "A man does not cut a thing like that into a stone unless he wishes it read. You read it. That will have to do."
    ],
    "reward": {
      "gold": 60,
      "xp": {
        "fishing": 100
      }
    },
    "journal": "Maren scratched 'A lie.' under the oath himself, with a cinder shard, after the tenth heir. Old Tam had guessed."
  }
}
```

Trigger: talk to Old Tam with `a1_tam` and `a2_rune` done. Reach the altar, bring Maren a cinder shard, return to Tam.

## 4. Idle lines

Added to `Quests.idle_lines` after Act 2's table (`SideData.IDLE`):

```json
{
  "villager": {
    "if": [
      [
        "flag:side_trader=post",
        "Someone nailed a list to the hearthstone. Half the vale has not spoken to the other half since."
      ],
      [
        "flag:side_trader=hold",
        "The Trader has been very kind to everyone this week. Free weight on the scale. I do not trust it."
      ],
      [
        "quest:side_bread",
        "I sat down and ate the bread myself, with one of you across from me. It was stale. I would do it again."
      ]
    ],
    "else": ""
  },
  "ranger": {
    "if": [
      [
        "flag:side_trader=post",
        "The list is on the stone. Half the vale will not look at me. The other half cannot read."
      ],
      [
        "flag:side_trader=hold",
        "He sends me venison. I do not eat it. I bury it by the watch."
      ],
      [
        "quest:side_isolde",
        "I looked at the next one's face today. I do not recommend it."
      ]
    ],
    "else": ""
  },
  "fisher": {
    "if": [
      [
        "quest:side_lie",
        "The elder has not come. I leave the trout out anyway. The gulls are well fed."
      ]
    ],
    "else": ""
  },
  "nan": {
    "if": [
      [
        "quest:side_marigold",
        "The last stake holds. Marigold on this side, ashbloom on that. Mind the line when you cross it."
      ]
    ],
    "else": "Rows want weeding. Thralls want something else."
  }
}
```

## 5. Deferred, with the reason

|id|Why it is not in part one|
|---|---|
|`a2_key`|Needs the tower trader to talk (a hook in the tower, not in the quest engine). The review calls it the weakest stretch and wants it rewritten. Part two.|
|`a2_roost`|Needs the casino place and a stake hook; a gold cost on a choice. Part two.|
|`side_pye`|Needs Thieving and Mag Pye's purse; the draft's `find` step has no relic and errors today.|
|`side_stones`|Cut. It is the second ring and Runecraft; the review merges it into a part-two side quest.|
|`side_keepers`|Merged into `a2_rune`.|
|`side_cousin`|Needs an online duel result fed into the quest engine and a live opponent. The online message format must not change.|
|`side_plot`|Needs clans, a new place and a banner stone. Part two.|
|Pyre Guard barks|One display name serves the Ashlands foe and the tier 5 lesser; the line fits one and not the other. Act 3.|
