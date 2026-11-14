# Questions for the owner

Each has a suggested answer. Nothing below blocks play: the build uses the suggestion.

## (a) Canon problems

1. The Chandler "sells to both", yet Maren has never passed the gate and no heir came back before this one. How could Maren buy from him? Suggest: he trades through the gate at night. (Part two.)
2. After taking the throne, who is the player? The game does not start a new bloodline, and the same hero walks back to Maren. Suggest: the same heir, crowned, with the hearth choice made once. Part one avoids the question.
3. Bandits are "of the blood", but the blood cannot die outside the tower. Suggest: embrace it. They wake on the hearthstone (`side_isolde` says so); Act 1's death bark means "again".
4. The ember seam is "dead", but ember veins are mined everywhere. Suggest: the ore is cold since the Burning until a forge wakes it (`a2_mark` says so).
5. The shrine burns "one flame per heir", but the shipped shrine is one light and Act 1 calls it a waymark. Suggest: drop the flames; part one never says them.
6. The Warden's Brand reward gives nothing when the Brand is already forged (`add_item` does nothing when owned, but the caption says "Received"). Suggest: pay gold in its place when owned.
7. Maren's idle line for `loop>=1` needs one variant per ending, which needs the ending stored. Suggest: store it as a one-line flag in `duel.gd` `spare()`. Part one gives the throne and not-throne variants only.

## (b) Facts my text invents

1. A sluice between the Cisterns and the pyre, which needs a hand on it from inside (Wren admits this in `side_hexer`).
2. The Duelist was Maren's own child, a daughter (`a2_ending`).
3. Oswin swore the oath first with the first heir, and corrected one word.
4. Maren's brother was Ansel, the Regent. Maren has not said the name since the first heir went up.
5. Maren sent a rook up before each heir; none came back and none was answered (`a2_letter`).
6. The family's mark is struck under the grip of every blade, and on the Gravemaul's plates (`a2_mark`, `side_mine`).
7. Ember ore is cold until a forge wakes it.
8. Wren keeps a cloak cut to the player's measure (`side_cloaks`).
9. Maren scratched "A lie." under the oath himself with a cinder shard, after the tenth heir (`side_lie`).
10. Bandits wake on the hearthstone in Hearthvale.
11. Thralls bone can be burned or buried, with the warmth calling the burned (`side_thralls`).
12. Oswin has kept the altar for two hundred years.
13. Hearthvale leaves bread out for the heirs (`side_bread`).
Suggested answer for all: keep.

## (c) What Act 3 needs decided first

1. The ending stored, so that Maren and others can speak per ending.
2. Who the player is after the throne (see a2).
3. Whether Maren can leave the hearth.
4. The hearth choice per ending.
5. A `cinders` reward key (the quest engine pays gold, XP, items, mats and lore only).
6. A way to hide an NPC by flag (a quest cannot remove a character from the map).
7. A second dungeon, if the Foundry and Court are to be played as places.
