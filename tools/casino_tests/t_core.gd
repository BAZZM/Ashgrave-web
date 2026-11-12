extends RefCounted
## RNG, cards, shoe and chip ledger.

const NAME := "core"
const Rng := preload("res://scripts/casino/rng.gd")
const Cards := preload("res://scripts/casino/cards.gd")
const Chips := preload("res://scripts/casino/chips.gd")
const U := preload("res://scripts/casino/util.gd")

const VECTOR_SEEDS := [0, 1, 42, -1, 123456789012345, 0xFFFFFFFF]


func run(t) -> void:
	# Determinism and range.
	var a = Rng.make(42)
	var b = Rng.make(42)
	var c = Rng.make(43)
	var same := true
	var differ := false
	for i in 1000:
		var x: int = a.next_u32()
		var y: int = b.next_u32()
		var z: int = c.next_u32()
		if x != y:
			same = false
		if x != z:
			differ = true
		if x < 0 or x > 0xFFFFFFFF:
			t.check(false, "u32 out of range")
	t.check(same, "same seed same stream")
	t.check(differ, "different seed different stream")
	# Bounded draws: in range and roughly uniform (chi-square, 10 bins).
	var r = Rng.make(7)
	var bins := []
	bins.resize(10)
	bins.fill(0)
	var ok := true
	for i in 100000:
		var v: int = r.next_below(10)
		if v < 0 or v >= 10:
			ok = false
		else:
			bins[v] += 1
	t.check(ok, "next_below in range")
	var chi := 0.0
	for k in 10:
		chi += pow(bins[k] - 10000.0, 2) / 10000.0
	t.check(chi < 27.9, "next_below uniform (chi2=%.1f, p>0.001)" % chi)
	t.eq(r.next_below(1), 0, "next_below(1)")
	var big = r.next_below(0x100000000)
	t.check(big >= 0 and big <= 0xFFFFFFFF, "next_below(2^32)")
	# Shuffle: permutation, deterministic.
	var d1 := Cards.deck()
	var d2 := Cards.deck()
	Rng.make(99).shuffle(d1)
	Rng.make(99).shuffle(d2)
	t.eq(d1, d2, "same seed same shuffle")
	var sorted := d1.duplicate()
	sorted.sort()
	t.eq(sorted, Cards.deck(), "shuffle is a permutation")
	t.check(d1 != Cards.deck(), "shuffle moved cards")
	# Shuffle position uniformity: card 0 lands in each of 4 positions of a 4-deck evenly.
	var pos := [0, 0, 0, 0]
	var rr = Rng.make(5)
	for i in 40000:
		var arr := [0, 1, 2, 3]
		rr.shuffle(arr)
		pos[arr.find(0)] += 1
	var chi2 := 0.0
	for k in 4:
		chi2 += pow(pos[k] - 10000.0, 2) / 10000.0
	t.check(chi2 < 16.3, "Fisher-Yates uniform (chi2=%.1f)" % chi2)
	# State round trip mid-stream.
	var s1 = Rng.make(2024)
	for i in 17:
		s1.next_u32()
	var s2 = Rng.new()
	s2.from_dict(JSON.parse_string(JSON.stringify(s1.to_dict())))
	t.eq(s2.next_u32(), s1.next_u32(), "rng round trip")
	_export_vectors(t)

	# Cards.
	t.eq(Cards.text(Cards.parse("As")), "As", "parse As")
	t.eq(Cards.parse("As"), 51, "As is 51")
	t.eq(Cards.parse("2c"), 0, "2c is 0")
	t.eq(Cards.parse("Td"), 8 * 4 + 1, "Td")
	t.eq(Cards.parse("Xx"), -1, "bad card")
	t.eq(Cards.texts(Cards.parse_list("Ah Kd 2c")), "Ah Kd 2c", "texts")
	var shoe := Cards.new_shoe(6, 75, Rng.make(1))
	t.eq((shoe["cards"] as Array).size(), 312, "6-deck shoe size")
	t.eq(shoe["cut"], 234, "cut card at 75%")
	var counts := {}
	for x in shoe["cards"]:
		counts[x] = int(counts.get(x, 0)) + 1
	var six := true
	for k in 52:
		if counts.get(k, 0) != 6:
			six = false
	t.check(six, "each card six times")
	for i in 234:
		Cards.shoe_draw(shoe)
	t.check(Cards.shoe_past_cut(shoe), "past cut after 234")

	# Ledger.
	var L = Chips.new()
	L.open("house", 0, true)
	L.open("a", 100)
	L.open("b", 50)
	t.check(L.transfer("a", "b", 30, "x"), "transfer ok")
	t.check(not L.transfer("a", "b", 71, "x"), "overdraw refused")
	t.check(not L.transfer("a", "b", -1, "x"), "negative refused")
	t.check(not L.transfer("a", "nobody", 1, "x"), "unknown account refused")
	t.check(L.transfer("house", "a", 500, "x"), "house may go negative")
	t.eq(L.balance("house"), -500, "house negative")
	t.eq(L.total(), 150, "total conserved")
	t.eq(L.faults, 3, "faults counted")
	var rp = Chips.replay(L.events, {})
	t.eq(rp, L.balances, "replay of log matches balances")
	t.eq(L.close("b"), 80, "close returns balance")
	t.eq(L.total(), L.opened - L.closed, "total = opened - closed")
	var L2 = Chips.new()
	L2.from_dict(JSON.parse_string(JSON.stringify(L.to_dict())))
	t.eq(JSON.stringify(L2.to_dict()), JSON.stringify(L.to_dict()), "ledger round trip")
	t.eq(L.events_since(L.seq - 2).size(), 2, "events_since")
	L.trim(L.seq - 1)
	t.eq(L.events.size(), 1, "trim")
	# Util.
	t.eq(U.as_int(3.0), 3, "as_int float")
	t.eq(U.as_int(3.5), null, "as_int fraction")
	t.eq(U.as_int("3"), null, "as_int string")
	t.eq(U.as_int(NAN), null, "as_int nan")


func _export_vectors(t) -> void:
	if t.export_path == "":
		return
	var f := FileAccess.open(t.export_path + ".rng", FileAccess.WRITE)
	for sd in VECTOR_SEEDS:
		var r = Rng.make(sd)
		var vals := []
		for i in 8:
			vals.append(r.next_u32())
		var bel := []
		for n in [1, 2, 3, 7, 10, 52, 37, 1000003, 0x80000001]:
			bel.append(r.next_below(n))
		var d := Cards.deck()
		r.shuffle(d)
		f.store_line("%d\t%s\t%s\t%s" % [sd, ",".join(PackedStringArray(vals.map(func(x): return str(x)))),
			",".join(PackedStringArray(bel.map(func(x): return str(x)))),
			",".join(PackedStringArray(d.map(func(x): return str(x))))])
	f.close()
