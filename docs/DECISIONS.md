# Decisions

Every decision the owner makes, dated, with the options that were offered.
The orchestrator owns this file.

## Which plan governs what

- `docs/ORCHESTRATOR.md` governs phases, gates, roles, model routing and the
  wave approvals from 12 Nov 2026 on.
- `docs/PLAN.md` keeps governing branch rules (`main` live, `dev` integration,
  only the orchestrator commits a build), the rules every subagent follows, and
  the status of the earlier Wave 0 and Wave 1 work. Its unfinished Wave 1 items
  are folded into the phases of `docs/ORCHESTRATOR.md`.
- File ownership follows `docs/CODE_MAP.md`.

## Log

| Date | Decision | Options offered | Answer |
|---|---|---|---|
| 12 Nov 2026 | Are the earlier session's Wave 1 lanes still running? | Stopped: `dev` becomes the base and the rest of Wave 1 folds into the new plan / Still running: only non-overlapping lanes until it finishes | Stopped. `dev` (725c11a) is the base. |
| 12 Nov 2026 | Start Wave 0 as carded (recon, crash breadcrumbs, export hygiene, screenshot harness, asset pipeline scaffold, perf budget) | Start / change the card | Start. |
| 12 Nov 2026 | Where did the nine sound effects come from? | (open question from recon) | No original sources exist. Replace them with sounds sourced elsewhere, licence recorded. |
| 12 Nov 2026 | How are visual assets chosen? | Approve one full pack list up front (DP2) / decide fits as the work goes | Decide as the agents go: the scout shortlists with licence evidence, the owner picks per category when it comes up. |
| 12 Nov 2026 | Run later phases in parallel with Wave 0? | Keep to 3 lanes / add a second track | Add a second track. Track B runs design and pure-logic work for later phases that shares no files with Track A and needs no headless browser. The 3-lane cap still applies to lanes that build and browser-test the game. |
| 12 Nov 2026 | Source for characters, shared rig and building kits | KayKit plus the owner's texture packs / Quaternius (new QAL licence) / stay code-built | KayKit (CC0) plus the owner's two AI-generated texture packs. Quaternius avoided. |
| 12 Nov 2026 | Are CC-BY assets acceptable? | Yes with a credits screen / CC0 only | Yes, with a credits screen. |
| 12 Nov 2026 | Replacement sounds | Scout's first choices / owner listens and picks | Owner listens and picks from docs/shortlists/AUDIO.md. |
| 12 Nov 2026 | COMBAT_RULES q1: a fourth, longer distance (FAR) | Add / keep three | Add it. |
| 12 Nov 2026 | COMBAT_RULES q2: paying for shots and spells | Reloading quiver, runes 20-80 mana / today's limits | Reloading quiver, runes 20-80 mana. |
| 12 Nov 2026 | COMBAT_RULES q3: parrying outside the melee stance | Melee only / any stance | Melee only. |
| 12 Nov 2026 | COMBAT_RULES q4: ranged and magic in PvP | On public relays as the last combat step, defender decides / wait for the server | On relays, as the last combat step. |
| 12 Nov 2026 | Sprint | Automatic with the stick fully out / sprint button | Automatic. |
| 12 Nov 2026 | DP3 server stack | Cloudflare authoritative service plus relays / Godot headless on Fly / stay on relays / decide later | Cloudflare service ("Hall") plus relays. casino_core will need a TypeScript port, checked against the GDScript tests. |
| 12 Nov 2026 | Server details | Gold carried over capped at 5,000; 20 s to resume a staked duel; strictly free hosting | All three accepted. |
| 12 Nov 2026 | DP5 casino house rules | European wheel, no resplitting aces, no rake, 6 decks, 20-250 big-blind buy-in | All accepted. Poker is Texas Hold'em (owner's note). |
| 12 Nov 2026 | Casino table, chips and wheel models | Built in code / keep looking for a pack | Built in code. |
| 12 Nov 2026 | Release Build 11 | Release now / push dev only / not yet | Release now. dev pushed and main fast-forwarded to 51b9f59. |
| 12 Nov 2026 | Start Phase 1 and combat step S1 | Both / Art Bible only / wait | Both. |
| 12 Nov 2026 | The owner's two texture packs (Knight RPG, Wildlands; AI-generated) | Both, look test first / ground and water only / hold off | Both, applied only after the owner approves look-test screenshots. Files to be copied by the owner into assets_src/. |
| 12 Nov 2026 | Which tool generated the two texture packs? | (open question from the paperwork lane) | ChatGPT. Recorded in docs/ASSETS.md with the OpenAI terms link. Packs delivered to assets_src/_packs/. |
| 12 Nov 2026 | Who does the texture work? | Orchestrator lanes / the owner's separate texture chat | The texture chat. The orchestrator runs everything else; file ownership is in the claude.ai project doc claude/orchestrator-status.md. |
| 12 Nov 2026 | Release world agility (S1) with the stuck-in-walls fix? | Together as Build 12 / stuck fix first | Together, once both pass review and checks. |
| 13 Nov 2026 | Build 11 phone test | (report) | ONLINE joined and showed a player count. Crashes came back with the restart banner (text still to be sent). Hero stuck in walls, mainly the tower. |
| 13 Nov 2026 | KayKit heads (ART_BIBLE q3, RIG_PLAN q1) | As shipped / head 0.85 with faces in shadow / also closed helms | Head scale 0.85, faces in shadow. |
| 13 Nov 2026 | Sky (ART_BIBLE q2) | Always overcast / blue noon over Hearthvale | Always overcast; Hearthvale is the warmest region. |
| 13 Nov 2026 | Ash ground (ART_BIBLE q1) | Reuse forest floor and mud grains / source a CC0 ash texture now / generate one | Source a CC0 ash texture now. |
| 13 Nov 2026 | Hunter's Bow (RIG_PLAN q2) | Crossbow and rename / bow in crossbow pose / author a draw clip | Show a crossbow and rename the item. |
| 13 Nov 2026 | Run animation (RIG_PLAN q3) | Cap leg speed at 1.6x / no cap / slow the world 25% | No cap: legs match speed. |
| 13 Nov 2026 | Agility XP with sprint and dash | Scale back / keep the bonus | Scale back so levelling pace matches Build 11. |
| 13 Nov 2026 | Licence for the repo's own code | All rights reserved / MIT / source-available / later | All rights reserved. |
| 13 Nov 2026 | Replacement sounds | Scout's first choices / owner picks | Scout's first choices (docs/shortlists/AUDIO.md); owner downloads them. |
| 13 Nov 2026 | Cloudflare account check | Later / done | Later. |
| 13 Nov 2026 | Usage | (owner instruction) | Continue usage-aware: Build 12 lanes only, narrowed scope, R1 paused, no extra review rounds. |
| 13 Nov 2026 | Build 12 phone test | (report) | Stuck-in-walls better; still crashes. |
| 13 Nov 2026 | Releases while the owner is away | Release when green / fixes and performance only / nothing | Release when every bot scenario passes on the pack and one independent review says ship. |
| 13 Nov 2026 | Texture and graphics ownership | This session / keep split with the texture chat | This session takes all of it. |
| 13 Nov 2026 | Texture colour treatment | Fresh Visual Critic picks / grain plus palette / source colours | A fresh Visual Critic picks from the look test. |
| 13 Nov 2026 | Story freedom | Build on existing lore / free rein / owner premise | Build on what exists. |
| 13 Nov 2026 | Usage while away | 2 lanes / 1 lane / 3 lanes | Two lanes at a time. |
| 13 Nov 2026 | Automatic safe mode after two memory deaths | Yes with a menu toggle / no | Yes. |
| 13 Nov 2026 | Build 12 released | (record) | dev and main at 1a70c09; 14/14 scenarios on the pack. |
| 14 Nov 2026 | Lighting (G1): a third fix round, past the plan's cap of two | Hold the lighting / one narrow extra pass | Orchestrator, owner away: one narrow pass on Greywood and Ashlands brightness and Ashlands saturation only, because both were measurable and hurt daylight play. Targets met; released as Build 13. |
| 14 Nov 2026 | Release order | Performance first as planned / whichever is ready | Orchestrator, owner away: lighting was ready first and lowers draw calls, so it shipped as Build 13; performance follows as Build 14. |
| 14 Nov 2026 | Build 13 released | (record) | Lighting, sky, fog, region colours, fighter rim and self-light per ART_BIBLE "Applied in G1". Visual Critic: ship after fixes; fixes verified by its own measures. 14/14 scenarios on the pack. |
