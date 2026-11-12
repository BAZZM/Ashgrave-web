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
