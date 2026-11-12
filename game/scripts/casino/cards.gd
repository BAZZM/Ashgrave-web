extends RefCounted
## Cards as ints, the 52-card deck and a multi-deck shoe with a cut card.
##
## card = rank * 4 + suit, rank 0..12 = 2..A, suit 0..3 = c d h s.
## So card >> 2 is the rank and card & 3 the suit. "As" "Td" "2c" in logs.

const RANKS := "23456789TJQKA"
const SUITS := "cdhs"
const ACE := 12


static func rank(c: int) -> int:
	return c >> 2


static func suit(c: int) -> int:
	return c & 3


static func make(r: int, s: int) -> int:
	return r * 4 + s


static func text(c: int) -> String:
	if c < 0 or c > 51:
		return "??"
	return RANKS[c >> 2] + SUITS[c & 3]


static func texts(cards: Array) -> String:
	var parts := PackedStringArray()
	for c in cards:
		parts.append(text(int(c)))
	return " ".join(parts)


## "As" -> 51, or -1 when not a card.
static func parse(t: String) -> int:
	if t.length() != 2:
		return -1
	var r := RANKS.find(t[0].to_upper())
	var s := SUITS.find(t[1].to_lower())
	if r < 0 or s < 0:
		return -1
	return make(r, s)


static func parse_list(t: String) -> Array:
	var out := []
	for w in t.split(" ", false):
		out.append(parse(w))
	return out


static func deck() -> Array:
	var d := []
	for c in 52:
		d.append(c)
	return d


## A shoe of `decks` decks shuffled with `rng`, the cut card placed so that
## `penetration_pct` percent of the shoe is dealt before a reshuffle is due.
## Returned as a plain Dictionary so it serialises with the game.
static func new_shoe(decks: int, penetration_pct: int, rng) -> Dictionary:
	var cards := []
	for i in decks:
		cards.append_array(deck())
	rng.shuffle(cards)
	var cut := clampi(cards.size() * penetration_pct / 100, 1, cards.size())
	return {"cards": cards, "pos": 0, "cut": cut, "decks": decks, "pen": penetration_pct}


static func shoe_draw(shoe: Dictionary) -> int:
	var cards: Array = shoe["cards"]
	var pos: int = shoe["pos"]
	if pos >= cards.size():
		return -1
	shoe["pos"] = pos + 1
	return cards[pos]


static func shoe_past_cut(shoe: Dictionary) -> bool:
	return int(shoe["pos"]) >= int(shoe["cut"])


static func shoe_left(shoe: Dictionary) -> int:
	return (shoe["cards"] as Array).size() - int(shoe["pos"])
