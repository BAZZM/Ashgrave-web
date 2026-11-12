# Combat rules: Phase 2

Spec only; nothing is built. Extends `docs/COMBAT_SPEC.md` (approved, Build 1 shipped) and
ORCHESTRATOR §10.

**u**: world/duel unit. **pip**: one dodge charge (`dodge_max` 3, `dodge_regen`
0.6 pips/s), the only stamina. **d**: an enemy's base damage. **g0**: starting gap, measured
at run time (about 2.75 u). Times: game seconds. Damage, posture, mana and surge are points
on today's meters.

Data lives in `.gd` constant tables (`preload`, no `class_name`, no `.tres`): new
`action_def.gd` and `CombatTune.WORLD`, `.B2`, `.P2`, `.B3`, `.ENEMY`. No rule needs a rig.

## 1. One build sequence

Step | Adds | `CV`
---|---|---
S1 World agility | §6 | 2
S2 Action model, attack any time | §2, COMBAT_SPEC 2.3 | 2
S3 Range and footwork | COMBAT_SPEC 2.4, FAR, rush (§4.4) | 3
S4 Stances, projectiles (button controls) | §3, §4, §8 | 3
S5 Aim drag, rune tracing | §5 | 3
S6 Weapon identities, guard sides, signatures | COMBAT_SPEC 2.5-2.6, §7 | 4
S7 PvP bands, stances, projectiles | §4.5 | 5

Each step is playable alone. S2+S3 are COMBAT_SPEC's Build 2, S6 its Build 3.

Changes to COMBAT_SPEC or today's game:

1. A fourth band, FAR; archers prefer it (question 1).
2. `shots` become a reloading quiver; spells cost 20-80 mana, not 100; an interrupting shot
   no longer opens the foe (question 2).
3. Archer thrusts and caster heavies become always-blockable projectiles. Heavy melee
   still crushes a guard.
4. ORCHESTRATOR's "block costs stamina" is the posture bar already built.

## 2. The action model

Every attack is one `ACTIONS` row over `DEFAULTS`:

```gdscript
const ALL := ["CLOSE", "REACH", "OUT", "FAR"]
const DEFAULTS := {active = 0.05, cost = {}, guard = 1.0, bands = ALL, proj = null,
	interrupt = "light", cancel_at = 0.5}
const ACTIONS := {
	"cut": {kind = "melee", windup = 0.20, recovery = 0.24, dmg = 0.8, posture = 6.0,
		bands = ["CLOSE", "REACH"]},
	"bow_shot": {kind = "ranged", windup = 0.45, recovery = 0.30, cost = {ammo = 1},
		dmg = 22.4, posture = 15.0, proj = {speed = 18.0, parry = "reflect"}},
	"ember_bolt": {kind = "spell", windup = 0.90, recovery = 0.35, cost = {mana = 70},
		dmg = 42.0, posture = 10.0, guard = 1.5, burn = 6.0,
		proj = {speed = 11.0, parry = "reflect"}},
}
```

Times and `burn` are seconds (enemies: ÷`e_speed`); `speed` is u/s. `cost` is paid when
active starts. `dmg` multiplies `slash_damage` (melee) or d (enemies); for ranged and spells
it is flat damage, ×`ranged_mult` or `spell_mult`. A hit adds `posture` to the target; a
blocker pays `guard`×damage in posture.

- **Windup** is the tell. Its owner may cancel into BLOCK or DODGE, free; enemies only by
  `feint`. IN and BACK do not cancel a ranged or spell windup.
- **Active:** the strike resolves or the projectile spawns. Nothing cancels it.
- **Recovery:** locked until the `cancel_at` fraction, then cancellable into BLOCK, DODGE,
  step or stance swap. The next attack waits for its end; input buffers 0.22 s.
- **Interrupt** (unblocked damage during windup). `light`: cancelled, ammo kept, half the
  mana back; player to HIT 0.36 s, enemy to RECOVER 0.35 s. `armoured`: ×0.5 damage, carries
  on. Only a posture break or stun cancels other phases.

`cut` is COMBAT_SPEC's free cut (on an OPEN foe: no windup, damage ×1.0, posture 3, as
today); its recovery is the weapon's `lock`. `bow_shot` posture applies only on an interrupt.

## 3. Stances

An open-screen touch depends on stance: **MELEE** (always) swipes to cut or parry, as
today; **RANGED** (`ranged` slot filled) aims; **MAGE** (`spell` slot filled) draws a rune.

No save change. Duels start in MELEE. Every button works in every stance; only MELEE
parries (question 3).

**Switching.** Today's RANGED and SPELL buttons (keys R, C) become stance buttons: tap to
enter, tap the lit one for MELEE. A swap takes 0.20 s, free, no cooldown; BLOCK and dodge
work during it, attack input buffers into the new stance, and a hit does not cancel it. It
cannot start in own windup, active or early recovery, HIT or stun.

**Guard at any time.** BLOCK raises from READY, own windup, late recovery and mid-swap, in
every stance and band.

**Resources.** Quiver: the item's `shots` (knives 3, bow 4), reloading 1 per 3.0 s; a bow
shot still uses an `arrow`. Mana starts at 40 (today 0); +4.5/s and +10 per parry as today.

**HUD.** Lit stance button: gold ring, ×1.15 size; others 60% opacity; quiver count on
RANGED, mana ring on MAGE.

## 4. Ranged and magic at distance

### 4.1 Flight

A projectile spawns when active starts and lands after max(0.10 s, gap÷speed), fixed at
spawn.

Band | Gap | Arrow, 18 u/s
---|---|---
CLOSE | g0−0.9 u | 0.10 s
REACH | g0 | 0.15 s
OUT | g0+1.3 u | 0.23 s
FAR | g0+4.5 u | 0.40 s

Duels start at REACH, or at FAR against a foe preferring it (world engage distance 7.0 u,
not 2.5 u). All incoming strikes share one **threat queue**; a defence input answers the
earliest entry in its window.

### 4.2 The defender

Defence | Condition | Result
---|---|---
Block | guard up at impact; any stance, any side | no damage; posture +`guard`×damage; a full bar breaks the guard as built (1.1 s stun)
Perfect block | raised ≤`perfect_block` (heater 0.2 s) before | no posture; shooter posture +12; surge +8
Parry | MELEE; matching swipe ≤0.3 s (`parry_window`) before; never THRUST | no damage; surge +15, mana +10
Perfect parry | ≤0.11 s | reflect: returns at the same speed for ×1.0 damage (casters ×1.5, as today), posture 1.6×`break_per_parry`; stagger: shooter OPEN 1.25 s
Dodge | i-frames (0.38 s) cover impact | avoided; perfect ≤0.18 s as today

Heavy projectiles have `guard` 2.0. Enemies block projectiles with chance `block_skill`
(+0.15 at FAR), never in windup, and never reflect. A shot landing in a light windup sends
the foe to RECOVER, not OPEN.

### 4.3 Point-blank

At CLOSE, ranged and spell windups take ×1.3, flight is 0.10 s, and a cut into such a
windup always lands and interrupts.

### 4.4 Closing the gap

IN moves one band in 0.22 s, free; BACK costs 0.5 pip. **Rush:** a MELEE swipe at a target
at OUT or FAR steps in automatically (FAR to REACH: 0.44 s), then free-cuts at +0.15 foe
parry chance. COMBAT_SPEC's enemy rules for OUT also hold at FAR.

### 4.5 PvP (S7, `CV` 5)

Still turn-based: three swings a turn, each a cut, shot or cast.

**The defender decides every hit, projectiles included**: with no server or shared clock
and 100-400 ms of relay delay, the attacker cannot know when the guard went up, and each
client already owns its health. The defender's clock starts when `atk` arrives: it plays
windup `wu`, then flight (its own gap÷`sp`), defends by §4.2 and sends one `res`. Latency
delays the exchange, never the defence window. The attacker's projectile is cosmetic,
waiting at the target up to 2.0 real seconds for `res`.

- Shot or cast: `atk {dir, dmg, pj: 1, wu, sp, gd, pr}` (windup s, speed u/s, `guard`, parry).
- Outcome: `res.o` as today; a reflect is `parried` with `pf: 1, rf: 1` and `rip` = damage,
  like today's riposte; new `out` = cut out of reach.
- Bands: `step {o, q}` (COMBAT_SPEC 2.4); band = clamp(mine+theirs), −1 CLOSE to 2 FAR.
- Frost Bind and Gust are not castable.

**Old clients.** Both run min(`cv`). Below 5 a new client sends none of this, keeps ranged
and spells off in PvP as today, and captions "Classic duel: their game is older." Old
clients already ignore unknown kinds, fields and `res.o` values (`duel_pvp.gd`). Every `atk`
still gets one `res`. S1-S5 change nothing in PvP (MELEE only, no bands, nothing new
sent); S6 sends COMBAT_SPEC's `CV` 4 fields.

## 5. Controls

A touch on a button is that button. Any other touch means what the stance says (§3), so
swipe, aim and stroke never collide.

**Aim drag (RANGED).** Touch down starts the draw, reticle on the target's chest; dragging
moves it 1:1 within ±180 px by ±150 px. Release looses the shot, never before the windup ends
(a tap is a quick chest shot). Chest: THRUST (unparryable), ×0.8 damage. Left or right
body: LEFT or RIGHT, ×1.0, snaps within 48 px. Head (28 px radius, no snap): OVER, ×1.5.
Cancel, arrow kept: release ≥100 px below the touch-down point, or press BLOCK.

**Rune stroke (MAGE).** One stroke with a trail, read on release as up to 3 straight legs,
each ≥60 px within 35° of up, down, left or right; mirrors count; limit 1.5 s. Cast windup =
max(stroke time, 0.6 × rune windup). Unknown shape, unowned rune or too little mana: FIZZLE
(grey crumbling trail, 0.30 s recovery, no mana spent).

Rune | Stroke | Mana | Windup | Casts
---|---|---|---|---
Spark | up | 20 | 0.50 s | 12 damage, 14 u/s, reflect
Gust | down | 25 | 0.50 s | target back one band, cancels a light windup
Ember Bolt | down, right | 70 | 0.90 s | 42 damage, burn 6 s, 11 u/s, reflect
Sunder | down, up | 60 | 1.10 s | 30 damage, 6 u/s, `guard` 2.0, stagger
Frost Bind | right, down, left | 80 | 0.90 s | 11 u/s; today's effect on landing
Ward | up, right, down | 50 | 0.60 s | absorbs the next blow, as today

You cast the spell items you own; Spark comes with any.

**Button fallback** (pause menu, GESTURES OFF, saved): in RANGED a tap fires a chest shot;
in MAGE owned runes are a row of 88 px buttons above BLOCK (keys 1-6), at full windup. S4
ships with only this; S5 makes gestures the default.

## 6. World agility (S1)

Feel | Today | S1
---|---|---
Walk (stick <0.8) | 5.0 u/s | 5.5 u/s
Run (stick ≥0.8) | 8.5 u/s after 0.5 s | 9.5 u/s after 0.25 s
Sprint | none | 12.5 u/s after 1.0 s of running at stick ≥0.95, builds in 0.4 s; lost below 0.8, on a turn over 90° inside 0.25 s, or when blocked
Road | ×1.2 (10.2 u/s) | ×1.2 (run 11.4, sprint 15.0 u/s)
Acceleration | instant | 40 u/s² up, 60 u/s² down
Turn rate | eased 10/s | 720°/s walk, 540°/s run, 300°/s sprint
Dash | none | 4.5 u in 0.22 s along the stick; 1 pip; 0.35 s lockout; 0.18 s i-frames (no foe can start a duel); stops at obstacles
Camera lookahead | 0 u | velocity × 0.25 s, max 2.5 u, eased 4/s
Camera distance, FOV | 6.6 u, 60° | sprinting 7.4 u, 66°; dash 70° (0.15 s in, 0.4 s out)

Dash button: 130 px square at (width−380, height−180), key Shift, pips above. World pips
use `dodge_max` and `dodge_regen`; duels still start full. Nothing new goes on the relay.

## 7. Enemies

Enemies use the same rows and rules; a combo is a list of rows. An existing `AttackDef`
reads as a melee row (its windup and damage, recovery 0.35 s, `armoured` if heavy); archer
and caster ones become LEFT, RIGHT or OVER projectiles. Each archetype's signature comes
every third combo with a fixed tell.

Archetype, band | Signature and tell | Counter
---|---|---
Brute, CLOSE | `quake` (both arms raised): heavy OVER, windup 1.30 s, armoured, 1.5×d, hits CLOSE and REACH, recovery 1.20 s | BACK to OUT in the windup: it misses, he is OPEN 1.2 s
Duelist, REACH | `riposte` (blade upright): a 1.5 s light windup held as a guard, every cut into it parried and countered; recovery 0.6 s | a shot or spell: it lands and interrupts
Archer, FAR | `volley` (three pips): 3 arrows 0.50 s apart, LEFT, RIGHT, OVER, 0.7×d each, 18 u/s, reflect | perfect-parry the first (the reflect cancels the rest), or rush
Mage, OUT | `orb` (grows in hand): windup 1.15 s, 6 u/s, 1.3×d, `guard` 2.0, any parry reflects at ×1.5 | parry it back (0.68 s flight), or cut into the cast

## 8. Several foes

- A ranged side foe fires a real projectile: 0.80 s tell on its alert icon, then a fixed
  0.45 s flight shown by a marker running from the icon to screen centre (1.25 s, as today).
- Block (any side) or dodge it; no parry, like side strikes today.
- A perspective change (0.45 s glide) never removes a threat or moves its impact. Only a
  projectile from the current target, landing after the glide, can be parried.
- At most 2 projectiles fly at the player, impacts ≥0.5 s apart.

## 9. Acceptance checks

Every step: `node tools/check.js` passes.

- **S1.** 100 u of flat off-road ground at full stick takes ≤9.0 s. A dash covers
  4.5±0.3 u within 0.25 s and costs a pip. The relay log has no new kinds.
- **S2.** A swipe at an idle foe lands, is guarded, or is parried and countered. BLOCK
  during a cut's windup cancels it. A cut-in shows ARMOURED on a heavy.
- **S3.** IN and BACK reach four distinct distances in tower, arena and on a slope.
  Stepping back makes a left cut miss. From FAR, a swipe cuts within 0.75 s.
- **S4.** A stance tap completes within 0.25 s with BLOCK working throughout. The bot log
  shows an arrow flying 0.40±0.05 s at FAR. A poacher's arrow can be blocked, deflected,
  reflected onto her, or dodged.
- **S5.** 50 MELEE swipes produce no shot or cast. A person on a phone casts each rune 9
  times in 10; a scribble fizzles at no mana. With GESTURES OFF everything works by taps.
- **S6.** COMBAT_SPEC Build 3's checks hold. Each signature shows its tell. A scripted
  counter to each works 5 times in 5.
- **S7.** With 400 ms added relay delay, BLOCK raised after seeing the arrow blocks it.
  `res` count equals `atk` count. Against a `cv` 2 client the relay carries no `pj` or
  `step`.

## 10. Questions for the owner

1. **A fourth distance, FAR?** (Changes COMBAT_SPEC's three.) **A, recommended:** add it;
   arrows visibly fly 0.4 s; costs camera framing work at 7 u. **B:** keep three; cheapest,
   but you react to the draw, not the arrow.
2. **Paying for shots and spells?** (Changes today's 3-4 shots a fight and full-bar spells.)
   **A, recommended:** reloading quiver, runes at 20-80 mana; needs a balance pass. **B:**
   today's limits; no rebalance, but a bow empty after 4 shots is no stance.
3. **Parrying outside MELEE?** **A, recommended:** MELEE only; input stays unambiguous, but
   bow and staff can only block or dodge. **B:** any stance; gentler, but parry swipes and
   rune strokes get confused.
4. **Ranged and magic in PvP?** **A, recommended:** S7 last, on public relays, defender
   decides; attackers see results 0.2-0.8 s late. **B:** wait for the Phase 6 server;
   fairer, much later; PvP melee-only until then.
