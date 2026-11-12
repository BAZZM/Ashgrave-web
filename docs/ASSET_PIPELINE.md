# Asset pipeline (.glb to web build)

Proven with Godot 4.4.1 headless, on a generated test model (rig, animation, texture).

## Commands
```bash
tools/get_godot.sh /home/claude/godot          # once; or set GODOT=path
python3 tools/test_assets/make_test_glb.py      # writes assets_src/test/assettest.glb
python3 tools/import_assets.py                  # assets_src/** -> game/assets/*.import + game/.godot/imported/*
python3 tools/build.py
node tools/test_assets/shot.js out.png "--assettest=0.25"   # 0.75 for the other pose; no value = animates
```
Sources go in `assets_src/<path>` (git-ignored) and load as `res://assets/<path>`.

## What is committed / packed
- Commit: `game/assets/**/*.import`, `game/.godot/imported/<name>-<hash>.scn|.ctex`, the merged `game/.godot/uid_cache.bin`.
- Never in the pack or repo: the raw .glb/.png, `.md5`, `.godot/editor`, `*.gd.uid`.
- The runtime needs the `.import` of the glb AND of the texture the glb extracts (the scene references the texture by its source path; without that `.import` load fails with "No loader found"). Both `.import` files, the `.scn` and the `.ctex` total 8 KB.
- The test asset (`game/assets/test/`, `game/.godot/imported/assettest*`) is committed. To remove: delete those and `git checkout game/.godot/uid_cache.bin` (while no real assets exist).

## Why import runs in a copy
`import_assets.py` copies `game/` to a temp dir, imports there and copies back only the files above. A direct in-place import adds `.uid` files, `.godot/editor`, and rewrites `uid_cache.bin` with new script uids (different from the ones baked into the shipped scenes). The staged run avoids that; `project.godot` and `global_script_class_cache.cfg` came out unchanged. The existing sounds/font were not deleted even in place, but that is not guaranteed. The tool prints and aborts on Godot errors, except the harmless headless `texture_2d_get` one.
An untouched `game/` still packs to `game_d39387b973.wasm`.

## Texture settings
Godot imported the PNG lossless (`compress/mode=0`, `vram_texture=false`, mipmaps on), RGB8 in the running web build. No S3TC/ETC2/ASTC was produced, so it works anywhere WebGL2 does. Larger textures will want VRAM compression or Basis; that is unproven.
Animation `sway-loop` imports as `sway`, loop on (suffix sets looping).

## Renderer evidence (Chromium, 844x390 CSS, DPR 3)
- Console: `OpenGL ES 3.0 (WebGL 2.0 ...) - Compatibility`; `get_current_rendering_method()=gl_compatibility`, driver `opengl3`, while the project setting says `mobile`. The shipped web build runs Compatibility/WebGL2.
- `window_get_size()=(2532, 1170)` (device pixels), visible rect 1558x720, so `scaling_3d_scale=0.547` (640/1170).
- This is software WebGL, not Safari.

## Pitfalls
- `.glb` embedded images are extracted by the importer; ship their `.import`.

## Unproven
iPhone Safari behaviour, VRAM-compressed textures on web, big models, `.import` tweaks per asset, memory use.
