# Rig stage R1: result

Stage R1 of `docs/RIG_PLAN.md`, finished 15 Nov 2026 on `lane/p2-r1-rigvisual` (merged with dev at Build 19). Players see no change: the release pack holds no rig file.

## What was built

- `tools/pack_characters.py` (the plan's `rig_pack.py`) writes `knight.glb`, `skeleton_warrior.glb` (merged Body and Head, no clips, no images), `anims.glb` (16 clips from Skeleton_Warrior), `gear.glb` (Skeleton_Blade) and one 512 px atlas. `tools/import_assets.py` imports the rig meshes without LODs, shadow meshes or tangents (knight 237 to 163 KB).
- `game/scripts/rig_visual.gd`: `RigVisual extends FighterVisual` (by path, no `class_name`). It uses AnimationPlayer section play in manual mode, one shared AnimationLibrary, and static caches for the library, meshes, gear, atlas and shader. Gear hangs on bone attachments. `get_clash_point()` keeps the base formula. `RigVisual.allowed()` reads `Run.quality_allows("models")`. No physics.
- `rig_clips.gd` holds the clip names and section times. `rig_check.gd` and `rig_looktest.gd` are debug only (`--looktest=rig-check|rig-shots|rig18|rig-perf=N|...`). `tools/rig_shots.js` takes the shots and runs the cost tests. The check is `check.js rig`.
- `tools/build.py` leaves `assets/rig/`, `assets/kaykit/` (the p1 probe, 1.24 MB, carried on this branch) and the four rig scripts out of the pack unless you pass `--looktest`.

## Differences from the plan

|Plan|R1|Why|
|---|---|---|
|instance uniforms or one material|two ShaderMaterials per rig (body and gear; weapon), one shared Shader|on the web renderer the instance-uniform buffer ran out ("Too many instances using shader instance variables", 4096 slots)|
|`RigOffsets` SkeletonModifier3D|chest yaw and head scale applied after each manual advance, then undone before the next|this keeps the timing exact under manual ticking. Undoing stops the yaw piling up on clips whose chest track was stripped as constant|
|64 px masks; metal by mask|metal chosen by atlas saturation in the shader|no hand-corrected masks yet (R2/R4)|
|rim 0.5/0.7|PlaceholderVisual's rim, metallic 0.35 and an emission lift of 0.45|needed to meet the lighting rule (see below)|
|`strike` contact 0.05 s|done (`STRIKE_TIME`)|the duel's `duration` (0.1) is ignored for S|
|`shaders/fighter.gdshader`|shader code inline, compiled once|one less file to keep out of the pack|
|nearest 6 every frame, the rest every second frame|every rig ticks every frame|for R5|
|hero-only AnimationTree cost|not measured|for S4, if it is needed|

## Measurements

The `rig` check passes in headless Chromium: 32 actions land their key pose within 0.05 s, strike contact comes at 0.050 s, and the windup tips sit LEFT x +2.15, RIGHT x −1.37, OVER 1.27 above the head, THRUST pointing at the player. The MeshKit blade and Skeleton_Blade stay rigid on `handslot.r`. Knight and skeleton warrior agree to 0.0 mm across 21 deform bones. 20 rebuilds plus 20 new rigs load nothing again, and static memory does not grow.

**Knight on grass:** 1.60× the ground (tools/g3_measure.py), against a target of 1.5. A lift of 0.32 gave 1.20 and 0.5 gave 1.76.

|Rigs|draw calls|tex|buffers|video|frame ms|
|---|---|---|---|---|---|
|1|260|20.55 MB|16.96 MB|37.51 MB|133.0|
|6|385|20.57|17.49|38.06|133.3|
|18|517|20.62|18.75|39.36|133.7|

The first rig adds 1.05 MB of texture (the atlas for four characters). After that each rig adds about 0.1 MB of buffers and about 15 draw calls (shadows included), so 18 rigs cost 3.3 MB of video memory in all. Frame time is pinned at about 133 ms by the software renderer, so it does not show the rigs' cost. The wasm heap stayed at 95.8 MiB. **The iPhone is unmeasured**: `rig18` with `?perf=1` on the phone is the owner's R1 test.

Release pack: 3,568,906 B before, 3,577,658 B after (+8.7 KB of script).

## For R2

Move the rig into the pack (`build.py` `look_test_only()`), add the factory, and fall back to PlaceholderVisual when `allowed()` is false. Gear for items needs `rig_looks.gd`. The idle clip holds the sword level out to the side; consider `Idle_Combat` or another clip. Leg speed tops out at 2.2×.

## Owner questions

- Q1 (heads) blocks R2's hero look.
- Q3 (run) blocks R2's sign-off.
- Q4 (two-handed) blocks R3 for the greatswords.
- Q2 (bow) blocks only S4.
