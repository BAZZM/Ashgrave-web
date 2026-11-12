# Casino core

Rules engine for blackjack, roulette and 6-max no-limit Hold'em in
`game/scripts/casino/`: pure GDScript (`RefCounted`, no nodes, singletons or
global randomness), so it runs offline now and unchanged on a server later.
In-game gold only.

## API

```gdscript
const Holdem := preload("res://scripts/casino/holdem.gd")
const CryptoSeeds := preload("res://scripts/casino/adapters/crypto_seed_source.gd")
var g = Holdem.new({"sb": 1, "bb": 2, "ante": 0}, CryptoSeeds.new())
var r = g.apply({"type": "raise", "seat": 3, "to": 12})
# r = {ok: true, raw_events: [...]}  or  {ok: false, error: "bad_amount", message: "..."}
var v = g.view_for(3)                        # what seat 3 may know, incl. "legal" actions
var e = Holdem.events_for(3, r["raw_events"])  # what seat 3 may be sent
var d = g.to_dict(); var g2 = Holdem.new({}, source); g2.from_dict(d)   # JSON-safe
```

- `rng.gd`: xoshiro128** seeded from 128 bits, unbiased `next_below(n)`
  (n outside 1..2^32 returns -1), Fisher-Yates `shuffle`; mirrored bit for bit
  in `tools/casino_tests/ref_eval.py`.
- `adapters/crypto_seed_source.gd`: the offline seed source (engine `Crypto`).
  Outside the pure core; the only casino file allowed to touch `Crypto`.
- `cards.gd`: card = rank*4 + suit (0 = 2c, 51 = As), text form, shoe with cut card.
- `hand_eval.gd`: `value(cards)` is a totally ordered int; `evaluate()` adds
  category and the five cards used. ~200,000 7-card hands/s.
- `chips.gd`: integer ledger; chips move only by `transfer`, enter by `open`,
  leave by `close`. Append-only event log, auditable with `replay()`.
- `blackjack.gd`, `roulette.gd`, `holdem.gd`: same interface; actions listed in
  each file's header. Errors never change state; garbage never crashes (fuzzed).

## Seeds and randomness

**xoshiro128\*\* is not cryptographic.** A few dozen outputs determine its
state (the review recovered the old 32-bit-seeded state from 8 roulette
results), so the games never let one generator state run for long.
Unpredictability rests entirely on fresh secret seeds:

- Every game takes a **seed source**: any object with `next_seed()` returning
  128 bits, as four u32 (word 0 first) or 32 hex digits. `Rng.parse_seed`
  validates; a bad or missing seed refuses the action (`no_seed`) and changes
  nothing.
- Each **Hold'em hand**, each **blackjack shoe** and each **roulette spin** is
  shuffled or drawn by a generator newly seeded from the source. Blackjack also
  holds one spare seed (taken at a deal) for an emergency reshuffle, so a round
  never needs the source once dealt.
- Seeding: `s[i] = fmix32((w[i] + 0x9E3779B9*(i+1)) mod 2^32)` (murmur3
  finaliser, a bijection), all-zero state becomes `s[0]=1`, then 4 outputs are
  discarded so every draw depends on all 128 bits.
- `Rng.test_only_from_int(n)` exists for tests and tools only; `tools/casino_tests/seed_seq.gd`
  is the deterministic test source. Neither may deal real chips.

When a seed is revealable (it is in the raw log and to_dict from the start,
for audit and replay):

| Unit | Raw log | Sent to clients |
|---|---|---|
| Hold'em hand | `seed` event at hand start; `audit_history[i].seed` | in `hand_end`, after the last award; `events_for` drops the `seed` event |
| Blackjack shoe | `seed` event when the shoe is made | `seed_reveal` once the shoe is retired and no round dealt from it is in play: at the next between-rounds shuffle, or after `round_end` of the round in which an emergency reshuffle retired it |
| Roulette spin | in the `spin` event | same `spin` event: the spin is settled in the apply() that draws it |

**What the server must do:** supply a seed source backed by a CSPRNG (e.g.
`crypto.randomBytes(16)`), never derived from time, table id, hand number or a
counter; keep seeds and `to_dict()` server-side; send clients only `view_for`
and `events_for` output (never `raw_events`, `to_dict()`, `audit_history` or
the shoe); store the raw log so any hand, shoe or spin can be replayed from
its seed; optionally publish revealed seeds so players can verify.

## Sendable vs server-only

Sendable: `view_for(seat)` and `<Game>.events_for(seat, raw_events)`.
Server-only: `apply()`'s `raw_events` (Hold'em hole cards for every seat, live
seeds), `to_dict()` (generator state, deck/shoe order, spare seed), Hold'em
`audit_history` (every hand's hole cards and seed). Tests assert the sendable
forms never contain the raw ones.

## House rules chosen where the plan was silent

| Rule | Chosen | Alternative |
|---|---|---|
| Blackjack 3:2 on odd bets | round down (5 wins 7) | bets in even units only |
| Dealer hole card | peeks under ace or ten; only original bets lost to a blackjack | European no-hole-card |
| Double | any first two cards, after splits too | 9-11 only |
| Split | equal value (K+Q), up to 4 hands; aces once, one card each; 21 after split is not blackjack | resplit aces |
| Insurance | up to half the bet, 2:1 | none |
| Surrender | not offered | late surrender |
| Roulette zero | even-money bets lose | la partage (half back) |
| Basket | first four 8:1; American top line 6:1 | no top line |
| Hold'em button | moving button, no missed blinds, new players dealt in at once | dead button, post to enter |
| Short all-in | does not reopen betting unless short raises total a full raise (TDA) | |
| Odd chip | clockwise from left of the button | best-suit rule |
| Showdown | all live hands shown, last aggressor first; all-in hands shown at once | allow mucking |
| Leaving mid-hand | folds (all-in hands play on), cashed out at hand end; the bet stands for players still to act, and any uncalled part goes back to the leaver | auto-check/fold timer |
| Seats per player (Hold'em) | one; a top-up must leave the stack inside the buy-in range | |
| Roulette bet limit | `max_bets` (64) per seat; no table cap needed (seats x max_bets bounds it) | table-wide cap |

## How the server will use it

The server owns the game and its seed source (see "Seeds and randomness"). It
`apply`s client actions, stores the raw events, and sends each client
`view_for(seat)` and `events_for(seat, raw_events)`. Never send `to_dict()`:
its RNG state and deck reveal every future card. `chips.trim()`
drops persisted events. `open`/`close` are the only bridge to a player's gold.

## Owner decisions (recommendation first)

1. Roulette wheel: **European** (2.7% house edge) or American (5.3%).
2. Blackjack: keep **3:2 rounding down**; resplitting aces **no**; surrender **no** for now.
3. Rake: **none**; a capped rake later if the economy needs a gold sink.
4. Blackjack decks: **6** with 75% penetration.
5. Buy-ins: **20-250 bb** defaults; limits per venue tier.
6. Zero: **no la partage**; revisit if roulette feels harsh.

## Tests

`tools/casino_tests/run.sh <godot>` (about 6 minutes; `QUICK=1` for smaller
property runs, `ONLY=core,holdem` for single modules, `FAILFAST=1`).
Scenario tests with hand-computed results; property runs (twin games
round-tripped through JSON); a fuzzer; golden vectors; and two Python checks
that share no code with the engine: `ref_eval.py` (brute-force hand
evaluator, RNG mirror) and `oracle.py` (pot distribution rebuilt from each
exported hand's raw event log, and blackjack settlement, dealer drawing and
insurance rules for every exported round). `mutants.py <godot>` applies
single-line rule mutations to temporary copies and checks the suite kills
each one.

## Porting to TypeScript

Nothing is ported yet. The port must reproduce `tools/casino_tests/vectors/`:
`rng.json` (seed -> first u32s, bounded draws, 52-card shuffle, a 6-deck shoe)
and `blackjack.json`, `roulette.json`, `holdem.json` (config + seeds in the
order the game asks for them + action list -> final balances, event count,
SHA-256 of the event log). Regenerate them only on purpose
(`WRITE_VECTORS=1 tools/casino_tests/run.sh <godot>`) and say so in the commit.

- GDScript ints are 64-bit. JS numbers are doubles: every 32-bit operation
  needs `>>> 0` (unsigned) and multiplication needs `Math.imul(a, b) >>> 0`
  (`Rng.mul32`). `(n >> 32)` in `Rng.test_only_from_int` needs BigInt or a
  pair of u32. `next_below`'s `0x100000000 - n` and `%` are safe as doubles
  (below 2^53).
- Integer division truncates in GDScript; use `Math.trunc` (all operands here
  are non-negative, so `Math.floor` also works): `cards.gd` `new_shoe` cut
  card (`size * pct / 100`), `blackjack.gd` insurance cap (`bet / 2`, in
  `_insurance` and `legal_actions`) and blackjack payout (`bet * 3 / 2`),
  `holdem.gd` default small blind (`bb / 2`) and `_showdown` share
  (`amt / winners`), `roulette.gd` `covers` dozen (`(n - 1) / 12`).
- `Array.sort()` in GDScript is numeric for ints; JS `sort()` is
  lexicographic. Pass `(a, b) => a - b` at `holdem.gd` `pots()` (`levels`),
  `hand_eval.gd` and `roulette.gd` `_key`/`covers`.
- Godot's `JSON.stringify` sorts keys when asked and writes no whitespace;
  the vectors' canonical event line is `JSON.stringify(e, "", true)`, equal to
  Python `json.dumps(e, sort_keys=True, separators=(",", ":"))`. JS needs a
  sorted-key serialiser. JSON turns ints into floats on the way back in
  (`Chips.norm` restores them).
- Dictionaries iterate in insertion order in GDScript; the event log order
  is the order of `log_event` calls, which the vectors pin down.
