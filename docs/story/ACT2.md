# Ashgrave Act 2, part one: The Drowned Crown

This is the text of part one exactly as built (`game/scripts/quest_data_act2.gd`, merged by `quests.gd`). It
follows `docs/story/ACT1.md` in layout and `docs/STORY_BIBLE.md` section 9 in schema. Every block is valid
JSON. It was written from the editor's review (`docs/story/REVIEW_S3.md`); where the bible and the review
disagree the bible wins, and the cases are in `OWNER_QUESTIONS.md`.

**What the part does.** The player has the first relic and has left the Warden's stair. In five quests they
learn that the Drowned Crown was made for a child and worn for years (`a2_flood`), choose whether to tell the
elder that the dead duelist was his own (`a2_ending`), find a mark on every blade that comes down the stair
(`a2_mark`), hear the oath read plain by the Keeper who heard it first sworn (`a2_rune`), and decide what to do with a
letter the elder never received (`a2_letter`). The side quests are in `SIDE_QUESTS.md`.

## 1. Order of play

|#|id|Name|Giver|Opens when|State|
|---|---|---|---|---|---|
|1|`a2_flood`|Drowned Crown|Sister Wren|a1_stair done|NEW|
|2|`a2_ending`|No Ending|starts itself|a1_stair done, tier:2|NEW|
|3|`a2_mark`|The Maker's Mark|Brannoc|a1_stair done, a1_bone done|NEW|
|4|`a2_rune`|The Wording|Keeper Oswin|a2_ending done|NEW|
|5|`a2_letter`|Rook's Letter|starts itself|a1_stair done, relic:4|NEW|

Offers go by `order`: `a2_flood` sits at 44, the other main-line quests at 210 to 240, the side quests at 500 and above. The main line has one hard order: `a2_ending` before `a2_rune`.
The tower sets the rest: relic 2 and tier 2 for the flood and the ending, relic 3 and tier 3 for the mark,
relic 4 and tier 4 for the letter. Level bands: the Old Ruins keepers in `a2_rune` are level 38.

## 2. The quests

### 2.1 `a2_flood`: Drowned Crown

```json
{
  "a2_flood": {
    "name": "Drowned Crown",
    "act": 2,
    "order": 44,
    "giver": "alchemist",
    "requires": [
      "quest:a1_stair"
    ],
    "offer": [
      {
        "if": [
          [
            "quest:a1_diggers",
            "I told you I meant to ask one of your blood. This is the asking, and it is a small one."
          ]
        ],
        "else": "My order cut cisterns into the Ashgrave to drown the pyre. They failed. I would have one of your blood see them."
      },
      "No one of your blood has come down from the Warden before you. You may be the first who can tell me what that water kept.",
      "Go up to the cisterns. See what the flood left behind. Come to me before you tell the elder."
    ],
    "accept": "I will go up.",
    "decline": "Not yet.",
    "steps": [
      {
        "do": "find",
        "relic": 2,
        "text": "Find the Drowned Crown in the cisterns, up the second stair.",
        "track": "Find the Drowned Crown",
        "say": [
          "The inside of the band is worn bright. It was worn for years, and never made larger."
        ]
      },
      {
        "do": "win",
        "tier": 2,
        "text": "Defeat the Ashbound Duelist, guardian of the cisterns.",
        "track": "Defeat the Ashbound Duelist",
        "say": []
      },
      {
        "do": "talk",
        "to": "alchemist",
        "text": "Return to Sister Wren in Hearthvale.",
        "track": "Return to Sister Wren",
        "say": [
          "Worn bright, and never let out. Years on one small head. Think on that as you climb. I have.",
          "My order dug as far as a sluice and stopped. It opens with a key, and I want that key more than I wanted the crown."
        ]
      }
    ],
    "finish": [
      "The thirtieth wrote of a Sworn who sells on the stair. If any man holds that key, it is he. Leave him be for now. I am not ready.",
      "They crowned him so the fire would have a keeper. A keeper who cannot lift a sword cannot put it out."
    ],
    "reward": {
      "gold": 80,
      "xp": {
        "alchemy": 120
      },
      "item": "ward"
    },
    "journal": "Wren wants the key to a sluice below the pyre, but not yet. The Drowned Crown was made for a child, worn for years."
  }
}
```

Trigger: talk to Sister Wren with `a1_stair` done. Steps 1 and 2 pass at once for a veteran who already holds relic 2 or has beaten tier 2. Complete: the third step's talk with Wren. Pays 80 gold, alchemy XP and a Ward.

### 2.2 `a2_ending`: No Ending

```json
{
  "a2_ending": {
    "name": "No Ending",
    "act": 2,
    "order": 210,
    "giver": "elder",
    "auto": true,
    "requires": [
      "quest:a1_stair",
      "tier:2"
    ],
    "steps": [
      {
        "do": "choose",
        "to": "elder",
        "text": "The Duelist's last words: ask him why the oath has no ending. Take them to Elder Maren.",
        "track": "Take the Duelist's words to Maren",
        "say": [
          {
            "if": [
              [
                "flag:a1_stair=all",
                "The Warden's words you gave me whole. Now the second stair. What did the one in the cisterns say?"
              ],
              [
                "flag:a1_stair=keep",
                "The Warden's words you kept from me, and I let you. Now the second stair. What did the one in the cisterns say?"
              ]
            ],
            "else": "You have been through the second stair as well. What did the one in the cisterns say?"
          },
          "Whatever it said, it said it to you. It is yours to give me or to keep. I will not take it."
        ],
        "choices": [
          [
            "Tell Maren the Duelist's words.",
            "tell"
          ],
          [
            "Keep the Duelist's words back.",
            "keep"
          ]
        ],
        "reply": {
          "tell": [
            "'Ask him.' She never would say my name when she was angry. So that is where the first I sent went. I wondered.",
            "My own child. The best with a sword I ever saw. I sent her first, so that I need not ask it of a stranger."
          ],
          "keep": [
            "Keep it, then. I can guess whose voice said it, and I would sooner not have the guess confirmed."
          ]
        }
      }
    ],
    "finish": [
      {
        "if": [
          [
            "flag:a2_ending=keep",
            "Whatever it asked, it asked about the oath. I did not write it. I swore it, and I counted."
          ]
        ],
        "else": "As to the ending, I did not write the oath. I swore it, and I counted. I never asked what else the words would bear."
      },
      "A Keeper at the altar in the Old Ruins still talks. Ask him the wording, and tell me what he says."
    ],
    "reward": {
      "gold": 60,
      "xp": {
        "vitality": 120
      }
    },
    "journal": "Maren did not write the oath. A Keeper at the altar in the Old Ruins still talks, and holds the wording."
  }
}
```

Trigger: starts itself once `a1_stair` is done and tier 2 is beaten. The first `say` line varies on the `a1_stair` flag. The choice is stored under the quest id, and read by `a2_rune` and by Maren's idle line. Complete: the choice at Maren. Pays 60 gold and vitality XP.

### 2.3 `a2_mark`: The Maker's Mark

```json
{
  "a2_mark": {
    "name": "The Maker's Mark",
    "act": 2,
    "order": 220,
    "giver": "smith",
    "requires": [
      "quest:a1_stair",
      "quest:a1_bone"
    ],
    "offer": [
      {
        "if": [
          [
            "quest:side_mine",
            "That stamp on the brutes is under the grip of every blade I have refitted. I never cut it."
          ]
        ],
        "else": "There is a mark under the grip of every blade that comes down the stair. Small, struck deep. I never cut it."
      },
      "I have refitted what the tower sends and called it my work. It is not. Somebody strikes that mark, and it is not me.",
      "Find where it is struck. See what is done with the blades too broken to come down. Then bring me three ember ore."
    ],
    "accept": "I will look.",
    "decline": "Not now.",
    "steps": [
      {
        "do": "find",
        "relic": 3,
        "text": "Find the Unfinished Blade in the Foundry, up the third stair.",
        "track": "Find the Unfinished Blade",
        "say": [
          "The mark on its tang is the mark under your own grip. The same die, struck by the same hand."
        ]
      },
      {
        "do": "win",
        "tier": 3,
        "text": "Defeat the Gravemaul, guardian of the Foundry.",
        "track": "Defeat the Gravemaul",
        "say": [
          "Its plates are broken blades, hammered flat. The family's mark is on every one, facing in."
        ]
      },
      {
        "do": "bring",
        "to": "smith",
        "mats": {
          "ember_ore": 3
        },
        "text": "Bring Brannoc 3 ember ore. Mining 40 is needed; ember veins lie in the Ashlands and the Ruins.",
        "track": "Bring Brannoc 3 ember ore",
        "say": []
      }
    ],
    "finish": [
      "Cold. This ore has lain cold since the Burning, and a forge has to wake it. Mine will, if I do not hurry her.",
      "Years I fitted what came down and did not ask who struck it. Now I have asked. Wait by the fire. This one I make with no mark.",
      "Take it up the stair. If the tower wants it back, it can come down and ask me."
    ],
    "reward": {
      "gold": 150,
      "xp": {
        "smithing": 250
      },
      "item": "pyre_greatsword"
    },
    "journal": "The family's mark is under every grip, and on the Gravemaul's plates. Brannoc has made one blade with no mark."
  }
}
```

Trigger: talk to Brannoc with `a1_stair` and `a1_bone` done. Needs relic 3, tier 3 and three ember ore (Brannoc's offer names the ore; Mining 40 is stated in the step text only). The offer varies on `side_mine`. Complete: the bring step at Brannoc. Pays 150 gold, smithing XP and a Pyre Greatsword.

### 2.4 `a2_rune`: The Wording

```json
{
  "a2_rune": {
    "name": "The Wording",
    "act": 2,
    "order": 230,
    "giver": "oswin",
    "requires": [
      "quest:a2_ending"
    ],
    "offer": [
      "The elder sent you with a question. In two hundred years he has sent me heirs to swear, and never once a question.",
      "I would read the oath aloud, exactly, from the stone. Two of my fellows stand over it and will not allow a reading.",
      "Put two of them down. Then read the stone as it stands, and come back and tell me what you read."
    ],
    "accept": "I will read it.",
    "decline": "Not now.",
    "steps": [
      {
        "do": "kill",
        "foes": [
          "keeper"
        ],
        "need": 2,
        "text": "Defeat 2 Ruin Keepers in the Old Ruins.",
        "track": "Defeat 2 Ruin Keepers",
        "say": [
          "It stops in the middle of a word. The word was the oath's."
        ]
      },
      {
        "do": "reach",
        "place": "altar",
        "text": "Read the oath again at the broken altar, north-east beyond the river.",
        "track": "Read the oath at the altar",
        "say": [
          "'While one of us tends the fire, none of us need burn.' One of us. It does not say which, or for how long."
        ]
      },
      {
        "do": "talk",
        "to": "oswin",
        "text": "Return to Keeper Oswin and say what you read.",
        "track": "Return to Keeper Oswin",
        "say": [
          "One of us tends the fire. We have read that for two hundred years to mean one of us must.",
          "Read it as it is cut. It says one of us may tend. It does not say that one must. Whoever may keep may also let go."
        ]
      }
    ],
    "finish": [
      {
        "if": [
          [
            "flag:a2_ending=keep",
            "The elder will not have said who swore here first. His own child. I corrected one word, and she swore again, exactly."
          ]
        ],
        "else": "He told you who swore here first. I add only this. I corrected one word, and she swore again, exactly. They all swore exactly."
      },
      "I keep the wording exact. That is all a Keeper is set to do. You asked what it permits. That is a worse habit than the oath, and I am glad of it."
    ],
    "reward": {
      "gold": 120,
      "xp": {
        "sorcery": 150
      },
      "lore": [
        "oath_plain"
      ]
    },
    "journal": "Oswin reads the oath as it is cut: one of us may tend the fire. It does not say that one must."
  }
}
```

Trigger: talk to Keeper Oswin in the Old Ruins with `a2_ending` done. Kill two keepers (`keeper`, Old Ruins), reach the altar, talk to Oswin. The finish varies on the `a2_ending` flag. Pays 120 gold, sorcery XP and the lore entry `oath_plain`. This quest replaces the review's `a2_rune` and `side_keepers`.

### 2.5 `a2_letter`: Rook's Letter

```json
{
  "a2_letter": {
    "name": "Rook's Letter",
    "act": 2,
    "order": 240,
    "giver": "elder",
    "auto": true,
    "requires": [
      "quest:a1_stair",
      "relic:4"
    ],
    "steps": [
      {
        "do": "find",
        "relic": 4,
        "text": "You hold the Rook's Letter, taken from the Rookery up the fourth stair.",
        "track": "Find the Rook's Letter",
        "say": [
          "It is still tied for a rook's leg. The roost above it is empty, and has been for an age."
        ]
      },
      {
        "do": "win",
        "tier": 4,
        "text": "Defeat the Keeper of the Grave Gate, guardian of the Rookery.",
        "track": "Defeat the Keeper",
        "say": [
          "Behind her gate, a row of graves, each the length of a sword. The last one is open."
        ]
      },
      {
        "do": "choose",
        "to": "elder",
        "text": "Take the Rook's Letter down to Elder Maren in Hearthvale.",
        "track": "Take the letter to Maren",
        "say": [
          "You have come down with paper in your hand. Not a sword, not a ring. Paper.",
          "If it is for me, give it, or read it to me. If it is not, say so, and I will not ask what it holds."
        ],
        "choices": [
          [
            "Read the letter aloud to Maren.",
            "read"
          ],
          [
            "Hand the letter to Maren.",
            "give"
          ],
          [
            "Keep the letter.",
            "keep"
          ]
        ],
        "reply": {
          "read": [
            "'Brother.' Is that how it begins? Read the rest again. Slowly. I wish to hear where he stops.",
            "'Send no one after me.' Five words. I sent thirty."
          ],
          "give": [
            "Give it here. Hold the light still. I have not seen this hand on paper since we were boys.",
            "He wrote small, even then. Five words at the end, and I sent thirty."
          ],
          "keep": [
            "Keep it, then. It came down the stair in your hand, and it is yours.",
            "I have waited longer than anyone for a letter. I can wait for you to decide."
          ]
        }
      }
    ],
    "finish": [
      "I sent a rook up before each of you. Not one came back. I took the silence for a busy man, and sent help.",
      {
        "if": [
          [
            "flag:a2_letter=keep",
            "Paper out of that tower can only be his. His name is Ansel. I have not said it aloud since the first of you went up."
          ]
        ],
        "else": "His name is Ansel. I have not said it aloud since the first of you went up."
      },
      {
        "if": [
          [
            "flag:a2_letter=keep",
            "I told you I could not decide whether to bring him down or keep him company. I think you know the answer. I will not ask for it."
          ]
        ],
        "else": "I told you I could not decide whether to bring him down or keep him company. He had decided before your line had a name. It never reached me."
      },
      {
        "if": [
          [
            "quest:a2_rune",
            "Two hundred years I counted by that oath and never asked what it allowed. The Keeper says one of us may stop. I do not know which he means."
          ]
        ],
        "else": ""
      }
    ],
    "reward": {
      "gold": 200,
      "xp": {
        "vitality": 150
      },
      "lore": [
        "rooks_sent"
      ]
    },
    "journal": "The Rook's Letter was never sent. Maren sent a rook before each heir, and took the silence for a busy brother."
  }
}
```

Trigger: starts itself once `a1_stair` is done and relic 4 is held. Relic 4 and tier 4 are the tower's. The choice (read, give, keep) is stored under the quest id and read by Maren's and Wren's idle lines and by the quest's own finish. The finish is four boxes; boxes 2 to 4 are variants. Adds the lore entry `rooks_sent`. Pays 200 gold and vitality XP.

## 3. Inscriptions and letters met in Act 2

Lore entries (`Story.lore_entry` reads `Act2.LORE` after `Act1.LORE`; the save key `lore` only grows):

```json
{
  "oath_plain": {
    "name": "The Oath, Read Plain",
    "text": "'While one of us tends the fire, none of us need burn.' It says one of us may tend. It does not say that one must."
  },
  "rooks_sent": {
    "name": "A Rook for Each",
    "text": "Maren sent a rook up before every heir. Not one came back. The one answer ever written was never sent."
  }
}
```

The two entries are paid by `a2_rune` (`oath_plain`) and `a2_letter` (`rooks_sent`). Neither is paid twice.

## 4. Barks

New entries for `Story.BARKS` (looked up after `Act1.BARKS`). Same rules as Act 1: a list picks one at random,
an empty string says nothing this time.

```json
{
  "Cistern Lurker": {
    "intro": [
      "...the sluice... shut...",
      "...not yours to open..."
    ],
    "death": "...the water kept it..."
  },
  "Forge Hand": {
    "intro": [
      "Hold it out. I will strike the mark.",
      "Another blade for the pile."
    ],
    "death": "...reforge... me..."
  },
  "Rook Sentry": {
    "intro": [
      "Nothing flies in. Nothing flies out.",
      "The letter stays."
    ],
    "death": "...he stopped sleeping..."
  },
  "Ruin Seer": {
    "intro": [
      "Say the wording back to me. Exact.",
      "Say it as it is cut. Not as you remember it."
    ],
    "death": "...who scratched it..."
  }
}
```

## 5. What characters say when nothing is asked of them

`Quests.idle_lines(npc)` reads `Act2.IDLE`, then `Side.IDLE`, then `Act1.IDLE`; the first table whose
conditions give a non-empty line wins, otherwise the next table is tried. The elder's entry has no `loop>=1`
guard, so a player on a later heir still hears the letter and ending lines; when none applies, Act 1's returning-heir line
plays (Act 1 has one change: that line has a variant for `flag:throne=true`). Wren's three letter lines come before her two
hexer lines, so the hexer line stops showing once the letter is settled.

```json
{
  "elder": {
    "if": [
      [
        "flag:a2_letter=read",
        "It is a short letter. I have said it over more times than I have sent heirs, and it has not grown."
      ],
      [
        "flag:a2_letter=give",
        "The letter is under the hearthstone. I do not read it. I know where it is, and that is new."
      ],
      [
        "flag:a2_letter=keep",
        "You still have it. I do not ask what it says. I count the nights I do not ask."
      ],
      [
        "flag:a2_ending=tell",
        "The second stair has my child on it. I sent her there. I find I can say that now, and nothing falls down."
      ],
      [
        "flag:a2_ending=keep",
        "You kept the cistern's words from me. I count them anyway, unsaid. It is a short count."
      ]
    ],
    "else": ""
  },
  "alchemist": {
    "if": [
      [
        "flag:a2_letter=read",
        "I heard Maren at the well. He has stopped saying that the fire keeps us. I did not say I had noticed."
      ],
      [
        "flag:a2_letter=give",
        "Maren has his letter and I have my shelf. I could not tell you which of us is better kept."
      ],
      [
        "flag:a2_letter=keep",
        "You carry a letter you will not give him. I have carried worse silences. Keep it dry."
      ],
      [
        "flag:side_hexer=tell",
        "I have not asked you to hold the sluice. I will not, until you come and say that you will."
      ],
      [
        "flag:side_hexer=silent",
        "You came back from the fen quiet, and you have stayed quiet. I notice such things. It is most of my trade."
      ]
    ],
    "else": ""
  },
  "oswin": {
    "if": [
      [
        "quest:a2_rune",
        "I read it as it is cut, and the stone did not object. I had not expected that of a stone."
      ]
    ],
    "else": "The wording is exact. I check it each morning. It has not changed, and I am not sure I am glad."
  }
}
```

## 6. Check against the code

Places used: `smith`, `elder`, `alchemist`, `fisher`, `ranger`, `altar`, `shrine`, plus two new rows in
`land.gd` `PLACES`: `nan` (Meadows, near the village road) and `oswin` (Old Ruins, about 13 from the altar), each with
an `NPC_LOOKS` entry in `overworld_places.gd` and a display name in `quests.gd` `NPCS`. Foes: `keeper`
(`land.gd`, Old Ruins). Materials: `ember_ore`. Items: `ward`, `pyre_greatsword`. Skills in rewards: alchemy,
smithing, vitality, sorcery. Relics 2 to 4 and tiers 2 to 4.

New code: the data files `quest_data_act2.gd` and `quest_data_side.gd`; their merge in `Quests._build`,
`Story.lore_entry`, `Story.bark`; the five main ids in `Quests.MAIN`; `Quests.idle_lines`; `journal` may be a
variant list. **Nothing new in `items.gd`, `craft.gd`, `enemy_def.gd` or the save format.**

How Act 2 behaves for each way Act 1 can end:

|Act 1 ended with|Act 2 does|
|---|---|
|`a1_stair=all` (Warden's words given whole)|`a2_ending` opens with "The Warden's words you gave me whole."|
|`a1_stair=keep`|opens with "The Warden's words you kept from me, and I let you."|
|`a1_stair` missing (a quest finished by an older build)|the neutral third line plays; no quest needs the flag|
|`bloodline>=2`|`side_bread`'s finish has its own variant; the main line does not read bloodline|
|`loop>=1`|Maren's letter and ending lines still play; otherwise Act 1's idle line (`throne` variant)|
|optional Act 1 quests skipped|the side quests that need them wait; the main line needs only `a1_stair` (and `a1_bone` for the mark)|

## 7. Line check

Every string is audited by the quest bot in the real HUD (`_qb_audit`, in the `act2` scenario of
`tools/check.js`): offer, finish, say and reply boxes against the talk box (2 rows, 3 for the last box before
choices), journal entries (3 rows), tracker lines (520 px with the quest name), choice labels (426 px),
captions (3 rows at 716 px), barks (60 characters). The style-sheet limits were also checked offline
(`validate.py`, characters per box and boxes per conversation). No contractions, no dashes, plain quotes only.

## 8. Held for part two

- `a2_key` (the sluice key) and `a2_roost` (the roost book): they need the tower trader to talk and the casino stake hook, and the review calls them the weakest stretch of the draft.
- The second ring, tracing and Runecraft (the review's part-two side quest that absorbs `side_stones`).
- `side_pye` (Thieving), `side_cousin` (an online duel result into the quest engine), `side_plot` (clans, a new place, a banner stone).
- Pyre Guard barks: one display name serves the Ashlands foe and the tier 5 lesser.
- The flood itself. Wren is promised nothing in part one: `a2_flood` ends on the reason, not on the water.
- All of Act 3. It waits for the rulings in `OWNER_QUESTIONS.md` part (c).
