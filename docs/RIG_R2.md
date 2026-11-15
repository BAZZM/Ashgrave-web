# Rig stage R2: the rigged hero in the world, behind a flag

## What was built
RigVisual now carries the hero through the overworld and the tower's walking scenes. Duels stay on PlaceholderVisual. New: `rig_looks.gd` (look mapping), `rig_cycle.gd` (`--rigcycle=N` debug), a shared-shader class mask (faces in shadow), a locomotion rate derived from real speed, a hidden/off-screen tick skip, `RigVisual.release()`.

## The switch
| Case | Hero |
|---|---|
| `--rig` (or `?rig=1`), assets present, quality allows models | rig |
| no flag | primitive, rig script never loaded |
| Safe quality with `--rig` | primitive; `release()` and `TexKit.clear()` run, no rig resource held |
| rig assets absent | primitive |

The quality gate is checked before the rig script or any asset is loaded (`FighterVisual.rig_wanted()`). Rig assets stay out of release packs; build with `tools/build.py --rig` (or `--looktest`).

## Duel hand-off
`Overworld.hero_swap(false)` at duel and PvP start, `hero_swap(true, true)` in `duel_done`. Verified with `HERO swap` lines in a `--rig` run: primitive at start, rig restored after, repeated twice, one hero at a time.

## Faces and head
The atlas alpha holds a class (60 face, 120 cloth, 190 keep, 255 metal). Face texels are darkened (`face_shade` 0.4) and lifted less, so the face stays dark brown under the helm. Head scale default is 0.85.

## Legs
Clamps removed. Rate = measured speed / scale / natural speed (walk 0.64, run 3.2 u/s), clamped only to 0.1..12. The walk clip plays below 1.5 u/s, the run clip above (hysteresis 0.85). Foot slide, measured on the real path:

| speed u/s | clip | slide (mean) |
|---|---|---|
| 1.0 | walk | 45% (under the 60% bound) |
| 2.0 | run | 10% |
| 5.5 | run | 12% |
| 9.5 | run | 12% |
| 12.5 | run | 9% |

Chibi legs stride only 0.4 u, so slide at walk speed is visible but small in absolute terms (about 0.45 u/s).

## Looks
Mapped: weapon families to 1H sword, dagger (plus back blade) or 2H sword; shields to badge, round or rectangle; helms to sallet (KayKit) or code-built great helm and hood; `accent` to cloth and cape; `over` (blade tint, runes glow, fin, spikes, bulk, half cape, crossbow, knife belt). Code-built fallbacks: great helm, hood, fin, shoulder spikes, back crossbow, knife belt, spell orb. Hunter's Bow is now Hunter's Crossbow in display text only (item id and saves unchanged).

## Cost
| | primitive | rig |
|---|---|---|
| land draws | 368 | 305 |
| tower draws | 149 | 87 |
| land resources | 60 | 92 |
| texture bytes | 5.66 MB | 6.01 MB |
| video mem | 22.2 MB | 22.9 MB |

Draw counts are with `--rig` versus without, same scene. At most two materials per rig, everything heavy shared. Six land/tower scene changes leak nothing. Pack growth when shipped: 1.88 MB raw, 1.78 MB gzipped.

## For R3 (duels)
Hold the contract: `play`, `configure`, `set_tell`, `set_walk`, `set_pace`, `flash`, `get_clash_point`. `hero_swap` is the one place to flip duels to the rig. Open: the idle sword is held sideways, hero hovers slightly over its shadow, leather body reads grey, great helm and hood are oversized.

## Departures from the plan
- Question 4: one-handed clips for every weapon, shield kept (orchestrator, owner away).
- Atlas slot 128 px; masks for barbarian, rogue and skeleton are rule-based, not hand-corrected (R4).
- Rogue body and hood not packed; code-built fallbacks.
- Enemies and remote players stay primitive; other players see the primitive hero.
- Save and online formats unchanged.
