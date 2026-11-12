extends RefCounted
## Roulette payout table, spot validation, wheel fairness.

const NAME := "roulette"
const R := preload("res://scripts/casino/roulette.gd")
const Rng := preload("res://scripts/casino/rng.gd")
const Seq := preload("res://tests/seed_seq.gd")

const REDS := [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36]

## [kind, numbers, index, pockets that win (written out by hand), payout]
const EURO_TABLE := [
	["straight", [17], 0, [17], 35],
	["straight", [0], 0, [0], 35],
	["split", [17, 18], 0, [17, 18], 17],
	["split", [20, 17], 0, [17, 20], 17],
	["split", [0, 2], 0, [0, 2], 17],
	["street", [16, 17, 18], 0, [16, 17, 18], 11],
	["corner", [17, 18, 20, 21], 0, [17, 18, 20, 21], 8],
	["line", [16, 17, 18, 19, 20, 21], 0, [16, 17, 18, 19, 20, 21], 5],
	["trio", [0, 1, 2], 0, [0, 1, 2], 11],
	["trio", [0, 2, 3], 0, [0, 2, 3], 11],
	["basket", [], 0, [0, 1, 2, 3], 8],
	["dozen", [], 2, [13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24], 2],
	["column", [], 2, [2, 5, 8, 11, 14, 17, 20, 23, 26, 29, 32, 35], 2],
	["column", [], 3, [3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 33, 36], 2],
]
const AMER_TABLE := [
	["straight", [37], 0, [37], 35],
	["split", [0, 37], 0, [0, 37], 17],
	["split", [37, 3], 0, [3, 37], 17],
	["trio", [37, 2, 3], 0, [2, 3, 37], 11],
	["trio", [0, 37, 2], 0, [0, 2, 37], 11],
	["basket", [], 0, [0, 1, 2, 3, 37], 6],
	["corner", [32, 33, 35, 36], 0, [32, 33, 35, 36], 8],
]


static func _evens() -> Array:
	var red := []
	var black := []
	var odd := []
	var even := []
	var low := []
	var high := []
	for n in range(1, 37):
		(red if n in REDS else black).append(n)
		(odd if n % 2 == 1 else even).append(n)
		(low if n <= 18 else high).append(n)
	return [["red", [], 0, red, 1], ["black", [], 0, black, 1], ["odd", [], 0, odd, 1],
		["even", [], 0, even, 1], ["low", [], 0, low, 1], ["high", [], 0, high, 1]]


func _play(t, wheel: String, table: Array, spins: int) -> void:
	var g = R.new({"wheel": wheel}, Seq.new(77))
	g.apply({"type": "sit", "seat": 0, "player": "p", "buy_in": 1000000})
	var hits := {}
	var seen := {}
	var all_ok := true
	for s in spins:
		for row in table:
			var r: Dictionary = g.apply({"type": "bet", "seat": 0, "kind": row[0], "numbers": row[1], "index": row[2], "amount": 3})
			if not r["ok"]:
				t.check(false, "%s bet %s refused: %s" % [wheel, str(row), r["error"]])
				return
		var res: Dictionary = g.apply({"type": "spin"})
		var pocket := -1
		var k := 0
		for e in res["raw_events"]:
			if e["type"] == "spin":
				pocket = e["result"]
			elif e["type"] == "result":
				var row: Array = table[k]
				var want: int = 3 * row[4] if pocket in row[3] else -3
				if e["net"] != want:
					all_ok = false
				if pocket in row[3]:
					hits[k] = true
				k += 1
		seen[pocket] = true
		if k != table.size():
			all_ok = false
	t.check(all_ok, "%s: every bet settled at its payout" % wheel)
	t.eq(hits.size(), table.size(), "%s: every bet won at least once" % wheel)
	t.eq(seen.size(), 38 if wheel == "american" else 37, "%s: every pocket came up" % wheel)
	t.eq(g.chips.total(), g.chips.opened - g.chips.closed, "%s: chips conserved" % wheel)
	t.eq(g.chips.balance("table"), 0, "%s: table cleared" % wheel)


func run(t) -> void:
	var euro: Array = EURO_TABLE.duplicate(true)
	euro.append_array(_evens())
	_play(t, "european", euro, 1500)
	var amer: Array = euro.filter(func(r): return r[0] != "basket" and r[0] != "trio" and not (r[0] == "split" and 0 in r[1]))
	amer.append_array(AMER_TABLE)
	_play(t, "american", amer, 1500)
	# House edge identity: over one of each pocket, every bet returns -1 unit
	# (European), -2 (American), -3 for the American five-number bet.
	for wheel in ["european", "american"]:
		var g = R.new({"wheel": wheel}, Seq.new(1))
		var counts := {}
		var bad := 0
		var spots := []
		for kind in g._spots:
			for key in g._spots[kind]:
				var nums := []
				for x in String(key).split(","):
					nums.append(int(x))
				spots.append([kind, nums, 0])
			counts[kind] = g._spots[kind].size()
		for kind in ["red", "black", "odd", "even", "low", "high"]:
			spots.append([kind, [], 0])
		for kind in ["dozen", "column"]:
			for i in [1, 2, 3]:
				spots.append([kind, [], i])
		for sp in spots:
			var cov: Array = g.covers(sp[0], sp[1], sp[2])
			var net := 0
			for p in g.pockets():
				net += g.payout(sp[0]) if p in cov else -1
			var want := -1 if wheel == "european" else (-3 if sp[0] == "basket" else -2)
			if net != want:
				bad += 1
				t.check(false, "%s %s %s edge %d" % [wheel, sp[0], str(sp[1]), net])
		t.eq(bad, 0, "%s: house edge identity on %d spots" % [wheel, spots.size()])
		if wheel == "european":
			t.eq(counts, {"straight": 37, "split": 60, "street": 12, "trio": 2, "corner": 22, "line": 11, "basket": 1}, "European spot counts")
		else:
			t.eq(counts, {"straight": 38, "split": 62, "street": 12, "trio": 3, "corner": 22, "line": 11, "basket": 1}, "American spot counts")
	# Not table spots.
	var g = R.new({}, Seq.new(2))
	g.apply({"type": "sit", "seat": 0, "player": "p", "buy_in": 100})
	for bad in [["split", [1, 5]], ["split", [3, 4]], ["split", [0, 37]], ["corner", [3, 4, 6, 7]],
			["street", [2, 3, 4]], ["line", [1, 2, 3, 4, 5]], ["trio", [0, 37, 2]], ["straight", [37]],
			["straight", [38]], ["straight", [-1]], ["straight", []], ["straight", [1, 2]], ["split", [1, 1]],
			["dozen", [], 4], ["column", [], 0], ["nonsense", []], ["straight", "17"], ["straight", [1.5]]]:
		var a := {"type": "bet", "seat": 0, "kind": bad[0], "numbers": bad[1], "amount": 1}
		if bad.size() > 2:
			a["index"] = bad[2]
		t.check(not g.apply(a)["ok"], "not a spot: %s" % str(bad))
	t.check(not g.apply({"type": "bet", "seat": 0, "kind": "red", "amount": 101})["ok"], "over stack")
	t.check(not g.apply({"type": "bet", "seat": 0, "kind": "red", "amount": 0})["ok"], "zero bet")
	t.eq(g.chips.balance("seat0"), 100, "rejections cost nothing")
	g.apply({"type": "bet", "seat": 0, "kind": "red", "amount": 40})
	g.apply({"type": "clear", "seat": 0})
	t.eq(g.chips.balance("seat0"), 100, "clear returns bets")
	# Fairness of the draw: chi-square over 37 pockets, 74k spins (df 36, p>0.001 < 67.98).
	# Each draw from a freshly seeded generator, exactly as _spin does it.
	var src3 = Seq.new(3)
	var bins := {}
	for i in 74000:
		var p: int = Rng.from_seed(src3.next_seed()).next_below(37)
		bins[p] = int(bins.get(p, 0)) + 1
	var chi := 0.0
	for p in 37:
		chi += pow(int(bins.get(p, 0)) - 2000.0, 2) / 2000.0
	t.check(chi < 67.98, "wheel uniform (chi2=%.1f)" % chi)
	_per_seat_limit(t)
	_spin_seeds(t)


## max_bets is per seat: one seat filling its limit leaves the others free.
func _per_seat_limit(t) -> void:
	var g = R.new({"max_bets": 3}, Seq.new(4))
	for i in 3:
		g.apply({"type": "sit", "seat": i, "player": "p%d" % i, "buy_in": 100})
	for k in 3:
		t.check(g.apply({"type": "bet", "seat": 0, "kind": "red", "amount": 1})["ok"], "seat 0 bet %d" % k)
	t.eq(g.apply({"type": "bet", "seat": 0, "kind": "red", "amount": 1}).get("error", ""), "too_many_bets",
		"seat 0's fourth bet refused")
	for i in [1, 2]:
		for k in 3:
			t.check(g.apply({"type": "bet", "seat": i, "kind": "black", "amount": 1})["ok"],
				"seat %d still may bet (%d) after seat 0 hit its limit" % [i, k])
		t.eq(g.apply({"type": "bet", "seat": i, "kind": "red", "amount": 1}).get("error", ""), "too_many_bets",
			"seat %d limit is its own" % i)
	g.apply({"type": "clear", "seat": 0})
	t.check(g.apply({"type": "bet", "seat": 0, "kind": "red", "amount": 1})["ok"], "clearing frees the seat's slots")
	g.apply({"type": "spin"})
	t.check(g.apply({"type": "bet", "seat": 0, "kind": "red", "amount": 1})["ok"], "a spin frees the slots")


## Every spin takes one fresh seed; the result depends on that seed alone.
func _spin_seeds(t) -> void:
	var src = Seq.new(8)
	var g = R.new({}, src)
	g.apply({"type": "sit", "seat": 0, "player": "p", "buy_in": 1000})
	var ok := true
	for i in 30:
		var c0: int = src.calls
		var r: Dictionary = g.apply({"type": "spin"})
		if src.calls != c0 + 1:
			ok = false
		var sd: String = Rng.seed_hex(Rng.parse_seed(src.given[-1]))
		for e in R.events_for(0, r["raw_events"]):
			if e["type"] == "spin" and (e["seed"] != sd or e["result"] != Rng.from_seed(sd).next_below(37)):
				ok = false
	t.check(ok, "one seed per spin; result = from_seed(seed).next_below(37), published with the spin")
	# Same seed every time: the same pocket every time (no state carried over).
	var same = R.new({}, Seq.new("0123456789abcdef0123456789abcdef", true))
	same.apply({"type": "sit", "seat": 0, "player": "p", "buy_in": 1000})
	var results := {}
	for i in 20:
		for e in same.apply({"type": "spin"})["raw_events"]:
			if e["type"] == "spin":
				results[e["result"]] = true
	t.eq(results.size(), 1, "a spin depends only on its own seed")
	# No seed: refused, bets stay down.
	var g2 = R.new({}, null)
	g2.apply({"type": "sit", "seat": 0, "player": "p", "buy_in": 100})
	g2.apply({"type": "bet", "seat": 0, "kind": "red", "amount": 10})
	var before := JSON.stringify(g2.to_dict())
	t.eq(g2.apply({"type": "spin"}).get("error", ""), "no_seed", "no seed source: spin refused")
	t.eq(JSON.stringify(g2.to_dict()), before, "refused spin leaves state untouched")
