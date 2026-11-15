# Questions for the owner

Each has a suggested answer. Nothing below blocks play: the build uses the suggestion.

## Decisions this slice commits to

Part one commits to bible section 10 decisions 1 (Maren is the letter's "Brother"), 2 (the blood cannot die outside the tower), 4 (the Duelist is the first heir), 5 (Maren scratched "A lie.") and 6 (the Regent is Ansel). The owner has not reviewed them. Changing 1 or 4 means rewriting `a2_letter` or `a2_ending`; changing 5 removes `side_lie`; changing 6 is two lines.

## (a) Canon problems

1. The Chandler "sells to both", yet Maren has never passed the gate and no heir came back before this one. Suggest: he trades through the gate at night. (Part two.)
2. After taking the throne, who is the player? Suggest: taking the throne starts a new bloodline (one line in `duel.gd` `take_throne`), so the Usurper is the last heir, the player is the next, and Maren counts one more; this matches bible section 8. Needs the owner: the other option is that the crowned player stays and the Usurper is a stranger.
3. Bandits are "of the blood", but the blood cannot die outside the tower. Suggest: they wake on the hearthstone (`side_isolde` says so).
4. The ember seam is "dead", but ember veins are mined everywhere. Suggest: the ore is cold since the Burning until a forge wakes it (`a2_mark`).
5. The shrine burns "one flame per heir", but the shipped shrine is one light, called a waymark in Act 1. Suggest: drop the flames.
6. Item rewards give nothing when the item is already owned, while the caption says "Received". This hits every item reward (`ward`, `pyre_greatsword`, the Warden's Brand, and the Oath Ring, forgeable at Smithing 28 though Maren calls it the first heir's). Suggest: pay gold in its place when owned.
7. Maren's idle line for `loop>=1` needs one variant per ending, which needs the ending stored. Suggest: store it in `duel.gd` `spare()`. Part one has the throne and not-throne variants only.
8. The bible says an heir who dies on the stair burns; the Keeper's shipped line says she buried them. Part one answers with graves the length of a sword. Suggest: keep.
9. The bible says marigold grows only hearthward; on the map it grows everywhere but Mirefen, the Ashlands and the Ruins. Part one says it stops where ashbloom starts. Suggest: keep.
10. Part one calls Maren "he"; Act 1 never does. The bible's "two brothers" supports it. Suggest: keep.
11. Oswin and Nan stand in the world from the first minute, including Act 1's altar scenes, and say only idle lines until `a1_stair` is done. Suggest: keep.

## (b) Facts my text invents

Suggested answer: keep all, but confirm 1 and 3 one by one, because Act 3 stands on them.

1. A sluice between the Cisterns and the pyre, which needs a hand on it from inside. Whoever turns it stays inside. The Sisters would not write that down, and the hexers left over it. This prices any flood ending at one of the blood.
2. The Duelist was Maren's own child, a daughter (`a2_ending`).
3. Every heir swore the oath at the altar in front of Oswin. The first was Maren's child; he corrected one word of hers and she swore again.
4. Maren's brother is Ansel, the Regent. Maren has not said the name since the first heir went up.
5. Maren sent a rook up before each heir; none came back and none was answered (`a2_letter`).
6. The family's mark is struck under the grip of every blade, and on the Gravemaul's plates and the Stone Brutes.
7. Ember ore is cold until a forge wakes it.
8. Wren keeps a cloak cut to the player's measure (`side_cloaks`).
9. Maren scratched "A lie." under the oath himself with a cinder shard, after the tenth heir (`side_lie`).
10. Bandits wake on the hearthstone in Hearthvale.
11. Thralls' bone can be burned or buried, and the warmth calls the burned (`side_thralls`).
12. Oswin has kept the altar for two hundred years.
13. Hearthvale leaves bread out for the heirs (`side_bread`).
14. The Keeper of the Grave Gate keeps graves the length of a sword (`a2_letter`).
15. The Drowned Crown was worn for years and never let out (`a2_flood`).
16. The thirtieth wrote to Wren of a Sworn who sells on the stair, and he may hold the sluice key (`a2_flood`).
17. The Sisters dug as far as the sluice and stopped (`a2_flood`).
18. Maren sent his own child first so as not to ask it of a stranger (`a2_ending`).
19. Maren did not write the oath; he swore it (`a2_ending`).
20. Two Keepers stand over the altar and forbid a reading aloud (`a2_rune`).
21. The Trader sold the poached venison back to the vale at half price (`side_trader`).
22. The warmth once reached past the standing stones; Tam grew beans there as a boy (`side_marigold`).

## (c) What Act 3 needs decided first

1. The ending stored, so that Maren and others can speak per ending.
2. Who the player is after the throne (a2).
3. Whether Maren can leave the hearth.
4. The hearth choice per ending. If choices cannot be made conditional in the engine, this must be one quest per ending.
5. A `cinders` reward key (the quest engine pays gold, XP, items, mats and lore only).
6. A way to hide an NPC by flag.
7. The second dungeon (the dead seam), if `a3_seam` is kept. The Foundry and Court are tower tiers and exist.
8. Whether Wren's flood happens, and whose hand is on the sluice, now that `side_hexer` has set its price.
9. A new bloodline on taking the throne (a2).
