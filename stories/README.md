# Data-engineering stories

The ordered backlog for the two data engineers (lanes **DE1** and **DE2**) and any Claude session helping them. Build in dependency order. **This table is the status source of truth.**

Pick up work with `/story next DE1`, `/story next DE2`, or `/story DE-NN`. The skill (`.claude/skills/story/SKILL.md`) picks the first story whose dependencies are done, builds it test-first, verifies it and updates this table.

Paths in the stories are relative to `dbt/`: `models/00_stg/` means `dbt/models/00_stg/`.

| Order | ID | Story | Lane | Depends on | Unblocks | Status |
|---|---|---|---|---|---|---|
| 0 | [DE-00](DE-00-scaffold.md) | dbt scaffold, sources, shared macros and tests | Integrator | — | everything | done |
| 1 | [DE-01](DE-01-core-staging.md) | Core staging: `stg_teams`, `stg_games`, `stg_team_games` | DE1 | DE-00 | every story | done |
| 2 | [DE-02](DE-02-report-card-contract.md) | Report-card contract: `f_team_season` columns + skeleton | DE2 | DE-01 | ML1, ML2, AE | done |
| 3 | [DE-03](DE-03-history-staging.md) | More staging: player games, tournament history, season history | DE1 | DE-01 | DE-04, DE-06, DE-07, DE-08, DE-10 | done |
| 4 | [DE-04](DE-04-dq-gate.md) | Data-quality gate from the Knowledge Catalog scans | DE1 | DE-01, DE-03 | DE-07 | done |
| 5 | [DE-05](DE-05-game-efficiency.md) | Per-game efficiency: `f_team_game_efficiency` | DE2 | DE-01 | DE-07 | done |
| 6 | [DE-06](DE-06-roster-continuity.md) | Roster continuity: `f_roster_continuity` | DE2 | DE-03 | DE-07 | done |
| 7 | [DE-07](DE-07-report-card.md) | Full report card: `f_team_season` | DE2 | DE-02, DE-03, DE-04, DE-05, DE-06 | DE-09, DE-10, ML1, ML2, AE | done |
| 8 | [DE-08](DE-08-bracket.md) | Brackets: `stg_bracket` | DE1 | DE-01, DE-03 | ML2 simulation | done |
| 9 | [DE-09](DE-09-matchups.md) | Matchup rows: `f_matchups` | DE2 | DE-07 | ML1 | in-progress |
| 10 | [DE-10](DE-10-marts-v1.md) | Marts v1: team profile, conference, league | DE2 | DE-03, DE-07 | AE dashboard, Captain's agent | todo |
| 11 | [DE-11](DE-11-marts-v2.md) | Marts v2: title odds, backtests, scouting, agent Q&A | DE2 | DE-10 + ML1 T6–T7, ML2 T8–T10, AE T11–T13 | dashboard, agent, pitch | todo |

Status values: `todo` · `in-progress` · `blocked (reason)` · `done`. The `f_team_season` column names in `models/02_features/_f_team_season.yml` are the contract; **frozen**.

## Coverage priority

Build and validate all pre-2018 tournament work first. For backtests, 2015–2017 (canonical `season` 2014–2016) are core; the March 2018 tournament (`season = 2017`, SR-only and seedless) is a last, time-permitting extension. The 2017-18 **pre-NCAA** snapshot is still core because ML2 needs it for the 2018-19 forecast—do not interpret the optional 2018 backtest as permission to omit that input.

## Open decisions

- **Possessions coefficient.** `macros/conventions.sql` uses 0.44 × FTA; the planning docs used 0.475. Every figure in these stories is measured with 0.44. Changing it is a shared-macro change: get integrator approval, then rebuild from DE-01 on.

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
- Generic tests available: `unique`, `not_null`, `accepted_values`, `relationships`, plus `unique_combination_of_columns`, `expression_is_true`, `row_count_between` and `accepted_range` from `macros/generic_tests.sql`. Pass arguments under `arguments:`. In this repo `row_count_between` has no `where` argument, so filter it with `config: {where: ...}`; `expression_is_true` lets rows through when the expression is NULL, so add `not_null` wherever a NULL would be a bug.
- If the data contradicts a story's expectation, stop and report the query and numbers. Never loosen a test to pass.
- Staging (`stg_`) keeps every source row, including the four non-closed games. Game-derived features, models and evaluations use only `is_closed` rows unless a story explicitly says otherwise.
- Records and features also need a result (`win IS NOT NULL`, or `winner_team_id IS NOT NULL` in `stg_games`): one closed 2015-16 game is recorded 0–0.
- Scores are final scores (`points_game`). `has_box_stats` is FALSE for missing or zero-filled box scores; filter on it before using any box-score column.
- `pre_ncaa` is always `scheduled_date <` that season's first proper NCAA tournament game. This retains conference tournaments and excludes NCAA/NIT/CBI/CIT games on or after the cutoff.
- Team-season conference is the most common per-game `conf_alias`, not the current master value. It is the best available source signal, not audited historical membership; every downstream description and narrative keeps that caveat.
