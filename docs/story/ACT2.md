# Ashgrave Act 2: Send No One

Written to the schema in `docs/STORY_BIBLE.md` section 9 and the phone limits in its section 3.
Every block below is valid JSON and also a valid GDScript Dictionary literal. All text in this
file is NEW unless it carries a `file:line`. Anything the engine does not yet have is listed
under NEEDS at the end.

**What the act does.** The player is now a heir who has passed the gate once. Wren wants the
sluice key that would let her drown the pyre. The Foundry offers the family's own blade. Corbie
keeps the book of rooks, and one of its letters never flew. Oswin shows that the oath's rune can
be released by any of the blood. The act ends at the Rookery, where the player learns that the
Rook's Letter is addressed to Brother, and that the boy who wrote it was named Ansel.

## 1. Order of play

|#|id|Name|Giver|Opens when|State|
|---|---|---|---|---|---|
|1|`a2_flood`|Drowned Crown|Sister Wren|`a1_diggers` done|NEW|
|2|`a2_key`|Sluice Key|Mag Pye|`a2_flood` done|NEW|
|3|`a2_mark`|The Maker's Mark|Brannoc|`a1_stair` done|NEW|
|4|`a2_roost`|Roost Book|Mother Corbie|`a1_stair` done|NEW|
|5|`a2_rune`|The Oath Rune|Keeper Oswin|`a1_stair` done|NEW|
|6|`a2_letter`|Rook's Letter|starts itself|relic 4 held|NEW|

Rows 3, 4 and 5 may be played in any order. Row 2 needs row 1. Row 6 is the finale of the act.
Level bands: rows 1-2 suit an heir at combat 12 or more; rows 3-5 at 16 to 30; row 6 at the
Rookery's tier 4.

## 2. The quests

### 2.1 `a2_flood`: Drowned Crown

```json
{"a2_flood": {
  "name": "Drowned Crown", "act": 2, "order": 80, "giver": "alchemist",
  "requires": ["quest:a1_diggers"],
  "offer": [
    "The second stair is the cisterns. My order dug them to drown the pyre. They failed.",
    "Go down through the water and find what the flood left. Then bring it to me. I will tell you what I want with it."
  ],
  "accept": "I will go down.", "decline": "Not yet.",
  "steps": [
    {"do": "win", "tier": 2,
     "text": "Defeat the Ashbound Duelist, guardian of the cisterns.",
     "track": "Defeat the Ashbound Duelist",
     "say": ["The sluice gate is locked from the far side. The water has waited a long time for a key."]},
    {"do": "find", "relic": 2,
     "text": "Find the Drowned Crown in the cisterns.",
     "track": "Find the Drowned Crown",
     "say": ["A circlet no grown head would wear. Someone put it on a boy."]},
    {"do": "talk", "to": "alchemist",
     "text": "Return to Sister Wren at the hearth.",
     "track": "Return to Sister Wren",
     "say": [
       "A crown for a child. So the fire had a child for its first keeper.",
       "The sluice from the cisterns to the pyre has a lock. The only key is in the tower, with the Chandler.",
       "He will not give it to me. He may give it to you."
     ]}
  ],
  "finish": [
    "Then I will open the water on the pyre. I will need one of your blood beside me when I do.",
    "They crowned him so the fire would have a keeper. A keeper who cannot lift a sword cannot put it out."
  ],
  "reward": {"xp": {"alchemy": 120}, "item": "ward"},
  "journal": "Wren wants the sluice key. The Drowned Crown was made for a child, and the pyre was lit under him."
}}
```

Trigger: talk to Sister Wren with `a1_diggers` done. Step 1 completes on the `tier` 2 guardian
(`run.gd:408`). Step 2 completes when relic 2 is held (`world.gd:798`). Complete: talk to Wren.
The reward `ward` is an existing spell id (`items.gd:40`).

### 2.2 `a2_key`: Sluice Key

```json
{"a2_key": {
  "name": "Sluice Key", "act": 2, "order": 90, "giver": "magpye",
  "requires": ["quest:a2_flood"],
  "offer": [
    "The Chandler sells keys in the tower to anyone who climbs. He will not sell this one to Sister Wren.",
    "I can get it for you. It is a matter of waiting until he turns his back to count coin."
  ],
  "accept": "Show me.", "decline": "Not today.",
  "steps": [
    {"do": "find", "item": "sluice_key", "place": "tower",
     "text": "Steal the Chandler's sluice key from the tower.",
     "track": "Steal the Chandler's key",
     "say": ["The key hangs on a cord at his belt. He turns to count coin, and that is the whole trick."]},
    {"do": "choose", "to": "alchemist",
     "text": "Give the key to Sister Wren, or take it to Elder Maren first.",
     "track": "Choose who gets the key",
     "say": ["The Chandler sold a key to the elder as well. I know that much. Who do you give yours to?"],
     "choices": [["Give the key to Sister Wren.", "wren"], ["Take it to Elder Maren first.", "maren"]],
     "reply": {
       "wren": ["Good. The water comes up tonight. Stand where I tell you."],
       "maren": ["Then take it to him, and tell him I asked. He will know what it is for, and he will not say."]
     }}
  ],
  "finish": [
    "The Chandler sold that lock twice. Once to the one who wants the water, once to the one who wants the fire kept. He did not ask which.",
    "I do not charge for a lesson in patience. Go on. Someone has to be first to the water."
  ],
  "reward": {"gold": 60, "xp": {"agility": 100}},
  "journal": "The Chandler sells sluice keys to both Wren and Maren. Mag Pye taught you to take one from him."
}}
```

Trigger: talk to Mag Pye in Greywood with `a2_flood` done. Step 1 counts a held `sluice_key`
(NEW item, see NEEDS). Step 2 is a choice at Sister Wren's hearth; the reply shows at once and
the finish lines play when the quest completes. The key is spent by the choice, so the reward
does not hand out a second one.

### 2.3 `a2_mark`: The Maker's Mark

```json
{"a2_mark": {
  "name": "The Maker's Mark", "act": 2, "order": 100, "giver": "smith",
  "requires": ["quest:a1_stair"],
  "offer": [
    "The Foundry melts every blade that fell in the tower and makes it again. I keep the straps on the thirtieth's sallet.",
    "There is an unfinished blade in the Foundry with your family's mark on the tang. Find it. Take down the Gravemaul, then bring me three ember ore."
  ],
  "accept": "I will look.", "decline": "Not now.",
  "steps": [
    {"do": "find", "relic": 3,
     "text": "Find the Unfinished Blade in the Foundry.",
     "track": "Find the Unfinished Blade",
     "say": ["Left in the forge for an age. The mark on the tang is cut neat and small, like the mark on your sallet."]},
    {"do": "win", "tier": 3,
     "text": "Defeat the Gravemaul, guardian of the Foundry.",
     "track": "Defeat the Gravemaul",
     "say": ["It is made from swords too broken to send down. Each plate still has a hilt on it."]},
    {"do": "bring", "to": "smith", "mats": {"ember_ore": 3},
     "text": "Bring Brannoc 3 ember ore from the Ashlands veins.",
     "track": "Bring Brannoc 3 ember ore"}
  ],
  "finish": [
    "The Foundry made the Gravemaul from what it could not mend. I was asked to keep its edges. I did not ask by whom.",
    "This blade came down the stair when the thirtieth's arms did, and no one came for it. I can make it fit you. I will not ask what you mean to do with it."
  ],
  "reward": {"gold": 100, "xp": {"smithing": 250}, "item": "pyre_greatsword"},
  "journal": "Brannoc has the unfinished blade with your family's mark. He will make it fit an heir, and he will not ask which."
}}
```

Trigger: talk to Brannoc with `a1_stair` done. Step 1 completes when relic 3 is held
(`world.gd:798`). Step 2 completes on the tier 3 guardian (`run.gd:408`). Step 3 counts 3
`ember_ore` (`craft.gd:23`). Complete: talk to Brannoc. The reward `pyre_greatsword` is an
existing weapon (`items.gd:20`) used as the "upgrade" the bible names.

### 2.4 `a2_roost`: Roost Book

```json
{"a2_roost": {
  "name": "Roost Book", "act": 2, "order": 110, "giver": "corbie",
  "requires": ["quest:a1_stair"],
  "offer": [
    "The rooks that sat on the tower stair had keepers, and my people were the keepers. We kept their mail too.",
    "Win a stake at my tables, or pay five hundred gold for the book. Either pays me, and either gets you the book."
  ],
  "accept": "Show me the book.", "decline": "I do not gamble today.",
  "steps": [
    {"do": "choose", "to": "corbie",
     "text": "Win a stake at the tables, or pay 500 gold for the book.",
     "track": "Win a stake or pay 500 gold",
     "say": ["Five hundred gold, or a stake you win at the wheel. A stake you win is one you keep."],
     "choices": [["Pay five hundred gold.", "pay"], ["Win the stake at the table.", "win"]],
     "reply": {
       "pay": ["Gold is gold. It spends the same as a win would. Here is the book."],
       "win": ["You won it fair. The book is yours, and I will not say what the wheel cost me."]
     }}
  ],
  "finish": [
    "Turn to the page with the rook drawn on it. One letter in this book was never flown. It is addressed to Brother.",
    "Read the last line of it, and then ask yourself why no rook carried it up the stair."
  ],
  "reward": {"gold": 40, "lore": ["roost_book"]},
  "journal": "Corbie's roost book records one letter from the Rookery that never flew. It is addressed to Brother."
}}
```

Trigger: talk to Mother Corbie in the casino with `a1_stair` done. Step 1 is the choice; the
`win` branch needs the casino's stake game (NEEDS). Complete: the choice. The book is the lore
entry `roost_book` (section 4), not an item.

### 2.5 `a2_rune`: The Oath Rune

```json
{"a2_rune": {
  "name": "The Oath Rune", "act": 2, "order": 120, "giver": "oswin",
  "requires": ["quest:a1_stair"],
  "offer": [
    "The Keepers wrote the oath twice. Once on the altar, and once in stone at the second ring.",
    "Trace the oath rune on the second stones. Then come back and say the words to me. I want them said by someone who is not a Keeper."
  ],
  "accept": "I will trace it.", "decline": "Not now.",
  "steps": [
    {"do": "reach", "place": "second_stones",
     "text": "Go to the second humming stones, east of the bridge.",
     "track": "Find the second stones",
     "say": ["The hum here is lower than at the western ring. It is the same note, played slower."]},
    {"do": "reach", "place": "second_stones", "trace": "oath_rune",
     "text": "Trace the oath rune on the stones with Runecraft.",
     "track": "Trace the oath rune",
     "say": ["The rune reads top to bottom, then bottom to top. Both ways it says the same thing. Any of the blood may let it go out."]},
    {"do": "talk", "to": "oswin",
     "text": "Return to Keeper Oswin at the Old Ruins.",
     "track": "Return to Keeper Oswin",
     "say": [
       "Good. You read it right. Now you know what I have been careful not to say aloud for forty years.",
       "Any of the blood may release the oath. The rune does not say the eldest."
     ]}
  ],
  "finish": [
    "The Ashbound Duelist was the first heir to climb. Maren's child. She still teaches the stair as if it were a school.",
    "The rune is not a curse. It is a permission, and the family has never read it through."
  ],
  "reward": {"xp": {"sorcery": 150}, "lore": ["oath_rune"], "flags": {"rune": "1"}},
  "journal": "Oswin reads the oath rune: any of the blood may release the oath. The Duelist was the first heir."
}}
```

Trigger: talk to Keeper Oswin with `a1_stair` done. Step 2 is a reach with a `trace` field
(NEW, see NEEDS) that needs Runecraft. Complete: talk to Oswin. The reward sets `flags.rune`.

### 2.6 `a2_letter`: Rook's Letter

```json
{"a2_letter": {
  "name": "Rook's Letter", "act": 2, "order": 130, "giver": "elder", "auto": true,
  "requires": ["relic:4"],
  "steps": [
    {"do": "win", "tier": 4,
     "text": "Defeat the Keeper of the Grave Gate, guardian of the Rookery.",
     "track": "Defeat the Keeper",
     "say": ["It has buried every heir who reached it. It is sorry before it swings, and it swings anyway."]},
    {"do": "choose", "to": "elder",
     "text": "Give the Rook's Letter to Elder Maren, or keep it.",
     "track": "Give Maren the letter",
     "say": ["You have the rook's letter. Nobody sent it, and it never flew. Will you give it to me?"],
     "choices": [["Give Maren the letter.", "give"], ["Keep the letter.", "keep"]],
     "reply": {
       "give": ["'Brother.' Then you read it. Then you know who is at the top, and what he asked for."],
       "keep": ["Keep it, then. A letter that never flew is a poor reason to climb, and a worse one to stop."]
     }}
  ],
  "finish": [
    {"if": [["flag:a2_letter=keep", "You kept it, so I will say it for you. He wrote that no one was to be sent."]],
     "else": "His name was Ansel. He wrote that no one was to be sent, and I sent thirty."},
    "I sent them because the first letter said no one, and I could not stop once the first one went up."
  ],
  "reward": {"xp": {"vitality": 150}},
  "journal": "The Rook's Letter is addressed to Brother. Maren is Brother. The boy who wrote it was named Ansel."
}}
```

Trigger: starts by itself once relic 4 is held (`world.gd:798`), so old saves pick it up on
load. Step 1 completes on the tier 4 guardian (`run.gd:408`). Step 2 is a choice stored as
`flags.a2_letter` (`give` or `keep`). Complete: either choice. Act 3 reads the flag.

## 3. Inscriptions, letters and lore met in Act 2

|Where|Text|State|
|---|---|---|
|Cisterns, the sluice (`a2_flood` step 1)|"The sluice gate is locked from the far side. The water has waited a long time for a key."|NEW, caption|
|Foundry, the blade (`a2_mark` step 1)|"The mark on the tang is cut neat and small, like the mark on your sallet."|NEW, caption|
|Rookery mail (`a2_roost`)|"Rookery mail, last page: 'To Brother, by rook, at the fire's turn. Did not fly.'"|NEW, `roost_book`|
|Second stones (`a2_rune`)|"Any of the blood may let the fire go out. The rune does not name the eldest."|NEW, `oath_rune`|

Lore entries for `Story.LORE` (NEW):

```json
{
  "roost_book": {
    "name": "Roost Book",
    "text": "Rookery mail, last page: 'To Brother, by rook, at the fire's turn. Did not fly.'"
  },
  "oath_rune": {
    "name": "The Oath Rune",
    "text": "Any of the blood may let the fire go out. The rune does not name the eldest."
  }
}
```

## 4. Barks

Each entry is for `Story.BARKS`, keyed by display name. A list means pick one at random.

```json
{
  "Cistern Lurker": {
    "intro": ["...the sluice... shut...", "...not yours to open..."],
    "death": "...the water kept it..."},
  "Forge Hand": {
    "intro": ["Hot steel. Hold still.", "Another blade for the pile."],
    "death": "...reforge... me..."},
  "Rook Sentry": {
    "intro": ["Nothing flies in. Nothing flies out.", "The letter stays."],
    "death": "...he stopped sleeping..."},
  "Ruin Seer": {
    "intro": ["Say the wording back to me. Exact.", "The rune is older than the stone."],
    "enrage": "The wording is not yours to change!",
    "death": "...who scratched it..."},
  "Pyre Guard": {
    "intro": "The Court is lit. Stand in it.",
    "enrage": "The ash line is ours!",
    "death": "...still warm..."}
}
```

The Ashbound Duelist, Gravemaul and Keeper barks already exist (`story.gd:9-11`) and do not change.

## 5. Land and idle lines

No new idle lines are needed in Act 2 beyond those in `ACT1.md` section 5. The alchemist's idle
line changes when `flags.a2_letter` is set; that is left for the engineer to add.

## 6. Check against the code

Places used: `smith`, `elder`, `alchemist`, `ranger`, `tower`, `altar`, `circle`, `watch`
(`land.gd:67-87`), plus new `second_stones`, `casino`. Foes: `wight`, `brute`, `keeper`,
`bandit` (`land.gd:39-56`). Materials: `ember_ore`, `bone`, `bogroot` (`craft.gd:23-44`).
Items: `ward` (spell, `items.gd:40`), `pyre_greatsword` (`items.gd:20`). Relics 2, 3, 4
(`story.gd:30-34`). Skills in rewards: alchemy, smithing, sorcery, vitality, agility (`craft.gd:5-19`).

## NEEDS

- Item `sluice_key` (`items.gd`), held by the find step and spent by the choice in `a2_key`.
- Thieving skill for the Chandler's lesson; `a2_key` currently rewards `agility` in its place
  (`craft.gd:5`).
- Runecraft skill and a `trace` field on reach steps, for `a2_rune`.
- Places `second_stones` (`land.gd`, after `stones`, `land.gd:85`) and `casino`.
- NPCs not yet placed in `land.gd`: `magpye` (Greywood), `oswin` (Old Ruins), `corbie` (casino),
  `chandler` (tower). `smith`, `elder`, `alchemist`, `ranger` already exist (`land.gd:88-91`).
- Casino stake game for the `win` branch of `a2_roost`.
- Choose steps with `"to"` set to an NPC the player stands in front of: `a2_key` and `a2_letter`
  both rely on this (`quests.gd:205` as the engineer's item 4 in `ACT1.md`).
- Flags are read in variants: `flag:a2_letter=keep`, `flag:rune`, `flag:a1_stair`.

## Counts

|id|Dialogue lines|Longest line (characters)|
|---|---|---|
|`a2_flood`|11|113|
|`a2_key`|10|134|
|`a2_mark`|8|152|
|`a2_roost`|9|112|
|`a2_rune`|10|130|
|`a2_letter`|7|98|
