# Ashgrave Act 1: The Thirty-First

Written to the schema in `docs/STORY_BIBLE.md` section 9 and the phone limits in its section 3.
Every block below is valid JSON and also a valid GDScript Dictionary literal: paste it into the
quest table as it stands. All text in this file is NEW unless it carries a `file:line`
(paths are under `game/scripts/`).

**What the act does.** The player arrives as the thirty-first heir. In the first ten minutes
they learn that the dead heir's arms come back down the stair cleaned, that no body ever does,
and that the last heir trusted Sister Wren with his letter instead of Elder Maren. The act
ends when they pass the gate, read the tablet, beat the Cinder Warden and learn who else has
been keeping a list of their names.

## 1. Order of play

|#|id|Name|Giver|Opens when|State|
|---|---|---|---|---|---|
|1|`a1_thirty_first`|The Thirty-First|Elder Maren|always (offered before `oath`)|NEW|
|2|`forge`|The Cold Forge|Brannoc|always|existing, `quests.gd:10`|
|3|`a1_bone`|What Walks South|Brannoc|`forge` done|NEW|
|4|`line`|A Line in the Water|Old Tam|always|existing, `quests.gd:17`|
|5|`a1_tam`|Sixty Winters|Old Tam|`line` done|NEW|
|6|`poach`|Poachers in Greywood|Warden Isolde|always|existing, `quests.gd:27`|
|7|`a1_struck`|The Struck Name|Warden Isolde|`poach` done|NEW|
|8|`mire`|What the Mire Keeps|Sister Wren|always|existing, `quests.gd:39`|
|9|`a1_diggers`|Still Digging|Sister Wren|`mire` done|NEW|
|10|`oath`|The First Oath|Elder Maren|always|existing, `quests.gd:51`|
|11|`a1_hand`|In One Hand|starts itself|`oath` and `a1_thirty_first` done|NEW|
|12|`a1_stair`|The First Stair|Elder Maren|`a1_hand` done|NEW|

The five existing quests keep their ids, steps, text and rewards exactly as they are. Rows 3,
5, 7 and 9 may be played in any order; none is required for the finale. Level bands follow the
foes already in `land.gd:39-48`: rows 1-5 suit a new heir, 6-9 combat 8 to 20, 10-12 an
heir ready for the tower (`overworld_interact.gd:182` warns below combat 12).

## 2. The quests

### 2.1 `a1_thirty_first`: The Thirty-First

```json
{"a1_thirty_first": {
  "name": "The Thirty-First", "act": 1, "order": 10, "giver": "elder",
  "requires": [],
  "offer": [
    {"if": [["bloodline>=2", "Another of the blood. I stopped counting at thirty, and I will not start again for you."]],
     "else": "So. The thirty-first. You have the walk of the thirtieth, and I watched him go."},
    "Before I send you north, ask Brannoc what came back down the stair. Then ask Sister Wren what did not."
  ],
  "accept": "I will ask them.", "decline": "Not now.",
  "steps": [
    {"do": "talk", "to": "smith",
     "text": "Ask Brannoc the Smith what came back down the stair.",
     "track": "Ask Brannoc what came down",
     "say": [
       "The arms you were given belonged to the heir before you. Sword, sallet, plate, shield. I changed the straps and nothing else.",
       "Each time one of you falls, they are at the gate by morning. Laid out. Cleaned. The blade comes down better than it went up.",
       "I do not know who lays them there. I fit them to the next of you, and I do not ask."
     ]},
    {"do": "talk", "to": "alchemist",
     "text": "Ask Sister Wren what did not come back down.",
     "track": "Ask Sister Wren what did not",
     "say": [
       "A body. In all the years of the oath, the tower has not sent down one. I have a shelf of folded cloaks and nothing to put in them.",
       "The thirtieth left this with me, and not with the elder. Think on why before you read it.",
       "'To my heir: Maren will offer you a ring. Before you take it, count the names on the altar. Then count the spaces.'"
     ]},
    {"do": "talk", "to": "elder",
     "text": "Return to Elder Maren by the hearth.",
     "track": "Return to Elder Maren",
     "say": [
       "Arms and no body. Now you know as much as the village does.",
       "The tower wants the next of you armed. I have never learned why it troubles to be kind."
     ]}
  ],
  "finish": [
    "Walk the land before you walk the stair. The forge, the lake, the wood, the mire. Each will tell you something I cannot.",
    {"if": [["quest:oath", "You wear the ring already. Then you have read the altar, and you know why I do not hurry you."]],
     "else": "The ring comes last. It always does."}
  ],
  "reward": {"gold": 30, "xp": {"vitality": 60}, "lore": ["letter_thirtieth"]},
  "journal": "Thirty went up. Their arms came back cleaned, and never a body. The thirtieth left his letter with Sister Wren, not with Maren."
}}
```

Trigger: talk to Elder Maren (`land.gd:80`) with the quest not yet started. Complete: the
third step's talk with Maren. Whole quest sits inside Hearthvale: about four minutes.

### 2.2 `a1_bone`: What Walks South

```json
{"a1_bone": {
  "name": "What Walks South", "act": 1, "order": 20, "giver": "smith",
  "requires": ["quest:forge"],
  "offer": [
    "Since the forge was lit, the field thralls come closer at night. They stand at the edge of the light and do nothing.",
    "Put two of them down and bring me the bone. I want to see what they are made of."
  ],
  "accept": "I will bring it.", "decline": "Not now.",
  "steps": [
    {"do": "bring", "to": "smith", "mats": {"bone": 2},
     "text": "Bring Brannoc 2 old bones. Field Thralls in the Meadows carry them.",
     "track": "Bring Brannoc 2 old bones"}
  ],
  "finish": [
    "Burnt through. This did not die this year, or this age. This died in the Burning.",
    "They are not hunting. They walk south each night, toward the hearth, the way a cold man walks toward a window.",
    "I will tell Maren. Maren will say what Maren always says. Leave them be."
  ],
  "reward": {"gold": 40, "xp": {"slaying": 80, "smithing": 60}},
  "journal": "The thralls of the Meadows are the dead of the Burning. They walk south toward the hearth and stop at the edge of its light."
}}
```

Trigger: talk to Brannoc with `forge` done. Complete: talk to Brannoc holding 2 `bone`
(`craft.gd:44`; dropped by `thrall`, `land.gd:39`).

### 2.3 `a1_tam`: Sixty Winters

```json
{"a1_tam": {
  "name": "Sixty Winters", "act": 1, "order": 30, "giver": "fisher",
  "requires": ["quest:line"],
  "offer": [
    "You cook like one of your line. I have fed a few of them at this fire, going north.",
    "Go and stand in the stone ring west of here. Then come back and tell me what you hear."
  ],
  "accept": "I will listen.", "decline": "Not now.",
  "steps": [
    {"do": "reach", "place": "circle",
     "text": "Stand in the standing stones, west of the Fisher's fire.",
     "track": "Stand in the standing stones",
     "say": ["The hum is not in the stones. It comes up through your boots, and it comes from the north."]},
    {"do": "talk", "to": "fisher",
     "text": "Return to Old Tam at the lake.",
     "track": "Return to Old Tam",
     "say": ["From the north. It was fainter when I was a boy. Each time one of you goes up, it is a little louder after."]}
  ],
  "finish": [
    "Here is another thing sixty years will show you. Maren was old when I was a boy. Same cloak. Same hands.",
    "I have buried my father, my wife and two dogs. The elder has not aged a day I could swear to.",
    "I do not say it is wrong. I say look at the hands."
  ],
  "reward": {"gold": 40, "xp": {"fishing": 80}, "mats": {"meal_trout": 2}},
  "journal": "The ground hums from the north, louder after every heir. Old Tam says Elder Maren was already old sixty years ago."
}}
```

Trigger: talk to Old Tam with `line` done. Step 1 completes on entering the `circle` spot
(`land.gd:86`). Complete: talk to Old Tam.

### 2.4 `a1_struck`: The Struck Name

```json
{"a1_struck": {
  "name": "The Struck Name", "act": 1, "order": 40, "giver": "ranger",
  "requires": ["quest:poach"],
  "offer": [
    {"if": [["flag:poach=bribe", "You sold my forest for three hundred gold. Good. Then you will follow the next thing better than most."]],
     "else": "You gave up coin for a list of names. So I will give you a name for nothing."},
    "Go to the fallen watchtower, north-east through the wood. Read the stump. Then come and say it to my face."
  ],
  "accept": "I will read it.", "decline": "Not now.",
  "steps": [
    {"do": "reach", "place": "watch",
     "text": "Find the fallen watchtower in Greywood, north-east of Warden Isolde.",
     "track": "Find the fallen watchtower",
     "say": ["Cut in the stump, small and neat: ISOLDE. Through it, one deep stroke from a different knife."]},
    {"do": "talk", "to": "ranger",
     "text": "Return to Warden Isolde at the end of the forest road.",
     "track": "Return to Warden Isolde",
     "say": [
       "My name, in the elder's cutting. I was to be the thirtieth. I struck it out myself and came here.",
       "The oath went looking and took the next of us instead. You know who went. You were handed his sword.",
       "Bandits have killed me four times since. Each time I wake by the hearth, sore but whole, and walk back. None of the blood can die out here."
     ]}
  ],
  "finish": [
    "So here is my counsel, and it is the opposite of Maren's. Do not go. The oath cannot kill you unless you climb.",
    "And if you go anyway, do not go for me. I have enough of your line on my account."
  ],
  "reward": {"xp": {"slaying": 150, "archery": 100}, "mats": {"arrow": 20}},
  "journal": "Isolde was named the thirtieth and struck her own name out. Another went in her place. None of the blood can die outside the tower."
}}
```

Trigger: talk to Warden Isolde with `poach` done. Step 1 completes on entering the `watch`
spot (`land.gd:87`). Complete: talk to Isolde. The existing look line still plays there
(`overworld_interact.gd:141`).

### 2.5 `a1_diggers`: Still Digging

```json
{"a1_diggers": {
  "name": "Still Digging", "act": 1, "order": 50, "giver": "alchemist",
  "requires": ["quest:mire"],
  "offer": [
    "The shrine burns green again. You should know what you relit. It is a waymark, and it points at the tower.",
    "My order cut the cisterns into the Ashgrave to drown the pyre. They failed, and they did not all come home.",
    "Some walk the fen as wights. Lay two down, and I will tell you what they dug toward."
  ],
  "accept": "I will lay them down.", "decline": "Not now.",
  "steps": [
    {"do": "kill", "foes": ["wight"], "need": 2,
     "text": "Defeat 2 Bog Wights in Mirefen.",
     "track": "Defeat 2 Bog Wights",
     "say": ["The wight folds into the water. Its hands keep moving a moment longer, as if at a spade."]},
    {"do": "talk", "to": "alchemist",
     "text": "Return to Sister Wren in Hearthvale.",
     "track": "Return to Sister Wren",
     "say": ["Sisters, once. They dug until the water took them, and after. That is what an oath does with a person."]}
  ],
  "finish": [
    "They failed because they dug in secret, and alone. I will not make their mistake. I mean to ask one of the blood.",
    "Maren will tell you the fire keeps us. Ask what it keeps, and watch which fire the elder looks at."
  ],
  "reward": {"gold": 60, "xp": {"alchemy": 150}, "mats": {"bogroot": 2}},
  "journal": "The Sisters dug the cisterns to drown the pyre, and failed. Wren means to try again, and she wants one of the blood beside her."
}}
```

Trigger: talk to Sister Wren with `mire` done. Step 1 counts `wight` kills
(`land.gd:41`). Complete: talk to Sister Wren.

### 2.6 `a1_hand`: In One Hand

```json
{"a1_hand": {
  "name": "In One Hand", "act": 1, "order": 60, "giver": "elder", "auto": true,
  "requires": ["quest:oath", "quest:a1_thirty_first"],
  "steps": [
    {"do": "reach", "place": "altar",
     "text": "The thirtieth wrote: count the names, then the spaces. Go back to the broken altar.",
     "track": "Count the names on the altar",
     "say": [
       "Thirty names, all in one neat hand. Below the last, a thirty-first space has been dressed smooth.",
       "The stone dust in it is new."
     ]},
    {"do": "choose", "to": "elder",
     "text": "Return to Elder Maren by the hearth.",
     "track": "Return to Elder Maren",
     "say": [
       "You went back to the altar. The thirtieth told you to, I suppose. He counted too.",
       "Well. You have seen the space. Ask what you came to ask."
     ],
     "choices": [["Whose hand cut the names?", "ask"], ["You have cut my place already.", "accuse"]],
     "reply": {
       "ask": ["Mine. Every name on the altar, and every one on the gate. I cut each when the ring comes back down."],
       "accuse": ["I dressed that stone the day you came into the vale. I have never once needed to leave a space empty."]
     }}
  ],
  "finish": [
    "I cut them so that someone does. The tower sends down arms. It does not send down names.",
    "But I have never passed the gate. One letter that came down spoke of a tablet inside: the oath, and all your names under it.",
    "I did not cut that one. I have wanted for a long time to know who did."
  ],
  "reward": {"xp": {"vitality": 150}},
  "journal": "Maren cut every name on the altar and the gate, and has dressed a space for yours. Someone inside the tower keeps a list too."
}}
```

Trigger: starts by itself the moment both required quests are done (also checked on load,
so old saves pick it up). Step 1 completes on entering the `altar` spot (`land.gd:85`); the
existing look line still reads thirty names (`overworld_interact.gd:143`). Complete: either
choice. The choice is stored as `flags.a1_hand` and changes only Maren's reply.

### 2.7 `a1_stair`: The First Stair

```json
{"a1_stair": {
  "name": "The First Stair", "act": 1, "order": 70, "giver": "elder",
  "requires": ["quest:a1_hand"],
  "offer": [
    "I will ask a thing of you that I asked of none of the thirty. Not to reach the top. Only to pass the gate and read.",
    "Find the tablet. Face the Warden on the first stair. Then come down and tell me what he said. None of the thirty did."
  ],
  "accept": "I will pass the gate.", "decline": "Not yet.",
  "steps": [
    {"do": "find", "relic": 1,
     "text": "Enter the Ashgrave. Find the tablet in the side chamber off the entry hall.",
     "track": "Find the tablet inside the gate",
     "say": ["Small, neat letters. It is the hand from the altar. But Maren has never passed the gate."]},
    {"do": "win", "tier": 1,
     "text": "Defeat the Cinder Warden, guardian of the first stair.",
     "track": "Defeat the Cinder Warden",
     "say": ["You were asked to carry word down. Leave by the gate behind you."]},
    {"do": "choose", "to": "elder",
     "text": "Go down to Hearthvale and tell Elder Maren what you found.",
     "track": "Tell Maren what you found",
     "say": ["You came back down. No one who faced the Warden has, in all my years. The tablet, then the Warden. What did he say?"],
     "choices": [["Tell Maren everything.", "all"], ["Keep back the Warden's words.", "keep"]],
     "reply": {
       "all": ["'He will be glad of you.' Glad. Then he is still himself, somewhere in it."],
       "keep": ["Nothing you will repeat. Very well. Keep it. I have kept worse."]
     }}
  ],
  "finish": [
    "The hand on the tablet is the hand on the altar. It would be. We learned our letters at one table, he and I.",
    "My brother carved it. He went up before your line had a name, and I have been sending you after him ever since.",
    "Do not ask me yet whether you are to bring him down or keep him company. I have had longer than anyone to decide.",
    "Brannoc found a second sword at the gate this morning, cleaned and laid out. The Warden's. Take it. He meant it for you."
  ],
  "reward": {"gold": 150, "xp": {"blade": 200, "vitality": 200}, "item": "wardens_brand", "flags": {"act": "2"}},
  "journal": "The tablet is in the hand of Maren's brother, who went up before the line had a name. Maren has sent heirs after him ever since. It is the Warden who lays the arms at the gate."
}}
```

Trigger: talk to Elder Maren with `a1_hand` done. Step 1 completes when relic 1 is held
(`world.gd:798`; relic text `story.gd:30`). Step 2 completes when the tier 1 guardian has
been beaten (`run.gd:408`). Both are state checks, so a save that already holds the relic or
has beaten the Warden passes them at once. Complete: either choice, stored as
`flags.a1_stair` (`all` or `keep`); Act 2 reads it. Reward item `wardens_brand` exists
(`items.gd:10`).

## 3. Inscriptions and letters met in Act 1

|Where|Text|State|
|---|---|---|
|Ash Gate, on entry|One of the three tier 1 inscriptions, by bloodline|existing, `story.gd:5`|
|Tower gate (`oath` step 1)|"The gate is warm to the touch. Your family name is cut into the stone, again and again, in the same hand."|existing, `quests.gd:55`|
|Broken altar (`oath` step 2)|"Under the moss: 'While one of us tends the fire, none of us need burn.' Below it, a second line, scratched later: 'A lie.'"|existing, `quests.gd:56`|
|Broken altar (look)|"The broken altar. Thirty names are cut into its side, all in one hand."|existing, `overworld_interact.gd:143`|
|The First Vow (relic 1)|"A cracked tablet. The oath is carved in one hand; every heir's name beneath it is carved in the same hand."|existing, `story.gd:30`|
|Letter of the thirtieth (`letter_thirtieth`, from Wren)|"To my heir: Maren will offer you a ring. Before you take it, count the names on the altar. Then count the spaces."|NEW|
|Watchtower stump (`a1_struck`)|"Cut in the stump, small and neat: ISOLDE. Through it, one deep stroke from a different knife."|NEW|
|Altar, second visit (`a1_hand`)|"Thirty names, all in one neat hand. Below the last, a thirty-first space has been dressed smooth." "The stone dust in it is new."|NEW|
|Tablet, after taking it (`a1_stair`)|"Small, neat letters. It is the hand from the altar. But Maren has never passed the gate."|NEW|

Lore entry for the journal (`Story.LORE`, NEW):

```json
{"letter_thirtieth": {
  "name": "Letter of the Thirtieth",
  "text": "To my heir: Maren will offer you a ring. Before you take it, count the names on the altar. Then count the spaces."
}}
```

## 4. Barks

The Cinder Warden's lines exist and do not change (`story.gd:13`): intro "Another of the
blood. Turn back, child."; again "You again, in a new face."; enrage "I held this stair
before your line had a name!"; death "He will be glad of you. That is the horror of it."

NEW entries for `Story.BARKS`, keyed by display name as today. A list means pick one at
random; an empty string means say nothing this time.

```json
{
  "Sworn Blade": {
    "intro": "I swore to him when he was a boy. I know no other thing.",
    "enrage": "The Warden is too gentle with you!",
    "death": "Tell the Warden... I held as long as he asked."},
  "Ash Thrall": {
    "intro": ["...the gate... is warm...", "...whose name?...", ""],
    "death": "...warm..."},
  "Field Thrall": {
    "intro": ["...south...", "...a light...", ""],
    "death": "...cold again..."},
  "Bog Wight": {
    "intro": ["...deeper...", "...almost through...", ""],
    "death": "...Sister... is it out?..."},
  "Mire Hexer": {
    "intro": ["The shrine gave freely. I only took more.", "Wren sent you. She sends everyone."],
    "enrage": "It was ours before it was hers!",
    "death": "...ask her... what the cisterns cost..."},
  "Greywood Bandit": {
    "intro": ["Purse first. Then we can both go home.", "The warden cannot be everywhere. You can."],
    "death": "...she will only... get up again..."},
  "Greywood Poacher": {
    "intro": ["Deer do not carry coin. You do.", ""],
    "death": "...the tally... burn it..."}
}
```

`Sworn Blade` is the tier 1 elite (`enemy_def.gd:157`); `Ash Thrall` the tier 1 lesser
(`tiers.gd:12`); the rest are land foes (`land.gd:39-46`).

## 5. What characters say when nothing is asked of them

Today an NPC with no quest business says "Good day to you." (`overworld_interact.gd:128`).
NEW idle lines, first matching condition wins. Brannoc has none: with nothing to say his
shop opens (`overworld_interact.gd:119`).

```json
{
  "elder": {"if": [
      ["loop>=1", "You reached the top, and the fire still burns. Sit. I am not surprised. Only sorry."],
      ["bloodline>=2", "You have the last one's hands already. The hearth is quick about that."]],
    "else": "The hearth is lit. That is all the news I trust."},
  "alchemist": {"if": [
      ["bloodline>=2", "Another cloak for the shelf. I folded it myself."]],
    "else": "Marigold for one flask. Bogroot for two. The mire is generous to the patient."},
  "fisher": {"if": [
      ["bloodline>=2", "A new face and the same cast. I have stopped being surprised."]],
    "else": "The pike are biting. They do not care who climbs."},
  "ranger": {"if": [
      ["bloodline>=2", "You went, then. And here you are again, with someone else's eyes."]],
    "else": "One warden. Count the trees and tell me if it is enough."},
  "villager": {"if": [
      ["quest:a1_stair", "They say someone came back down. My mother would not have believed it."],
      ["quest:a1_bone", "Brannoc says leave the thralls be. Brannoc does not hang washing by the north wall."]],
    "else": ""}
}
```

An empty villager line falls through to the existing small talk (`quests.gd:66-72`).

## 6. Check against the code

Places used: `smith`, `elder`, `alchemist`, `fisher`, `ranger`, `circle`, `watch`, `altar`,
`tower` (`land.gd:67-87`). Foes: `thrall`, `wight` (`land.gd:39,41`); Cinder Warden
(`enemy_def.gd:41`). Materials: `bone`, `meal_trout`, `arrow`, `bogroot` (`craft.gd:35-44`).
Items: `wardens_brand` (`items.gd:10`). Relic 1 (`story.gd:30`). Skills in rewards:
vitality, slaying, smithing, fishing, archery, alchemy, blade (`craft.gd:5-19`).

**Nothing new is needed in `land.gd`, `items.gd`, `craft.gd` or `enemy_def.gd`.**

What an engineer must add for Act 1 to play:

|#|What|File|
|---|---|---|
|1|Read `requires`, `order`, `auto`, `accept`, `decline`, `track`, `journal`, `reply`, and `if`/`else` variants; rewards `mats`, `lore`, `flags`|`quests.gd`|
|2|Step `find` (relic held) and step `win` (tier beaten), each checked when the step becomes current and from one new hook: relic pickup (`world.gd:798`) and guardian win (`run.gd:408`)|`quests.gd`, `world.gd`, `run.gd`|
|3|Talk order: an active step addressed to this NPC comes before a new offer; offers go by `order`|`quests.gd:148`|
|4|After a choice, show `reply` then `finish`; today the `say` lines play a second time (`quests.gd:205`)|`quests.gd`|
|5|Journal: page or scroll, grouped by act; it fits five cards today (`world_hud.gd:852-865`). Tracker: draw `track` (`world_hud.gd:648`)|`world_hud.gd`|
|6|The seven quest blocks, `BARKS` additions, `LORE`, idle lines; `BARKS` values may be lists|`quests.gd`, `story.gd`|
|7|`lore` list in the save defaults (the save only grows)|`run.gd:43`|
|8|Bot scenario: accept `a1_thirty_first`, talk to three NPCs, assert done and 30 gold|`overworld_bot.gd`|

## 7. Line check

Every line above was measured with the game font (Cinzel 700) at the sizes and widths the HUD
uses on a 1280 by 720 viewport, the narrowest case. Results: talk lines at most 2 rows of
1000 px; lines that share the box with choices at most 3 rows of 520 px; choice labels within
426 px; captions at most 2 rows of 716 px; journal entries at most 2 rows; tracker lines
within 520 px with the quest name; barks at most 56 characters; no conversation longer than
6 boxes. No contractions, no dashes, plain quotes only.
