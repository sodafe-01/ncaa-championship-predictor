# DE-07 — Full report card: `f_team_season`

**Lane:** DE2 · **Depends on:** DE-02, DE-03, DE-04, DE-05, DE-06 · **Unblocks:** DE-09, DE-10, ML1, ML2, AE · **Task:** T4 (part 4)

## Goal

Fill every column of the frozen DE-02 contract with real numbers. `adj_net` becomes the team-strength rating used by the model, the simulation and the story.

## Files you own

- `models/02_features/f_team_season.sql` (replace the skeleton)
- `models/02_features/_f_team_season.yml` (add tests and descriptions; don't rename or retype columns)
- `data_tests/f_team_season_sanity.sql`

## Inputs

`ref('f_team_game_efficiency')`, `ref('f_roster_continuity')`, `ref('dq_season_gate')`, `ref('stg_team_games')`, `ref('stg_games')`, `ref('stg_player_games')`, `ref('stg_team_season_history')`.

## How to compute

1. **Seasons:** only seasons where `dq_season_gate.model_ready` (2014–2017).
2. **Rows per scope:** `pre_ncaa` uses `in_pre_ncaa_scope`; `full` uses every row. Efficiency columns use only `is_valid_efficiency_row`.
3. **Record columns** (`games` … `win_pct`): keep the DE-02 logic (all closed games, any opponent).
4. **Raw efficiency and tempo:** `raw_oe = 100 * SUM(points) / SUM(game_poss)`, `raw_de` likewise, `raw_net = raw_oe - raw_de`, `tempo = AVG(game_poss)`, `d1_games = COUNT(*)`.
5. **Venue adjustment:** per season × scope, `hca = SQRT(AVG(oe | home) / AVG(oe | away)) - 1` over non-neutral rows (expect roughly 0.015–0.02). Neutralize each row: home `oe_n = oe / (1 + hca)`, `de_n = de * (1 + hca)`; away `oe_n = oe * (1 + hca)`, `de_n = de / (1 + hca)`; neutral unchanged.
6. **Opponent adjustment, 10 passes with a Jinja loop:** `lg` = league average `oe` for the season × scope. Start with `adj_oe_0 = AVG(oe_n)` and `adj_de_0 = AVG(de_n)` per team. On pass k, for each row: `g_oe = oe_n * lg / opp_adj_de_(k-1)` and `g_de = de_n * lg / opp_adj_oe_(k-1)`. The team's `adj_oe_k` is the `game_poss`-weighted average of `g_oe` (same for `adj_de_k`). Then rescale so the team averages of both equal `lg`. Generate the CTEs with `{% for k in range(1, 11) %}`.
7. `adj_net = adj_oe - adj_de`; `sos_adj_net` = average of the opponents' final `adj_net` over the team's rows.
8. **Four factors and shooting:** from season sums, never averages of per-game rates (formulas in the DE-02 contract).
9. **`last10_net`:** the team's last 10 rows in scope by `game_seq`: `100 * (SUM(points) - SUM(opp_points)) / SUM(game_poss)`.
10. **`ap_rank_last`:** the team's AP rank (`home_ap_rank` or `away_ap_rank` in `stg_games`, for its side) in its last closed game in scope; NULL when unranked.
11. **`experience_index`:** 2017 only: `SUM(class_rank * minutes) / SUM(minutes)` over played rows with a class, games in scope.
12. **`ret_min_share`, `ret_pts_share`, `ret_basis`:** from `f_roster_continuity`, same values in both scopes.
13. **`program_win_pct_5y`:** `stg_team_season_history` seasons s−5 to s−1: `SUM(wins) / SUM(wins + losses)`.
14. **`rank_adj_net`:** `RANK() OVER (PARTITION BY season, scope ORDER BY adj_net DESC)`.
15. **Percentiles:** `PERCENT_RANK()` over season × scope, ordered so 1 = best: ascending for higher-is-better metrics, descending for `adj_de`, `tov_pct` and `opp_efg_pct`; `tempo` ascending, so 1 = fastest.

## Tests first

Keep the DE-02 tests and add these to `_f_team_season.yml`:

```yaml
    columns:
      - name: adj_oe
        data_tests: [not_null, {accepted_range: {arguments: {min_value: 70, max_value: 140}}}]
      - name: adj_de
        data_tests: [not_null, {accepted_range: {arguments: {min_value: 70, max_value: 140}}}]
      - name: adj_net
        data_tests: [not_null]
      - name: tempo
        data_tests: [not_null, {accepted_range: {arguments: {min_value: 55, max_value: 85}}}]
      - name: efg_pct
        data_tests: [not_null, {accepted_range: {arguments: {min_value: 0.35, max_value: 0.65}}}]
      - name: tov_pct
        data_tests: [{accepted_range: {arguments: {min_value: 0.08, max_value: 0.30}}}]
      - name: orb_pct
        data_tests: [{accepted_range: {arguments: {min_value: 0.12, max_value: 0.50}}}]
      - name: ftr
        data_tests: [{accepted_range: {arguments: {min_value: 0.15, max_value: 0.65}}}]
      - name: three_par
        data_tests: [{accepted_range: {arguments: {min_value: 0.15, max_value: 0.65}}}]
      - name: rank_adj_net
        data_tests: [not_null]
      - name: sos_adj_net
        data_tests: [not_null]
      - name: ret_min_share
        data_tests: [not_null, {accepted_range: {arguments: {min_value: 0, max_value: 1}}}]
      - name: program_win_pct_5y
        data_tests: [not_null, {accepted_range: {arguments: {min_value: 0, max_value: 1}}}]
      - name: experience_index
        data_tests: [{accepted_range: {arguments: {min_value: 1, max_value: 5}}}]
      - name: pctl_adj_net
        data_tests: [{accepted_range: {arguments: {min_value: 0, max_value: 1}}}]
```

Add `accepted_range` 0–1 on every other `pctl_*` column, and these model-level tests:

```yaml
      - expression_is_true: {arguments: {expression: "experience_index IS NULL", where: "season < 2017"}}
      - expression_is_true: {arguments: {expression: "experience_index IS NOT NULL", where: "season = 2017"}}
```

`data_tests/f_team_season_sanity.sql`:

```sql
-- One row per failed sanity check on the rating
WITH s AS (SELECT * FROM {{ ref('f_team_season') }}),
checks AS (
  SELECT 'mean adj_net is not ~0' AS failed_check, CONCAT(CAST(season AS STRING), ' ', scope) AS detail
  FROM s GROUP BY season, scope HAVING ABS(AVG(adj_net)) > 0.5
  UNION ALL
  SELECT 'adj_net weakly correlated with raw_net', CONCAT(CAST(season AS STRING), ' ', scope)
  FROM s GROUP BY season, scope HAVING CORR(adj_net, raw_net) < 0.85
  UNION ALL
  SELECT 'Villanova 2017-18 not top 5 before the tournament', CAST(s.rank_adj_net AS STRING)
  FROM s JOIN {{ ref('stg_teams') }} t ON t.team_id = s.team_id
  WHERE s.season = 2017 AND s.scope = 'pre_ncaa' AND t.alias = 'VILL' AND s.rank_adj_net > 5
  UNION ALL
  SELECT 'champion ranked outside the top 30 before its tournament',
    CONCAT(CAST(s.season AS STRING), ' rank ', CAST(s.rank_adj_net AS STRING))
  FROM s JOIN {{ ref('stg_games') }} g
    ON g.season = s.season AND g.ncaa_round = 'FINAL' AND g.winner_team_id = s.team_id
  WHERE s.scope = 'pre_ncaa' AND s.rank_adj_net > 30
)
SELECT * FROM checks
```

## Done when

```bash
scripts/dbt.sh build --select f_team_season
scripts/verify.sh
```

## Report back

- Top 10 by `adj_net`, 2017-18 `pre_ncaa` (team, `adj_oe`, `adj_de`, `adj_net`, rank).
- Pre-tournament rank of each champion, 2014-15 to 2017-18.
- `hca` per season, and the largest change in `adj_net` between passes 9 and 10 (convergence).

## Out of scope

Projecting 2018-19 strength (ML2) and matchup rows (DE-09).
