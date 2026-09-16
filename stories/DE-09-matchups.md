# DE-09 — Matchup rows: `f_matchups`

**Lane:** DE2 · **Depends on:** DE-07 · **Unblocks:** ML1's win model and backtests · **Task:** T5

## Goal

One training/scoring row per team per game, with "team A minus team B" feature differences from the pre-tournament report cards, so BigQuery ML can learn P(team A wins).

## Files you own

- `models/02_features/f_matchups.sql`
- `models/02_features/_f_matchups.yml`
- `data_tests/f_matchups_symmetry.sql`

## Inputs

`ref('f_team_game_efficiency')` (the games), `ref('f_team_season')` (scope `pre_ncaa`).

## Output contract

Table. Grain: `game_id` × `team_a_id`. Every row of `f_team_game_efficiency` becomes one row (each game appears twice, once per team as team A). Features always come from the **`pre_ncaa`** report card of the same season, so tournament rows use only pre-tournament information.

Validate tournament scoring rows for `season` 2014–2016 first. Rows for the March 2018 tournament (`season = 2017`) may already flow through the generic model, but they do not become a required backtest input until the final extension; the 2017 pre-NCAA report card remains required for the forward forecast.

| Column | Type | Rule |
|---|---|---|
| game_id, season, scheduled_date | | |
| postseason_kind, ncaa_round | STRING | |
| in_pre_ncaa_scope | BOOL | |
| is_training_row | BOOL | `in_pre_ncaa_scope` |
| is_tournament_row | BOOL | `postseason_kind = 'NCAA'` |
| team_a_id, team_b_id | STRING | |
| venue_a | STRING | home, away or neutral, for team A |
| home_indicator | INT64 | +1 team A at home, −1 team B at home, 0 neutral |
| label_a_wins | INT64 | 1 or 0 |
| margin_a | INT64 | team A points − team B points |
| a_adj_net, b_adj_net | FLOAT64 | for reference |
| d_adj_oe, d_adj_de, d_adj_net, d_tempo, d_efg_pct, d_tov_pct, d_orb_pct, d_ftr, d_opp_efg_pct, d_opp_tov_pct, d_drb_pct, d_opp_ftr, d_three_par, d_sos_adj_net, d_last10_net, d_program_win_pct_5y, d_win_pct | FLOAT64 | team A value − team B value |

Left out on purpose: seeds (not available for the season we forecast), `experience_index` (2017-18 only) and `ret_*` (next-season concepts).

## Build notes

- **In-season leakage:** a regular-season row's `pre_ncaa` report card includes that game. That's acceptable for training but inflates confidence, so ML1 checks calibration on tournament rows, which have none.
- **Walk-forward for ML1:** for backtest season s, train on rows with `season < s OR (season = s AND is_training_row)`; score rows with `season = s AND is_tournament_row`.

## Tests first

`models/02_features/_f_matchups.yml` (describe every column):

```yaml
version: 2
models:
  - name: f_matchups
    data_tests:
      - unique_combination_of_columns: {arguments: {combination_of_columns: [game_id, team_a_id]}}
      - row_count_between: {arguments: {min_count: 2, max_count: 2, group_by: [game_id]}}
      - row_count_between: {arguments: {min_count: 134, max_count: 134, group_by: [season], where: "is_tournament_row AND season BETWEEN 2014 AND 2016"}}
      - expression_is_true: {arguments: {expression: "home_indicator = 0", where: "venue_a = 'neutral'"}}
    columns:
      - name: label_a_wins
        data_tests:
          - accepted_values: {arguments: {values: [0, 1], quote: false}}
      - name: d_adj_net
        data_tests: [not_null]
      - name: d_efg_pct
        data_tests: [not_null]
```

Add `not_null` on every other `d_*` column.

`data_tests/f_matchups_symmetry.sql`:

```sql
-- The two orderings of a game mirror each other
SELECT a.game_id, a.team_a_id
FROM {{ ref('f_matchups') }} a
JOIN {{ ref('f_matchups') }} b ON b.game_id = a.game_id AND b.team_a_id = a.team_b_id
WHERE a.label_a_wins + b.label_a_wins != 1
   OR ABS(a.d_adj_net + b.d_adj_net) > 1e-9
   OR a.home_indicator + b.home_indicator != 0
```

## Done when

```bash
scripts/dbt.sh build --select f_matchups
scripts/verify.sh
```

## Report back

- Rows per season and core tournament rows for `season` 2014–2016 (134 each); report `season = 2017` separately only with the March 2018 extension.
- Share of rows by `venue_a`.

## Out of scope

The prediction grid for every possible tournament pairing (`p_matchup`, ML1).
