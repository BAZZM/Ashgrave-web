# Ashgrave: from OK to amazing

The working plan for orchestrated development. The orchestrator (the main
Claude session) owns this file; subagents read it and report back, they do not
edit it.

## Goals, in priority order

1. Smoothness: no stutter while walking, steady frame rate on a phone.
2. Combat feel: the directional duel stays, and gets deeper and punchier.
3. Lighting and atmosphere.
4. World and questlines.
5. Refactoring only where it unblocks the above.

## How work is organised

- `main` is the live game. Nothing reaches it without the owner's say-so.
- `dev` is the integration branch. Subagents branch from it in their own
  worktree and commit source only.
- Only the orchestrator runs `tools/build.py` for a commit. Every build renames
  the pack and edits `index.html`, so two branches that both commit a build
  always conflict. Subagents build to test, then leave `index.html` and
  `game_*.wasm` uncommitted.
- Each track owns a set of files (below). Touching a file outside your set
  needs the orchestrator's agreement first.
- At most three subagents run at once. The headless browser here renders at
  2-4 frames a second and slows further when shared.
- This sandbox has no real GPU. It can prove a build loads and that bots finish
  their runs. It cannot judge smoothness or feel; the owner playtests on a
  phone and on desktop after each wave.

### Choosing a model

The cheapest model that can do the task, moving up one tier after a failed
attempt rather than retrying at the same tier.

- Haiku: bulk and mechanical work against a fixed schema (quest text, item
  tables, comment restoration).
- Sonnet: well-specified implementation. Effort set per task: low for
  mechanical edits, medium by default, high for fiddly work with many edge cases.
- Opus: only where the orchestrator can name the reason, normally restructuring
  code that every track depends on, or design work where a wrong call is
  expensive to undo.

### Rules every subagent follows

- Keep saves loadable: the format in `game/scripts/run.gd` only grows.
- Keep the online message format compatible: old builds stay in the shared
  world until their tab is reloaded.
- No Godot editor exists here. New scenes, sounds, fonts and models cannot be
  imported; build new content in code.
- A change is not done until `node tools/smoke.js` passes and the feature
  touched has been exercised.
- Report what was verified and what was not. Do not fix bugs found outside your
  files; report them.

## Wave 0: foundations

| # | Task | Owns | Model | Status |
|---|------|------|-------|--------|
| 0.1 | On-screen performance readout, off unless `?perf=1` | `game/scripts/perf.gd` (new), autoload line in `project.godot` | Sonnet, medium | done |
| 0.2 | Automated checks: bot runs as pass/fail | `tools/` | Sonnet, high | started |
| 0.3 | Split `overworld.gd` and `duel.gd` along their seams, no behaviour change | those two files and the new files they become | Opus | after 0.2 |

0.3 waits for 0.2 because the checks are what make a 3,000-line restructure of
commentless code safe. Opus is justified here: every later track builds on
these files and a subtly wrong split costs all of them.

## Wave 1: parallel tracks

Starts after 0.3 and the owner's first phone readings. File ownership is set
once the split in 0.3 decides the new file names.

### Smoothness (Sonnet; Opus for terrain streaming if needed)

Suspects from reading the code, not yet measured:

- A terrain chunk is built in one go on the frame the player crosses into range.
- Both HUDs redraw everything every frame.
- A character is assembled from many separate meshes, so each visible foe costs
  many draw calls.
- Other players ease toward a position that updates every 0.3-1.5 s, so they
  glide and snap.
- The whole save is written to browser storage every 5 s.
- Shadows and anti-aliasing are fixed regardless of device.

Order of work follows the phone readings from 0.1, worst first.

### Battle (Opus designs, Sonnet builds)

The directional duel stays and gains, as chosen by the owner:

1. Feel pass: heavier impacts, a finisher camera, layered hit sounds.
2. Posture as the way to win: perfect parries fill the foe's posture bar, a
   full bar means an execution. The player has a posture bar too.
3. Player-led offence: attack at any time; enemies parry and counter by
   direction.
4. Weapon identities: each weapon family gets its own direction chains and a
   signature move.
5. Guard stances: hold a guard direction; attacks from that side are blocked.
6. Melee range and footwork: stepping in and out, with distance deciding what
   can hit.

Range changes what every other item means (who can reach whom, when a parry is
even possible), so it is designed in from the start even though it is built
late. Order:

- Design (Opus): one short spec covering all six and how PvP carries them over
  the relay, written against the existing duel code. The owner approves it
  before anything is built.
- Build 1 (Sonnet): feel pass and posture. Smallest change, felt in every fight.
- Build 2: range and footwork, with player-led offence, since both change who
  acts when.
- Build 3: weapon identities and guard stances.

Each build is playable on its own and goes to the owner for a playtest.

### Traversal (Sonnet)

Today: walking speed is 5 units a second (plus 0.35% per agility level) and the
land is about 440 by 460 units, so village to tower gate is roughly 45 seconds
of holding the stick. There is no sprint, mount or fast travel. The map screen
is view-only.

- Fast travel: tap a discovered place on the map to go there (hearth, fisher's
  fire, quarry anvil, shrine, altar, standing stones, watchtower, tower gate).
  Not while a foe is close or in a duel, and not out of the Ashlands, so it is
  no escape from PvP. Cheapest and carries no performance risk, so it goes first.
- Sprint, and a speed bonus on roads (the road paths already exist as data).
  Faster movement crosses terrain chunks more often and makes other players'
  movement harder to smooth, so this ships with or after the terrain-loading
  fix in Smoothness, in the same files.
- A mount, later: needs a model and animation built in code, so it sits with
  Visual polish.

Fast travel runs as its own task in Wave 1. Sprint joins the Smoothness queue.

### World and quests (orchestrator outlines, Sonnet builds, Haiku fills)

- Move quests into data tables so content can be added without code.
- A story outline and one questline per region.

### Visual polish (Sonnet), after Smoothness

Lighting, sky, weather and hit effects, all generated in code. Shares rendering
code with Smoothness, so it follows rather than runs alongside.

## Wave 2: integrate and fix

Merge the tracks, balance, and fix what playtests turn up.

## Bug log

| Bug | Status |
|-----|--------|
| Two players online never saw each other (split across relays) | fixed, live |
| A fighter who died stayed tipped over until reload; later falls looked wrong | fixed, live |
| Finisher camera aimed away from the foe in open-world duels (world point used as a local one) | fixed on `dev` |
