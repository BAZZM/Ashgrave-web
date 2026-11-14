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
