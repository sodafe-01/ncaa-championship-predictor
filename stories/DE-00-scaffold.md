# DE-00 — dbt scaffold, sources, shared macros and tests (done)

**Lane:** Integrator · **Done:** 2026-09-16 · **Task:** T0

## What exists

| File | What it does |
|---|---|
| `pyproject.toml` | dbt-core 1.12 + dbt-bigquery 1.12 + ruff. Install with `uv sync`. |
| `dbt_project.yml` | Folder → materialization and tags (`00_stg` views; `01_dq` views; `02_features`, `03_models`, `04_sim`, `05_ai`, `06_marts` tables). `persist_docs` on. Vars: `first_model_season` 2014, `last_season` 2017, `forecast_season` 2018, `sim_seed`, `n_sims`. Singular tests live in `data_tests/`. |
| `profiles.yml` | BigQuery `oauth-secrets`; the token comes from `scripts/dbt.sh`. Dataset `texas_longhorns`, 20 GB bytes-billed cap. |
| `selectors.yml` | Default selector `routine` excludes `tag:ai`, so a bare `dbt build` never calls Gemini. |
| `models/sources.yml` | Sources `ncaa_basketball` (10 tables + `tables_meta` = `__TABLES__`) and `ncaa_scans` (Catalog profile scans), with key tests. |
| `macros/conventions.sql` | `season_label`, `postseason_kind`, `ncaa_round`, `ncaa_round_order`, `ncaa_region`, `hist_round_to_ncaa_round`, `possessions`, `class_rank`. |
| `macros/generic_tests.sql` | `unique_combination_of_columns`, `expression_is_true`, `row_count_between`, `accepted_range`. |
| `scripts/dbt.sh` | Runs dbt with a fresh gcloud token (plain dbt login fails in this project). |
| `scripts/verify.sh` | ruff + `dbt parse` (no BigQuery needed). |

## Verified on 2026-09-16

- `scripts/dbt.sh debug`: connection OK.
- Source key tests: 6/6 PASS (`game_id`, (`game_id`,`team_id`), (`game_id`,`player_id`), team `id`).
- Possessions: this repo's `possessions` macro is `FGA - ORB + TOV + 0.44 * FTA`. The planning docs said 0.475, and no `possessions_formula` test exists; see Open decisions in `README.md`.
- `ncaa_round` + `postseason_kind` on the raw games: FF 4, R64 32, R32 16, S16 8, E8 4, F4 2, FINAL 1 for every season 2013–2017.
- `postseason_kind` counts: REG 27,645 · CONF 1,448 · NCAA 335 · NIT 155 · CIT 131 · CBI 84 · OTHER 7.

## Using the macros

```sql
SELECT
  game_id,
  season,
  {{ season_label('season') }} AS season_label,
  {{ postseason_kind('tournament', 'tournament_type') }} AS postseason_kind,
  {{ ncaa_round('season', 'tournament_type', 'tournament_round') }} AS ncaa_round
FROM {{ source('ncaa_basketball', 'mbb_games_sr') }}
```

Macros take SQL expressions as strings. To use one macro's output inside another (for example `ncaa_round_order`), compute it in an inner CTE and reference the column name.
