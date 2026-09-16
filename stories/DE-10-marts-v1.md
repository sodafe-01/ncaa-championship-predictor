# DE-10 — Marts v1: `mart_team_profile`, `mart_conference_season`, `mart_league_season`

**Lane:** DE2 (DE1 pairs on descriptions) · **Depends on:** DE-03, DE-07 · **Unblocks:** the AE's dashboard (Team and League pages), the Captain's Data Agent · **Task:** T14 (part 1)

## Goal

Plain-English, fully documented tables that Looker Studio and the Data Agent read directly. Column names are words an executive would use. Every column has a description; those descriptions become the agent's vocabulary and show up in Knowledge Catalog.

## Files you own

- `models/06_marts/mart_team_profile.sql`
- `models/06_marts/mart_conference_season.sql`
- `models/06_marts/mart_league_season.sql`
- `models/06_marts/_marts_v1.yml`
- `data_tests/marts_have_column_descriptions.sql`

## Inputs

`ref('f_team_season')`, `ref('stg_teams')`, `ref('stg_games')`, `ref('stg_team_games')`, `ref('stg_tournament_teams')`.

## Output contract

No `SELECT *`. Seasons 2014–2017.

### `mart_team_profile` — one row per season × team (351 per season)

Ratings come from the `pre_ncaa` scope (what was known before the tournament); the final record comes from `full`.

| Column | Type | Source |
|---|---|---|
| season, season_label, team_id | | |
| team_name | STRING | `stg_teams.display_name` ('Villanova Wildcats') |
| school, alias, conference | STRING | `market`, `alias`, best-available per-game `conf_alias` that season; not audited historical membership |
| color_hex, logo_url | STRING | `stg_teams.color_hex`, `logo_medium` |
| wins, losses, win_pct | | full scope |
| pre_tourney_wins, pre_tourney_losses | INT64 | pre_ncaa scope |
| adj_offense, adj_defense, adj_margin | FLOAT64 | `adj_oe`, `adj_de`, `adj_net` |
| strength_rank | INT64 | `rank_adj_net` |
| tempo, efg_pct, turnover_pct, off_rebound_pct, ft_rate, opp_efg_pct, three_point_rate, three_point_pct | FLOAT64 | report-card columns |
| schedule_strength | FLOAT64 | `sos_adj_net` |
| conference_strength | FLOAT64 | conference mean `adj_net` from `f_team_season` |
| last10_margin | FLOAT64 | `last10_net` |
| ap_rank_before_tourney | INT64 | `ap_rank_last` |
| returning_minutes_share | FLOAT64 | `ret_min_share` |
| returning_basis | STRING | `ret_basis` |
| experience_index | FLOAT64 | |
| program_win_pct_5y | FLOAT64 | |
| pctl_offense, pctl_defense, pctl_margin, pctl_tempo, pctl_shooting, pctl_ball_security, pctl_off_rebounding, pctl_three_point_rate | FLOAT64 | `pctl_adj_oe`, `pctl_adj_de`, `pctl_adj_net`, `pctl_tempo`, `pctl_efg_pct`, `pctl_tov_pct`, `pctl_orb_pct`, `pctl_three_par` |
| made_ncaa | BOOL | appeared in an NCAA tournament game that season |
| ncaa_seed | INT64 | `stg_tournament_teams` (2014-15 to 2016-17); NULL for 2017-18 |
| ncaa_wins | INT64 | NCAA wins that season, First Four excluded |
| ncaa_last_round | STRING | furthest round played |
| is_champion | BOOL | |

### `mart_conference_season` — one row per season × conference

| Column | Type | Rule |
|---|---|---|
| season, season_label, conference | | |
| teams | INT64 | |
| avg_adj_margin | FLOAT64 | |
| conference_rank | INT64 | 1 = highest `avg_adj_margin` |
| best_team_name | STRING | |
| best_team_adj_margin | FLOAT64 | |
| top25_teams | INT64 | teams with `strength_rank <= 25` |
| ncaa_bids | INT64 | |
| ncaa_wins | INT64 | |
| final_four_teams | INT64 | |
| champion_from_conference | BOOL | |

### `mart_league_season` — one row per season

| Column | Type | Rule |
|---|---|---|
| season, season_label | | |
| teams | INT64 | 351 |
| avg_tempo, avg_efg_pct, avg_three_point_rate, avg_three_point_pct, avg_ft_rate, avg_turnover_pct | FLOAT64 | league averages, pre_ncaa scope |
| home_win_pct | FLOAT64 | home-team win share in non-neutral regular-season D1 games |
| home_margin | FLOAT64 | average home margin in those games |
| parity_sd_adj_margin | FLOAT64 | standard deviation of `adj_margin` (lower = more parity) |
| top10_gap | FLOAT64 | average `adj_margin` of the top 10 minus the median team's |
| ncaa_upset_rate | FLOAT64 | share of NCAA games from the round of 64 on won by the worse seed; NULL for 2017-18 (no seeds) |
| ncaa_avg_margin | FLOAT64 | |
| champion_name | STRING | |
| champion_pre_tourney_rank | INT64 | |

**Conference provenance:** `conference` and every conference aggregation use the report card's most common per-game `conf_alias`, not the current-master value from `stg_teams`. YAML descriptions and dashboard/agent language must say that historical membership is best available and may not perfectly reflect realignment.

## Tests first

`models/06_marts/_marts_v1.yml` (describe every column in plain English):

```yaml
version: 2
models:
  - name: mart_team_profile
    data_tests:
      - unique_combination_of_columns: {arguments: {combination_of_columns: [season, team_id]}}
      - row_count_between: {arguments: {min_count: 351, max_count: 351, group_by: [season]}}
      - row_count_between: {arguments: {min_count: 1, max_count: 1, group_by: [season], where: "is_champion"}}
      - expression_is_true: {arguments: {expression: "ncaa_seed IS NULL", where: "season = 2017"}}
    columns:
      - name: team_name
        data_tests: [not_null]
      - name: adj_margin
        data_tests: [not_null]
      - name: strength_rank
        data_tests: [not_null]
  - name: mart_conference_season
    data_tests:
      - unique_combination_of_columns: {arguments: {combination_of_columns: [season, conference]}}
  - name: mart_league_season
    data_tests:
      - row_count_between: {arguments: {min_count: 4, max_count: 4}}
    columns:
      - name: season
        data_tests: [unique, not_null]
```

`data_tests/marts_have_column_descriptions.sql` (it also covers the DE-11 marts once they exist):

```sql
-- depends_on: {{ ref('mart_team_profile') }}
-- depends_on: {{ ref('mart_conference_season') }}
-- depends_on: {{ ref('mart_league_season') }}
-- Every mart column must carry a description (persist_docs copies YAML descriptions to BigQuery)
SELECT table_name, column_name
FROM `{{ target.project }}.{{ target.dataset }}`.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
WHERE STARTS_WITH(table_name, 'mart_')
  AND (description IS NULL OR TRIM(description) = '')
```

## Done when

```bash
scripts/dbt.sh build --select mart_team_profile mart_conference_season mart_league_season
scripts/verify.sh
```

## Report back

- 2017-18 top 10 from `mart_team_profile` (team, conference, adj_margin, strength_rank).
- 2017-18 conference ranking.
- Confirmation that conference descriptions include the historical-membership caveat.
- The four-row league trends table.

## Out of scope

Title odds, backtests and AI outputs (DE-11).
