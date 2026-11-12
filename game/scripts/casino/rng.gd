extends RefCounted
## Seedable, portable random generator for the casino core.
##
## Algorithm: xoshiro128** (Blackman & Vigna). The state is four 32-bit words
## taken from a 128-bit seed supplied by the caller: an Array of four u32 or a
## 32-hex-digit String (word 0 first). Each word passes through the murmur3
## finaliser, a bijection on 32 bits, so all 2^128 seeds give distinct states;
## the first four outputs are then discarded.
## Every operation is done on 32-bit values held in 64-bit ints and masked, so
## the same seed gives the same stream on every platform and in the Python
## mirror (tools/casino_tests/ref_eval.py). Never use randi()/randf() in the
## casino.
##
## NOT CRYPTOGRAPHIC. A few dozen outputs reveal the whole state. The games
## therefore never let one state run for long: every Hold'em hand, blackjack
## shoe and roulette spin is shuffled or drawn by a generator freshly seeded
## with 128 secret bits from a seed source (see docs/CASINO_CORE.md).
##
## A seed source is any object with `next_seed()` returning a seed in either
## form above. The core never creates seeds itself.

const M32 := 0xFFFFFFFF
const GOLDEN := 0x9E3779B9

var s: Array = [0, 0, 0, 1]


static func mul32(a: int, b: int) -> int:
	# 32x32 -> low 32 bits without ever exceeding 2^48 in a 64-bit int.
	return ((a * (b & 0xFFFF)) + (((a * (b >> 16)) & 0xFFFF) << 16)) & M32


static func _rotl(x: int, k: int) -> int:
	return ((x << k) | (x >> (32 - k))) & M32


static func _fmix32(h: int) -> int:
	h = h & M32
	h = mul32(h ^ (h >> 16), 0x85EBCA6B)
	h = mul32(h ^ (h >> 13), 0xC2B2AE35)
	return (h ^ (h >> 16)) & M32


## A seed in canonical form (four ints in [0, 2^32)), or [] if `seed` is not
## an Array of four u32 (JSON floats holding whole numbers accepted) or a
## 32-hex-digit String.
static func parse_seed(seed: Variant) -> Array:
	var out := []
	if typeof(seed) == TYPE_STRING or typeof(seed) == TYPE_STRING_NAME:
		var h := String(seed).to_lower()
		if h.length() != 32:
			return []
		for i in 4:
			var part := h.substr(i * 8, 8)
			for ch in part:
				if not "0123456789abcdef".contains(ch):
					return []
			out.append(part.hex_to_int())
		return out
	if typeof(seed) != TYPE_ARRAY or (seed as Array).size() != 4:
		return []
	for x in seed:
		var v = x
		if typeof(v) == TYPE_FLOAT and is_finite(v) and v == floorf(v):
			v = int(v)
		if typeof(v) != TYPE_INT or v < 0 or v > M32:
			return []
		out.append(v)
	return out


## 32 lowercase hex digits, word 0 first. This is the form logged for audit.
static func seed_hex(words: Array) -> String:
	var t := ""
	for w in words:
		t += "%08x" % (int(w) & M32)
	return t


## Seeds the state from 128 bits. Returns false (state untouched) on a bad seed.
func seed_128(seed: Variant) -> bool:
	var w := parse_seed(seed)
	if w.is_empty():
		return false
	for i in 4:
		s[i] = _fmix32((int(w[i]) + GOLDEN * (i + 1)) & M32)
	if s[0] == 0 and s[1] == 0 and s[2] == 0 and s[3] == 0:
		s[0] = 1
	# Warm-up: xoshiro's first output reads only word 1. Four steps make every
	# output depend on all 128 seed bits (a roulette spin uses just one draw).
	for i in 4:
		next_u32()
	return true


## A generator seeded from 128 bits, or null on a bad seed.
static func from_seed(seed: Variant) -> RefCounted:
	var r = load("res://scripts/casino/rng.gd").new()
	return r if r.seed_128(seed) else null


## TESTS ONLY: a generator from a small int (the int fills words 0-1, words
## 2-3 are fixed). 64 bits of an int is not a secret seed; never use this to
## deal real chips.
static func test_only_from_int(n: int) -> RefCounted:
	var r = load("res://scripts/casino/rng.gd").new()
	r.seed_128([n & M32, (n >> 32) & M32, 0x54455354, 0x4F4E4C59])
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


## Unbiased integer in [0, n) for 1 <= n <= 2^32 (n = 1 gives 0 and draws
## nothing). Rejection sampling: values below 2^32 mod n are redrawn, so every
## residue has exactly the same weight. Any other n is an error: returns -1
## and draws nothing.
func next_below(n: int) -> int:
	if n < 1 or n > 0x100000000:
		return -1
	if n == 1:
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
