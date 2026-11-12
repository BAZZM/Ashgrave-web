extends RefCounted
## Blackjack payouts and rules on rigged shoes.

const NAME := "blackjack"
const BJ := preload("res://scripts/casino/blackjack.gd")
const Cards := preload("res://scripts/casino/cards.gd")


## A game with `players` seats funded with 100 each and a shoe whose next
## cards are `seq` (deal order: seats then dealer up, seats then dealer hole).
func _game(seq: String, players := 1, stack := 100) -> RefCounted:
	var g = BJ.new({"decks": 1})
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
