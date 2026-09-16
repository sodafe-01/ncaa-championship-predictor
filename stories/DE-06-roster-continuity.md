# DE-06 — Roster continuity: `f_roster_continuity`

**Lane:** DE2 · **Depends on:** DE-03 · **Unblocks:** DE-07, ML2's next-season projection · **Task:** T4 (part 3)

## Goal

For each team-season, how much of the team's production comes back next season. It's the only roster signal we have for the 2018-19 forecast.

## Files you own

- `models/02_features/f_roster_continuity.sql`
- `models/02_features/_f_roster_continuity.yml`

## Inputs

`ref('stg_player_games')`, `ref('stg_team_games')` (for the D1 team list).

## Output contract

Table. Grain: `season` × `team_id`. D1 teams (351 per season), seasons 2014–2017.

| Column | Type | Rule |
|---|---|---|
| season | INT64 | the season whose production we measure |
| next_season | INT64 | `season + 1` |
| team_id | STRING | |
| team_minutes | INT64 | minutes by `played` rows, closed games |
| team_points | INT64 | |
| ret_min_share_actual | FLOAT64 | share of `team_minutes` by players who played at least one game for the same team in `next_season`; NULL for 2017 (no next season in the data) |
| ret_pts_share_actual | FLOAT64 | same for points |
| ret_min_share_class | FLOAT64 | share of minutes with a known class played by FR, SO or JR (`class_rank <= 3`); 2017 only |
| ret_pts_share_class | FLOAT64 | same for points |
| ret_min_share | FLOAT64 | `COALESCE(ret_min_share_actual, ret_min_share_class)` |
| ret_pts_share | FLOAT64 | `COALESCE(ret_pts_share_actual, ret_pts_share_class)` |
| ret_basis | STRING | 'actual' or 'class_proxy' |
| minutes_coverage | FLOAT64 | share of played rows with `minutes` |

## Build notes

- Player ids are stable across seasons, so "played for the same team next season" is a join on (`player_id`, `team_id`, `season + 1`).
- Class exists only in 2017-18, and the class proxy can't see early NBA entries or transfers, so it overstates returning production. Report the average actual share (2014–2016) next to the average proxy share (2017) so ML2 can correct for it.
- D1 teams come from `stg_team_games` rows with `division_alias = 'D1'`.

## Tests first

`models/02_features/_f_roster_continuity.yml` (describe every column):

```yaml
version: 2
models:
  - name: f_roster_continuity
    data_tests:
      - unique_combination_of_columns: {arguments: {combination_of_columns: [season, team_id]}}
      - row_count_between: {arguments: {min_count: 351, max_count: 351, group_by: [season]}}
      - expression_is_true: {arguments: {expression: "ret_basis = 'actual'", where: "season < 2017"}}
      - expression_is_true: {arguments: {expression: "ret_basis = 'class_proxy'", where: "season = 2017"}}
    columns:
      - name: ret_min_share
        data_tests:
          - not_null
          - accepted_range: {arguments: {min_value: 0, max_value: 1}}
      - name: ret_pts_share
        data_tests:
          - not_null
          - accepted_range: {arguments: {min_value: 0, max_value: 1}}
      - name: ret_basis
        data_tests:
          - accepted_values: {arguments: {values: ['actual', 'class_proxy']}}
```

## Done when

```bash
scripts/dbt.sh build --select f_roster_continuity
scripts/verify.sh
```

## Report back

- Average `ret_min_share` by season and basis.
- 2017-18 `ret_min_share` for Villanova, Michigan State, Duke, Virginia and Gonzaga.

## Out of scope

Predicting next-season strength (ML2, T10).
