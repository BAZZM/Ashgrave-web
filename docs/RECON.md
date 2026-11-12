# Recon

What exists in the repo as of `dev` 725c11a (12 Nov 2026). Read this instead of
re-exploring. Part A is code and engine (Haiku recon), part B is assets and
licences (Sonnet recon). "Not determined" means nobody checked; do not assume.

## Headlines

- No image textures and no imported models: all art is meshes and materials
  built in code. Asset memory is under 1.5 MB, so assets are not what is
  pushing an iPhone tab toward its limit. Suspects are the 43.7 MB engine,
  code-built meshes and node counts. The crash breadcrumbs measure this.
- Characters have no skeleton. Each is dozens of separate MeshInstance3D parts
  posed in code with two-bone IK. Phase 2's shared rig replaces this outright.
- A player downloads 44.65 MB, of which 43.7 MB is the stock engine.
- Licence paperwork is missing for the font, the nine sounds and the engine
  (part B). Nothing third-party was ever committed raw.

# Part A: code and engine

## 1. Engine and renderer
- Godot 4.4.1 (`project.godot:10`). Rendering method is set to "mobile"
  (`project.godot:32`); what the web build actually runs with is not determined
  from the repo (web exports normally use Compatibility) and task 0.3 confirms it.
- Viewport 1280x720, stretch `canvas_items`, aspect `expand`
  (`project.godot:20-23`), `window/handheld/orientation=4` (meaning not checked).
- Portrait shows a "Turn your phone sideways" overlay (`index.html:103, 144-145`):
  the game is landscape-only.

## 2. Web export
- Threads off (`index.html:151`). Stock single-threaded engine.
- `index.html:121-130` wraps `fetch`: a request for `index.wasm` fetches
  `part0-2.wasm` and joins them. `index.html:132` maps `index.pck` to
  `game_<hash>.wasm`. `GODOT_CONFIG` at `index.html:150`: `args []`,
  `canvasResizePolicy 2`, no service worker.
- Download: engine parts 43,699,190 bytes; pack 597,997; `index.js` 317,142;
  the rest under 40 KB. Total 44.65 MB.

## 3. Scenes
- 3D with 2D Control HUDs drawn in `_draw()`.
- `overworld.tscn` (main scene; `overworld.gd`, class `Overworld`),
  `duel.tscn` (`duel.gd`, class `Duel`), `world.tscn` (`world.gd`, class
  `World`, the tower), `placeholder_fighter.tscn` (root script not determined).
  Only compiled `.scn` files exist; node trees not determined.
- Autoloads: `Online` (`online.gd`), `Perf` (`perf.gd`).
- HUDs: `hud.gd` (duel), `world_hud.gd` (land and tower).

## 4. Character construction
- `PlaceholderVisual` (`placeholder_visual.gd`, extends `FighterVisual`) builds
  the body in `_build()` (111-336) and the sword in `_build_weapon()` (339).
- Every part is its own MeshInstance3D (`_part` 95-103, `_free_part` 105): 52
  call sites in `_build`, 7 in `_build_weapon`, several inside loops. Instances
  per character not counted.
- Limbs placed each frame: `_place` (397), two-bone IK `_solve` (422), `_bend`
  (409). Poses tween via `_pose` (484-497); walk and pace via `set_walk` /
  `set_pace` (607, 612). Hit flash is a `material_overlay` (620-625).
- `AnimPackVisual` (AnimationPlayer based) exists but no script instantiates it.
- `mesh_kit.gd` builds meshes: lathe 56, tube 13, limb 65, blade 69, shield 124,
  horn 154, merge 169.

## 5. Combat input
- Touch: `hud.gd:106-136` then `_on_press` (139-185). Buttons: dodge L/R, block
  (held), super, flask, spell, ranged, pause (rects 65-80). A press that misses
  every button starts a swipe.
- A swipe fires `duel.input_swipe(v)` per 60 px of drag (`SWIPE_MIN`, `hud.gd:4`).
- `duel.gd:474 input_swipe` routes by enemy state: FINISHER finishes, OPEN
  executes or slashes, WINDUP parries on matching direction and timing, else
  whiffs, IDLE/RECOVER starts a swing. PvP sends the swipe over the relay.
- Ranged: `input_ranged` (`duel.gd:705`), `hunters_bow` branch only. Spell:
  `input_spell` (735), needs a `spell_id` and 100 mana. Both are single buttons;
  no aiming, no projectiles in flight.

## 6. World movement
- `overworld_hero.gd`: walk 5, run 8.5 (stick at 0.8 or more, builds in 0.5 s),
  road run 10.2 units/s; agility adds 0.35% per level.
- Stick: `world_hud.gd:138-145`, touch must start in the left 45% of the screen.
- Camera: follow, distance 6.6, height 3.3, FOV 60, far 260.

## 7. Materials, lights, anti-aliasing
- Almost all `StandardMaterial3D` (`overworld_kit.gd:7-35`). One custom shader:
  cloth sway, inline at `placeholder_visual.gd:84-93`.
- Sun `DirectionalLight3D` with shadows, max distance 45
  (`overworld_sky.gd:35-37`); OmniLights for beacons, torches and the hero.
- `ProceduralSkyMaterial`, Filmic tonemap, sky-driven ambient, fog 0.0045
  (0.012 in rain, 0.035 in the arena). Glow off on web.
- On web `run.gd:38-40` turns MSAA off, sets `scaling_3d_scale` to
  `clamp(640 / window height, 0.45, 1.0)` and the shadow atlas to 1024.
  Whether window height is CSS or device pixels is not determined.

## 8. Perf readout (`perf.gd`)
- Off unless `?perf=1` or `--perf`. Other flags: `--perflog`, `--perfdump`,
  `--worlddump`, `--worldlive`, `--terrainbench`.
- Measures fps, average/p95/worst frame over 5 s, stutter counts (over 50 ms and
  100 ms in 60 s), draw calls, objects, primitives, nodes. `Perf.mark(label, usec)`
  prints anything 8 ms or longer.

## 9. Saves and online
- Save: localStorage key `ashgrave_save_v1`, `SAVE_VERSION 3`, `BUILD 10`
  (`run.gd`). The whole dictionary (45 top-level keys) is written as JSON every
  5 s and on events. Size not determined.
- Online: world `ashgrave/w1`, three public WSS MQTT relays joined at once and
  merged. Topics `p/<id>` (state every 0.3 s moving, 1.5 s idle) and `c/<id>`
  (direct messages). Duel message kinds: `atk`, `res`, `pst`, `turn`, `ping`.
  Override with `?relay=`.

## 10. Status of the earlier plan's Wave 1 (from `git log dev`)
| Task | Status | Evidence |
|---|---|---|
| Combat Build 1 (feel, posture) | done on dev | 82c2ae1, fb3c72e |
| Fast travel | done on dev | 177b858, 55bf6ec |
| Smoothness A (terrain) | done on dev | 4bc2849, 0afc21b, 070bbc9 |
| Running and road bonus | done on dev | 057027c, 747cbd4 |
| Smoothness B (character mesh count, HUD redraw, remote easing) | not built; plan says "started" but no code commit | e810e11 is plan-only |
| Combat Build 2 and 3 | not started | |
| Quest system, visual polish, mount | not started | |

None of the above is on `main` yet.

# Part B: assets and licences


Repo: /home/claude/ashgrave, branch `dev` (read-only). Everything below is **measured** (parsed from the files or git) unless marked **estimated**.

Headline: there are NO image textures in the game. Shipped non-code assets are 9 sound samples, 1 font, 5 tiny scenes and the stock Godot splash (`index.png`). The 5 `.scn` files hold no texture references (checked by string scan). No `.ctex` files exist anywhere.

## Asset table

| Path | Type | Disk size | Details |
|---|---|---|---|
| game/.godot/imported/ambience.wav-*.sample | AudioStreamWAV, QOA-compressed | 107,470 B | 22,050 Hz, mono, 12.00 s, loop set in code |
| ...block.wav-*.sample | same | 5,738 B | 44,100 Hz mono 0.30 s |
| ...break.wav-*.sample | same | 16,442 B | 44.1k mono 0.90 s |
| ...clang.wav-*.sample | same | 12,890 B | 44.1k mono 0.70 s |
| ...finish.wav-*.sample | same | 28,930 B | 44.1k mono 1.60 s |
| ...hit.wav-*.sample | same | 4,858 B | 44.1k mono 0.25 s |
| ...hurt.wav-*.sample | same | 7,522 B | 44.1k mono 0.40 s |
| ...tell.wav-*.sample | same | 3,594 B | 44.1k mono 0.18 s |
| ...whoosh.wav-*.sample | same | 5,386 B | 44.1k mono 0.28 s |
| game/.godot/imported/cinzel-700.woff2-*.fontdata | FontFile (dynamic), embeds a woff2 | 16,054 B | Font name string "Cinzel" found inside; weight 700 from filename; no mipmaps or MSDF settings checked |
| game/.godot/exported/133200997/*.scn (5) | binary scenes | 3,723 B total | arena, duel, world, overworld, placeholder_fighter; script refs only |
| game/scenes/*.tscn.remap (5), game/audio/*.import (9), game/fonts/*.import | import metadata | ~2 KB | point at source files that are not in the repo |
| game/.godot/uid_cache.bin, global_script_class_cache.cfg, project.godot | engine data | ~5 KB | not art |
| index.png (repo root) | PNG 800x600 RGBA | 21,443 B | Stock Godot web splash (Godot logo, "Game engine"), viewed. Not game art. |

Sample rate and channels: mix_rate is stored only for ambience (22,050); the others omit it, so they are the engine default 44,100 Hz mono. The round durations (0.30, 0.90, 0.70...) confirm this. Durations come from the QOA header sample counts (measured).

Source files (`game/audio/*.wav`, `game/fonts/cinzel-700.woff2`) are absent from the working tree and from every commit. Only the imported forms exist, so the originals cannot be re-imported or re-encoded.

## Runtime-generated textures (all in code)

| Where | What | Size | Memory (estimated) |
|---|---|---|---|
| overworld.gd `build_map()` (land map, static, built once on first map open) | Image RGB8 to ImageTexture, no mipmaps | 110 x 115 (from Land.X_MAX 220, Z -262..200, 4 m per pixel) | 37,950 B; ~50 KB if the GPU stores RGBA |
| hud.gd | GradientTexture2D radial vignette | 128 x 128 | 65,536 B |
| hud.gd | GradientTexture2D edge flash | 64 x 64 | 16,384 B |
| world_hud.gd | GradientTexture2D vignette | 128 x 128 | 65,536 B |

Total about 0.19 MB if both HUDs are alive. No NoiseTexture or FastNoiseLite exists. `get_viewport().get_texture()` is used only by screenshot bots (not shipped play). Meshes and materials use no textures; the sky is ProceduralSkyMaterial (the radiance cubemap it creates is an engine buffer: **not determined**, not measured).

## Audio

`sfx.gd` loads files, it does not synthesise. For each name in NAMES it tries `res://audio/<n>.ogg` then `.wav` through `ResourceLoader`, and silently skips missing ones. Ambience is loaded as `res://audio/ambience.wav`, duplicated, and looped forward. A pool of AudioStreamPlayers (size `Tune.B1.sfx_pool`) plays the effects.

Format is QOA (format id 3), the Godot 4.3+ default for WAV import. As I understand the 4.4 engine, QOA streams stay compressed in memory and are decoded on the fly. **Estimated** in-memory audio: 189,560 B (sum of QOA payloads). Worst case if fully decoded to 16-bit PCM: 935,800 B. Whether the generation of the sounds is "generated" is not evidenced; see gaps.

## Licence evidence and gaps

Searched: `git grep` of licen/OFL/CC0/copyright/credit/public domain/freesound/kenney/opengameart/polyhaven across dev, main, gh-pages, lane and claude/* branches (excluding node_modules, wasm, js); commit messages; docs on all branches.

| Asset | Status |
|---|---|
| Cinzel font | **Stated in docs only**: `docs/ORCHESTRATOR.md` (main) says "Cinzel font (SIL OFL)". No licence text, copyright line, author or download URL in the repo. Source .woff2 not committed. |
| 9 sound samples | **Stated in docs only**: same line says "generated sound effects". No generator script, tool name, prompt, or source in repo or history. Effectively no evidence of origin or licence. |
| 5 scenes | Code-authored by the project, no third-party indication. No evidence either way beyond that. |
| index.png | No evidence in repo. Visually the stock Godot splash (engine-supplied). |
| Godot engine (part0-2.wasm, index.js, worklets) | CLAUDE.md says "stock Godot 4.4.1 web engine". No Godot/third-party licence notice in repo. Godot's own licence and bundled third-party notices are **no evidence found**. |

Gaps to list for the owner: no LICENSE file for the repo itself; `docs/ASSETS.md` and `CREDITS.md` (planned in ORCHESTRATOR.md) do not exist on any branch; no OFL text or font attribution; no record of how the sounds were made.

## Third-party files in history

All 59 commits on all branches inspected (`git rev-list --all --objects`). The only image/audio/font/model file ever committed in a normal path is `index.png`. No PNG packs, WAV/OGG/MP3, TTF/OTF/WOFF, FBX/GLB/GLTF, OBJ, blend or zip files exist in any commit. Every historic pack (17 distinct `game_*.wasm` blobs, including gh-pages `game_pck.wasm`) was parsed: none contains raw source assets; extensions are only gd/binary(compiled scripts)/scn/sample/fontdata/import/remap/cfg. The very first pack (134,912 B) has samples but no font; the font appears in later builds. CLAUDE.md says `assets_src/` is git-ignored (commit 14ee5b9), so local raw sources could exist outside the repo; **not determined**.

## Build size

Current pack `game_d39387b973.wasm` = 597,997 B (uncompressed Godot pack, 72 files, 591,945 B of content). Breakdown (measured): scripts .gd 372,404 B (63%), audio samples 192,830 B (33% by pack, including ~3 KB of padding-free metadata), font 16,054 B, scenes 3,723 B, config/import/other ~7 KB. The pack is small; the engine `part0-2.wasm` (43.7 MB across 3 files) dominates the download but is not an asset.

## Memory estimate (typical session)

Assumptions: both HUD vignettes alive, land map opened once, QOA kept compressed.

| Item | Estimate |
|---|---|
| Image textures (map + 3 gradients) | ~0.19 MB |
| Audio (compressed QOA) | ~0.19 MB (0.94 MB if decoded) |
| Font | 16 KB plus glyph-cache atlases (**not determined**) |
| Directional shadow atlas 1024x1024 (run.gd) | ~4 MB if 32-bit depth (estimated, engine buffer) |

Asset-driven memory is under 1.5 MB in all cases, so the 300 MB iOS limit is consumed by engine, meshes and render buffers, not by assets. Real heap use was not measured here.

## Open questions for the owner

1. How were the 9 sounds made (tool, prompt, licence of output)? Can the originals be provided?
2. Where was the Cinzel font downloaded from, and which version? Can the original .woff2/.ttf and OFL text be added with attribution?
3. Is there an original Godot project or `assets_src/` holding the raw WAV/font files?
4. Should a repo LICENSE and Godot third-party notices be added?
5. Was `index.png` intentionally the stock splash?
