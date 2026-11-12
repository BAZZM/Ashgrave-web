extends RefCounted
## TESTS ONLY: a deterministic seed source (the object the games call
## next_seed() on). Never use it for real chips: its seeds are predictable.
##
##   new(42)              counter mode: an endless stream derived from 42
##   new(["<hex>", ...])  list mode: these seeds in order, then [] (invalid)
##   new("<hex>", true)   constant mode: the same seed every time
## `calls` counts next_seed() calls; `given` keeps every seed handed out.

const Rng := preload("res://scripts/casino/rng.gd")

var calls := 0
var given: Array = []
var _list = null
var _const = null
var _gen = null


func _init(src: Variant = 0, constant := false) -> void:
	if constant:
		_const = src
	elif typeof(src) == TYPE_ARRAY:
		_list = (src as Array).duplicate()
	else:
		_gen = Rng.test_only_from_int(int(src) * 2654435761 + 97)


func next_seed() -> Variant:
	calls += 1
	var out: Variant
	if _const != null:
		out = _const
	elif _list != null:
		out = _list[calls - 1] if calls - 1 < _list.size() else []
	else:
		out = Rng.seed_hex([_gen.next_u32(), _gen.next_u32(), _gen.next_u32(), _gen.next_u32()])
	given.append(out)
	return out
