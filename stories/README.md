# Data-engineering stories

The ordered backlog for the two data engineers (lanes **DE1** and **DE2**) and any Claude session helping them. Build in dependency order. **This table is the status source of truth.**

Pick up work with `/story next DE1`, `/story next DE2`, or `/story DE-NN`. The skill (`.claude/skills/story/SKILL.md`) picks the first story whose dependencies are done, builds it test-first, verifies it and updates this table.

| Order | ID | Story | Lane | Depends on | Unblocks | Status |
|---|---|---|---|---|---|---|
| 0 | [DE-00](DE-00-scaffold.md) | dbt scaffold, sources, shared macros and tests | Integrator | — | everything | done |
| 1 | [DE-01](DE-01-core-staging.md) | Core staging: `stg_teams`, `stg_games`, `stg_team_games` | DE1 | DE-00 | every story | todo |
| 2 | [DE-02](DE-02-report-card-contract.md) | Report-card contract: `f_team_season` columns + skeleton | DE2 | DE-01 | ML1, ML2, AE | todo |
| 3 | [DE-03](DE-03-history-staging.md) | More staging: player games, tournament history, season history | DE1 | DE-01 | DE-04, DE-06, DE-07, DE-08, DE-10 | todo |
| 4 | [DE-04](DE-04-dq-gate.md) | Data-quality gate from the Knowledge Catalog scans | DE1 | DE-01, DE-03 | DE-07 | todo |
| 5 | [DE-05](DE-05-game-efficiency.md) | Per-game efficiency: `f_team_game_efficiency` | DE2 | DE-01 | DE-07 | todo |
| 6 | [DE-06](DE-06-roster-continuity.md) | Roster continuity: `f_roster_continuity` | DE2 | DE-03 | DE-07 | todo |
| 7 | [DE-07](DE-07-report-card.md) | Full report card: `f_team_season` | DE2 | DE-02, DE-03, DE-04, DE-05, DE-06 | DE-09, DE-10, ML1, ML2, AE | todo |
| 8 | [DE-08](DE-08-bracket.md) | Brackets: `stg_bracket` | DE1 | DE-01, DE-03 | ML2 simulation | todo |
| 9 | [DE-09](DE-09-matchups.md) | Matchup rows: `f_matchups` | DE2 | DE-07 | ML1 | todo |
| 10 | [DE-10](DE-10-marts-v1.md) | Marts v1: team profile, conference, league | DE2 | DE-03, DE-07 | AE dashboard, Captain's agent | todo |
| 11 | [DE-11](DE-11-marts-v2.md) | Marts v2: title odds, backtests, scouting, agent Q&A | DE2 | DE-10 + ML1 T6–T7, ML2 T8–T10, AE T11–T13 | dashboard, agent, pitch | todo |

Status values: `todo` · `in-progress` · `blocked (reason)` · `done`. The `f_team_season` column contract is **not frozen yet** (DE-02 freezes it).

## Two lanes in parallel

- **DE1:** DE-01 → DE-03 → DE-04 → DE-08, then help with DE-10 descriptions and the Captain's Knowledge Catalog work.
- **DE2:** DE-02 (write the contract while DE-01 builds) → DE-05 → DE-06 → DE-07 → DE-09 → DE-10 → DE-11.

DE-01 is the only story that blocks everyone. Do it first.

## Definition of done (every story)

1. Tests written first, exactly as the story's **Tests first** section lists, then the models.
2. `scripts/dbt.sh build --select <the story's models>` finishes with 0 errors and 0 test failures.
3. `scripts/verify.sh` passes.
4. Every model and every column has a YAML description. `persist_docs` copies them to BigQuery, where Knowledge Catalog and the Data Agent read them.
5. The story's **Report back** items are answered with real numbers.
6. Status is updated here. A contract change (new, renamed or retyped column) is approved by the integrator first and written into the story and `docs/design.md`.
7. Anything new or surprising goes into `docs/learnings.md`.

## Rules that save time

- Build only your own models: `scripts/dbt.sh build --select stg_games stg_team_games`. Don't use `+model` graph selectors; they rebuild other people's models.
- Use `source()`, `ref()` and `macros/conventions.sql`. Never re-derive season labels, NCAA rounds, neutral sites or possessions.
- Generic tests available: `unique`, `not_null`, `accepted_values`, `relationships`, plus `unique_combination_of_columns`, `expression_is_true`, `row_count_between` and `accepted_range` from `macros/generic_tests.sql`. Pass arguments under `arguments:`.
- If the data contradicts a story's expectation, stop and report the query and numbers. Never loosen a test to pass.
- Staging (`stg_`) keeps every row; features (`f_`) filter to model seasons and D1 games.
