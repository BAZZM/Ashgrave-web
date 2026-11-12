extends RefCounted
## Property tests: thousands of random legal games. Each game runs twice in
## lockstep, the twin being serialised to JSON and rebuilt at random moments
## (mid-hand included); both must stay identical. Chips are conserved, no stack
## goes negative, the state stays legal, and a seat's view never holds a card
## it may not know.

const NAME := "props"
const H := preload("res://scripts/casino/holdem.gd")
const BJ := preload("res://scripts/casino/blackjack.gd")
const R := preload("res://scripts/casino/roulette.gd")
const Rng := preload("res://scripts/casino/rng.gd")
const Chips := preload("res://scripts/casino/chips.gd")
const Seq := preload("res://tests/seed_seq.gd")

var t
var bad := 0
var stats := {}
## Oracle export (tools/casino_tests/oracle.py): one JSON line per hand / round.
var _pots_f: FileAccess = null
var _bj_f: FileAccess = null


func _fail(msg: String) -> void:
	bad += 1
	if bad <= 20:
		t.check(false, msg)


## Rebuilt from JSON; the seed source is not state, so it is passed again.
func _rt(g, script, src) -> RefCounted:
	var d = JSON.parse_string(JSON.stringify(g.to_dict()))
	var n = script.new({}, src)
	n.from_dict(d)
	return n


static func _sig(g) -> String:
	return JSON.stringify(g.to_dict())


func _stat(k: String, n := 1) -> void:
	stats[k] = int(stats.get(k, 0)) + n


func run(tt) -> void:
	t = tt
	var q: bool = t.quick
	var n_hold := 2000 if q else 20000
	var n_bj := 2000 if q else 20000
	var n_rou := 2000 if q else 20000
	if t.export_path != "":
		_pots_f = FileAccess.open(t.export_path + ".pots", FileAccess.WRITE)
		_bj_f = FileAccess.open(t.export_path + ".bj", FileAccess.WRITE)
	var t0 := Time.get_ticks_msec()
	var hs := _holdem_run(n_hold, 1000)
	t.check(bad == 0, "holdem property run clean")
	print("  holdem: %d hands in %.1f s  %s" % [n_hold, (Time.get_ticks_msec() - t0) / 1000.0, str(hs)])
	bad = 0
	t0 = Time.get_ticks_msec()
	stats = {}
	_bj_run(n_bj, 2000)
	t.check(bad == 0, "blackjack property run clean")
	print("  blackjack: %d rounds in %.1f s  %s" % [n_bj, (Time.get_ticks_msec() - t0) / 1000.0, str(stats)])
	bad = 0
	t0 = Time.get_ticks_msec()
	stats = {}
	_rou_run(n_rou, 3000)
	t.check(bad == 0, "roulette property run clean")
	print("  roulette: %d spins in %.1f s  %s" % [n_rou, (Time.get_ticks_msec() - t0) / 1000.0, str(stats)])
	bad = 0
	# Same seed, same game; another seed, another game.
	stats = {}
	t.eq(_holdem_session(5, 300, false), _holdem_session(5, 300, false), "holdem: same seed same game")
	t.check(_holdem_session(5, 300, false) != _holdem_session(6, 300, false), "holdem: other seed other game")
	t.eq(_bj_session(5, 300, false), _bj_session(5, 300, false), "blackjack: same seed same game")
	t.check(_bj_session(5, 300, false) != _bj_session(6, 300, false), "blackjack: other seed other game")
	t.eq(_rou_session(5, 300, false), _rou_session(5, 300, false), "roulette: same seed same game")
	t.check(_rou_session(5, 300, false) != _rou_session(6, 300, false), "roulette: other seed other game")
	t.check(bad == 0, "determinism sessions clean")
	bad = 0
	stats = {}
	_fuzz(2000 if q else 20000)
	t.check(bad == 0, "fuzz: garbage actions never crash or break invariants")
	print("  fuzz: %s" % str(stats))
	if _pots_f != null:
		_pots_f.close()
		_bj_f.close()
		_pots_f = null
		_bj_f = null


# ======================================================== Fuzz

const FUZZ_TYPES := ["sit", "leave", "sit_out", "sit_in", "top_up", "start_hand", "fold", "check", "call",
	"bet", "raise", "deal", "hit", "stand", "double", "split", "insurance", "spin", "clear", "", "x"]
const FUZZ_KEYS := ["type", "seat", "amount", "to", "buy_in", "player", "kind", "numbers", "index"]


func _junk(pol) -> Variant:
	match pol.next_below(12):
		0: return null
		1: return pol.next_below(8) - 1
		2: return float(pol.next_below(200)) / 2.0
		3: return 9223372036854775807
		4: return -9223372036854775807
		5: return "seat"
		6: return [pol.next_below(40), pol.next_below(40)]
		7: return {"a": 1}
		8: return true
		9: return pol.next_below(2000)
		10: return R.INSIDE[pol.next_below(R.INSIDE.size())]
		_: return INF
	return null


## Random garbage and half-right actions against each game; every answer must
## be a well-formed result and the ledger must stay sound.
func _fuzz(n: int) -> void:
	var pol = Rng.test_only_from_int(4242)
	var games := [H.new({"min_buy_in": 1, "max_buy_in": 5000}, Seq.new(1)), BJ.new({}, Seq.new(2)),
		R.new({"wheel": "american"}, Seq.new(3))]
	for g in games:
		for i in 3:
			g.apply({"type": "sit", "seat": i, "player": "f%d" % i, "buy_in": 1000})
	for k in n:
		var g = games[k % 3]
		var a := {}
		for key in FUZZ_KEYS:
			if pol.next_below(3) != 0:
				a[key] = _junk(pol)
		if pol.next_below(3) != 0:
			a["type"] = FUZZ_TYPES[pol.next_below(FUZZ_TYPES.size())]
		if pol.next_below(2) == 0:
			a["seat"] = pol.next_below(4)
		var r = g.apply(a if pol.next_below(50) != 0 else _junk(pol))
		if typeof(r) != TYPE_DICTIONARY or not r.has("ok") or (not r["ok"] and not r.has("error")):
			_fail("malformed result for %s" % str(a))
			continue
		_stat("ok" if r["ok"] else "refused")
		var c = g.chips
		if c.faults != 0 or c.total() != c.opened - c.closed:
			_fail("fuzz broke the ledger with %s" % str(a))
			c.faults = 0
		for key in c.balances:
			if key != "house" and c.balances[key] < 0:
				_fail("fuzz made a negative balance with %s" % str(a))
		if g == games[0] and g.phase == "betting":
			_hold_inv(g)
		if g == games[1]:
			_bj_inv(g)
		# Keep the games moving so mid-hand states get fuzzed too.
		if pol.next_below(4) == 0:
			if g == games[0]:
				if g.phase == "waiting":
					g.apply({"type": "start_hand"})
				else:
					var la: Array = g.legal_actions(g.to_act)
					var p := _pick(la, pol)
					p["seat"] = g.to_act
					g.apply(p)
			elif g == games[1]:
				if g.phase == "betting":
					for i in 3:
						g.apply({"type": "bet", "seat": i, "amount": 1 + pol.next_below(20)})
					g.apply({"type": "deal"})
				elif g.phase == "insurance":
					for i in 3:
						g.apply({"type": "insurance", "seat": i, "amount": 0})
				else:
					g.apply({"type": "stand", "seat": g.turn_seat})
		for i in 3:
			if g.chips.balance("seat%d" % i) < 30 and (g != games[0] or g.phase == "waiting") and (g != games[1] or g.phase == "betting"):
				g.apply({"type": "leave", "seat": i})
				g.apply({"type": "sit", "seat": i, "player": "f%d" % i, "buy_in": 1000})


# ======================================================== Hold'em

func _holdem_run(total: int, seed: int) -> Dictionary:
	stats = {}
	var per := 500
	var done := 0
	var k := 0
	while done < total:
		var n := mini(per, total - done)
		_holdem_session(seed + k, n, true)
		done += n
		k += 1
	return stats


## Plays `hands` hands; returns the final state signature.
func _holdem_session(seed: int, hands: int, twin: bool) -> String:
	var pol = Rng.test_only_from_int(seed * 7919 + 13)
	var bb: int = [2, 2, 10, 50][pol.next_below(4)]
	var cfg := {"seats": 2 + pol.next_below(5), "sb": bb / 2, "bb": bb,
		"ante": [0, 0, 1, bb / 2][pol.next_below(4)], "min_buy_in": bb, "max_buy_in": bb * 100}
	var srcB = Seq.new(seed)
	var A = H.new(cfg, Seq.new(seed))
	var B = H.new(cfg, srcB) if twin else null
	var names := 0
	var played := 0
	var guard := 0
	while played < hands and guard < hands * 4:
		guard += 1
		# Table changes between hands.
		for i in A.n_seats():
			var s: Dictionary = A.seats[i]
			var roll: int = pol.next_below(100)
			if s["player"] == "":
				if roll < 60:
					names += 1
					var buy: int = cfg["min_buy_in"] + pol.next_below(cfg["max_buy_in"] - cfg["min_buy_in"] + 1)
					_both(A, B, {"type": "sit", "seat": i, "player": "bot%d" % names, "buy_in": buy})
			elif A.stack(i) < bb and roll < 70:
				_both(A, B, {"type": "top_up", "seat": i, "amount": cfg["max_buy_in"] - A.stack(i)})
			elif roll < 2:
				_both(A, B, {"type": "leave", "seat": i})
			elif roll < 4:
				_both(A, B, {"type": "sit_out" if not s["sitting_out"] else "sit_in", "seat": i})
			elif s["sitting_out"] and roll < 30:
				_both(A, B, {"type": "sit_in", "seat": i})
		var r: Dictionary = _both(A, B, {"type": "start_hand"})
		if not r["ok"]:
			continue
		played += 1
		_stat("hands")
		var start_bal: Dictionary = A.chips.balances.duplicate()
		var start_seq: int = A.chips.seq
		var in_hand_chips := _in_hand_chips(A)
		var steps := 0
		while A.phase == "betting":
			steps += 1
			if steps > 400:
				_fail("hand %d did not finish" % A.hand_no)
				break
			if twin and pol.next_below(12) == 0:
				B = _rt(B, H, srcB)
			var roll: int = pol.next_below(1000)
			if roll < 4:
				var who: int = pol.next_below(A.n_seats())
				if A.seats[who]["player"] != "":
					_both(A, B, {"type": "leave", "seat": who})
					_stat("leave_mid_hand")
					continue
			if roll >= 990:
				_illegal(A, B, pol)
				continue
			var seat: int = A.to_act
			var legal: Array = A.legal_actions(seat)
			if legal.is_empty():
				_fail("no legal actions for to_act %d" % seat)
				break
			var a := _pick(legal, pol)
			a["seat"] = seat
			var res: Dictionary = _both(A, B, a)
			if not res["ok"]:
				_fail("legal action refused: %s %s" % [str(a), res["error"]])
				break
			if A.phase == "betting":
				_hold_inv(A)
				var now := _in_hand_chips(A)
				if now != in_hand_chips:
					_fail("chips in hand changed %d -> %d" % [in_hand_chips, now])
					in_hand_chips = now
			if pol.next_below(4) == 0:
				_leak_check(A, pol.next_below(A.n_seats() + 1) - 1, res["raw_events"])
		_hold_inv(A)
		if A.chips.balance("pot") != 0:
			_fail("pot not empty after hand")
		# The hand's log replays to the balances.
		var hand_evts: Array = A.chips.events_since(start_seq)
		var rp := Chips.replay(hand_evts, start_bal)
		if rp != A.chips.balances:
			_fail("log replay mismatch on hand %d" % A.hand_no)
		if twin:
			_export_pots(A, r["raw_events"] + hand_evts)
		if twin:
			var sa := _sig(A)
			if sa != _sig(B):
				_fail("twin diverged after hand %d" % A.hand_no)
				B = _rt(A, H, srcB)
			A.chips.trim(A.chips.seq)
			B.chips.trim(B.chips.seq)
		for e in A.audit_history[-1]["awards"]:
			if e["winners"].size() > 1:
				_stat("split_pots")
		if A.audit_history[-1]["awards"].size() > 1:
			_stat("side_pots")
		if not A.audit_history[-1]["shown"].is_empty():
			_stat("showdowns")
	if played < hands:
		_fail("session %d played only %d hands" % [seed, played])
	A.chips.trim(A.chips.seq)
	return _sig(A)


func _both(A, B, a: Dictionary) -> Dictionary:
	var ra: Dictionary = A.apply(a)
	if B != null:
		var rb: Dictionary = B.apply(a.duplicate(true))
		if ra["ok"] != rb["ok"] or ra.get("error", "") != rb.get("error", "") \
				or (ra["ok"] and ra["raw_events"].size() != rb["raw_events"].size()):
			_fail("twin answered differently to %s" % str(a))
	return ra


func _pick(legal: Array, pol) -> Dictionary:
	var roll: int = pol.next_below(100)
	var raise_la = null
	var passive = null
	for la in legal:
		if la["type"] == "raise" or la["type"] == "bet":
			raise_la = la
		elif la["type"] == "check" or la["type"] == "call":
			passive = la
	if roll < 12:
		return {"type": "fold"}
	if raise_la != null and roll >= 70:
		var lo: int = raise_la["min"]
		var hi: int = raise_la["max"]
		var r2: int = pol.next_below(10)
		var to: int = lo if r2 < 3 else (hi if r2 < 6 else lo + pol.next_below(hi - lo + 1))
		return {"type": raise_la["type"], "to": to}
	return {"type": passive["type"]}


func _illegal(A, B, pol) -> void:
	var before := _sig(A) if pol.next_below(5) == 0 else ""
	var seat: int = A.to_act
	var other: int = (seat + 1 + pol.next_below(A.n_seats() - 1)) % A.n_seats()
	var cases := [
		{"type": "call", "seat": other}, {"type": "raise", "seat": seat, "to": A.current_bet},
		{"type": "raise", "seat": seat, "to": A.stack(seat) + A.seats[seat]["bet"] + 1},
		{"type": "start_hand"}, {"type": "top_up", "seat": seat, "amount": 1},
		{"type": "raise", "seat": seat, "to": "x"}, {"type": "fold", "seat": -1}, {"type": 7},
	]
	if A.current_bet > A.seats[seat]["bet"]:
		cases.append({"type": "check", "seat": seat})
	var a: Dictionary = cases[pol.next_below(cases.size())]
	if str(a.get("type")) == "call" and other == seat:
		return
	var r: Dictionary = _both(A, B, a)
	if r["ok"]:
		_fail("illegal action accepted: %s" % str(a))
	_stat("illegal_refused")
	if before != "" and before != _sig(A):
		_fail("refused action changed state: %s" % str(a))


func _in_hand_chips(g) -> int:
	var n: int = g.chips.balance("pot")
	for i in g.n_seats():
		if g.seats[i]["in_hand"]:
			n += g.stack(i)
	return n


func _hold_inv(g) -> void:
	var c = g.chips
	if c.faults != 0:
		_fail("ledger fault")
		c.faults = 0
	if c.total() != c.opened - c.closed:
		_fail("chips not conserved: %d vs %d" % [c.total(), c.opened - c.closed])
	for k in c.balances:
		if c.balances[k] < 0:
			_fail("negative balance %s" % k)
	var committed := 0
	var seen := {}
	for c2 in g.board:
		seen[c2] = true
	for i in g.n_seats():
		var s: Dictionary = g.seats[i]
		if not s["in_hand"]:
			continue
		committed += s["total"]
		if g.phase == "betting":
			if s["hole"].size() != 2:
				_fail("hole size")
			for h in s["hole"]:
				if seen.has(h):
					_fail("duplicate card")
				seen[h] = true
			if s["all_in"] != (g.stack(i) == 0):
				_fail("all_in flag wrong at seat %d" % i)
			if s["bet"] > g.current_bet:
				_fail("bet above current bet")
	if g.phase == "betting":
		if committed != c.balance("pot"):
			_fail("pot %d != committed %d" % [c.balance("pot"), committed])
		if not g._needs_action(g.to_act):
			_fail("to_act %d does not need to act" % g.to_act)
		if g.board.size() != [0, 3, 4, 5][H.STREETS.find(g.street)]:
			_fail("board size on %s" % g.street)
	elif g.to_act != -1:
		_fail("to_act set between hands")


func _collect(v: Variant, out: Array, key: String = "") -> void:
	match typeof(v):
		TYPE_DICTIONARY:
			for k in v:
				_collect(v[k], out, String(k))
		TYPE_ARRAY:
			for x in v:
				if typeof(x) == TYPE_INT and key in ["hole", "board", "cards", "best", "dealer"]:
					out.append(x)
				else:
					_collect(x, out, key)


## Cards the seat must not know: others' unshown hole cards and the deck.
func _leak_check(g, seat: int, evts: Array) -> void:
	_stat("views_checked")
	var hidden := {}
	for i in g.n_seats():
		var s: Dictionary = g.seats[i]
		if i != seat and s["in_hand"] and not s["shown"]:
			for c in s["hole"]:
				hidden[c] = true
	for k in range(g.deck_pos, g.deck.size()):
		hidden[g.deck[k]] = true
	var seen := []
	var view: Dictionary = g.view_for(seat)
	var sent: Array = H.events_for(seat, evts)
	_collect(view, seen)
	_collect(sent, seen)
	for c in seen:
		if hidden.has(c):
			_fail("seat %d can see hidden card %d" % [seat, c])
			return
	# The live hand's seed never reaches a client before the hand ends.
	if g.phase == "betting" and g.hand_seed != "":
		if JSON.stringify(view).contains(g.hand_seed) or JSON.stringify(sent).contains(g.hand_seed):
			_fail("seat %d can see the live hand's seed" % seat)
			return
	for e in sent:
		if e["type"] == "seed":
			_fail("events_for passed a seed event")
			return
	if seat >= 0 and g.seats[seat]["in_hand"] and g.view_for(seat)["hole"] != g.seats[seat]["hole"]:
		_fail("seat %d missing its own cards" % seat)


# ======================================================== Blackjack

func _bj_run(total: int, seed: int) -> void:
	var done := 0
	var k := 0
	while done < total:
		var n := mini(500, total - done)
		_bj_session(seed + k, n, true)
		done += n
		k += 1


func _bj_session(seed: int, rounds: int, twin: bool) -> String:
	var pol = Rng.test_only_from_int(seed * 104729 + 7)
	var cfg := {"decks": [1, 2, 6, 8][pol.next_below(4)], "seats": 1 + pol.next_below(6),
		"min_bet": [1, 2, 5][pol.next_below(3)], "max_bet": 200, "penetration_pct": 50 + pol.next_below(46)}
	var srcB = Seq.new(seed)
	var A = BJ.new(cfg, Seq.new(seed))
	var B = BJ.new(cfg, srcB) if twin else null
	for i in A.seats.size():
		_both(A, B, {"type": "sit", "seat": i, "player": "p%d" % i, "buy_in": 500})
	var played := 0
	var guard := 0
	while played < rounds and guard < rounds * 3:
		guard += 1
		for i in A.seats.size():
			if A.stack(i) < A.cfg["min_bet"] * 4 or pol.next_below(200) == 0:
				_both(A, B, {"type": "leave", "seat": i})
				_both(A, B, {"type": "sit", "seat": i, "player": "p%d" % i, "buy_in": 100 + pol.next_below(900)})
			if pol.next_below(10) < 9:
				var mx := mini(A.cfg["max_bet"], A.stack(i))
				var amt: int = A.cfg["min_bet"] + pol.next_below(maxi(1, mx - A.cfg["min_bet"] + 1))
				if amt % 2 == 0 and pol.next_below(2) == 0:
					amt = maxi(A.cfg["min_bet"], amt - 1)  # plenty of odd bets for the 3:2 rounding
				if not _both(A, B, {"type": "bet", "seat": i, "amount": amt})["ok"]:
					_fail("bet refused")
		var pre := []
		for i in A.seats.size():
			pre.append([A.stack(i) + int(A.seats[i]["bet"]), int(A.seats[i]["bet"])])
		if not _both(A, B, {"type": "deal"})["ok"]:
			continue
		played += 1
		_stat("rounds")
		var steps := 0
		while A.phase != "betting":
			steps += 1
			if steps > 200:
				_fail("round did not finish")
				break
			if twin and pol.next_below(8) == 0:
				B = _rt(B, BJ, srcB)
			if A.phase == "insurance":
				for i in A.seats.size():
					var la: Array = A.legal_actions(i)
					if not la.is_empty():
						var mx: int = la[0]["max"]
						var amt: int = 0 if pol.next_below(2) == 0 else pol.next_below(mx + 1)
						if amt > 0:
							_stat("insurance")
						if not _both(A, B, {"type": "insurance", "seat": i, "amount": amt})["ok"]:
							_fail("insurance refused")
						break
			else:
				var seat: int = A.turn_seat
				var la: Array = A.legal_actions(seat)
				if la.is_empty():
					_fail("no blackjack actions")
					break
				var w := {"hit": 30, "stand": 30, "double": 15, "split": 25}
				var tot := 0
				for x in la:
					tot += w[x["type"]]
				var roll: int = pol.next_below(tot)
				var pick: String = la[0]["type"]
				for x in la:
					roll -= w[x["type"]]
					if roll < 0:
						pick = x["type"]
						break
				_stat(pick)
				if not _both(A, B, {"type": pick, "seat": seat})["ok"]:
					_fail("legal %s refused" % pick)
				if pol.next_below(50) == 0:
					var other: int = (A.turn_seat + 1) % A.seats.size()
					if A.phase == "play" and other != A.turn_seat and _both(A, B, {"type": "hit", "seat": other})["ok"]:
						_fail("out-of-turn hit accepted")
			_bj_inv(A)
			if pol.next_below(6) == 0:
				var s: int = pol.next_below(A.seats.size())
				var v: Dictionary = A.view_for(s)
				if A.phase != "betting" and not A.hole_shown and v["dealer"][1] != -1:
					_fail("hole card leaked")
		_bj_inv(A)
		if twin:
			_export_bj(A, pre)
		for s in A.seats:
			for h in s["hands"]:
				_stat("res_" + h["result"])
		if twin:
			if _sig(A) != _sig(B):
				_fail("blackjack twin diverged in round %d" % A.round_no)
				B = _rt(A, BJ, srcB)
			A.chips.trim(A.chips.seq)
			B.chips.trim(B.chips.seq)
	if played < rounds:
		_fail("blackjack session played %d" % played)
	A.chips.trim(A.chips.seq)
	return _sig(A)


func _bj_inv(g) -> void:
	var c = g.chips
	if c.faults != 0:
		_fail("bj ledger fault")
		c.faults = 0
	if c.total() != c.opened - c.closed:
		_fail("bj chips not conserved")
	for k in c.balances:
		if k != "house" and c.balances[k] < 0:
			_fail("bj negative balance %s" % k)
	var in_table := 0
	for s in g.seats:
		in_table += s["bet"]
		if g.phase != "betting":
			for h in s["hands"]:
				in_table += h["bet"]
				for card in h["cards"]:
					if card < 0 or card > 51:
						_fail("bad card")
			if g.phase == "insurance":
				in_table += s["insurance"]
	if in_table != c.balance("table"):
		_fail("table %d != wagers %d (%s)" % [c.balance("table"), in_table, g.phase])
	if g.phase == "play":
		var h: Dictionary = g.seats[g.turn_seat]["hands"][g.turn_hand]
		if h["done"] or BJ.total(h["cards"])[0] > 21:
			_fail("turn on a finished hand")


# ======================================================== Roulette

func _rou_run(total: int, seed: int) -> void:
	var done := 0
	var k := 0
	while done < total:
		var n := mini(1000, total - done)
		_rou_session(seed + k, n, true)
		done += n
		k += 1


func _rou_session(seed: int, spins: int, twin: bool) -> String:
	var pol = Rng.test_only_from_int(seed * 31337 + 1)
	var cfg := {"wheel": "american" if pol.next_below(2) == 0 else "european", "seats": 1 + pol.next_below(6), "max_bet": 100}
	var srcB = Seq.new(seed)
	var A = R.new(cfg, Seq.new(seed))
	var B = R.new(cfg, srcB) if twin else null
	var kinds := R.INSIDE + R.OUTSIDE
	for i in A.seats.size():
		_both(A, B, {"type": "sit", "seat": i, "player": "p%d" % i, "buy_in": 1000})
	for sp in spins:
		for i in A.seats.size():
			if A.chips.balance("seat%d" % i) < 10:
				_both(A, B, {"type": "leave", "seat": i})
				_both(A, B, {"type": "sit", "seat": i, "player": "p%d" % i, "buy_in": 1000})
			for b in pol.next_below(5):
				var kind: String = kinds[pol.next_below(kinds.size())]
				var a := {"type": "bet", "seat": i, "kind": kind, "amount": 1 + pol.next_below(20)}
				if kind in R.INSIDE:
					var keys: Array = A._spots[kind].keys()
					var nums := []
					for x in String(keys[pol.next_below(keys.size())]).split(","):
						nums.append(int(x))
					a["numbers"] = nums
				elif kind == "dozen" or kind == "column":
					a["index"] = 1 + pol.next_below(3)
				var r: Dictionary = _both(A, B, a)
				if not r["ok"] and r["error"] != "insufficient_chips":
					_fail("roulette bet refused: %s %s" % [str(a), r["error"]])
				if r["ok"]:
					_stat(kind)
			if pol.next_below(100) == 0:
				_both(A, B, {"type": "clear", "seat": i})
		if twin and pol.next_below(5) == 0:
			B = _rt(B, R, srcB)
		var res: Dictionary = _both(A, B, {"type": "spin"})
		for e in res["raw_events"]:
			if e["type"] == "spin":
				if e["result"] == 0 or e["result"] == 37:
					_stat("pocket_" + e["label"])
		var c = A.chips
		if c.faults != 0 or c.total() != c.opened - c.closed or c.balance("table") != 0:
			_fail("roulette chips wrong after spin")
		for k in c.balances:
			if k != "house" and c.balances[k] < 0:
				_fail("roulette negative balance")
		if twin:
			if _sig(A) != _sig(B):
				_fail("roulette twin diverged at spin %d" % A.spins)
				B = _rt(A, R, srcB)
			A.chips.trim(A.chips.seq)
			B.chips.trim(B.chips.seq)
	_stat("spins", spins)
	A.chips.trim(A.chips.seq)
	return _sig(A)


# ======================================================== Oracle export

## One Hold'em hand, rebuilt from its raw event log alone (no engine state):
## what each seat put in and got back, who folded, the cards, the payouts.
func _export_pots(g, evts: Array) -> void:
	if _pots_f == null:
		return
	var h := {"n": g.n_seats(), "button": -1, "commit": {}, "uncalled": {}, "folded": [], "hole": {},
		"board": [], "won": {}}
	for e in evts:
		match String(e["type"]):
			"hand_start":
				h["button"] = e["button"]
			"post", "commit":
				h["commit"][str(e["seat"])] = int(h["commit"].get(str(e["seat"]), 0)) + int(e["amount"])
			"uncalled":
				h["uncalled"][str(e["seat"])] = int(h["uncalled"].get(str(e["seat"]), 0)) + int(e["amount"])
			"fold":
				h["folded"].append(e["seat"])
			"hole":
				h["hole"][str(e["seat"])] = e["cards"]
			"flop", "turn", "river":
				# "turn" is also the to-act notice; street events carry the board.
				if e.has("board"):
					h["board"] = e["board"]
			"transfer":
				if e["reason"] == "pot":
					var k := String(e["to"]).substr(4)
					h["won"][k] = int(h["won"].get(k, 0)) + int(e["amount"])
	_pots_f.store_line(JSON.stringify(h))


## One blackjack round: stacks before (bet included) and after, the original
## bet, insurance, every hand's cards and final bet, the dealer's cards.
func _export_bj(g, pre: Array) -> void:
	if _bj_f == null:
		return
	var seats := []
	for i in g.seats.size():
		var s: Dictionary = g.seats[i]
		if s["hands"].is_empty():
			continue
		var hands := []
		for hd in s["hands"]:
			hands.append({"cards": hd["cards"], "bet": hd["bet"], "split": hd["split"], "doubled": hd["doubled"],
				"split_aces": hd["split_aces"]})
		seats.append({"seat": i, "before": pre[i][0], "orig": pre[i][1], "after": g.stack(i),
			"ins": s["insurance"], "hands": hands})
	_bj_f.store_line(JSON.stringify({"dealer": g.dealer, "seats": seats}))
