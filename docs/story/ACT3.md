# Ashgrave Act 3: A Keeper

Written to the schema in `docs/STORY_BIBLE.md` section 9 and the phone limits in its section 3.
Every block below is valid JSON and also a valid GDScript Dictionary literal. All text in this
file is NEW unless it carries a `file:line`. Anything the engine does not yet have is listed
under NEEDS at the end.

**What the act does.** The player finds that the second seam is cold, so the fire lives on the
blood alone. The Ashlands holdings each make their case, and the player picks one to stand by.
In the Pyre Court the player beats the Regent and makes the ending choice, which decides whose
fire it is. At the hearth the player decides what becomes of the coal that kept two brothers and
one vale warm.

## 1. Order of play

|#|id|Name|Giver|Opens when|State|
|---|---|---|---|---|---|
|1|`a3_seam`|The Dead Seam|Keeper Oswin|`a2_rune` done|NEW|
|2|`a3_banner`|Three Holdings|Warden Isolde|`a2_letter` done|NEW|
|3|`a3_court`|The Pyre Court|Elder Maren|five relics held and `a2_letter` done|NEW|
|4|`a3_hearth`|The Hearth|Elder Maren|`a3_court` done|NEW|

Rows 1 and 2 may be played in any order. Row 3 is the finale: its duel ends in one of three
endings (section 3). Row 4 is read after the ending and changes the later loops.
Level band: an heir at the Pyre Court's tier 5, with all five relics.

## 2. The quests

### 2.1 `a3_seam`: The Dead Seam

```json
{"a3_seam": {
  "name": "The Dead Seam", "act": 3, "order": 10, "giver": "oswin",
  "requires": ["quest:a2_rune"],
  "offer": [
    "There is a second dungeon cut into the ember seam. My order was told the seam burned. I was never sure.",
    "Go to the end of it. Then come back and tell me what the stone is doing."
  ],
  "accept": "I will go down.", "decline": "Not yet.",
  "steps": [
    {"do": "reach", "place": "seam_end",
     "text": "Reach the end of the second dungeon, where the seam was dug.",
     "track": "Reach the end of the seam",
     "say": ["The vein is cold to the palm. The fire in the tower is not in this rock. It never was."]},
    {"do": "talk", "to": "oswin",
     "text": "Return to Keeper Oswin at the Old Ruins.",
     "track": "Return to Keeper Oswin",
     "say": [
       "The seam is cold. Then the fire lives on blood alone, and it never came up out of the ground.",
       "I will write that down exactly. Someone should write down a thing that is true and bad at once."
     ]}
  ],
  "finish": [
    "Your line has warmed the tower for two hundred years. The ground never did.",
    "Wear this. It is the only ember left in the vale that has not been fed to the tower."
  ],
  "reward": {"gold": 120, "xp": {"smithing": 200}, "item": "ember_ring"},
  "journal": "The second seam is cold. The fire lives on the blood alone, and it never came up out of the ground."
}}
```

Trigger: talk to Keeper Oswin with `a2_rune` done. Step 1 completes on entering `seam_end`
(NEW spot, see NEEDS). Step 2 is a talk. Complete: talk to Oswin. The reward `ember_ring` is an
existing ring (`items.gd:30`), the "ember gear" the bible names.

### 2.2 `a3_banner`: Three Holdings

```json
{"a3_banner": {
  "name": "Three Holdings", "act": 3, "order": 20, "giver": "ranger",
  "requires": ["quest:a2_letter"],
  "offer": [
    "The dead court's holdings in the ash are going to whoever shouts loudest. Three of them have shouted at me this month.",
    "Go and hear each one. Then tell me which one you can stand beside. I am not asking which you would like."
  ],
  "accept": "I will hear them.", "decline": "Not yet.",
  "steps": [
    {"do": "reach", "place": "holding_tenders",
     "text": "Visit the Tenders' holding in the Ashlands.",
     "track": "Hear the Tenders",
     "say": ["We tend the ember. Put it out and the cold comes down the stair into the vale. Let the tower keep its fire."]},
    {"do": "reach", "place": "holding_quenchers",
     "text": "Visit the Quenchers' holding in the Ashlands.",
     "track": "Hear the Quenchers",
     "say": ["Ash on every roof and in every well. Put the water back on the pyre, and then no one needs fire again."]},
    {"do": "reach", "place": "holding_struck",
     "text": "Visit the Struck's holding in the Ashlands.",
     "track": "Hear the Struck",
     "say": ["We do not climb and we do not send. The oath took our names. We took them back, and we keep them."]},
    {"do": "choose", "to": "ranger",
     "text": "Tell Warden Isolde which holding you will stand beside.",
     "track": "Choose a holding to stand by",
     "say": ["Three holdings, three cases. Which one can you stand beside?"],
     "choices": [["Stand with the Tenders.", "tenders"], ["Stand with the Quenchers.", "quenchers"], ["Stand with the Struck.", "struck"]],
     "reply": {
       "tenders": ["The Tenders keep the oath and the stair. They will want more of us to climb, and they will be kind about it."],
       "quenchers": ["The Quenchers want the water on the pyre. Sister Wren will like that. She will want one of your blood to do it."],
       "struck": ["The Struck take no heirs. Some of them will be angry about it, and some of them will be dead by spring."]
     }}
  ],
  "finish": [
    "Each holding will remember which of your line stood beside it. That is all a banner is in the ash.",
    "Take this stone. Set it at the holding's edge. It is not a claim, only a name cut in stone."
  ],
  "reward": {"gold": 150, "item": "banner_stone"},
  "journal": "Three Ashlands holdings state their claims. Isolde asks which one you will stand beside."
}}
```

Trigger: talk to Warden Isolde with `a2_letter` done. Steps 1 to 3 complete on entering each
holding spot (NEW, see NEEDS). Step 4 is the lean, stored as `flags.a3_banner` (`tenders`,
`quenchers` or `struck`). Complete: the choice. The reward `banner_stone` is the NEW item the
bible names (see NEEDS).

### 2.3 `a3_court`: The Pyre Court

```json
{"a3_court": {
  "name": "The Pyre Court", "act": 3, "order": 30, "giver": "elder",
  "requires": ["relic:1", "relic:2", "relic:3", "relic:4", "relic:5", "quest:a2_letter"],
  "offer": [
    "You have the tablet, the crown, the blade, the letter and the ember. I did not think you would bring all five.",
    "The Court is the last tier. Go up and win it. Then come down and tell me whose fire it was."
  ],
  "accept": "I will climb it.", "decline": "Not yet.",
  "steps": [
    {"do": "win", "tier": 5,
     "text": "Defeat the Hollow Regent in the Pyre Court, with all five relics held.",
     "track": "Defeat the Hollow Regent",
     "say": ["He is hungry, and he has waited a long time for someone to climb up and talk to him. The helm is too big for him."]},
    {"do": "talk", "to": "elder",
     "text": "Return to Elder Maren by the hearth.",
     "track": "Return to Elder Maren",
     "say": [
       {"if": [
          ["flag:ending=finish", "You put him out. The tower will call that a finish. I call it a quiet stair."],
          ["flag:ending=spare", "You left him the door. Did he say anything to you on the way down?"],
          ["flag:ending=throne", "You sat in his place. The fire took to you very fast."]],
        "else": "You came down. Whatever you did up there, you did it with the fire still lit."},
       "It was never his fire. It sits wherever our blood sits, and our blood keeps feeding it."
     ]}
  ],
  "finish": [
    {"if": [
       ["flag:ending=finish", "The helm lies empty. The armour stands up again, and it is hollow all the way through."],
       ["flag:ending=spare", "The pyre has gone dark. The door at the top stands open, as he asked."],
       ["flag:ending=throne", "The fire is yours now. It will keep you, and you will keep it."]],
     "else": "The top of the tower is quiet."},
    "Take these cinders for the Court. They are the last the vale will be given."
  ],
  "reward": {"gold": 200, "xp": {"blade": 300, "vitality": 300}, "mats": {"cinder": 6}},
  "journal": "The Pyre Court's fire was never the Regent's. The blood keeps feeding it. The ending was yours."
}}
```

Trigger: talk to Elder Maren with all five relics held and `a2_letter` done. Step 1 completes
on the tier 5 guardian (`run.gd:408`) with `relic:1` to `relic:5` held (`world.gd:798`). The
ending is chosen in the duel and stored as `flags.ending` (`finish`, `spare` or `throne`); see
section 3. Complete: talk to Maren. The journal is the closing entry.

### 2.4 `a3_hearth`: The Hearth

```json
{"a3_hearth": {
  "name": "The Hearth", "act": 3, "order": 40, "giver": "elder",
  "requires": ["quest:a3_court"],
  "steps": [
    {"do": "talk", "to": "elder",
     "text": "Return to Elder Maren by the hearth.",
     "track": "Return to Elder Maren",
     "say": [
       "The hearth is the coal Maren carried down the first day. It kept two brothers and one vale warm.",
       "Without it the vale gets winter, and the brothers die. Now you decide what it does next."
     ]},
    {"do": "choose", "to": "elder",
     "text": "Choose what becomes of the hearth: bank it, send Maren up, or douse it.",
     "track": "Choose the fate of the hearth",
     "say": ["The coal is yours to decide. Maren will not decide it for you."],
     "choices": [["Bank the hearth and keep it low.", "bank"], ["Send Maren up the stair.", "send"], ["Douse the hearth with Sister Wren.", "douse"]],
     "reply": {
       "bank": ["Banked under the ash. The coal will keep. So will the cold, for a while yet, down the stair."],
       "send": ["Then I will go up. I have sent thirty of you. I can take the first step myself, once."],
       "douse": ["Then Wren will drown it, and she will need one of the blood to hold the sluice. I will not stop you. We both go out."]
     }}
  ],
  "finish": [
    {"if": [
       ["flag:a3_hearth=douse", "The coal is in the water. Wren is quiet. The vale will be cold by midwinter."],
       ["flag:a3_hearth=send", "The elder is on the first step, and he has not looked back."]],
     "else": "The coal is banked under the ash. It will keep until someone opens the door."}
  ],
  "reward": {"xp": {"vitality": 300}, "flags": {"act": "3"}},
  "journal": "The hearth kept two brothers and one vale warm. What it does next was your choice."
}}
```

Trigger: talk to Elder Maren with `a3_court` done. Step 2 is a choice stored as `flags.a3_hearth`
(`bank`, `send` or `douse`). The later loops read that flag (section 3). Complete: the choice.

## 3. Endings and later loops

The duel in the Pyre Court sets `flags.ending` to one of three values. Each ending's lines are
shown after the win, read by `a3_court` (section 2.3), and kept for later loops.

|`flags.ending`|What the player does|Shown at the end (talk line, 160 characters or fewer)|Later loops|
|---|---|---|---|
|`finish`|Finishes the Regent (S:37)|"The helm lies empty. The armour stands up again, and it is hollow all the way through."|Maren: "You reached the top, and the fire still burns. Sit. I am not surprised. Only sorry."|
|`spare`|Spares him (D:770)|"The pyre has gone dark. The door at the top stands open, as he asked."|The hearth's coal relights the pyre. Whoever goes up next finds the door open.|
|`throne`|Takes the throne (D:786)|"The fire is yours now. It will keep you, and you will keep it."|The Usurper King speaks with the heir letters, below.|

The spared Regent's last words are the existing line (`story.gd` S:38, D:279):
"Then it ends with me. Go down, child. Leave the door open." This act does not reword it.

Later loops read `flags.a3_hearth`. If `send` was chosen, Maren's eyes are under the helm, and
every Regent line fits (S:17). This is the one variant added to a line that already exists:

```json
{
  "The Hollow Regent": {
    "intro": {"if": [
      ["flag:a3_hearth=send", "The elder came up after all. I can see him under the helm."]],
      "else": ""}
  },
  "The Usurper King": {
    "intro": ["To my heir: the stair is steep, but our cause is just.", "To my heir: I said finish it.", "Someone of your blood will climb to end you."],
    "enrage": "I sat on the throne first! Then the throne sat on me.",
    "death": "To my heir: I did not finish it. Your heir will."}
}
```

The Usurper King is the enemy in the player's look (E:122). Its intro quotes the heir letters
(`story.gd:21-26`) and the existing line in D:789-791; the letters are quoted, not reworded, and
are cut at their first sentence where the bark limit of 60 characters requires it.

## 4. Inscriptions and letters met in Act 3

Only the three endings' lines above are new text. No new inscription is needed in Act 3.

## 5. Check against the code

Places used: `tower`, `elder`, `ranger`, `oswin` (NPC, see NEEDS), new `seam_end`,
`holding_tenders`, `holding_quenchers`, `holding_struck`. Foes: `Hollow Regent` (tier 5,
`enemy_def.gd:157`), `Usurper King` (E:122). Relics 1 to 5 (`story.gd:30-34`). Items:
`ember_ring` (`items.gd:30`), `banner_stone` (NEW). Materials: `cinder` (`craft.gd:43`). Skills
in rewards: smithing, blade, vitality (`craft.gd:5-19`).

## NEEDS

- Place `seam_end` in a second dungeon cut into the ember seam (bible section 4.3, proposed).
- Places `holding_tenders`, `holding_quenchers`, `holding_struck` in the Ashlands, and the clans
  feature (bible section 7). Each holding spot must count as a reach.
- Item `banner_stone` (`items.gd`), used as a reward and placed by the Ashlands plot in `SIDE_QUESTS.md`.
- Flag `flags.ending` written by the duel (`duel.gd`) with `finish`, `spare` or `throne`.
- Flag `flags.a3_hearth` written by the choice in `a3_hearth`, and `flags.a3_banner` by its choice.
- The Usurper King's barks and the Regent's variant need `Story.BARKS` to accept a variant map
  (`{"if": ...}`), not only lists.
- A `loop` condition in the later-loop lines (`loop>=1`).
- NPC `oswin` (Old Ruins) and NPC `magpye`, `corbie`, `chandler`, `nan` as listed in `ACT2.md`.

## Counts

|id|Dialogue lines|Longest line (characters)|
|---|---|---|
|`a3_seam`|9|103|
|`a3_banner`|13|118|
|`a3_court`|15|113|
|`a3_hearth`|9|116|
|Endings (section 3)|3 endings and 1 later-loop line|92|
