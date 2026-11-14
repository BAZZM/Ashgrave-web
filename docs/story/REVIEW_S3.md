# S3 review: ACT2.md, ACT3.md, SIDE_QUESTS.md

Reviewed in `/home/claude/wt/s3-story-fill` (branch `lane/s3-story-fill`), against `docs/STORY_BIBLE.md`,
`docs/story/STYLE_SHEET.md`, `docs/story/ACT1.md` and the code in `game/scripts/`. Nothing in the repo was
changed. Nothing was run except a script that measured every draft string against the style-sheet limits.

## 0. Verdicts

|Document|Verdict|Why, in one line|
|---|---|---|
|`ACT2.md`|**Rewrite**|Spine (tiers 2, 3, 4) is usable; the finale contradicts canon, half the act is unbuildable, the middle is incoherent.|
|`ACT3.md`|**Reject**|Bible sentences pasted into mouths; the two ending menus contradict each other; nothing shows a consequence. Redraft after the owner rules on section 8 below.|
|`SIDE_QUESTS.md`|**Rewrite**|Of 14: 3 keep with line edits, 6 need a new premise, 2 merge away, 3 defer.|

Top problems:

1. **The Act 2 finale (`a2_letter`) breaks canon and reveals nothing.** Maren talks as if he had received the letter and knew its words. The bible says no rook flew and Maren heard nothing. "Maren is Brother" was already given at the end of Act 1 (`a1_stair` finish). The one new fact, that Maren reads "Send no one after me" for the first time after sending thirty, is thrown away.
2. **Characters say things they cannot know, often about themselves in the third person.** Brannoc explains the inside of the Foundry, Maren describes the top of a tower he has never entered, Wren knows the Chandler's stock, Maren calls himself "Maren". Cause: the bible's tables were pasted in as dialogue, and `finish` lines are spoken by whoever owns the last step (`quests.gd:255-272`), which the drafts ignore.
3. **No choice has a consequence and the ending does not resolve.** Every flag the drafts write (`a2_key`, `a2_letter`, `rune`, `a3_banner`) is never read by a later quest. Wren is promised her flood "tonight" in Act 2 and it never happens. Act 3 offers the duel ending and the hearth choice as two independent menus, so the player can take the throne and then send Maren up to it, or douse a hearth while the pyre still burns.

Also: 9 of 24 quests need systems that do not exist, and three read keys that are not there and should fail when played (`a2_key` and `side_pye` use `find` without a `relic`; `a3_hearth` has no `offer` and is not `auto`). Read from the code, not run.

Story judgement, briefly:

- **Does Act 2 escalate?** No. Act 1 ends on "bring him down or keep him company". Act 2 answers with three errands for unbuilt systems (thieving, casino, runecraft) and a finale that repeats Act 1. Only the tower tiers escalate. The Duelist, the strongest thing on tier 2 (her shipped death line asks the player to put a question to "him"), is reduced to one sentence of exposition from Oswin. Isolde and Tam are absent from the act; Maren is absent until the last box.
- **Weakest stretch of Act 2:** `a2_key` into `a2_roost`. Who steals the key, who holds a second key, lock versus key, and who is speaking are all confused; the roost choice is a menu that neither takes gold nor plays a game.
- **Does Act 3 pay off the premise?** No. The central question is who decides, the warm or the burned. The warm (the vale) never speaks in Act 3, the cost of dousing is never shown, and the question is put as a three-button menu after the climax.
- **Weakest stretch of Act 3:** `a3_banner`, a clan tutorial placed between the Act 2 finale and the last climb. `a3_seam` only confirms what relic 4 and relic 5 already say.
- **Turns earned?** One: Oswin's reading of the oath, and only if it hinges on the shipped words "one of us". The Duelist reveal, Maren's confession in `side_lie` and the Ansel naming are announced, not earned.
- **Does the ending land?** No. The last beat is a one-line reply, Maren stays standing by the hearth whatever was chosen, and no other character has a line after it.

## 1. Engine facts the drafts ignored (writers: check against these)

- `find` only means "relic N held"; `win` only means "tier N beaten" (`quests.gd:223-227`). There is no `find` for an item or a place. Unknown step fields (`trace`, `plant`, `raise`, `item`) are ignored.
- `reach` fires only for places of type `spot` and for the tower gate (`overworld_interact.gd:81-85`), once on arrival. Two `reach` steps at the same place in a row cannot both complete without walking away and back. NPCs, the hearth and stations are not reach targets.
- `kill` counts land foes only (`run.gd:397`). Tower guardians, tower lessers, elites and player duels are not counted.
- `finish` and a `choose` step's `reply` are spoken in the box of the last step's NPC. If the last step is `reach`, `kill`, `find` or `win`, `finish` is shown as captions with no speaker.
- A choice cannot cost gold or give an item (only two hard-coded cases for `poach`, `quests.gd:375-382`). Choices cannot be conditional. Rewards cannot differ by choice. A consequence today means: a later quest with `requires: ["flag:id=value"]` or `"!flag:id=value"`, or an `if` variant on a line.
- A flag condition needs its value: `flag:rune=1`, not `flag:rune` (`quests.gd:110-112`).
- The Trader (`store`) and Taskmaster (`task`) do not go through the quest engine (`overworld_interact.gd:148-151`); they cannot give quests or take a step until wired the way Brannoc is (`overworld_interact.gd:118-124`, about six lines each). Villagers can: any of the three walkers answers as `villager`.
- The duel does not store which ending was taken. Taking the throne sets `flags.throne = true` (readable now as `flag:throne=true`); sparing sets nothing in the save (`duel.gd:770-791`). `flags.ending` does not exist.
- `Run.add_item` does nothing if the item is already owned (`run.gd:143-146`), yet the caption still says "Received". `ward`, `pyre_greatsword` and `ember_ring` are all sold or forgeable, so every item reward in the drafts can be a no-op. Pair each with gold.
- `Story.lore_entry`, `Story.bark` and idle lines read `quest_data_act1.gd` only, and `Quests._build` merges two files. New acts either paste into that file (no code) or add a data file and about ten lines of merging.
- There is already a trader standing on every tier of the tower (`tiers.gd:67`, `world.gd:432`, `world.gd:814`). He has no name and opens the shop. He is the obvious Chandler; making him talk is a small hook, not a new system.
- A casino engine exists on lane `p5-casino-core` only (cards, roulette, hold'em logic). Here there is no casino place, no Corbie and no stake hook.
- Ember ore needs Mining 40 and the Trader only buys. Ruin Keepers are level 38, Seers 40, Pyre Guards 46. The drafts' level bands ("16 to 30") are wrong for any step that uses them.

## 2. Edits that apply to all three files

1. **Speaker pass.** For every quest, name the NPC of the last step and rewrite `finish` in that voice, first person. Move narration to a `say` on a `reach`, `kill`, `find` or `win` step.
2. **Knowledge pass.** Brannoc has never been in the tower and does not ask. Maren has never passed the gate. Wren is not of the blood. Only the player, the guardians and the tower trader know the inside.
3. **Bloodline variants (rule 12).** Almost none are written. By Act 2 most players have died on the stair at least once. Any line that says "the thirtieth's sallet", "thirty", "first" or shows surprise needs a `bloodline>=2` variant, and Act 3 lines need `loop>=1`.
4. **`order` values.** Act 3 uses 10 to 40 and the side quests 10 to 140, colliding with Act 1 (10 to 100) and putting side offers ahead of main ones from the same giver. Use Act 2: 200 to 290, Act 3: 300 to 390, side quests: 500 and up.
5. **Offer length.** The last offer box shares the screen with accept and decline, so its limit is 125. Over: `a2_mark` (145), `a2_rune` (130), `side_bread` (129), `side_plot` (129). All other strings are inside their limits.
6. **Tics to thin.** Brannoc's "I do not ask" is stamped on five lines; allow it once in all of Act 2. The dying or reaching hand closes four kill captions (`side_thralls`, `side_isolde`, `side_keepers`, after `a1_diggers`); keep one. "Small and neat" is the brothers' handwriting; do not use it for a maker's mark.
7. **"Check against the code" sections are not checks.** `ACT2.md:320-324` lists places and foes the act never uses; line numbers such as `land.gd:88-91`, `items.gd:40`, `enemy_def.gd:157` are wrong. Redo them from the files, or delete them.
8. **`ACT2.md:315-316`** leaves an idle-line change "for the engineer". The writer writes it.

## 3. ACT2.md, quest by quest

### `a2_flood` Drowned Crown: KEEP, edit (A)

- L36: `requires` to `["quest:a1_stair"]`. `a1_diggers` is optional in Act 1, so gating on it locks some players out of Act 2 and lets others start it before the Act 1 finale. Add an `if quest:a1_diggers` variant to offer box 1.
- L38: cut. It repeats Wren's own `a1_diggers` offer almost word for word. New hook: the player is the first heir to come down, and Wren wants to know what her order's water kept.
- L39, L41: the Cisterns are up the stair. Remove "go down"; accept becomes "I will go up."
- L43-50: swap the steps to `find` relic 2, then `win` tier 2. The relic chamber comes before the guardian, and `a1_stair` uses that order.
- L50: the caption repeats the relic's own text. Replace with: "The inside of the band is worn bright. It was worn for years, and never made larger."
- L52: "at the hearth" to "in Hearthvale" (Wren stands at the alchemy table).
- L55-57: three boxes to two. Remove "the only key" (the next quest says there are two). Wren must say how she knows of the Chandler: the thirtieth wrote of a Sworn who sells on the stair.
- L61: cut. "Then" follows from nothing and the line repeats `a1_diggers`. Keep L62 as the last box; it is the best line in the act.
- L64: add `"gold": 80`; `ward` may already be owned.
- L65: remove the clause that the pyre was lit under him; nothing supports it. Say the crown was made for a child and worn for years, and that Wren wants the sluice key.
- Final conversation after edits: 2 + 2 boxes.

### NEW `a2_ending` No Ending (A): add

Starts itself when tier 2 is beaten and `a1_stair` is done. One `choose` step at Maren. The Duelist's shipped death line tells the heir to ask "him" why the oath has no ending; the player carries the question down, as `a1_stair` did with the Warden's line. Maren answers half: the first he sent was his own child, the best with a sword, and she has taught every heir since; for the wording he sends the player to "a Keeper who still talks" (hook for `a2_rune`). Uses bible decision 4; if the owner rejects it, Maren refuses the second half.

### `a2_key` Sluice Key: REWRITE, hold for part two (C as written; B plus a small hook after rewrite)

Problems to remove: Mag Pye offers to fetch the key and then the player steals it; the player is never told to seek her; "lock" and "key" swap; the `choose` box is Wren asking whether to give the key to Wren; the `finish` is Mag's voice in Wren's box; the Maren option never reaches Maren; Wren promises the flood that night and nothing follows; the journal says the Chandler sells to Wren, the offer says he will not. L85 raises a script error.

New premise: the Chandler is the trader already on every stair. He has the sluice key on his table and will not name a price, because Maren has paid him for thirty heirs not to sell it. The player gets it from him (bought dear now; lifted with Mag Pye's lesson once Thieving exists) and decides at Wren's table whether she has it. The choice must open one of two follow-up quests by flag: Wren's (she readies the water and says what it needs) or Maren's (he shows what he has paid for). Wren must not flood anything in Act 2.

Blocked on the owner: how a trader inside the tower deals with Maren, who has never passed the gate (section 8, item 1).

### `a2_mark` The Maker's Mark: REWRITE lines, keep steps (A)

New premise: Brannoc has found the same small mark under the grip of every blade that has come down, and he did not cut it. He asks the heir to find where it is struck. When he knows, he asks for ore to make one blade of his own with no mark on it (his bible want: one blade that does not come back).

- L120: cut. Brannoc cannot describe the Foundry. Open on the mark under the grip.
- L121: 145 characters and names the Gravemaul, which he cannot know. Ask only: find where the mark is struck, and see what is done with the blades that do not come down.
- L128: drop the first sentence (it is the relic text). Say the mark on the tang is the mark under the player's own grip.
- L132: keep.
- L134: add "Mining 40 is needed" (as `mire` states its Foraging gate). Consider 2 cinder shards instead; see section 8, item 6.
- L138: cut. It has Brannoc tending the Gravemaul.
- L139: cut. The Unfinished Blade did not come down with the thirtieth's arms; the player found it in the Foundry. New finish: he has fitted the tower's work for years and called it his; this blade is his alone. One line on ember ore being cold since the Burning until a forge wakes it (plants Act 3).
- L141: keep `pyre_greatsword` (it is an ember blade, so the ore makes sense) but present it as Brannoc's unmarked blade, not as the relic finished. Raise gold to 150 for players who own it.
- L142: journal to match.

### `a2_roost` Roost Book: REWRITE, hold for part two (C)

- The choice at L163-171 is not a choice: "pay" takes no gold, "win" plays no game, and the reward then adds 40 gold.
- L158: "keepers" collides with the Keepers faction. Say her people kept the rooks.
- L170: Corbie never loses (bible). Cut the admission that the wheel cost her.
- New premise, so that it works before or after the finale: Corbie's book shows that Maren sent a rook up before every heir, thirty in all, and each came back with his letter still tied. Her price is news, not gold: the player pays with one true thing (which one is the choice), and villagers repeat it afterwards through idle-line variants. With the casino, add a real stake as the second way to pay.
- The lore entry (L276) dates the letter by an invented phrase. Cut it or have the owner approve it.

### `a2_rune` The Oath Rune: REWRITE and MERGE with `side_keepers` (C as written; B after rewrite)

New premise for part one, name "The Wording": Oswin cannot read the altar aloud while two Keepers stand over it. The player puts two Ruin Keepers down (`kill`, 2), reads the altar again (`reach altar`), returns. Oswin's point rests on the shipped words: one of us may tend, so one of us may stop.

- L205, L211, L280: remove "the eldest". No one in the game has claimed only the eldest may end it.
- L210: "forty years" is invented and unneeded.
- L215: cut. The Duelist reveal moves to `a2_ending`.
- L218: keep `flags.rune`; later lines must test `flag:rune=1`.
- The second ring, the tracing and Runecraft become a part-two side quest that absorbs `side_stones`.

### `a2_letter` Rook's Letter: REWRITE (A)

New premise: Maren has never seen the letter. The player carries it down and chooses to read it to him, hand it over, or keep it. Maren hears "Send no one after me" for the first time, after thirty.

- L231: add `"quest:a1_stair"`. Otherwise an old save holding relic 4 gets Maren talking of his brother before Act 1 has revealed him.
- Add a first step `find` relic 4 (passes at once) with the caption: "It is still tied for a rook's leg. The roost above it is empty, and has been for an age." This carries "it never flew" without Corbie.
- L236: the Keeper is "she" in the bible, and the caption describes her fighting after she is dead. Replace with what lies behind her gate: "Behind her gate, a row of graves, each the length of a sword. The last one is open." (This also settles section 8, item 4, if the owner agrees.)
- L240: Maren cannot know the letter never flew. He sees that the heir carries paper and asks for it.
- L241: three choices: "Read it to him." / "Hand it over." / "Keep it."
- L243-244: each reply is Maren meeting the words, or not being given them. On `keep` he must not know the contents.
- L248: cut the `keep` variant; it has Maren quote a letter he was refused.
- L250: cut. See Voice, example 1.
- New finish, up to four boxes: he sent a rook before each heir and took the silence for a brother too busy to answer; he sent help thirty times; the name (decision 6); then the turn back to `a1_stair`: the question he would not answer was answered before the line had a name, and the answer did not reach him. Add a variant on `quest:a2_rune`.
- L252: an act finale needs more than Vitality XP. Add gold 200 and the letter as a lore entry.
- The flag must be read afterwards: idle variants for Maren and Wren, and a `requires` on at least one Act 3 quest.

### Barks (`ACT2.md:289-309`): KEEP, three edits (A, data)

- Pyre Guard: one display name serves the Ashlands foe and the tier 5 lesser, so the Court line plays in the Ashlands and the ash-line line plays in the Court. Write lines that fit both, or hold them for Act 3.
- Forge Hand, first intro: the rhyme reads as a joke. Replace.
- Rook Sentry: keep all three; they are the best new lines in the file.

## 4. ACT3.md

Do not build from this draft. Instructions for the redraft:

- **Decide first (owner):** who the player is after taking the throne; whether Maren can leave the hearth; whether the hearth choice exists for every duel ending (section 8, items 2 and 3).
- **`a3_court`:** end the quest at the duel. L122: add a variant for a player who has already beaten the Regent. L123: "tier" to "stair". L130: cut the first sentence (it is the cast table); the helm line can stay. L136-140: Maren's brother has just died, been freed or been replaced, and Maren says nothing about him; the `finish` line also says the stair is quiet when the bible says the fire still burns. L145-148: cut; they are narration in Maren's mouth and repeat the shipped duel captions (`duel.gd:780`, `duel.gd:791`). L149 and L151: six cinder shards are a common drop and the last of nothing; the bible meant the `cinders` currency, which needs a reward key. L152: no "ending" in a journal line.
- **`a3_hearth`:** replace with one quest per duel ending, each `auto`, each requiring its ending flag, each with its own choice. After a sparing: the pyre is dark and the hearth coal is the last of it; bank it (the coal relights the pyre), send Maren up with it, or douse it with Wren (winter; both brothers die). After a finish: the armour stands again; the choice is what to tell Maren. After the throne: no hearth choice; Maren counts a thirty-second. L172-173, L178: Maren speaks of "Maren" and "the brothers"; rewrite in first person. L183 `douse`: the sluice is in the tower, the hearth is in the village; do not mix them. L183 `send`: keep, it is the one strong line. L165-167: add `auto` or an offer or Maren's talk breaks.
- **Give the warm a voice before the climb.** Add a quest in which Nan (her stakes), Tam, Brannoc and a villager each say what the warmth is worth to them. This is where the central question is asked.
- **`a3_seam`:** hold until the second dungeon exists. L36: see Voice, example 3. L44, L49, L58: the seam did burn, for a year (bible section 2); say it has been cold since, not that it never burned. "Second seam" in the summary and journal is wrong; there is one seam. L55: the ring is forged from three ember ore at Smithing 35 and is not the last ember in the vale.
- **`a3_banner`:** take out of the main line; it becomes the Ashlands side quest that introduces clans. L81-89: speeches cannot be captions; give each holding a speaker or have Isolde report them. L85: the Quenchers' case is nonsense (with the fire out the vale needs fire more, not less); their case is that winter can be lived through and the stair cannot. L98: the Struck cannot die outside the tower (`a1_struck`); fix to say they will be angry and cannot even die of it. Make the lean matter: it should be read by the hearth quests.
- **Barks, L218-228:** delete the Regent variant. It blanks a shipped line (rule 1), puts narration in his mouth, and misreads the bible, whose point is that the existing Regent lines already fit Maren under the helm. Usurper King: keep the idea of quoting the heir letters; cut the third intro (it is the throne caption turned the wrong way round); rewrite the enrage (a joke, and "first" is false); add an `again` line.
- **Write the after-state.** The bible promises "new lines everywhere". The draft has none. Each of Maren, Wren, Brannoc, Tam, Isolde and the villagers needs idle variants per ending.
- **Engine work the redraft will need:** store the duel ending in the save; a way to hide or replace an NPC by flag if Maren goes up; a `cinders` reward key.

## 5. SIDE_QUESTS.md, quest by quest

### `side_bread` Hearth Bread: REWRITE (A)

Premise: a villager's mother left bread out for heirs going north and none came back to eat it; she asks this heir to sit and eat for once, and bring the fish. Maren's line that he did not ask them to and did not ask them to stop (L55) stays. L44: cut the first sentence; it contradicts the box before it. L56, L60: cut; they name the feeling. L55 first sentence: the village did not send the heirs, Maren did; fix the journal too. Add `requires: ["quest:a1_thirty_first"]`.

### `side_trader` Trader's Tally: REWRITE (A after rewrite; as written it needs the Trader wired to the quest engine)

The draft has the Trader keep and volunteer his own ledger. The shipped `poach` quest says a poacher carried the tally and the Trader's name is on it. The "keep" choice is undone by the next step (tell Isolde anyway). Slaying XP for a talk quest is wrong.

New premise: giver Isolde, `requires: ["quest:poach", "flag:poach=tally"]`. She has the tally and the Trader's name is on it. The player chooses with her: post it on the hearthstone, or hold it over him. Villager idle lines change by flag. A player who burned the tally never gets this quest; that is the consequence of the old choice. The Trader never needs to speak.

### `side_thralls` Nan's Rows: KEEP, edit (B: Nan)

L134: Nan gives away both outcomes before the choice, and "the light stays cold" means nothing; she should ask only what to do with the bone. L146: the journal states both outcomes whichever was chosen; make it a variant. L127: cut the reaching hand. Make the flag matter in Nan's second quest.

### `side_marigold` Hearthward Rows: REWRITE (C as written; B after rewrite)

Remove Farming. Premise: Nan asks for three marigold and plants them at her last stake; she has a stake for every year, and each year marigold stops one row nearer the hearth and ashbloom starts. L172: remove "next spring"; the game has no seasons. Say the line runs toward the ash line, not "only hearthward" (section 8, item 8).

### `side_isolde` Isolde's Cell: REWRITE (A)

The offer gives away the payoff, Isolde orders her cousins killed for no reason, the watchtower is visited for the third time, and a Struck camp is invented that is not in the world.

New premise: Isolde has stopped looking at the faces of the bandits on her road. She asks the heir to put three down and then ask in Hearthvale who woke on the hearthstone that morning (`talk` to `villager`). Three strangers did, sore, and asked the way to Greywood. They are of the blood. Rename; there is no cell. Needs the owner's ruling in section 8, item 5.

### `side_pye` Mag's Lesson: DEFER (C: Thieving, Mag Pye, purse)

L237 raises a script error. L235: see Voice. L245-252: the last step is at a ruin where Isolde does not stand, and the `finish` is Mag's voice shown as captions. Rewrite when Thieving exists.

### `side_cloaks` Wren's Cloaks: REWRITE (A)

It repeats `mire` (three bogroot, then the shrine), reuses Wren's signature Act 1 line as its opening, and its payoff contradicts the shipped shrine (one green light that went dark and was relit; "a waymark" in `a1_diggers`). L282 and L286 disagree on whether the newest flame is the player's.

New premise: Wren asks for herbs to keep moth from the wool, then for the thirtieth's cloak to be laid in the water at the shrine, the nearest thing to a grave the fen can give. Back at the shelf there is one cloak more than there are dead, in new wool, cut to the player's measure. It mirrors Maren's dressed space on the altar. Drop the flames. L271: "a heir" to "an heir".

### `side_hexer` A Hexer's Word: REWRITE (A)

What the hexer says is never written, so "tell her all of it" tells nothing. Wren knows of the meeting before she is told. L318 has Wren refuse to forgive a killing she herself ordered in `mire`. L322-323 are narration about Wren in Wren's box. The journal reverses who sold the craft.

New premise: the hexer's shipped death line asks what the cisterns cost. At the shrine a hexer says it alive, in two captions. The choice at Wren is to ask her or say nothing. If asked, she says half: a flood wants a hand on the sluice from inside, the Sisters would not write that down, and the hexers left over it. This is new canon for the owner (section 9, P3). Hexers are people: "she", not "it".

### `side_mine` The Mine Road: KEEP, edit (A)

Merge steps 2 and 3 (both at Brannoc). Add `requires: ["quest:a1_bone"]`; brutes are level 24 and the quest opens after a starter quest. L353: add "Mining 15 is needed". L351: tighten; the stamp is the one under the player's own grip. L358, L361: Brannoc must not lecture on the Foundry or on who built the tower; he recognises the stamp, and that is the payoff. L362: second sentence is garbled; cut. Play before `a2_mark`, which pays off the stamp.

### `side_stones` Second Hum: CUT, merge

Same place, same trace and same payoff as `a2_rune`, and it disagrees with it on who cut the rune. Fold "the oath, repeating" into the part-two second-ring quest. The ferry (L379) does not exist.

### `side_lie` Who Wrote a Lie: KEEP, edit (B as written; A after edit)

- Giver to Old Tam. It pays off his shipped line about the hands and removes the need for Oswin. `requires: ["quest:a1_stair"]`.
- Replace the Seer kill (level 40, unrelated) with `reach altar`: the scratch fits the edge of a cinder shard.
- L419: say why a shard: the scratch was cut with one.
- L432: Maren must not simply confess. He takes the shard the way he once held it; the admission comes through the object. Keep "after the tenth" (decision 5) and keep L433 as written.
- L426: "the last word" is two words.

### `side_keepers` Keepers' Ward: MERGE into `a2_rune`

Oswin, a Keeper, asks for two Keepers killed to learn what he already knows. Keep the mid-word kill caption (without the hand) and L466. L462 ends on a large new rule (an oath not said exactly is forgotten by the fire); cut unless the owner wants it.

### `side_cousin` A Cousin's Duel: DEFER

Needs a hook from online duels into the quest engine and the Taskmaster wired in; it cannot be finished without another live player; the bible says "fight", the draft says "win". The Taskmaster stands in Hearthvale, not at the ash line. L500 invents stakes (holdings, road tolls) that do not exist; only gold is lost. L485: the cousin watching from the stair means nothing; cut.

### `side_plot` Dead House Plot: DEFER (C: clans, a new place, banner stone)

Two `reach` steps at one place; Mining 40 and Woodcutting 40 are not stated; L534 last sentence is meaningless; `finish` is the Taskmaster's voice shown as captions.

## 6. Voice

General: the drafts obey the mechanical rules (no contractions, no dashes, no exclamation marks outside an enrage, lengths mostly kept). They fail rules 2, 3 and 4. Boxes explain, name the theme and end on a summary; Act 1 boxes end on a turn. Speakers are not distinct: Wren, Oswin, Corbie and Mag Pye all explain in the same even sentences. Mag Pye is meant to be quick and has the longest lines in `a2_key`. Corbie is meant to be warm and reads as a clerk. Isolde in `a3_banner` and Oswin's two closing lines (`a3_seam` L50, `side_keepers` L466) are the only places a new speaker sounds like one person. Modern idiom is rare; one decline label has it (`SIDE_QUESTS.md:235`; use "Not today.").

Three examples:

1. `ACT2.md:250`, Maren: "I sent them because the first letter said no one"
   Wrong: no letter reached him (bible section 2), and it is not a reason. Should read: "I sent him a rook before each of you. I took his silence for a busy man, and sent help."
2. `ACT3.md:178`, Maren: "The coal is yours to decide. Maren will not decide it for you."
   Wrong: he names himself; it is a note to the writer, not speech. Should read: "Thirty times I let the stair decide. This once you say it, and I will do it."
3. `ACT3.md:36`, Oswin: "There is a second dungeon cut into the ember seam."
   Wrong: game word, and any fantasy game could say it. Should read: "The king's diggings run on under the Scar. My order was told they still burn."

## 7. Buildability table

A: runs today as data. A+: every id exists, but a few lines of wiring are needed (no new system). B: needs a new NPC or item of an existing kind. C: needs a new system, skill or place.

|Quest|As written|Needs|After the edits above|
|---|---|---|---|
|`a2_flood`|A|nothing|A|
|`a2_key`|C|Thieving, Mag Pye, Chandler, item, `find` for an item (errors today)|B plus the tower-trader talk hook; part two|
|`a2_mark`|A|nothing|A|
|`a2_roost`|C|casino place and stake hook, Corbie, gold cost on a choice|C; part two|
|`a2_rune`|C|Runecraft, tracing, second ring, Oswin|B (Oswin), merged with `side_keepers`|
|`a2_letter`|A|nothing|A|
|`a2_ending` (new)|n/a|nothing|A|
|`a3_seam`|C|second dungeon, Oswin|C|
|`a3_banner`|C|clans, three places, banner stone|C|
|`a3_court`|A+|duel must store the ending or all three variants fall to `else`|redraft|
|`a3_hearth`|A|one-key data fix (`auto`); showing any outcome is C|redraft|
|`side_bread`|A|nothing|A|
|`side_trader`|A+|Trader wired to the quest engine|A (giver Isolde)|
|`side_thralls`|B|Nan|B|
|`side_marigold`|C|Farming, planting, a new place|B (Nan, bring marigold)|
|`side_isolde`|A|nothing|A|
|`side_pye`|C|Thieving, Mag Pye, purse (errors today)|C|
|`side_cloaks`|A|nothing|A|
|`side_hexer`|A|nothing|A|
|`side_mine`|A|nothing|A|
|`side_stones`|C|Runecraft, second ring|cut, merged|
|`side_lie`|B|Oswin|A (giver Tam)|
|`side_keepers`|B|Oswin|merged into `a2_rune`|
|`side_cousin`|A+|online duel result into the quest engine, Taskmaster wired in, a live opponent|defer|
|`side_plot`|C|clans, a new place, banner stone|C|

**As written, 24 quests: A 9, A+ 3, B 3, C 9.** Barks for both acts are data (A), except the Regent variant, which is cut.

## 8. Canon: things in the bible or Act 1 the owner should rule on

1. **Bible section 6, `a2_key`: "He sells to both."** The Chandler is inside the tower. Maren has never passed the gate (`a1_hand`), and no heir came back down before this one (`a1_stair`). Nothing says how Maren or Wren could buy from him. Suggest: he trades through the gate at night.
2. **After the throne, who is the player?** Bible section 8 says "their heir climbs next", but the game does not start a new bloodline on taking the throne, and the same character walks back to Maren. Every post-throne line depends on this.
3. **Maren's shipped idle line for `loop>=1`** (`ACT1.md` section 5) says the fire still burns. It plays after a sparing too, where the shipped caption says the pyre went dark. It needs variants by ending, which needs the ending stored.
4. **Bible section 2: an heir who dies on the stair burns.** The Keeper's shipped line says she buried every heir who reached her. Suggest: she buries the sword for a night (proposed caption in `a2_letter`).
5. **Bible section 7: "Her bandits are Struck cousins."** With "the blood cannot die outside the tower", every bandit the player puts down wakes on the hearthstone in Hearthvale. Act 1's bandit death bark implies bandits die and Isolde does not. Either embrace it (the rewritten `side_isolde` does) or make only some of them Struck.
6. **"The seam is dead" against the ember veins.** Players mine ember ore across the Ashlands and the Ruins and forge ember tools, and the bible says cousins fight over ember. Act 3's cold-seam reveal needs one line reconciling them (suggested in `a2_mark`: cold since the Burning until a forge wakes it).
7. **Bible section 7: "The shrine burns one flame per heir."** The shipped shrine is one green light that went dark and was relit, and `a1_diggers` calls it a waymark. Drop the flames.
8. **Bible section 7: "Marigold grows only hearthward."** On the map marigold grows everywhere except Mirefen, the Ashlands and the Ruins. What is true is that it gives way to ashbloom at the ash line.
9. **Act 1 reward bug.** `a1_stair` gives Warden's Brand as the act's prize. It is forgeable at Smithing 15, and `add_item` does nothing if it is owned, so some players receive nothing while the caption says they did. The Oath Ring ("the first heir's") is likewise forgeable at Smithing 28.
10. Minor: `a1_struck`'s last conversation is five boxes against the sheet's four. Two shipped tower lines use kinship ("Your father's name", "Your grandmother") against rule 6; they cannot be reworded, so the rule should say it covers new text. Act 1 avoids a pronoun for Maren; the drafts use "he" throughout, which the bible supports only after `a1_stair`.

## 9. Invented facts in the drafts (not in the bible or the game)

Marked X where the invention also contradicts canon.

**Act 2**
1. A sluice gate between the Cisterns and the pyre, locked from the far side.
2. Wren knows the Chandler and that he holds "the only key"; he refuses her.
3. The Chandler sold a second sluice key to Maren. (X with "the only key"; see section 8, item 1.)
4. The Chandler wears the key on a cord and turns his back to count coin.
5. Wren will flood the pyre the night she gets the key. (X: never happens.)
6. The family's maker's mark is on the heir's sallet.
7. Brannoc was asked by someone unknown to keep the Gravemaul's edges. (X)
8. The Unfinished Blade came down the stair with the thirtieth's arms. (X: it is found in the Foundry.)
9. Every plate of the Gravemaul still carries a hilt.
10. Corbie's price is 500 gold or a stake at a wheel.
11. The roost book's entry and its dating phrase.
12. The Keepers wrote the oath twice, on the altar and at the second ring; the rune reads the same both ways.
13. Oswin has kept quiet for forty years.
14. A belief that only the eldest may release the oath.
15. The Duelist treats the stair as a school.
16. A "first letter" that reached Maren and said to send no one. (X)
17. Maren knows the Rook's Letter never flew, and knows its words unread. (X)
18. The hum at the second ring is the same note, slower.

**Act 3**
19. A "second seam"; a "second dungeon" as an in-world term.
20. The seam never burned. (X: it burned a year.)
21. Oswin's ring is the only ember in the vale not fed to the tower. (X: forgeable; nothing but heirs is fed to the tower.)
22. The three clans' cases as worded; ash in every well; three physical holdings.
23. What a banner stone is: a name, not a claim, set at a holding's edge.
24. Some of the Struck will be dead by spring. (X)
25. Dousing the hearth needs one of the blood to hold a sluice. (X: wrong fire.)
26. The cinders given are the vale's last. (X: they keep dropping.)
27. Maren can be seen under the helm; the Usurper King's new lines.

**Side quests**
28. The Trader keeps his own ledger of the deer trade under his scale. (X: `poach`)
29. The village "sent" the heirs. (X)
30. Burned thrall bone brings thralls back in a season.
31. Nan sets a stake a year; the warmth retreats one row a year.
32. Bandits send their coin to those who refused the oath; a Struck camp can be seen from the watchtower; the watch is Isolde's "by right".
33. The purse as the player's "first debt".
34. Wren's cloaks came from the heirs' chests; the shrine holds thirty flames and one new, built by the Sisters to keep the count. (X: shipped shrine)
35. A hexer seeks the player out peaceably; Wren will not forgive a hexer's death (X: `mire`); the hexers left because the order would not say whose craft it was; the Sisters sold the craft to them (X: reversed).
36. Stone Brutes carry a Foundry stamp like the one on the heirs' arms; they came down in spring; they are workers the Foundry could not use.
37. A ferry once ran; the second-ring rune is the oath's first line "in one hand". (X with `a2_rune`)
38. Ruin Seers recite the oath and stop at the scratch.
39. Maren scratched the stone after the tenth (decision 5) and it was the first time he said it aloud.
40. Two Keepers stand at the altar; Keepers were "built"; if the oath is not said exactly the fire forgets it.
41. A cousin has watched the player from the stair; stakes include holdings and road tolls; the Taskmaster stands at the ash line.
42. A dead house held its plot three generations; a plot cannot be taken while its stone stands.

**Proposed by this review (also need the owner's eye)**
- P1. Maren sent a rook up before each heir and each came back unread (`a2_letter`, `a2_roost`).
- P2. The Keeper of the Grave Gate buries swords, in graves the length of a sword (`a2_letter`).
- P3. A flood needs a hand on the sluice from inside, and that is why the hexers left (`side_hexer`).
- P4. Maren paid the Chandler not to sell the key (`a2_key`).
- P5. Defeated bandits of the blood wake on the hearthstone (`side_isolde`).
- P6. Ember ore has been cold since the Burning until a forge wakes it (`a2_mark`).
- P7. One cloak on Wren's shelf is already cut for the player (`side_cloaks`).

## 10. Build order: "Act 2, part one" (A and B quests only)

Fourteen quests (eleven A, three B), all from the edited versions above. The tower already carries the player through tiers 2 to 4, and relic 4 shows the letter's text on pickup, so the finale has to ship in part one; it cannot wait for the casino.

|#|Quest|Class|Giver|Opens when|Suits|
|---|---|---|---|---|---|
|1|`a2_flood` Drowned Crown|A|Wren|`a1_stair` done|tier 2|
|2|`a2_ending` No Ending|A|starts itself|tier 2 beaten|tier 2|
|3|`side_cloaks`|A|Wren|`a1_diggers` done|land 16 to 20|
|4|`side_hexer`|A|starts itself|`a1_diggers` done|land 20|
|5|`side_isolde` (renamed)|A|Isolde|`a1_struck` done|land 8 to 12|
|6|`side_trader`|A|Isolde|`poach` done with the tally kept|any|
|7|`side_bread`|A|villager|`a1_thirty_first` done|any|
|8|`side_mine` The Mine Road|A|Brannoc|`a1_bone` done|land 24, Mining 15|
|9|`a2_mark` The Maker's Mark|A|Brannoc|`a1_stair` done; plays best after 8|tier 3, Mining 40|
|10|`side_thralls` then `side_marigold`|B|Nan Harrow|`a1_bone` done|land 2 to 10|
|11|`side_lie` Who Wrote a Lie|A|Old Tam|`a1_stair` done|any; needs 1 cinder shard|
|12|`a2_rune` The Wording|B|Keeper Oswin|`a2_ending` done|land 38|
|13|`a2_letter` Rook's Letter|A|starts itself|relic 4 held and `a1_stair` done|tier 4|

(Row 10 is two quests.) Main line: 1, 2, 9, 12, 13. The real choice in part one is the letter in 13 (read, hand over, keep), carried forward by idle variants and by an Act 3 `requires`. The second is `poach` finally mattering in 6.

**New NPCs (two):** Keeper Oswin, in the Old Ruins near the altar; Nan Harrow, in the Meadows. Each needs one `PLACES` row in `land.gd`, one look in `overworld_places.gd` `NPC_LOOKS` (the game errors on an NPC without one), and a display name in `quests.gd` `NPCS`. Without them, part one still holds together as eleven quests, all A: drop rows 10 and 12 and the `quest:a2_rune` variant in 13.

**New items:** none. Rewards use `ward`, `pyre_greatsword`, gold, XP and materials, each item paired with gold.

**New lore entries:** the Rook's Letter as read to Maren; optionally the oath as Oswin reads it. **Barks:** Cistern Lurker, Forge Hand (one line replaced), Rook Sentry, Ruin Seer. **Idle lines:** variants for Maren and Wren on `flag:a2_letter`, villagers on `flag:side_trader`.

**Data wiring, once:** paste into `quest_data_act1.gd`, or add `quest_data_act2.gd` and merge it in `Quests._build`, `Story.lore_entry`, `Story.bark` and the idle lookup; add the main-line ids to `Quests.MAIN`.

**Part two, when their systems land:** `a2_key` (tower trader talks; Thieving optional), `a2_roost` (casino), the second ring (Runecraft), `side_pye` (Thieving), `side_cousin` and `side_plot` (clans, online hook). **Act 3:** redraft after the rulings in section 8.
