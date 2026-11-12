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
