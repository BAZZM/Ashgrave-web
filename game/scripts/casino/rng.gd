extends RefCounted
## Seedable, portable random generator for the casino core.
##
## Algorithm: xoshiro128** (Blackman & Vigna), state seeded by splitmix32.
## Every operation is done on 32-bit values held in 64-bit ints and masked, so
## the same seed gives the same stream on every platform and in the Python
## reference (tools/casino_tests/ref_eval.py). Never use randi()/randf() in the
## casino: pass one of these in, so a seed reproduces a game exactly.
##
## The state is secret on a server: whoever holds it can predict every card.

const M32 := 0xFFFFFFFF

var s: Array = [0, 0, 0, 0]


static func mul32(a: int, b: int) -> int:
	# 32x32 -> low 32 bits without ever exceeding 2^48 in a 64-bit int.
	return ((a * (b & 0xFFFF)) + (((a * (b >> 16)) & 0xFFFF) << 16)) & M32


static func _rotl(x: int, k: int) -> int:
	return ((x << k) | (x >> (32 - k))) & M32


func seed_with(seed: int) -> void:
	var lo := seed & M32
	var hi := (seed >> 32) & M32
	var sm := (lo ^ mul32(hi, 0x85EBCA6B)) & M32
	for i in 4:
		sm = (sm + 0x9E3779B9) & M32
		var z := sm
		z = mul32(z ^ (z >> 16), 0x85EBCA6B)
		z = mul32(z ^ (z >> 13), 0xC2B2AE35)
		s[i] = (z ^ (z >> 16)) & M32
	if s[0] == 0 and s[1] == 0 and s[2] == 0 and s[3] == 0:
		s[0] = 1


static func make(seed: int) -> RefCounted:
	var r = load("res://scripts/casino/rng.gd").new()
	r.seed_with(seed)
	return r


## Next raw 32-bit value in [0, 2^32).
func next_u32() -> int:
	var s0: int = s[0]
	var s1: int = s[1]
	var s2: int = s[2]
	var s3: int = s[3]
	var result := (_rotl((s1 * 5) & M32, 7) * 9) & M32
	var t := (s1 << 9) & M32
	s2 ^= s0
	s3 ^= s1
	s1 ^= s2
	s0 ^= s3
	s2 ^= t
	s3 = _rotl(s3, 11)
	s[0] = s0
	s[1] = s1
	s[2] = s2
	s[3] = s3
	return result


## Unbiased integer in [0, n), 1 <= n <= 2^32. Rejection sampling: values below
## 2^32 mod n are redrawn, so every residue has exactly the same weight.
func next_below(n: int) -> int:
	if n <= 1:
		return 0
	var threshold := (0x100000000 - n) % n
	while true:
		var x := next_u32()
		if x >= threshold:
			return x % n
	return 0


## Fisher-Yates in place, from the top down.
func shuffle(a: Array) -> void:
	var i := a.size() - 1
	while i > 0:
		var j := next_below(i + 1)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp
		i -= 1


func to_dict() -> Dictionary:
	return {"alg": "xoshiro128**", "s": s.duplicate()}


func from_dict(d: Dictionary) -> void:
	var a = d.get("s", [])
	for i in 4:
		s[i] = (int(a[i]) if typeof(a) == TYPE_ARRAY and a.size() == 4 else 0) & M32
	if s[0] == 0 and s[1] == 0 and s[2] == 0 and s[3] == 0:
		s[0] = 1
