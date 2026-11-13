# Ashgrave writing style sheet

For whoever writes Acts 2 and 3 and the side quests. Read `docs/STORY_BIBLE.md` sections 1 to 4
and all of `docs/story/ACT1.md` first, then write in the schema of bible section 9.

## Rules

1. **Never contradict or reword a line already in the game** (bible section 1). New facts come from the bible; anything else must be small, local and listed when you hand in.
2. **One beat a box.** Two or three short sentences; the last one turns the first.
3. **People say half.** They talk about work, food and weather. Feeling sits in an object: a folded cloak, a changed strap, a dressed stone.
4. **Every speaker wants something** (bible section 4), and the wants conflict. Maren counts and defers. Brannoc does not ask. Wren tests. Tam remembers. Isolde refuses.
5. **Guardians are tired, not cruel.** They speak to the whole bloodline as one person.
6. **Dead heirs go by number**, never "your father". A new heir makes kinship wrong.
7. **No game words in speech**: level, XP, quest, floor, boss, spawn. They are fine in `text` and `track`.
8. **No contractions, no dashes, plain quotes.** "..." only for the dead and the dying. An exclamation mark only in a guardian's `enrage`.
9. **Do not answer a question the bible saves for a later act**, and never name a chosen one, a prophecy or a dark lord.
10. **Quest shape:** hook in the offer's first box; three or four steps; a payoff that changes how one character, or the central question, looks.
11. **Use only ids that exist** in `land.gd`, `craft.gd`, `items.gd` and `quests.gd`; list anything you need added, with its file.
12. **Write a variant** (`bloodline>=2`, `loop>=1`) for any line that counts heirs, says "first" or shows surprise.

|Text|Limit|Text|Limit|
|---|---|---|---|
|Talk line|160 characters|Journal `text`|115 characters|
|Talk line before choices|125 characters|Tracker `track`|34 characters|
|Choice label, at most 3|36 characters|Quest name|16 characters|
|Caption (`say` on reach, kill, find, win)|125 characters|Boxes in one conversation|4 (act finale 6)|
|Duel bark|60 characters, one line|Letters and inscriptions|125 characters|

## Ten lines to imitate

1. "Here the oath was first spoken. Here it is still owed." (inscription, `story.gd:5`)
2. "To my heir: do not swear the oath as I did. Read it first." (letter, `story.gd:25`)
3. "He will be glad of you. That is the horror of it." (guardian, `story.gd:13`)
4. "The tower was quieter when I was young. Or I was." (villager, `quests.gd:67`)
5. "I fit them to the next of you, and I do not ask." (Brannoc)
6. "I have a shelf of folded cloaks and nothing to put in them." (Wren)
7. "I do not say it is wrong. I say look at the hands." (Tam)
8. "Do not go. The oath cannot kill you unless you climb." (Isolde)
9. "The tower sends down arms. It does not send down names." (Maren)
10. "Purse first. Then we can both go home." (bandit)

## Ten bad lines, and the fix

|Bad|Why|Fix|
|---|---|---|
|"You are the chosen one who will end the curse!"|Chosen one; exclamation|"You are the thirty-first. I said as much to the thirtieth."|
|"The ancient evil in the tower hungers for your soul."|Stock fantasy; the fire is not evil|"The fire wants company. That is worse."|
|"I can't believe you're back!"|Contractions; gush|"You came back down. No one has."|
|"Kill level 38 Ruin Keepers for 500 XP."|Game words in speech|"The Keepers still guard their wording. Put two down."|
|"In the Second Age, King Aldremar the Bright of Valdoria..."|Lore dump; grand invented names|"There was a king. Greywood was his."|
|"Your father died bravely on the tower."|Kinship; vague|"The thirtieth went up in spring. His arms came down by summer."|
|"It breaks my heart, all those dead heirs."|Names the feeling|"Another cloak for the shelf. I folded it myself."|
|"Prepare to die, fool! None shall pass!"|Cruel, loud, generic|"I have a place dug for you. It has waited."|
|"Maren has been elder longer than anyone can remember, and some of us wonder whether that is natural, if you take my meaning."|Too long; explains itself|"Maren was old when I was a boy. Same cloak. Same hands."|
|"Oswin wrote the oath to trick your family."|Settles a mystery early; flat|"Ask Oswin who chose the words. He will say who. Not why."|

## Before you hand in

Count every string against the table. Check each fact against bible section 1. If a box
could come from any fantasy game, cut it and write what this person would say about their own day.
