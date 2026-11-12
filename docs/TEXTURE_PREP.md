# Texture prep (T1)

Turns the 18 pack textures and 2 ripple normal maps into seamless, power-of-two, game-ready PNGs. Images never enter the repo.

```
python3 tools/prep_textures.py --src /home/claude/assets_src/_masters \
  --out /home/claude/assets_src --sheets /home/claude/screens/texprep [--only NAME ...]
```

Adding a texture is one row in the `ROWS` table at the top of the script. Outputs: `<out>/textures/<group>/<name>.png`, lossless seam-fixed masters in `<out>/_prepared_masters/`, review sheets (`contact.png`, `tiled/<name>.png` 3x3, `before_after/<name>.png`) in `--sheets`. The run is deterministic: two clean runs gave identical hashes.

**Method.** Seam score = wrap-edge difference divided by interior neighbour difference (1.0 is invisible), measured at master resolution. Above 1.3 the texture gets a min-error-cut seam fix (image quilting: the cut follows mortar, grain and grass gaps, so there is no soft band). Then gentle low-frequency flattening (blurred luminance subtracted, mean re-added; strength in the table) and a periodic Lanczos-3 resize in linear light. No colour grading. Cards: alpha clean-up, specks removed, colour bled under transparency, border cleared. Chainmail is cropped to the interior (leather frame removed) first. Cloth is not seam-fixed: a cut would wreck the emblem.

**Memory.** Uncompressed RGBA8 with mips: w x h x 4 x 1.33 bytes. The total is 19.6 MB, against about 19 MB in the plan's section 3 (that figure leaves out the ripple normals, 0.7 MB; without them it is 18.9 MB, the same set). That is the 10% trigger, so compress before shipping all of it.

**Caveat.** `tools/import_assets.py` imports every PNG under `assets_src/`, including `_masters/` and `_prepared_masters/`. Move or zip them first.

| Output | Source | Px | Ops | Seam H/V before > after | Verdict | MB |
|---|---|---|---|---|---|---|
| ground/grass_lush | 01_lush_grassland | 512 | flatten .6 | 1.07/1.07 > 1.07/1.07 | clean | 1.40 |
| ground/grass_meadow | 02_wild_meadow | 512 | flatten .6 | 1.02/1.10 > 1.02/1.10 | clean | 1.40 |
| ground/dirt_trail | 03_grassy_dirt_trail | 512 | cut 15%, flatten .5 | 1.37/1.10 > 1.30/0.90 | acceptable: diamond lattice repeats | 1.40 |
| ground/mud_wetland | 04_muddy_wetland | 512 | cut 15%, flatten .6 | 1.59/1.43 > 1.09/1.06 | clean | 1.40 |
| ground/forest_floor | 07_forest_floor | 512 | cut 18%, flatten .6 | 1.31/1.18 > 1.11/1.09 | clean | 1.40 |
| ground/cobblestone | 05_cobblestone | 512 | cut 18%, flatten .6 | 1.44/1.26 > 1.16/0.98 | clean | 1.40 |
| water/water_shallow | 05_shallow_riverbed | 256 | cut 18%, flatten .5 | 1.94/1.39 > 1.18/1.11 | clean | 0.35 |
| water/water_deep | 06_deep_lake | 512 | cut 18%, flatten .5 | 2.95/1.35 > 1.17/0.98 | clean | 1.40 |
| water/ripple_normal_a | Shader_Extras a | 256 | resize, renormalise | 0.89/1.10 > 0.97/1.01 (final) | clean (periodic, unit, blue) | 0.35 |
| water/ripple_normal_b | Shader_Extras b | 256 | resize, renormalise | 0.99/0.94 > 1.00/0.94 (final) | clean (periodic, unit, blue) | 0.35 |
| bark/bark_deciduous | 07_deciduous_bark | 256 | cut 18%, flatten .6 | 1.39/1.47 > 1.02/0.99 | clean | 0.35 |
| bark/bark_pine | 08_pine_bark | 256 | cut 18%, flatten .6 | 1.65/1.59 > 1.06/1.06 | clean | 0.35 |
| foliage/leaf_broadleaf | 09_broadleaf_card | 512 | alpha clean, bleed | n/a | clean (cover 0.44) | 1.40 |
| foliage/leaf_evergreen | 10_evergreen_card | 512 | alpha clean, bleed | n/a | clean (cover 0.43) | 1.40 |
| walls/castle_stone | 04_castle_stone | 512 | cut 20%, flatten .6 | 1.63/1.50 > 0.97/1.29 | clean; courses intact | 1.40 |
| wood/planks | 06_planks | 512 | cut 20%, flatten .6 | 2.10/1.42 > 1.08/1.10 | clean; knots repeat | 1.40 |
| armour/steel_plate | 01_steel_plate | 256 | flatten .5 | 1.20/1.27 > 1.20/1.27 | clean (blurred shut by wrap resize) | 0.35 |
| armour/gambeson | 02_gambeson | 256 | flatten .5 | 1.14/1.10 > 1.14/1.10 | acceptable: grid and patches repeat | 0.35 |
| armour/chainmail | 03_chainmail | 256 | crop 1060, cut 15%, flatten .5 | 4.12/3.00 > 0.85/1.16 | clean | 0.35 |
| cloth/heraldic_cloth | 08_heraldic_fabric | 512 | flatten .3 | 1.37/0.96 > 1.37/0.96 | reject for tiling: use once, UV-placed | 1.40 |
| **Total** | | | | | | **19.6** |
