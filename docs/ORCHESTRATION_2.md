# Ashgrave: unattended orchestration plan (from 13 Nov 2026, 22:30)

The owner is away and cannot answer questions. This file is the standing brief
for the orchestrator (Fable 5.2) and for any session that has to pick the work
up. It sits on top of `docs/ORCHESTRATOR.md` (phases, gates, roles) and
`docs/PLAN.md` (branch rules, rules every subagent follows).

## Owner's instructions (13 Nov)

- Three tracks: **performance**, **texture and graphics**, **story**.
- Build 12 on the owner's iPhone: stuck-in-walls is better; **it still crashes**.
- **Release when green:** a build goes live on `main` when every bot scenario
  passes on the exact pack and one independent review says ship.
- This session owns all texture and graphics work (the texture chat produced
  nothing in the repo).
- **Texture colour treatment is chosen by a fresh Visual Critic** from the
  look test (flat, greyscale grain plus palette, source colours).
- Story: build on the existing lore; do not rework it.
- **Usage: two lanes at a time.** Sonnet by default; Opus for deep debugging and
  cross-cutting work; Fable for design, taste and reviews; Haiku for bulk text.
- **Automatic safe mode is approved:** after two detected memory deaths the game
  may drop to a lighter mode, with a menu toggle to restore full quality.

## How to run unattended

- Ask nothing. Where a choice is needed, take the recommended option, and log
  it in `docs/DECISIONS.md` marked "orchestrator, owner away" so it can be
  reviewed and reversed.
- Stop a task (park it, move to the next) on: anything needing an account,
  payment or a download the build machines cannot reach; any licence doubt;
  destructive git; a third failure of the same check.
- One adversarial review per release, not per lane. Fix findings graded
  Important or worse before release.
- Every finished lane branch is pushed to `origin` as `lane/...` before it is
  merged, so a lost workspace loses nothing. `dev` is pushed after each merge.
- Run `tour` and the two `pvp` scenarios alone; they time out on a busy machine.
- State lives in: this file's status table, `docs/DECISIONS.md`, the local
  ledger `.superpowers/sdd/ledger.md` in the owner's folder, and the claude.ai
  project doc `claude/orchestrator-status.md`.
- If agents stop (usage limit or a restart), resume them from their transcripts;
  uncommitted work stays in their worktrees.

## Queue (two at a time, in this order; a later item starts when a slot frees)

| # | Track | Task | Model | Files | Status |
|---|---|---|---|---|---|
| P1 | Perf | Memory and crash investigation by soak bot; fix leaks found; `perf-soak` scenario; `docs/PERF_BUDGET.md` | Opus | any script, minimal; `tools/` | running |
| S1 | Story | `docs/STORY_BIBLE.md` and a fully written Act 1 from existing lore | Fable | docs only | DONE, merged (6010437) |
| P2 | Perf | Safe mode and quality settings (pixel-ratio cap, shadows, auto-drop after two memory deaths, menu toggle) | Sonnet | `perf.gd`, `run.gd` settings, `world_hud.gd` | queued |
| G1 | Graphics | Lighting and atmosphere per `docs/ART_BIBLE.md` section 4; Golden Shots before and after | Sonnet | `overworld_sky.gd`, `arena.gd`, lights in `world.gd` | running |
| S2 | Story | Quests as data; dialogue UI; Act 1 playable; quest bot scenario | Sonnet | `quests.gd`, `story.gd`, `world_hud.gd`, NPC hooks | queued |
| G2 | Graphics | `tex_kit.gd`, texture import, look test with three treatments | Sonnet (Opus if the shader fights the renderer) | new files; debug hook in `overworld.gd` | queued |
| G3 | Graphics | Visual Critic picks the treatment; apply ground and water behind the quality setting; memory measured | Fable, then Sonnet | `overworld_terrain.gd`, `overworld_kit.gd`, `land.gd` colours | queued |
| S3 | Story | Acts 2 and 3 and region side quests filled against the schema | Haiku, Sonnet review | quest data | queued |
| G4 | Graphics | Walls and wood, then trees | Sonnet | `overworld_places.gd`, `world.gd`, terrain scatter | queued |
| R1 | Graphics | Resume rig stage R1 (paused, work on `lane/p2-r1-rigvisual`) | Opus | see `docs/RIG_PLAN.md` | parked until the above are out |

## Releases

Build 13: P1 and P2. Build 14: G1. Build 15: S2. Build 16: G3. Then G4 and S3 as
they pass. Each release: full `node tools/check.js` on the pack, one review,
bump `BUILD` in `run.gd`, commit the build on `dev`, push `dev`, fast-forward `main`.

## What cannot be verified without the owner's phone

Real iPhone memory limits, touch feel, and whether a visual change reads well
on the device. Texture and model stages therefore ship behind the quality
setting with safe mode as the fallback, and every release records heap,
texture memory, draw calls and pack size in `docs/PERF_BUDGET.md`.
