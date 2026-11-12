extends RefCounted
## Integer chip ledger and the append-only event log every casino game writes.
##
## Chips only move by transfer() between named accounts, so the sum of all
## balances changes only through open() (chips sat down at the table) and
## close() (chips cashed out), both of which are logged. Only accounts opened
## as unbounded (the house) may go below zero.
##
## Every event is a plain Dictionary with a rising "seq" and a "type". A UI can
## replay them; a server can audit them with replay(). trim() lets the host drop
## events it has already stored; seq keeps counting.

const U := preload("res://scripts/casino/util.gd")

var balances: Dictionary = {}
var unbounded: Dictionary = {}
var opened := 0
var closed := 0
var seq := 0
var events: Array = []
## Count of refused internal transfers. A correct game never causes one.
var faults := 0


func has(account: String) -> bool:
	return balances.has(account)


func balance(account: String) -> int:
	return int(balances.get(account, 0))


func total() -> int:
	var t := 0
	for k in balances:
		t += int(balances[k])
	return t


func log_event(type: String, data: Dictionary = {}) -> Dictionary:
	seq += 1
	var e := {"seq": seq, "type": type}
	for k in data:
		e[k] = data[k]
	events.append(e)
	return e


func open(account: String, amount: int, is_unbounded := false) -> bool:
	if balances.has(account) or amount < 0:
		faults += 1
		return false
	balances[account] = amount
	if is_unbounded:
		unbounded[account] = true
	opened += amount
	log_event("open", {"account": account, "amount": amount})
	return true


## Removes the account and returns what it held (chips leave the table).
func close(account: String) -> int:
	if not balances.has(account):
		return 0
	var amt := int(balances[account])
	balances.erase(account)
	unbounded.erase(account)
	closed += amt
	log_event("close", {"account": account, "amount": amt})
	return amt


func can_pay(account: String, amount: int) -> bool:
	return balances.has(account) and (unbounded.has(account) or int(balances[account]) >= amount)


func transfer(from: String, to: String, amount: int, reason: String) -> bool:
	if amount < 0 or not balances.has(from) or not balances.has(to) or not can_pay(from, amount):
		faults += 1
		return false
	if amount == 0:
		return true
	balances[from] = int(balances[from]) - amount
	balances[to] = int(balances[to]) + amount
	log_event("transfer", {"from": from, "to": to, "amount": amount, "reason": reason})
	return true


func events_since(seq0: int) -> Array:
	var n := seq - seq0
	if n <= 0:
		return []
	var start := maxi(0, events.size() - n)
	return events.slice(start)


func trim(upto_seq: int) -> void:
	var keep := []
	for e in events:
		if int(e["seq"]) > upto_seq:
			keep.append(e)
	events = keep


## Balances after applying the open/close/transfer events to `start`.
static func replay(evts: Array, start: Dictionary) -> Dictionary:
	var b := start.duplicate()
	for e in evts:
		match String(e.get("type", "")):
			"open":
				b[e["account"]] = int(e["amount"])
			"close":
				b.erase(e["account"])
			"transfer":
				b[e["from"]] = int(b.get(e["from"], 0)) - int(e["amount"])
				b[e["to"]] = int(b.get(e["to"], 0)) + int(e["amount"])
	return b


func to_dict() -> Dictionary:
	return {
		"balances": balances.duplicate(),
		"unbounded": unbounded.keys(),
		"opened": opened,
		"closed": closed,
		"seq": seq,
		"faults": faults,
		"events": events.duplicate(true),
	}


func from_dict(d: Dictionary) -> void:
	balances = {}
	var b = d.get("balances", {})
	for k in b:
		balances[String(k)] = int(b[k])
	unbounded = {}
	for k in d.get("unbounded", []):
		unbounded[String(k)] = true
	opened = int(d.get("opened", 0))
	closed = int(d.get("closed", 0))
	seq = int(d.get("seq", 0))
	faults = int(d.get("faults", 0))
	events = _norm(d.get("events", []))


## JSON turns ints into floats; put whole numbers back to ints, deeply.
static func _norm(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			var i = U.as_int(v)
			return i if i != null else v
		TYPE_ARRAY:
			var out := []
			for x in v:
				out.append(_norm(x))
			return out
		TYPE_DICTIONARY:
			var o := {}
			for k in v:
				o[k] = _norm(v[k])
			return o
	return v


static func norm(v: Variant) -> Variant:
	return _norm(v)
