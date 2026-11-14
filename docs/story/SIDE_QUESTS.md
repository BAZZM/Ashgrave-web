# Ashgrave side questlines

Written to the schema in `docs/STORY_BIBLE.md` section 9 and the phone limits in its section 3,
one questline per hook in bible section 7. Every block below is valid JSON and also a valid
GDScript Dictionary literal. All text is NEW unless it carries a `file:line`. Anything the engine
does not yet have is listed under NEEDS at the end.

Side quests do not belong to an act. `act` is set to the act in which the player first meets the
giver: 1 for Hearthvale, the Meadows, Greywood's Isolde, Mirefen's Wren and the Scar's Brannoc
and Tam; 2 for Mag Pye, the second stones, the Old Ruins and the Ashlands.

## 1. Order of play

|#|id|Name|Region|Giver|Opens when|State|
|---|---|---|---|---|---|---|
|1|`side_bread`|Hearth Bread|Hearthvale|villager|always|NEW|
|2|`side_trader`|Trader's Tally|Hearthvale|store|`a1_thirty_first` done|NEW|
|3|`side_thralls`|Nan's Rows|Meadows|Nan Harrow|`a1_bone` done|NEW|
|4|`side_marigold`|Hearthward Rows|Meadows|Nan Harrow|always|NEW|
|5|`side_isolde`|Isolde's Cell|Greywood|Warden Isolde|`a1_struck` done|NEW|
|6|`side_pye`|Mag's Lesson|Greywood|Mag Pye|`a2_key` done|NEW|
|7|`side_cloaks`|Wren's Cloaks|Mirefen|Sister Wren|`a1_diggers` done|NEW|
|8|`side_hexer`|A Hexer's Word|Mirefen|starts itself|`a1_diggers` done|NEW|
|9|`side_mine`|The Mine Road|The Scar|Brannoc|`forge` done|NEW|
|10|`side_stones`|Second Hum|The Scar|Old Tam|`a2_rune` done|NEW|
|11|`side_lie`|Who Wrote a Lie|Old Ruins|Keeper Oswin|`a1_hand` done|NEW|
|12|`side_keepers`|Keepers' Ward|Old Ruins|Keeper Oswin|`a1_hand` done|NEW|
|13|`side_cousin`|A Cousin's Duel|Ashlands|Taskmaster|`a1_stair` done|NEW|
|14|`side_plot`|Dead House Plot|Ashlands|Taskmaster|`a1_stair` done|NEW|

Each questline has two or three steps, a hook in its offer, and a payoff in its finish lines.
The payoff changes how one character, or the central question, looks.

## 2. Hearthvale

### 2.1 `side_bread`: Hearth Bread

```json
{"side_bread": {
  "name": "Hearth Bread", "act": 1, "order": 10, "giver": "villager",
  "requires": [],
  "offer": [
    "My mother left bread out for the heirs. So do I. It keeps.",
    "Only the bread does not keep if no one eats it. Bring me two grilled trout for the table. Then talk to the elder about the bread."
  ],
  "accept": "I will bring the trout.", "decline": "Not now.",
  "steps": [
    {"do": "bring", "to": "villager", "mats": {"meal_trout": 2},
     "text": "Bring the villager 2 grilled trout for the hearthstone.",
     "track": "Bring 2 grilled trout"},
    {"do": "talk", "to": "elder",
     "text": "Talk to Elder Maren about the bread on the hearthstone.",
     "track": "Ask Maren about the bread",
     "say": [
       "They feed you because they sent you. I did not ask them to, and I did not ask them to stop.",
       "That is the trouble with a village. It can feel sorry and leave bread out in the same breath."
     ]}
  ],
  "finish": [
    "Next year they will leave out more. The vale is sorry in its own way, and it will keep saying so until the heirs stop coming.",
    "Eat the bread on the step, then. It is the one thing here that was never sent up the stair."
  ],
  "reward": {"gold": 25, "xp": {"cooking": 60}},
  "journal": "Hearthvale leaves bread out for the heirs. Maren says the village feeds them because it sent them."
}}
```

Trigger: the villager on the hearthstone offers it at once. Step 1 counts 2 `meal_trout`
(`craft.gd:36`). Complete: talk to Maren.

### 2.2 `side_trader`: Trader's Tally

```json
{"side_trader": {
  "name": "Trader's Tally", "act": 1, "order": 20, "giver": "store",
  "requires": ["quest:a1_thirty_first"],
  "offer": [
    "I keep a list of who sells deer to whom. Nobody asked me to keep it. Nobody asked me not to.",
    "It is in a ledger under the scale. I have not decided whether to show it to anyone."
  ],
  "accept": "Show me the ledger.", "decline": "Keep your ledger.",
  "steps": [
    {"do": "choose", "to": "store",
     "text": "Choose: expose the poachers' tally, or keep it under the scale.",
     "track": "Expose or keep the tally",
     "say": ["The tally has names, weights and dates. Do you want it read out loud?"],
     "choices": [["Expose the tally.", "expose"], ["Keep it under the scale.", "keep"]],
     "reply": {
       "expose": ["Then take it to Isolde. I did not say that, and I will swear to it."],
       "keep": ["Good. I make more from silence than from ledgers."]
     }},
    {"do": "talk", "to": "ranger",
     "text": "Tell Warden Isolde what the tally holds.",
     "track": "Tell Isolde about the tally",
     "say": ["Deer, weights and dates. The forest is hungry, and the vale eats what is poached."]}
  ],
  "finish": [
    {"if": [["flag:side_trader=expose", "Then it is in the vale's stomach, and in the Trader's purse. I will say so at the gate."]],
     "else": "Then the vale keeps eating, and the Trader keeps his scale. He will say he never knew."},
    "He never knows anything. He has a very good scale."
  ],
  "reward": {"gold": 60, "xp": {"slaying": 60}},
  "journal": "The Trader keeps a tally of who sells poached deer. Isolde wants to hear it, and the vale eats what is poached."
}}
```

Trigger: talk to the Trader (`store`) with `a1_thirty_first` done. Step 1 is a choice stored as
`flags.side_trader` (`expose` or `keep`). Step 2 is a talk to Isolde. Complete: talk to Isolde.

## 3. Meadows

### 3.1 `side_thralls`: Nan's Rows

```json
{"side_thralls": {
  "name": "Nan's Rows", "act": 1, "order": 30, "giver": "nan",
  "requires": ["quest:a1_bone"],
  "offer": [
    "Thralls walk my rows at night. They go along the furrows as if looking for a seed.",
    "Kill three of them. Bring me their bone. Then we will decide what to do with the rest."
  ],
  "accept": "I will clear them.", "decline": "Let them walk.",
  "steps": [
    {"do": "kill", "foes": ["thrall"], "need": 3,
     "text": "Defeat 3 Field Thralls in Nan Harrow's rows.",
     "track": "Defeat 3 Field Thralls",
     "say": ["It falls into the furrow and does not get up. Its hand still reaches for the light."]},
    {"do": "bring", "to": "nan", "mats": {"bone": 3},
     "text": "Bring Nan Harrow 3 old bone.",
     "track": "Bring Nan 3 old bone"},
    {"do": "choose", "to": "nan",
     "text": "Choose: burn the bone, or bury it in the rows.",
     "track": "Burn or bury the bone",
     "say": ["Burn it and the light stays cold. Bury it and the thralls stop at the furrow's end."],
     "choices": [["Burn it on the fire.", "burn"], ["Bury it in the rows.", "bury"]],
     "reply": {
       "burn": ["It burns with a smell like old wool. The thralls will still come, but fewer of them."],
       "bury": ["Buried deep. The rows are quiet, and the thralls stay where they were put."]
     }}
  ],
  "finish": [
    {"if": [["flag:side_thralls=bury", "Buried thralls stay down. I have three rows that are quiet for the first time."]],
     "else": "Burned thralls stay gone for a season. Then the warmth pulls them up the field again."}
  ],
  "reward": {"gold": 45, "xp": {"slaying": 90, "foraging": 40}},
  "journal": "Thralls walk Nan Harrow's rows toward the light. Buried thralls stay down. Burned ones come back in a season."
}}
```

Trigger: talk to Nan Harrow with `a1_bone` done. Step 1 counts `thrall` kills
(`land.gd:39`). Step 2 counts 3 `bone`. Step 3 is a choice stored as `flags.side_thralls`.

### 3.2 `side_marigold`: Hearthward Rows

```json
{"side_marigold": {
  "name": "Hearthward Rows", "act": 1, "order": 40, "giver": "nan",
  "requires": [],
  "offer": [
    "Marigold grows only hearthward. Each year it grows a little less far from the hearth.",
    "Plant three rows in my field, and I will show you the line I have been marking."
  ],
  "accept": "I will plant them.", "decline": "Not this year.",
  "steps": [
    {"do": "reach", "place": "nan_rows", "plant": 3,
     "text": "Plant three rows of marigold in Nan's field.",
     "track": "Plant three rows",
     "say": ["Three rows in the dark earth. The ground is warm under them, and it is warm only near the hearth."]},
    {"do": "talk", "to": "nan",
     "text": "Return to Nan Harrow with the rows planted.",
     "track": "Return to Nan Harrow",
     "say": ["It retreats one row a year. I have marked it with stakes. Look at the stakes next spring and tell me where they stand."]}
  ],
  "finish": [
    "I have a stake for every year. The warmth shrinks, and someone has to write the marks down.",
    "Take the marigold. It is the only thing here that grows toward the hearth, and it always will."
  ],
  "reward": {"gold": 50, "xp": {"foraging": 80}, "mats": {"marigold": 3}},
  "journal": "Marigold grows only near the hearth. Nan marks each year where the warmth stops, and the mark moves in each year."
}}
```

Trigger: talk to Nan Harrow. Step 1 plants three rows at `nan_rows` (NEW, see NEEDS, and the
Farming skill). Complete: talk to Nan.

## 4. Greywood

### 4.1 `side_isolde`: Isolde's Cell

```json
{"side_isolde": {
  "name": "Isolde's Cell", "act": 1, "order": 50, "giver": "ranger",
  "requires": ["quest:a1_struck"],
  "offer": [
    "Nobody comes to see me except the bandits. The Struck say they are my cousins. I do not argue with the Struck.",
    "Kill three of them. Then go up to the watch and tell me what you see from it."
  ],
  "accept": "I will go.", "decline": "Not now.",
  "steps": [
    {"do": "kill", "foes": ["bandit"], "need": 3,
     "text": "Defeat 3 Greywood Bandits in the wood.",
     "track": "Defeat 3 Greywood Bandits",
     "say": ["It drops its knife and reaches for your coin. Then it stops and looks at its own hand."]},
    {"do": "reach", "place": "watch",
     "text": "Reach the fallen watchtower in Greywood.",
     "track": "Reach the fallen watchtower",
     "say": ["From the stump you can see the Struck camp. Smoke, and a line of cloaks drying on a rope."]},
    {"do": "talk", "to": "ranger",
     "text": "Return to Warden Isolde at the end of the forest road.",
     "track": "Return to Warden Isolde",
     "say": ["Struck cousins. They take the road and send the coin to the ones who refused the oath. Do not thank me."]}
  ],
  "finish": [
    "I will not ask you to join them. I will ask you to stop thinking they are only thieves.",
    "The watch is mine by right. Nobody else has ever come up to look at what I can see."
  ],
  "reward": {"gold": 40, "xp": {"archery": 80, "slaying": 100}},
  "journal": "Isolde's bandits are Struck cousins who send their coin to the heirs who refused. Nobody else visits her."
}}
```

Trigger: talk to Warden Isolde with `a1_struck` done. Step 1 counts `bandit` kills
(`land.gd:40`). Step 2 completes at the `watch` spot (`land.gd:87`). Complete: talk to Isolde.

### 4.2 `side_pye`: Mag's Lesson

```json
{"side_pye": {
  "name": "Mag's Lesson", "act": 2, "order": 60, "giver": "magpye",
  "requires": ["quest:a2_key"],
  "offer": [
    "Everything you have ever taken from a chest, you took because nobody was watching. I can teach you the other kind.",
    "Lift a purse from a traveller on the road. Then come back and show me how quick you were."
  ],
  "accept": "Teach me.", "decline": "I am not in the mood.",
  "steps": [
    {"do": "find", "item": "purse", "place": "forest",
     "text": "Lift a purse from a traveller in Greywood (Thieving).",
     "track": "Lift a purse",
     "say": ["The purse is warm from a hand. Do not count the coin on the road."]},
    {"do": "talk", "to": "magpye",
     "text": "Return to Mag Pye with the purse.",
     "track": "Return to Mag Pye",
     "say": ["Quick, and not clean. A clean lift is the one nobody remembers. Now you know that."]},
    {"do": "reach", "place": "watch",
     "text": "Reach the fallen watchtower and show Isolde what you learned.",
     "track": "Reach the fallen watchtower",
     "say": ["The stump still has her name cut in it. Do not touch it, and do not lift anything from her."]}
  ],
  "finish": [
    "Mag taught Isolde to run, long ago. Isolde does not say so. She runs the same way.",
    "Of the blood, and ran. Now you have run too. Keep the purse. It is your first debt."
  ],
  "reward": {"gold": 60, "xp": {"agility": 120}},
  "journal": "Mag Pye taught Isolde to run. She teaches a lift now: quick, not clean. Both went to the same watch."
}}
```

Trigger: talk to Mag Pye with `a2_key` done. Step 1 counts a held `purse` (NEW item, see
NEEDS) and the Thieving skill. Complete: talk to Mag Pye at step 2; step 3 is the watch.

## 5. Mirefen

### 5.1 `side_cloaks`: Wren's Cloaks

```json
{"side_cloaks": {
  "name": "Wren's Cloaks", "act": 1, "order": 70, "giver": "alchemist",
  "requires": ["quest:a1_diggers"],
  "offer": [
    "I have a shelf of folded cloaks and nothing to put in them. Each one came from a heir's chest.",
    "Bring me three bogroot for the salve. Then go and see the shrine. It burns for each of you."
  ],
  "accept": "I will bring the bogroot.", "decline": "Not now.",
  "steps": [
    {"do": "bring", "to": "alchemist", "mats": {"bogroot": 3},
     "text": "Bring Sister Wren 3 bogroot for the salve.",
     "track": "Bring Wren 3 bogroot"},
    {"do": "reach", "place": "shrine",
     "text": "Reach the Mire shrine and count the flames.",
     "track": "Count the flames at the shrine",
     "say": ["One flame for each heir. They still burn. The brightest one is the newest, and it is not yours."]},
    {"do": "talk", "to": "alchemist",
     "text": "Return to Sister Wren and tell her the count.",
     "track": "Return to Sister Wren",
     "say": ["Thirty flames, and one new. You counted. Now you know why I fold cloaks."]}
  ],
  "finish": [
    "The Sisters built the shrine to keep the count. They did not build it to keep the heirs.",
    "I will keep the shelf. Someone should have something to fold while they wait."
  ],
  "reward": {"gold": 50, "xp": {"alchemy": 100}},
  "journal": "Wren's shelf holds cloaks with no bodies. The Mire shrine burns one flame per heir: thirty."
}}
```

Trigger: talk to Sister Wren with `a1_diggers` done. Step 1 counts 3 `bogroot`
(`craft.gd:43`). Step 2 completes at the `shrine` spot (`land.gd:92`). Complete: talk to Wren.

### 5.2 `side_hexer`: A Hexer's Word

```json
{"side_hexer": {
  "name": "A Hexer's Word", "act": 1, "order": 80, "giver": "hexer",
  "requires": ["quest:a1_diggers"], "auto": true,
  "steps": [
    {"do": "reach", "place": "shrine",
     "text": "Go to the Mire shrine. Something in the reeds wants to talk.",
     "track": "Go to the Mire shrine",
     "say": ["A hexer steps out of the reeds with its hands open. It says Wren sent you, and that it has something to say."]},
    {"do": "choose", "to": "alchemist",
     "text": "Tell Sister Wren what the hexer said.",
     "track": "Tell Wren the hexer's words",
     "say": ["It wanted to talk. Tell me what it said, or tell me you struck it first."],
     "choices": [["Tell her all of it.", "all"], ["Tell her you struck it.", "strike"]],
     "reply": {
       "all": ["So the Sisters taught the craft and then forgot to say whose it was. Now I know where it went."],
       "strike": ["Then you killed one of the Sisters' pupils. I will not forgive it, and I will keep asking why."]
     }}
  ],
  "finish": [
    "The hexers are Sisters who sold the craft. They left because the order would not say whose craft it was.",
    "Wren will go to the shrine herself, one day soon. She will want to hear the rest from the hexers' mouths."
  ],
  "reward": {"gold": 40, "xp": {"sorcery": 120}},
  "journal": "A hexer at the Mire shrine says the Sisters sold it their craft. Wren wants the whole of what it said."
}}
```

Trigger: starts by itself once `a1_diggers` is done (old saves pick it up on load). Step 1
completes at the `shrine` spot (`land.gd:92`). Step 2 is a choice stored as `flags.side_hexer`.
The hexer's offer to talk, or to fight, is the choice at step 1; see NEEDS.

## 6. The Scar

### 6.1 `side_mine`: The Mine Road

```json
{"side_mine": {
  "name": "The Mine Road", "act": 1, "order": 90, "giver": "smith",
  "requires": ["quest:forge"],
  "offer": [
    "The mine road went bad. The brutes came down it in the spring, and they carry no iron of their own.",
    "Kill three on the road. Bring me four iron ore for the forge. Then tell me where they came from."
  ],
  "accept": "I will clear the road.", "decline": "Not now.",
  "steps": [
    {"do": "kill", "foes": ["brute"], "need": 3,
     "text": "Defeat 3 Stone Brutes on the mine road in the Scar.",
     "track": "Defeat 3 Stone Brutes",
     "say": ["Its back has a Foundry stamp, the same kind that is on the arms that come down the stair."]},
    {"do": "bring", "to": "smith", "mats": {"iron_ore": 4},
     "text": "Bring Brannoc 4 iron ore from the Scar.",
     "track": "Bring Brannoc 4 iron ore"},
    {"do": "talk", "to": "smith",
     "text": "Return to Brannoc the Smith.",
     "track": "Return to Brannoc",
     "say": ["Discards. The Foundry throws them down the quarry road. I do not ask why it throws them."]}
  ],
  "finish": [
    "Your family built the tower out of this quarry. The brutes are the workers the Foundry could not use.",
    "The road is clear. Do not bring me another one that stamps."
  ],
  "reward": {"gold": 70, "xp": {"mining": 120, "slaying": 100}},
  "journal": "The mine road is full of stone brutes, the Foundry's discards. The quarry still throws them down."
}}
```

Trigger: talk to Brannoc with `forge` done. Step 1 counts `brute` kills (`land.gd:50`). Step 2
counts 4 `iron_ore` (`craft.gd:24`). Complete: talk to Brannoc.

### 6.2 `side_stones`: Second Hum

```json
{"side_stones": {
  "name": "Second Hum", "act": 2, "order": 100, "giver": "fisher",
  "requires": ["quest:a2_rune"],
  "offer": [
    "The stones east of the bridge hum too. I heard them when I was young. I thought it was the ferry.",
    "Go and find out. You have the trick of the rune now, from Oswin."
  ],
  "accept": "I will go.", "decline": "Not now.",
  "steps": [
    {"do": "reach", "place": "second_stones",
     "text": "Go to the second humming stones in the Scar.",
     "track": "Find the second stones",
     "say": ["The hum is lower here. It comes up through your boots, the same way it did at the western ring."]},
    {"do": "reach", "place": "second_stones", "trace": "oath_rune",
     "text": "Trace the rune on the second stones with Runecraft.",
     "track": "Trace the rune",
     "say": ["The rune is the oath's first line, cut a second time. Each stroke hums the note of the ring in the west."]},
    {"do": "talk", "to": "fisher",
     "text": "Return to Old Tam at the lake.",
     "track": "Return to Old Tam",
     "say": ["Two rings, one hand. I told you it got louder after each heir. It is the oath, repeating."]}
  ],
  "finish": [
    "The oath is in the ground and in the stones. Each heir makes the ground sing a little louder.",
    "Keep this to yourself. Old Tam has listened to that hum for sixty years, and he has never said so to the elder."
  ],
  "reward": {"gold": 60, "xp": {"fishing": 100}},
  "journal": "Old Tam says the stones east of the bridge hum. The rune there is the oath, cut again."
}}
```

Trigger: talk to Old Tam with `a2_rune` done. Step 1 completes at `second_stones` (NEW spot,
see NEEDS). Step 2 uses the `trace` field (NEW, see NEEDS). Complete: talk to Tam.

## 7. The Old Ruins

### 7.1 `side_lie`: Who Wrote a Lie

```json
{"side_lie": {
  "name": "Who Wrote a Lie", "act": 2, "order": 110, "giver": "oswin",
  "requires": ["quest:a1_hand"],
  "offer": [
    "Someone scratched a word under the oath at the broken altar. It says a lie. It is not a Keeper's hand.",
    "Kill one Ruin Seer. Then take a cinder shard to Elder Maren and watch his hand while he takes it."
  ],
  "accept": "I will find out.", "decline": "Leave it alone.",
  "steps": [
    {"do": "kill", "foes": ["seer"], "need": 1,
     "text": "Defeat a Ruin Seer in the Old Ruins.",
     "track": "Defeat a Ruin Seer",
     "say": ["It speaks the oath back to you, word for word, then stops at the scratch. It will not say the last word."]},
    {"do": "bring", "to": "elder", "mats": {"cinder": 1},
     "text": "Bring Elder Maren a cinder shard.",
     "track": "Bring Maren a cinder shard"}
  ],
  "finish": [
    "I scratched it. I did it after the tenth went up, and it was the first time I said it aloud. I said it to the stone.",
    "Oswin will ask me why I did not cut it deeper. I will tell him the stone was already full."
  ],
  "reward": {"gold": 50, "xp": {"sorcery": 120}},
  "journal": "The scratch 'A lie.' under the oath is Maren's, cut after the tenth heir. The Seers say it back."
}}
```

Trigger: talk to Keeper Oswin with `a1_hand` done. Step 1 counts `seer` kills (`land.gd:56`).
Step 2 counts 1 `cinder` and completes when given to Maren. Complete: the bring.

### 7.2 `side_keepers`: Keepers' Ward

```json
{"side_keepers": {
  "name": "Keepers' Ward", "act": 2, "order": 120, "giver": "oswin",
  "requires": ["quest:a1_hand"],
  "offer": [
    "Two Keepers stand at the altar and do nothing but stand. I want to know what they are guarding.",
    "Kill two of them. Then ask me what they were guarding. I will tell you, and you will not like it."
  ],
  "accept": "I will kill them.", "decline": "Not now.",
  "steps": [
    {"do": "kill", "foes": ["keeper"], "need": 2,
     "text": "Defeat 2 Ruin Keepers in the Old Ruins.",
     "track": "Defeat 2 Ruin Keepers",
     "say": ["It stops in the middle of a word, and the word was the oath's. It falls with its hand still on the stone."]},
    {"do": "talk", "to": "oswin",
     "text": "Return to Keeper Oswin and ask what they guard.",
     "track": "Ask Oswin what they guard",
     "say": ["They guard the wording against change. The oath must be said the same way each time, or the fire forgets it."]}
  ],
  "finish": [
    "The wording is kept exact. That is all the Keepers were built for. I have never once asked whether it should be.",
    "You have asked. That is a worse habit than the oath, and I am glad of it."
  ],
  "reward": {"gold": 60, "xp": {"blade": 120}},
  "journal": "Ruin Keepers guard the oath's wording against change. Oswin says that is all they were built for."
}}
```

Trigger: talk to Keeper Oswin with `a1_hand` done. Step 1 counts `keeper` kills
(`land.gd:51`). Complete: talk to Oswin.

## 8. The Ashlands

### 8.1 `side_cousin`: A Cousin's Duel

```json
{"side_cousin": {
  "name": "A Cousin's Duel", "act": 2, "order": 130, "giver": "task",
  "requires": ["quest:a1_stair"],
  "offer": [
    "A cousin of the blood has put a stake on you at the ash line. You have never met him. He has watched you from the stair.",
    "Take the duel. Then come and see me about why the loser pays."
  ],
  "accept": "I accept.", "decline": "I do not fight cousins.",
  "steps": [
    {"do": "kill", "foes": ["cousin"], "need": 1,
     "text": "Win one live duel in the Ashlands against a cousin of the blood.",
     "track": "Win one live duel",
     "say": ["He bows, then strikes. He is not a guardian. He is only as tired as you are."]},
    {"do": "talk", "to": "task",
     "text": "Return to the Taskmaster at the ash line.",
     "track": "Return to the Taskmaster",
     "say": ["Cousins cannot kill each other outside the tower. So the loser pays in gold and ground, and never in blood."]}
  ],
  "finish": [
    "Stakes are gold, holdings or a month of road tolls. The blood stays whole. Be careful what you bet with.",
    "Next time he will bring a stake you cannot pay. Then you will know the whole of the ash line."
  ],
  "reward": {"gold": 90, "xp": {"blade": 100, "guard": 100}},
  "journal": "A cousin of the blood challenged you at the ash line. The loser pays, and the blood stays whole."
}}
```

Trigger: the Taskmaster's offer at the ash line, once `a1_stair` is done. Step 1 counts one
live duel win against `cousin` (NEW, see NEEDS). Step 2 is a talk. Complete: talk to the
Taskmaster (`task`, `land.gd:81`).

### 8.2 `side_plot`: Dead House Plot

```json
{"side_plot": {
  "name": "Dead House Plot", "act": 2, "order": 140, "giver": "task",
  "requires": ["quest:a1_stair"],
  "offer": [
    "There is a plot at the ash line where a house died. The hearth stone is still there, and no roof.",
    "Bring me three ember ore and two ashwood. Then raise a banner stone on the plot. It is the only thing a dead house leaves behind."
  ],
  "accept": "I will bring them.", "decline": "Not now.",
  "steps": [
    {"do": "bring", "to": "task", "mats": {"ember_ore": 3, "ash_log": 2},
     "text": "Bring the Taskmaster 3 ember ore and 2 ashwood logs.",
     "track": "Bring 3 ember ore, 2 ashwood"},
    {"do": "reach", "place": "holding_plot",
     "text": "Go to the dead house's plot in the Ashlands.",
     "track": "Go to the dead house's plot",
     "say": ["A wall, a hearth stone and no roof. The house held this ground for three generations and left the stone."]},
    {"do": "reach", "place": "holding_plot", "raise": "banner_stone",
     "text": "Raise a banner stone on the plot.",
     "track": "Raise a banner stone",
     "say": ["You set the stone upright in the old hearth. Nothing burns in it. The wind is from the north, and it still counts."]}
  ],
  "finish": [
    "A holding is a future off the stair. The plot is yours if you can keep it warm.",
    "The Taskmaster will take the stakes from anyone who asks. The plot will not be taken while the stone stands."
  ],
  "reward": {"gold": 120, "xp": {"smithing": 150}},
  "journal": "A dead house's plot at the ash line has a hearth and no roof. A banner stone there is a future."
}}
```

Trigger: the Taskmaster's offer, once `a1_stair` is done. Step 1 counts 3 `ember_ore` and 2
`ash_log` (`craft.gd:23,39`). Step 2 completes at the `holding_plot` spot. Step 3 raises a
`banner_stone` at that spot (NEW, see NEEDS). Complete: step 3.

## 9. Check against the code

Places used: `villager` and `store` (Trader), `nan`, `shrine`, `watch`, `task`, `elder`, `smith`,
`ranger`, `alchemist`, `fisher` (`land.gd:67-95`). Foes: `thrall`, `bandit`, `brute`, `keeper`,
`seer`, `cousin` (`land.gd:39-56`). Materials: `meal_trout`, `bone`, `bogroot`, `iron_ore`,
`ember_ore`, `ash_log`, `cinder`, `marigold` (`craft.gd:23-44`). Skills in rewards: cooking,
slaying, foraging, alchemy, sorcery, archery, agility, mining, fishing, smithing, blade, guard
(`craft.gd:5-19`).

## NEEDS

- Places `nan_rows`, `second_stones`, `holding_plot` (Ashlands, see ACT3 NEEDS). `shrine` and
  `watch` already exist (`land.gd:92,87`).
- NPCs not in `land.gd`: `nan` (Meadows), `magpye` (Greywood). `hexer` is a foe, not an NPC: the
  side quest `side_hexer` is `auto` and its giver field is only a label.
- Foe `cousin`: a live duel against another player of the blood (online), counted as a kill.
- Item `purse` (lifted by Thieving) and the Thieving skill, for `side_pye`.
- Farming skill and a `plant` field on reach steps, for `side_marigold`.
- Runecraft skill and the `trace` field on reach steps, for `side_stones`.
- Items `banner_stone` (`side_plot`, `a3_banner`) to be added to `items.gd`.
- Step `choose` on the Trader and on the hexer's talk: the hexer offers to talk or to fight at
  step 1 of `side_hexer`; only the talk branch is written, the fight is the existing combat.
- Quest `side_hexer` has no quest-giver NPC; the offer is an `auto` start.

## Counts

|id|Dialogue lines|Longest line (characters)|
|---|---|---|
|`side_bread`|8|129|
|`side_trader`|11|111|
|`side_thralls`|10|109|
|`side_marigold`|8|118|
|`side_isolde`|9|110|
|`side_pye`|9|114|
|`side_cloaks`|8|95|
|`side_hexer`|6|108|
|`side_mine`|8|101|
|`side_stones`|9|111|
|`side_lie`|7|116|
|`side_keepers`|8|112|
|`side_cousin`|8|120|
|`side_plot`|8|129|
