# DE-05 — Per-game efficiency: `f_team_game_efficiency`

**Lane:** DE2 · **Depends on:** DE-01 · **Unblocks:** DE-07, DE-09 · **Task:** T4 (part 2)

## Goal

One clean row per team per game with possessions and per-100-possession efficiency, ready for the opponent-adjusted ratings in DE-07.

## Files you own

- `models/02_features/f_team_game_efficiency.sql`
- `models/02_features/_f_team_game_efficiency.yml`
- `data_tests/f_team_game_efficiency_mirror.sql`
- `data_tests/f_team_game_efficiency_scope.sql`

## Inputs

`ref('stg_team_games')`, `ref('stg_games')`.

## Output contract

Table. Grain: `game_id` × `team_id`. Rows: closed D1-vs-D1 games with a result (`win IS NOT NULL`) and `has_box_stats`, seasons `var('first_model_season')` to `var('last_season')`.

| Column | Type | Rule |
|---|---|---|
| game_id, season, scheduled_date | | |
| team_id, opp_id, conf_alias, opp_conf_alias | STRING | |
| is_home, is_neutral | BOOL | |
| venue_type | STRING | home, away, neutral |
| postseason_kind, ncaa_round | STRING | |
| first_ncaa_date | DATE | the season's first NCAA tournament game |
| in_pre_ncaa_scope | BOOL | `scheduled_date < first_ncaa_date` |
| game_seq | INT64 | 1 = the team's first game of the season in this table (order by `scheduled_date`, `game_id`) |
| win | BOOL | |
| points, opp_points, margin | INT64 | |
| fgm, fga, tpm, tpa, ftm, fta, orb, drb, tov | INT64 | carried for season sums |
| opp_fgm, opp_fga, opp_tpm, opp_tpa, opp_ftm, opp_fta, opp_orb, opp_drb, opp_tov | INT64 | |
| poss, opp_poss | FLOAT64 | from `stg_team_games` |
| game_poss | FLOAT64 | `(poss + opp_poss) / 2`: the game's possessions, identical for both teams |
| is_valid_efficiency_row | BOOL | `game_poss BETWEEN 45 AND 115` (a few source box scores are broken) |
| oe | FLOAT64 | `100 * points / game_poss` |
| de | FLOAT64 | `100 * opp_points / game_poss` |
| net | FLOAT64 | `oe - de` |
| efg_pct | FLOAT64 | `(fgm + 0.5 * tpm) / fga` |
| tov_pct | FLOAT64 | `tov / game_poss` |
| orb_pct | FLOAT64 | `orb / (orb + opp_drb)` |
| ftr | FLOAT64 | `fta / fga` |
| three_par | FLOAT64 | `tpa / fga` |
| opp_efg_pct, opp_tov_pct, opp_ftr | FLOAT64 | opponent versions |
| drb_pct | FLOAT64 | `drb / (drb + opp_orb)` |

Using the shared `game_poss` makes one team's `oe` equal its opponent's `de`.

## Build notes (verified 2026-09-16)

- Measured on the built DE-01 views with this repo's `possessions` macro (0.44 × FTA): 10,998 / 11,022 / 11,068 / 11,080 rows for 2014-15 to 2017-18, all 351 teams, at least 24 games each.
- Median `game_poss` 66.1–70.5; average `oe` 100.7–103.0 (range 34.8–166.3).
- One broken game remains: 155 possessions in 2014-15 (2 rows outside 45–115). Keep it and flag it with `is_valid_efficiency_row`; DE-07 ignores it. The 30-possession row seen during planning was a zero-filled box score that DE-01's `has_box_stats` now excludes.
- Filter `win IS NOT NULL`. One closed 2015-16 game (UTSA vs Central Arkansas) has a full box score but a recorded 0–0 final score and no result; without the filter its rows fail the `oe` range test.
- Use `SAFE_DIVIDE` for every ratio.

## Tests first

`models/02_features/_f_team_game_efficiency.yml` (describe every column):

```yaml
version: 2
models:
  - name: f_team_game_efficiency
    data_tests:
      - unique_combination_of_columns: {arguments: {combination_of_columns: [game_id, team_id]}}
      - row_count_between: {arguments: {min_count: 2, max_count: 2, group_by: [game_id]}}
      - row_count_between: {arguments: {min_count: 10500, max_count: 11500, group_by: [season]}}
      - row_count_between:
          arguments: {min_count: 0, max_count: 25, group_by: [season]}
          config: {where: "NOT is_valid_efficiency_row"}
      - expression_is_true:
          arguments: {expression: "NOT in_pre_ncaa_scope", where: "postseason_kind = 'NCAA'"}
    columns:
      - name: oe
        data_tests:
          - accepted_range: {arguments: {min_value: 25, max_value: 175, where: "is_valid_efficiency_row"}}
      - name: game_poss
        data_tests: [not_null]
```

The last `row_count_between` returns seasons with *more than 25* invalid rows. Seasons with none don't appear, which passes.

`data_tests/f_team_game_efficiency_scope.sql`:

```sql
-- Feature rows are closed games with a result, and the pre-NCAA flag is exactly the strict date cutoff.
SELECT 'non-closed game reached features' AS failed_check, f.game_id
FROM {{ ref('f_team_game_efficiency') }} f
JOIN {{ ref('stg_games') }} g USING (game_id)
WHERE NOT g.is_closed
UNION ALL
SELECT 'game without a result reached features', game_id
FROM {{ ref('f_team_game_efficiency') }}
WHERE win IS NULL
UNION ALL
SELECT 'pre_ncaa flag differs from first-NCAA-date cutoff', game_id
FROM {{ ref('f_team_game_efficiency') }}
WHERE in_pre_ncaa_scope IS DISTINCT FROM (scheduled_date < first_ncaa_date)
UNION ALL
SELECT 'national postseason game leaked into pre_ncaa', game_id
FROM {{ ref('f_team_game_efficiency') }}
WHERE in_pre_ncaa_scope AND postseason_kind IN ('NCAA', 'NIT', 'CBI', 'CIT')
```

`data_tests/f_team_game_efficiency_mirror.sql`:

```sql
-- A team's offensive efficiency equals its opponent's defensive efficiency in the same game
SELECT a.game_id, a.team_id, a.oe, b.de
FROM {{ ref('f_team_game_efficiency') }} a
JOIN {{ ref('f_team_game_efficiency') }} b ON b.game_id = a.game_id AND b.team_id = a.opp_id
WHERE ABS(a.oe - b.de) > 0.001
```

## Done when

```bash
scripts/dbt.sh build --select f_team_game_efficiency
scripts/verify.sh
```

## Report back

- Rows per season and invalid rows per season.
- Confirmation that the closed-only and strict cutoff test returned zero rows.
- Average `game_poss` and `oe` per season.

## Out of scope

Opponent adjustment and season aggregation (DE-07).
