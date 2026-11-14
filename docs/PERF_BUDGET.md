# Ashgrave memory budget

Measured 13-14 Nov 2026 in headless Chromium (software WebGL), Build 12 (`dev`) against
`lane/p-perf-soak`. Godot monitors are the engine's own counts; "renderer" is the
Chromium tab process (Pss). No iPhone was measured: see the last section.

## Baselines by phase (branch; 320x180 unless stated)

| Phase | wasm heap | textures | video (tex+buffers) | nodes | draws | primitives |
|---|---|---|---|---|---|---|
| Title, 844x390 at dpr 3 | 79.8 MB | 22.0 MB (dev 35.5) | 37.3 MB (dev 59.7) | 964 | 645 | 173k (dev 639k) |
| Title (village) | 79.8 | 2.4 | 17.7 (dev 25.5) | 964 | 566 | 156k (dev 565k) |
| Land, roaming | 79.8 (dev 95.8) | 3.2-5.0 | 18.5-22.1 | 690-1224 | 300-530 | 50-200k |
| HUD screens open | 79.8 | 5.7-6.5 | 21.5-23.6 | 1300-1340 | 710-1070 | |
| Tower tier | 79.8 | 2.4 | 18.1 | 268-310 | 685-784 | 250k |
| Pack duel, tier 2 | 79.8 | 3.8-4.5 | 19.6-21.6 | 343-393 | 730-910 | |

Renderer process: ~270 MB at the phone-shaped title, 310-345 MB through the soak.

## Findings, ranked

| # | What | Size | Status |
|---|---|---|---|
| 1 | Ambience: every land/tower scene load duplicated `ambience.wav`; the web engine decodes each new stream into a 4.6 MB stereo Float32 AudioBuffer and never frees it. Also caused the one wasm heap growth (80 -> 96 MB at the first tower load) | 4.6 MB per scene load, unbounded | fixed (`sfx.gd`) |
| 2 | Canvas at devicePixelRatio 3: 2532x1170 for an 844x390 page, though 3D renders at ~640 rows anyway | Godot textures +12.5 MB; browser drawing buffers +1.65 Mpx x 4-8 B each (estimated 7-20 MB) | fixed: page caps the ratio at 2 (`index.html`) |
| 3 | Figure spheres and tori at engine defaults (64x32, 4096 triangles each), one set per figure | ~0.1 MB per part per figure; 8.2 MB buffers in the village; 72% of primitives | fixed: shared, 24x12 and 32x12 (`placeholder_visual.gd`) |
| 4 | Fixed engine buffers: ~15 MB of buffer memory in every scene, even the tower | 15 MB | not fixed: engine pools (likely `rendering/gl_compatibility/item_buffer_size`); project.godot is not this lane's |
| 5 | GPU process (software GL) grows ~1.3 MB per scene load; Godot's texture and buffer counts stay flat | ~5 MB a cycle | not fixed, cause unknown; may be the software driver only |
| 6 | Save (1 KB JSON every 5 s) and crumbs (1.3 KB every 4 s) | negligible | none |

No leak in Godot objects: across 5 cycles nodes (1224 at the hearth), orphans (0),
resources (49), objects, textures and wasm heap are flat on dev and on the branch.

## perf-soak: dev versus branch

| | dev (Build 12) | branch |
|---|---|---|
| Phone title video memory | 59.7 MB: FAIL (ceiling 48) | 37.3 MB |
| Peak video memory, soak | 34.4 MB: FAIL (ceiling 30) | 23.6 MB |
| Peak wasm heap | 95.8 MB | 79.8 MB |
| JS heap growth per cycle | 33.2 MB: FAIL (limit 10) | 6.3 MB |
| Renderer growth per cycle | 46.6 MB: FAIL (limit 20) | 6.4 MB |
| Cycles completed | 3 (a lost duel outlasted the 400 s limit in cycle 4; dev renders 4x the primitives) | 5, 1519 game s |

Thresholds after the warm-up cycle, per cycle: wasm heap 2 MB, JS heap 10 MB, renderer
20 MB, nodes 25, orphans 0, textures 0.25 MB, objects 150, resources 2. Ceilings: wasm heap
128 MB, video 30 MB (320x180), phone title video 48 MB. The soak runs with sound on (as
after a first tap): with a suspended audio context no sound ends and the engine keeps a
copy of each, a headless artifact.

## Trade-offs for the quality setting (phone title, dpr capped at 2)

| Change | Saving |
|---|---|
| Sun shadows off | draws 645 -> 247, primitives 173k -> 84k; memory not visible in monitors (1024 atlas, est. 2-4 MB) |
| 3D scale x0.75 (640 -> 480 rows) | textures -2.7 MB, fill rate -44% |
| Pixel ratio cap 1 instead of 2 | textures 23.0 -> 9.0 MB plus browser buffers; HUD visibly soft |
| Sky radiance 64 instead of 256 | -0.65 MB; metal reflections duller |
| Shadow atlas 512 | not visible in monitors (est. 1.5-3 MB) |

## Quality levels (Build 15: `game/scripts/quality.gd`, `run.gd`)

Two levels, saved in the save's `settings` key (`quality`, plus `q_auto`, `q_auto_done`, `q_auto_n`, `q_mark`) and
mirrored in the small localStorage key `ashgrave_quality`, which `index.html` reads before the engine starts. A save
without the key loads as `full`; a level string this build does not know reads as `safe` (and stays stored untouched);
an older build ignores the key and drops it on its next save (the level then resets to full there). `?quality=safe|full`
on the page address (or `--quality=` as a user arg) sets the level for that session only, never saved, and also sets
the pixel-ratio cap from the first frame.

**What `safe` changes**: pixel-ratio cap 1.5 instead of 2 (the big one; applies from the first frame of the next
launch), and sun and moon shadows off with the shadow atlas released (size 0). The 3D render scale (`scale_k`) and
sky radiance (`radiance`) levers exist in `LEVELS` but are left at the full values: with them in, safe soaked with a
16 MB wasm heap step at cycle 5 (three runs, atlas 0 and 256); without them, and with the setters guarded to run only
on a change, the safe soak is flat at 79.8 MB through all five cycles. Cause of the step not isolated (it appeared with
those two levers on, at a heap growth boundary). The HUD is a little softer at 1.5 (text and bars stay legible in the captures); the owner accepted
that for not crashing. Not changed: draw distance and chunk radius (no memory saving measured). Switching in the
game: to Safe applies shadows, scale and radiance at once and the cap at the next launch; back to Full takes effect
at the next launch only (the button says so), and the stored level changes immediately.

Measured, headless software WebGL, 844x390 at dpr 3 (Godot monitors, video = textures + buffers, MB):

| Phase | full | safe, cap 2 | safe, cap 1.5 | safe, cap 1.0 |
|---|---|---|---|---|
| title | 39.1 | 40.0 (buffer reading 4 MB high, transient) | **30.2 (-8.9)** | 25.7 (-13.4) |
| land (road-wide shot) | 34.3 | 30.9 (-3.4) | **25.4 (-8.9)** | 20.9 (-13.4) |
| duel (HUD shot) | 35.8 | 26.5 (-9.3) | **23.6 (-12.2)** | 18.2 (-17.6) |

**Shipped safe** (cap 1.5, shadows off, atlas released) against full, video MB: phone title 37.3 -> 26.6 in the soak (-10.7), land shot 34.3 -> 23.1 (-11.2), duel shot 35.8 -> 21.3 (-14.4). Safe soak: heap 79.8 in every cycle, buffers 17.6 against 15.5 in full (+2 MB). The table above was measured with the scale and radiance levers on. Cap 1.5 saves at least 8.9 MB in every phase, so it is the one used (1.0 would save 4.5 MB more with a much softer
HUD). Textures alone: title 23.0 -> 14.1 at 1.5; land 18.4 -> 9.5; duel 24.3 -> 12.1. Buffers (15-16 MB land, 11.5 duel)
do not move with any lever; the shadow atlas does not show in the monitors either way. Levers alone at the title
at cap 2 (earlier run): shadows off draws 424 -> 247 and primitives 124k -> 84k, no memory; scale x0.75 -2.7 MB;
sky radiance 64 -0.65 MB. At 320x180 (the soak size) the levers save almost nothing (about 0.4 MB): the saving is the
phone-sized canvas. Wasm heap is the same in both (79.8 MB).

`check.js quality` (PERFLOG means at 320x180, `--perflog` also prints the levers read back from the engine):

| Phase | level | draws | primitives | scale | shadowed lights | radiance |
|---|---|---|---|---|---|---|
| land | full / safe | 379 / 224 | 113k / 55k | 1.00 / 0.75 | 1 / 0 | 256 / 64 |
| tower duel | full / safe | 235 / 133 | 56k / 19k | 1.00 / 0.75 | 1 / 0 | 256 / 64 |
| duel | full / safe | 228 / 114 | 55k / 27k | 1.00 / 0.75 | 1 / 0 | 256 / 64 |

`perf-soak` (320x180, 5 cycles, sound on). Full (merged build): passes, heap flat 79.8 MB, video peak 24.1 MB. Safe, run three
times: phone title video 28.8 MB (textures 13.5 against 22.0 in full); per-cycle video 18.1 MB (full 18.5), textures
2.6 (3.0), buffers 15.5 flat, nodes, objects, resources and orphans flat, renderer growth 5-9 MB per cycle, draws per
phase about 40% lower. The buffer rise seen in the first safe run (17.6 MB) did not persist as a trend: it appeared only
on the cycle where the wasm heap stepped. **Safe fails the soak's heap check** (twice with the shadow atlas released, once
at 256): one 16 MB wasm heap step (79.8 -> 95.8 MB) in cycle 5, at the screens phase, then flat; full never stepped.
Not a leak (a single step, under the 128 MB ceiling) and not the atlas size; cause unknown, open for a phone to show.

**Automatic rule** (`perf.gd`, `_auto_safe_check`): when a boot reports a foreground death or a stall that is young
enough to show the banner (not a background reload, a shared tab or an old death), and the previous such death is
no more than 30 minutes before it, and both came after the level last changed, and the level is `full`, and the
game has not already switched by itself, the level becomes `safe` (saved, marked automatic) and the banner says so
once (and once more in the caption line). A death during the engine load (crumb phase `boot`) never counts. Why: one unlucky crash does not count; two a day apart do not count; two in half an hour is a loop. In `safe`
nothing further happens but the crumb. The player choosing Full (or Safe) resets the mark and re-arms the rule.
Every crumb carries `q` (level in force), `qa` (set by the game), `qd` (deaths counted since the last change; 0 on a boot that reported none) and
`qn` (automatic switches); the restart banner prints `Quality:` and the death line `q= qa= qd= qn=`. The six-
character report code already uses all 30 bits (heap 9, video 7, mode 3, minutes 6, dpr 2, nodes 3), so it is
unchanged: the level is on the banner line next to it.

**Hooks for texture and model lanes**: ask `Run.quality_allows("textures")` / `("models")` / `("shadows")` before
loading, creating or showing anything heavy, and skip the `load()` itself when it is false (a gated resource must
never be loaded, not loaded and hidden). `Run.quality_level()` names the level; to add a level or switch, add a row
or a key to `Quality.LEVELS` (a missing key counts as allowed). `Run.quality_tune_light(light)` and
`Run.quality_tune_sky(sky)` apply the level to lights and skies built in code; `Run.quality_apply(viewport)`
re-applies the level to a running scene (it walks the tree once). A feature name a row does not list is refused in
safe (typos fail closed). Gated features are decided when a scene loads and never loaded or unloaded mid-scene; a lane
that wants to notice a change reads `Run.quality_rev` (counts level changes). Lane G3: the live game's ground and water use textures at Full only (`overworld_terrain.gd`, `tex_kit.gd` GRAIN; three lossless maps, 2.63 MB of the pack). Measured in the real overworld (844x390): texture memory +3.15 MB on land and in a duel, video +3.6 MB, about +8k primitives and +0.5 MB of buffers (water meshes); Safe adds nothing (`texheld=0` in PERFLOG, checked by `check.js quality`). Nothing in the live game uses models yet.

## Budget for textures and skinned characters

Estimated iPhone footprint today, after the fixes: wasm heap 80 MB, compiled 43.7 MB
engine 50-100 MB, JS 20-30 MB, audio ~10 MB, Godot video 37-45 MB, browser drawing
buffers 10-15 MB, driver and shaders 20 MB or more: roughly 230-300 MB. The fixes freed
about 25-40 MB at rest and stop ~4.6 MB per scene load. Spend no more than that:
**textures at most 16 MB of GPU memory** (on iOS WebGL, desktop-compressed imports fall
back to RGBA8: a 1024x1024 with mips is 5.3 MB, so three such, or ASTC if the import
supports it), and **skinned characters at most 10 MB GPU and 15 MB wasm heap**
(meshes, skins, animation clips). Large images decode in the wasm heap, which never
shrinks: keep any single texture at 1024 or below. Uncertainty is high (+/- 50 MB in
the estimate); ship behind the quality setting and read the crumbs.

## What only a real iPhone can settle

The kill threshold; WebKit's compiled-code size for the engine; whether ambience leaked
the same way in WebKit (same engine JS, so likely); drawing-buffer count; whether
finding 5 exists outside software GL; HUD sharpness at the 2x cap on the device. The
banner's report code (`node tools/crumb_test.js --decode CODE`) and the crumb's heap,
canvas, dpr, device memory and GPU fields are for this.
