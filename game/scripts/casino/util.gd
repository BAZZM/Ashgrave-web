extends RefCounted
## Small shared helpers: strict reading of action fields that may have come
## through JSON (numbers arrive as floats), the apply() result shapes, and
## taking a seed from a seed source.

const Rng := preload("res://scripts/casino/rng.gd")


## An int from an int, or from a float holding a whole number; else `fallback`.
static func as_int(v: Variant, fallback: Variant = null) -> Variant:
	if typeof(v) == TYPE_INT:
		return v
	if typeof(v) == TYPE_FLOAT and is_finite(v) and v == floorf(v) and absf(v) < 9.0e15:
		return int(v)
	return fallback


static func field_int(d: Dictionary, key: String) -> Variant:
	return as_int(d.get(key), null)


static func field_str(d: Dictionary, key: String) -> Variant:
	var v = d.get(key)
	if typeof(v) == TYPE_STRING or typeof(v) == TYPE_STRING_NAME:
		return String(v)
	return null


## Array of ints from a state array (JSON floats included).
static func ints(a: Variant) -> Array:
	var out := []
	if typeof(a) != TYPE_ARRAY:
		return out
	for x in a:
		out.append(int(x))
	return out


## A successful apply(). "raw_events" is the server-side log slice: it can hold
## secrets (hole cards, seeds). Clients get a game's events_for() of it only.
static func ok(events: Array) -> Dictionary:
	return {"ok": true, "raw_events": events}


static func err(code: String, message := "") -> Dictionary:
	return {"ok": false, "error": code, "message": message if message != "" else code}


## Common entry checks for apply(): returns [type, error_dict_or_null].
static func action_type(action: Variant) -> Array:
	if typeof(action) != TYPE_DICTIONARY:
		return ["", err("bad_action", "action must be a Dictionary")]
	var t = field_str(action, "type")
	if t == null:
		return ["", err("bad_action", "action needs a String 'type'")]
	return [t, null]


## A fresh 128-bit seed (four u32) from `source`, or [] when there is no
## source or it returned something that is not a seed.
static func take_seed(source: Variant) -> Array:
	if source == null or typeof(source) != TYPE_OBJECT or not source.has_method("next_seed"):
		return []
	return Rng.parse_seed(source.next_seed())
