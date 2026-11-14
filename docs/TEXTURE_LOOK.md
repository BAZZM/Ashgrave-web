# Texture look test (lane G2)

Nothing in normal play loads a texture. The look test is behind a debug argument; `game/scripts/tex_kit.gd` holds the shared materials, `tex_looktest.gd` the scene.

**Run:** `python3 tools/build.py`, then `node tools/tex_shots.js [--treatments=flat,grain,source] [--cams=v1,w2] [--single] [--scale=2]`. Pictures land in `/home/claude/screens/g2/<treatment>/NN-name.png` (844x390, device scale 2), the memory lines in `mem.txt`, and the flat | grain | source sheets in `compare/`. One client: `node tools/check.js --probe "--looktest=tex --treatment=grain --ltcam=v6b-duel-armour --ltmem"`. Textures: `python3 tools/pack_textures.py`, then `python3 tools/import_assets.py`.

## The treatments
- **FLAT**: today's flat and vertex colour; the control, and the fallback whenever `Run.quality_allows("textures")` is false (nothing is loaded then).
- **GRAIN**: luminance-only grain, `mix(dark, light, g)`, light = tint x (1+d), dark = tint x (1-d) mixed 10% to fog, d+0.10 if tint V < 0.25; grain stretched 5th-95th percentile to 0.10-0.90; macro noise +-8%, 37 m. Six channel-packed textures. d: grass 0.18, forest 0.20, mud 0.20, trail 0.28, water 0.15, stone 0.28, cobble 0.22, wood and bark 0.25, leaf 0.25, armour 0.30 hero / 0.20 enemy.
- **SOURCE**: the colour files, graded: desaturate, hue against the texture's own mean, brightness gain softened to 0.55 of the texture's contrast, blended by k toward the palette tint. Desaturation / k: grass, forest 0.30 / 0.75 (0.25 forest), trail and mud 0.25 / 0.80, water 0.30 / 0.80, stone 0.20, bark 0.25, leaf 0.30, steel and chain 0.10, gambeson 0.25 (all k 0.80), cloth 0.10 / 0.25.

Tile, world units per repeat: ground 4 (second rotated sample 9.2 in GRAIN; SOURCE uses a sine warp instead), water 4 and 6.5, stone and cobble 4, planks 2, bark 2, leaf cards 1.6, armour 0.5, banner once (cropped, not tiled).

## Memory (844x390 page; the page caps the pixel ratio at 2, so a ratio-3 request measured the same)
| | Texture MB | Video MB | Added vs flat | Pack on disk | Draws (duel / Greywood) |
|---|---|---|---|---|---|
| FLAT | 27.17 | 37.17 | 0 | 0 | 200 / 38 |
| GRAIN lossless | 32.17 | 42.20 | +5.0 | +4.3 MB | 200 / 38 |
| SOURCE lossless | 39.92 | 49.95 | +12.75 | +7.8 MB | 200 / 38 |
| GRAIN S3TC | 28.42 | 38.45 | +1.25 | +1.1 MB | 200 / 38 |
| SOURCE S3TC | 29.63 | 39.66 | +2.46 | +3.0 MB | 200 / 38 |

Budget: 16 MB of textures (`docs/PERF_BUDGET.md`). Every row fits in this scene; SOURCE lossless takes 80% of it. Whole game: land has all of it resident (GRAIN 5.25 MB, SOURCE about 12.8); tower needs stone, planks, cobble, armour (GRAIN 3.15 MB, SOURCE 5.3 plus the banner 1.4). Committed lossless; pack 0.73 to 12.9 MB. Both compressed forms (S3TC and ETC2 variants, 4.1 MB each) loaded in headless Chromium; compression was not committed (iPhone unproven, channel packs suffer in DXT).

## Substituted
Texture arrays not used (two packs read twice instead). `source_color` dropped: Compatibility hands texels over undecoded, so means are raw. No tangents: water normals are perturbed in view space by hand. Instance uniforms avoided (a material per colour). Ashlands: forest-floor and mud grain under the Ashlands tint; reads as dark gritty soil, without cracks.

## Weaknesses
- GRAIN: soft and uniform at distance; walls and trees lose moss and colour; ripple normals are regular stripes; banner shows the grain only.
- SOURCE: busier, high-frequency grass; single sample per layer so repeats may show; trail reads pink; moss and clover stay; only four ground layers (meadow unused); extra 7.7 MB.
- Both: fighter / ground luminance (linear) flat 1.57, GRAIN 1.53 (armour overlay 1.47), SOURCE 1.58 (1.51); target 1.5. Texel density agrees between ground and walls (4 m tile). Banner crop and Greywood camera are unpolished. iPhone unverified.

## Trade-off
GRAIN costs 5 MB, matches the palette and the Art Bible, and gives subtle surface; it throws away the owner's colour. SOURCE costs 12.8 MB (about 2.5 MB compressed), keeps recognisable textures and gives the strongest surface detail; it looks busier and sits closer to the photographic risk.
