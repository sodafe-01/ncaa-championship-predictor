# DE-07 — Full report card: `f_team_season`

**Lane:** DE2 · **Depends on:** DE-02, DE-03, DE-04, DE-05, DE-06 · **Unblocks:** DE-09, DE-10, ML1, ML2, AE · **Task:** T4 (part 4)

## Goal

Fill every column of the frozen DE-02 contract with real numbers. `adj_net` becomes the team-strength rating used by the model, the simulation and the story.

## As built (2026-09-16)

Built and verified: 47/47 tests pass (DE-02 tests, the column tests below, the sanity test and the join-coverage test). Column names, types and order are unchanged. Differences and findings:

1. **`tempo` is per 40 minutes.** `AVG(game_poss)` counts overtime games as longer games and put Savannah State 2017-18 at 85.64, over the 55–85 test. Each game's possessions are scaled by `40 / (40 + 5 × overtime periods)` before averaging (Savannah State: 84.55; regulation-only games 84.24). The test is unchanged.
2. **`hca` is 0.036–0.040, not 0.015–0.02:** 0.0383 / 0.0361 / 0.0368 / 0.0403 in `full` for 2014-15 to 2017-18, with `pre_ncaa` within 0.0005. The raw home/away `oe` ratio also carries schedule strength (stronger teams host weaker ones), which pushes it up. The formula is kept as written; revisit only with integrator approval.
3. **Convergence:** the largest change in `adj_net` between passes 9 and 10 is 0.10–0.15 points per 100 possessions.
4. Record columns keep the DE-02 logic, so the 6 CIT first-round games DE-05 excludes (played the Monday before the First Four) still count in those teams' `pre_ncaa` records but not in their efficiency.
5. Seasons come from `dq_season_gate.model_ready`; `experience_index` uses the gate's `class_usable` (2017-18 only).

## Files you own

- `models/02_features/f_team_season.sql` (replace the skeleton)
- `models/02_features/_f_team_season.yml` (add tests and descriptions; don't rename or retype columns)
- `data_tests/f_team_season_sanity.sql`
- `data_tests/f_team_season_tournament_join_coverage.sql`

## Inputs

`ref('f_team_game_efficiency')`, `ref('f_roster_continuity')`, `ref('dq_season_gate')`, `ref('stg_team_games')`, `ref('stg_games')`, `ref('stg_player_games')`, `ref('stg_team_season_history')`.

## How to compute

1. **Seasons:** only seasons where `dq_season_gate.model_ready` (2014–2017).
2. **Rows per scope:** `pre_ncaa` uses `in_pre_ncaa_scope`; `full` uses every row. Efficiency columns use only `is_valid_efficiency_row`.
3. **Record columns** (`games` … `win_pct`): keep the DE-02 logic (closed games with a result, any opponent).
4. **Raw efficiency and tempo:** `raw_oe = 100 * SUM(points) / SUM(game_poss)`, `raw_de` likewise, `raw_net = raw_oe - raw_de`, `tempo = AVG(game_poss)`, `d1_games = COUNT(*)`.
5. **Venue adjustment:** per season × scope, `hca = SQRT(AVG(oe | home) / AVG(oe | away)) - 1` over non-neutral rows (expect roughly 0.015–0.02). Neutralize each row: home `oe_n = oe / (1 + hca)`, `de_n = de * (1 + hca)`; away `oe_n = oe * (1 + hca)`, `de_n = de / (1 + hca)`; neutral unchanged. `is_neutral` is best-effort (DE-01): 2.6% of regular-season games are flagged neutral and some neutral-site events count as home or away, which can pull `hca` slightly low. Report it.
6. **Opponent adjustment, 10 passes with a Jinja loop:** `lg` = league average `oe` for the season × scope. Start with `adj_oe_0 = AVG(oe_n)` and `adj_de_0 = AVG(de_n)` per team. On pass k, for each row: `g_oe = oe_n * lg / opp_adj_de_(k-1)` and `g_de = de_n * lg / opp_adj_oe_(k-1)`. The team's `adj_oe_k` is the `game_poss`-weighted average of `g_oe` (same for `adj_de_k`). Then rescale so the team averages of both equal `lg`. Generate the CTEs with `{% for k in range(1, 11) %}`.
7. `adj_net = adj_oe - adj_de`; `sos_adj_net` = average of the opponents' final `adj_net` over the team's rows.
8. **`conference_strength`:** after final `adj_net`, calculate `AVG(adj_net) OVER (PARTITION BY season, scope, conf_alias)`. Include every team in the conference so every member receives the same conference-season-scope value. DE2 owns this calculation; ML2 consumes it for the forward projection.
9. **Four factors and shooting:** from season sums, never averages of per-game rates (formulas in the DE-02 contract).
10. **`last10_net`:** the team's last 10 rows in scope by `game_seq`: `100 * (SUM(points) - SUM(opp_points)) / SUM(game_poss)`.
11. **`ap_rank_last`:** the team's AP rank (`home_ap_rank` or `away_ap_rank` in `stg_games`, for its side) in its last closed game in scope; NULL when unranked.
12. **`experience_index`:** 2017 only: `SUM(class_rank * minutes) / SUM(minutes)` over played rows with a class, games in scope.
13. **`ret_min_share`, `ret_pts_share`, `ret_basis`:** from `f_roster_continuity`, same values in both scopes.
14. **`program_win_pct_5y`:** `stg_team_season_history` seasons s−5 to s−1: `SUM(wins) / SUM(wins + losses)`.
15. **`rank_adj_net`:** `RANK() OVER (PARTITION BY season, scope ORDER BY adj_net DESC)`.
16. **Percentiles:** `PERCENT_RANK()` over season × scope, ordered so 1 = best: ascending for higher-is-better metrics, descending for `adj_de`, `tov_pct` and `opp_efg_pct`; `tempo` ascending, so 1 = fastest.

Use the most common per-game `conf_alias` from DE-02. It is the best available source value and may not perfectly reproduce historical conference membership; preserve that caveat in the YAML description.

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
      - name: conference_strength
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
  SELECT 'conference_strength differs within conference or from conference mean',
    CONCAT(CAST(season AS STRING), ' ', scope, ' ', conf_alias)
  FROM s
  GROUP BY season, scope, conf_alias
  HAVING MAX(conference_strength) - MIN(conference_strength) > 1e-9
     OR ABS(ANY_VALUE(conference_strength) - AVG(adj_net)) > 1e-9
  UNION ALL
  SELECT 'Villanova 2017-18 not top 5 before the tournament', CAST(s.rank_adj_net AS STRING)
  FROM s JOIN {{ ref('stg_teams') }} t ON t.team_id = s.team_id
  WHERE s.season = 2017 AND s.scope = 'pre_ncaa' AND t.alias = 'VILL' AND s.rank_adj_net > 5
  UNION ALL
  SELECT 'champion ranked outside the top 30 before its tournament',
    CONCAT(CAST(s.season AS STRING), ' rank ', CAST(s.rank_adj_net AS STRING))
  FROM s JOIN {{ ref('stg_games') }} g
    ON g.season = s.season AND g.ncaa_round = 'FINAL' AND g.winner_team_id = s.team_id
  WHERE s.scope = 'pre_ncaa' AND s.season BETWEEN 2014 AND 2016 AND s.rank_adj_net > 30
)
SELECT * FROM checks
```

`data_tests/f_team_season_tournament_join_coverage.sql`:

```sql
-- At least 95% of teams in each core tournament have a pre-NCAA feature row.
-- Widen the season filter to 2017 when the March 2018 backtest extension is attempted.
WITH participants AS (
  SELECT g.season, team_id
  FROM {{ ref('stg_games') }} g,
    UNNEST([g.home_team_id, g.away_team_id]) AS team_id
  WHERE g.postseason_kind = 'NCAA' AND g.season BETWEEN 2014 AND 2016
  GROUP BY g.season, team_id
), coverage AS (
  SELECT p.season, COUNT(*) AS participants, COUNTIF(f.team_id IS NOT NULL) AS matched
  FROM participants p
  LEFT JOIN {{ ref('f_team_season') }} f
    ON f.season = p.season AND f.team_id = p.team_id AND f.scope = 'pre_ncaa'
  GROUP BY p.season
)
SELECT season, participants, matched, SAFE_DIVIDE(matched, participants) AS join_rate
FROM coverage
WHERE SAFE_DIVIDE(matched, participants) < 0.95
```

## Done when

```bash
scripts/dbt.sh build --select f_team_season
scripts/verify.sh
```

## Report back

- Top 10 by `adj_net`, 2017-18 `pre_ncaa` (team, `adj_oe`, `adj_de`, `adj_net`, rank).
- Core tournament-team feature join rates for 2014-15 through 2016-17; report 2017-18 separately only with the 2018 backtest extension.
- Conference rankings by `conference_strength`, with the source-provenance caveat.
- Pre-tournament rank of each core champion, 2014-15 to 2016-17; add 2017-18 only with the extension.
- `hca` per season, and the largest change in `adj_net` between passes 9 and 10 (convergence).

## Out of scope

Projecting 2018-19 strength (ML2) and matchup rows (DE-09).
