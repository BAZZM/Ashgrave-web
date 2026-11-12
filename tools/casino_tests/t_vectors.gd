extends RefCounted
## Golden vectors under tools/casino_tests/vectors/: the bits a future port
## (TypeScript server) must reproduce. Normally they are only checked; run
## with --write-vectors=<dir> to regenerate them (only when the rules or the
## RNG change on purpose, and say so in the commit).
##
## rng.json: seed in -> first u32s, bounded draws, a shuffled 52-card deck.
## <game>.json: config + seeds (in the order the game asks for them) + the
## action list in -> final balances, event count and the SHA-256 of the event
## log, one canonical JSON line per event (keys sorted, no spaces) joined by
## "\n". Every listed action must succeed.

const NAME := "vectors"
const Rng := preload("res://scripts/casino/rng.gd")
const Cards := preload("res://scripts/casino/cards.gd")
const H := preload("res://scripts/casino/holdem.gd")
const BJ := preload("res://scripts/casino/blackjack.gd")
const R := preload("res://scripts/casino/roulette.gd")
const Seq := preload("res://tests/seed_seq.gd")

const DIR := "res://tests/vectors/"
const RNG_SEEDS := ["00000000000000000000000000000000", "00000000000000000000000000000001",
	"ffffffffffffffffffffffffffffffff", "0123456789abcdef0123456789abcdef",
	"80000000000000000000000000000000", "deadbeef00000000cafebabe12345678",
	"9e3779b97f4a7c15f39cc0605cedc834"]
const BELOW_N := [1, 2, 3, 7, 10, 37, 38, 52, 312, 1000003, 0x80000001, 0xFFFFFFFF, 0x100000000]

var t


func run(tt) -> void:
	t = tt
	if t.write_vectors != "":
		_write(t.write_vectors)
	_check_rng()
	for game in ["blackjack", "roulette", "holdem"]:
		_check_game(game)


static func canonical_line(e: Dictionary) -> String:
	return JSON.stringify(e, "", true)


static func log_hash(evts: Array) -> String:
	var lines := PackedStringArray()
	for e in evts:
		lines.append(canonical_line(e))
	return "\n".join(lines).sha256_text()


func _rng_vector(seed: String) -> Dictionary:
	var r = Rng.from_seed(seed)
	var u := []
	for i in 8:
		u.append(r.next_u32())
	var bel := []
	for n in BELOW_N:
		bel.append(r.next_below(n))
	var d := Cards.deck()
	Rng.from_seed(seed).shuffle(d)
	return {"seed": seed, "u32": u, "below_n": BELOW_N, "below": bel, "deck": d}


func _check_rng() -> void:
	var data = _load("rng.json")
	if data == null:
		return
	var ok := 0
	for v in data["vectors"]:
		if t.eq(_rng_vector(v["seed"]), v, "rng vector %s" % v["seed"]):
			ok += 1
	t.check(ok >= RNG_SEEDS.size(), "rng vectors present (%d)" % ok)
	# A 6-deck shoe too: what a port's blackjack must shuffle.
	t.eq(Cards.new_shoe(6, 75, Rng.from_seed(data["shoe"]["seed"]))["cards"], data["shoe"]["cards"], "6-deck shoe vector")


func _load(name: String) -> Variant:
	var txt := FileAccess.get_file_as_string(DIR + name)
	var d = JSON.parse_string(txt)
	if not t.check(typeof(d) == TYPE_DICTIONARY, "vector file %s loads" % name):
		return null
	return Chips_norm(d)


static func Chips_norm(d: Variant) -> Variant:
	return preload("res://scripts/casino/chips.gd").norm(d)


func _new_game(game: String, cfg: Dictionary, src) -> RefCounted:
	match game:
		"blackjack":
			return BJ.new(cfg, src)
		"roulette":
			return R.new(cfg, src)
	return H.new(cfg, src)


func _check_game(game: String) -> void:
	var v = _load(game + ".json")
	if v == null:
		return
	var src = Seq.new(v["seeds"])
	var g := _new_game(game, v["config"], src)
	var all_ok := true
	for a in v["actions"]:
		var r: Dictionary = g.apply(a)
		if not r["ok"]:
			all_ok = false
			t.check(false, "%s vector action %s refused: %s" % [game, str(a), r["error"]])
			break
	t.check(all_ok, "%s vector: every action accepted" % game)
	t.eq(src.calls, (v["seeds"] as Array).size(), "%s vector: seeds consumed" % game)
	t.eq(g.chips.balances, v["final_balances"], "%s vector: final balances" % game)
	t.eq(g.chips.events.size(), v["event_count"], "%s vector: event count" % game)
	t.eq(log_hash(g.chips.events), v["event_log_sha256"], "%s vector: event log hash" % game)
	t.eq(canonical_line(g.chips.events[0]), v["first_event"], "%s vector: canonical first event" % game)


# ------------------------------------------------------------ generation

func _write(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var vecs := []
	for sd in RNG_SEEDS:
		vecs.append(_rng_vector(sd))
	var shoe_seed := "5a17c0de5a17c0de5a17c0de5a17c0de"
	_save(dir, "rng.json", {"algorithm": "xoshiro128**; s[i] = murmur3 fmix32((w[i] + 0x9E3779B9*(i+1)) mod 2^32), all-zero state -> s[0]=1, then 4 outputs discarded",
		"vectors": vecs, "shoe": {"seed": shoe_seed, "decks": 6, "penetration_pct": 75,
		"cards": Cards.new_shoe(6, 75, Rng.from_seed(shoe_seed))["cards"]}})
	_save(dir, "blackjack.json", _gen_blackjack())
	_save(dir, "roulette.json", _gen_roulette())
	_save(dir, "holdem.json", _gen_holdem())
	print("  wrote vectors to %s" % dir)


func _save(dir: String, name: String, d: Dictionary) -> void:
	var f := FileAccess.open(dir.path_join(name), FileAccess.WRITE)
	f.store_string(JSON.stringify(d, " ", true) + "\n")
	f.close()


func _result(game: String, cfg: Dictionary, src, g, actions: Array) -> Dictionary:
	var seeds := []
	for s in src.given:
		seeds.append(Rng.seed_hex(Rng.parse_seed(s)))
	return {"game": game, "config": cfg, "seeds": seeds, "actions": actions,
		"final_balances": g.chips.balances.duplicate(), "event_count": g.chips.events.size(),
		"event_log_sha256": log_hash(g.chips.events), "first_event": canonical_line(g.chips.events[0]),
		"canonical_form": "one JSON object per event, keys sorted, no whitespace, joined by \\n; SHA-256 of the UTF-8"}


func _go(g, actions: Array, a: Dictionary) -> bool:
	var r: Dictionary = g.apply(a)
	if r["ok"]:
		actions.append(a)
	return r["ok"]


func _gen_blackjack() -> Dictionary:
	var cfg := {"decks": 6, "seats": 3, "min_bet": 1, "max_bet": 500, "penetration_pct": 75}
	var src = Seq.new(1001)
	var g = BJ.new(cfg, src)
	var pol = Rng.test_only_from_int(2001)
	var acts := []
	for i in 3:
		_go(g, acts, {"type": "sit", "seat": i, "player": "p%d" % i, "buy_in": 5000})
	for round in 120:
		for i in 3:
			_go(g, acts, {"type": "bet", "seat": i, "amount": 1 + pol.next_below(60)})
		_go(g, acts, {"type": "deal"})
		var guard := 0
		while g.phase != "betting" and guard < 100:
			guard += 1
			if g.phase == "insurance":
				for i in 3:
					var la: Array = g.legal_actions(i)
					if not la.is_empty():
						_go(g, acts, {"type": "insurance", "seat": i, "amount": pol.next_below(la[0]["max"] + 1)})
						break
			else:
				var la: Array = g.legal_actions(g.turn_seat)
				var pick: String = la[pol.next_below(la.size())]["type"]
				_go(g, acts, {"type": pick, "seat": g.turn_seat})
	return _result("blackjack", cfg, src, g, acts)


func _gen_roulette() -> Dictionary:
	var cfg := {"wheel": "european", "seats": 3, "min_bet": 1, "max_bet": 100, "max_bets": 8}
	var src = Seq.new(1002)
	var g = R.new(cfg, src)
	var pol = Rng.test_only_from_int(2002)
	var acts := []
	var kinds := R.INSIDE + R.OUTSIDE
	for i in 3:
		_go(g, acts, {"type": "sit", "seat": i, "player": "p%d" % i, "buy_in": 5000})
	for sp in 60:
		for i in 3:
			for b in pol.next_below(4):
				var kind: String = kinds[pol.next_below(kinds.size())]
				var a := {"type": "bet", "seat": i, "kind": kind, "amount": 1 + pol.next_below(20)}
				if kind in R.INSIDE:
					var keys: Array = g._spots[kind].keys()
					var nums := []
					for x in String(keys[pol.next_below(keys.size())]).split(","):
						nums.append(int(x))
					a["numbers"] = nums
				elif kind == "dozen" or kind == "column":
					a["index"] = 1 + pol.next_below(3)
				_go(g, acts, a)
		_go(g, acts, {"type": "spin"})
	return _result("roulette", cfg, src, g, acts)


func _gen_holdem() -> Dictionary:
	var cfg := {"seats": 6, "sb": 1, "bb": 2, "ante": 0, "min_buy_in": 40, "max_buy_in": 500}
	var src = Seq.new(1003)
	var g = H.new(cfg, src)
	var pol = Rng.test_only_from_int(2003)
	var acts := []
	var names := 0
	for hand in 60:
		for i in 6:
			if g.seats[i]["player"] == "":
				names += 1
				_go(g, acts, {"type": "sit", "seat": i, "player": "n%d" % names, "buy_in": 40 + pol.next_below(461)})
			elif g.stack(i) < 40:
				_go(g, acts, {"type": "top_up", "seat": i, "amount": 500 - g.stack(i)})
		if not _go(g, acts, {"type": "start_hand"}):
			continue
		var guard := 0
		while g.phase == "betting" and guard < 200:
			guard += 1
			if pol.next_below(60) == 0:
				_go(g, acts, {"type": "leave", "seat": pol.next_below(6)})
				continue
			var la: Array = g.legal_actions(g.to_act)
			var x: Dictionary = la[pol.next_below(la.size())]
			var a := {"type": x["type"], "seat": g.to_act}
			if x.has("min"):
				a["to"] = x["min"] + pol.next_below(x["max"] - x["min"] + 1)
			_go(g, acts, a)
	return _result("holdem", cfg, src, g, acts)
