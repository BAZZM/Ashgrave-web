extends RefCounted
## Poker hand evaluator: best five of five to seven cards.
##
## value() returns one int; a higher int is a better hand and equal ints tie,
## so values are totally ordered. Layout: category << 20, then five 4-bit rank
## nibbles in order of significance (e.g. two pair K K Q Q 9). A wheel
## (A-2-3-4-5) is encoded 5 4 3 2 A and ranks below 6-high. Suits never matter.
##
## evaluate() also returns the category, its name and the five cards used.

const HIGH_CARD := 0
const PAIR := 1
const TWO_PAIR := 2
const TRIPS := 3
const STRAIGHT := 4
const FLUSH := 5
const FULL_HOUSE := 6
const QUADS := 7
const STRAIGHT_FLUSH := 8

const NAMES := ["high card", "pair", "two pair", "three of a kind", "straight",
	"flush", "full house", "four of a kind", "straight flush"]


static func category(v: int) -> int:
	return v >> 20


static func category_name(v: int) -> String:
	return NAMES[v >> 20]


static func _pack(cat: int, r: Array) -> int:
	return (cat << 20) | (r[0] << 16) | (r[1] << 12) | (r[2] << 8) | (r[3] << 4) | r[4]


## Highest rank of a 5-long run in a 13-bit rank mask, or -1. Ace plays low.
static func _straight_top(mask: int) -> int:
	var m := (mask << 1) | (1 if mask & 0x1000 else 0)
	var h := 13
	while h >= 4:
		if (m >> (h - 4)) & 0x1F == 0x1F:
			return h - 1
		h -= 1
	return -1


static func _straight_ranks(top: int) -> Array:
	if top == 3:
		return [3, 2, 1, 0, 12]
	return [top, top - 1, top - 2, top - 3, top - 4]


static func _top_bits(mask: int, n: int, skip: int = 0) -> Array:
	var out := []
	var r := 12
	while r >= 0 and out.size() < n:
		if mask & (1 << r) and not (skip & (1 << r)):
			out.append(r)
		r -= 1
	return out


## The rank value of the best five of `cards` (5 to 7 ints).
static func value(cards: Array) -> int:
	var counts := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	var smask := [0, 0, 0, 0]
	var sn := [0, 0, 0, 0]
	var mask := 0
	for c in cards:
		var r: int = c >> 2
		var s: int = c & 3
		counts[r] += 1
		smask[s] |= 1 << r
		sn[s] += 1
		mask |= 1 << r
	var flush_mask := -1
	for s in 4:
		if sn[s] >= 5:
			flush_mask = smask[s]
	if flush_mask >= 0:
		var sft := _straight_top(flush_mask)
		if sft >= 0:
			return _pack(STRAIGHT_FLUSH, _straight_ranks(sft))
	var quad := -1
	var trips := []
	var pairs := []
	var r := 12
	while r >= 0:
		var n: int = counts[r]
		if n == 4:
			quad = r
		elif n == 3:
			trips.append(r)
		elif n == 2:
			pairs.append(r)
		r -= 1
	if quad >= 0:
		var k: Array = _top_bits(mask, 1, 1 << quad)
		return _pack(QUADS, [quad, quad, quad, quad, k[0]])
	if trips.size() > 0 and (trips.size() > 1 or pairs.size() > 0):
		var t: int = trips[0]
		var p := -1
		if trips.size() > 1:
			p = trips[1]
		if pairs.size() > 0 and pairs[0] > p:
			p = pairs[0]
		return _pack(FULL_HOUSE, [t, t, t, p, p])
	if flush_mask >= 0:
		return _pack(FLUSH, _top_bits(flush_mask, 5))
	var st := _straight_top(mask)
	if st >= 0:
		return _pack(STRAIGHT, _straight_ranks(st))
	if trips.size() > 0:
		var t: int = trips[0]
		var k: Array = _top_bits(mask, 2, 1 << t)
		return _pack(TRIPS, [t, t, t, k[0], k[1]])
	if pairs.size() >= 2:
		var a: int = pairs[0]
		var b: int = pairs[1]
		var k: Array = _top_bits(mask, 1, (1 << a) | (1 << b))
		return _pack(TWO_PAIR, [a, a, b, b, k[0]])
	if pairs.size() == 1:
		var a: int = pairs[0]
		var k: Array = _top_bits(mask, 3, 1 << a)
		return _pack(PAIR, [a, a, k[0], k[1], k[2]])
	return _pack(HIGH_CARD, _top_bits(mask, 5))


## {value, category, name, cards (the five used, in significance order)}.
static func evaluate(cards: Array) -> Dictionary:
	var v := value(cards)
	var cat := v >> 20
	var want := [(v >> 16) & 15, (v >> 12) & 15, (v >> 8) & 15, (v >> 4) & 15, v & 15]
	var suit_only := -1
	if cat == FLUSH or cat == STRAIGHT_FLUSH:
		var sn := [0, 0, 0, 0]
		for c in cards:
			sn[c & 3] += 1
		for s in 4:
			if sn[s] >= 5:
				suit_only = s
	var pool := cards.duplicate()
	pool.sort()
	pool.reverse()
	var used := []
	for rk in want:
		for i in pool.size():
			var c: int = pool[i]
			if c >= 0 and (c >> 2) == rk and (suit_only < 0 or (c & 3) == suit_only):
				used.append(c)
				pool[i] = -1
				break
	return {"value": v, "category": cat, "name": NAMES[cat], "cards": used}
