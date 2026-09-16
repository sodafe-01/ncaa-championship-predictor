# DE-01 — Core staging: `stg_teams`, `stg_games`, `stg_team_games`

**Lane:** DE1 · **Depends on:** DE-00 · **Unblocks:** every other story · **Task:** T1 (part 1)

## Goal

Tidy, correctly labeled views over the raw Sportradar tables, so nobody downstream re-derives season labels, tournament rounds, neutral sites or possessions.

## Files you own

- `models/00_stg/stg_teams.sql`
- `models/00_stg/stg_games.sql`
- `models/00_stg/stg_team_games.sql`
- `models/00_stg/_stg_core.yml` (descriptions and tests for all three)
- `data_tests/stg_games_ncaa_rounds_complete.sql`
- `data_tests/stg_team_games_pairs.sql`

## Inputs

`source('ncaa_basketball', …)`: `mbb_teams`, `team_colors`, `mascots`, `mbb_games_sr`, `mbb_teams_games_sr`. Macros in `macros/conventions.sql`.

## Output contract

Views (the folder default). Staging keeps every row; later layers filter.

### `stg_teams` — one row per team (351)

| Column | Type | Rule |
|---|---|---|
| team_id | STRING | `mbb_teams.id` |
| market | STRING | school, e.g. `Villanova` |
| name | STRING | nickname, e.g. `Wildcats` |
| alias | STRING | short code, e.g. `VILL` |
| display_name | STRING | `CONCAT(market, ' ', name)` |
| school_ncaa | STRING | |
| conf_alias, conf_name | STRING | current-master conference as of 2017-18; do not use this as historical membership |
| code_ncaa, kaggle_team_id | INT64 | |
| venue_id, venue_name, venue_city, venue_state | STRING | current home venue, used by the neutral-site rule |
| venue_capacity | INT64 | |
| color_hex | STRING | `team_colors.color`, joined on `id` |
| mascot | STRING | `mascots.mascot`, joined on `id` |
| logo_small, logo_medium, logo_large | STRING | |

### `stg_games` — one row per game (29,805)

| Column | Type | Rule |
|---|---|---|
| game_id | STRING | |
| season | INT64 | start year (2017 = 2017-18) |
| season_label | STRING | `season_label` macro |
| scheduled_date | DATE | |
| gametime | TIMESTAMP | |
| status | STRING | raw |
| is_closed | BOOL | `status = 'closed'` (4 games aren't) |
| has_pbp | BOOL | `coverage = 'full'` |
| tournament, tournament_type, tournament_round | STRING | raw, kept for traceability |
| postseason_kind | STRING | `postseason_kind` macro: REG, CONF, NCAA, NIT, CBI, CIT, OTHER |
| ncaa_round | STRING | `ncaa_round` macro: FF, R64, R32, S16, E8, F4, FINAL; NULL outside the NCAA tournament |
| ncaa_round_order | INT64 | `ncaa_round_order` macro on the computed `ncaa_round` column |
| ncaa_region | STRING | `ncaa_region` macro: EAST, WEST, SOUTH, MIDWEST |
| conference_game | BOOL | |
| neutral_site_raw | BOOL | source `neutral_site` (NULL for 60% of games; unreliable) |
| is_neutral | BOOL | rule below |
| venue_id, venue_name, venue_city, venue_state | STRING | |
| home_team_id, home_market, home_alias, home_conf_alias, home_division_alias | STRING | from `h_*` |
| away_team_id, away_market, away_alias, away_conf_alias, away_division_alias | STRING | from `a_*` |
| home_points, away_points | INT64 | `h_points`, `a_points` |
| home_ap_rank, away_ap_rank | INT64 | `NULLIF(h_rank, 0)`: 0 means unranked |
| winner_team_id | STRING | NULL unless closed with both scores |
| is_d1_matchup | BOOL | both division aliases = `D1` |
| attendance, lead_changes, times_tied, periods | INT64 | |
| is_overtime | BOOL | `periods > 2` |

**`is_neutral` rule.** The source `neutral_site` is missing for 60% of games and marks 137 NCAA-tagged games as not neutral.

```sql
CASE
  WHEN <postseason_kind> = 'NCAA' THEN TRUE
  WHEN g.neutral_site IS NOT NULL THEN g.neutral_site
  WHEN g.venue_id = home_team.venue_id THEN FALSE   -- mbb_teams venue of the home team
  WHEN g.tournament = 'Conference' THEN TRUE
  ELSE FALSE
END
```

### `stg_team_games` — one row per team per game (59,610)

Build from `mbb_teams_games_sr` joined to `stg_games`. Take `season_label`, `postseason_kind`, `ncaa_round`, `ncaa_round_order`, `is_neutral`, `is_closed` and `is_d1_matchup` from `stg_games`; don't re-derive them.

| Column | Type | Rule |
|---|---|---|
| game_id, season, season_label, scheduled_date | | |
| team_id, market, name, alias, conf_alias, division_alias | STRING | source-provided conference on the game row; preferred for team-season grouping, but not audited historical membership |
| opp_id, opp_market, opp_alias, opp_conf_alias, opp_division_alias | STRING | |
| is_home | BOOL | source `home_team` |
| is_neutral | BOOL | from `stg_games` |
| venue_type | STRING | `neutral` when `is_neutral`, else `home` or `away` |
| postseason_kind, ncaa_round, ncaa_round_order, conference_game, is_closed, is_d1_matchup | | from `stg_games` |
| win | BOOL | |
| points, opp_points, margin | INT64 | margin = points − opp_points |
| fgm, fga, tpm, tpa, ftm, fta | INT64 | field goals, three-pointers, free throws |
| orb, drb, reb, team_reb | INT64 | `offensive_rebounds`, `defensive_rebounds`, `rebounds` (players only), `team_rebounds` |
| ast, stl, blk, pf | INT64 | |
| tov | INT64 | `turnovers + COALESCE(team_turnovers, 0)`: source `turnovers` excludes team-charged turnovers |
| opp_fgm, opp_fga, opp_tpm, opp_tpa, opp_ftm, opp_fta, opp_orb, opp_drb, opp_ast, opp_stl, opp_blk, opp_pf | INT64 | |
| opp_tov | INT64 | `opp_turnovers + COALESCE(opp_team_turnovers, 0)` |
| poss, opp_poss | FLOAT64 | `possessions('fga', 'orb', 'tov', 'fta')` and the opponent version |
| has_box_stats | BOOL | fga, orb, tov, fta and all four opponent versions are non-NULL |

## Build notes (verified 2026-09-16)

- Keys are unique in the source: `game_id` in games, (`game_id`, `team_id`) in team games.
- Every season 2013–2017 has 67 NCAA tournament games; the `ncaa_round` macro already handles the old round names in 2013-14 and 2014-15.
- AP rank is 0 for unranked (27,153 home values), maximum 25.
- `mbb_teams` holds the 2017-18 venue, and a few programs changed arenas, so `is_neutral` is a best-effort rule. Report its distribution.
- `mbb_teams.conf_alias` is current-state. Downstream uses the most common per-game `conf_alias` for a team-season, but Sportradar remains best-available rather than authoritative conference history.
- 2013-14 box scores are 66% missing; `has_box_stats` makes that visible without dropping rows.

## Tests first

`models/00_stg/_stg_core.yml` (add a description to every model and column):

```yaml
version: 2
models:
  - name: stg_teams
    data_tests:
      - row_count_between: {arguments: {min_count: 351, max_count: 351}}
    columns:
      - name: team_id
        data_tests: [unique, not_null]
  - name: stg_games
    data_tests:
      - row_count_between: {arguments: {min_count: 29805, max_count: 29805}}
      - row_count_between: {arguments: {min_count: 4, max_count: 4, where: "NOT is_closed"}}
      - expression_is_true: {arguments: {expression: "is_closed = (status = 'closed')"}}
      - expression_is_true:
          arguments: {expression: "ncaa_round IS NOT NULL AND is_neutral", where: "postseason_kind = 'NCAA'"}
    columns:
      - name: game_id
        data_tests: [unique, not_null]
      - name: postseason_kind
        data_tests:
          - accepted_values: {arguments: {values: ['REG', 'CONF', 'NCAA', 'NIT', 'CBI', 'CIT', 'OTHER']}}
      - name: ncaa_round
        data_tests:
          - accepted_values: {arguments: {values: ['FF', 'R64', 'R32', 'S16', 'E8', 'F4', 'FINAL']}}
      - name: home_ap_rank
        data_tests:
          - accepted_range: {arguments: {min_value: 1, max_value: 25}}
  - name: stg_team_games
    data_tests:
      - unique_combination_of_columns: {arguments: {combination_of_columns: [game_id, team_id]}}
      - row_count_between: {arguments: {min_count: 59610, max_count: 59610}}
    columns:
      - name: game_id
        data_tests:
          - relationships: {arguments: {to: "ref('stg_games')", field: game_id}}
      - name: venue_type
        data_tests:
          - accepted_values: {arguments: {values: ['home', 'away', 'neutral']}}
      - name: poss
        data_tests:
          - accepted_range: {arguments: {min_value: 15, max_value: 190, where: "has_box_stats"}}
```

`data_tests/stg_games_ncaa_rounds_complete.sql`:

```sql
-- Every season has a complete NCAA tournament: FF 4, R64 32, R32 16, S16 8, E8 4, F4 2, FINAL 1
WITH rounds AS (
  SELECT 'FF' AS ncaa_round, 4 AS n UNION ALL SELECT 'R64', 32 UNION ALL SELECT 'R32', 16
  UNION ALL SELECT 'S16', 8 UNION ALL SELECT 'E8', 4 UNION ALL SELECT 'F4', 2 UNION ALL SELECT 'FINAL', 1
),
expected AS (
  SELECT season, ncaa_round, n
  FROM UNNEST(GENERATE_ARRAY(2013, {{ var('last_season') }})) AS season CROSS JOIN rounds
),
actual AS (
  SELECT season, ncaa_round, COUNT(*) AS n
  FROM {{ ref('stg_games') }}
  WHERE postseason_kind = 'NCAA'
  GROUP BY season, ncaa_round
)
SELECT COALESCE(e.season, a.season) AS season, COALESCE(e.ncaa_round, a.ncaa_round) AS ncaa_round,
  e.n AS expected_games, a.n AS actual_games
FROM expected e
FULL OUTER JOIN actual a ON a.season = e.season AND a.ncaa_round = e.ncaa_round
WHERE e.n IS DISTINCT FROM a.n
```

`data_tests/stg_team_games_pairs.sql`:

```sql
-- Each game has exactly two team rows matching stg_games, and each decided closed game has one winner
WITH per_game AS (
  SELECT tg.game_id, COUNT(*) AS n_rows, COUNTIF(tg.win) AS n_wins,
    LOGICAL_AND(tg.team_id IN (g.home_team_id, g.away_team_id)) AS teams_match
  FROM {{ ref('stg_team_games') }} tg
  JOIN {{ ref('stg_games') }} g USING (game_id)
  GROUP BY tg.game_id
)
SELECT g.game_id, p.n_rows, p.n_wins, p.teams_match
FROM {{ ref('stg_games') }} g
LEFT JOIN per_game p USING (game_id)
WHERE p.n_rows IS DISTINCT FROM 2
   OR NOT p.teams_match
   OR (g.is_closed AND g.home_points IS NOT NULL AND g.home_points != g.away_points AND p.n_wins != 1)
```

## Done when

```bash
scripts/dbt.sh build --select stg_teams stg_games stg_team_games
scripts/verify.sh
```

Selecting the three models also runs their YAML tests and both singular tests.

## Report back

- Row counts for the three views.
- The four retained non-closed games and their raw statuses.
- `is_neutral` share by `postseason_kind`.
- Share of team-games with `has_box_stats` by season (expect about 0.34 for 2013 and about 1.0 for 2014–2017).

## Out of scope

Filtering to D1 or model seasons (features do that); player, tournament-history and bracket tables (DE-03, DE-08).
