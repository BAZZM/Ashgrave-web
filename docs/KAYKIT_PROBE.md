# KayKit probe (12 Nov 2026)

Verdict: KayKit characters and dungeon pieces import through the existing pipeline and render in the web build. Facts below are measured from the files.

## Licence evidence
LICENSE.txt in each repo reads: "License: (Creative Commons Zero, CC0) ... free to use in personal, educational and commercial projects. ... crediting Kay Lousberg ... is not mandatory."

| Pack | Repository (github.com/KayKit-Game-Assets/) | Commit | Licence file |
|---|---|---|---|
| Adventurers 1.0 | KayKit-Character-Pack-Adventures-1.0 | 672074b | LICENSE.txt, CC0 |
| Skeletons 1.0 | KayKit-Character-Pack-Skeletons-1.0 | 15b62b9 | LICENSE.txt, CC0 |
| Dungeon Remastered 1.0 | KayKit-Dungeon-Remastered-1.0 | b0ca9bd | LICENSE.txt, CC0 |
| Character Animations | not found on GitHub (guessed names refused) | - | not used; itch.io only |

## Rig and animations
- All 9 characters (5 adventurers, 4 skeletons) have the same 41-joint skin "Rig", identical names and order (root, hips, spine, chest, upperarm/lowerarm/wrist/hand/handslot .l/.r, head, legs, IK helpers). Godot shows 50 (knight) and 42 (skeleton) bones: extra bones are weapon/helmet/cape mount points.
- Animations are inside every character file: adventurers 76 clips, skeletons 95 (same names, plus Spawn, Awaken, Taunt, Death_C, Summon). Covered: idle, walk, run, 1H/2H/dual/unarmed attacks (chop, slice, stab, spin), Block, Blocking, Block_Hit, Hit_A/B, Death_A/B, bow/crossbow (Ranged_Aim/Shoot/Reload), Spellcast_*, Sit_Chair/Floor_*, dodge, jump. No loop flags: set loop in code.
- Weapons and shields are separate meshes on bone attachments (1H_Sword, Badge_Shield, 2H_Sword, ...), all present in the file; hide what is not worn. More weapon files are in the pack; attaching one to `handslot.r` is untested.

## Sizes
| Item | Value |
|---|---|
| Knight.glb / Skeleton_Warrior.glb | 3.66 / 4.86 MB; knight 6,952 tris (all gear), skeleton 5,934 |
| Imported .scn, all clips | 1,303,284 / 1,855,538 B |
| Imported .scn, 16-17 clips kept | 424,260 / 411,359 B |
| Atlas | 1024x1024 PNG, 1 material (skeleton 2, with Glow); not shared between packs; each .glb embeds its own copy (7 copies of the dungeon atlas) |
| Dungeon pieces (tris) | wall 494, floor 188, pillar 136, doorway+door 1,068, torch 270, barrel 561 |
| Committed (18 .import + .scn/.ctex) | 1.24 MB; pack 623,581 to 1,875,005 B |
| Free download | repos 142 + 131 + 72 MB (FBX/OBJ/glTF duplicates) |

Texture: lossless .ctex with mips, RGBA8 on the GPU. Each embedded atlas becomes its own 5.3 MB GPU texture, so atlas duplication is the main memory cost.

| Perf readout (Performance monitors, as perf.gd) | `--looktest=empty` | `--looktest=wide`, before barrel added |
|---|---|---|
| Draw calls (shadow pass included) | 439 | 622 |
| Primitives | 441,692 | 522,142 |
| Nodes | 1,225 | 1,308 |
| Texture memory | 16.3 MB | 45.7 MB (49.9 MB with barrel) |

VRAM compression: glb option "embed as Basis Universal" fails in the web build (`basis_universal_unpacker_ptr is null`). A standalone PNG imported with compress/mode=2 gives `.etc2.ctex` and `.s3tc.ctex` (524 KB each, no mips) and loads and renders in headless Chromium. iOS ETC2 is unverified. Extracted glb textures cannot take that setting directly.

## Scale and orientation
Knight is 2.31 high at scale 1.0; the code hero's top is 2.30. Use scale 1.0. glTF front is +Z, the game faces -Z: rotate 180 degrees about Y. Dungeon grid is 4 x 4 (wall 4 high): characters are about 0.58 of a wall.

## Shots
/home/claude/screens/kaykit/: wide, close, swing, compare, empty. They read as chunky cartoon figures with clear silhouettes, much richer than the code-built hero, but bright and toy-like against Ashgrave's ashen tone. The head is half the height, and from the duel camera (behind the player) the knight's head and cape cover the enemy unless offset sideways. Floor tiles are blown out by the overworld sun.

## Reproduce
```bash
tools/get_godot.sh /home/claude/godot-kaykit
# clone the three repos (GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1) into /home/claude/assets_src/kaykit/, copy
# Characters/gltf/Knight.glb, Skeleton_Warrior.glb and Assets/gltf/{wall,floor_tile_large,pillar,torch_lit,barrel_large}.gltf.glb,
# wall_doorway.glb into assets_src/kaykit/ as knight.glb, skeleton_warrior.glb, d_<name>.glb
python3 -I tools/test_assets/kaykit_trim.py IN.glb assets_src/kaykit/knight.glb Idle Block ...   # keep clips
python3 tools/import_assets.py --godot /home/claude/godot-kaykit/Godot_v4.4.1-stable_linux.x86_64
python3 tools/build.py
node tools/test_assets/looktest_shot.js out.png "--looktest=wide --looktest-seek=0.5"   # close, swing, compare, empty
```

## Problems
- Re-running import_assets.py after a source change failed (Invalid UID); the tool now re-imports its sources from a clean stage.
- A world object (glowing orb) sat at the first test site; the hook now picks a site away from entities.
- Trimmed clips: the committed .glb sources are not committed; only imports.

## Recommendation
(a) Use KayKit "Rig" (41 joints) as the universal skeleton: all 9 characters share it. (b) No retargeting for KayKit characters: clips come ready, with identical names. Ship a trimmed clip set (or one shared library), not 76-95 clips per file; retarget only non-KayKit meshes.
