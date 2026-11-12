# ASHGRAVE — Fable 5.2 Orchestrator Plan

> Start a new Claude Code conversation on this repo with Fable 5.2 selected and say:
> **"Read CLAUDE.md and docs/ORCHESTRATOR.md fully. You are the orchestrator (Fable 5.2). Do the Reconciliation step, then begin Phase 0. Follow the Session Protocol."**
>
> This document is the user's explicit opt-in to subagent-driven development for Ashgrave, within the limits below.
>
> **Model routing (set by the user, 12 Nov).** Fable 5.2 orchestrates and takes taste, architecture and rules design. Opus 5.5 takes large, cross-cutting or subtle implementation and deep debugging (the animation tree, the action model, netcode, `casino_core`, the iPhone memory hunt). Sonnet 5.5 takes implementation to a written spec. Haiku 5.5 takes mechanical work. Use the cheapest tier that will pass the acceptance check; where the role table below says Sonnet, move the task to Opus when it fits that description.
> API IDs: `claude-fable-5-2`, `claude-opus-5-5`, `claude-sonnet-5-5`, `claude-haiku-5-5`.

## Reconciliation (do this before Phase 0)

This plan was written without sight of work already under way in this repo. As of 12 Nov:

- `docs/PLAN.md` is an **earlier orchestration plan that is still live**: Wave 0 is done (perf readout via `?perf=1`, `tools/check.js` bot checks, the split of `overworld.gd` and `duel.gd`), and Wave 1 has lanes started on `dev` (Combat Build 1, fast travel, Smoothness A). `docs/COMBAT_SPEC.md` is approved. Another session may still be running those lanes.
- So: read `docs/PLAN.md`, `docs/CODE_MAP.md` and the `dev` branch state first. Then **ask the user** whether in-flight Wave 1 lanes are finished and merged, or folded into this plan, before dispatching anything that touches the same files. Do not run two orchestrators over the same files.
- Where the two plans overlap, reuse what exists: task 0.2 here extends `perf.gd` (add the crash breadcrumbs); task 0.4 extends `tools/smoke.js` and `tools/check.js`; P2's combat work builds on `docs/COMBAT_SPEC.md` and must not contradict the answers already given there; fast travel in P4 may already be done.
- The file ownership, branch rules (`main` live, `dev` integration, only the orchestrator commits a build) and subagent rules in `docs/PLAN.md` and `CLAUDE.md` stay in force. This document adds phases, gates and roles on top of them; record which plan governs what in `docs/DECISIONS.md`.
- **Assets need an engine.** `CLAUDE.md` notes no Godot editor is installed and new scenes, sounds, fonts and models cannot be imported. Phase 1 depends on importing `.glb` models and textures, so Phase 0 must install Godot 4.4.1 headless (the build used it originally) and prove an imported model survives `tools/build.py` and loads on the phone, before any asset work is planned.
- All current art is procedural (built in code); the only third-party files are the Cinzel font (SIL OFL) and generated sound effects. No licensed packs are in the repo.

---

## 0. Mission and non-negotiables

Ashgrave is an iPhone-first dark-fantasy swipe-duel game (Infinity Blade lineage) that grew into a tower plus an open world with skills, online PvP and now casinos and clans. Godot, web build on GitHub Pages, played in Chrome on iPhone.

**Non-negotiables, in priority order:**

1. **It must stay alive on an iPhone.** Every browser on iOS is WebKit, so Chrome on iPhone has Safari's memory watchdog. The random reloads you've reported are most likely iOS killing the tab for memory. Art, content and netcode are all budgeted against that. **No phase passes its gate if the build gets less stable.**
2. **The best visual product we can reach with free, legal assets.** Cohesion beats quantity. Ten cohesive things beat a hundred mismatched ones. Visual quality is a gate on every phase, not a final polish step.
3. **Everything shipped is legally clean.** Free sources only, CC0 by default, every asset logged in `docs/ASSETS.md`. The repo is public, so what goes into it matters (Section 7).
4. **Long-run sustainability.** Work in waves with approvals, durable state on disk, small briefs, small returns. A session can end at any point without losing anything.

**Frozen decisions (from the user; do not reopen without approval):**
Godot engine. Web build on GitHub Pages, played in Chrome on iPhone. Virtual stick for world movement, sidelined in battle. Fights happen in place (no arena cut). Unlimited pack (no bank). Bloodlines are tower-only. Live duels only (no shades). Open PvP zone in the Ashlands is the stakes. Free public relay is the current online transport (Decision Point 3 may supersede it). Multi-foe fights use the side alert icon to change perspective.

---

## 1. What changed from your existing plan

| Your item | Where it lives now | Why it moved |
|---|---|---|
| Check first: ONLINE joining, iPhone reload | **P0** (instrumented so you don't have to describe where it happens) | Everything else sits on a stable build |
| 3. Terrain smooth, walls low-fi, assets, enemy texturing | **P1** and **P3**, ahead of most features | You asked for the best visuals; the look is decided once, on a vertical slice, before scaling content |
| 4. Fluid movement; 1. faster/agile | **P2** | Needs one shared rig and animation tree first |
| 7. Builds, abilities, seamless melee/ranged/mage, blockable ranged | **P2** (system) and **P3** (content) | System first, then variety |
| Drag-to-aim, rune tracing | **P2** | Part of the combat-style system |
| Tower nav, Chandler, fast travel, 2nd dungeon, Thieving/Runecraft/Farming | **P4** | Content on top of the look from P1 |
| 5, 6. Poker, roulette, blackjack | **P5** (blackjack, roulette, then poker) | Shared `casino_core` first; offline-capable, online later |
| Online extras, own relay, anti-cheat | **P6** (server foundation), starts as a background lane during P3 | Persistence and authority are prerequisites for clans |
| 2. Faction PvP, land claims, bases; Housing | **P7** (housing merged into bases) | Needs the server from P6 |
| (new) Hardening, credits, polish | **P8** | |

---

## 2. Operating model

### 2.1 Roles
You are the **Orchestrator (Fable 5.2)**. You plan, dispatch, integrate, run gates and talk to the user. You do not write feature code, except trivial glue. This keeps your context clean across a long project.

| Role | Default model | Owns |
|---|---|---|
| Recon (Explore agent) | Haiku 5.5 / Sonnet 5.5 | Read-only inventory; answers questions about the repo |
| **Art Director** | **Fable 5.2** | `docs/ART_BIBLE.md`, style options, taste calls, final say on look |
| **Technical Artist** | **Fable 5.2** | Terrain/wall/enemy shaders, material system, lighting, perf-for-art |
| Environment Artist | Sonnet 5.5 | Kitbashing rooms/regions from approved assets, using the Art Bible |
| Asset Scout and Licence Clerk | Sonnet 5.5 (Haiku for bulk logging) | Shortlists, `docs/ASSETS.md`, licence evidence, CREDITS |
| **Animation Lead** | **Fable 5.2** | Rig standard, retargeting, AnimationTree, stance transitions |
| **Combat Designer** | **Fable 5.2** | Action model, ranged/mage block rules, builds, enemy abilities |
| Gameplay Engineer | Sonnet 5.5 | Implementation to a Fable-written spec |
| Systems Engineer | Sonnet 5.5 | Skills, navigation, vendors, quests, economy |
| **Casino Architect** | **Fable 5.2** | `casino_core` design, poker rules, fairness and authority model |
| Casino Engineer | Sonnet 5.5 | Blackjack, roulette, UI, bots |
| **Network Architect** | **Fable 5.2** | Server design, authority, anti-cheat, persistence |
| Network Engineer | Sonnet 5.5 | Implementation |
| UI/UX Engineer | Sonnet 5.5 | Touch-first HUD, menus, table UIs |
| QA and Perf Gatekeeper | Sonnet 5.5 (Haiku for mechanical runs) | Builds, tests, screenshots, perf numbers |
| **Visual Critic** | **Fable 5.2, fresh context every time** | Scores screenshots against the rubric (Section 6) |
| **Adversarial Reviewer** | **Fable 5.2, fresh context every time** | Reviews diffs at gates; never the author |

**Routing rule:** judgement, taste, architecture, rules design → Fable. Implementing a written spec → Sonnet. Large, cross-cutting or subtle implementation → Opus. Mechanical (run build, format, move files, log entries, write manifest rows) → Haiku or the shell. If a Sonnet lane fails the same acceptance check **twice**, escalate that task one tier (Sonnet → Opus → Fable) and say so in the ledger. Never loop a third time on the same tier.

### 2.2 Concurrency and git
- **At most 3 lanes active at once.** Never two lanes touching the same files.
- One lane = one branch: `lane/<phase>-<slug>`, in its own worktree where possible. Merge to `main` only through a gate (Section 5), never directly from a lane.
- Never force-push, rewrite history or delete branches without the user.

### 2.3 Durable state
Anything not on disk is lost when a session ends.

**Committed** (public repo, no secrets):
- `docs/PLAN.md` — roadmap and status (update the status column only)
- `docs/ORCHESTRATOR.md` — this file
- `docs/RECON.md`, `docs/ART_BIBLE.md`, `docs/PERF_BUDGET.md`
- `docs/ASSETS.md` — asset manifest and licence record
- `docs/DECISIONS.md` — every user decision, dated, with the options offered

**Local only** (`.superpowers/sdd/`; never commit; confirm it's in `.gitignore`):
- `ledger.md` — current wave, lanes, branch, status, model used, rough size, next action
- `briefs/`, `reports/`, `screens/`, `critiques/`
- `assets_src/` (outside the Godot project): raw downloads and anything whose licence forbids redistribution (also gitignored)

### 2.4 Session Protocol (every session, no exceptions)
**Start:** read `ledger.md`, `docs/DECISIONS.md`, the current phase section of this file, and `git status`. Summarise to the user in ≤6 lines, then continue. **Do not re-explore what is already in RECON.md.**
**End (or before any long wait):** update `ledger.md`; write a ≤10-line handoff at its top: what is done, what is in flight, what the next orchestrator should do first, what is waiting on the user.

### 2.5 Subagent brief (one page max; use this exact shape)
```
LANE: <id> <slug>            MODEL: <tier>            BRANCH: lane/<...>
GOAL: one sentence, outcome not activity
READ FIRST: <≤5 files with line ranges if known>
CONSTRAINTS: engine/version pin, perf budget refs, frozen decisions that apply, files you may touch
DONE WHEN: <testable acceptance checks, incl. screenshot/number evidence>
RETURN: ≤250 words + paths. Include: what changed, evidence, risks, anything you were unsure of.
DO NOT: commit assets_src or .superpowers; add unlogged assets; touch files outside the list.
```
Subagents return **paths and evidence, not file dumps.** You read their output files only when a gate needs it.

### 2.6 Approvals and spend (long-run usage)
- **One approval per wave.** Before each wave, post a **Wave Card**: lanes, model per lane, rough size (S/M/L), expected user time (e.g. "you test on phone, 10 min"), the gate. Wait for an OK. Inside an approved wave, proceed without asking.
- **Stop-and-ask list (always):** work beyond the Wave Card; any licence uncertainty; anything needing an account, paid service or hosting; destructive git actions; a third failure on one task; any change to a frozen decision; the Decision Points in Section 8.
- **Decision Points:** present 2–3 options, one-line cost/risk each, a recommendation. Record the answer in `DECISIONS.md`. **While waiting, continue lanes that don't depend on the answer.**
- Prefer Haiku or the shell for anything mechanical. Never ask Fable to re-read a file a Sonnet lane has just summarised unless a gate requires it.

---

## 3. Phase 0 — Recon, stability, pipeline (Wave 0)

**Goal:** know exactly what exists, make the iPhone crash diagnosable, and build the tooling every later phase needs.

| Task | Lane (model) | Output |
|---|---|---|
| 0.1 Recon | 2× Explore (Haiku/Sonnet) | `docs/RECON.md`: Godot version and renderer; 2D vs 3D; scene tree overview; current combat input model; current character rig/skeleton; **inventory of every art/audio asset with source and licence**; export settings; texture import settings and sizes; whether threads are enabled; PLAN.md status |
| 0.2 Stability instrumentation | Gameplay Eng (Sonnet) | In-game debug overlay (toggle): FPS, `Performance.MEMORY_STATIC`, object/node counts, texture memory, draw calls. **Crash breadcrumbs:** every few seconds write position/state/memory to `sessionStorage`; on boot, if the previous run didn't exit cleanly, show "restarted after a suspected memory kill" with the last breadcrumb. This answers "where does it reload?" without you having to describe it |
| 0.3 Export hygiene | Technical Artist (Fable) + QA | Pin the Godot version. Confirm **single-threaded** web export (the default since 4.3; works on iOS and needs no special headers on GitHub Pages). Audit every texture: max size, VRAM-compressed/Basis Universal where appropriate, mipmaps. Audit audio formats. **Do not upgrade Godot mid-project without a test pass** (there are community reports of web-export regressions between minor versions, and of an iOS audio crash in 4.5 dev builds fixed in a later beta) |
| 0.4 Screenshot harness | QA (Sonnet) | Script that launches the web build in headless Chromium at iPhone portrait and landscape sizes, and captures the **Golden Shots** (Section 6) from fixed debug camera spots. Note: headless is for **looks**; it can't prove iPhone memory behaviour, only your phone can |
| 0.5 Asset pipeline scaffold | Asset Scout (Sonnet) | `tools/` scripts: Blender headless export to `.glb`; glTF optimisation; texture downsizing; manifest row generator. `docs/ASSETS.md` created |
| 0.6 Roster materialised | Orchestrator | `.claude/agents/*.md` from Section 2.1, each with `model:` set and a tight tool list |
| 0.7 Perf budget v0 | Technical Artist (Fable) | `docs/PERF_BUDGET.md` (Section 4) with real measured baselines from the overlay |

**User tasks (Build 11):**
1. Open ONLINE on your phone. Does it show "ONLINE n" or stick on "JOINING"? (Public relays were unreachable from the sandbox, so this is still untested.)
2. Play 10+ minutes with the overlay on. If a reload happens, note whether the restart banner appears, and send the breadcrumb text it shows.

**Gate G0:** RECON.md reviewed by user; build deploys; overlay works on phone; you have either a reproduced reload with a breadcrumb, or 10+ clean minutes.

---

## 4. Performance and memory budget (provisional until P0 measures)

Why this exists: community reports for Godot web on iOS commonly cite a ceiling around **~300 MB** of runtime memory before iOS force-reloads the page. That is a rule of thumb, not a guarantee; **measure on your phone and set the real number in P0.** A reported fix for one texture-heavy Godot web game was importing textures with Basis Universal compression. WebKit also has open reports of reload loops under texture-heavy WebGL load.

Working rules until P0 replaces them:
- Treat **~200 MB steady-state** as the target (leave headroom below the rule-of-thumb ceiling).
- Uncompressed RGBA with mipmaps is about **5.6 MB at 1024²** and about **22 MB at 2048²**. Compressed block formats are roughly 4× smaller on the GPU. Use that arithmetic before approving any texture.
- **Tiling environment textures: 512². Hero atlases (player, boss): ≤1024². Nothing at 2048+** without Technical Artist sign-off and measured headroom.
- **Share textures and materials.** One gradient atlas per kit, reused. Prefer palette parameters per instance over per-enemy textures. Every unique texture costs memory on every phone.
- Instance everything repeated (MultiMesh for grass/rocks/props); distance-cull and LOD; keep draw calls low.
- Web export uses the Compatibility renderer. **Before relying on any feature (lightmaps, GPU particles, post effects, SSAO etc.), verify it works in the pinned version's web build.** Fall back to baked or faked lighting where needed.
- Every phase gate records: steady-state memory, peak memory, FPS at the three worst Golden Shots, build download size.
- **A change that raises steady-state memory more than ~10% needs an offsetting saving or Technical Artist approval.**

---

## 5. Gates (every phase ends with all that apply)

1. **Build gate** (QA): clean export, no console errors, deploys to GitHub Pages preview.
2. **Perf gate** (QA + you): numbers from Section 4 recorded; no regression beyond budget; **phase-specific phone check by the user.**
3. **Visual gate** (Visual Critic): Golden Shot set re-captured and scored (Section 6). Fix loop capped at 2 rounds, then escalate or ask the user.
4. **Licence gate** (Clerk): every new asset has a row in `ASSETS.md` with URL, author, licence, date, files used and where used. CC-BY items appear in `CREDITS.md`.
5. **Review gate** (Adversarial Reviewer, fresh context): reviews the diff against the phase's DONE criteria and the frozen decisions. Findings of "Important" or worse block the merge.
6. **Decision gate:** open Decision Points for this phase answered and logged.

Merge to `main`, update `PLAN.md` status, write the ledger handoff.

---

## 6. Visual quality system (the "best visual product" mechanism)

### 6.1 Principle
**Vertical slice first.** One impeccable slice (a tower hall, a stretch of the Ashlands, the hero, one enemy, the HUD) is built and approved in P1 before any content is scaled. Everything later is reproduced from that slice's rules.

### 6.2 Golden Shots (captured by the harness at fixed camera spots)
1. Hero on a road, wide, daylight-equivalent
2. Tower corridor/hall with torchlight
3. Duel framing: hero vs enemy, mid-combat
4. Hero close-up (gear readability)
5. Terrain at a grazing angle (reveals flatness and tiling)
6. Wall close-up (reveals fidelity)
7. HUD during a fight
8. Region-specific shot per biome added later
9. Casino table, seated view (from P5)
10. Clan base overview (from P7)

### 6.3 Rubric (Visual Critic scores each 1–5 with one-line justification)
Silhouette readability · Material coherence (one family of materials) · Lighting and mood · Colour script (palette discipline, regional identity) · Terrain variation (no visible tiling, believable breakup) · Wall and architecture fidelity · Character-to-world contrast and readability in motion · Enemy distinctness and texture richness · VFX clarity and restraint · UI legibility and style fit.

**Pass:** average ≥ 4.0 and no score below 3. The Critic must name the **top 3 specific fixes** with where to apply them. The Critic is a fresh instance with only the Art Bible, the screenshots and the rubric. It never sees the author's reasoning.

### 6.4 Motion check
For animation gates, capture **frame strips** (8 frames across an action) and ask the Critic about foot sliding, pose breaks, anticipation/recovery, weapon contact and transition pops. Add automated checks where possible (foot-slide measurement, transition time).

---

## 7. Free-asset guide (for the user, and the rules the agents follow)

*(Not legal advice. Licences change; the Clerk saves a snapshot of each licence page into `assets_src/<pack>/LICENCE.*` at download time.)*

### 7.1 Sources, verified this session

| Source | What it gives you | Licence | Notes |
|---|---|---|---|
| **KayKit** (Kay Lousberg, itch.io) | Rigged, animated low-poly characters (Adventurers, Skeletons), 133 humanoid animations, dungeon/forest/medieval environment kits | CC0 | Characters use a single 1024² gradient atlas that can be downsampled. Don't resell unmodified copies |
| **Quaternius** | Universal Animation Library 1 and 2 (~120 and ~130 animations on one universal humanoid rig), base characters, modular fantasy outfits, fantasy props | CC0 (including the free tiers) | Built for retargeting in Godot. Confirm which items are free vs paid on each page |
| **Kenney** | Prototype textures, UI, misc kits | CC0 | Some bundles list as unavailable; check the page |
| **Poly Haven** | PBR textures, HDRIs, models | CC0 | Use 1K versions for the web |
| **ambientCG** | 2,000+ PBR materials | CC0 | Use 1K versions; stone, brick, ground, metal, wood |
| **Mixamo** (Adobe) | Thousands of animations, auto-rigger | Royalty-free incl. commercial, **no redistribution of the raw files** | Needs a free Adobe account. See 7.3 |
| **Rokoko free clips** | Mocap clips | Commercial OK per source | Use only for gaps |
| OpenGameArt, Sketchfab, itch.io free packs, Poly Pizza | Huge variety | **Mixed per item** | Filter to CC0 first, CC-BY second (needs credit). Reject NC, ND and anything unclear. Poly Pizza is mostly CC-BY |
| FreePBR | Textures | **Personal use only; commercial is paid** | Do not use |
| Bandai Namco motion dataset | Motion | **CC BY-NC (non-commercial)** | Do not use |

### 7.2 Your shopping list for P1 (download, don't unzip into the project)
Put everything in `assets_src/` outside the Godot project. The Clerk ingests only what the Art Director approves.

1. KayKit **Adventurers** (hero/NPC bases) and **Character Animations**
2. KayKit **Skeletons** (undead enemy base)
3. KayKit **Dungeon Remastered** (modular walls/floors) and **Forest Nature Pack** (Ashlands dressing)
4. Quaternius **Universal Animation Library 1 and 2** (the main animation source)
5. Quaternius **Universal Base Characters** and **Modular Character Outfits – Fantasy** (visible gear changes)
6. Quaternius **Fantasy Props MegaKit** (tables, chairs, barrels, casino and base dressing)
7. From Poly Haven / ambientCG (1K): 3–4 stone/brick variants, dark soil, ash/dust ground, cracked rock, rough wood, aged metal, a few HDRIs for lighting reference only
8. Optional: a Mixamo account, for animation gaps only

The Asset Scout will refine this list after RECON.md shows what you already own.

### 7.3 Mixamo and your public repo (Decision Point 6)
`ashgrave-web` is public. Mixamo's terms allow using its animations in your game but not redistributing the raw files. So:
- Prefer the CC0 libraries (Quaternius UAL 1 and 2, KayKit) for every animation they cover. They are legally simpler and designed for retargeting.
- If you do use Mixamo, keep the raw FBX only in `assets_src/` (gitignored). Commit only what is baked into the game's own resources, and note the residual risk in `DECISIONS.md`.
- **Also check your existing licensed/paid packs' terms.** Many forbid raw source files in a public repo. RECON.md will flag any that are committed; decide what to do with them before P1 adds more.

### 7.4 Acquisition → game pipeline (the Clerk and Technical Artist follow this)
1. Download to `assets_src/<source>/<pack>/`; save a copy of the licence page.
2. Add the `ASSETS.md` row **before** the asset enters the project.
3. In Blender (headless script): apply transforms, fix scale to 1 unit = 1 m, merge materials, decimate where needed, bake AO where it helps, export `.glb`.
4. Re-assign to **shared atlases and materials**. Delete unused textures from the project.
5. Godot import: size cap, VRAM-compressed or Basis Universal for textures, mipmaps on, no per-prop unique textures.
6. Place in the scene via the Environment Artist, following the Art Bible rules.
7. Capture the Golden Shots; run the gates.

### 7.5 Applying assets tastefully (Art Director enforces these)
1. **One base kit per category.** Borrow from elsewhere only when the base has nothing. Three sources per category at most.
2. **Unify, don't collage.** Everything passes through the shared palette, shared materials, shared lighting and fog. If it still looks foreign after that, cut it.
3. **Detail hierarchy:** big shapes → medium trim and props → fine surface detail. Put detail where the player looks (duel framing, hero, gate); leave quiet areas quiet.
4. **Contrast on purpose:** the hero and the current enemy are the most readable things on screen. Environment values sit slightly lower and more muted than characters.
5. **Break repetition:** rotate and scale props, vary material tint per instance, add decals (cracks, stains, soot), and use a different wall module at a different cadence. Repetition, not low polygon count, is what makes free kits look cheap.
6. **Stylised silhouettes + real surface texture** is the target (see DP1): low-poly forms with 512² PBR stone, soil and metal detail beats either flat low-poly or photoreal-on-a-phone.
7. **Restraint with effects:** few, readable, well-timed. Particles and post-processing are the first things to blow the mobile budget.
8. **Colour script per region** (Ashlands ash-grey and ember; tower tiers shifting by floor; casino warm and gold against the tower's cold stone). Players should know where they are from one screenshot.

---

## 8. Decision Points (ask the user, log in DECISIONS.md)

| # | When | Options (recommendation first) |
|---|---|---|
| **DP1 Art direction** | End of P1 mood scenes | (A) **Stylised silhouettes + real PBR surface detail** (recommended; balances look and memory) · (B) Pure stylised/painterly low-poly with gradient atlases (safest on memory, flatter) · (C) Photoreal-leaning (rejected by default: not viable on iPhone web memory; Art Director may argue for it with numbers) |
| **DP2 Asset set** | After Scout shortlist | Approve the exact packs to ingest (≤3 sources per category) |
| **DP3 Server stack** | Start of P6 | (a) **Godot headless dedicated server** reusing game logic (best for casino fairness and combat authority; needs a host) · (b) Lightweight WebSocket server in another language plus a database for persistence · (c) Stay on public relays (cannot persist land claims or enforce fairness; not recommended past P5). Free hosting tiers change; the Network Architect verifies current terms. Your PC has `.fly` and `.supabase` folders, so those may already be set up |
| **DP4 Siege rules** | Start of P7 | (a) Timed siege windows with offline-owner protection (recommended) · (b) Always-on raiding · (c) Raids only vs online owners. Also: does a clan chest conflict with your "no bank" decision? |
| **DP5 Casino scope** | Start of P5 | Roulette wheel (European single-zero recommended vs American); poker bot personalities; chips are **in-game gold only, never real money** |
| **DP6 Mixamo and licensed packs** | Before P1 ingests | Section 7.3 |
| **DP7 Cross-family review** | Optional, at G2 and G6 | A non-Claude reviewer on one diff as a second opinion |

---

## 9. Phase 1 — Visual foundation and vertical slice (Wave 1)

**Goal:** a screenshot of Ashgrave on an iPhone that you'd show people.

| Task | Lane | Output |
|---|---|---|
| 1.1 Art Bible | Art Director (Fable) | `docs/ART_BIBLE.md`: pillars, palette, material families, lighting and fog recipe, silhouette rules, UI language, region colour scripts. **Three rendered test scenes for DP1** |
| 1.2 Shortlist and ingest | Asset Scout (Sonnet) + Clerk | DP2 list; after approval, ingest per 7.4 |
| 1.3 **Terrain** | Technical Artist (Fable) | Replace the smooth ground. Height- and slope-based blend of 3–4 materials (soil, ash, rock, path) in a custom shader; macro-noise to kill tiling; detail normals; real micro-relief in the mesh/heightmap; **scatter** (MultiMesh grass tufts, pebbles, rocks, debris) with distance fade; decals for tracks and stains. Verify each feature in the web build |
| 1.4 **Walls and architecture** | Technical Artist (Fable) + Env Artist (Sonnet) | Modular wall/floor/arch kit with trim sheet or triplanar stone, normal detail, baked or vertex AO, edge wear, props (brackets, banners, chains, cracks), light sources with believable falloff. Replace the low-fidelity walls everywhere in the slice |
| 1.5 Atmosphere | Technical Artist | Fog, sky or HDRI-informed lighting, colour grading that survives the Compatibility renderer; verify any post effect's cost |
| 1.6 Hero and one enemy, textured in style | Technical Artist + Env Artist | Establishes the enemy texturing recipe used in P3 (Section 11.1) |
| 1.7 HUD pass | UI/UX Eng (Sonnet) | Art-fitting frames, fonts (SIL OFL), touch targets sized for thumbs |

**Gate G1 (all gates, plus):** user approves "this is the look" on their phone. Nothing in P2+ may scale content until G1 is passed.

---

## 10. Phase 2 — Motion and combat feel (Wave 2)

**Goal:** the character feels fast and fluid; melee, ranged and magic are one seamless system.

### 10.1 One rig to rule them all (Animation Lead, Fable)
- Choose **one universal humanoid skeleton** (candidates: the Quaternius UAL rig or a KayKit rig; test retarget quality on the real hero before choosing). Everything humanoid shares it: hero, NPCs, **casino dealers**, humanoid enemies. This is what lets one animation library serve the whole game.
- Bone map, weapon/focus sockets (BoneAttachment3D), and an Animation Library structure: locomotion · melee sets per weapon class · bow/crossbow/throw · cast · block/parry/hit/death · emotes · casino (sit, deal, bet, fold).
- Retarget from T-pose references; verify no pops.

### 10.2 Agility (Combat Designer spec → Gameplay Eng)
- Higher base speed, **sprint** with stamina or momentum, acceleration and turn-rate curves, **dodge/dash with i-frames**, analog gait blend from the virtual stick (walk→jog→sprint), camera lookahead and soft lag.
- **Anti-skate:** playback speed tied to ground speed (or stride warping) so feet don't slide.
- Re-check world scale and travel times once speed changes (the world may feel smaller; fast travel helps).

### 10.3 Fluidity (Animation Lead)
- `AnimationTree`: BlendSpace2D locomotion, **upper/lower body layering** (move while attacking/aiming/casting), additive hit reactions, stance state machine, short blend times, cancel windows. Optional foot IK if affordable.
- Target: no frame where the character visibly "snaps" between states.

### 10.4 Seamless melee / ranged / mage (Combat Designer, Fable)
- **Action model:** every action = windup → active → recovery, plus cancel windows and interrupt rules. Melee, ranged and spells use the same model.
- **Stances derived from the equipped loadout** (main hand, off hand, focus). Quick-swap between stances mid-fight in ≤~0.25 s with blended draw/sheath on the upper body. No loading, no animation pop.
- **Ranged and magic work from distance but can be blocked at any time:** projectiles are real entities with travel time; the defender can block, parry (perfect timing reflects or staggers), or dodge during flight; block costs stamina; a broken block staggers. Melee closes the gap (lunges, gap-closers); ranged/magic is weaker at point-blank (slower or interrupted casts), so the triangle stays honest.
- Document the rules in `docs/COMBAT_RULES.md`; data-driven (Godot Resources) so P3 content is data, not code.

### 10.5 Controls (Gameplay Eng)
- **Drag-to-aim** for ranged: aim line, mild assist, cancel by dragging back.
- **Rune tracing** for spells: a forgiving unistroke gesture recogniser; 6–8 starter runes; visible trail; mistakes fizzle visibly. Keep **buttons as an accessibility fallback** toggle.
- Ties to the Runecraft skill in P4.

### 10.6 VFX
Readable projectile trails, cast glows, block sparks. Budget particles; verify GPU particle support in the pinned web build (use CPU particles if not).

**Gate G2:** frame strips and the foot-slide check pass; Visual Critic motion review passes; user confirms on phone that movement feels faster and fluid and that a ranged hit can be blocked.

---

## 11. Phase 3 — Enemy and build diversity (Wave 3)

### 11.1 How to texture enemies (the recipe)
You can't give every enemy its own texture on an iPhone. You can still make them look distinct:

1. **Base:** shared gradient atlas of the base mesh.
2. **Palette swap per instance** (shader uniform): same mesh, different colour identity, no new texture.
3. **Shared detail layers:** 2–3 tiling overlays used by *every* enemy (leather weave, scratched metal, grime) via the shader. This unifies the whole bestiary and costs almost nothing.
4. **Emissive masks** for runes, eyes, wounds (a small mask, or a vertex-colour channel).
5. **Kitbash:** armour and weapons from the modular outfit and prop kits; scale and proportion variation.
6. **Tiers:** grunt = palette + kitbash; elite = plus emissive and silhouette change; **boss = one hand-painted ≤1024² texture** painted in Blender or Krita, in the Art Bible's style.
7. **Damage/dissolve shader** for death and hit flash (shared).

### 11.2 Roster and abilities (Combat Designer, Fable)
- 12–16 archetypes across melee brute, duelist, assassin, archer, mage, summoner, shield wall, flyer, etc., each with **one signature ability and one clear counter** the player can learn.
- Region-appropriate variants (Ashlands, tower tiers, second dungeon) from the same base meshes via Section 11.1.
- Multi-foe fights keep the side alert icon behaviour (frozen decision).

### 11.3 Player builds and imagery
- Weapon classes (melee, bow/crossbow, staff/focus), gear sets, runes, passives. **Equipment changes are visibly prominent** (modular outfits and weapon sockets; you asked for this earlier).
- Per-weapon-class fight animation sets from the P2 library.

### 11.4 Background lane starts here
Lane N (Network Architect, Fable) writes `docs/SERVER_DESIGN.md` for DP3. No implementation until DP3.

**Gate G3:** Visual Critic on the enemy line-up shot (all tiers side by side) and on a multi-foe fight; perf gate with the maximum enemy count on screen.

---

## 12. Phase 4 — World and content (Wave 3/4)

| Task | Notes |
|---|---|
| 4.1 Tower navigation | Forks, **locked doors with keys**, the **Chandler vendor**, **fast travel** (waystones plus a tower map). Frozen: tiers are tiers of the map, not just bosses |
| 4.2 Skills | **Thieving, Runecraft, Farming.** Runecraft links to rune tracing; Farming links to base plots in P7. Housing is handled as personal plots inside P7 |
| 4.3 Second dungeon | New biome kit built with the P1 rules; theme chosen by Art Director with 2 options for the user |
| 4.4 World-building diversity | A region bible: colour script, ambient audio, NPC roster with Fable-written dialogue and quest hooks; regional enemy/skill ties |
| 4.5 Systems rebalance | After the speed increase from P2 |

**Gate G4:** a playthrough route (tier 1 → key door → Chandler → fast travel → dungeon 2) completes on phone; Visual Critic on each new region's Golden Shot.

---

## 13. Phase 5 — Casino (Wave 4)

**Design principle:** all game logic lives in a pure, deterministic module `casino_core/` with **no scene dependencies**, injectable RNG, and unit tests. It runs offline today, and later on the authoritative server (DP3) unchanged. Chips are **in-game gold only**.

| Task | Notes |
|---|---|
| 5.1 `casino_core` (Casino Architect, Fable) | Shoe/deck, shuffle with injectable RNG, 7-card hand evaluator (tested against known hand vectors), blackjack rules (dealer stands on 17, 3:2 blackjack, split/double/insurance), roulette payouts, chip ledger, side pots, event log. Property tests for conservation of chips |
| 5.2 Casino venue | Art Director designs a warm, gold, lamplit contrast to the cold tower; Env Artist builds from the kits; seated camera rig per seat |
| 5.3 **Blackjack** | Dealer vs up to 6 seats; offline with bots filling seats |
| 5.4 **Roulette** | Wheel and ball *choreographed*: the result is decided in `casino_core`, the animation lands on it; touch-first betting layout; chip stacking |
| 5.5 **Poker (6-max Texas Hold'em)** | Up to 6 characters per table. **Live dealer** (shared humanoid rig): shuffle, deal, burn, flop/turn/river, chip push, barks and gestures. **Bot players** with distinct styles (tight, loose, bluffer, calling station) fill seats offline; later, online humans take seats. Immersive: seat camera, ambient audio, emotes, tells, chip sounds, hand history, action timers, reconnect |
| 5.6 Table UI | Two-thumb layout, bet slider with presets, one-tap fold/check/call, readable on a phone at arm's length |
| 5.7 Fairness | When online, the server holds the deck and sends each client only its own cards (Casino Architect + Network Architect) |

**Gate G5:** `casino_core` tests green; one full poker hand cycle with 5 bots plays correctly on phone; Visual Critic on the table shot; perf gate at a full table.

---

## 14. Phase 6 — Online foundation (Wave 4/5)

Starts after DP3. Prerequisite for clans and online poker.

- Own relay/server (replacing reliance on public relays), account/identity minimal, persistence for world state.
- **Chat, parties, trading, shared foes and resources.**
- **Anti-cheat as authority:** server validates movement speed, damage, drops, trades and casino actions; clients are untrusted. Rate limits and sanity checks.
- Reconnect/resume; graceful degradation to offline.
- Test with scripted bot clients before any human tests it.

**Gate G6:** soak test (bots) passes; the Adversarial Reviewer attempts exploits against the trade and casino paths and reports; user tests on phone.

---

## 15. Phase 7 — Factions, clan land and bases (Wave 5)

Lives in the Ashlands open-PvP zone (frozen decision). Needs P6 persistence.

- **Clans:** roster, ranks, invites, clan chat, colours and banner (builds on P6 chat).
- **Land:** the Ashlands divided into claimable holdings. Claiming needs a craftable/purchasable banner stone; upkeep prevents land hoarding; contested claims resolve by siege rules (DP4).
- **Base progression in one place:** Camp → Outpost → Keep → Citadel. Amenities unlock as the base grows: healer shrine, forge, market stall and vendors, Runecraft altar, Farming plots, training dummies, a fast-travel waystone, personal house plots (this is **Housing**), a clan stash (check against "no bank").
- **Fights:** siege windows, defender advantages, and respawn/recovery rules that fit "live duels only, no shades".
- **Visuals:** each tier is a visible upgrade (new silhouettes, banners, lights). Art Director defines the base kit; Visual Critic scores the Clan Base Golden Shot.
- Offline-owner protection and anti-grief rules per DP4.

**Gate G7:** two phones plus bot clients complete claim → build → siege → resolve; Adversarial Reviewer attempts claim/duplication exploits.

---

## 16. Phase 8 — Hardening and polish (Wave 6)

Perf pass on the worst Golden Shots; audio pass (royalty-free or CC0 only, logged); tutorial and onboarding; `CREDITS.md` screen; accessibility toggles; save/resume robustness; final licence audit of `ASSETS.md` against the shipped build; release checklist.

---

## 17. Appendix A — Wave sequencing

| Wave | Phases | Active lanes (max 3) |
|---|---|---|
| 0 | P0 | Recon, stability, tooling |
| 1 | P1 | Art Director → Technical Artist → Env Artist |
| 2 | P2 | Animation Lead, Combat Designer, Gameplay Eng |
| 3 | P3 + P4 + start of Lane N | Combat Designer / Systems Eng / Network Architect (design only) |
| 4 | P5 + P6 | Casino Architect / Network Eng / Casino Eng |
| 5 | P7 | Network Eng / Technical Artist / UI Eng |
| 6 | P8 | QA and Reviewer lanes |

Waves can slip, but G1 gates all content scaling and DP3 gates all online work.

## 18. Appendix B — First 10 actions for the orchestrator

1. Read the repo's `PLAN.md`, `.gitignore`, project settings; confirm `.superpowers/sdd/` and `assets_src/` are gitignored.
2. Launch two Explore agents for `RECON.md` (Section 3, task 0.1). Do not read the whole repo yourself.
3. Post the **Wave 0 Card** to the user and wait for OK.
4. Run tasks 0.2–0.5; run the lanes in parallel only where files don't overlap.
5. Materialise `.claude/agents/*.md` (task 0.6), e.g.:
```
---
name: technical-artist
description: Shaders, materials, lighting and perf-for-art for Ashgrave. Use for terrain, walls, enemy skin system.
model: claude-fable-5-2
tools: Read, Write, Edit, Bash, Glob, Grep
---
You work to docs/ART_BIBLE.md and docs/PERF_BUDGET.md. Verify every feature in the web build before relying on it. Return ≤250 words plus paths.
```
6. Build 11 deployed; tell the user the two phone checks.
7. Draft `PERF_BUDGET.md` from measured numbers.
8. Brief the Art Director for the Art Bible and three test scenes.
9. Post the **Wave 1 Card**; prepare DP1, DP2, DP6.
10. Write the ledger handoff.

## 19. Appendix C — Evidence behind the key constraints
- Godot docs: single-threaded web export is the default; it works on macOS and iOS; GitHub Pages cannot set the cross-origin isolation headers threaded builds need. https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html
- Godot forum: iOS reloads at roughly 300 MB runtime memory; all iOS browsers are WebKit; Basis Universal textures fixed one VRAM-heavy web game; textures above 4096 fail on mobile web. https://forum.godotengine.org/t/web-export-to-ios-suddenly-crashing-after-working-for-ages/120627 · https://forum.godotengine.org/t/game-crashes-randomly-on-ios-devices-html-export/114043 · https://forum.godotengine.org/t/trying-to-test-the-game-on-the-browser-gives-me-an-error/77607
- Godot forum: iOS audio crash in 4.5 dev5, reported fixed in a later beta; memory out-of-bounds report moving from 4.5.1 to 4.6 on web. https://forum.godotengine.org/t/sounds-crash-my-web-game-on-mobile-browser-godot-4-5-dev5-html-export-on-itch/113237 · https://forum.godotengine.org/t/memory-access-out-of-bounds-on-web-export-migrating-4-5-1-4-6/131968
- WebKit bug: reload loops under memory pressure with texture-heavy WebGL pages. https://bugs.webkit.org/show_bug.cgi?id=300782
- Mixamo, Quaternius UAL, KayKit, CC0 texture sources: https://app.cinevva.com/guides/free-character-animations-rigging · https://kaylousberg.itch.io/kaykit-character-animations · https://kaylousberg.itch.io/kaykit-adventurers · https://docs.polyhaven.com/en/faq · https://app.cinevva.com/guides/free-textures-hdris-materials
