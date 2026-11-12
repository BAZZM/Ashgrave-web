extends RefCounted
## Roulette. European single zero by default; {"wheel": "american"} adds 00.
##
## Pockets are ints 0..36, and 37 means 00. The core draws the pocket; the wheel
## animation must land on spin's "result". Even-money bets lose on zero (no
## la partage / en prison).
##
## Bets (kind: payout to 1):
##   straight 35, split 17, street 11, trio 11, corner 8, line (six line) 5,
##   basket 8 on European (0-1-2-3, "first four"), 6 on American (0-00-1-2-3,
##   "top line"), dozen 2 / column 2 (index 1..3), red black odd even low high 1.
## Inside bets name their pockets in "numbers"; they must be a real table spot.
##
## Accounts: "seat<i>", "table" (bets down), "house" (unbounded).

const U := preload("res://scripts/casino/util.gd")
const Rng := preload("res://scripts/casino/rng.gd")
const Chips := preload("res://scripts/casino/chips.gd")

const DOUBLE_ZERO := 37
const RED := [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36]
const INSIDE := ["straight", "split", "street", "trio", "corner", "line", "basket"]
const OUTSIDE := ["red", "black", "odd", "even", "low", "high", "dozen", "column"]

var cfg: Dictionary = {}
var rng = Rng.new()
var chips = Chips.new()
var seats: Array = []
var bets: Array = []
var spins := 0
var history: Array = []
var _spots: Dictionary = {}


func _init(config: Dictionary = {}, seed: int = 1) -> void:
	var w := String(config.get("wheel", "european"))
	cfg = {
		"wheel": "american" if w == "american" else "european",
		"seats": clampi(int(config.get("seats", 6)), 1, 8),
		"min_bet": maxi(1, int(config.get("min_bet", 1))),
		"max_bet": maxi(1, int(config.get("max_bet", 1000000))),
		"max_bets": maxi(1, int(config.get("max_bets", 64))),
	}
	rng.seed_with(seed)
	chips.open("house", 0, true)
	chips.open("table", 0)
	for i in cfg["seats"]:
		seats.append({"player": ""})
	_build_spots()


func american() -> bool:
	return cfg["wheel"] == "american"


func pockets() -> int:
	return 38 if american() else 37


static func label(n: int) -> String:
	return "00" if n == DOUBLE_ZERO else str(n)


static func color(n: int) -> String:
	if n == 0 or n == DOUBLE_ZERO:
		return "green"
	return "red" if n in RED else "black"


func payout(kind: String) -> int:
	match kind:
		"straight": return 35
		"split": return 17
		"street", "trio": return 11
		"corner": return 8
		"basket": return 6 if american() else 8
		"line": return 5
		"dozen", "column": return 2
	return 1


static func _key(nums: Array) -> String:
	var a := nums.duplicate()
	a.sort()
	return ",".join(PackedStringArray(a.map(func(x): return str(x))))


## Every legal inside spot for this wheel, keyed by kind then sorted pockets.
func _build_spots() -> void:
	var sp := {}
	for k in INSIDE:
		sp[k] = {}
	var top := 37 if american() else 36
	for n in range(0, top + 1):
		sp["straight"][_key([n])] = true
	for n in range(1, 37):
		if n % 3 != 0:
			sp["split"][_key([n, n + 1])] = true
		if n <= 33:
			sp["split"][_key([n, n + 3])] = true
	for r in 12:
		var a := r * 3 + 1
		sp["street"][_key([a, a + 1, a + 2])] = true
		if r < 11:
			sp["line"][_key([a, a + 1, a + 2, a + 3, a + 4, a + 5])] = true
	for n in range(1, 33):
		if n % 3 != 0:
			sp["corner"][_key([n, n + 1, n + 3, n + 4])] = true
	if american():
		for s in [[0, 1], [0, 2], [DOUBLE_ZERO, 2], [DOUBLE_ZERO, 3], [0, DOUBLE_ZERO]]:
			sp["split"][_key(s)] = true
		for s in [[0, 1, 2], [0, DOUBLE_ZERO, 2], [DOUBLE_ZERO, 2, 3]]:
			sp["trio"][_key(s)] = true
		sp["basket"][_key([0, DOUBLE_ZERO, 1, 2, 3])] = true
	else:
		for s in [[0, 1], [0, 2], [0, 3]]:
			sp["split"][_key(s)] = true
		for s in [[0, 1, 2], [0, 2, 3]]:
			sp["trio"][_key(s)] = true
		sp["basket"][_key([0, 1, 2, 3])] = true
	_spots = sp


## Pockets a bet covers, or [] when the bet is not a real spot.
func covers(kind: String, numbers: Array, index: int) -> Array:
	if kind in INSIDE:
		if kind == "basket" and numbers.is_empty():
			numbers = [0, DOUBLE_ZERO, 1, 2, 3] if american() else [0, 1, 2, 3]
		if not _spots[kind].has(_key(numbers)):
			return []
		var a := numbers.duplicate()
		a.sort()
		return a
	var out := []
	for n in range(1, 37):
		var hit := false
		match kind:
			"red": hit = n in RED
			"black": hit = not (n in RED)
			"odd": hit = n % 2 == 1
			"even": hit = n % 2 == 0
			"low": hit = n <= 18
			"high": hit = n >= 19
			"dozen": hit = index >= 1 and index <= 3 and (n - 1) / 12 == index - 1
			"column": hit = index >= 1 and index <= 3 and ((n - 1) % 3) + 1 == index
		if hit:
			out.append(n)
	return out


static func acct(i: int) -> String:
	return "seat%d" % i


func apply(action: Variant) -> Dictionary:
	var tt := U.action_type(action)
	if tt[1] != null:
		return tt[1]
	var t: String = tt[0]
	var s0: int = chips.seq
	var e = null
	var seat = U.field_int(action, "seat")
	if t in ["sit", "leave", "bet", "clear"]:
		if seat == null or seat < 0 or seat >= seats.size():
			return U.err("bad_seat")
		if t != "sit" and seats[seat]["player"] == "":
			return U.err("empty_seat")
	match t:
		"sit":
			e = _sit(seat, action)
		"leave":
			_clear(seat)
			var p: String = seats[seat]["player"]
			var amt: int = chips.close(acct(seat))
			seats[seat] = {"player": ""}
			chips.log_event("leave", {"seat": seat, "player": p, "cash_out": amt})
		"bet":
			e = _bet(seat, action)
		"clear":
			_clear(seat)
		"spin":
			e = _spin()
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
	if buy == null or buy < 0:
		return U.err("bad_amount")
	seats[seat] = {"player": p}
	chips.open(acct(seat), buy)
	chips.log_event("sit", {"seat": seat, "player": p, "buy_in": buy})
	return null


func _bet(seat: int, a: Dictionary):
	var kind = U.field_str(a, "kind")
	if kind == null or not (kind in INSIDE or kind in OUTSIDE):
		return U.err("bad_kind")
	var amt = U.field_int(a, "amount")
	if amt == null or amt < cfg["min_bet"] or amt > cfg["max_bet"]:
		return U.err("bet_limits", "bet must be %d..%d" % [cfg["min_bet"], cfg["max_bet"]])
	if amt > chips.balance(acct(seat)):
		return U.err("insufficient_chips")
	if bets.size() >= cfg["max_bets"]:
		return U.err("too_many_bets")
	var nums := []
	var raw = a.get("numbers", [])
	if typeof(raw) != TYPE_ARRAY:
		return U.err("bad_numbers")
	for x in raw:
		var n = U.as_int(x)
		if n == null or n < 0 or n > (DOUBLE_ZERO if american() else 36):
			return U.err("bad_numbers")
		nums.append(n)
	var idx = U.field_int(a, "index")
	if kind == "dozen" or kind == "column":
		if idx == null or idx < 1 or idx > 3:
			return U.err("bad_index", "dozen and column need index 1..3")
	else:
		idx = 0
	var cov := covers(kind, nums, idx)
	if cov.is_empty():
		return U.err("bad_spot", "%s on %s is not a table spot" % [kind, str(nums)])
	if kind in OUTSIDE:
		nums = []
	else:
		nums = cov
	var b := {"seat": seat, "kind": kind, "numbers": nums, "index": idx, "amount": amt}
	bets.append(b)
	chips.transfer(acct(seat), "table", amt, "bet")
	chips.log_event("bet", b.duplicate(true))
	return null


func _clear(seat: int) -> void:
	var keep := []
	for b in bets:
		if b["seat"] == seat:
			chips.transfer("table", acct(seat), b["amount"], "bet_returned")
		else:
			keep.append(b)
	if keep.size() != bets.size():
		chips.log_event("clear", {"seat": seat})
	bets = keep


func _spin():
	var r := rng.next_below(pockets())
	spins += 1
	chips.log_event("spin", {"spin": spins, "result": r, "label": label(r), "color": color(r)})
	for b in bets:
		var cov := covers(b["kind"], b["numbers"], b["index"])
		var amt: int = b["amount"]
		var s: int = b["seat"]
		if r in cov:
			var win: int = amt * payout(b["kind"])
			chips.transfer("table", acct(s), amt, "bet_returned")
			chips.transfer("house", acct(s), win, "win")
			chips.log_event("result", {"seat": s, "kind": b["kind"], "amount": amt, "net": win})
		else:
			chips.transfer("table", "house", amt, "lost")
			chips.log_event("result", {"seat": s, "kind": b["kind"], "amount": amt, "net": -amt})
	bets = []
	history.append(r)
	if history.size() > 50:
		history = history.slice(history.size() - 50)
	return null


func view_for(seat: int) -> Dictionary:
	var ss := []
	for i in seats.size():
		ss.append({"seat": i, "player": seats[i]["player"], "stack": chips.balance(acct(i))})
	return {"seat": seat, "wheel": cfg["wheel"], "seats": ss, "bets": bets.duplicate(true),
		"history": history.duplicate(), "spins": spins, "min_bet": cfg["min_bet"], "max_bet": cfg["max_bet"]}


func to_dict() -> Dictionary:
	return {"game": "roulette", "v": 1, "cfg": cfg.duplicate(), "rng": rng.to_dict(),
		"chips": chips.to_dict(), "seats": seats.duplicate(true), "bets": bets.duplicate(true),
		"spins": spins, "history": history.duplicate()}


func from_dict(d: Dictionary) -> void:
	var n = Chips.norm(d)
	cfg = n["cfg"]
	rng.from_dict(n["rng"])
	chips = Chips.new()
	chips.from_dict(n["chips"])
	seats = n["seats"]
	bets = n["bets"]
	spins = n["spins"]
	history = n["history"]
	_build_spots()
