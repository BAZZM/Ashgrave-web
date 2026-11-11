# Ashgrave

A Godot 4.4.1 web game. This repo is both the source and the published site:
the built files sit at the repo root, so whatever is on `main` is what players
load (the `.nojekyll` file and root layout point to GitHub Pages from `main`;
the Pages settings themselves have not been checked from here).

## Layout

- `game/` — the game's source, laid out exactly as the engine sees `res://`.
  - `game/scripts/*.gd` — all gameplay code. Almost everything, including
    meshes and UI, is built in code here.
  - `game/project.godot` — project settings and the `Online` autoload.
  - `game/scenes/*.tscn.remap`, `game/.godot/` — scenes, sounds and the font in
    Godot's already-imported binary form. Treat these as fixed assets.
- `game_<hash>.wasm` — the built game data: a Godot pack of `game/`, named
  `.wasm` only so the host serves it. Generated; never edit by hand.
- `part0.wasm`–`part2.wasm`, `index.js`, `index.audio*.js` — the stock Godot
  4.4.1 web engine (no threads), split in three. `index.html` stitches the
  parts back together and maps `index.pck` to the current `game_<hash>.wasm`.
- `tools/build.py` — packs `game/` and updates `index.html`.
- `tools/smoke.js` — loads the build in headless Chromium, fails on script errors.

## Working on the game

Edit `game/scripts/`, then:

```bash
python3 tools/build.py
```

```bash
node tools/smoke.js
```

Commit the source change together with the new `game_<hash>.wasm` and the
`index.html` change that `build.py` makes. `python3 tools/build.py --check`
tells you whether the committed pack matches `game/`.

Scripts ship as plain text and the engine compiles them on load, so no Godot
install is needed to build. A script with a parse error only fails when the
game first loads it, so run the smoke test and exercise the feature you touched.

## Things to know

- The source in `game/scripts/` was recovered from the Build 10 pack, which
  held compiled scripts. The code is exact, but the original comments and
  blank-line layout are gone. If the original Godot project turns up, prefer it.
- Adding a new scene, sound or font needs the Godot editor to import it; none
  is installed here. New content built in code needs nothing.
- Online play (`game/scripts/online.gd`) uses public MQTT brokers as relays.
  `?relay=ws://host:port` on the page URL replaces the relay list
  (comma-separated for several), which is how to test against a local broker.
  `--autoplay=pvp_a` / `--autoplay=pvp_b` in the `args` of `GODOT_CONFIG`
  (after a `--`) make two clients challenge and duel each other unattended.
- Saves live in the browser's localStorage. Keep the save format in
  `game/scripts/run.gd` backward compatible.
- Players on an older build stay in the same shared world until they reload,
  so keep the message format in `online.gd` compatible across builds.
