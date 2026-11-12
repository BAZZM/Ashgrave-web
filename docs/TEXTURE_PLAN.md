# Ashgrave texture packs: implementation plan v2 (runs alongside docs/ORCHESTRATOR.md)

Status: draft for the user's approval. v2.1, 12 Nov 21:30, written against the user's local `dev` branch (90e3821). Fits ORCHESTRATOR P1 (1.3 terrain, 1.4 walls, 1.6 hero and enemy texturing) and the G1 look gate. It does not create a second pipeline.

**Changes since v1:** (1) user confirmed AI-generated textures are fine; (2) Wildlands pack added; (3) v2.1: the pack files are now in the repo's `assets_src/` and the plan follows the repo's existing asset pipeline (`tools/import_assets.py`, `docs/ASSET_PIPELINE.md`), which I had not seen when I wrote v2.

## 1. The two packs

Both are AI-generated, albedo only (no normal, roughness or AO maps), with baked lighting in places. Masters are the 1254px files; the 1024px files are the same images resized. Seam check = edge mismatch compared with a typical interior pixel.

**Pack 1, Knight RPG (castle and armour)**

| Tex | Use | Tiling |
|---|---|---|
| 01 steel plate, 02 gambeson | armour overlays | clean |
| 03 chainmail | armour overlay | framed panel: crop to a tile |
| 04 castle stone, 06 planks | walls, wood | visible seams: fix |
| 05 cobblestone | paved roads | clean |
| 07 forest floor, 08 heraldic cloth | forest/ash ground, banners | slight seams |

**Pack 2, Wildlands (nature)**

| Tex | Use | Tiling |
|---|---|---|
| 01 lush grass, 02 wild meadow | main grass ground | clean |
| 03 grassy dirt trail | dirt roads and worn patches | mild seam; it has a directional path in it, so use as patches, not as an oriented road |
| 04 muddy wetland | marsh and shorelines | mild seam |
| 05 shallow riverbed, 06 deep lake | water surface layers | clean (very clean) |
| 07 deciduous bark, 08 pine bark | trunks | visible seams: fix before wrapping on trunks |
| 09 broadleaf card, 10 evergreen card | canopy cards | true alpha (transparent background), no tiling needed |

**Not received:** the pack's bonus folder (three `.gdshader` files and two ripple normal maps). Only the README, index, preview and images reached me. I'd write the shaders in code in the repo's style anyway (they are untested starter code). Send the normal maps if you want them used.

## 2. Repo facts that shape the plan

- 3D game, Godot 4.4.1 web, single-threaded, Compatibility renderer. Almost all art is built in code: trees are lathe meshes (`oak`, `pine`, `dead`) scattered by MultiMesh with a flat leaf colour; ground is one vertex-coloured material (`Kit.mat("ground", ..., tinted)`); water is one flat translucent `PlaneMesh` per nearby chunk; walls are `BoxMesh`; characters use `StandardMaterial3D`/cloth shaders in `placeholder_visual.gd`.
- **Import pipeline exists (Phase 0 done).** Sources go in `assets_src/<path>` (git-ignored); `python3 tools/import_assets.py` imports them with headless Godot 4.4.1 into `game/assets/<path>.import` plus `game/.godot/imported/*.ctex`, loaded in code as `res://assets/<path>`. Proven on the web build with a lossless PNG (RGB8, mipmaps on). **VRAM compression and Basis on web are listed there as unproven.** The importer imports every PNG under `assets_src/`, so only prepped, ready-to-ship textures may go in the import folders.
- Shaders are strings in code (`Shader.new()`); no `class_name`, use `preload`.
- `.gitignore` already covers `assets_src/` and `.superpowers/`. `docs/ASSETS.md` has both packs as PLANNED rows (generating tool still not recorded); `docs/DECISIONS.md` records "both packs, applied only after the owner approves look-test screenshots".

**Branches.** Owner decision 12 Nov: the earlier Wave 1 lanes are stopped; `dev` (now past Build 11) is the base and the rest folds into the orchestrator phases. Branch texture lanes from `dev`.

## 2b. Where the files live (done 12 Nov)

```
assets_src/                          git-ignored, imported by tools/import_assets.py
  README.md                          rules for this folder
  _packs/                            originals as delivered, zipped so the importer skips them
    knight_rpg_texture_starter_pack.zip   (8 textures at 1254 and 1024 px, PREVIEW, README, index)
    wildlands_environment_pack.zip        (10 textures, 1254 and 1024 px, Shader_Extras, PREVIEW, README, index)
  textures/                          empty import targets -> res://assets/textures/<group>/
    ground  water  bark  foliage  walls  wood  armour  cloth
docs/
  TEXTURE_PLAN.md                    this file
  textures/knight_rpg/               pack README.txt + TEXTURE_INDEX.csv (committed, small)
  textures/wildlands/                pack README.txt + ASSET_INDEX.csv
```

Prepped textures (T1) go in `assets_src/textures/<group>/`, never the full-size masters.

## 3. Budget (ORCHESTRATOR section 4 governs)

Rules there: tiling textures 512px, hero atlases up to 1024px, steady state about 200 MB, +10% needs an offset. Uncompressed RGBA with mips is 1.4 MB at 512px and 0.35 MB at 256px.

| Group | Textures and size | MB uncompressed |
|---|---|---|
| Pack 1 environment | 04, 06, 05, 07 at 512 | 5.6 |
| Pack 1 armour, cloth | 01, 02, 03 at 256; 08 at 512 | 2.5 |
| Grass and trail | Wildlands 01, 02, 03 at 512 | 4.2 |
| Mud | Wildlands 04 at 512 | 1.4 |
| Water | 06 at 512, 05 at 256 | 1.8 |
| Bark | 07, 08 at 256 | 0.7 |
| Foliage cards | 09, 10 at 512 with alpha | 2.8 |
| **Total** | | **about 19 MB, 9.5% of the target; about 5 MB once compressed** |

That sits right at the 10% trigger, so: compress through Godot headless before shipping all of it (T6), roll out in stages (ground and water first, then walls, then trees, then armour) and record memory at each stage, and use the cut list if over (drop mud and tint grass instead; 256px for the trail; share one grass layer). If the iPhone reload gets worse at any stage, back that stage out.

## 4. Where each texture goes

**Ground (Wildlands 01, 02, 03, 04; Pack 1 05, 07), P1.3.** One terrain shader sampling world-space (no mesh UV dependency). Grass biomes: 01 with 02 noise-mixed in, plus a second larger-scale sample to break repetition. Roads: 03 as worn-dirt patches along dirt roads (road data exists in `land.gd`), Pack 1 05 cobble on paved village and tower paths. Marsh and shorelines: 04. Ashlands: 07 and 04 darkened and tinted, as there is no ash texture in either pack. Vertex colour (biome colour) becomes a tint times the texture, so biomes keep their palette, and per-vertex weights pick layers. Texture array in the web build if it works in Compatibility (to be verified; fallback is three samplers with layers chosen per biome). Cap at three to four reads per fragment.

**Water, P1.3/1.5.** Replace the flat translucent plane with a shader: two scrolling samples of Wildlands 06 for deep water, Wildlands 05 near shores, blended by shore distance baked into the vertices of a lightly subdivided plane (from `Land.lake_dist`/`river_dist`, which already exist). No depth or refraction texture, since that is not reliable on the web Compatibility renderer. Edge fade by alpha; keep `Land.WATER_Y`.

**Trees (07, 08 bark; 09, 10 foliage), P1.3/P3.** Bark on trunk and dead-tree meshes (triplanar, tinted dark for dead trees), 07 on oaks and 08 on pines. Canopy options, to be decided by the look test (T3) and a phone memory reading:
- A: cards only (6 to 10 cutout cards per tree). Best silhouette, highest fill cost.
- B: keep the lathe canopy and texture it with the leaf image via triplanar. No overdraw, softer silhouette.
- **C, recommended: hybrid.** Lathe canopy as the core, plus about 4 cards for a ragged edge, MultiMesh, alpha-scissor, near-distance only.
Prep must dilate colour under transparent pixels to avoid white halos in mipmaps. Optional wind sway in the vertex shader, near trees only.

**Walls and floors (Pack 1 04, 06), P1.4.** Triplanar stone for tower walls, ruins, houses and watchtower; planks for house trim, stalls, fences and docks. No UV changes to the existing box meshes. Per-tier tint from `tiers.gd` themes.

**Armour and cloth (Pack 1 01, 02, 03), P1.6/P3.** No per-gear textures. Palette colour per piece plus shared tiling detail overlays (plate, leather weave, chain, with chain cropped to a tile) in the shader, plus roughness/metallic by material class.

**Banners (Pack 1 08).** Tower and village banners now, clan banners in P7 (tinted per clan).

**Gaps neither pack fills:** grass blades and flower cards, reeds, an ash/soot ground, rock face textures beyond 04 and 05. These belong on the orchestrator's CC0 shopping list (ambientCG, Poly Haven, Kenney).

**Cohesion risk (Art Director, DP1).** Photographic textures next to flat low-poly trees and characters can look collaged. Mitigation: tint and grade all textures to the biome palette, share one lighting and fog recipe, and make the look test show a grass, tree, wall and character shot together. Go/no-go is at DP1.

## 5. Work packages

New files and docs only until the Smoothness situation is confirmed, so nothing collides.

| # | Task | Model | Files | Depends on |
|---|---|---|---|---|
| T0 | **Masters in `assets_src/_packs/` (done).** Remaining: update the two `ASSETS.md` rows (AI-generated, owner confirmed 12 Nov; generating tool still to record) | Haiku / shell | `docs/ASSETS.md` | owner names the tool |
| T1 | Prep script in `tools/`: fix seams (04, 06, bark 07, 08, mild on 03, 04); crop chain to a tile; soften baked crinkle on stone and cobble; dilate foliage edges and keep alpha coverage; resize to 512/256; optional procedural ripple normals; output lossless masters plus game copies | Sonnet | `tools/` (new), `assets_src/` | T0 |
| T2 | `tex_kit.gd`: shared shader strings and cached materials (terrain blend, water, triplanar stone/wood/bark, foliage cutout, detail overlay, banner); loads `res://assets/textures/...` (imported), mipmaps on, repeat on | Sonnet (Opus if the terrain/water shader fights Compatibility) | `game/scripts/tex_kit.gd` (new), `assets_src/textures/` then `tools/import_assets.py` | T1 |
| T3 | Look test (`?texdemo=1`): grass at a grazing angle, trail and mud blend, water, tree variants A/B/C, wall close-up, armour mannequin, banner; screenshots plus `perf.gd` readout | Sonnet | `tools/`, new scene code | T2 |
| T4 | Visual Critic scores T3 against the rubric; fix loop capped at 2 | Fable, fresh context | none | T3 |
| T5a | Apply terrain and water | Sonnet (Opus if it touches chunk streaming) | `overworld_terrain.gd`, `land.gd` colours, `overworld_kit.gd` | `dev` base, T4 |
| T5b | Apply walls, houses, wood | Sonnet | `overworld_places.gd`, `world.gd`, `tiers.gd` | T5a measured |
| T5c | Apply trees (bark, canopy variant chosen in T4) | Sonnet | `overworld_terrain.gd` scatter | T5a measured |
| T5d | Apply armour and banners | Sonnet | `placeholder_visual.gd` | ledger shows no lane on that file |
| T6 | Compress: try VRAM-compressed or Basis Universal in the `.import` settings (unproven on web per `docs/ASSET_PIPELINE.md`); re-measure on the phone | Technical Artist (Fable) + QA | `.import` files | T5a measured |
| T7 | Gates after each T5 stage: build, perf, visual, licence, review | per ORCHESTRATOR section 5 | | |

T0 to T4 touch only new files and docs, so they can start now.

## 6. Collision rules with the existing plans

- Branch from `dev`, never `main`.
- Smoothness A (terrain) is merged, so T5a is not blocked by it. `placeholder_visual.gd` (armour, T5d) was Smoothness B and Battle territory: check the ledger for what is in flight before touching it.
- `world.gd`, `world_hud.gd`, `overworld_kit.gd` are shared: agree each change with the orchestrator first.
- One orchestrator over the same files. The orchestrator's reconciliation step asks the user about Wave 1 lanes; the answer is in section 2.
- Only the orchestrator commits a build (`tools/build.py` renames the pack and edits `index.html`). Lanes build to test and leave them uncommitted.
- Run `python3 tools/members.py` and `node tools/check.js` before reporting, per `CLAUDE.md`.

## 7. Gates and acceptance

- **Perf:** steady-state memory change under 10% per stage; no extra draw calls beyond a small agreed number; FPS at the three worst Golden Shots recorded; total texture memory logged against section 3.
- **Visual:** Golden Shots 5 (grazing terrain) and 6 (wall close-up) improve on today's flat colour; average at least 4.0 and nothing below 3. Add water and tree shots.
- **Licence:** every texture has an `ASSETS.md` row.
- **User phone check:** 10 minutes with the overlay on after each stage, compared with the build before it.

## 8. Decisions

1. Provenance: **resolved.** The user is happy with AI-generated textures (12 Nov). Record in `DECISIONS.md`.
2. Wave 1 lanes: **resolved** (stopped; `dev` is the base).
3. Look test (T1 to T4) starts now that the files are in place. Per DECISIONS, nothing is applied to the game until the owner approves its screenshots.
4. DP1 art direction: option A (stylised forms with real surface texture) is what these textures serve, subject to the cohesion risk in section 4.
5. Canopy variant (A, B or C) chosen after T3/T4 from screenshots and a phone memory reading.

## 9. Not verified

- VRAM-compressed or Basis textures on the web build, and `Texture2DArray` under the Compatibility renderer: T3 verifies in a real web build before anything depends on them.
- Cost of the terrain and water shaders on an iPhone: only the phone can confirm it.
- No Godot editor ran for this plan, so it is design, not tested code.
