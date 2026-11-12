# Ashgrave Art Bible

Colours are sRGB hex; S and V are HSV saturation and value. A ref px is a pixel of the 1280x720 UI viewport (88 ref px = 48 pt on iPhone). `a → b` is current → proposed. *verify*: to verify in the web build.

## 1. Pillars

|Pillar|This means|This rules out|
|---|---|---|
|**Ash and ember.** The world is dim and low in saturation; fire, gold and blood carry the colour.|World palette V ≤ 0.45 and S ≤ 0.50, falling to ≤ 0.20 in the Ashlands (casino ≤ 0.65). Saturated hue only on emissives, heraldry, VFX|Blue noon sky, mint grass, fill lights other than fire or moon|
|**Chunky form, quiet grain.** Shape carries the design; texture adds grain only.|Bevelled low-poly forms; every texture is a luminance grain map coloured by the palette|Photographic colour, moss, baked highlights, detail under 3 texels|
|**Fighters read first.** Hero and current enemy are the brightest, most saturated shapes on screen.|Backdrop luminance ≤ 60% of fighter luminance; rim on fighters only|Emissive props behind the duel line; HUD over the fighters|
|**Few things, shared.** One palette, one grain set, one light recipe per place.|5 packed grain textures; variety from instance colour|Per-item or per-enemy textures; world textures above 512|

## 2. Cohesion method: grain, then ramp

KayKit is flat colour with soft gradients, so **no texture carries colour**: each becomes a luminance grain map, and the palette colours it through a two-colour ramp. That strips the packs' saturated greens and stone moss; one grain serves every region.

### 2.1 Incoming textures (offline, at ingest)

1. Crop the master to a seamless square; never stretch. Crop chainmail and gambeson inside their leather straps.
2. Baked light: the 64 px-blurred luminance of a 512 tile may vary ≤ 0.06 (all 16 measure 0.01-0.06 as delivered). Small-scale shading stays as relief (no normal maps exist): keep texture-up as world-up on walls; clip luminance above the 98th percentile.
3. Keep luminance only; stretch its 5th-95th percentile to 0.10-0.90.
4. Resize to 512 (armour and foliage 256); pack four grains per RGBA texture.
5. Shader: `albedo = mix(dark, light, grain)`, with `light = tint × (1 + d)` and `dark = tint × (1 - d)` mixed 10% toward region fog. `tint` is the palette colour; add 0.10 to `d` where its V < 0.25. Then world-space macro noise, ±8% V, period 37 m.

|Grain|Source S|Colour in game|d|Tile|
|---|---|---|---|---|
|Lush grass, wild meadow|0.78, 0.71|region ground|0.18|4 m|
|Dirt trail, as patches|0.54|dark = region ground, light = `#6B5A40`|ramp|4 m|
|Muddy wetland|0.43|Mud|0.20|4 m|
|Forest floor (also Ashlands ground)|0.46|region ground|0.20|4 m|
|Shallow riverbed|0.24|Shallow|0.15|4 m|
|Deep lake|0.80|Deep|0.15|4 m and 6.5 m|
|Castle stone (course 0.45 m)|0.15|region architecture|0.28|4 m|
|Cobblestone (cobble 0.45 m)|0.27|region architecture × 0.9|0.22|4 m|
|Wood planks (0.29 m), both barks|0.37, 0.33, 0.45|Loam, Bark|0.25|2 m|
|Heraldic cloth|0.75|dark = heraldry colour, light = Brass|ramp|0.8 m|
|Steel, chainmail, gambeson|0.07, 0.26, 0.48|instance colour|0.30 hero, 0.20 enemies|0.5 m|
|Foliage cards (luminance + alpha)|0.74, 0.67|Leaf, Pine|0.25|1.2 m card|

**Texel density:** 128 texels per world unit on ground, stone and water (512 px = 4 m), 256 on wood, about 500 on character overlays. Ground is world-space and walls triplanar, so a wall and the grass at its foot agree.

**Memory:** three 512 RGBA at 1.4 MB with mipmaps (Terrain A: grass, meadow, trail, mud; Terrain B: forest floor, riverbed, lake, deciduous bark; Build: stone, cobble, planks, pine bark) and two 256 at 0.35 MB (Armour: steel, chainmail, gambeson, cloth; Foliage: two luminance, two alpha). Total 4.9 MB uncompressed, against 19 MB in colour in `docs/TEXTURE_PLAN.md`. KayKit atlases ship at 256.

### 2.2 Models

- **Mask atlas:** each KayKit atlas gets a 64 px mask on the same UVs: R metal, G cloth and leather, B emissive.
- **Palette remap:** R and G areas take the instance colour (`metal_tint`, `identity`) times atlas luminance: KayKit's gradients survive, its hues do not. Unmasked areas (skin, bone, wood) keep atlas colour at S × 0.7, V × 0.85.
- **Kit buildings and props:** same remap plus the Build grain, triplanar, at half `d`.
- **Code-built meshes:** palette ramp plus the same grain; no bare single-colour material wider than 2 m.
- **Character overlay:** yes, on body armour only: steel on R, gambeson on G, chainmail by instance. It also offsets roughness ±0.12. Sample from rest-pose coordinates (baked UV2), not skinned position, or it swims (*verify*).

### 2.3 If it still looks foreign

When the Critic scores Material coherence below 4 on a shot twice, cut in this order: halve `d`; remove foliage cards; replace that grain with macro noise alone; remove the model.

## 3. Palette

|Family|Colours|
|---|---|
|Ash|Soot `#121114`, Char `#1E1C20`, Ash-dark `#2E2B2E`, Ash `#4A4648`, Ash-light `#77716D`, Bone `#CFC6B4`|
|Earth|Bark `#3D2E22`, Loam `#4A3A2A`, Mud `#4A4634`, Thatch `#5E4935`, Plaster `#736A56`|
|Green|Vale `#5E6B38`, Meadow `#5A6B3C`, Leaf `#505F32`, Greywood `#2F3F2C`, Pine `#26382C`, Mire `#3D4D38`|
|Water|Deep `#20343A`, Shallow `#3E6A68`|
|Metal|Blackened `#2B2D33` (enemies), Iron `#6E7480`, Steel `#8C97A8`, Silver `#B4BCC8`, Brass `#C9A24B`|
|Fire|Ember `#FF731A`, Torch `#FF8C40`, Hearth `#FFCC66`, Gold `#FFD68C`, Blood `#B3261E`|
|Cold|Moon `#B3C7FF`, Frost `#66CCFF`, Storm `#BF99FF`, Grave `#66FF80` → `#A6D94A` (green is player life)|
|Heraldry|Blue `#2F4E9E` (hero), Red `#8C2E26`, Green `#2F6B4A`, Purple `#5A3A7A`|

|Region|Ground|Architecture|Accent|Fog|Key light|Ambient|
|---|---|---|---|---|---|---|
|Hearthvale|`#5E6B38`|`#736A56`, `#5E4935`|`#FFCC66`|`#8A8F88`|`#FFE2B8`|`#8795A8`|
|Forest|`#2F3F2C`|`#3D2E22`|`#9DB35A`|`#4A5F54`|`#DDE8C4`|`#55685E`|
|River, lake|`#4A4634`; water `#20343A`, `#3E6A68`|`#4A3A2A`|`#B8A65A`|`#66756E`|`#E6E2D0`|`#6A7C82`|
|Ashlands|`#332B2B`|`#2E2B2E`|`#FF731A`|`#4D332E`|`#FF9A6B`|`#4A3A40`|
|1 Ash Gate|`#3D383B`|same|`#8C2E26`|`#211717`|`#FF8C40`|`#5A4442`|
|2 Cisterns|`#29383D`|same|`#4FA89A`|`#0D1F21`|`#66D9CC`|`#2E4A4D`|
|3 Foundry|`#332621`|same|`#FFB02E`|`#33140A`|`#FF661A` → `#FF5514`|`#5A3326`|
|4 Rookery|`#4D4F5C`|same|`#D9E2FF`|`#333347`|`#B3CCFF`|`#5A5F7A`|
|5 Pyre Court|`#241F24`|same|`#B3261E`|`#29120D`|`#FF8026` → `#FFB84D`|`#4A2E2A`|
|Casino|felt `#1F4D3A`, carpet `#5A2126`|`#3A2A20`|`#C9A24B`, `#FFD68C`|`#1A1210`|`#FFD9A0`|`#4A3A30`|
|Clan base|`#4A4034`|`#4A3A2A`, `#4A4648`|clan heraldry colour|host region|host region|host region|

Tower rows are today's `tiers.gd` values; land grounds and fogs are `land.gd` values with S lowered.

**Saturation is the danger gauge.** Hearthvale and the Meadows stay green as the safe land (ground S 0.48 and 0.44, against 0.78 in the source grass); Greywood 0.30, Mirefen 0.27, Ashlands 0.16.

**World against characters:** world palette V 0.12-0.45; character albedo V 0.35-0.80 (a darker enemy needs an emissive accent); identity colour S 0.50-0.75 on 10-25% of the body.

## 4. Lighting and atmosphere

Energies are starting values: tune until a `#808080` card on the ground reads `#808080`-`#949494` in sun and at least `#303030` in shade.

|Property|Land day|Land dusk (new key at `light` 0.35)|Rain|Tower|Duel|
|---|---|---|---|---|---|
|Sun or moon `light_energy`|1.7 → 1.2|0.8|× 0.6 (new)|1.0 → 0.5 (Rookery 1.6 → 1.0)|1.1 → 0.6 (outdoor 2.2 → 1.2)|
|`light_color`|`#FFF2D9` → `#FFE2B8`|`#FF9A5A`|keep|`#B3C7FF` keep|keep|
|Sun elevation (`rotation_degrees.x`)|65° → 50° maximum|12°|keep|keep|keep|
|`ambient_light_source`|SKY → COLOR|COLOR|COLOR|SKY → COLOR|SKY → COLOR|
|`ambient_light_color`|region|`#5A5F86`|region|tier|tier|
|`ambient_light_energy`|1.3 → 0.6|0.45|keep|1.8 → 0.5|1.6 → 0.55|
|`fog_density`|0.0045 → 0.008|0.008|0.012 → 0.018|0.022 → 0.03|0.035 → 0.045|
|`fog_light_color`|region fog × 0.8|× 0.5|50% toward `#59646B`|tier|tier|
|`fog_sky_affect`|0.35 → 0.7|0.7|0.9|keep|keep|
|`sky_top_color`|`#3361B2` → `#56637A`|`#3A3550`|`#3E454D`|keep|keep|
|`directional_shadow_max_distance`|45 → 32|32|32|40 → 24|100 → 16|
|`directional_shadow_mode` (*verify*)|4 splits → 2|2|2|2|orthogonal|
|Torch `light_energy`, `omni_range`|none|none|none|2.4 → 2.8, 10 → 7|2.2 keep; lit torches 5 → 3|
|Fill and rim `light_energy`|none|none|none|none|fill 1.6 → 2.0; rim 3.0 → 4.0, behind the enemy, colour opposite the tier key|

Night keeps today's sun (0.25, `#99B2FF`); ambient 0.5 → 0.35. Everywhere: `tonemap_mode` Filmic, keep. `adjustment_enabled` false → true, `adjustment_contrast` 1.08, `adjustment_saturation` 0.9 (0.75 in rain) (*verify* cost; fallback: palette S × 0.9). `glow_enabled` stays false on web: emissives get a V 1.0 core plus a shared 64 px halo quad, at most 12 on screen. OmniLight shadows off; at most 5 OmniLights reach any mesh. Ashlands adds `fog_height` 6 m above ground, `fog_height_density` 0.08 (*verify*).

**Renderer check:** read against the Godot 4.4 renderer feature table and the 4.4.1 `Environment` reference. Compatibility supports depth and height fog, tonemapping and adjustments; it lacks Decal nodes, light projectors, SSAO, SSR, volumetric fog and depth of field, and nothing here uses them (stains are alpha quads). Directional shadows, rim and CPUParticles3D already render in the Golden Shots. No proposed value has been run in the web build.

## 5. Material classes

|Class|Roughness|Metallic|Tint|Grain|
|---|---|---|---|---|
|Stone|0.95|0|region architecture|castle stone; cobble on floors|
|Wood|0.85|0|Bark, Loam|planks along the length; bark on trunks|
|Soil, grass|1.0|0|region ground|terrain layers|
|Water|0.10|0|Deep, Shallow by baked shore distance; alpha 0.72 → 0.80|two lake samples, 0.04 and 0.025 m/s, 20° apart; no screen or depth texture|
|Metal|0.34 → 0.45 (blade 0.18 → 0.30)|0.85 → 0.60 (blade 0.95 → 0.85)|Metal family, S ≤ 0.25; trim Brass|steel or chainmail|
|Cloth, leather|0.90, 0.70|0|identity or Earth colour|gambeson, heraldic cloth|
|Skin, bone|0.70|0|atlas colour, Bone|none|
|Emissive|unshaded|0|Fire and Cold only; energy 2-4|none; under 3% of the screen|

## 6. Shape language

|Subject|Rules|
|---|---|
|Architecture|Base, body and cap on every structure. Walls ≥ 0.6 m thick; tower walls lean in 3-5°. Bevels ≥ 0.05 m. Roof pitch 40-50°. No plain box or sphere wider than 2 m|
|Props|Readable at 48 px tall; at most 3 material classes; thinnest part ≥ 0.06 m|
|Trees|Trunk visible for ≥ 1/3 of height, lean 3-8°. Canopy of 3-5 offset clumps plus 4-6 cards at its edge. Ashlands: dead trees only|
|Hero|1.8 m; shoulders wider than hips; plume, cape and shield in heraldry Blue|
|Grunt|1.0-1.15 × hero, hunched, no cape, one accent, emissive eyes only|
|Elite|1.2-1.35 ×, one silhouette signature (horns, pauldrons, back banner), emissive accent|
|Boss|1.5-1.8 ×, two signatures plus cape or crown, own key-light colour, one ≤ 1024 texture|

## 7. Character readability

- Rim on the hero and current enemy only: `rim` 0.35 → 0.5 hero, 0.7 enemy; `rim_tint` 0.4 → 0.3.
- Faces sit in shadow: helm, hood or skull on every fighter.
- A gear change must alter the silhouette or a colour block ≥ 8% of the body; parts under 0.05 m do not read at duel distance.
- Weapon: length, blade shape, element emissive along the blade. Shield: round, kite or tower, plus heraldry. Helm: plume, fin, horns or crown. Armour tier: Iron, Steel, then Silver with Brass trim, plus a pauldron swap.

## 8. VFX

A particle is earned by a change in health or posture, a parry, a state change, an element proc, or one ambient signature per region. All are CPUParticles3D, unshaded quads.

|Effect|Count|Lifetime|Colour|
|---|---|---|---|
|Hit sparks|12-28 by weight (28 today)|0.45 s keep|`#FFD980`|
|Parry; perfect parry|28; 40|0.45 s|`#FFF2BF`|
|Element proc|20|0.6 s|Ember, Frost, Storm, Grave|
|Hurt; heal|16|0.5 s|`#D12929`; `#66FF8C`|
|Arena embers|40 keep|5 s keep|`#FF8C33`|
|Ashlands ash-fall|60|6 s|`#77716D`|
|Rain|260 → 200|0.8 s keep|`#CCE0FF` at 45% alpha|

Ceiling: 150 live particles in a duel, 300 on land.

## 9. UI

- **Type:** Cinzel 700 for names, banners and buttons, ≥ 20 ref px. Body text: Alegreya Sans Medium (SIL OFL, about 40 KB), ≥ 24 ref px; today's 15-22 px Cinzel labels move to it.
- **Colours:** text `#FFFFFF` and Gold, 6 px `#000000` outline at 80% alpha (keep). Panels Soot at 90%, 2 px Gold border. Bar track `#1A1A1F`; player health `#4CCC66`; enemy health `#D12929`; posture `#FFCC40`; player posture `#73A6FF`.
- **Frames:** Gold rules and diamonds; round buttons with a 3 px ring; no textures.
- **Touch:** hit area ≥ 88 × 88 ref px, 16 px apart. Pause grows 64 → 88.
- **Placement:** insets 90 ref px at the sides, 40 at the bottom (*verify* on the phone). The centre 50% × 60% holds prompts only, each ≤ 2 s.

## 10. Vertical slice: the look-test scene

One 40 × 30 m scene where Hearthvale meets forest and river; land day, fixed sun. Capture at 844 × 390 CSS px, DPR 3, three ways for the look decision: flat palette, grain and ramp, source colour tinted.

|View|Contents|Camera|
|---|---|---|
|V1 grass|40 m of lush grass into meadow|height 0.6 m, pitch -4°, FOV 60, sun side-on|
|V2 trail and mud|grass → dirt trail → mud, blend bands 0.8-1.5 m|height 2.5 m, pitch -35°|
|V3 water edge|mud bank, riverbed, deep water|height 1.6 m, pitch -15°, along the shore|
|V4 tree|one deciduous, one pine, hero for scale|9 m back, height 1.7 m, FOV 50|
|V5 stone wall|castle stone, plank door, cobble at its foot|1.5 m away, height 1.6 m; square-on and at 30°|
|V6 duel|hero and one skeleton grunt, the wall behind|the duel camera, FOV 55|
|V7 banner|0.8 × 2.2 m heraldic cloth, swaying|3 m away, pitch +10°|

Golden Shots to improve first: 05, 06, then 03, then 01.

## 11. Critic checklist (pass or fail)

- No world surface wider than 2 m is one flat colour.
- No texture shows its own hue, moss, a highlight or a cast shadow.
- A wall and the ground at its foot show grain at one scale.
- No tiling repeat shows in shots 01 and 05.
- In greyscale, the fighters are the lightest large shapes in shots 03 and 07, and the enemy's whole outline separates from the backdrop.
- Metal shows its own colour, not a mirrored sky.
- Sky, fog and horizon meet without a hard line.
- Each screenshot names its region by colour alone.
- Saturated colour appears only on emissives, heraldry, VFX and HUD.
- No scene has more than one warm and one cool light colour.
- Every tree shows trunk, lean and a broken canopy outline; every structure base, body and cap.
- No fighter shows a cartoon face.
- No HUD element covers a fighter; no text is under 20 ref px.
- Every particle traces to a hit, parry, state change or the region.

## 12. Open questions for the owner

1. **Ash ground and rock faces: neither pack has them.** (a) Forest-floor and mud grains under the Ashlands ramp: no new texture; may read as dark soil. (b) One CC0 ash texture: truer cracks; a third source to unify. (c) Macro noise only: cheapest; flattest. **Recommend (a), then (b) if Ashlands terrain scores below 3.** Rock faces use macro noise.
2. **Sky.** (a) Always overcast, Hearthvale warmest: most cohesive. (b) Blue noon over Hearthvale only: stronger haven contrast; two sky recipes. **Recommend (a).**
3. **KayKit heads are large and friendly.** (a) Accept them under the dark palette: no work; least menace. (b) Cover every fighter's face and scale the head bone to 0.85: darker read; needs an animation check. **Recommend (b).**
