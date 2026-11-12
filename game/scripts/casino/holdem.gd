extends RefCounted
## No-limit Texas Hold'em, up to six seats, as a state machine.
##
## Table actions (any time): sit {seat, player, buy_in}, leave {seat},
## sit_out {seat}, sit_in {seat}, top_up {seat, amount} (between hands only),
## start_hand {}. Player actions on their turn: fold, check, call,
## bet/raise {to} ("to" is the street total, the two names are aliases).
##
## Rules (see docs/CASINO_CORE.md for the reasoning and alternatives):
## - Moving button: it advances to the next seat dealt in. No dead button and
##   no missed-blind posting; a new player is dealt in at once.
## - Heads-up: the button posts the small blind and acts first preflop, last after.
## - A blind or ante that a player cannot cover is posted all-in; the amount to
##   call stays the full big blind.
## - Minimum raise is the size of the last full bet or raise (at least the big
##   blind). An all-in for less than that is a short raise: it does not reopen
##   betting to anyone who already acted, unless short raises add up to a full
##   raise over what that player last faced (TDA).
## - No raise is offered when nobody left could call it.
## - Uncalled chips go back to the bettor at the end of each betting round.
## - When betting is over with two or more hands live and someone all-in, every
##   live hand is shown at once. At showdown hands are shown starting with the
##   last river aggressor, else the first live seat left of the button.
## - Odd chips of a split pot go one at a time to the winners clockwise from the
##   seat left of the button. No rake.
## - leave mid-hand folds the hand (unless all-in, which plays on), even out of
##   turn; the stack is cashed out when the hand ends. A leaver's bet stands
##   for the players still to act, and any part of it nobody calls goes back
##   to the leaver like any other uncalled bet.
## - One player name holds at most one seat. A top-up must leave the stack
##   between the minimum and maximum buy-in.
##
## Randomness: every hand is shuffled by a generator freshly seeded with 128
## bits from `seed_source.next_seed()`. The seed is logged in a "seed" event
## and in the hand history; events_for() withholds it until "hand_end", which
## carries it (the hand is over, so it reveals nothing still in play).
##
## SENDABLE to a client: view_for(seat) and events_for(seat, raw_events) only.
## SERVER-ONLY: apply()'s "raw_events" (all hole cards, the seed), to_dict()
## (RNG state and deck), audit_history (every hand's hole cards and seed).
##
## Accounts: "seat<i>" stacks, "pot" (everything committed this hand).

const U := preload("res://scripts/casino/util.gd")
const Cards := preload("res://scripts/casino/cards.gd")
const Rng := preload("res://scripts/casino/rng.gd")
const Chips := preload("res://scripts/casino/chips.gd")
const Eval := preload("res://scripts/casino/hand_eval.gd")

const STREETS := ["preflop", "flop", "turn", "river"]
const HISTORY_KEEP := 20

var cfg: Dictionary = {}
var rng = Rng.new()
var chips = Chips.new()
var seats: Array = []
var hand_no := 0
var phase := "waiting"  # waiting | betting
var street := ""
var button := -1
var sb_seat := -1
var bb_seat := -1
var deck: Array = []
var deck_pos := 0
var board: Array = []
var to_act := -1
var current_bet := 0
var last_raise := 0
var last_aggressor := -1
var hist: Dictionary = {}
var audit_history: Array = []
var hand_seed := ""
## Object with next_seed() (see rng.gd). Not serialised: pass it again after
## from_dict().
var seed_source = null


func _init(config: Dictionary = {}, source = null) -> void:
	var bb := maxi(2, int(config.get("bb", 2)))
	cfg = {
		"seats": clampi(int(config.get("seats", 6)), 2, 6),
		"sb": clampi(int(config.get("sb", bb / 2)), 1, bb),
		"bb": bb,
		"ante": maxi(0, int(config.get("ante", 0))),
		"min_buy_in": maxi(1, int(config.get("min_buy_in", bb * 20))),
		"max_buy_in": maxi(1, int(config.get("max_buy_in", bb * 250))),
	}
	seed_source = source
	chips.open("pot", 0)
	for i in cfg["seats"]:
		seats.append(_empty_seat())


static func _empty_seat() -> Dictionary:
	return {"player": "", "sitting_out": false, "leaving": false, "in_hand": false,
		"folded": false, "all_in": false, "hole": [], "bet": 0, "total": 0,
		"acted": false, "acted_at": -1, "shown": false}


static func acct(i: int) -> String:
	return "seat%d" % i


func n_seats() -> int:
	return seats.size()


func stack(i: int) -> int:
	return chips.balance(acct(i))


func _live(i: int) -> bool:
	return seats[i]["in_hand"] and not seats[i]["folded"]


func _can_act(i: int) -> bool:
	return _live(i) and not seats[i]["all_in"]


func _live_count() -> int:
	var n := 0
	for i in n_seats():
		if _live(i):
			n += 1
	return n


func _can_act_count() -> int:
	var n := 0
	for i in n_seats():
		if _can_act(i):
			n += 1
	return n


func _eligible(i: int) -> bool:
	var s: Dictionary = seats[i]
	return s["player"] != "" and not s["sitting_out"] and not s["leaving"] and stack(i) > 0


func _next(from: int, pred: Callable) -> int:
	var n := n_seats()
	for k in range(1, n + 1):
		var i := (from + k + n) % n
		if pred.call(i):
			return i
	return -1


func _ev(type: String, data: Dictionary = {}) -> void:
	chips.log_event(type, data)


func _act_log(seat: int, type: String, amount: int = -1) -> void:
	if hist.is_empty():
		return
	var a := {"street": street, "seat": seat, "type": type}
	if amount >= 0:
		a["amount"] = amount
	hist["actions"].append(a)


# ----------------------------------------------------------------- apply

func apply(action: Variant) -> Dictionary:
	var tt := U.action_type(action)
	if tt[1] != null:
		return tt[1]
	var t: String = tt[0]
	var s0: int = chips.seq
	var e = null
	var seat = U.field_int(action, "seat")
	if t != "start_hand":
		if seat == null or seat < 0 or seat >= n_seats():
			return U.err("bad_seat")
		if t != "sit" and seats[seat]["player"] == "":
			return U.err("empty_seat")
	match t:
		"sit":
			e = _sit(seat, action)
		"leave":
			e = _leave(seat)
		"sit_out":
			seats[seat]["sitting_out"] = true
			_ev("sit_out", {"seat": seat})
		"sit_in":
			seats[seat]["sitting_out"] = false
			_ev("sit_in", {"seat": seat})
		"top_up":
			e = _top_up(seat, action)
		"start_hand":
			e = _start_hand()
		"fold", "check", "call", "bet", "raise":
			e = _player_action(seat, t, action)
		_:
			e = U.err("unknown_action", "unknown action '%s'" % t)
	if e != null:
		return e
	return U.ok(chips.events_since(s0))


func _sit(seat: int, a: Dictionary):
	if seats[seat]["player"] != "" or chips.has(acct(seat)):
		return U.err("seat_taken")
	var p = U.field_str(a, "player")
	var buy = U.field_int(a, "buy_in")
	if p == null or p == "":
		return U.err("bad_player")
	if buy == null or buy < cfg["min_buy_in"] or buy > cfg["max_buy_in"]:
		return U.err("bad_amount", "buy-in must be %d..%d" % [cfg["min_buy_in"], cfg["max_buy_in"]])
	for s in seats:
		if s["player"] == p:
			return U.err("player_seated", "%s already has a seat" % p)
	seats[seat] = _empty_seat()
	seats[seat]["player"] = p
	chips.open(acct(seat), buy)
	_ev("sit", {"seat": seat, "player": p, "buy_in": buy})
	return null


func _top_up(seat: int, a: Dictionary):
	if phase != "waiting" and seats[seat]["in_hand"]:
		return U.err("in_hand", "top up between hands")
	var amt = U.field_int(a, "amount")
	if amt == null or amt <= 0 or stack(seat) + amt > cfg["max_buy_in"] or stack(seat) + amt < cfg["min_buy_in"]:
		return U.err("bad_amount", "stack after top-up must be %d..%d" % [cfg["min_buy_in"], cfg["max_buy_in"]])
	# A top-up is new chips sitting down: the account is reopened larger.
	var have: int = chips.close(acct(seat))
	chips.open(acct(seat), have + amt)
	_ev("top_up", {"seat": seat, "amount": amt})
	return null


func _cash_out(seat: int) -> void:
	var p: String = seats[seat]["player"]
	var amt: int = chips.close(acct(seat))
	seats[seat] = _empty_seat()
	_ev("leave", {"seat": seat, "player": p, "cash_out": amt})


func _leave(seat: int):
	var s: Dictionary = seats[seat]
	if phase != "betting" or not s["in_hand"]:
		_cash_out(seat)
		return null
	if s["leaving"]:
		return U.err("already_leaving")
	s["leaving"] = true
	_ev("leaving", {"seat": seat})
	if s["folded"] or s["all_in"]:
		return null
	s["folded"] = true
	_ev("fold", {"seat": seat, "reason": "leave"})
	_act_log(seat, "fold")
	if _live_count() <= 1:
		_end_betting_round()
	elif to_act == seat or not _needs_action(to_act):
		_after_action(to_act)
	return null


# ----------------------------------------------------------------- hand start

func _start_hand():
	if phase != "waiting":
		return U.err("hand_in_progress")
	var elig := []
	for i in n_seats():
		if _eligible(i):
			elig.append(i)
	if elig.size() < 2:
		return U.err("not_enough_players")
	var words := U.take_seed(seed_source)
	if words.is_empty():
		return U.err("no_seed", "the seed source gave no valid 128-bit seed")
	hand_no += 1
	for i in n_seats():
		var s: Dictionary = seats[i]
		var keep := {"player": s["player"], "sitting_out": s["sitting_out"], "leaving": s["leaving"]}
		seats[i] = _empty_seat()
		for k in keep:
			seats[i][k] = keep[k]
		seats[i]["in_hand"] = i in elig
	var in_hand := func(i): return seats[i]["in_hand"]
	button = _next(button if button >= 0 else n_seats() - 1, in_hand)
	if elig.size() == 2:
		sb_seat = button
		bb_seat = _next(button, in_hand)
	else:
		sb_seat = _next(button, in_hand)
		bb_seat = _next(sb_seat, in_hand)
	rng = Rng.new()
	rng.seed_128(words)
	hand_seed = Rng.seed_hex(words)
	deck = Cards.deck()
	rng.shuffle(deck)
	deck_pos = 0
	board = []
	street = "preflop"
	phase = "betting"
	last_aggressor = -1
	var players := []
	for i in elig:
		players.append({"seat": i, "player": seats[i]["player"], "stack": stack(i)})
	hist = {"hand": hand_no, "seed": hand_seed, "button": button, "sb": sb_seat, "bb": bb_seat,
		"blinds": [cfg["sb"], cfg["bb"], cfg["ante"]], "players": players,
		"actions": [], "board": [], "shown": [], "awards": []}
	_ev("seed", {"unit": "hand", "hand": hand_no, "seed": hand_seed})
	_ev("hand_start", {"hand": hand_no, "button": button, "sb": sb_seat, "bb": bb_seat, "players": players.duplicate(true)})
	if cfg["ante"] > 0:
		var i := sb_seat
		for k in elig.size():
			_commit(i, mini(cfg["ante"], stack(i)), false, "ante")
			i = _next(i, in_hand)
	_commit(sb_seat, mini(cfg["sb"], stack(sb_seat)), true, "small_blind")
	_commit(bb_seat, mini(cfg["bb"], stack(bb_seat)), true, "big_blind")
	current_bet = cfg["bb"]
	last_raise = cfg["bb"]
	# Deal: one card at a time from the seat left of the button.
	for r in 2:
		var i := _next(button, in_hand)
		for k in elig.size():
			seats[i]["hole"].append(_draw())
			i = _next(i, in_hand)
	for i in elig:
		_ev("hole", {"seat": i, "cards": seats[i]["hole"].duplicate()})
		for p in hist["players"]:
			if p["seat"] == i:
				p["hole"] = seats[i]["hole"].duplicate()
	to_act = -1
	_after_action(bb_seat)
	return null


func _draw() -> int:
	var c: int = deck[deck_pos]
	deck_pos += 1
	return c


## Moves chips from a stack into the pot. street=true counts toward the bet.
func _commit(i: int, amount: int, on_street: bool, why: String) -> void:
	if amount <= 0:
		return
	chips.transfer(acct(i), "pot", amount, why)
	var s: Dictionary = seats[i]
	if on_street:
		s["bet"] += amount
	s["total"] += amount
	if stack(i) == 0:
		s["all_in"] = true
	_ev("post" if why != "bet" else "commit", {"seat": i, "amount": amount, "kind": why, "all_in": s["all_in"]})


# ----------------------------------------------------------------- betting

func _needs_action(i: int) -> bool:
	if i < 0 or not _can_act(i):
		return false
	var s: Dictionary = seats[i]
	if _can_act_count() == 1 and s["bet"] >= _max_live_bet():
		return false
	return not s["acted"] or s["bet"] < current_bet


func _max_live_bet() -> int:
	var m := 0
	for j in n_seats():
		if _live(j) and seats[j]["bet"] > m:
			m = seats[j]["bet"]
	return m


func _raise_rights(i: int) -> bool:
	var at: int = seats[i]["acted_at"]
	return at < 0 or current_bet - at >= last_raise


func _others_can_act(i: int) -> bool:
	for j in n_seats():
		if j != i and _can_act(j):
			return true
	return false


func min_raise_to() -> int:
	return current_bet + last_raise


func legal_actions(seat: int) -> Array:
	if phase != "betting" or seat != to_act or seat < 0:
		return []
	var s: Dictionary = seats[seat]
	var st := stack(seat)
	var to_call := maxi(0, current_bet - int(s["bet"]))
	var out := [{"type": "fold"}]
	if to_call == 0:
		out.append({"type": "check"})
	else:
		out.append({"type": "call", "amount": mini(to_call, st), "all_in": st <= to_call})
	if st > to_call and _raise_rights(seat) and _others_can_act(seat):
		var max_to: int = s["bet"] + st
		var min_to := mini(min_raise_to(), max_to)
		out.append({"type": "bet" if current_bet == 0 else "raise", "min": min_to, "max": max_to})
	return out


func _player_action(seat: int, t: String, a: Dictionary):
	if phase != "betting":
		return U.err("no_hand")
	if seat != to_act:
		return U.err("not_your_turn")
	var legal := legal_actions(seat)
	var s: Dictionary = seats[seat]
	match t:
		"fold":
			s["folded"] = true
			_ev("fold", {"seat": seat})
			_act_log(seat, "fold")
		"check":
			if current_bet != s["bet"]:
				return U.err("illegal_action", "cannot check facing a bet")
			s["acted"] = true
			s["acted_at"] = current_bet
			_ev("check", {"seat": seat})
			_act_log(seat, "check")
		"call":
			var amt := mini(current_bet - int(s["bet"]), stack(seat))
			if amt <= 0:
				return U.err("illegal_action", "nothing to call; check")
			_commit(seat, amt, true, "bet")
			s["acted"] = true
			s["acted_at"] = current_bet
			_ev("call", {"seat": seat, "amount": amt, "all_in": s["all_in"]})
			_act_log(seat, "call", amt)
		"bet", "raise":
			var r = null
			for la in legal:
				if la["type"] == "bet" or la["type"] == "raise":
					r = la
			if r == null:
				return U.err("illegal_action", "raising is not allowed now")
			var to = U.field_int(a, "to")
			if to == null:
				return U.err("bad_amount", "bet/raise needs an int 'to'")
			if to < r["min"] or to > r["max"]:
				return U.err("bad_amount", "raise to %d..%d" % [r["min"], r["max"]])
			var add: int = to - int(s["bet"])
			var inc: int = to - current_bet
			var kind := "bet" if current_bet == 0 else "raise"
			_commit(seat, add, true, "bet")
			var full := inc >= last_raise
			if full:
				last_raise = inc
			current_bet = to
			last_aggressor = seat
			for j in n_seats():
				if j != seat and _can_act(j):
					seats[j]["acted"] = false
			s["acted"] = true
			s["acted_at"] = to
			_ev(kind, {"seat": seat, "to": to, "all_in": s["all_in"], "full": full})
			_act_log(seat, kind, to)
	_after_action(seat)
	return null


func _after_action(seat: int) -> void:
	if _live_count() <= 1:
		_end_betting_round()
		return
	var nx := _next(seat, func(i): return _needs_action(i))
	if nx >= 0:
		to_act = nx
		_ev("turn", {"seat": nx})
		return
	_end_betting_round()


func _return_uncalled() -> void:
	var top := -1
	for i in n_seats():
		if seats[i]["in_hand"] and (top < 0 or seats[i]["bet"] > seats[top]["bet"]):
			top = i
	# The top bettor may have folded by leaving: their excess still goes back.
	if top < 0:
		return
	var second := 0
	for i in n_seats():
		if i != top and seats[i]["in_hand"] and seats[i]["bet"] > second:
			second = seats[i]["bet"]
	var back: int = seats[top]["bet"] - second
	if back <= 0:
		return
	chips.transfer("pot", acct(top), back, "uncalled")
	seats[top]["bet"] -= back
	seats[top]["total"] -= back
	seats[top]["all_in"] = false
	_ev("uncalled", {"seat": top, "amount": back})


func _end_betting_round() -> void:
	to_act = -1
	while true:
		_return_uncalled()
		for i in n_seats():
			seats[i]["bet"] = 0
			seats[i]["acted"] = false
			seats[i]["acted_at"] = -1
		if _live_count() <= 1:
			_award_uncontested()
			return
		if street == "river" or _can_act_count() <= 1:
			_show_all()
		if street == "river":
			_showdown()
			return
		_deal_street()
		current_bet = 0
		last_raise = cfg["bb"]
		last_aggressor = -1
		if _can_act_count() >= 2:
			var nx := _next(button, func(i): return _needs_action(i))
			if nx >= 0:
				to_act = nx
				_ev("turn", {"seat": nx})
				return


func _deal_street() -> void:
	_draw()  # burn
	var n := 3 if street == "preflop" else 1
	var cs := []
	for k in n:
		cs.append(_draw())
	board.append_array(cs)
	street = STREETS[STREETS.find(street) + 1]
	hist["board"] = board.duplicate()
	_ev(street, {"cards": cs, "board": board.duplicate()})


func _show_order() -> Array:
	var first := last_aggressor
	if first < 0 or not _live(first):
		first = _next(button, func(i): return _live(i))
	var out := []
	var i := first
	for k in n_seats():
		if _live(i):
			out.append(i)
		i = (i + 1) % n_seats()
	return out


func _show_all() -> void:
	for i in _show_order():
		if not seats[i]["shown"]:
			seats[i]["shown"] = true
			_ev("show", {"seat": i, "cards": seats[i]["hole"].duplicate()})
			hist["shown"].append({"seat": i, "cards": seats[i]["hole"].duplicate()})


## Main pot first. Each pot: {amount, eligible:[seats]}.
func pots() -> Array:
	var levels := []
	for i in n_seats():
		if _live(i) and seats[i]["total"] > 0 and not (seats[i]["total"] in levels):
			levels.append(seats[i]["total"])
	levels.sort()
	var out := []
	var prev := 0
	var given := 0
	for lv in levels:
		var amt := 0
		var elig := []
		for i in n_seats():
			if not seats[i]["in_hand"]:
				continue
			var t: int = seats[i]["total"]
			amt += clampi(t, prev, lv) - prev
			if _live(i) and t >= lv:
				elig.append(i)
		if amt > 0:
			out.append({"amount": amt, "eligible": elig})
			given += amt
		prev = lv
	var all := 0
	for i in n_seats():
		if seats[i]["in_hand"]:
			all += seats[i]["total"]
	if all > given:
		if out.is_empty():
			var live := []
			for i in n_seats():
				if _live(i):
					live.append(i)
			out.append({"amount": all - given, "eligible": live})
		else:
			out[out.size() - 1]["amount"] += all - given
	return out


func _award_uncontested() -> void:
	var w := _next(button, func(i): return _live(i))
	var amt: int = chips.balance("pot")
	chips.transfer("pot", acct(w), amt, "pot")
	_ev("award", {"pot": 0, "amount": amt, "winners": [w], "shares": [amt], "showdown": false})
	hist["awards"].append({"pot": 0, "amount": amt, "winners": [w], "shares": [amt]})
	_end_hand()


func _showdown() -> void:
	var val := {}
	for i in n_seats():
		if _live(i):
			var cs: Array = seats[i]["hole"].duplicate()
			cs.append_array(board)
			var ev := Eval.evaluate(cs)
			val[i] = ev["value"]
			_ev("hand_value", {"seat": i, "name": ev["name"], "value": ev["value"], "best": ev["cards"]})
	var ps := pots()
	for pi in ps.size():
		var p: Dictionary = ps[pi]
		var best := -1
		var winners := []
		for i in p["eligible"]:
			if val[i] > best:
				best = val[i]
				winners = [i]
			elif val[i] == best:
				winners.append(i)
		# Odd chips clockwise from the seat left of the button.
		var ordered := []
		var j := _next(button, func(_i): return true)
		for k in n_seats():
			if j in winners:
				ordered.append(j)
			j = (j + 1) % n_seats()
		var amt: int = p["amount"]
		var share := amt / ordered.size()
		var odd := amt % ordered.size()
		var shares := []
		for k in ordered.size():
			var got := share + (1 if k < odd else 0)
			shares.append(got)
			chips.transfer("pot", acct(ordered[k]), got, "pot")
		_ev("award", {"pot": pi, "amount": amt, "winners": ordered, "shares": shares, "showdown": true})
		hist["awards"].append({"pot": pi, "amount": amt, "winners": ordered, "shares": shares})
	_end_hand()


func _end_hand() -> void:
	phase = "waiting"
	street = ""
	to_act = -1
	var stacks := {}
	for i in n_seats():
		if seats[i]["player"] != "":
			stacks[str(i)] = stack(i)
	hist["stacks"] = stacks
	audit_history.append(hist)
	if audit_history.size() > HISTORY_KEEP:
		audit_history = audit_history.slice(audit_history.size() - HISTORY_KEEP)
	# The hand is over: its seed may now be published for verification.
	_ev("hand_end", {"hand": hand_no, "stacks": stacks, "seed": hand_seed})
	hist = {}
	hand_seed = ""
	for i in n_seats():
		if seats[i]["leaving"]:
			_cash_out(i)


# ----------------------------------------------------------------- views

## Exactly what the player at `seat` may know. Spectators pass -1. Never holds
## the deck, the RNG, the hand's seed or another seat's hole cards unless that
## seat has shown.
func view_for(seat: int) -> Dictionary:
	var ss := []
	for i in n_seats():
		var s: Dictionary = seats[i]
		var hole := []
		if (i == seat or s["shown"]) and s["in_hand"]:
			hole = s["hole"].duplicate()
		ss.append({"seat": i, "player": s["player"], "stack": stack(i) if s["player"] != "" else 0,
			"bet": s["bet"], "committed": s["total"], "in_hand": s["in_hand"], "folded": s["folded"],
			"all_in": s["all_in"], "sitting_out": s["sitting_out"], "leaving": s["leaving"],
			"has_cards": _live(i) and phase == "betting", "hole": hole})
	var mine := []
	if seat >= 0 and seat < n_seats() and seats[seat]["in_hand"]:
		mine = seats[seat]["hole"].duplicate()
	return {"seat": seat, "hand": hand_no, "phase": phase, "street": street, "button": button,
		"sb_seat": sb_seat, "bb_seat": bb_seat, "board": board.duplicate(), "to_act": to_act,
		"pot": chips.balance("pot"), "pots": pots() if phase == "betting" else [],
		"current_bet": current_bet, "min_raise_to": min_raise_to(), "hole": mine,
		"blinds": {"sb": cfg["sb"], "bb": cfg["bb"], "ante": cfg["ante"]},
		"seats": ss, "legal": legal_actions(seat)}


## The events a given seat may receive, from apply()'s raw_events: other
## seats' hole cards are removed and the "seed" event of a hand in play is
## dropped (hand_end carries the seed once the hand is over).
static func events_for(seat: int, evts: Array) -> Array:
	var out := []
	for e in evts:
		if e.get("type", "") == "seed":
			continue
		if e.get("type", "") == "hole" and int(e.get("seat", -1)) != seat:
			var c: Dictionary = e.duplicate()
			c["cards"] = []
			out.append(c)
		else:
			out.append(e)
	return out


# ----------------------------------------------------------------- state

func to_dict() -> Dictionary:
	return {"game": "holdem", "v": 1, "cfg": cfg.duplicate(), "rng": rng.to_dict(),
		"chips": chips.to_dict(), "seats": seats.duplicate(true), "hand_no": hand_no,
		"phase": phase, "street": street, "button": button, "sb_seat": sb_seat, "bb_seat": bb_seat,
		"deck": deck.duplicate(), "deck_pos": deck_pos, "board": board.duplicate(),
		"to_act": to_act, "current_bet": current_bet, "last_raise": last_raise,
		"last_aggressor": last_aggressor, "hist": hist.duplicate(true),
		"audit_history": audit_history.duplicate(true), "hand_seed": hand_seed}


func from_dict(d: Dictionary) -> void:
	var n = Chips.norm(d)
	cfg = n["cfg"]
	rng.from_dict(n["rng"])
	chips = Chips.new()
	chips.from_dict(n["chips"])
	seats = n["seats"]
	hand_no = n["hand_no"]
	phase = n["phase"]
	street = n["street"]
	button = n["button"]
	sb_seat = n["sb_seat"]
	bb_seat = n["bb_seat"]
	deck = n["deck"]
	deck_pos = n["deck_pos"]
	board = n["board"]
	to_act = n["to_act"]
	current_bet = n["current_bet"]
	last_raise = n["last_raise"]
	last_aggressor = n["last_aggressor"]
	hist = n["hist"]
	audit_history = n["audit_history"]
	hand_seed = String(n.get("hand_seed", ""))
