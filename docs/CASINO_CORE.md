# Casino core

Rules engine for blackjack, roulette and 6-max no-limit Hold'em in
`game/scripts/casino/`: pure GDScript (`RefCounted`, no nodes, singletons or
global randomness), so it runs offline now and unchanged on a server later.
In-game gold only.

## API

```gdscript
const Holdem := preload("res://scripts/casino/holdem.gd")
var g = Holdem.new({"sb": 1, "bb": 2, "ante": 0}, seed)
var r = g.apply({"type": "raise", "seat": 3, "to": 12})
# r = {ok: true, events: [...]}  or  {ok: false, error: "bad_amount", message: "..."}
var v = g.view_for(3)              # what seat 3 may know, incl. "legal" actions
var d = g.to_dict(); g2.from_dict(d)   # JSON-safe; play continues identically
```

- `rng.gd`: xoshiro128** seeded by splitmix32, unbiased `next_below(n)`,
  Fisher-Yates `shuffle`; mirrored bit for bit in `tools/casino_tests/ref_eval.py`.
- `cards.gd`: card = rank*4 + suit (0 = 2c, 51 = As), text form, shoe with cut card.
- `hand_eval.gd`: `value(cards)` is a totally ordered int; `evaluate()` adds
  category and the five cards used. ~200,000 7-card hands/s.
- `chips.gd`: integer ledger; chips move only by `transfer`, enter by `open`,
  leave by `close`. Append-only event log, auditable with `replay()`.
- `blackjack.gd`, `roulette.gd`, `holdem.gd`: same interface; actions listed in
  each file's header. Errors never change state; garbage never crashes (fuzzed).

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
| Leaving mid-hand | folds (all-in hands play on), cashed out at hand end | auto-check/fold timer |

## How the server will use it

The server owns the game and its seed (from a secure source). It `apply`s
client actions, stores the events, and sends each client `view_for(seat)` and
`Holdem.events_for(seat, events)` (other hole cards stripped). Never send
`to_dict()`: its RNG state and deck reveal every future card. `chips.trim()`
drops persisted events. `open`/`close` are the only bridge to a player's gold.

## Owner decisions (recommendation first)

1. Roulette wheel: **European** (2.7% house edge) or American (5.3%).
2. Blackjack: keep **3:2 rounding down**; resplitting aces **no**; surrender **no** for now.
3. Rake: **none**; a capped rake later if the economy needs a gold sink.
4. Blackjack decks: **6** with 75% penetration.
5. Buy-ins: **20-250 bb** defaults; limits per venue tier.
6. Zero: **no la partage**; revisit if roulette feels harsh.
