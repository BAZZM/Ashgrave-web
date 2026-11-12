extends RefCounted
## Blackjack: a dealer against up to six seats, played from a shoe.
##
## House rules (see docs/CASINO_CORE.md):
## - Dealer stands on all 17s, peeks for blackjack under an ace or a ten.
## - Blackjack pays 3:2, rounded down to the chip: a bet of 5 wins 7.
## - Double on any first two cards, also after a split, for the full bet.
## - Split any two cards of equal value (K and Q too) up to 4 hands. Split aces
##   get one card each, cannot be resplit or hit; 21 on a split is not blackjack.
## - Insurance up to half the bet (rounded down) when the dealer shows an ace,
##   pays 2:1. No surrender.
##
## Randomness: every shoe is shuffled by a generator freshly seeded with 128
## bits from `seed_source.next_seed()`. The first shoe is built at the first
## deal; a new one when a round would start past the cut card. Each deal also
## makes sure one spare seed is held for an emergency reshuffle (a shoe that
## runs out mid-round), so a round never needs the seed source once started.
## A shoe's seed is logged in a "seed" event when the shoe is made and
## published in a "seed_reveal" event once the shoe is retired and no round
## dealt from it is still in play: at the next shuffle between rounds, or at
## the end of the round in which an emergency reshuffle retired it.
##
## Accounts: "seat<i>" (the player's stack), "table" (wagers in play), "house"
## (unbounded). Actions are Dictionaries; apply() returns
## {ok:true, raw_events:[...]} or {ok:false, error, message} and never mutates
## on error. SENDABLE: view_for(seat), events_for(seat, raw_events).
## SERVER-ONLY: raw_events ("seed" events), to_dict() (shoe order, seeds).

const U := preload("res://scripts/casino/util.gd")
const Cards := preload("res://scripts/casino/cards.gd")
const Rng := preload("res://scripts/casino/rng.gd")
const Chips := preload("res://scripts/casino/chips.gd")

const MAX_HANDS := 4

var cfg: Dictionary = {}
var rng = Rng.new()
var chips = Chips.new()
var shoe: Dictionary = {}
var phase := "betting"  # betting | insurance | play
var round_no := 0
var seats: Array = []
var dealer: Array = []
var hole_shown := true
var turn_seat := -1
var turn_hand := -1
var shoe_no := 0
## Seeds of retired shoes not yet published: [[shoe_no, hex], ...].
var pending_reveal: Array = []
## Spare 128-bit seed (four u32) for an emergency reshuffle, or [].
var reserve_seed: Array = []
## Object with next_seed() (see rng.gd). Not serialised: pass it again after
## from_dict().
var seed_source = null


func _init(config: Dictionary = {}, source = null) -> void:
	cfg = {
		"seats": clampi(int(config.get("seats", 6)), 1, 6),
		"decks": clampi(int(config.get("decks", 6)), 1, 8),
		"penetration_pct": clampi(int(config.get("penetration_pct", 75)), 10, 95),
		"min_bet": maxi(1, int(config.get("min_bet", 1))),
		"max_bet": maxi(1, int(config.get("max_bet", 1000000))),
	}
	seed_source = source
	chips.open("house", 0, true)
	chips.open("table", 0)
	seats = []
	for i in cfg["seats"]:
		seats.append(_empty_seat())


static func _empty_seat() -> Dictionary:
	return {"player": "", "bet": 0, "hands": [], "insurance": 0, "ins_done": false}


static func _new_hand(bet: int) -> Dictionary:
	return {"cards": [], "bet": bet, "done": false, "doubled": false, "split": false,
		"split_aces": false, "result": "", "paid": 0}


static func acct(i: int) -> String:
	return "seat%d" % i


static func card_value(c: int) -> int:
	var r := c >> 2
	if r == Cards.ACE:
		return 11
	if r >= 8:
		return 10
	return r + 2


## [total, soft] for a list of cards.
static func total(cards: Array) -> Array:
	var t := 0
	var aces := 0
	for c in cards:
		var v := card_value(c)
		t += v
		if v == 11:
			aces += 1
	while t > 21 and aces > 0:
		t -= 10
		aces -= 1
	return [t, aces > 0]


static func is_natural(h: Dictionary) -> bool:
	return not h["split"] and (h["cards"] as Array).size() == 2 and total(h["cards"])[0] == 21


func stack(i: int) -> int:
	return chips.balance(acct(i))


# ----------------------------------------------------------------- apply

func apply(action: Variant) -> Dictionary:
	var tt := U.action_type(action)
	if tt[1] != null:
		return tt[1]
	var t: String = tt[0]
	var s0: int = chips.seq
	var e = null
	var seat = U.field_int(action, "seat")
	var needs_seat := t in ["sit", "leave", "bet", "insurance", "hit", "stand", "double", "split"]
	if needs_seat:
		if seat == null or seat < 0 or seat >= seats.size():
			return U.err("bad_seat")
		if t != "sit" and seats[seat]["player"] == "":
			return U.err("empty_seat")
	match t:
		"sit":
			e = _sit(seat, action)
		"leave":
			e = _leave(seat)
		"bet":
			e = _bet(seat, action)
		"deal":
			e = _deal()
		"insurance":
			e = _insurance(seat, action)
		"hit", "stand", "double", "split":
			e = _play(seat, t)
		_:
			e = U.err("unknown_action", "unknown action '%s'" % t)
	if e != null:
		return e
	return U.ok(chips.events_since(s0))


func _sit(seat: int, a: Dictionary):
	if seats[seat]["player"] != "":
		return U.err("seat_taken")
	var p = U.field_str(a, "player")
	var buy = U.field_int(a, "buy_in")
	if p == null or p == "":
		return U.err("bad_player")
	if buy == null or buy < 0:
		return U.err("bad_amount")
	if chips.has(acct(seat)):
		return U.err("seat_taken")
	seats[seat] = _empty_seat()
	seats[seat]["player"] = p
	chips.open(acct(seat), buy)
	chips.log_event("sit", {"seat": seat, "player": p, "buy_in": buy})
	return null


func _leave(seat: int):
	if phase != "betting":
		return U.err("round_in_progress", "leave between rounds")
	var b: int = seats[seat]["bet"]
	if b > 0:
		chips.transfer("table", acct(seat), b, "bet_returned")
	var p: String = seats[seat]["player"]
	var amt: int = chips.close(acct(seat))
	seats[seat] = _empty_seat()
	chips.log_event("leave", {"seat": seat, "player": p, "cash_out": amt})
	return null


func _bet(seat: int, a: Dictionary):
	if phase != "betting":
		return U.err("not_betting")
	var amt = U.field_int(a, "amount")
	if amt == null or amt < 0:
		return U.err("bad_amount")
	if amt != 0 and (amt < cfg["min_bet"] or amt > cfg["max_bet"]):
		return U.err("bet_limits", "bet must be %d..%d" % [cfg["min_bet"], cfg["max_bet"]])
	var old: int = seats[seat]["bet"]
	if amt > stack(seat) + old:
		return U.err("insufficient_chips")
	if old > 0:
		chips.transfer("table", acct(seat), old, "bet_returned")
	seats[seat]["bet"] = amt
	if amt > 0:
		chips.transfer(acct(seat), "table", amt, "bet")
	chips.log_event("bet", {"seat": seat, "amount": amt})
	return null


func _draw() -> int:
	if Cards.shoe_left(shoe) <= 0:
		_emergency_shuffle()
	return Cards.shoe_draw(shoe)


## Retires the current shoe (its seed waits in pending_reveal) and seeds a
## fresh generator for the next one. Returns the new shoe's hex seed.
func _reseed(words: Array) -> String:
	if not shoe.is_empty() and shoe.has("seed"):
		pending_reveal.append([shoe_no, String(shoe["seed"])])
	shoe_no += 1
	rng = Rng.new()
	rng.seed_128(words)
	var hex := Rng.seed_hex(words)
	chips.log_event("seed", {"unit": "shoe", "shoe": shoe_no, "seed": hex})
	return hex


## Publishes the seeds of retired shoes. Only called between rounds.
func _flush_reveals() -> void:
	for p in pending_reveal:
		chips.log_event("seed_reveal", {"unit": "shoe", "shoe": p[0], "seed": p[1]})
	pending_reveal = []


## The shoe ran out mid-round (only possible with few decks and many splits):
## reshuffle every card not on the table, as a dealer shuffles the discards.
## Uses the spare seed taken at the deal; its seed is revealed at round end.
func _emergency_shuffle() -> void:
	var in_play := {}
	for c in dealer:
		in_play[c] = int(in_play.get(c, 0)) + 1
	for s in seats:
		for h in s["hands"]:
			for c in h["cards"]:
				in_play[c] = int(in_play.get(c, 0)) + 1
	var cards := []
	for d in cfg["decks"]:
		for c in 52:
			if int(in_play.get(c, 0)) > 0:
				in_play[c] = int(in_play[c]) - 1
			else:
				cards.append(c)
	var words := reserve_seed
	if words.is_empty():
		# A second emergency in one round (one deck, many splits): ask the
		# source now. A source that fails here is a host bug; count a fault
		# and fall back to continuing the old stream rather than stop the round.
		words = U.take_seed(seed_source)
		if words.is_empty():
			chips.faults += 1
			words = [rng.next_u32(), rng.next_u32(), rng.next_u32(), rng.next_u32()]
	var hex := _reseed(words)
	reserve_seed = []
	rng.shuffle(cards)
	shoe = {"cards": cards, "pos": 0, "cut": 0, "decks": cfg["decks"], "pen": cfg["penetration_pct"], "seed": hex}
	chips.log_event("shuffle", {"shoe": shoe_no, "cards": cards.size(), "cut": 0, "emergency": true})


func _deal():
	if phase != "betting":
		return U.err("not_betting")
	var any := false
	for s in seats:
		if s["bet"] > 0:
			any = true
	if not any:
		return U.err("no_bets")
	# Take every seed this round could need before changing anything.
	var need_shoe: bool = shoe.is_empty() or Cards.shoe_past_cut(shoe)
	var shoe_words := []
	if need_shoe:
		shoe_words = U.take_seed(seed_source)
		if shoe_words.is_empty():
			return U.err("no_seed", "the seed source gave no valid 128-bit seed")
	var spare := reserve_seed
	if spare.is_empty():
		spare = U.take_seed(seed_source)
		if spare.is_empty():
			return U.err("no_seed", "the seed source gave no valid 128-bit seed")
	reserve_seed = spare
	if need_shoe:
		var hex := _reseed(shoe_words)
		shoe = Cards.new_shoe(cfg["decks"], cfg["penetration_pct"], rng)
		shoe["seed"] = hex
		chips.log_event("shuffle", {"shoe": shoe_no, "cards": (shoe["cards"] as Array).size(), "cut": shoe["cut"]})
		_flush_reveals()
	round_no += 1
	dealer = []
	hole_shown = false
	var order := []
	for i in seats.size():
		var s: Dictionary = seats[i]
		s["hands"] = []
		s["insurance"] = 0
		s["ins_done"] = false
		if s["bet"] > 0:
			s["hands"] = [_new_hand(s["bet"])]
			s["bet"] = 0
			order.append(i)
	chips.log_event("round_start", {"round": round_no, "seats": order})
	for pass_no in 2:
		for i in order:
			var c := _draw()
			seats[i]["hands"][0]["cards"].append(c)
			chips.log_event("card", {"seat": i, "hand": 0, "card": c})
		var dc := _draw()
		dealer.append(dc)
		if pass_no == 0:
			chips.log_event("dealer_card", {"card": dc})
		else:
			chips.log_event("dealer_hole", {})
	for i in order:
		var h: Dictionary = seats[i]["hands"][0]
		if is_natural(h):
			h["done"] = true
	var up: int = dealer[0]
	if card_value(up) == 11:
		phase = "insurance"
		chips.log_event("insurance_open", {})
		_maybe_close_insurance()
	else:
		_after_peek_point()
	return null


func _insurance(seat: int, a: Dictionary):
	if phase != "insurance":
		return U.err("not_insurance")
	var s: Dictionary = seats[seat]
	if s["hands"].is_empty() or s["ins_done"]:
		return U.err("not_eligible")
	var amt = U.field_int(a, "amount")
	if amt == null or amt < 0:
		return U.err("bad_amount")
	var cap: int = s["hands"][0]["bet"] / 2
	if amt > cap:
		return U.err("insurance_limit", "insurance is at most %d" % cap)
	if amt > stack(seat):
		return U.err("insufficient_chips")
	s["insurance"] = amt
	s["ins_done"] = true
	if amt > 0:
		chips.transfer(acct(seat), "table", amt, "insurance")
	chips.log_event("insurance", {"seat": seat, "amount": amt})
	_maybe_close_insurance()
	return null


func _maybe_close_insurance() -> void:
	for s in seats:
		if not s["hands"].is_empty() and not s["ins_done"]:
			return
	# Insurance is settled at the peek.
	var dbj: bool = total(dealer)[0] == 21
	for i in seats.size():
		var amt: int = seats[i]["insurance"]
		if amt <= 0:
			continue
		if dbj:
			chips.transfer("table", acct(i), amt, "insurance_returned")
			chips.transfer("house", acct(i), amt * 2, "insurance_win")
		else:
			chips.transfer("table", "house", amt, "insurance_lost")
	_after_peek_point()


## Called once the dealer's hole card may be peeked (ten or ace up).
func _after_peek_point() -> void:
	var up_v := card_value(dealer[0])
	if (up_v == 10 or up_v == 11) and total(dealer)[0] == 21:
		chips.log_event("dealer_blackjack", {})
		_finish_round()
		return
	if up_v == 10 or up_v == 11:
		chips.log_event("peek", {"blackjack": false})
	phase = "play"
	turn_seat = -1
	turn_hand = -1
	_advance()


## Moves the turn to the next unfinished hand, dealing a split hand's second
## card when its turn comes; ends the round when no hand is left.
func _advance() -> void:
	var si := maxi(turn_seat, 0)
	var hi := maxi(turn_hand, 0)
	while si < seats.size():
		var hands: Array = seats[si]["hands"]
		while hi < hands.size():
			var h: Dictionary = hands[hi]
			if not h["done"] and (h["cards"] as Array).size() == 1:
				var c := _draw()
				h["cards"].append(c)
				chips.log_event("card", {"seat": si, "hand": hi, "card": c})
				if total(h["cards"])[0] == 21:
					h["done"] = true
			if not h["done"]:
				turn_seat = si
				turn_hand = hi
				chips.log_event("turn", {"seat": si, "hand": hi})
				return
			hi += 1
		si += 1
		hi = 0
	turn_seat = -1
	turn_hand = -1
	_dealer_play()
	_finish_round()


func legal_actions(seat: int) -> Array:
	if phase == "insurance":
		if seat >= 0 and seat < seats.size() and not seats[seat]["hands"].is_empty() and not seats[seat]["ins_done"]:
			return [{"type": "insurance", "min": 0, "max": mini(seats[seat]["hands"][0]["bet"] / 2, stack(seat))}]
		return []
	if phase == "betting":
		if seat >= 0 and seat < seats.size() and seats[seat]["player"] != "":
			return [{"type": "bet", "min": cfg["min_bet"], "max": mini(cfg["max_bet"], stack(seat) + int(seats[seat]["bet"]))}]
		return []
	if seat != turn_seat:
		return []
	var h: Dictionary = seats[seat]["hands"][turn_hand]
	var out := [{"type": "hit"}, {"type": "stand"}]
	var cards: Array = h["cards"]
	if cards.size() == 2 and stack(seat) >= h["bet"]:
		out.append({"type": "double"})
		if card_value(cards[0]) == card_value(cards[1]) and seats[seat]["hands"].size() < MAX_HANDS \
				and not (h["split_aces"]):
			out.append({"type": "split"})
	return out


func _play(seat: int, t: String):
	if phase != "play":
		return U.err("not_playing")
	if seat != turn_seat:
		return U.err("not_your_turn")
	var legal := false
	for la in legal_actions(seat):
		if la["type"] == t:
			legal = true
	if not legal:
		return U.err("illegal_action", "%s is not allowed now" % t)
	var hands: Array = seats[seat]["hands"]
	var h: Dictionary = hands[turn_hand]
	chips.log_event(t, {"seat": seat, "hand": turn_hand})
	match t:
		"hit":
			var c := _draw()
			h["cards"].append(c)
			chips.log_event("card", {"seat": seat, "hand": turn_hand, "card": c})
			if total(h["cards"])[0] >= 21:
				h["done"] = true
		"stand":
			h["done"] = true
		"double":
			chips.transfer(acct(seat), "table", h["bet"], "double")
			h["bet"] = h["bet"] * 2
			h["doubled"] = true
			var c := _draw()
			h["cards"].append(c)
			chips.log_event("card", {"seat": seat, "hand": turn_hand, "card": c})
			h["done"] = true
		"split":
			chips.transfer(acct(seat), "table", h["bet"], "split")
			var aces: bool = card_value(h["cards"][0]) == 11
			var nh := _new_hand(h["bet"])
			nh["cards"] = [h["cards"][1]]
			h["cards"] = [h["cards"][0]]
			h["split"] = true
			nh["split"] = true
			h["split_aces"] = aces
			nh["split_aces"] = aces
			hands.insert(turn_hand + 1, nh)
			var c := _draw()
			h["cards"].append(c)
			chips.log_event("card", {"seat": seat, "hand": turn_hand, "card": c})
			if aces:
				h["done"] = true
				var c2 := _draw()
				nh["cards"].append(c2)
				chips.log_event("card", {"seat": seat, "hand": turn_hand + 1, "card": c2})
				nh["done"] = true
			elif total(h["cards"])[0] == 21:
				h["done"] = true
	if h["done"]:
		_advance()
	return null


func _dealer_play() -> void:
	hole_shown = true
	chips.log_event("dealer_reveal", {"card": dealer[1]})
	var live := false
	for s in seats:
		for h in s["hands"]:
			if total(h["cards"])[0] <= 21 and not is_natural(h):
				live = true
	if not live:
		return
	while total(dealer)[0] < 17:
		var c := _draw()
		dealer.append(c)
		chips.log_event("dealer_card", {"card": c})


func _finish_round() -> void:
	if not hole_shown:
		hole_shown = true
		chips.log_event("dealer_reveal", {"card": dealer[1]})
	var dt: int = total(dealer)[0]
	var dbj: bool = dealer.size() == 2 and dt == 21
	for i in seats.size():
		var hands: Array = seats[i]["hands"]
		for hi in hands.size():
			var h: Dictionary = hands[hi]
			var bet: int = h["bet"]
			var pt: int = total(h["cards"])[0]
			var res := ""
			var win := 0
			if is_natural(h):
				if dbj:
					res = "push"
				else:
					res = "blackjack"
					win = bet * 3 / 2  # 3:2, rounded down to the chip
			elif dbj:
				res = "lose"
			elif pt > 21:
				res = "bust"
			elif dt > 21 or pt > dt:
				res = "win"
				win = bet
			elif pt == dt:
				res = "push"
			else:
				res = "lose"
			if res == "lose" or res == "bust":
				chips.transfer("table", "house", bet, "lost")
			else:
				chips.transfer("table", acct(i), bet, "bet_returned")
				if win > 0:
					chips.transfer("house", acct(i), win, "win")
			h["result"] = res
			h["paid"] = win if res != "lose" and res != "bust" else -bet
			chips.log_event("result", {"seat": i, "hand": hi, "result": res, "net": h["paid"]})
	phase = "betting"
	turn_seat = -1
	turn_hand = -1
	chips.log_event("round_end", {"round": round_no, "dealer": dealer.duplicate(), "dealer_total": dt})
	_flush_reveals()


# ----------------------------------------------------------------- views / state

## What a player at `seat` may see: everything but the hole card before it is
## turned, and the shoe order. Spectators pass -1.
func view_for(seat: int) -> Dictionary:
	var d := []
	for i in dealer.size():
		d.append(dealer[i] if (i != 1 or hole_shown) else -1)
	var ss := []
	for i in seats.size():
		var s: Dictionary = seats[i]
		ss.append({"seat": i, "player": s["player"], "stack": stack(i) if s["player"] != "" else 0,
			"bet": s["bet"], "insurance": s["insurance"], "hands": s["hands"].duplicate(true)})
	return {"seat": seat, "phase": phase, "round": round_no, "dealer": d,
		"dealer_total": total(dealer)[0] if hole_shown else (card_value(dealer[0]) if dealer.size() > 0 else 0),
		"seats": ss, "turn_seat": turn_seat, "turn_hand": turn_hand,
		"shoe_left": Cards.shoe_left(shoe) if not shoe.is_empty() else 0, "legal": legal_actions(seat),
		"min_bet": cfg["min_bet"], "max_bet": cfg["max_bet"]}


## The events a seat may receive, from apply()'s raw_events: the "seed" event
## of a shoe still in use is dropped ("seed_reveal" publishes it later).
## Blackjack has no other per-seat secret: the hole card is never in an event
## before "dealer_reveal".
static func events_for(_seat: int, evts: Array) -> Array:
	return evts.filter(func(e): return e.get("type", "") != "seed")


func to_dict() -> Dictionary:
	return {
		"game": "blackjack", "v": 1,
		"cfg": cfg.duplicate(), "rng": rng.to_dict(), "chips": chips.to_dict(),
		"shoe": shoe.duplicate(true), "phase": phase, "round": round_no,
		"seats": seats.duplicate(true), "dealer": dealer.duplicate(), "hole_shown": hole_shown,
		"turn_seat": turn_seat, "turn_hand": turn_hand, "shoe_no": shoe_no,
		"pending_reveal": pending_reveal.duplicate(true), "reserve_seed": reserve_seed.duplicate(),
	}


func from_dict(d: Dictionary) -> void:
	var n = Chips.norm(d)
	cfg = n["cfg"]
	rng.from_dict(n["rng"])
	chips = Chips.new()
	chips.from_dict(n["chips"])
	shoe = n["shoe"]
	phase = n["phase"]
	round_no = n["round"]
	seats = n["seats"]
	dealer = n["dealer"]
	hole_shown = n["hole_shown"]
	turn_seat = n["turn_seat"]
	turn_hand = n["turn_hand"]
	shoe_no = int(n.get("shoe_no", 0))
	pending_reveal = n.get("pending_reveal", [])
	reserve_seed = n.get("reserve_seed", [])
