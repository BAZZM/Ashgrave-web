# Rig plan: KayKit fighters on one skeleton

Plan only; no game code. Based on `docs/KAYKIT_PROBE.md`, the code at `829ccf2` and Godot 4.4.1 (`ClassDB` confirms `AnimationPlayer.play_section`, `play_section_backwards` and `SkeletonModifier3D`).

**Clip evidence.** Names, lengths and section times were read from the pack files the probe imported from (`/home/claude/assets_src/kaykit/*/addons/*/Characters/gltf/Knight.glb`, `Skeleton_Warrior.glb`), not from `game/assets/kaykit/`: those `.scn` files are compressed and hold only the probe's 16-17 clips. Times are seconds along the sword-tip path, sampled at 30 fps. Across all 9 files rest poses match and every shared clip has identical keys on every bone except the two toe bones, so one library fits all characters. **est.** = estimate, measured in R1.

## 1. The contract

No signals. `:N` = line in `fighter_visual.gd`.

|Must keep|Callers|
|---|---|
|`play(action, dir, duration)` :5|duel.gd:314,315,331,381,426,436,437,503,504,510,524,538,545,546,606,608,630,653,678,718,776,777,820,821,846; duel_enemy.gd:29,36,41,95,106,150,161,175,192; duel_posture.gd:106,107,177; duel_pvp.gd:47,114,140,197,203,241,242; duel_stage.gd:56,107; overworld_duels.gd:61,66,85,89; overworld_interact.gd:197,216,279; world.gd:596|
|`configure(cfg)` :9|duel.gd:210,211,218; overworld.gd:161,463; world.gd:89,361,369,663; overworld_places.gd:62,102,154; overworld_interact.gd:26; overworld_remote.gd:46|
|`set_tell(color, t)` :13|duel_enemy.gd:30,37,162,174; duel.gd:544,823; duel_stage.gd:80,84; overworld_duels.gd:60|
|`set_walk(amount)` :17|overworld_hero.gd:78; overworld.gd:413; world.gd:468,498,554; overworld_places.gd:197,209; overworld_interact.gd:51; overworld_remote.gd:61; overworld_duels.gd:21,28,191,193; overworld_travel.gd:198|
|`set_pace(mult)` :21|overworld_hero.gd:79; overworld_remote.gd:64|
|`flash(color)` :25|duel.gd:425,609,699,722,750,758,766,803,822; duel_fx.gd:230; duel_posture.gd:108; duel_pvp.gd:198,204; overworld.gd:464; world.gd:664|
|`get_clash_point()` :29|duel.gd:410,506,507,539,556,562,569,596,611,647,698,721,732,751,754,827,828; duel_fx.gd:51,56,232,233,239,271; duel_enemy.gd:73,209,217; duel_posture.gd:112-114; duel_pvp.gd:194,206,207,224|
|Node3D: `position`, `rotation`, `global_position`, `visible`, `reparent`; tweens on `position`, `position:x`, `rotation:y`|duel_stage.gd:36,47,49,50,69; duel_fx.gd:209,210; duel.gd:660,663; overworld_hero.gd:80,81; overworld_remote.gd:59,60; overworld_interact.gd:41,50; overworld.gd:341|

Actions in use: `idle`, `taunt`, `windup(Dir, s)`, `feint(0, hold)`, `strike(Dir, 0.1)`, `stagger`, `broken`, `hit(±1, s)`, `guard`, `slash(-1 L, 1 R, 2 U, 3 D; s)`, `parry(±1)`, `block`, `dodge(±1)`, `death`, `victory`. `Dir` is LEFT, RIGHT, OVER, THRUST (attack_def.gd:4). Damage resolves in duel code at the `strike` call (duel_enemy.gd:192); the visual decides nothing. Unknown actions must be ignored.

|Can change|Where|To|
|---|---|---|
|Type `PlaceholderVisual`, `.new()`|overworld.gd:17,158; world.gd:17,86,359,367; overworld_interact.gd:23,34; overworld_remote.gd:31,46,50; overworld_duels.gd:89,90,193; overworld_places.gd:58,100,152,194|`FighterVisual` plus one factory|
|`placeholder_fighter.tscn`|duel.gd:215; `Player`, `Enemy` in duel.tscn (duel.gd:203,204)|swapped at `_ready` when the flag is on|
|`has_shield`|overworld.gd:159; world.gd:87; overworld_remote.gd:32|a `configure` key|
|Look keys `style`, `scale`, `body`, `accent`, `over`|items.gd:110-153; enemy_def.gd:44-191; land.gd:39-48; overworld_places.gd:4-10,94-98|kept as input; mapped by a table (§2)|
|`slash` reused for gathering and shooting|overworld_interact.gd:197,279; duel.gd:718|new actions `gather`, `shoot`, `cast`, `sit`|

**Dead:** `AnimPackVisual` (anim_pack_visual.gd; nothing instantiates it); action `recover`; exports `body_color`, `accent_color`, `style` beyond `configure`. `AnimPackVisual` maps whole clips to actions and has no `configure`, tell, locomotion, sections or holds: reuse its idea, not its file.

## 2. The new visual: `RigVisual extends FighterVisual`

```
RigVisual                    scale and yaw as today
└ Rig (yaw 180°)             from res://assets/rig/<base>.glb: no clips, no textures
  └ Skeleton3D               41 joints
    ├ Body, Head             2 skinned meshes (KayKit's 6-9 parts merged offline)
    ├ RigOffsets             SkeletonModifier3D: head scale, chest lean, hunch
    └ BoneAttachment3D ×≤5   handslot.r, handslot.l, head, chest, hips
AnimationPlayer              library "" = one shared AnimationLibrary
Trail                        today's 11-quad MultiMesh, fed by a Tip marker on the weapon
```

- **AnimationPlayer, not AnimationTree** (departs from ORCHESTRATOR 10.3). The duel code already is the state machine; a second one could disagree with it. Everything needed is section play, speed, reverse and cross-fade. A player blends two clips at most; a tree evaluates its whole graph for every fighter on the one thread. Players run in manual mode from one loop: the nearest 6 every frame, the rest every second frame, none off-screen or beyond 40 u. **N = 18** (hero, 3 foes, 8 villagers, 6 players). Reserve: a tree on the hero alone if S4 needs to walk while aiming.
- **One library.** New `tools/rig_pack.py` (grown from `kaykit_trim.py`) writes `anims.glb` (skeleton plus ≤50 clips from `Skeleton_Warrior.glb`, the superset), 8 clip-free character files (both Rogue heads in one), `gear.glb`, and per pack `atlas_<pack>.png` (256 px) and `mask_<pack>.png` (64 px, classified from swatch colour, then hand-corrected). `RigVisual` loads the library once into a static and adds it to each player; loop flags are set there.
- **Differences:** mesh swap (Body, Head), one shared shader with one `ShaderMaterial` per skinned mesh (`metal_tint`, `identity`, `flash`, `rim`, `tell`), gear parented to attachments.
- `rig_looks.gd` maps `style` to base, gear and tier; `Items.hero_look` stays the input. `get_clash_point()` keeps today's formula, so camera and sparks do not follow the animation.
- **KayKit has:** `1H_Sword`, `2H_Sword`, `1H_Axe`, `2H_Axe`, `Knife`, `1H_Wand`, `2H_Staff`, `1H_Crossbow`, `2H_Crossbow`; five shields; `Knight_Helmet`, `Barbarian_Hat`, `Mage_Hat`, skeleton helmet, hood and hat; five capes.

|Item|KayKit mesh|KayKit lacks → fallback|
|---|---|---|
|iron_longsword, wardens_brand|`1H_Sword`|rune glow → emission uniform|
|twin_fangs, frostbite_pair|`Knife` ×1.4; `Knife_Offhand` on the back|dual clips wait for S6|
|pyre_greatsword, stormcleaver|`2H_Sword`|one-handed until S6 (Q4)|
|heater, buckler, tower_shield|`Badge_Shield`, `Round_Shield`, `Rectangle_Shield` ×1.25|heraldry → identity tint|
|plain_sallet|`Knight_Helmet`|plume → `MeshKit.horn` on `head`|
|watchers_helm|none|`MeshKit.lathe` great helm and fin (placeholder_visual.gd:191,201)|
|duelists_hood|`Rogue_Head_Hooded`|-|
|worn_plate, wardens_plate|Knight body: Steel; Blackened with Ember|spikes → `MeshKit.horn` on `upperarm`|
|duelists_leathers|Rogue body, `Rogue_Cape`|-|
|hunters_bow|no bow; `2H_Crossbow`|Q2|
|throwing_knives|`Throwable`|belt → `MeshKit.blade` on `hips`|
|spells|`Spellbook` while casting|hip orb → SphereMesh|
|cape|`Knight_Cape` (rigid)|code cape with the cloth shader (placeholder_visual.gd:84,226)|
|rings|none|dropped: under 0.05 m (Art Bible 7)|

Skeleton gear (`Skeleton_Blade`, `_Axe`, `_Staff`, `_Crossbow`, `_Shield_Large_A`) is separate files; `MeshKit.cleaver`, horns and crown stay for brutes and bosses. Both attach to `handslot.r` or `head`: untested, first job of R1.

## 3. State to clip

**Duel timings are law.** Each attack clip is cut into windup **W**, strike **S** and recovery **R**. `windup(dir, d)` plays W so it ends at 0.6 × d (speed clamped 0.3-3×), then holds. `strike` plays S in 0.05 s (the active window), so contact is 0.05 s after the call (today: 0.1 s). R runs at 1× until the next call. `slash` skips W and plays S in its `duration`. Default blend 0.12 s; into `strike`, `slash`, `hit`: 0.03 s.

|Direction|Clip (length)|W|S|R|Windup pose, seen from the player|
|---|---|---|---|---|---|
|RIGHT, `slash` R|`1H_Melee_Attack_Slice_Horizontal` (1.07)|0-0.20|0.20-0.30|0.30-1.07|blade level, screen right|
|LEFT, `slash` L|the same clip, **reversed**|1.07→0.40|0.40→0.27|0.27→0|blade level, far screen left|
|OVER, `slash` D|`1H_Melee_Attack_Chop` (1.07)|0-0.53|0.53-0.60|0.60-1.07|blade above the head|
|THRUST, `slash` U|`1H_Melee_Attack_Stab` (1.60)|0-0.33|0.33-0.47|0.87-1.60|blade drawn back, point at you|

Every KayKit swing travels the same way, and a mirrored clip would move the sword to the shield hand. Reversing the horizontal slice gives a true opposite sweep with the right hand at no cost. `RigOffsets` adds chest yaw ±20° toward the windup side; the tell colour and strike trail stay as today. `1H_Melee_Attack_Slice_Diagonal` stays out of enemy tells: it starts right and ends low.

|State (call)|Clip|Warp and blend|
|---|---|---|
|idle|`Idle`; unarmed `Unarmed_Idle`|loop; 0.2|
|walk (`set_walk` × `set_pace` ≤ 0.75)|`Walking_A` (natural stride 0.75 u/s)|rate 0.8-2.2×, from walk × pace|
|run|`Running_A`|rate 1.0-1.6×, from pace; feet slide (Q3)|
|sprint (S1)|`Running_A`|1.6×, spine pitch 12°|
|dash (S1), IN, BACK (S3)|`Dodge_Forward`, `Dodge_Backward`|0.40 → 0.22 s|
|dodge −1, +1|`Dodge_Left`, `Dodge_Right`|0.40 → 0.46 s; the clip's 0.69 u hip travel is stripped (the duel tweens `position:x`)|
|parry −1, +1|S of the LEFT, RIGHT slice, stopped at 0.27 for 0.08 s|white trail|
|block|`Blocking`|loop; 0.1|
|guard|`Block_Hit` 0-0.35|1.5×|
|hit ±1|`Hit_A` (heavy `Hit_B`)|1.5×; chest yaw 16° × dir|
|stagger|`Hit_B` 0-0.27, hold|**no reel loop**: sway from `RigOffsets`|
|broken|`PickUp` 0-0.50 in 0.3 s, hold|**no kneel**: author 2 poses if it reads weak|
|finisher|attacker `1H_Melee_Attack_Stab` (holds 0.47-0.87); victim `Death_B`|**no paired clip**|
|death|`Death_A` (0.8), hold|1×|
|get-up|`Lie_StandUp` (2.33)|2×; else 0.25 s fade, as today|
|feint|none|S nudged 0.05 s and back over `hold`|
|taunt, victory|`Taunt` (skeleton pack only; plays on every base), `Cheer`|1×|
|shoot|`2H_Ranged_Aiming` hold, `2H_Ranged_Shoot` (release ≈0.15), `2H_Ranged_Reload` 0-0.5|aim fills the windup|
|throw|`Throw`|release 0.72|
|cast|`Spellcast_Raise` 0-0.55, `Spellcast_Shoot` (release ≈0.2); rune drawing `Spellcasting`|raise fills the windup|
|gather|wood, ore `1H_Melee_Attack_Chop`; herbs `PickUp`; fishing `Interact`|contact at `duration`|
|sit|`Sit_Chair_Down`, `Sit_Chair_Idle`, `Sit_Chair_StandUp`|loop the middle|

## 4. Memory and cost

- **Atlases: five 256 px RGBA8 without mipmaps, 0.26 MB each, 1.3 MB total**, against 5.3 MB per 1024 px copy. Flat swatches lose nothing visible (R1 diffs a close shot). Characters therefore need no VRAM compression. Proven: skinned KayKit renders in headless Chromium; ETC2 and S3TC load there. Unproven: everything on the iPhone.
- **Duplicates:** `rig_pack.py` strips images from every `.glb`; atlases import once as standalone PNGs. The dungeon pieces need the same step.
- **Clips:** constant tracks removed (about 100 of 123 per clip), importer optimiser on; 15-19 KB per clip on disk, so ≤50 clips ≈ 0.9 MB. A character file without clips ≈ 0.19 MB.
- **Hero + 3 foes + 8 villagers + 6 players:** atlases and masks 1.4 MB; 6 meshes 3 MB est.; 18 instances 5 MB est.; library 2 MB est.; gear 0.5 MB est. **About 12 MB; gate at 20 MB** across crumb `tex`, `vid` and `ms`.
- **Draw calls:** today 38 per starting hero (counted in `_build`), up to about 50, doubled by shadows. New: 2 skinned + ≤5 gear = ≤7; shadows for hero and current foe only, blob quads for the rest. 18 fighters: ≤140 against about 1,400.
- **Cap: 6 distinct character meshes loaded.** A seventh request reuses the nearest loaded base with its own palette.

## 5. The look

- **Remap** (Art Bible 2.2): mask R metal → `metal_tint` × atlas luminance; G cloth and leather → `identity`; unmasked keeps atlas colour at S × 0.7, V × 0.85; B emissive, which gives skeleton eyes for free.
- **No maps:** roughness and metallic are constants per mask channel: metal 0.45 and 0.60 (blade 0.30 and 0.85), cloth 0.90, leather and bone 0.70.
- **Rim:** 0.5 hero, 0.7 current foe, 0 elsewhere.
- **Heads:** `RigOffsets` scales `head` to 0.85. Helmets hang from that bone and shrink with it; no other bone moves; the figure loses about 0.17 u. Faces go dark through a mask alpha island. Show the owner the V6 duel shot three ways (as shipped; 0.85 with shadowed faces; plus a closed code-built helm) and a 5 s chop loop.
- **Tiers:** grunt = a skeleton base, Blackened, one accent, glowing eyes, hunch 10°, scale 1.0-1.15. Elite = Knight, Barbarian or `Rogue_Hooded`, face shadowed, one signature (`Spike_Shield`, `Barbarian_Hat`, MeshKit horns), 1.2-1.35. Boss = `2H_Sword`, crown and cape, own key light, 1.5-1.8.

## 6. Stages

Each ships dark behind `Run.data.rig` (pause menu) and `--rig`.

|Stage|Files|Tier|Needs|Bot check|Owner on the phone|
|---|---|---|---|---|---|
|**R1** class, pipeline, one knight|`tools/rig_pack.py`, `assets/rig/*`, `rig_visual.gd`, `rig_clips.gd`, `rig_offsets.gd`, `shaders/fighter.gdshader`, overworld.gd (`--looktest=rig`, `rig18`)|Opus|-|new `check.js rig`: every action and direction runs; tip is left, right, above, centred per direction; contact 0.05 ± 0.02 s after `strike`; 8 bases agree within 1 mm; two rigs add ≤1 MB of `tex`|`rig18` with `?perf=1`: fps and crumb heap; picks the head (Q1)|
|**R2** hero in the world|fighter_visual.gd (factory), overworld.gd:158, world.gd:86, run.gd, hud.gd:595, `rig_looks.gd`|Sonnet|R1, S1|`load`, `tour`, `gather` pass with `--rig`; bag shots of 6 weapons, 3 shields, 3 helms each differ over ≥8% of the hero|10 minutes roaming; heap ≤ +10 MB against off; gait (Q3)|
|**R3** duel, hero and thrall|`rig_clips.gd`, duel.gd:203-218|Opus|R2, S2|the five `duel-*` scenarios pass with `--rig`; with a fixed seed the damage log equals flag off; the foe's tip stays outside the hero's screen rectangle at scales 1.1, 1.45, 1.85|names 40 windups, ≥38 right; parry feel|
|**R4** every enemy by data|`rig_looks.gd`, overworld_interact.gd:23, world.gd:359, duel_stage.gd (`set_focus`)|Sonnet|R3|every `Land.FOES` id and encounter kind spawns and is shot; ≤6 bases loaded|grunt, elite, boss tell apart|
|**R5** villagers, players|overworld_places.gd:58,100,152; world.gd:367; overworld_remote.gd:31|Sonnet|R4|`pvp` passes; 18-fighter village: draw calls ≤ flag off, `tex` ≤ +3 MB|two phones, 15 minutes, no reload|
|**R6** remove the old|delete placeholder_visual.gd, anim_pack_visual.gd, the scene, the flag|Sonnet|owner approval|full `check.js`; no `PlaceholderVisual` left|sign-off|

Order: S1 ∥ R1 → R2 → S2 → R3 → S3 ∥ R4 → S4 (`shoot`, `cast`) → R5 → S5 → S6 (`2H_`, `Dualwield_` sets) → R6 → S7. R3 also runs on today's calls if S2 slips.

## 7. Risks

|Risk|Retire by|
|---|---|
|Skinning cost on the iPhone (Compatibility is believed to add one pass per skinned surface)|R1 `rig18` on the phone; fallbacks: lower rate, N = 12|
|Per-instance memory unknown|R1 crumbs at 1, 6 and 18 rigs|
|The reversed slice reads oddly|R3 owner test; fallback: author one clip|
|The hero's head hides a LEFT windup (enemy tip reaches 2.2 u × scale)|R3 rectangle check; fallback: hero x −1.2 → −1.6|
|Short legs: natural walk 0.75 u/s against 5-12.5 u/s|R2; Q3|
|Non-KayKit weapons on `handslot.r`|R1 attaches `MeshKit.blade` and `Skeleton_Blade`|
|Section play with blends and reverse on web|R1 bot|
|AnimationTree cost, if S4 forces layering|R1 `rig18` also runs a hero-only tree|
|Enemy scale 1.85 makes a 4.3 u figure|R4 shots; cap the look scale|
|itch.io animation pack names differ|unused; names live only in `rig_clips.gd`|
|PvP latency|visuals start on arrival and the defender's clock rules (COMBAT_RULES 4.5); a `strike` with no windup plays S from the coil|

## 8. Owner questions

1. **Heads and faces?** (a) As shipped: no work, friendliest. (b) Head 0.85, faces in shadow: darker, no new geometry. (c) As (b), plus closed code-built helms on hero and elites: darkest, mixes two styles. **Recommend (b).**
2. **Hunter's Bow: KayKit has only crossbows.** (a) Show the crossbow, rename the item: fits the clips. (b) Keep a code-built bow in the crossbow pose: looks wrong. (c) Author a draw clip at S4: extra work. **Recommend (a).**
3. **The run.** (a) Cap leg speed at 1.6×: a quick scurry with some slide. (b) No cap: legs blur. (c) Slow the world about 25%: changes S1's numbers. **Recommend (a).**
4. **Greatswords and twin blades with a shield.** (a) One-handed clips for every weapon, shield kept, as today. (b) At S6 the shield goes to the back and two-handed and dual clips play. **Recommend (a) now, (b) at S6.**
