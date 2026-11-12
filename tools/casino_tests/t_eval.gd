extends RefCounted
## Hand evaluator: known hands, ordering, ties, kickers; export for the Python
## brute-force cross-check; speed.

const NAME := "evaluator"
const Cards := preload("res://scripts/casino/cards.gd")
const Eval := preload("res://scripts/casino/hand_eval.gd")
const Rng := preload("res://scripts/casino/rng.gd")

## [7 cards, category, best five as text (order-free)]
const KNOWN := [
	["As Ks Qs Js Ts 2d 3c", 8, "As Ks Qs Js Ts"],
	["5h 4h 3h 2h Ah Kd Kc", 8, "5h 4h 3h 2h Ah"],
	["9c 8c 7c 6c 5c 4c Ac", 8, "9c 8c 7c 6c 5c"],
	["7d 7h 7s 7c Ad Kd Qd", 7, "7d 7h 7s 7c Ad"],
	["Kd Kh Ks 9c 9d 9h 2c", 6, "Kd Kh Ks 9c 9d"],
	["2d 2h 2s Ac Ad 3h 4h", 6, "2d 2h 2s Ac Ad"],
	["Ad 9d 7d 4d 2d Kd 3s", 5, "Ad Kd 9d 7d 4d"],
	["Ah 2c 3d 4s 5h 9c Kd", 4, "Ah 2c 3d 4s 5h"],
	["Ah 2c 3d 4s 5h 6c Kd", 4, "2c 3d 4s 5h 6c"],
	["Ts Jh Qd Kc Ad 2c 3c", 4, "Ts Jh Qd Kc Ad"],
	["8s 8h 8d Ac Kd 4h 2s", 3, "8s 8h 8d Ac Kd"],
	["Js Jh 4d 4c 2h 2s Ad", 2, "Js Jh 4d 4c Ad"],
	["Js Jh 4d 4c 2h 2s 3d", 2, "Js Jh 4d 4c 3d"],
	["Qs Qh 9d 7c 5h 3s 2d", 1, "Qs Qh 9d 7c 5h"],
	["As Jh 9d 7c 5h 3s 2d", 0, "As Jh 9d 7c 5h"],
]

## [a, b, expected sign of value(a) - value(b)]
const ORDER := [
	["As Ks Qs Js Ts", "9s 8s 7s 6s 5s", 1],
	["6h 5h 4h 3h 2h", "5d 4d 3d 2d Ad", 1],  # 6-high SF beats steel wheel
	["5d 4d 3d 2d Ad", "Ac Ad Ah As Kd", 1],
	["2c 2d 2h 2s 3c", "Ac Ad Ah Kd Kc", 1],
	["Ac Ad Ah 2d 2c", "Kc Kd Kh Ad Ac", 1],
	["Kc Kd Kh Ad Ac", "Kc Kd Kh Qd Qc", 1],
	["2h 3h 4h 5h 7h", "Ac Kd Qh Js Tc", 1],
	["Ah Kh 3h 2h 4h", "Ad Qd Jd Td 8d", 1],
	["Ah Kh Qh Jh 9h", "Ad Kd Qd Jd 8d", 1],
	["6c 5d 4h 3s 2c", "5c 4d 3h 2s Ac", 1],  # 6-high straight beats wheel
	["5c 4d 3h 2s Ac", "Ac Ad Ah Kc Qd", 1],
	["Ac Ad Ah 2c 3d", "Kc Kd Kh Ac Qd", 1],
	["Ac Ad Kh Kc 2d", "Ac Ad Qh Qc Kd", 1],
	["Kc Kd Qh Qc 3d", "Kc Kd Qh Qc 2d", 1],
	["Kc Kd 5h 4c 3d", "Kc Kd 5h 4c 2d", 1],
	["Ac Kd 9h 7c 6d", "Ac Kd 9h 7c 5d", 1],
	["Ac Kd 9h 7c 6d", "As Kh 9c 7d 6s", 0],  # suits never matter
	["Ts Jh Qd Kc Ad", "Th Jc Qs Kd As", 0],
	["5c 4d 3h 2s Ac", "5h 4c 3s 2d Ad", 0],
	["2c 3d 4h 5s 7c", "2d 3h 4s 5c 7d", 0],
]

## Board plays: both players tie.
const TIES := [
	["As Ks Qs Js Ts", "2c 3d", "2d 3c"],
	["Ac Ad Kh Kc Qd", "2c 3d", "4h 5h"],   # two pair, Q kicker on board
	["9c 9d 9h 9s Ad", "Kc Kd", "2h 3h"],   # quads, ace kicker on board
	["5c 6d 7h 8s 9c", "2c 2d", "Ah Kh"],
]


func run(t) -> void:
	for k in KNOWN:
		var cs := Cards.parse_list(k[0])
		var ev := Eval.evaluate(cs)
		t.eq(ev["category"], k[1], "category of %s" % k[0])
		var want := Cards.parse_list(k[2])
		var subset := true
		for c in ev["cards"]:
			if not (c in cs):
				subset = false
		t.check(subset and ev["cards"].size() == 5, "five of the seven: %s" % k[0])
		t.eq(Eval.value(ev["cards"]), Eval.value(want), "best five of %s" % k[0])
		t.eq(Eval.value(ev["cards"]), ev["value"], "best five scores the same (%s)" % k[0])
	for o in ORDER:
		var va := Eval.value(Cards.parse_list(o[0]))
		var vb := Eval.value(Cards.parse_list(o[1]))
		t.eq(signi(va - vb), o[2], "%s vs %s" % [o[0], o[1]])
	for tie in TIES:
		var bd := Cards.parse_list(tie[0])
		var a := Cards.parse_list(tie[1])
		a.append_array(bd)
		var b := Cards.parse_list(tie[2])
		b.append_array(bd)
		t.eq(Eval.value(a), Eval.value(b), "board plays: %s" % tie[0])
	# Kicker beyond five cards does not count.
	t.eq(Eval.value(Cards.parse_list("Ac Ad Kc Qd Jh 3c 2d")), Eval.value(Cards.parse_list("Ac Ad Kc Qd Jh 4c 5d")),
		"sixth/seventh cards ignored")
	t.eq(Eval.category_name(Eval.value(Cards.parse_list("Ac Ad Kc Qd Jh"))), "pair", "name")

	# Random hands: every result's five cards come from the seven and score the same.
	var rng = Rng.test_only_from_int(20261112)
	var n := 100000
	var hands := []
	var deck := Cards.deck()
	for i in n:
		var h := []
		for k in 7:
			var j: int = k + rng.next_below(52 - k)
			var tmp = deck[k]
			deck[k] = deck[j]
			deck[j] = tmp
			h.append(deck[k])
		hands.append(h)
	var t0 := Time.get_ticks_usec()
	var vals := PackedInt64Array()
	vals.resize(n)
	for i in n:
		vals[i] = Eval.value(hands[i])
	var dt := (Time.get_ticks_usec() - t0) / 1e6
	t.hands_per_sec = n / dt
	print("  evaluator: %d 7-card hands in %.2f s = %d hands/s (GDScript)" % [n, dt, int(n / dt)])
	var cats := []
	cats.resize(9)
	cats.fill(0)
	var sub_ok := true
	for i in 3000:
		var ev := Eval.evaluate(hands[i])
		for c in ev["cards"]:
			if not (c in hands[i]):
				sub_ok = false
		if ev["cards"].size() != 5 or Eval.value(ev["cards"]) != ev["value"]:
			sub_ok = false
	t.check(sub_ok, "evaluate() returns five of the seven with the same value")
	for i in n:
		cats[vals[i] >> 20] += 1
	print("  category counts: %s" % str(cats))
	for k in 9:
		t.check(cats[k] > 0, "random sample has category %d" % k)
	if t.export_path != "":
		var f := FileAccess.open(t.export_path, FileAccess.WRITE)
		for i in n:
			var h: Array = hands[i]
			f.store_line("%s\t%d\t%d" % [" ".join(PackedStringArray(h.map(func(x): return str(x)))), vals[i], vals[i] >> 20])
		f.close()
		print("  exported %d hands for the Python cross-check" % n)
