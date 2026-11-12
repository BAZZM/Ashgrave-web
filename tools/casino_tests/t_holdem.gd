extends RefCounted
## Hold'em scenarios: min-raise, short all-in, side pots, odd chip, heads-up,
## leaving mid-hand, antes, short blinds, errors, the seat view.

const NAME := "holdem"
const H := preload("res://scripts/casino/holdem.gd")
const Cards := preload("res://scripts/casino/cards.gd")
const Rng := preload("res://scripts/casino/rng.gd")
const Seq := preload("res://tests/seed_seq.gd")

var t


func _table(stacks: Array, extra := {}) -> RefCounted:
	var cfg := {"sb": 1, "bb": 2, "min_buy_in": 1, "max_buy_in": 100000}
	for k in extra:
		cfg[k] = extra[k]
	var g = H.new(cfg, Seq.new(11))
	for i in stacks.size():
		if stacks[i] > 0:
			g.apply({"type": "sit", "seat": i, "player": "p%d" % i, "buy_in": stacks[i]})
	return g


## After start_hand: set hole cards and the coming board (burns included).
func _rig(g, holes: Dictionary, board: String) -> void:
	var used := {}
	for s in holes:
		g.seats[s]["hole"] = Cards.parse_list(holes[s])
		for c in g.seats[s]["hole"]:
			used[c] = true
	var b := Cards.parse_list(board)
	for c in b:
		used[c] = true
	var rest := []
	for c in 52:
		if not used.has(c):
			rest.append(c)
	var d := [rest.pop_back(), b[0], b[1], b[2], rest.pop_back(), b[3], rest.pop_back(), b[4]]
	d.append_array(rest)
	g.deck = d
	g.deck_pos = 0


func _do(g, a: Dictionary, label: String) -> Dictionary:
	var r: Dictionary = g.apply(a)
	t.check(r["ok"], "%s: %s -> %s" % [label, str(a), r.get("error", "ok")])
	return r


func _legal(g, seat: int, type: String) -> Variant:
	for la in g.legal_actions(seat):
		if la["type"] == type:
			return la
	return null


func _stacks(g) -> Array:
	var out := []
	var used := 0
	for i in g.n_seats():
		if g.seats[i]["player"] != "":
			used = i + 1
	for i in used:
		out.append(g.stack(i))
	return out


func _awards(evts: Array) -> Array:
	var out := []
	for e in evts:
		if e["type"] == "award":
			out.append(e["amount"])
	return out


func run(tt) -> void:
	t = tt
	_min_raise()
	_short_all_in()
	_cumulative_short()
	_side_pots()
	_uncalled()
	_odd_chip()
	_heads_up()
	_leave()
	_antes_and_short_blinds()
	_errors()
	_view()
	_reraise_exact_min()
	_folded_contributor()
	_leaver_uncalled()
	_seat_rules()
	_seeds()
	_client_safe()


func _min_raise() -> void:
	var g = _table([1000, 1000, 1000])
	_do(g, {"type": "start_hand"}, "min-raise")
	t.eq([g.button, g.sb_seat, g.bb_seat, g.to_act], [0, 1, 2, 0], "3-handed positions")
	t.eq(_legal(g, 0, "raise"), {"type": "raise", "min": 4, "max": 1000}, "preflop min raise to 2bb")
	_do(g, {"type": "raise", "seat": 0, "to": 6}, "open")
	t.eq(g.apply({"type": "raise", "seat": 1, "to": 9})["error"], "bad_amount", "raise to 9 is below min 10")
	t.eq(_legal(g, 1, "raise")["min"], 10, "min re-raise = last raise size")
	_do(g, {"type": "raise", "seat": 1, "to": 10}, "min re-raise")
	_do(g, {"type": "raise", "seat": 2, "to": 30}, "3-bet")
	t.eq(_legal(g, 0, "raise")["min"], 50, "min after a 20 raise is 50")
	_do(g, {"type": "call", "seat": 0}, "call")
	_do(g, {"type": "call", "seat": 1}, "call")
	t.eq(g.street, "flop", "flop dealt")
	t.eq(g.board.size(), 3, "three on the flop")
	t.eq(g.chips.balance("pot"), 90, "pot 90")
	t.eq(g.to_act, 1, "first live left of button acts first")
	t.eq(_legal(g, 1, "bet"), {"type": "bet", "min": 2, "max": 970}, "postflop min bet is the big blind")
	t.eq(g.apply({"type": "bet", "seat": 1, "to": 1})["error"], "bad_amount", "bet below bb")
	_do(g, {"type": "bet", "seat": 1, "to": 2}, "min bet")
	t.eq(_legal(g, 2, "raise")["min"], 4, "min raise over a min bet")
	_do(g, {"type": "raise", "seat": 2, "to": 970}, "all-in raise")
	t.eq(_legal(g, 0, "call")["amount"], 970, "call all-in")
	t.eq(_legal(g, 0, "raise"), null, "cannot raise: stack only covers the call")


func _short_all_in() -> void:
	var g = _table([1000, 1000, 150])
	_do(g, {"type": "start_hand"}, "short")
	_do(g, {"type": "call", "seat": 0}, "limp")
	_do(g, {"type": "call", "seat": 1}, "complete")
	_do(g, {"type": "check", "seat": 2}, "bb checks")
	t.eq(g.street, "flop", "flop")
	_do(g, {"type": "bet", "seat": 1, "to": 100}, "bet 100")
	t.eq(_legal(g, 2, "raise"), {"type": "raise", "min": 148, "max": 148}, "short stack may only go all-in for less")
	_do(g, {"type": "raise", "seat": 2, "to": 148}, "short all-in")
	t.check(g.seats[2]["all_in"], "seat 2 all-in")
	t.eq(_legal(g, 0, "raise"), {"type": "raise", "min": 248, "max": 998}, "seat 0 has not acted: may raise, min 148+100")
	_do(g, {"type": "call", "seat": 0}, "seat 0 calls 148")
	t.eq(g.to_act, 1, "back to the bettor")
	t.eq(_legal(g, 1, "raise"), null, "short all-in does not reopen betting")
	t.eq(_legal(g, 1, "call")["amount"], 48, "bettor may call the extra 48")
	t.eq(g.apply({"type": "raise", "seat": 1, "to": 300})["error"], "illegal_action", "raise refused")
	_do(g, {"type": "call", "seat": 1}, "call 48")
	t.eq(g.street, "turn", "turn after call")


func _cumulative_short() -> void:
	var g = _table([1000, 1000, 150, 210])
	_do(g, {"type": "start_hand"}, "cumulative")
	_do(g, {"type": "call", "seat": 3}, "")
	_do(g, {"type": "call", "seat": 0}, "")
	_do(g, {"type": "call", "seat": 1}, "")
	_do(g, {"type": "check", "seat": 2}, "")
	_do(g, {"type": "bet", "seat": 1, "to": 100}, "bet 100")
	_do(g, {"type": "raise", "seat": 2, "to": 148}, "short all-in 148")
	_do(g, {"type": "raise", "seat": 3, "to": 208}, "short all-in 208")
	t.eq(_legal(g, 0, "raise")["min"], 308, "min raise stays the last full raise (100)")
	_do(g, {"type": "call", "seat": 0}, "call 208")
	t.check(_legal(g, 1, "raise") != null, "two short all-ins adding to a full raise reopen betting")


func _side_pots() -> void:
	var g = _table([50, 150, 300])
	_do(g, {"type": "start_hand"}, "side pots")
	_rig(g, {0: "As Ah", 1: "Ks Kh", 2: "Qs Qh"}, "2c 7d 9h 3s 4c")
	_do(g, {"type": "raise", "seat": 0, "to": 50}, "all-in 50")
	_do(g, {"type": "raise", "seat": 1, "to": 150}, "all-in 150")
	t.eq(_legal(g, 2, "raise"), null, "no raise when nobody can call it")
	var p: Array = g.pots()
	t.eq(p, [{"amount": 6, "eligible": [0, 1, 2]}, {"amount": 96, "eligible": [0, 1]}, {"amount": 100, "eligible": [1]}],
		"pots before the big blind calls")
	var r := _do(g, {"type": "call", "seat": 2}, "call 150")
	t.eq(_awards(r["raw_events"]), [150, 200], "main 150, side 200")
	t.eq(_stacks(g), [150, 200, 150], "aces win main, kings win side")
	t.eq(g.phase, "waiting", "hand over")
	t.eq(g.chips.balance("pot"), 0, "pot empty")
	# Same, kings beat everyone: both pots to seat 1.
	g = _table([50, 150, 300])
	_do(g, {"type": "start_hand"}, "side pots 2")
	_rig(g, {0: "Qs Qh", 1: "As Ah", 2: "Ks Kh"}, "2c 7d 9h 3s 4c")
	_do(g, {"type": "raise", "seat": 0, "to": 50}, "")
	_do(g, {"type": "raise", "seat": 1, "to": 150}, "")
	_do(g, {"type": "call", "seat": 2}, "")
	t.eq(_stacks(g), [0, 350, 150], "big stack second-best keeps the rest")
	# Four-way, everyone all-in or calling (no folder; see _folded_contributor).
	g = _table([1000, 100, 300, 600])
	_do(g, {"type": "start_hand"}, "4-way")
	_rig(g, {0: "2s 2h", 1: "As Ah", 2: "Ks Kh", 3: "Qs Qh"}, "3c 7d 9h Ts 4c")
	_do(g, {"type": "raise", "seat": 3, "to": 600}, "seat3 all-in 600")
	_do(g, {"type": "call", "seat": 0}, "seat0 calls 600")
	_do(g, {"type": "call", "seat": 1}, "seat1 all-in 100")
	_do(g, {"type": "call", "seat": 2}, "seat2 all-in 300")
	t.eq(g.phase, "waiting", "ran out")
	# main 400 (A), 600 side among 0,2,3 -> K wins 600, 600 among 0,3 -> Q wins.
	t.eq(_stacks(g), [400, 400, 600, 600], "four-way side pots, no folder")


func _uncalled() -> void:
	var g = _table([1000, 100])
	_do(g, {"type": "start_hand"}, "uncalled")
	_rig(g, {0: "2s 3h", 1: "As Ah"}, "Kc 7d 9h Ts 4c")
	_do(g, {"type": "raise", "seat": 0, "to": 500}, "")
	var r := _do(g, {"type": "call", "seat": 1}, "")
	var back := 0
	for e in r["raw_events"]:
		if e["type"] == "uncalled":
			back = e["amount"]
	t.eq(back, 400, "uncalled 400 returned")
	t.eq(_stacks(g), [900, 200], "heads-up all-in result")


func _odd_chip() -> void:
	var g = _table([100, 100, 100])
	_do(g, {"type": "start_hand"}, "odd chip")
	_rig(g, {0: "2c 3c", 1: "4d 5d", 2: "2d 3d"}, "As Ks Qs Js Ts")
	_do(g, {"type": "call", "seat": 0}, "")
	_do(g, {"type": "fold", "seat": 1}, "")
	_do(g, {"type": "check", "seat": 2}, "")
	for k in 3:
		t.eq(g.to_act, 2, "seat 2 first postflop when seat 1 folded")
		_do(g, {"type": "check", "seat": 2}, "")
		_do(g, {"type": "check", "seat": 0}, "")
	t.eq(g.phase, "waiting", "showdown done")
	t.eq(_stacks(g), [100, 99, 101], "pot of 5 split: odd chip to first winner left of button")


func _heads_up() -> void:
	var g = _table([100, 100, 100])
	g.apply({"type": "sit_out", "seat": 2})
	_do(g, {"type": "start_hand"}, "heads-up")
	t.eq([g.button, g.sb_seat, g.bb_seat], [0, 0, 1], "heads-up: button is small blind")
	t.eq(g.to_act, 0, "button acts first preflop")
	t.check(not g.seats[2]["in_hand"], "sitting-out seat not dealt")
	_do(g, {"type": "call", "seat": 0}, "")
	_do(g, {"type": "check", "seat": 1}, "")
	t.eq(g.to_act, 1, "big blind acts first after the flop")
	_do(g, {"type": "bet", "seat": 1, "to": 2}, "")
	_do(g, {"type": "fold", "seat": 0}, "")
	t.eq(_stacks(g), [98, 102, 100], "heads-up result")
	_do(g, {"type": "start_hand"}, "heads-up 2")
	t.eq([g.button, g.sb_seat, g.bb_seat, g.to_act], [1, 1, 0, 1], "button moves, still posts small")
	_do(g, {"type": "fold", "seat": 1}, "")
	g.apply({"type": "sit_in", "seat": 2})
	_do(g, {"type": "start_hand"}, "back to 3")
	t.eq([g.button, g.sb_seat, g.bb_seat, g.to_act], [2, 0, 1, 2], "three-handed again")


func _leave() -> void:
	var g = _table([100, 100, 100])
	_do(g, {"type": "start_hand"}, "leave")
	_do(g, {"type": "leave", "seat": 1}, "small blind leaves out of turn")
	t.check(g.seats[1]["folded"], "leaving folds")
	t.eq(g.to_act, 0, "turn unchanged")
	t.eq(g.seats[1]["player"], "p1", "seat held until the hand ends")
	t.eq(g.apply({"type": "leave", "seat": 1})["error"], "already_leaving", "leave twice")
	_do(g, {"type": "fold", "seat": 0}, "")
	t.eq(g.phase, "waiting", "big blind wins")
	t.eq(g.seats[1]["player"], "", "seat freed")
	t.eq(g.chips.closed, 99, "leaver cashed out 99")
	t.eq(g.stack(2), 101, "blind won")
	t.eq(g.chips.total(), g.chips.opened - g.chips.closed, "conserved")
	# Leaving on your turn passes the action; leaving to one player ends the hand.
	g = _table([100, 100, 100])
	_do(g, {"type": "start_hand"}, "leave 2")
	_do(g, {"type": "leave", "seat": 0}, "to-act player leaves")
	t.eq(g.to_act, 1, "action passed on")
	_do(g, {"type": "leave", "seat": 2}, "")
	t.eq(g.phase, "waiting", "last player standing wins")
	# SB 1 vs BB 2: the big blind left, so its uncalled 1 goes back to it
	# (cashed out 99); the small blind wins 1 (was 102 before the fix).
	t.eq(g.stack(1), 101, "small blind takes the called part of the pot")
	t.eq(g.chips.closed, 100 + 99, "button cashed 100, big blind 98 + its uncalled 1")
	# An all-in player who leaves plays on.
	g = _table([50, 1000, 1000])
	_do(g, {"type": "start_hand"}, "leave all-in")
	_rig(g, {0: "As Ah", 1: "Ks Kh", 2: "Qs Qh"}, "2c 7d 9h 3s 4c")
	_do(g, {"type": "raise", "seat": 0, "to": 50}, "")
	_do(g, {"type": "leave", "seat": 0}, "all-in leaves")
	t.check(not g.seats[0]["folded"], "all-in hand stays live")
	_do(g, {"type": "call", "seat": 1}, "")
	_do(g, {"type": "call", "seat": 2}, "")
	for k in 3:
		_do(g, {"type": "check", "seat": 1}, "")
		_do(g, {"type": "check", "seat": 2}, "")
	t.eq(g.phase, "waiting", "hand finished")
	t.eq(g.chips.closed, 150, "leaver cashed out the main pot")
	# Not in a hand: leave is immediate.
	g = _table([100, 100, 100])
	_do(g, {"type": "leave", "seat": 1}, "")
	t.eq(g.seats[1]["player"], "", "immediate leave")


func _antes_and_short_blinds() -> void:
	var g = _table([100, 100, 100], {"ante": 1})
	_do(g, {"type": "start_hand"}, "antes")
	t.eq(g.chips.balance("pot"), 6, "3 antes + blinds")
	t.eq(g.current_bet, 2, "to call 2")
	t.eq(_legal(g, 0, "call")["amount"], 2, "antes are not part of the bet")
	g = _table([100, 100, 1])
	_do(g, {"type": "start_hand"}, "short bb")
	t.check(g.seats[2]["all_in"], "bb all-in for 1")
	t.eq(_legal(g, 0, "call")["amount"], 2, "still call the full big blind")
	_do(g, {"type": "call", "seat": 0}, "")
	_do(g, {"type": "call", "seat": 1}, "")
	t.eq(g.street, "flop", "bb all-in needs no option")
	t.eq(g.pots(), [{"amount": 3, "eligible": [0, 1, 2]}, {"amount": 2, "eligible": [0, 1]}], "side pot from short blind")
	# Everyone all-in from the blinds runs the board out.
	g = _table([1, 2])
	var r := _do(g, {"type": "start_hand"}, "blinds all-in")
	t.eq(g.phase, "waiting", "ran out at once")
	t.eq(g.chips.total(), 3, "chips conserved")
	var shows: int = r["raw_events"].filter(func(e): return e["type"] == "show").size()
	t.eq(shows, 2, "both hands shown")


func _errors() -> void:
	var g = _table([100, 100, 100])
	t.eq(g.apply({"type": "check", "seat": 0})["error"], "no_hand", "no hand yet")
	_do(g, {"type": "start_hand"}, "errors")
	var before := JSON.stringify(g.to_dict())
	var cases := [
		[null, "bad_action"], [[1], "bad_action"], [{"seat": 0}, "bad_action"],
		[{"type": "start_hand"}, "hand_in_progress"], [{"type": "call", "seat": 1}, "not_your_turn"],
		[{"type": "check", "seat": 0}, "illegal_action"], [{"type": "raise", "seat": 0}, "bad_amount"],
		[{"type": "raise", "seat": 0, "to": "lots"}, "bad_amount"], [{"type": "raise", "seat": 0, "to": 4.5}, "bad_amount"],
		[{"type": "raise", "seat": 0, "to": 101}, "bad_amount"], [{"type": "raise", "seat": 0, "to": 3}, "bad_amount"],
		[{"type": "call", "seat": 7}, "bad_seat"], [{"type": "call", "seat": "0"}, "bad_seat"],
		[{"type": "call", "seat": 4}, "empty_seat"], [{"type": "dance", "seat": 0}, "unknown_action"],
		[{"type": "top_up", "seat": 0, "amount": 5}, "in_hand"],
		[{"type": "sit", "seat": 0, "player": "x", "buy_in": 50}, "seat_taken"],
		[{"type": "sit", "seat": 3, "player": "x", "buy_in": 0}, "bad_amount"],
		[{"type": "sit", "seat": 3, "player": 5, "buy_in": 50}, "bad_player"],
	]
	for c in cases:
		var r: Dictionary = g.apply(c[0])
		t.check(not r["ok"], "rejected %s" % str(c[0]))
		t.eq(r.get("error", ""), c[1], "error code for %s" % str(c[0]))
	t.eq(JSON.stringify(g.to_dict()), before, "rejections leave state untouched")
	var g2 = _table([100])
	t.eq(g2.apply({"type": "start_hand"})["error"], "not_enough_players", "one player")


func _view() -> void:
	var g = _table([100, 100, 100])
	_do(g, {"type": "start_hand"}, "view")
	for s in 3:
		var v: Dictionary = g.view_for(s)
		t.eq(v["hole"], g.seats[s]["hole"], "own cards in view %d" % s)
		for o in 3:
			if o != s:
				t.eq(v["seats"][o]["hole"], [], "no other hole cards in view %d" % s)
		t.check(not v.has("deck") and not v.has("rng") and not v.has("history"), "no deck/rng/history in view")
	t.eq(g.view_for(-1)["hole"], [], "spectator sees no hole cards")
	t.eq(g.view_for(0)["legal"].size(), 3, "to-act seat gets its legal actions")
	t.eq(g.view_for(1)["legal"], [], "others get none")
	var evs: Array = H.events_for(1, g.chips.events)
	for e in evs:
		if e["type"] == "hole" and e["seat"] != 1:
			t.eq(e["cards"], [], "event filter hides seat %d" % e["seat"])
	# Hand history records the hand.
	_do(g, {"type": "fold", "seat": 0}, "")
	_do(g, {"type": "fold", "seat": 1}, "")
	t.eq(g.audit_history.size(), 1, "hand history kept")
	t.eq(g.audit_history[0]["actions"].size(), 2, "two actions recorded")
	t.eq(g.audit_history[0]["awards"][0]["winners"], [2], "winner recorded")


## A player who has acted may re-raise when facing exactly a minimum raise.
func _reraise_exact_min() -> void:
	var g = _table([1000, 1000, 1000])
	_do(g, {"type": "start_hand"}, "exact min")
	_do(g, {"type": "call", "seat": 0}, "button limps 2")
	_do(g, {"type": "call", "seat": 1}, "sb completes")
	var rr := _do(g, {"type": "raise", "seat": 2, "to": 4}, "bb min-raises by exactly 2")
	var full_flag = null
	for e in rr["raw_events"]:
		if e["type"] == "raise":
			full_flag = e["full"]
	t.eq(full_flag, true, "an exact minimum raise is a full raise")
	t.eq(g.to_act, 0, "back to the limper")
	# Faced 2 more = the full minimum raise: betting is reopened.
	t.eq(_legal(g, 0, "raise"), {"type": "raise", "min": 6, "max": 1000}, "limper may re-raise an exact min-raise")
	_do(g, {"type": "raise", "seat": 0, "to": 6}, "re-raise to 6")
	t.eq(_legal(g, 1, "raise"), {"type": "raise", "min": 8, "max": 1000}, "sb may re-raise too")
	# A postflop exact min bet + exact min raise reopens to the first bettor.
	_do(g, {"type": "call", "seat": 1}, "")
	_do(g, {"type": "call", "seat": 2}, "")
	t.eq(g.street, "flop", "flop")
	_do(g, {"type": "bet", "seat": 1, "to": 2}, "min bet")
	_do(g, {"type": "raise", "seat": 2, "to": 4}, "min raise")
	_do(g, {"type": "call", "seat": 0}, "")
	t.eq(_legal(g, 1, "raise"), {"type": "raise", "min": 6, "max": 994}, "first bettor may re-raise an exact min-raise")


## Side pots with a folded player whose chips reach above the smallest all-in.
## Hand-computed: totals s0 300, s1 100 (all-in), s2 300 (all-in), s3 200 (folded).
## Main (100 level): 100 x 4 = 400, s0 s1 s2 eligible -> s1 (aces).
## Side (300 level): s0 200 + s2 200 + s3 100 = 500, s0 s2 eligible -> s2 (kings).
func _folded_contributor() -> void:
	var g = _table([1000, 100, 300, 1000])
	_do(g, {"type": "start_hand"}, "folded contributor")
	_rig(g, {0: "2s 2h", 1: "As Ah", 2: "Ks Kh", 3: "Qs Qh"}, "3c 7d 9h Ts 4c")
	_do(g, {"type": "raise", "seat": 3, "to": 200}, "utg raises 200")
	_do(g, {"type": "call", "seat": 0}, "button calls 200")
	_do(g, {"type": "call", "seat": 1}, "sb calls all-in 100")
	_do(g, {"type": "raise", "seat": 2, "to": 300}, "bb short all-in 300")
	t.eq(g.to_act, 3, "raiser to act")
	_do(g, {"type": "fold", "seat": 3}, "raiser folds with 200 in")
	# Button has 200 in so far: levels 100, 200, 300; the folder's 200 is
	# split 100 / 100 across the first two.
	t.eq(g.pots(), [{"amount": 400, "eligible": [0, 1, 2]}, {"amount": 300, "eligible": [0, 2]},
		{"amount": 100, "eligible": [2]}], "pots before the last call")
	var r := _do(g, {"type": "call", "seat": 0}, "button calls 300")
	t.eq(g.phase, "waiting", "ran out")
	t.eq(_awards(r["raw_events"]), [400, 500], "main 400, side 500")
	t.eq(_stacks(g), [700, 400, 500, 800], "aces win main, kings win side, folder loses 200")


func _closed_for(g, seat: int) -> int:
	var amt := -1
	for e in g.chips.events:
		if e["type"] == "leave" and e["seat"] == seat:
			amt = e["cash_out"]
	return amt


## Chips nobody called go back to a player who left (and so folded).
func _leaver_uncalled() -> void:
	# The review's case: heads-up 1/2, 1000 each; button raises to 500, then leaves.
	var g = _table([1000, 1000])
	_do(g, {"type": "start_hand"}, "hu leaver")
	_do(g, {"type": "raise", "seat": 0, "to": 500}, "raise 500")
	var r := _do(g, {"type": "leave", "seat": 0}, "raiser leaves")
	t.eq(_awards(r["raw_events"]), [4], "big blind wins only the called 4")
	t.eq(g.stack(1), 1002, "big blind +2")
	t.eq(_closed_for(g, 0), 998, "leaver cashes out 998 (498 uncalled back)")
	t.eq(g.chips.total(), g.chips.opened - g.chips.closed, "conserved")
	# Multi-way: leaver is the last aggressor, the blinds still to act and fold.
	g = _table([1000, 1000, 1000, 1000])
	_do(g, {"type": "start_hand"}, "4-way leaver")
	_do(g, {"type": "raise", "seat": 3, "to": 100}, "utg raises 100")
	_do(g, {"type": "leave", "seat": 3}, "utg leaves")
	t.eq(_legal(g, 0, "call")["amount"], 100, "the leaver's bet still stands")
	_do(g, {"type": "fold", "seat": 0}, "")
	r = _do(g, {"type": "fold", "seat": 1}, "")
	t.eq(_awards(r["raw_events"]), [5], "big blind wins 2 + 1 + the leaver's called 2")
	t.eq(_stacks(g), [1000, 999, 1003], "stacks (seat 3 gone)")
	t.eq(_closed_for(g, 3), 998, "leaver gets 98 uncalled back")
	# Leaver's bet is called by one player, who then raises; nobody calls that.
	g = _table([1000, 1000, 1000, 1000])
	_do(g, {"type": "start_hand"}, "4-way leaver 2")
	_do(g, {"type": "raise", "seat": 3, "to": 100}, "")
	_do(g, {"type": "leave", "seat": 3}, "")
	_do(g, {"type": "raise", "seat": 0, "to": 300}, "button raises over the leaver")
	_do(g, {"type": "fold", "seat": 1}, "")
	r = _do(g, {"type": "fold", "seat": 2}, "")
	t.eq(_stacks(g), [1103, 999, 998], "button gets 200 uncalled back and wins 1 + 2 + 100")
	t.eq(_closed_for(g, 3), 900, "the leaver's 100 was called")
	# Leaver's bet called by a player behind, then the rest fold: no refund.
	g = _table([1000, 1000, 1000, 1000])
	_do(g, {"type": "start_hand"}, "4-way leaver 3")
	_do(g, {"type": "raise", "seat": 3, "to": 100}, "")
	_do(g, {"type": "call", "seat": 0}, "")
	_do(g, {"type": "leave", "seat": 3}, "")
	_do(g, {"type": "fold", "seat": 1}, "")
	_do(g, {"type": "fold", "seat": 2}, "")
	t.eq(_stacks(g), [1103, 999, 998], "caller wins 100 + 100 + 3")
	t.eq(_closed_for(g, 3), 900, "called leaver gets nothing back")
	# All-in leaver who is the top bettor; everyone else folds.
	g = _table([300, 1000, 1000])
	_do(g, {"type": "start_hand"}, "all-in leaver")
	_do(g, {"type": "raise", "seat": 0, "to": 300}, "button all-in 300")
	_do(g, {"type": "leave", "seat": 0}, "")
	_do(g, {"type": "fold", "seat": 1}, "")
	_do(g, {"type": "fold", "seat": 2}, "")
	t.eq(_closed_for(g, 0), 303, "all-in leaver: 298 uncalled back + the blinds")
	# Big blind leaves preflop after the button raised: raise is uncalled.
	g = _table([1000, 1000, 1000])
	_do(g, {"type": "start_hand"}, "bb leaver")
	_do(g, {"type": "raise", "seat": 0, "to": 50}, "")
	_do(g, {"type": "fold", "seat": 1}, "")
	_do(g, {"type": "leave", "seat": 2}, "bb leaves facing a raise")
	t.eq(_stacks(g), [1003, 999], "button: 48 uncalled back, wins 1 + 2")
	t.eq(_closed_for(g, 2), 998, "big blind loses its blind")
	# Heads-up: the button (small blind) leaves before acting.
	g = _table([1000, 1000])
	_do(g, {"type": "start_hand"}, "sb leaver")
	_do(g, {"type": "leave", "seat": 0}, "")
	t.eq(g.stack(1), 1001, "big blind: 1 uncalled back, wins the small blind")
	t.eq(_closed_for(g, 0), 999, "small blind loses 1")


func _seat_rules() -> void:
	var g = _table([100, 100])
	t.eq(g.apply({"type": "sit", "seat": 2, "player": "p0", "buy_in": 100}).get("error", ""), "player_seated",
		"one player cannot hold two seats")
	_do(g, {"type": "sit", "seat": 2, "player": "p2", "buy_in": 100}, "another name may sit")
	# Top-up must leave the stack inside the buy-in range.
	g = H.new({"sb": 1, "bb": 2, "min_buy_in": 40, "max_buy_in": 400}, Seq.new(3))
	_do(g, {"type": "sit", "seat": 0, "player": "a", "buy_in": 40}, "")
	_do(g, {"type": "sit", "seat": 1, "player": "b", "buy_in": 400}, "")
	_do(g, {"type": "start_hand"}, "")
	_do(g, {"type": "fold", "seat": 0}, "button folds the small blind")
	t.eq(g.stack(0), 39, "39 left")
	t.eq(g.apply({"type": "top_up", "seat": 0, "amount": 0}).get("error", ""), "bad_amount", "zero top-up")
	t.eq(g.apply({"type": "top_up", "seat": 0, "amount": 362}).get("error", ""), "bad_amount", "top-up over max")
	_do(g, {"type": "top_up", "seat": 0, "amount": 361}, "top-up to exactly max")
	g = H.new({"sb": 1, "bb": 2, "min_buy_in": 40, "max_buy_in": 400}, Seq.new(3))
	_do(g, {"type": "sit", "seat": 0, "player": "a", "buy_in": 40}, "")
	_do(g, {"type": "sit", "seat": 1, "player": "b", "buy_in": 400}, "")
	_do(g, {"type": "start_hand"}, "")
	_do(g, {"type": "fold", "seat": 0}, "")
	_do(g, {"type": "start_hand"}, "")
	_do(g, {"type": "raise", "seat": 1, "to": 4}, "")
	_do(g, {"type": "fold", "seat": 0}, "")
	t.eq(g.stack(0), 37, "37 left")
	t.eq(g.apply({"type": "top_up", "seat": 0, "amount": 2}).get("error", ""), "bad_amount", "top-up to 39 is below the minimum buy-in")
	_do(g, {"type": "top_up", "seat": 0, "amount": 3}, "top-up to exactly the minimum")
	t.eq(g.stack(0), 40, "40 after top-up")


func _hand_events(g, from_seq: int) -> Array:
	return g.chips.events.filter(func(e): return e["seq"] > from_seq)


## Every hand takes one fresh 128-bit seed; it is logged, replays the deck,
## and is withheld from clients until the hand is over.
func _seeds() -> void:
	var src = Seq.new(77)
	var g = H.new({"sb": 1, "bb": 2, "min_buy_in": 1, "max_buy_in": 10000}, src)
	for i in 3:
		g.apply({"type": "sit", "seat": i, "player": "p%d" % i, "buy_in": 1000})
	var seen := {}
	for h in 5:
		var calls0: int = src.calls
		var r := _do(g, {"type": "start_hand"}, "seeded hand")
		t.eq(src.calls, calls0 + 1, "one seed per hand")
		var want: String = Rng.seed_hex(Rng.parse_seed(src.given[-1]))
		var logged := ""
		for e in r["raw_events"]:
			if e["type"] == "seed":
				logged = e["seed"]
		t.eq(logged, want, "raw log records the hand's seed")
		t.eq(g.hand_seed, want, "hand_seed")
		seen[want] = true
		# Replay: the deck is the seed's shuffle of a fresh deck.
		var d := Cards.deck()
		Rng.from_seed(want).shuffle(d)
		t.eq(g.deck, d, "seed replays the deck")
		for s in 3:
			var v: Dictionary = g.view_for(s)
			t.check(not JSON.stringify(v).contains(want), "seed absent from seat %d view mid-hand" % s)
			t.check(not JSON.stringify(H.events_for(s, r["raw_events"])).contains(want),
				"seed absent from seat %d events mid-hand" % s)
		var r2 := _do(g, {"type": "fold", "seat": g.to_act}, "")
		if g.phase == "betting":
			r2 = _do(g, {"type": "fold", "seat": g.to_act}, "")
		t.eq(g.phase, "waiting", "hand over")
		var end_seed := ""
		for e in H.events_for(0, r2["raw_events"]):
			if e["type"] == "hand_end":
				end_seed = e.get("seed", "")
		t.eq(end_seed, want, "hand_end publishes the seed to clients")
		t.eq(g.audit_history[-1]["seed"], want, "hand history records the seed")
	t.eq(seen.size(), 5, "every hand a different seed")
	# No source, or a source giving junk: start_hand refuses and changes nothing.
	for bad_src in [null, Seq.new(["xyz"]), Seq.new([[1, 2, 3]]), RefCounted.new()]:
		var g2 = H.new({"sb": 1, "bb": 2}, bad_src)
		g2.apply({"type": "sit", "seat": 0, "player": "a", "buy_in": 100})
		g2.apply({"type": "sit", "seat": 1, "player": "b", "buy_in": 100})
		var before := JSON.stringify(g2.to_dict())
		t.eq(g2.apply({"type": "start_hand"}).get("error", ""), "no_seed", "no valid seed: refused")
		t.eq(JSON.stringify(g2.to_dict()), before, "refused start leaves state untouched")
	# Same seed source, same game; a rebuilt game continues with the source passed again.
	var a = H.new({}, Seq.new(5))
	var b = H.new({}, Seq.new(5))
	for x in [a, b]:
		x.apply({"type": "sit", "seat": 0, "player": "a", "buy_in": 100})
		x.apply({"type": "sit", "seat": 1, "player": "b", "buy_in": 100})
		x.apply({"type": "start_hand"})
	t.eq(a.deck, b.deck, "same seeds, same deck")


## The raw forms (apply()'s raw_events, audit_history, to_dict) hold secrets;
## view_for and events_for, the only sendable forms, never return them.
func _client_safe() -> void:
	var g = _table([500, 500, 500, 500])
	var forbidden_keys := ["audit_history", "hist", "deck", "deck_pos", "rng", "hand_seed", "seed", "s"]
	var raw_had_hole := false
	var raw_had_seed := false
	var ok_views := true
	var ok_events := true
	for h in 3:
		var seq0: int = g.chips.seq
		var r := _do(g, {"type": "start_hand"}, "client-safe")
		var raw: Array = r["raw_events"]
		var steps := 0
		while true:
			for e in raw:
				if e["type"] == "hole":
					raw_had_hole = true
				if e["type"] == "seed":
					raw_had_seed = true
			var over: bool = g.phase == "waiting"
			for s in range(-1, 4):
				var v: Dictionary = g.view_for(s)
				if _has_key(v, forbidden_keys):
					ok_views = false
				for i in 4:
					if i != s and not g.seats[i]["shown"] and v["seats"][i]["hole"] != []:
						ok_views = false
				for e in H.events_for(s, raw):
					if e["type"] == "seed":
						ok_events = false
					if e["type"] == "hole" and e["seat"] != s and e["cards"] != []:
						ok_events = false
					if e.has("seed") and e["type"] != "hand_end":
						ok_events = false
					if e["type"] == "hand_end" and not over:
						ok_events = false
			if over or steps > 50:
				break
			steps += 1
			var la: Array = g.legal_actions(g.to_act)
			var pick: Dictionary = la[1] if la.size() > 1 else la[0]
			var a := {"type": pick["type"], "seat": g.to_act}
			r = _do(g, a, "")
			raw = r["raw_events"]
		t.eq(g.phase, "waiting", "client-safe hand %d finished" % h)
	t.check(raw_had_hole and raw_had_seed, "raw events do hold hole cards and seeds (so the test means something)")
	t.check(ok_views, "view_for never holds raw secrets")
	t.check(ok_events, "events_for never passes raw hole cards or a live seed")
	t.check(g.to_dict().has("audit_history") and not g.view_for(0).has("audit_history"), "audit history only in to_dict")


func _has_key(v: Variant, keys: Array) -> bool:
	match typeof(v):
		TYPE_DICTIONARY:
			for k in v:
				if String(k) in keys or _has_key(v[k], keys):
					return true
		TYPE_ARRAY:
			for x in v:
				if _has_key(x, keys):
					return true
	return false
