# Visual asset shortlist (scout, 12 Nov 2026)

Every fact below was read on the page linked in that row, on 12 Nov 2026. "Not stated" means the page I opened did not say. UNVERIFIED means I could not open the page or could not confirm. Nothing was downloaded. Page text was read through a fetch tool that summarises pages, so owner should eyeball the licence line on each page at download time (ORCHESTRATOR 7 already requires saving a licence snapshot).

ORCHESTRATOR.md was not in this branch; I read it from commit 63f06df (identical to /home/claude/reports/ORCHESTRATOR.md).

## Findings that change the plan

1. **Quaternius is no longer uniformly CC0.** Its licence page now defines the Quaternius Asset License (QAL) v1.0, "last updated 8/28/2026". Pack pages for Bestiary (Aug 2026) and Characters - Fantasy Races (Nov 2026) point at QAL; older and mid-2025/2026 pages I opened (UAL 1 and 2, Base Characters, Outfits, Props MegaKit, Village MegaKit, Modular Dungeons) say CC0. QAL allows use, modification and incorporating into a Product, no attribution, but forbids to "extract, repackage, sublicense, sell, or otherwise redistribute the Assets" as a standalone asset or pack, "free or paid", and says Assets include source files. Whether raw .glb files in a public repo count is not answered by the text. Treat QAL packs as **needs owner decision**; CC0 packs are clear.
2. **Free tiers are partial and the sites disagree.** quaternius.com says Standard is "60-70% free" and Pro "still free" (UAL 1, Village MegaKit, Props MegaKit). The itch.io pages say otherwise: UAL 1 Pro "$9.99 or more"; UAL 2 and Universal Base Characters show downloads unlocking at "$14.99" / "$19.99 or more" with no clear free tier. OpenGameArt (UAL 1, 16 Apr 2025) hosts a free Standard zip with **45 animations**; the Godot Asset Store lists a free 14.54 MB Standard. Plan section 7's "~120 and ~130 animations" is the full count, not the free count.
3. **KayKit** matches the plan (CC0, 1024 px atlas, 133 animations) but the free tiers are partial: Adventurers free = 5 characters; Skeleton Golem boss and Necromancer are in the paid Extra ($7.95+).
4. **Mixamo:** see its section. The "no redistribution" rule is not on any Adobe terms page I could open; it comes from an Adobe community-forum FAQ.
5. Not confirmed: Rokoko, FreePBR, Bandai Namco, Poly Pizza "mostly CC-BY", ambientCG "2,000+" (none opened). Kenney: "some bundles unavailable" not seen; the kenney.nl/assets index showed only 2D packs; several Kenney pages gave no formats.

## 1. Humanoid base characters and modular outfits

| Candidate | Author / licence / cost | Formats, technical | Fit |
|---|---|---|---|
| [Quaternius Universal Base Characters](https://quaternius.com/packs/universalbasecharacters.html) + [Modular Character Outfits - Fantasy](https://quaternius.com/packs/modularcharacteroutfitsfantasy.html) | Quaternius, CC0 per both pages ("Free to use in personal, educational and commercial projects"). Standard "60-70% free". Source (.blend, shaders) paid via Patreon. Itch pages show Standard zips 122 MB and 263 MB, but pricing text is ambiguous (see finding 2) | OBJ/FBX/glTF (Standard). Base: 6 bodies (Superhero/Regular/Teen, M/F), 20 hairstyles, avg ~13k tris, texture sizes not stated; tested Godot 4.3. Outfits: 12 outfits, 62 modular parts, 3 colour variants each, tris and textures not stated. Humanoid rig, "compatible with the Universal Animation Library". Rigged | Best match for visible gear swaps. 13k tris per body is heavy for phone; outfit parts may need decimation. Knight/peasant themes (itch tags). Preview: https://quaternius.com/assets/images/fullres/modularcharacteroutfitsfantasy.jpg |
| [KayKit Adventurers](https://kaylousberg.itch.io/kaykit-adventurers) | Kay Lousberg, CC0. FREE: 5 characters with a handful of accessories each. EXTRA $7.95+: 3 more (Engineer, Druid, large Barbarian) and 3 alt textures per character. SOURCE $11.95+: .blend | FBX, glTF. "Low poly optimized", tris not stated. One 1024x1024 gradient atlas (can drop to 128). Rigged; rig name not stated on this page. 25+ weapons/accessories (swords, shields, axes, bows, staffs) | Chunky low-poly, tiny atlas, ideal for memory. Gear change is weapon swaps, not modular armour. Preview image: none offered |
| [Quaternius Characters - Fantasy Races](https://quaternius.com/packs/charactersfantasyraces.html) | Quaternius, **QAL** (finding 1), Nov 2026. Standard free ("60-70%") | OBJ/FBX/glTF. 12 characters (6M/6F), 3 colour variants, tris not stated, humanoid rig, compatible with UAL. Not itemised: names, textures | Non-human races could vary NPCs. Licence needs owner decision. Preview: https://quaternius.com/assets/images/fullres/charactersfantasyraces.jpg |

## 2. Animation libraries

| Library | Licence / cost | Technical | Covers | Lacks |
|---|---|---|---|---|
| [KayKit Character Animations](https://kaylousberg.itch.io/kaykit-character-animations) (the current page; `/kaykit-animations` is marked Legacy, 29 clips) | Kay Lousberg, CC0. FREE tier "100+" clips, page also says 133 total; SOURCE $14.99+ (.blend per set) | FBX, glTF. Rigs **Rig_Medium** and **Rig_Large** (Large has fewer clips). Updated "6 days ago" | Idle, hit, death, spawn, interact; walk, run, jump, crawl, sneak, dodge, crouch; 1H, 2H, unarmed, dual-wield, blocking; shooting, bows, magic/spellcasting; sitting, lying, wave, cheer | Card-table gestures. Sword-and-shield specific clips not named (only "one handed" and "blocking"). Whether the free 100+ includes all categories not stated |
| [Quaternius Universal Animation Library](https://quaternius.com/packs/universalanimationlibrary.html) (Mar 2025) | CC0. Free Standard = 45 clips ([OpenGameArt](https://opengameart.org/content/universal-animation-library), 16 Apr 2025); full 120+ is Source (Patreon) | One "universal humanoid rig", "compatible with other common rigs (Mixamo for example)" per [itch](https://quaternius.itch.io/universal-animation-library). No clip names listed. Standard zip 13-14.5 MB | Locomotion in 8 directions, jog, sprint, push, crawl, swim, sitting, death, "combat and gun", emotes | Sword/shield, bow, spell, block, hit, card gestures: not mentioned |
| [Quaternius UAL 2](https://quaternius.com/packs/universalanimationlibrary2.html) (Jan 2026) | CC0. "Standard free" per site; OGA lists a free 10.3 MB zip; Digital Production says Standard has about 70%; itch says downloads at $14.99+ (conflict). Pro tier: not described | 130+ clips, same rig | Melee and armed combos (3- and 4-hit, split with recoveries), parkour, farming, fishing, zombie locomotion | Bow, spell, block, hit, sitting, card gestures: not mentioned on any page opened |

Mixamo (not shortlisted; terms differ): see section "Mixamo".

**Retargeting in Godot 4 (what is documented).** The Godot docs ([godot-es mirror of the English .rst](https://godot-es.readthedocs.io/es/4.x/_sources/tutorials/assets_pipeline/retargeting_3d_skeletons.rst.txt); the official 4.4 page body would not load for me) say: set a `BoneMap` with `SkeletonProfileHumanoid` in Advanced Import; it auto-maps by English bone-name patterns; the profile assumes a T-pose facing +Z; Rest Fixer (Overwrite Axis, Fix Silhouette, Normalize Position Tracks) handles mismatches; limits: unusual names need manual mapping, Overwrite Axis is destructive. Reports: the Godot Asset Store reviews of UAL ([store page](https://store.godotengine.org/asset/quaternius/universal-animation-library/)) mention "UpperChest bones bend too much" on other characters; a [Godot forum thread](https://forum.godotengine.org/t/bone-poses-getting-messed-up-when-going-from-one-retargeted-animation-to-another/130611) (Godot 4.5.1) mixing UAL with another melee set via humanoid BoneMaps saw leaning poses because animations key different bones; suggested fixes are `AnimationPlayer.deterministic = true` or trimming the BoneMap. **KayKit Rig_Medium to Quaternius rig retargeting: UNVERIFIED, no source found.** Test on the real hero (ORCH 10.1) before choosing.

## 3. Enemies and creatures

| Candidate | Licence / cost | Facts | Fit |
|---|---|---|---|
| [KayKit Skeletons](https://kaylousberg.itch.io/kaykit-skeletons) | CC0. FREE: 4 skeletons (warrior, rogue, mage, plain). EXTRA $7.95+: Skeleton Golem (boss) and Necromancer plus alt colour | FBX, glTF; 1024 atlas; rigged, basic movement included; tris not stated; v1.1. Skeleton clip sets exist in Character Animations | Undead grunts and casters free; boss is paid. Preview: none offered |
| [Quaternius Ultimate Monsters](https://quaternius.com/packs/ultimatemonsters.html) (Oct 2022) | CC0, free download | 50 monsters, "fully animated"; FBX/OBJ/Blend (glTF in format menu); rig and creature names not stated | Beasts and large creatures likely; list not shown. Preview: https://quaternius.com/assets/images/fullres/ultimatemonsters.jpg |
| [Quaternius Bestiary - Dungeon Monsters Kit](https://quaternius.com/packs/bestiarydungeonmonsterskit.html) (Aug 2026) | **QAL**; Standard free | 7 monsters with weapons, 3 colour variants; humanoid rig, UAL-compatible; animation clips unclear; tris not stated; monster names not stated | Dungeon humanoids that would share the UAL rig. Licence needs owner decision |

Beasts and large bosses: no verified dedicated pack beyond the above. Quaternius "Ultimate Animated Animal Pack" is listed on its site but not opened.

## 4. Tower and dungeon architecture

| Candidate | Licence / cost | Facts | Fit |
|---|---|---|---|
| [KayKit Dungeon Remastered](https://kaylousberg.itch.io/kaykit-dungeon-remastered) | CC0. FREE 200+ models (29 MB); EXTRA $7.95+ 275+ models, 6 alt textures; SOURCE $11.95+ | FBX, glTF (.gltf + .bin), OBJ. One 1024 atlas. Walls, floors, stairs, doors; arches not mentioned. Props: chests, barrels, chairs, tables, crates, traps, banners | Best fit: tiny shared atlas, modular. Bright stylised palette; needs ashen grading |
| [Quaternius Modular Dungeons Pack](https://quaternius.com/packs/modulardungeon.html) (Apr 2019) | CC0, free | FBX/OBJ/Blend (no glTF); 48 models; Textured/Animated shown as X. Contents beyond "modular dungeon assets" not stated. (Older [Modular Dungeon Pack](https://quaternius.com/packs/medievaldungeon.html), Jan 2018: 41 models incl. barrels, torches, potions, wall pieces) | Old; untextured by icon, so would take the shared palette. Preview: https://quaternius.com/assets/images/fullres/updatedmodulardungeon.jpg |
| [Kenney Castle Kit](https://kenney.nl/assets/castle-kit) | Kenney, "Creative Commons CC0", free (donations optional) | v2.0 complete remake 27/03/2024; 75 files; formats, model count, textures not stated; no preview URL | Medieval fortress, not dungeon; could supply towers and arches. Facts thin |

## 5. Outdoor: rocks, trees, ruins, village

| Candidate | Licence / cost | Facts | Fit |
|---|---|---|---|
| [KayKit Forest Nature Pack](https://kaylousberg.itch.io/kaykit-forest) | CC0. FREE: 100+ trees, rocks, bushes, grass (6.1 MB). EXTRA $9.99+: 200+ models, modular terrain, 8 colour variants. SOURCE $14.99+ | FBX, glTF, OBJ; 1024 atlas; grass in 2 styles. **Dead trees not mentioned** | Rocks and scatter OK; dead trees UNVERIFIED |
| [Quaternius Ultimate Modular Ruins](https://quaternius.com/packs/ultimatemodularruins.html) (Aug 2021) | CC0, free | FBX/OBJ/Blend; 90 models, includes an animated character and props; textured | Ruins for the wasteland. Preview: https://quaternius.com/assets/images/fullres/ultimatemodularruins.jpg |
| [Quaternius Medieval Village MegaKit](https://quaternius.com/packs/medievalvillagemegakit.html) (Jan 2025) | CC0. Standard and Pro free; Source via Patreon | OBJ/FBX/glTF; 304 models; textured, textures sizes not stated; tested Godot 4.3 | Village buildings. Preview: https://quaternius.com/assets/images/fullres/medievalvillagemegakit.jpg |

Opened, not shortlisted: [Quaternius Stylized Nature MegaKit](https://quaternius.com/packs/stylizednaturemegakit.html) (CC0, 27 rocks, 40 trees, no dead trees mentioned); [KayKit Halloween Bits](https://kaylousberg.itch.io/halloween-bits) (CC0, free 60+ models: graveyard, mausoleum, gravestones, skulls); [Kenney Graveyard Kit](https://kenney.nl/assets/graveyard-kit) (CC0, v5.0 17/10/2025, formats not stated).

## 6. Props, casino

| Candidate | Licence / cost | Facts | Fit |
|---|---|---|---|
| [Quaternius Fantasy Props MegaKit](https://quaternius.com/packs/fantasypropsmegakit.html) (Jun 2025) | CC0. Standard and Pro free; Source (collisions, worn variants) Patreon | OBJ/FBX/glTF; 211 models sharing 4 texture sets (sizes not stated); weapons, tools, potions, stalls, chests, furniture, books | Main prop source. Preview: https://quaternius.com/assets/images/fullres/fantasypropsmegakit.jpg |
| KayKit Dungeon Remastered (above) | CC0 | Props incl. barrels, crates, banners, tables, chairs, chests; 24 weapons are in the older [KayKit Dungeon](https://kaylousberg.itch.io/kaykit-dungeon) (superseded, CC0, 3 weapon tiers) | Matches KayKit set |
| [KayKit Furniture Bits](https://kaylousberg.itch.io/furniture-bits) / [RPG Tools Bits](https://kaylousberg.itch.io/rpg-tools-bits) | CC0. Furniture FREE 50+; Tools FREE 45+ (pickaxe, hammer, anvil, lantern) | OBJ/FBX/GLTF; 1024 atlas | Furniture and tools; no braziers named |

**Casino (card table, cards, chips, roulette wheel): no verified free candidate found.** Searches returned only paid marketplaces (CGTrader, Superhive). Poly Pizza roulette search returned no roulette model and licence was not shown; its poker search failed. [Quaternius 3D Card Kit - Fantasy](https://quaternius.com/packs/3dcardkitfantasy.html) (CC0, 60+ spell-style cards, one 1024 atlas) is not playing cards or chips. [Kenney Playing Cards Pack](https://kenney.nl/assets/playing-cards-pack) is 2D pixel art (270 assets, CC0). Casino will need modelling in code or a later search. Banners and braziers: not named in any pack opened.

## 7. Tiling PBR textures (1K)

All below are CC0 per the Poly Haven licence page; each asset page lists 1K to 8K, maps AO, ARM, Diffuse, Displacement, Normal (GL and DX), Roughness. The brief wants 512 px in game, so downscale from 1K. Authors in brackets.

| Need | Material (page) | Notes |
|---|---|---|
| Stone, brick | [rock_wall_08](https://polyhaven.com/a/rock_wall_08) (Amal Kumar), [medieval_blocks_06](https://polyhaven.com/a/medieval_blocks_06) (Rob Tuytel) | Fortress walls; grey, "dungeon" tag on blocks_06. Previews: https://cdn.polyhaven.com/asset_img/thumbs/rock_wall_08.png |
| Dark soil | [forest_ground_06](https://polyhaven.com/a/forest_ground_06) (Charlotte Baglioni) | Compact dark soil with leaves; leaf litter may need cleaning |
| Ash | [burned_ground_01](https://polyhaven.com/a/burned_ground_01) (Rob Tuytel) | Tags "ash", "charred soil", "scorched earth"; also leaves and gravel |
| Cracked rock | [dark_rock](https://polyhaven.com/a/dark_rock) (Amal Kumar) | Tags cracked, fissured, striated. Preview: https://cdn.polyhaven.com/asset_img/primary/dark_rock.png |
| Rough wood | [dark_wooden_planks](https://polyhaven.com/a/dark_wooden_planks) (Amal Kumar) | Tags rough, old, cracked, chipped |
| Aged metal | [rusty_metal_03](https://polyhaven.com/a/rusty_metal_03) (Amal Kumar) | Corroded sheet |

Backup: ambientCG [Rock030](https://ambientcg.com/view?id=Rock030) (grey cliff/wall, 1K to 8K, published 2020-03-29) and [Ground054](https://ambientcg.com/view?id=Ground054) (dirt/mud/sand, published 2022-05-15); creator not stated on either page. I could not find an ambientCG ash or burnt material (search returned nothing). Poly Haven's ToS prohibits scraping or bulk downloading without permission, so download by hand.

## 8. UI and icons

| Candidate | Licence | Facts |
|---|---|---|
| [Kenney UI Pack - RPG Expansion](https://kenney.nl/assets/ui-pack-rpg-expansion) | CC0 1.0, attribution appreciated not required | 85 assets, 209.4 KB zip; formats not stated; preview: none offered |
| [game-icons.net](https://game-icons.net/about.html) | **CC BY 3.0, credit required** ("Icons made by {author}. Available on https://game-icons.net") | Thousands of item icons (per-author table; no total stated); credit per author needed in game credits |
| [Kenney Game Icons](https://kenney.nl/assets/game-icons) | **UNVERIFIED**: page gave no licence text | Free per page; contents not itemised. Kenney's [support page](https://kenney.nl/support) says assets are CC0 generally. Kenney Fantasy UI Borders: page blocked to my fetcher, UNVERIFIED |

## Mixamo

The [Adobe Mixamo FAQ](https://helpx.adobe.com/creative-cloud/faq/mixamo-faq.html) (last updated 14 Sep 2021) allows characters and animations "royalty free for personal, commercial, and non-profit projects" including video games and is **silent on redistribution**; not available for Enterprise or Federated IDs, or country code China. The [Mixamo Additional Terms](https://wwwimages2.adobe.com/content/dam/cc/en/legal/servicetou/Mixamo-Addl-Terms-en_US-20210623.pdf) (effective 23 Jun 2021): the text I received contained only a ban on using the service to train machine-learning systems. An [Adobe community FAQ post](https://community.adobe.com/t5/mixamo-discussions/mixamo-faq-licensing-royalties-ownership-eula-and-tos/m-p/13234775) (29 Sep 2022) says "the only thing you can't do is distribute the raw character and animation files" and that files may not go to "customers or non-team members". That is a forum post, not a terms page, and it describes a "technology preview". A public repo would distribute raw files: do not commit Mixamo FBX (plan 7.3 is consistent). Whether baked animation data counts: not stated.

## Cohesion sets

- **A. All Quaternius (CC0 packs only):** Universal Base Characters + Outfits + UAL 1/2 + Fantasy Props + Village + Modular Dungeons/Ruins + Ultimate Monsters, with Poly Haven surfaces. Gaps: no confirmed sword-shield, bow, spell or card clips; no casino; no confirmed dead trees; atlas sizes not stated; Bestiary and Fantasy Races excluded (QAL).
- **B. All KayKit (CC0):** Adventurers + Skeletons + Character Animations (Rig_Medium) + Dungeon Remastered + Forest + Furniture/Tools Bits. Most memory-friendly (1024 atlases). Gaps: no modular armour, golem boss and alt textures are paid, no card clips, no casino, dead trees unconfirmed.
- **C. KayKit world + Poly Haven surfaces:** B with Poly Haven 512 px stone, soil, ash, metal layered on the KayKit shapes (ORCH 7.5 item 6 target). Same gaps as B; style clash between flat atlas and PBR is a DP1 test.

## Licence evidence

| Source | Licence statement URL | Wording / name | Checked | Public-repo redistribution | Credit |
|---|---|---|---|---|---|
| Quaternius CC0 packs | each pack page, e.g. [UAL](https://quaternius.com/packs/universalanimationlibrary.html) | "Free to use in personal, educational and commercial projects" (CC0 link) | 2026-11-12 | Yes under CC0 as stated | No |
| Quaternius QAL packs | [license.html](https://quaternius.com/license.html) | QAL v1.0, updated 8/28/2026; no redistribution as standalone asset or pack | 2026-11-12 | **Unclear** (owner decision) | No |
| KayKit | each itch page, e.g. [Dungeon Remastered](https://kaylousberg.itch.io/kaykit-dungeon-remastered) | CC0 v1.0; "do not resell unmodified copies" | 2026-11-12 | Yes (not a resale) | No |
| Kenney | [support](https://kenney.nl/support) | "public domain licensed (CC0)" | 2026-11-12 | Not addressed on page; CC0 | No |
| Poly Haven | [license](https://polyhaven.com/license) | "licensed as CC0... You can redistribute them" | 2026-11-12 | Yes; ToS bans scraping | No |
| ambientCG | [license docs](https://docs.ambientcg.com/license/) | CC0 1.0; "include the raw files in your project" | 2026-11-12 | Yes | No |
| game-icons.net | [about](https://game-icons.net/about.html) | CC BY 3.0 | 2026-11-12 | Yes with credit | **Yes** |
| Mixamo | see above | Royalty free use; raw redistribution barred per community FAQ | 2026-11-12 | **No** | No |

## What the owner must do

Build machines cannot download these. Download by hand into `assets_src/` (gitignored); itch pages show a "Name your own price" prompt, take the free option where the page offers one and check what you got matches the tier named above. Whether an account is needed: not stated on the pages, except Mixamo (Adobe ID).

- [ ] Decide the QAL question (finding 1) before taking Bestiary or Fantasy Races.
- [ ] KayKit: [Adventurers](https://kaylousberg.itch.io/kaykit-adventurers), [Character Animations](https://kaylousberg.itch.io/kaykit-character-animations), [Skeletons](https://kaylousberg.itch.io/kaykit-skeletons), [Dungeon Remastered](https://kaylousberg.itch.io/kaykit-dungeon-remastered), [Forest](https://kaylousberg.itch.io/kaykit-forest). Decide whether paid Extra ($7.95+, Golem boss) is wanted.
- [ ] Quaternius: [Base Characters](https://quaternius.com/packs/universalbasecharacters.html), [Outfits](https://quaternius.com/packs/modularcharacteroutfitsfantasy.html), [UAL 1](https://quaternius.com/packs/universalanimationlibrary.html) (free zip also at [OpenGameArt](https://opengameart.org/content/universal-animation-library)), [UAL 2](https://quaternius.com/packs/universalanimationlibrary2.html) (free zip at [OpenGameArt](https://opengameart.org/content/universal-animation-library-2)), [Fantasy Props](https://quaternius.com/packs/fantasypropsmegakit.html), [Village](https://quaternius.com/packs/medievalvillagemegakit.html), [Ruins](https://quaternius.com/packs/ultimatemodularruins.html). The site's "Download" link showed as `#inline` to my fetcher, so use the itch or OpenGameArt links if it fails. Confirm which tier (free or paid) each zip is.
- [ ] Poly Haven (click each, pick 1K, glTF or maps): rock_wall_08, medieval_blocks_06, forest_ground_06, burned_ground_01, dark_rock, dark_wooden_planks, rusty_metal_03 (links in section 7).
- [ ] Kenney [UI Pack RPG Expansion](https://kenney.nl/assets/ui-pack-rpg-expansion); game-icons.net icons only if credit is accepted.
- [ ] Mixamo (optional): Adobe account at mixamo.com; keep raw FBX out of the repo.
- [ ] Casino models: pick a source or approve code-built.
- [ ] Save a screenshot of each licence line at download time.
