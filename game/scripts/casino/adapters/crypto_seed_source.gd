extends RefCounted
## Seed source for offline play: 128 bits per call from the engine's CSPRNG.
##
## This file is deliberately OUTSIDE the pure core (game/scripts/casino/*.gd):
## it is the only casino script allowed to touch the engine's Crypto class.
## The core only ever calls next_seed() on whatever source it is given; the
## server supplies its own source (see docs/CASINO_CORE.md), tests a
## deterministic one.

var _crypto := Crypto.new()


## Four u32 words from 16 bytes of OS-backed randomness, word 0 first,
## each word big-endian (so seed_hex() prints the bytes in order).
func next_seed() -> Array:
	var b: PackedByteArray = _crypto.generate_random_bytes(16)
	var out := []
	for i in 4:
		out.append((b[i * 4] << 24) | (b[i * 4 + 1] << 16) | (b[i * 4 + 2] << 8) | b[i * 4 + 3])
	return out
