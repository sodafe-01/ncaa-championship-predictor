# DE-04 — Data-quality gate from the Knowledge Catalog scans

**Lane:** DE1 · **Depends on:** DE-01, DE-03 · **Unblocks:** DE-07 (which seasons models may use), the dashboard's data-quality page, the Captain's Catalog story · **Task:** T2

## Goal

Turn the organizers' Dataplex profile scans into a queryable profile plus a per-season gate that decides which seasons the models may use. This is the "metadata-driven quality gate" in the pitch.

## Files you own

- `models/01_dq/dq_column_profile.sql`
- `models/01_dq/dq_season_gate.sql`
- `models/01_dq/_dq.yml`
- `data_tests/dq_season_gate_expectations.sql`

## Inputs

`source('ncaa_scans', 'ncaa_basketball_20_sample_scans')`, `source('ncaa_basketball', 'tables_meta')` (the dataset's `__TABLES__`: `table_id`, `row_count`), `ref('stg_games')`, `ref('stg_team_games')`, `ref('stg_player_games')`.

## Output contract

### `dq_column_profile` — one row per scanned table × column (latest scan)

| Column | Type | Rule |
|---|---|---|
| table_name | STRING | `data_source.table_id` |
| column_name, column_type, column_mode | STRING | |
| percent_null | FLOAT64 | as reported by the scan (0–100 scale) |
| percent_unique | FLOAT64 | |
| min_value, max_value, average_value, standard_deviation | FLOAT64 | |
| quartile_lower, quartile_median, quartile_upper | FLOAT64 | |
| top_values | ARRAY<STRUCT<value STRING, count INT64, percent FLOAT64>> | `top_n` |
| rows_scanned | INT64 | `job_rows_scanned` |
| table_row_count | INT64 | from `tables_meta` |
| sample_fraction | FLOAT64 | rows_scanned / table_row_count (≈0.2 for `mbb_pbp_sr`, 1.0 for the rest) |
| scanned_at | TIMESTAMP | `job_start_time` |
| is_high_null | BOOL | `percent_null > 50` |

Latest scan only: `QUALIFY ROW_NUMBER() OVER (PARTITION BY table_name, column_name ORDER BY job_start_time DESC) = 1`.

### `dq_season_gate` — one row per Sportradar season (2013–2017)

| Column | Type | Rule |
|---|---|---|
| season, season_label | | |
| games, closed_games | INT64 | from `stg_games` |
| d1_teams | INT64 | distinct D1 `team_id` in `stg_team_games` |
| ncaa_games | INT64 | `postseason_kind = 'NCAA'` |
| ncaa_complete | BOOL | `ncaa_games = 67` |
| d1_team_games | INT64 | closed D1-vs-D1 team rows |
| box_stats_rate | FLOAT64 | share of those rows with `has_box_stats` |
| stats_usable | BOOL | `box_stats_rate >= 0.95` |
| played_player_rows | INT64 | |
| class_rate | FLOAT64 | share of played rows with `class` |
| class_usable | BOOL | `class_rate >= 0.9` |
| minutes_rate | FLOAT64 | share of played rows with `minutes` |
| catalog_class_percent_null | FLOAT64 | `dq_column_profile` value for `mbb_players_games_sr.class`: the Catalog flagged it before we did |
| model_ready | BOOL | `stats_usable AND ncaa_complete AND d1_teams = 351` |
| gate_note | STRING | plain-English reason, e.g. '2013-14: 66% of box scores missing' |

## Tests first

`models/01_dq/_dq.yml` (describe every column):

```yaml
version: 2
models:
  - name: dq_column_profile
    data_tests:
      - unique_combination_of_columns: {arguments: {combination_of_columns: [table_name, column_name]}}
      - row_count_between: {arguments: {min_count: 400, max_count: 505}}
    columns:
      - name: sample_fraction
        data_tests:
          - accepted_range: {arguments: {min_value: 0, max_value: 1.01}}
  - name: dq_season_gate
    data_tests:
      - row_count_between: {arguments: {min_count: 5, max_count: 5}}
    columns:
      - name: season
        data_tests: [unique, not_null]
```

`data_tests/dq_season_gate_expectations.sql`:

```sql
-- Verified expectations: 2013-14 unusable (box scores 66% missing); 2014-15..2017-18 model-ready; class only in 2017-18
SELECT season, stats_usable, class_usable, ncaa_complete, model_ready
FROM {{ ref('dq_season_gate') }}
WHERE NOT ncaa_complete
   OR (season = 2013 AND (stats_usable OR model_ready))
   OR (season BETWEEN 2014 AND 2017 AND NOT model_ready)
   OR (season < 2017 AND class_usable)
   OR (season = 2017 AND NOT class_usable)
```

## Done when

```bash
scripts/dbt.sh build --select dq_column_profile dq_season_gate
scripts/verify.sh
```

## Report back

- The five-row gate table.
- The 10 columns with the highest `percent_null` in `dq_column_profile`.

## Out of scope

Writing tags or aspects into Knowledge Catalog (we don't have permission; descriptions flow through BigQuery instead).
