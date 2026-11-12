extends RefCounted
## RNG, cards, shoe and chip ledger.

const NAME := "core"
const Rng := preload("res://scripts/casino/rng.gd")
const Cards := preload("res://scripts/casino/cards.gd")
const Chips := preload("res://scripts/casino/chips.gd")
const U := preload("res://scripts/casino/util.gd")

const Seq := preload("res://tests/seed_seq.gd")
const CryptoSrc := preload("res://scripts/casino/adapters/crypto_seed_source.gd")

const VECTOR_SEEDS := ["00000000000000000000000000000000", "00000000000000000000000000000001",
	"ffffffffffffffffffffffffffffffff", "0123456789abcdef0123456789abcdef",
	"80000000000000000000000000000000", "deadbeef00000000cafebabe12345678"]


func run(t) -> void:
	# Determinism and range.
	var a = Rng.test_only_from_int(42)
	var b = Rng.test_only_from_int(42)
	var c = Rng.test_only_from_int(43)
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
	var r = Rng.test_only_from_int(7)
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
	# Out of range n is an error (-1) and draws nothing.
	var st0: Array = r.s.duplicate()
	t.eq(r.next_below(0x100000001), -1, "next_below(2^32+1) is an error")
	t.eq(r.next_below(1 << 40), -1, "next_below(2^40) is an error")
	t.eq(r.next_below(0), -1, "next_below(0) is an error")
	t.eq(r.next_below(-7), -1, "next_below(-7) is an error")
	t.eq(r.s, st0, "rejected next_below draws nothing")
	_seeding(t)
	# Shuffle: permutation, deterministic.
	var d1 := Cards.deck()
	var d2 := Cards.deck()
	Rng.test_only_from_int(99).shuffle(d1)
	Rng.test_only_from_int(99).shuffle(d2)
	t.eq(d1, d2, "same seed same shuffle")
	var sorted := d1.duplicate()
	sorted.sort()
	t.eq(sorted, Cards.deck(), "shuffle is a permutation")
	t.check(d1 != Cards.deck(), "shuffle moved cards")
	# Shuffle position uniformity: card 0 lands in each of 4 positions of a 4-deck evenly.
	var pos := [0, 0, 0, 0]
	var rr = Rng.test_only_from_int(5)
	for i in 40000:
		var arr := [0, 1, 2, 3]
		rr.shuffle(arr)
		pos[arr.find(0)] += 1
	var chi2 := 0.0
	for k in 4:
		chi2 += pow(pos[k] - 10000.0, 2) / 10000.0
	t.check(chi2 < 16.3, "Fisher-Yates uniform (chi2=%.1f)" % chi2)
	# State round trip mid-stream.
	var s1 = Rng.test_only_from_int(2024)
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
	var shoe := Cards.new_shoe(6, 75, Rng.test_only_from_int(1))
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


## 128-bit seeding, the seed sources and the purity of the core.
func _seeding(t) -> void:
	var hex := "0123456789abcdef0011223344556677"
	t.eq(Rng.parse_seed(hex), [0x01234567, 0x89abcdef, 0x00112233, 0x44556677], "hex seed parses word 0 first")
	t.eq(Rng.parse_seed(hex.to_upper()), Rng.parse_seed(hex), "hex seed is case-blind")
	t.eq(Rng.seed_hex(Rng.parse_seed(hex)), hex, "seed_hex round trip")
	t.eq(Rng.parse_seed([1, 2, 3, 4.0]), [1, 2, 3, 4], "array seed, JSON float accepted")
	for bad in ["", "0123", hex + "0", hex.substr(1) + "g", [1, 2, 3], [1, 2, 3, -1], [1, 2, 3, 0x100000000],
			[1, 2, 3, 1.5], [1, 2, 3, "4"], 42, null, {"s": [1, 2, 3, 4]}]:
		t.eq(Rng.parse_seed(bad), [], "bad seed rejected: %s" % str(bad))
		t.eq(Rng.from_seed(bad), null, "from_seed refuses %s" % str(bad))
	# All 128 bits matter: flipping any one bit of any word changes the stream.
	var base := [0x11111111, 0x22222222, 0x33333333, 0x44444444]
	var ref_first := []
	var g0 = Rng.from_seed(base)
	for i in 4:
		ref_first.append(g0.next_u32())
	var all_differ := true
	var distinct_states := {}
	for w in 4:
		for bit in [0, 13, 31]:
			var sd := base.duplicate()
			sd[w] = sd[w] ^ (1 << bit)
			var g = Rng.from_seed(sd)
			distinct_states[str(g.s)] = true
			var first := []
			for i in 4:
				first.append(g.next_u32())
			if first == ref_first:
				all_differ = false
	t.check(all_differ, "every seed bit changes the stream (old code folded 64 bits to 32)")
	t.eq(distinct_states.size(), 12, "distinct seeds give distinct states")
	# Seeds equal in their low 64 bits but not the high 64 give other streams.
	var lo_a = Rng.from_seed([0, 0, 5, 6])
	var lo_b = Rng.from_seed([1, 0, 5, 6])
	var hi_b = Rng.from_seed([0, 0, 5, 7])
	var a1: int = lo_a.next_u32()
	t.check(a1 != lo_b.next_u32() and a1 != hi_b.next_u32(), "low and high words both reach the state")
	# The all-zero seed is legal and gives a working generator.
	var z = Rng.from_seed("00000000000000000000000000000000")
	t.check(z != null and z.s != [0, 0, 0, 0], "zero seed gives a non-zero state")
	# Test-only int constructor is deterministic and distinct per int.
	t.eq(Rng.test_only_from_int(5).next_u32(), Rng.test_only_from_int(5).next_u32(), "test_only_from_int deterministic")
	# Deterministic seed source.
	var q1 = Seq.new(9)
	var q2 = Seq.new(9)
	var all_valid := true
	var uniq := {}
	for i in 50:
		var x = q1.next_seed()
		if x != q2.next_seed() or Rng.parse_seed(x).is_empty():
			all_valid = false
		uniq[x] = true
	t.check(all_valid, "seed_seq: same base, same valid seeds")
	t.eq(uniq.size(), 50, "seed_seq: no repeats")
	t.eq(q1.calls, 50, "seed_seq counts calls")
	# CSPRNG adapter (outside the core): 4 u32 per call, never repeating.
	var cs = CryptoSrc.new()
	var c1: Array = cs.next_seed()
	var c2: Array = cs.next_seed()
	t.eq(Rng.parse_seed(c1), c1, "crypto source gives four u32")
	t.check(c1 != c2, "crypto source gives fresh seeds")
	# Purity: the core files never reach the engine's randomness, Crypto,
	# nodes or singletons; only the adapter may use Crypto.
	var banned := ["\\brandi\\(", "\\brandf", "\\brandomize\\(", "RandomNumberGenerator", "\\bCrypto\\b",
		"extends\\s+Node", "class_name", "\\bEngine\\.", "\\bOS\\.", "\\bTime\\.", "\\bInput\\.",
		"get_tree", "(^|[^A-Za-z0-9_.])seed\\(", "\\bClassDB\\b", "\\bProjectSettings\\b"]
	var dir := DirAccess.open("res://scripts/casino")
	var files := 0
	for fn in dir.get_files():
		if not fn.ends_with(".gd"):
			continue
		files += 1
		var src := FileAccess.get_file_as_string("res://scripts/casino/" + fn)
		# Comments may name what is forbidden; only code counts.
		var code := ""
		for line in src.split("\n"):
			var cut := line.find("#")
			code += (line if cut < 0 else line.substr(0, cut)) + "\n"
		for b in banned:
			var re := RegEx.new()
			re.compile(b)
			t.check(re.search(code) == null, "core %s does not use %s" % [fn, b])
	t.check(files >= 8, "purity scan saw the core files (%d)" % files)
	var ad := FileAccess.get_file_as_string("res://scripts/casino/adapters/crypto_seed_source.gd")
	t.check(ad.contains("Crypto.new()") and not ad.contains("extends Node"), "adapter is the Crypto user")


func _export_vectors(t) -> void:
	if t.export_path == "":
		return
	var f := FileAccess.open(t.export_path + ".rng", FileAccess.WRITE)
	for sd in VECTOR_SEEDS:
		var r = Rng.from_seed(sd)
		var vals := []
		for i in 8:
			vals.append(r.next_u32())
		var bel := []
		for n in [1, 2, 3, 7, 10, 52, 37, 1000003, 0x80000001]:
			bel.append(r.next_below(n))
		var d := Cards.deck()
		r.shuffle(d)
		f.store_line("%s\t%s\t%s\t%s" % [sd, ",".join(PackedStringArray(vals.map(func(x): return str(x)))),
			",".join(PackedStringArray(bel.map(func(x): return str(x)))),
			",".join(PackedStringArray(d.map(func(x): return str(x))))])
	f.close()
