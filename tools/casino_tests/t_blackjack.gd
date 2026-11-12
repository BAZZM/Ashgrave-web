extends RefCounted
## Blackjack payouts and rules on rigged shoes.

const NAME := "blackjack"
const BJ := preload("res://scripts/casino/blackjack.gd")
const Cards := preload("res://scripts/casino/cards.gd")
const Rng := preload("res://scripts/casino/rng.gd")
const Seq := preload("res://tests/seed_seq.gd")


## A game with `players` seats funded with 100 each and a shoe whose next
## cards are `seq` (deal order: seats then dealer up, seats then dealer hole).
func _game(seq: String, players := 1, stack := 100) -> RefCounted:
	var g = BJ.new({"decks": 1}, Seq.new(1))
	for i in players:
		g.apply({"type": "sit", "seat": i, "player": "p%d" % i, "buy_in": stack})
	var cards := Cards.parse_list(seq)
	for k in 6:
		cards.append_array(Cards.deck())
	g.shoe = {"cards": cards, "pos": 0, "cut": 10000, "decks": 1, "pen": 75}
	return g


func _round(t, name: String, seq: String, bet: int, actions: Array, want_stack: int, want_result := "") -> RefCounted:
	var g = _game(seq)
	t.check(g.apply({"type": "bet", "seat": 0, "amount": bet})["ok"], name + ": bet")
	var r: Dictionary = g.apply({"type": "deal"})
	t.check(r["ok"], name + ": deal")
	for a in actions:
		var aa: Dictionary = a.duplicate()
		aa["seat"] = 0
		var rr: Dictionary = g.apply(aa)
		t.check(rr["ok"], "%s: %s -> %s" % [name, str(a), rr.get("error", "")])
	t.eq(g.phase, "betting", name + ": round over")
	t.eq(g.stack(0), want_stack, name + ": stack")
	t.eq(g.chips.balance("table"), 0, name + ": table empty")
	t.eq(g.chips.total(), g.chips.opened - g.chips.closed, name + ": conserved")
	if want_result != "":
		t.eq(g.seats[0]["hands"][0]["result"], want_result, name + ": result")
	return g


func run(t) -> void:
	# Payout table.
	_round(t, "natural 3:2 even bet", "As 9c Kd 7h", 10, [], 115, "blackjack")
	_round(t, "natural 3:2 odd bet rounds down", "As 9c Kd 7h", 5, [], 107, "blackjack")
	_round(t, "natural 3:2 bet 1 pays 1", "As 9c Kd 7h", 1, [], 101, "blackjack")
	_round(t, "dealer blackjack, ten up", "9c Kd 9d As", 10, [], 90, "lose")
	_round(t, "both blackjack push (ace up, no insurance)", "Kc Ad As Kh", 10,
		[{"type": "insurance", "amount": 0}], 100, "push")
	_round(t, "insurance wins 2:1 vs dealer BJ", "9c Ad 9d Kh", 10,
		[{"type": "insurance", "amount": 5}], 100, "lose")
	_round(t, "insurance lost, hand wins", "Kc Ad Th 7h", 10,
		[{"type": "insurance", "amount": 5}, {"type": "stand"}], 105, "win")
	_round(t, "dealer stands on soft 17", "Tc 6d 8h Ah", 10, [{"type": "stand"}], 110, "win")
	_round(t, "dealer hits 16", "Tc Th Ts 6d 5c", 10, [{"type": "stand"}], 90, "lose")
	_round(t, "dealer busts", "Tc Th 2s 6d 9c", 10, [{"type": "stand"}], 110, "win")
	_round(t, "push 18", "Tc Th 8s 8d", 10, [{"type": "stand"}], 100, "push")
	_round(t, "player busts", "Tc Th 6s 8d Kc", 10, [{"type": "hit"}], 90, "bust")
	_round(t, "double wins 2x", "6c Th 5s 7d 9c", 10, [{"type": "double"}], 120, "win")
	_round(t, "double loses 2x", "6c Th 5s 9d 2c", 10, [{"type": "double"}], 80, "lose")
	# Hitting to 21 stands automatically.
	_round(t, "auto stand on 21", "6c Th 5s 9d Tc", 10, [{"type": "hit"}], 110, "win")

	# Split: 8 8 vs dealer 10 7. Hand A 8+T stand (18 win), hand B 8+2+9 = 19 win.
	var g = _round(t, "split two wins", "8c Th 8s 7d Tc 2c 9h", 10,
		[{"type": "split"}, {"type": "stand"}, {"type": "hit"}, {"type": "stand"}], 120)
	t.eq(g.seats[0]["hands"].size(), 2, "split made two hands")
	t.eq(g.seats[0]["hands"][1]["result"], "win", "second split hand")
	# Split hand reaching 21 with a ten is not blackjack: pays 1:1.
	g = _round(t, "split aces one card each, 1:1", "Ac Th As 7d Kc 9h", 10, [{"type": "split"}], 120)
	t.eq(g.seats[0]["hands"][0]["result"], "win", "split ace + K is a plain win")
	t.eq((g.seats[0]["hands"][0]["cards"] as Array).size(), 2, "split ace got one card")
	# Split aces cannot be resplit even with another ace.
	g = _game("Ac Th As 7d Ad 9h")
	g.apply({"type": "bet", "seat": 0, "amount": 10})
	g.apply({"type": "deal"})
	g.apply({"type": "split", "seat": 0})
	t.eq(g.seats[0]["hands"].size(), 2, "no resplit of aces")
	t.eq(g.phase, "betting", "split aces end the hand")
	# Resplit up to four hands.
	g = _game("8c Th 8s 7d 8h 8d 8s 2c 2d 2h 2s")
	g.apply({"type": "bet", "seat": 0, "amount": 10})
	g.apply({"type": "deal"})
	t.check(g.apply({"type": "split", "seat": 0})["ok"], "split 1")
	t.check(g.apply({"type": "split", "seat": 0})["ok"], "resplit 2")
	t.check(g.apply({"type": "split", "seat": 0})["ok"], "resplit 3")
	t.eq(g.seats[0]["hands"].size(), 4, "four hands")
	var la: Array = g.legal_actions(0)
	t.check(la.filter(func(x): return x["type"] == "split").is_empty(), "no fifth hand")
	t.eq(g.apply({"type": "split", "seat": 0})["error"], "illegal_action", "fifth split refused")
	# Double after split.
	t.check(g.apply({"type": "double", "seat": 0})["ok"], "double after split")
	# Ten-value cards split together.
	g = _game("Kc 9h Qs 7d")
	g.apply({"type": "bet", "seat": 0, "amount": 10})
	g.apply({"type": "deal"})
	t.check(g.legal_actions(0).any(func(x): return x["type"] == "split"), "K and Q may split")

	# Multi-seat order and the hole card staying hidden.
	g = _game("Tc 9c Th 6d 8s 9d Kh 2c 9s", 3)
	for i in 3:
		g.apply({"type": "bet", "seat": i, "amount": 10})
	g.apply({"type": "deal"})
	t.eq(g.turn_seat, 0, "seat 0 acts first")
	var v: Dictionary = g.view_for(1)
	t.eq(v["dealer"][1], -1, "hole card hidden in view")
	t.check(not v.has("shoe") and not v.has("rng"), "view has no shoe or rng")
	t.eq(g.apply({"type": "hit", "seat": 1})["error"], "not_your_turn", "out of turn")
	g.apply({"type": "stand", "seat": 0})
	g.apply({"type": "stand", "seat": 1})
	g.apply({"type": "stand", "seat": 2})
	t.eq(g.phase, "betting", "three seats played")
	t.check(g.view_for(0)["dealer"][1] != -1, "hole shown after round")
	# Dealer drew 2 to 8 -> 10, then... 6+2=8, 9s -> 17. Seat 0 (T8=18) wins, seat1 (9 9=18) wins, seat2 (Th Kh=20) wins.
	t.eq(Cards.texts(g.dealer), "6d 2c 9s", "dealer drew to 17")
	t.eq([g.stack(0), g.stack(1), g.stack(2)], [110, 110, 110], "three wins")

	# Errors never mutate.
	g = _game("Tc 9c Th 6d", 1, 20)
	var before := JSON.stringify(g.to_dict())
	for bad in [null, 5, "hit", {}, {"type": 3}, {"type": "bet", "seat": 0, "amount": 21},
			{"type": "bet", "seat": 0, "amount": -1}, {"type": "bet", "seat": 0, "amount": 2.5},
			{"type": "bet", "seat": 9, "amount": 1}, {"type": "bet", "seat": 1, "amount": 1},
			{"type": "deal"}, {"type": "hit", "seat": 0}, {"type": "insurance", "seat": 0, "amount": 1},
			{"type": "sit", "seat": 0, "player": "x", "buy_in": 5}, {"type": "frobnicate"}]:
		var r: Dictionary = g.apply(bad)
		t.check(not r["ok"] and r.has("error"), "rejected: %s" % str(bad))
	t.eq(JSON.stringify(g.to_dict()), before, "rejections left state untouched")
	g.apply({"type": "bet", "seat": 0, "amount": 15})
	g.apply({"type": "deal"})
	t.eq(g.apply({"type": "double", "seat": 0})["error"], "illegal_action", "cannot double without chips")
	t.eq(g.apply({"type": "leave", "seat": 0})["error"], "round_in_progress", "no leaving mid-round")
	# JSON floats are accepted as ints.
	g = _game("As 9c Kd 7h")
	t.check(g.apply(JSON.parse_string("{\"type\":\"bet\",\"seat\":0,\"amount\":10}"))["ok"], "JSON action")
	# Cash out.
	g.apply({"type": "leave", "seat": 0})
	t.eq(g.chips.closed, 100, "leave cashes out stack and returned bet")
	_soft_totals(t)
	_insurance_cap(t)
	_shoe_seeds(t)


## Several aces: each one counts 1 as long as the total is over 21.
func _soft_totals(t) -> void:
	var P := func(x: String) -> Array: return Cards.parse_list(x)
	t.eq(BJ.total(P.call("Ac Ad")), [12, true], "A A is soft 12")
	t.eq(BJ.total(P.call("Ac Ad 9h")), [21, true], "A A 9 is soft 21")
	t.eq(BJ.total(P.call("Ac Ad Kh")), [12, false], "A A K is hard 12 (two aces reduced)")
	t.eq(BJ.total(P.call("Ac Ad Ah 9s")), [12, false], "A A A 9 is hard 12")
	t.eq(BJ.total(P.call("Ac Ad Ah As 7c")), [21, true], "four aces and a 7 is soft 21")
	t.eq(BJ.total(P.call("Ac Ad Ah As 7c Kd")), [21, false], "four aces, 7, K is hard 21")
	t.eq(BJ.total(P.call("Ac 6d")), [17, true], "A 6 soft 17")
	t.eq(BJ.total(P.call("Ac 6d Th")), [17, false], "A 6 T hard 17")
	# In play: A A, hit K (12, not bust), hit 7 (19), stand vs dealer 17.
	_round(t, "two aces then a king stay live", "Ac Tc Ad 7h Kd 7s", 10,
		[{"type": "hit"}, {"type": "hit"}, {"type": "stand"}], 110, "win")
	# Dealer A A then draws: A A 5 = soft 17 stands (dealer stands on all 17).
	_round(t, "dealer two aces", "Tc Ac 8d Ah 5s", 10, [{"type": "insurance", "amount": 0}, {"type": "stand"}],
		110, "win")


## Insurance is capped at half the original bet, rounded down.
func _insurance_cap(t) -> void:
	for c in [[10, 5], [11, 5], [1, 0], [7, 3]]:
		var g = _game("9c Ad 9d 7h")
		g.apply({"type": "bet", "seat": 0, "amount": c[0]})
		g.apply({"type": "deal"})
		t.eq(g.phase, "insurance", "insurance offered under an ace (bet %d)" % c[0])
		t.eq(g.legal_actions(0)[0]["max"], c[1], "insurance max for bet %d" % c[0])
		var r: Dictionary = g.apply({"type": "insurance", "seat": 0, "amount": c[1] + 1})
		t.eq(r.get("error", ""), "insurance_limit", "insurance %d over half of %d refused" % [c[1] + 1, c[0]])
		t.check(g.apply({"type": "insurance", "seat": 0, "amount": c[1]})["ok"], "insurance %d on %d accepted" % [c[1], c[0]])
	# Doubled-up insurance would be paid 2:1: bet 10, insure 5, dealer BJ -> stack unchanged.
	_round(t, "full insurance vs dealer blackjack breaks even", "9c Ad 9d Kh", 10,
		[{"type": "insurance", "amount": 5}], 100, "lose")


func _types(evts: Array) -> Array:
	return evts.map(func(e): return e["type"])


## Each shoe takes a fresh seed; it is withheld until the shoe is retired and
## no round dealt from it is in play.
func _shoe_seeds(t) -> void:
	var src = Seq.new(31)
	var g = BJ.new({"decks": 1, "penetration_pct": 50}, src)
	g.apply({"type": "sit", "seat": 0, "player": "a", "buy_in": 100000})
	t.eq(src.calls, 0, "no seed taken before the first deal")
	t.eq(g.view_for(0)["shoe_left"], 0, "no shoe yet")
	g.apply({"type": "bet", "seat": 0, "amount": 1})
	var r: Dictionary = g.apply({"type": "deal"})
	t.eq(src.calls, 2, "first deal takes the shoe seed and a spare")
	var s1: String = Rng.seed_hex(Rng.parse_seed(src.given[0]))
	t.eq(g.shoe.get("seed", ""), s1, "shoe 1 seeded by the first seed")
	var ref := Cards.new_shoe(1, 50, Rng.from_seed(s1))
	t.eq(g.shoe["cards"], ref["cards"], "seed replays the shoe")
	t.check("seed" in _types(r["raw_events"]), "raw log records the shoe seed")
	t.check(not ("seed" in _types(BJ.events_for(0, r["raw_events"]))), "events_for withholds the shoe seed")
	t.check(not JSON.stringify(g.view_for(0)).contains(s1), "view never holds the seed")
	var revealed := ""
	var rounds := 0
	var saw_live_seed := false
	while revealed == "" and rounds < 100:
		while g.phase != "betting":
			if g.phase == "insurance":
				g.apply({"type": "insurance", "seat": 0, "amount": 0})
			else:
				g.apply({"type": "stand", "seat": 0})
		g.apply({"type": "bet", "seat": 0, "amount": 1})
		r = g.apply({"type": "deal"})
		rounds += 1
		for e in BJ.events_for(0, r["raw_events"]):
			if e["type"] == "seed_reveal":
				revealed = e["seed"]
				t.eq(e["shoe"], 1, "reveal names shoe 1")
			if e["type"] == "seed":
				saw_live_seed = true
	t.eq(revealed, s1, "shoe 1's seed is published when the shoe is retired")
	t.check(not saw_live_seed, "no live seed reached a client")
	t.eq(src.calls, 3, "a reshuffle takes one new seed (the spare is still held)")
	t.eq(g.shoe_no, 2, "second shoe")
	# Emergency reshuffle mid-round: the old shoe's seed waits for the round end.
	g = _game("Tc 9c 2h 7d")
	g.shoe["seed"] = "0000000000000000000000000000abcd"
	g.shoe["cut"] = 10000
	(g.shoe["cards"] as Array).resize(4)
	g.apply({"type": "bet", "seat": 0, "amount": 10})
	r = g.apply({"type": "deal"})
	var rr: Dictionary = g.apply({"type": "hit", "seat": 0})
	var types := _types(rr["raw_events"])
	t.check("shuffle" in types, "shoe ran out: emergency reshuffle")
	if g.phase != "betting":
		var more: Dictionary = g.apply({"type": "stand", "seat": 0})
		rr["raw_events"].append_array(more["raw_events"])
		types = _types(rr["raw_events"])
	t.eq(g.phase, "betting", "round over")
	var i_reveal: int = types.find("seed_reveal")
	t.check(i_reveal > types.find("dealer_reveal") and i_reveal > types.find("round_end"),
		"old shoe's seed revealed only after the round (and the hole card) is over")
	t.eq(rr["raw_events"][i_reveal]["seed"], "0000000000000000000000000000abcd", "the retired shoe's seed")
	t.eq(g.reserve_seed, [], "spare used")
	g.apply({"type": "bet", "seat": 0, "amount": 10})
	t.check(g.apply({"type": "deal"})["ok"], "next deal takes a new spare")
	t.eq(g.reserve_seed.size(), 4, "spare replenished")
	# No seed source: the deal is refused and nothing changes.
	var g2 = BJ.new({}, null)
	g2.apply({"type": "sit", "seat": 0, "player": "a", "buy_in": 100})
	g2.apply({"type": "bet", "seat": 0, "amount": 10})
	var before := JSON.stringify(g2.to_dict())
	t.eq(g2.apply({"type": "deal"}).get("error", ""), "no_seed", "no seed source: deal refused")
	t.eq(JSON.stringify(g2.to_dict()), before, "refused deal leaves state untouched")
