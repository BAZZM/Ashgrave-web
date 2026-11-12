# Combat spec: deepening the duel

Status: draft for the owner's approval. Nothing here is built yet.
Readers: the owner (part 0 and part 4), then the Sonnet builders (all of it).

## 0. What fighting will feel like (for the owner)

**After Build 1 (feel and posture).** Every blow lands harder: a short freeze on
contact, the foe rocks back, sounds stack into a proper crunch, and a perfect
parry gets its own flash and ring. The thin gold bar under the foe's health
becomes their **posture**. Perfect parries fill it fast, ordinary parries
slowly, and it drains back if you ease off. When it fills, the foe reels and the
screen says SWIPE TO EXECUTE: one swipe, a close camera shot, and ordinary foes
die on the spot while bosses lose a large slice of health. Your shield bar
becomes your own posture bar. Blocking fills it, and if it fills you are left
stunned for a second.

**After Build 2 (range and offence).** You and the foe stand at one of three
distances: close, at reach, or out of reach. Two new buttons beside the dodge
buttons step you in and back. Most cuts can't reach someone who has stepped back,
but thrusts lunge and still hit. You no longer have to wait for an opening: swipe
whenever you like. The foe may take the hit, block it, or parry it and hit back
from the other side. They read you, so repeating the same cut gets parried more
often. Clever foes follow you when you step back; archers keep their distance.

**After Build 3 (weapons and guard).** The three weapon kinds play differently.
Twin blades want to be close, the longsword sits in the middle, and the greatsword
hits from further out. Each has its own combos and one signature move. Blocking
now has a side: hold block and swipe (or press a direction key) to guard left,
right or high. Attacks from that side are stopped cheaply; attacks from the other
sides get through. Foes guard too. You can see which side they cover, so you cut
at the open side.

---

## 1. Ground truth: the duel today

What the code does now, so that nothing below gets specified as new by mistake.
Concepts are named as they are in the code. Since the split of the duel script
into several files is under way, no line numbers or file names are used.

- **States.** Enemy: INTRO, IDLE, WINDUP, RECOVER, OPEN, FINISHER, DEAD. Player:
  READY, DODGE, SWING, HIT, DEAD. The enemy picks a combo (a list of
  `AttackDef`: dir LEFT/RIGHT/OVER/THRUST, windup, damage, heavy, feint) and
  winds up each attack. When the windup ends, the strike resolves against the
  player's state (`_resolve_strike`).
- **Player defence.** Parry: swipe the arrow's direction within `parry_window`
  (about 0.3 s) of the strike. A thrust can't be parried. A **perfect parry**
  lands within `PERFECT_PARRY` (0.11 s). Dodge: a button, using charges
  (`dodge_max`, refilled at `dodge_regen`), with i-frames for `DODGE_IFRAME`; a
  **perfect dodge** lands within 0.18 s. Block: hold the button. It stops any
  attack except a heavy one ("GUARD CRUSHED") and drains `shield`. At 0 it shows
  "GUARD BROKEN", the player takes 60% of the damage, and the Warden set refills
  half the shield. A **perfect block** comes within `perfect_block` of pressing.
  The shield refills at 2/s while not blocking.
- **Player offence.** Real damage lands only while the enemy is OPEN. It opens
  after a parry (`stagger_time`), after finishing a combo ("winded"), on a
  break, on a ranged interrupt, on Frost Bind and on surge. A swipe while the
  enemy is IDLE or RECOVER only shows "GUARDED". A wrong or early swipe during a
  windup is a whiff (`WHIFF_LOCK`). While OPEN, cuts build `hit_combo` and the
  `slash_seq` letter chain. The chains FLURRY, CLEAVE and TEMPEST multiply
  damage, and weapon families adjust them (longsword ×1.2 FLURRY, greatsword
  CLEAVE = 3.0, twin ×1.5 on every chain).
- **Break meter.** `e_break` rises only on parries (`break_per_parry` ×
  weapon `break_mult`, ×1.6 when perfect). It never decays. At `break_max` the
  game shows "BREAK!" and opens the enemy for `break_time` with ×1.25 cut
  damage. It is drawn as the thin gold bar under the enemy's health.
- **Already in place:** surge (100 meter, opens and damages; on the Regent it
  takes the throne), ranged shots (interrupt a windup), three spells, elements
  (ember burn, frost chill ×0.8 windup speed, storm damage on perfect parries,
  weak and resist), flasks, enrage at 50% (speed ×1.15), feints (a pause in the
  windup), several foes (side foes `others` seated at ±3.3, throwing red THRUST
  tells, picked with the alert discs), the FINISHER state (at 0 HP: slow
  motion, a side camera, swipe to finish, automatic after 3 s), hit-stop
  (`_hitstop` = `_slow(0.05, t)`, skipped while slow motion is already
  running), camera shake, FOV punches, phone vibration, sparks (a single
  re-used particle emitter), and the tutorial (four single attacks).
- **Where duels happen.** In the tower and on the open land alike, the duel
  node is put at the midpoint between the fighters (`_place_in_world`). The
  player stands at local (-1.2, 0, 2.0), the foe at (0, 0, -0.75), and the gap
  along z is about 2.75. The tower's `ground_y` is flat (0). The open land
  follows `Land.walk_height`. The **standalone arena scene** (no host) is the
  one the bots and direct duels use. Its start positions come from the duel
  scene, which can't be read here. **Build 2 must measure the starting gap at
  run time rather than assume 2.75.**
- **Inputs.** Phone: swipe anywhere off the buttons (60 px) to attack or parry,
  plus buttons for dodge L/R, block (hold), surge, flask, spell, ranged, pause
  and target discs. Desktop: A/Left and D/Right dodge, Space block (hold), F
  surge, Q flask, R ranged, C spell, Esc/P pause, Enter. A mouse drag stands in
  for a swipe. **A swipe or a dodge is ignored while blocking**, which leaves
  room for new uses later.
- **Player stats** come from `Run.stats()`: weapon damage, lock, window and
  break_mult, plus the shield item (heater 60, buckler 35, tower 105),
  skills, boons, perks and sets.
- **Sound.** `Sfx.play(name, volume_db, pitch_jitter)` plays through 8
  round-robin players, with the pitch held at 1.0 ± jitter. There are eight
  one-shots (whoosh, clang, hit, block, hurt, break, finish, tell) plus a
  looping ambience. On the web build, Godot 4.4 plays sounds as browser
  "samples" (the `.sample` imports suggest so). Volume and pitch work that way;
  **bus effects (reverb, filters) very likely do not, so this design uses
  none.** Pitch under sample playback has not been tested on a phone. Build 1
  checks it first.
- **Player-vs-player.** Turn-based and decided by the defender. The attacker
  gets 3 swings per turn, with a 1.25 s cooldown. `atk {dir, dmg}` arrives,
  and the defender plays a 0.9 s windup locally and parries, dodges or blocks.
  Then `res {o: hit|dodged|blocked|parried, hp, rip}`, `turn`, `ping {hp}`
  every 3 s, and `dead {gold}`. Each client owns its own HP and reports it. The
  check needs, on every relay, exactly one challenge, accept and dead, and
  **as many `res` as `atk`**.
- **Bots.** `--autoplay=x` parries at 0.6 × `parry_window`, so it almost never
  gets a perfect. It dodges thrusts and side tells, swipes L/R while OPEN or in
  FINISHER, and uses surge, flask, spell and ranged. There are also `idle`,
  `block` and `dodge` variants and the `pvp` bot. The bots run at 4× time on a
  2-4 fps renderer, so **they act only once per frame and cannot be relied on
  for narrow windows.** The check patterns end in `foes=N$`, so any new RESULT
  field goes before `foes=`.

## 2. The six items

All numbers go in a new constants-only script, `CombatTune`, with one
dictionary per build (`B1`, `B2`, `B3`) and an `ENEMY` table of per-archetype
traits (§2.7). No number is written into duel code.

### 2.1 Feel pass (Build 1)

**Exists:** hit-stop, shake, FOV punch, slow motion, sparks, vibration, the
FINISHER camera, enemy flash, HUD streaks. **Changes:** the values below, and
hit-stop may now chain with slow motion (freeze first, then slow). **New:**
recoil when the foe is hit, a directional camera kick, a second spark emitter,
layered sounds, and the finisher camera move.

| Moment | Today | Build 1 |
|---|---|---|
| Cut lands (OPEN or free cut) | stop 0.045 s, shake 0.35 | stop 0.06; foe body pushed 0.12 along the cut, back in 0.12 s; camera kick 0.06 toward the swipe; layer L1 |
| Chain ender | stop 0.09, FOV 50, shake 0.9 | stop 0.11, FOV 48, white flash on the foe, second spark burst, layer L2 |
| Parry (not perfect) | slow 0.25 for 0.22 s, FOV 49 | slow 0.5 for 0.15 s, FOV 51, clang only |
| Perfect parry | same as a plain parry | freeze 0.06 then slow 0.25 for 0.30 s, FOV 46, gold edge flash, posture bar pulse, layer L3 |
| Enemy posture broken | (BREAK banner) | freeze 0.10, slow 0.35 for 0.5 s, "POSTURE BROKEN", layer L4 |
| Execution or killing blow | camera to (1.9,1.5,1.6), slow 0.25 for 3.2 s | finisher camera (below), contact freeze 0.15, layer L7 |
| Player hit for ≥15% of max HP | shake 1.0 | shake 1.3, layer L5 |
| Block | shake 0.5 | layer L6 |
| Player posture broken | GUARD BROKEN banner | blue edge flash, layer L4 at pitch ×0.8 |

**Finisher camera** (used on FINISHER and on execution): over 0.4 s, move to a
low side shot at local (±2.0, 1.2, midpoint z + 0.3), FOV 50, aimed at the
foe's clash point. Take the side away from any remaining foes. On the deciding
swipe: push in for 0.15 s to 65% of the distance with FOV 42, freeze 0.15, slow
0.3 for 0.8 s, then ease back to the normal camera, or move to the next foe.
**On the open land, keep the camera's world height at least `ground_y` + 0.5
at its own spot** (slopes). Keep the existing point-space fix: aim at
`to_local(clash point)`.

**Sound layers.** Add a base `pitch` argument to `Sfx.play` (default 1.0, so
current calls don't change) and raise the pool from 8 to 12 players. Each layer
is a list of (sound, dB, pitch, delay). A delay runs on a timer that ignores
time scale. If the same layer was started less than 40 ms ago, it is skipped.

| Layer | Parts |
|---|---|
| L1 cut | hit 0 dB p1.0±0.15; whoosh -10 p1.25 |
| L2 chain end | hit +1 p0.85; clang -6 p0.75; break -14 p1.3 |
| L3 perfect parry | clang 0 p1.0; clang -5 p1.45 at +30 ms; break -12 p1.2 |
| L4 posture break | break 0 p0.8; clang -4 p0.6 |
| L5 heavy hurt | hurt 0; hit -4 p0.7 |
| L6 block | block 0; clang -14 p0.6 |
| L7 execution / finish | finish +2; hit +2 p0.7; break -6 p0.9 at +60 ms |

**Enemies:** the player's hits get the same treatment. **PvP:** purely local
and driven by `res` as today. Works at every version.
**Phone cost:** tweens and timers only. Nothing new runs every frame apart from
the second emitter, which costs 28 particles.

### 2.2 Posture (Build 1)

**Exists:** the enemy break meter and its bar, and the shield meter, which
already behaves like a guard that wears down. **Changes:** the break meter
becomes **enemy posture** (fed by more sources, drains back, ends in an
execution instead of the BREAK window). The shield meter is **redrawn as the
player's posture**, a bar that fills (posture = `shield_max` − `shield`), so
shield gear keeps its meaning as posture capacity. **New:** posture drain,
execution, and the player stun.

What the player sees: the foe's gold bar is labelled with a small diamond and
fills left to right. The player's blue bar under their health now fills as
they take pressure. No new input: an execution is a swipe, the same as a
finish.

**Enemy posture gains** (all × weapon `break_mult`; B1 numbers):

| Source | Gain |
|---|---|
| Parry | 0.5 × `break_per_parry` (today 1.0) |
| Perfect parry | 1.6 × `break_per_parry` (unchanged) |
| Perfect block / perfect dodge | 12 / 10 |
| Cut while OPEN / chain ender | 3 / 12 |
| Ranged interrupt / Frost Bind | 15 / 25 |
| Surge | 60, plus today's damage; if it doesn't fill the bar, OPEN "broken" for `break_time` as today |

**Drain:** after 2.5 s with no gain, posture drains at 5/s × (0.3 + 0.7 × HP
fraction). A wounded foe recovers slower, so cuts still help the posture route.
No drain while OPEN, FINISHER or chilled (frost). ×1.25 while enraged.

**Full posture** puts the enemy in OPEN with the new reason "posture" for 2.2 s
of game time. HUD: "SWIPE TO EXECUTE". Side foes hold their attacks, as they do
in FINISHER. The first swipe makes the **execution** (finisher camera, L7):
damage = share × `max_hp`, with share wild 1.0, lesser 1.0, elite 0.6,
guardian 0.4. If that kills, it goes straight to `_finish` with no second
prompt. Otherwise posture goes to 0 and the foe stays OPEN "broken" for 1.0 s
with today's ×1.25 cut damage, so combos still fit. Missing the window drops
posture to 50% and the foe recovers. Execution damage goes through
`_damage_enemy`, so enrage and kill credit work. The Regent's spare and throne
choices only come from FINISHER (0 HP), as now.

**Player posture:**

| Source | Gain |
|---|---|
| Blocked hit (not perfect) | 1.0 × damage (today's shield drain) |
| Blocked side strike | 1.0 × damage (today) |
| Hit taken | 0.3 × damage (new) |
| Whiff | 6 (new) |
| Parried by the enemy (Build 2) | 20 |

Posture drains at 3/s after 1.0 s with no gain, and not while blocking (today:
2/s whenever not blocking). **When full:** today's GUARD BROKEN (60% damage),
**plus** a 1.1 s stun (the HIT state with no action, shown with the `broken`
pose), after which posture resets to 50%. Warden set: a 0.5 s stun (still
"restores half"). Heavy attacks crushing a guard behave as today.

**Interactions:** the g3 riposte, storm and caster reflect are unchanged. Leech
and the b2 Opening perk apply to the parry stagger as today. Tutorial: the
first posture break shows a hint "SWIPE TO EXECUTE". **Enemies:** they don't
choose anything new in Build 1. Heavy attacks are their posture weapon against
a player who blocks.

**PvP** (needs version ≥2 on both sides, §3): each client owns its own posture
and puts `po` (0-100) on `res` and `ping`. When a parry is reported,
`res.pf = 1` marks it perfect, and the attacker's client adds 0.5× or 1.6× of
34 to **its own** posture. Blocks fill the defender's own posture. When a
client's posture fills, it sends `pst {po: 100, pb: 2.5, q: seq}` (broken for
2.5 s real time; `q` lets the receiver drop older ones). The other player's
next swing becomes an execution `atk {x: 1, dir}`, and if they have no swings
left they get one. The broken defender resolves it as unavoidable damage of
30% of their own max HP and answers `res {o: "exec"}`, so `res` still equals
`atk`. An execution that arrives after the window has closed is resolved as a
normal attack. No instant kills in PvP.

### 2.3 Player-led offence (Build 2)

**Exists:** OPEN windows, the "GUARDED" bounce, whiffs, and parry by matching
direction. **Changes:** a swipe at an enemy that isn't open is a real attack
(a "free cut") instead of a bounce, and an early swipe during a windup is a
cut-in instead of a whiff. **New:** enemy parries, counters and reading.

Inputs: none new (a swipe). What a swipe means now:

| Enemy state | Swipe does |
|---|---|
| OPEN, FINISHER | as today (full cut, chain, execution) |
| IDLE, RECOVER | **free cut**: 0.20 s commit (0.15 s at CLOSE), then resolve |
| WINDUP, inside `parry_window` | parry attempt, as today |
| WINDUP, earlier | **cut-in**: free cut against a foe that is ready (+0.15 parry chance) |
| Target out of reach | lunge: automatic step in (2.4) then free cut, +0.15 parry chance |

At the start of the commit, the enemy's answer is rolled and shown
straight away (the `parry` or `guard` pose):
parry chance = `parry_skill` + 0.15 × the current free-cut streak + 0.25 for
each consecutive cut in the same direction (that bonus capped at 0.5) − 0.3 ×
posture fraction (−0.1 at CLOSE). The block chance is `block_skill`. Otherwise
the cut lands.

| Answer | Effect |
|---|---|
| Lands | 0.8 × the OPEN cut damage, enemy posture +6, enemy idle timer +0.25 (capped at `idle_gap` + 1.0 since the last enemy attack), chain letter kept |
| Cut-in lands on a light attack | as Lands, plus the combo is cancelled and the foe goes IDLE with a 0.6 s gap |
| Cut-in on a heavy attack | "ARMOURED": 0.5 × damage, the strike carries on |
| Blocked | "GUARDED", no damage, enemy posture +4, player recoil 0.25 s |
| Parried | "PARRIED" (with "READ!" if the repeat bonus decided it), player posture +20, player recoil 0.35 s, then the enemy **counters**: one attack in the opposite direction (L↔R; OVER and THRUST answered with LEFT), windup 0.75/`e_speed`, damage 1.1 × the enemy's first combo hit. It can be parried, dodged or blocked as usual |

The streak resets when the player is hit, parried or blocked, or after 1.2 s
without a cut. **The chain** (`slash_seq`) now carries across free cuts and
OPEN cuts. It resets on being hit, parried, or 1.2 s without a cut (today it
clears on every opening). **Unchanged:** OPEN cuts never get parried, and
every source of OPEN stays. A parry is still the best opening.
**Feints:** a cut-in during the feint's hold lands, so a feint is a gamble for
the enemy. **Several foes:** free cuts only hit the current target. Side foes
are unaffected.

**Enemies** use `parry_skill` and `block_skill` (§2.7) and keep their own
initiative. **PvP: stays turn-based, with no free cuts.** Both clients would
have to agree on who struck first, to within about 50 ms, while the relays add
100-500 ms and can arrive out of order. The PvP turn already is player-led
offence against a defender who parries by direction.

### 2.4 Range and footwork (Build 2)

**Exists:** a fixed gap, the sideways dodge (out and back in 0.46 s), and the
side seats. **New:** distance bands, steps, reach, and enemy movement.

**Bands.** The starting gap g0 (measured when the duel starts) is REACH. CLOSE
= g0 − 0.9, OUT = g0 + 1.3. The player moves along the duel's z axis and the
enemy along its own. The band is worked out from the actual gap (thresholds
halfway between the band distances). Each step calls `_stand` with a glide, so
the y follows `ground_y` (open land) or stays flat (tower and arena). The
camera follows the player in z (`CAM_POS.z` − 2.0 behind the player). Side
foes re-seat at the player's z − 2.1 when the player steps.

**Inputs:**

| | Phone | Desktop |
|---|---|---|
| Step in | new button ▲ "IN", 120×120, just inboard of the right dodge button (bottom row) | W or Up |
| Step back | new button ▼ "BACK", 120×120, just inboard of the left dodge button | S or Down |

**Rules:** a step takes 0.22 s (new player state STEP: no i-frames, can't
parry, and input during it is buffered as today). Stepping back costs 0.5
dodge charge; stepping in is free. No stepping while blocking. You can't step
past CLOSE or OUT. On switching target, the gap is reset to REACH.

**Reach** (B2; weapons change the player's row in Build 3):

| Attack | CLOSE | REACH | OUT |
|---|---|---|---|
| Player cut (all families in B2) | hit | hit | lunge (2.3) |
| Enemy LEFT, RIGHT, OVER | hit | hit | miss: "OUT OF REACH", foe goes to RECOVER, no OPEN |
| Enemy THRUST (it lunges) | hit | hit | hit |
| Archer and caster attacks, side strikes | hit | hit | hit |
| Player ranged and spells | hit | hit | hit |

At CLOSE, both sides' windups take ×0.85. Reach is checked when the strike
lands, so stepping out mid-windup dodges cuts without costing a charge, but it
gives no perfect-dodge reward and no opening.

**Enemies:** each archetype has a preferred band, `pref_band`, and a `chase`
chance (§2.7). When its idle timer runs out and the player is out of its
preferred band, the enemy steps toward it (0.35 s) before picking a combo. If
the player steps out during a windup with more than 0.3 s left, a chasing foe
steps in after them (rolled once per windup). Archers and casters step back to
OUT after each combo, and at CLOSE their windups take ×1.3. Enemy posture
drains ×2 while the gap is OUT, so backing off costs pressure.

**PvP** (version ≥3, and see question 4): each client owns its own offset (−1,
0, +1) and sends `step {o, q}` when it changes (`q` = a counter per sender;
older copies dropped). Band = clamp(REACH + my offset + their last heard
offset). `atk` carries `o` (the attacker's offset, so a lunge informs the
defender). The defender decides reach with its own view and may answer
`res {o: "out"}`. Latency favours the defender, as it already does.

### 2.5 Weapon identities (Build 3)

**Exists:** three families (longsword, twin, greatsword) with damage, lock,
parry-window and break_mult stats in `Items.WEAPONS`, family bonuses on the
shared chains, and blade shapes. **Changes:** the shared chain list becomes one
table per family, and reach depends on the family. **New:** signature moves.
Every individual weapon stat in `Items` stays the same.

| | Longsword | Twin blades | Greatsword |
|---|---|---|---|
| Reach | CLOSE, REACH | CLOSE (+20% damage), REACH | CLOSE (×0.6 damage), REACH, OUT |
| Free-cut commit | 0.20 s | 0.14 s | 0.28 s |
| Chains (mirrors too) | FLURRY L R L ×1.62; CLEAVE L L R R ×2.2; TEMPEST L R U D ×3.0 | FLURRY L R L ×2.0; FANGS L R L R L ×3.2; TEMPEST L R U D ×4.5 | CLEAVE L L R R ×3.0; SUNDER D D ×2.4 and posture +30; TEMPEST L R U D ×3.0 |
| Signature | **Counter-cut** | **Dash cut** | **Guard breaker** |

The longsword's values are today's effective numbers. Twin FLURRY and TEMPEST
and greatsword CLEAVE and TEMPEST also keep today's values. That leaves two
new chains (FANGS, SUNDER), and two are dropped: twin CLEAVE and greatsword
FLURRY. The pause-screen combo list shows the equipped family's table.

| Signature | Input (phone and desktop alike: a swipe or mouse drag) | Effect |
|---|---|---|
| Counter-cut | within 0.35 s after any successful parry, swipe the same direction you parried | lands at once, can't be parried, ×1.5 damage, posture +25 |
| Dash cut | swipe during a step in (or a lunge) | lands during the step, can't be parried, posture +10 |
| Guard breaker | swipe up (thrust) while at CLOSE; 4 s cooldown | can't be parried or blocked, ×0.6 damage, posture +35, foe pushed to REACH |

**Enemies:** unchanged. **PvP** (version ≥4): the attacker works out chain
damage as now and sends it in `dmg`. `atk` adds `np: 1` (can't be parried) and
`pz` (posture damage) for signatures. The defender applies them. Turns keep 3
swings, so only chains of 3 or fewer letters (FLURRY) complete inside a turn
unless swings are added. Leave it so.

### 2.6 Guard stances (Build 3)

**Exists:** hold-to-block against every side, perfect block, GUARD CRUSHED on
heavy attacks, the `block` and `guard` poses. **Changes:** the player's block
covers **one side**. **New:** choosing a side, side-specific poses, enemy
stances.

**Player inputs:**

| | Phone | Desktop |
|---|---|---|
| Raise guard | hold BLOCK (as today) | hold Space (as today) |
| Set the side while guarding | swipe L, R or U with the other thumb | A/Left, D/Right, W/Up while Space is held (dodge and step are off while guarding), or a mouse drag |

When raised during an enemy windup that isn't a thrust, the guard faces that
attack's side automatically. Otherwise it uses the last side (HIGH at the
start of a duel). A LEFT attack is stopped by a LEFT guard, RIGHT by RIGHT,
OVER by HIGH. A THRUST is stopped by any guard at 1.5× posture. Heavy attacks
can't be blocked, as today. Side strikes from other foes are stopped by any
guard.

| Result | Effect |
|---|---|
| Right side | player posture +0.7 × damage (cheaper than B1's 1.0) |
| Right side within `perfect_block` of raising **or switching** | no posture, enemy posture +12, surge +8 |
| Wrong side | full hit, and player posture +0.3 × damage |

**Feints** (enemies): at the feint moment, if the player is guarding the
attack's side, a LEFT or RIGHT attack flips to the other side and the arrow
flips with it. OVER feints don't flip. **Poses:** `block` and `guard` take a
side argument (L, R, HIGH), built in code in the placeholder visual.

**Enemy stances:** in IDLE and RECOVER, the enemy holds a side shown by its
`guard` pose, and with guide arrows on, by a small shield-and-arrow above its
health bar. It changes side every `stance_time`/`e_speed` seconds, and after
taking a hit it moves to the side that was hit with chance `adapt`. In Build 3
this replaces the Build 2 dice for free cuts:

| Free cut at | Result |
|---|---|
| The guarded side | blocked, or parried and countered with chance `parry_skill` (the streak and repeat bonuses from 2.3 still apply) |
| An open side | lands (Build 2's "Lands" row) |

Convention: "match the arrow". A shield arrow pointing left means swipe-left
cuts are blocked, the same way an enemy's left arrow means swipe left to parry.

**PvP** (version ≥4): defence stays with the defender. It compares the
incoming `dir` to its own guard, so nothing needs agreeing. A cosmetic
`grd {s, q}`, sent at most 4 times a second, poses the opponent's avatar for
the attacker. It may be stale; the defender's view decides.

### 2.7 Enemy traits (`CombatTune.ENEMY`, keyed by archetype)

Wild foes use the `arche` from `Land.FOES`. Their `ranged` setting overrides
it. Build 2 adds the first four columns, Build 3 the last two.

| Archetype | parry_skill | block_skill | pref_band | chase | stance_time | adapt |
|---|---|---|---|---|---|---|
| 1 Warden / thrall | 0.15 | 0.25 | REACH | 0.3 | 1.8 | 0.3 |
| 2 Duelist / bandit | 0.35 | 0.10 | REACH | 0.7 | 1.2 | 0.6 |
| 3 Gravemaul / brute | 0.05 | 0.35 | CLOSE | 0.2 | 2.4 | 0.2 |
| 4 Keeper / wight | 0.25 | 0.35 | REACH | 0.5 | 1.6 | 0.5 |
| 5 Regent / pyre guard | 0.35 | 0.25 | REACH | 0.7 | 1.2 | 0.7 |
| archer | 0.0 | 0.10 | OUT | 0 | 2.0 | 0.2 |
| caster | 0.10 | 0.0 | OUT | 0 | 2.0 | 0.3 |

These are added as plain fields on `EnemyDef` with defaults, so the PvP
opponent (`EnemyDef.new()`) still works.

## 3. Builds

### Versions in player-vs-player (all builds)

- `challenge`, `attack` and `accept` carry `card.cv`, the combat version:
  missing = 1 (today), Build 1 = 2, Build 2 = 3, Build 3 = 4. Both sides run
  **min(mine, theirs)**.
- A new client facing an older one shows the caption "Classic duel: their game
  is older." The old client sees nothing different. A new client never sends a
  new message kind, field or `res` outcome below the version that brings it.
  Unknown kinds and fields are already ignored by old clients.
- Below the matching version, every new rule that touches defence (stun on
  posture break, the directional guard, reach) behaves as today. A rule that
  only changes local presentation (the feel pass) applies at every version.
- New kinds (`pst`, `step`, `grd`) don't affect the check's counts. Every `atk`
  still gets exactly one `res`.

### Build 1: feel and posture

- **Scope:** §2.1, §2.2, `CombatTune.B1`, the `pitch` argument and pool size
  in `Sfx`, `cv` = 2, PvP `po`/`pf`/`pst`/execution.
- **Must not change:** parry, dodge and block windows; enemy combos and
  damage; OPEN sources; chains; inputs; saves; the RESULT line, apart from a
  new `execs=N` field placed before `foes=`; PvP behaviour against an old
  client.
- **Done when** a tester sees: (1) a perfect parry looks and sounds clearly
  different from a plain one; (2) the gold bar fills on parries and drains
  after a pause; (3) three perfect parries on a Field Thrall bring SWIPE TO
  EXECUTE, and one swipe kills it with the side camera; (4) on the Cinder
  Warden, an execution takes about 40% of health and the fight goes on;
  (5) blocking until the blue bar fills stuns you about 1 s; (6) on a hillside
  the finisher camera never goes under the ground; (7) two new-build players'
  duel shows each other's posture, and an execution takes 30%; (8) a new
  against an old build duels exactly as today; (9) all of `node tools/check.js`
  passes.
- **Bots:** already swipe while OPEN, so they execute. Check that `x` still
  wins duel-win, duel-gear and duel-tower within the time limits (ordinary
  parries now give half the break, but executions kill wild foes), and that
  `idle` still loses. The PvP bot executes when `pst` arrives on its turn.
- **Risks:** pitch under web samples (test first; fall back to volume-only
  layers). Longer guardian fights if the drain is too strong (tune B1.drain).
  Hit-stop now nests inside slow motion, so check that time-scale tokens still
  restore 1.0 (or 4.0 for bots).

### Build 2: range, footwork, player-led offence

- **Scope:** §2.3, §2.4, the first four columns of §2.7, `CombatTune.B2`, the
  step buttons and keys, `cv` = 3, PvP `step` and `o` (see question 4).
- **Must not change:** parry and dodge timing, OPEN cuts, everything from
  Build 1, the PvP turn structure, saves, the RESULT format.
- **Done when:** (1) ▲/▼ and W/S move you between three visibly different
  distances in the tower, in the arena, and on a slope; (2) stepping back
  during a left cut makes it whiff, and a thrust still hits; (3) a duelist
  follows you out about two times in three, and an archer backs off; (4) a
  swipe at an idle foe either lands, is guarded, or is parried and followed by
  a counter you can parry; (5) cutting the same way four times gets parried
  noticeably more; (6) with two side foes, they stay beside you as you step;
  (7) swiping from OUT lunges; (8) the check passes.
- **Bots:** step in whenever the gap is OUT (all foes, archers included).
  `x` throws a free cut when the foe is IDLE, the bot is READY and at REACH,
  alternating L and R and never repeating a direction; it doesn't step back.
  A counter is an ordinary WINDUP, which it already handles. The PvP bot steps
  in if out. Add the free-cut count to RESULT before `foes=`.
- **Risks:** the largest build. Clipping into rocks and walls when stepping
  back (accept it, or cap OUT where the space behind is blocked: unknown,
  since there's no collision query in duels today). Camera framing on CLOSE
  with big foes (Gravemaul's scale is 1.85; test it). Free cuts making parrying
  pointless (watch the parry count in RESULT; tune `free_cut_mult`). If enemy
  parries feel random in the playtest, bring §2.6's enemy stances forward;
  they are designed to slot in.

### Build 3: weapon identities and guard stances

- **Scope:** §2.5, §2.6, the last two columns of §2.7, `CombatTune.B3`, the
  side poses, the per-family combo list on the pause screen, `cv` = 4.
- **Must not change:** individual weapon stats and prices, saves, Builds 1-2.
- **Done when:** (1) each family's chains fire with its own banners; (2) each
  signature works by its input and shows its name; (3) a twin feels best close
  and a greatsword at reach or out; (4) guarding left stops a left cut and lets
  a right cut through; raising guard during a windup faces it automatically;
  (5) a feint flips sides when you guard it; (6) the enemy's guard side can be
  read on a phone, and cutting the open side lands; (7) Space + A/D/W changes
  the side on desktop; (8) the check passes, including suggested scenarios with
  `--equip=twin_fangs` and `--equip=pyre_greatsword` (the orchestrator owns
  `tools/`).
- **Bots:** while guarding, set the side to the telegraphed attack (the `block`
  bot). `x` aims free cuts at the enemy's open side, and after a parry
  sometimes uses the counter-cut. Greatsword bots use guard breaker at CLOSE.
- **Risks:** one-sided blocking makes the game harder for current players and
  the `block` bot (question 3). The side-switch swipe while holding block needs
  two thumbs; test it on a small phone. Enemy guard poses may be hard to read
  at 720p on a phone, which is why the HUD icon is there.

## 4. Questions for the owner

1. **How hard should an execution hit a boss?** Recommendation: ordinary foes
   die; elites lose 60% and tower guardians 40%, so bosses need two or three
   executions plus cuts. Killing outright makes posture everything and boss
   fights short. A smaller slice makes posture feel like a side reward.
2. **Should the foe's posture recover?** Recommendation: yes, slowly (after
   2.5 s), and slower when they're hurt. That rewards keeping up pressure.
   Without recovery it is simpler and easier, and backing off costs nothing.
3. **Directional guard in Build 3: replace the old block, or keep both?**
   Recommendation: replace it, but have the guard face the telegraphed attack
   automatically when you raise it, so a single blow is as easy as today and
   only combos and feints test you. Keeping an any-side block (at double cost)
   is gentler, but the stances then matter much less.
4. **Range in player-vs-player: in Build 2, or later?** Recommendation: later.
   It is the most delicate network piece and adds little to turn-based duels.
   Bring posture (Build 1) and guard (Build 3) to PvP, which are simple there.
   Doing it in Build 2 costs time and risk in that build.
5. **Step controls on the phone.** Recommendation: two buttons beside the
   dodge buttons (▼ back on the left, ▲ in on the right), plus the automatic
   lunge when you swipe from too far away. The alternative, tap the screen to
   step in and keep only a back button, frees space but risks accidental steps
   from short swipes.
