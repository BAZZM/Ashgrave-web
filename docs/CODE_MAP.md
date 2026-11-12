# Code map

What each script in `game/scripts/` is responsible for, and which Wave 1 track
owns it. Tracks: **Smoothness**, **Battle**, **Traversal**, **World** (world and
quests), **Visual** (visual polish). "Shared" means more than one track edits it;
agree changes with the orchestrator first.

## How the split scripts fit together

`overworld.gd` (class `Overworld`) and `duel.gd` (class `Duel`) are still the
scene roots and still hold the state other scripts read (`world_hud.gd` reads
`world.hero_pos`, `world.ents`, ...; `hud.gd` reads `duel.e_state`, `duel.p_hp`, ...).
Their logic now lives in part scripts:

- Each part `extends Node`, has no `class_name`, and is loaded with
  `const X := preload("res://scripts/x.gd")` in its owner. The owner creates the
  parts at the top of `_ready()` as `X.new(self)` and adds them as children, so
  they are freed with it (timer lambdas inside a part die with the owner, as
  they did before the split).
- A part reaches its owner through `ow` (overworld parts) or `d` (duel parts),
  and the other parts through the owner: `ow.terrain._blocked(p)`,
  `d.fx._burst(pos, 8)`. Parts have no `_process`; the owner calls them in a
  fixed order from its own `_process`.
- State used by more than one part, or read from outside, stays on the owner.
  A part keeps only the fields nobody else touches.
- Do not add a `class_name` to a new script: there is no editor here to
  regenerate `game/.godot/global_script_class_cache.cfg`. Use `preload`.
- **The engine does not catch a misspelt member on `d.` or `ow.` at load**
  (tested: `d.statz` in a part loaded and ran without error until that line ran).
  A bare undeclared identifier is caught at load. So after moving or renaming a
  field, grep every `d.<name>` / `ow.<name>` / `duel.<name>` / `world.<name>`.

## Overworld (the open land)

| File | Responsible for | Track |
|---|---|---|
| `overworld.gd` | Scene root, class `Overworld`. Shared state, command-line parsing, scene setup in `_ready`, the per-frame order in `_process`, biome change, the periodic save (every 5 s), `_collect_ents`, the map texture (`build_map`, used by `world_hud.gd`). Thin forwarders `prompt`, `interact`, `pvp_answer`, `duel_done` that the HUD and duel call by name. | Shared (Smoothness for the save; anyone adding a part) |
| `overworld_terrain.gd` | Chunk streaming (`_update_chunks`, `LOAD_R`), ground mesh, scatter tables and MultiMesh batching, gatherable nodes, fishing spots, wild-foe and beast spawn records, beast meshes, obstacle collision (`_blocked`). | Smoothness |
| `overworld_kit.gd` | Static mesh and material cache (`mat`, `mesh`) and the `_part` helper, used by terrain and places. | Shared (Smoothness, Visual) |
| `overworld_places.gd` | Built-in-code places: the tower and its gate, houses, village stalls and NPC figures (`NPC_LOOKS`), crafting stations, braziers, shrine/altar/stones/watchtower, villager walkers and their loops. | World |
| `overworld_interact.gd` | What is near the hero each frame (`_check_surroundings`: foes spawning, chasing and starting a duel, beasts, node respawn, quest `on_reach`, last safe spot), the action prompt, `interact` (talk, shop, craft, chest, stones crossing, entering the tower), gathering, taskmaster, hunting with ranged gear. | World (foe chase radius is Battle's call) |
| `overworld_hero.gd` | Hero movement from stick/keys (`SPEED`, agility XP from walking) and the follow camera, including the bag/shop showcase camera. | Traversal |
| `overworld_remote.gd` | Publishing our position to the relay and showing other players: spawning, easing toward their last position, despawning. Also the `pvp_a` test bot's auto-challenge. | Smoothness |
| `overworld_duels.gd` | Starting a duel against wild foes (pack grouping), cleaning up after it, the PvP handshake (challenge/attack/accept/decline/busy messages) and the PvP aftermath. | Battle |
| `overworld_sky.gd` | Sky, sun, ambient light and fog by time of day and biome, rain and its fog. | Visual |
| `overworld_bot.gd` | Test bots in the land (`tour`, `gather`) and screenshot timing for `--shot`. | Shared (tooling; whoever changes what a bot relies on) |

## Duel (the directional fight)

| File | Responsible for | Track |
|---|---|---|
| `duel.gd` | Scene root, class `Duel`. All duel state the HUD reads, setup from gear and stats, the player's state and timers, every input (`input_swipe`, dodge, block, super, ranged, spell, potion), parry and slash rules and combos, damage both ways, element effects, spare/throne endings, rewards, result and handing back to the host. | Battle |
| `duel_enemy.gd` | The enemy's state machine (intro, idle, windup with feints, strike, recover, open, finisher), combo choice, tutorial pacing, how a strike resolves against dodge/block/guard, and the side foes' attacks in a pack. | Battle |
| `duel_stage.gd` | Placing the duel in the world (ground height from the host, reparenting fighters in and out), seating side foes, switching target. | Battle |
| `duel_pvp.gd` | The player-vs-player turn protocol over the relay: turns, attack/result/ping/dead messages, leaving. Message format must stay compatible across builds. | Battle |
| `duel_fx.gd` | Duel camera (moves, shake, sway), hit sparks, hitstop and slow motion (`_slow`, `_hitstop`, `_restore_time`), phone vibration. | Battle (feel pass); Visual for hit effects |
| `duel_bot.gd` | Duel test bots (solo and PvP) and screenshot timing for `--shot`. | Shared (tooling) |
| `hud.gd` | Duel HUD: bars, tells, buttons, swipe input, result screen. Reads many `Duel` fields. | Battle |
| `arena.gd` | Backdrop of the standalone duel scene (`duel.tscn`). | Visual |

## Everything else

| File | Responsible for | Track |
|---|---|---|
| `world.gd` | The tower interior (class `World`): tiers, movement, entities, duels hosted inside it. Unsplit. | Shared (World, Traversal, Battle) |
| `world_hud.gd` | HUD for both the land and the tower: stick, prompts, labels, and the bag, shop, skills, quests, map, players and craft screens. Unsplit and touched by most tracks. | Shared |
| `tiers.gd` | Tower tier layouts, themes and entities as data. | World |
| `land.gd` | The land as data and functions: biomes, river, lake, roads, heights, colours, places, foes. | World (heights/colours: Smoothness, Visual) |
| `quests.gd` | Quest steps, NPC talk, kill/reach hooks. | World |
| `story.gd` | Inscriptions, enemy barks, heir letters. | World |
| `run.gd` | The save and character progress (`Run`): stats, skills, items, rewards. Save format only grows. | Shared |
| `items.gd` | Item tables and hero look from gear. | Battle (weapons), World |
| `craft.gd` | Skills, XP curve, recipes. | World |
| `enemy_def.gd`, `attack_def.gd` | Enemy and attack definitions (combos, timings, damage). | Battle |
| `placeholder_visual.gd`, `fighter_visual.gd`, `anim_pack_visual.gd` | Character models built in code and their animation; `FighterVisual` is the interface the duel uses. | Smoothness (mesh count), Battle (animation feel) |
| `mesh_kit.gd` | Static mesh builders (lathe, tube, horn, blades). | Shared |
| `online.gd` | Autoload: relay connections, presence, direct messages. Message format must stay compatible. | Battle (PvP), Smoothness |
| `perf.gd` | Autoload: on-screen performance readout (`?perf=1`, off by default). Always on (web): the crash breadcrumb in localStorage (a write every 4 s, a per-frame clock check) and the report of the previous run's death; the page half lives in the inline script at the top of `index.html`. | Smoothness |
| `sfx.gd` | Plays the imported sound effects (`res://audio/`) and the ambience loop. New sounds need the editor. | Battle, Visual |
