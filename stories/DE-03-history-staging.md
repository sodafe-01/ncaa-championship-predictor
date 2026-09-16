# DE-03 — More staging: player games, tournament history, season history

**Lane:** DE1 · **Depends on:** DE-01 · **Unblocks:** DE-04, DE-06, DE-07, DE-08, DE-10 · **Task:** T1 (part 2)

## Goal

Staging for everything that isn't a team box score: players (for roster continuity and experience), historical tournaments (for champions, seeds and baselines) and historical season records (for program strength).

## Files you own

- `models/00_stg/stg_player_games.sql`
- `models/00_stg/stg_tournament_results.sql`
- `models/00_stg/stg_tournament_teams.sql`
- `models/00_stg/stg_team_season_history.sql`
- `models/00_stg/_stg_history.yml`
- `data_tests/stg_tournament_champions_match_games.sql`

## Inputs

`source('ncaa_basketball', …)`: `mbb_players_games_sr`, `mbb_historical_tournament_games`, `mbb_historical_teams_seasons`. `ref('stg_games')`.

## Output contract

### `stg_player_games` — one row per player per game (888,844)

| Column | Type | Rule |
|---|---|---|
| game_id, season, season_label, scheduled_date | | |
| postseason_kind, is_closed | | from `stg_games` |
| team_id, player_id | STRING | |
| full_name | STRING | |
| class | STRING | `NULLIF(class, '')`: FR, SO, JR, SR, GR. Populated only for 2017-18 (80 blank strings there) |
| class_rank | INT64 | `class_rank` macro |
| height_in, weight_lb | INT64 | `height`, `weight` |
| position, primary_position | STRING | |
| is_starter | BOOL | `starter` |
| played | BOOL | |
| minutes | INT64 | `minutes_int64` |
| points, reb, ast, tov, stl, blk, pf, fgm, fga, tpm, tpa, ftm, fta | INT64 | |

### `stg_tournament_results` — one row per historical NCAA tournament game (1985–2017, 2,117 rows)

| Column | Type | Rule |
|---|---|---|
| season | INT64 | **start year = source `season` − 1** (the source uses the end year) |
| season_label | STRING | |
| tournament_year | INT64 | source `season`: the March the games were played |
| ncaa_round | STRING | `hist_round_to_ncaa_round('round')`; round 68 = play-in games |
| ncaa_round_order | INT64 | |
| game_date | DATE | |
| win_team_id, lose_team_id | STRING | |
| win_seed, lose_seed | INT64 | `SAFE_CAST` of the two-digit strings '01'–'16' |
| win_region_code, lose_region_code | STRING | W, X, Y, Z: codes, not region names |
| win_pts, lose_pts, num_ot | INT64 | |
| is_upset | BOOL | `win_seed > lose_seed` |

### `stg_tournament_teams` — one row per team per historical tournament

| Column | Type | Rule |
|---|---|---|
| season, season_label, tournament_year | | as above |
| team_id | STRING | |
| seed | INT64 | |
| region_code | STRING | |
| played_play_in | BOOL | appeared in a round-68 game |
| tournament_wins | INT64 | wins excluding play-in games |
| last_round | STRING | `ncaa_round` of the team's last game |
| is_champion | BOOL | won the FINAL |

### `stg_team_season_history` — one row per team per season (source rows with `team_id`)

| Column | Type | Rule |
|---|---|---|
| season | INT64 | start year (same convention as Sportradar; verified) |
| season_label | STRING | |
| team_id | STRING | |
| market | STRING | long official name |
| wins, losses, ties | INT64 | |
| win_pct | FLOAT64 | `wins / NULLIF(wins + losses, 0)` |
| division | INT64 | |
| current_division | STRING | |

## Build notes (verified 2026-09-16)

- Teams per tournament: 64 (1985–2000), 65 (2001–2010), 68 (2011–2017).
- Seeds are strings '01'–'16' and regions are codes, so attach seeds by (`season`, `team_id`), never by region.
- No duplicate (`season`, `team_id`) in the season history; it ends with 2016-17 and covers all 351 current D1 teams from 2000.
- Maximum player minutes in one game: 58.

## Tests first

`models/00_stg/_stg_history.yml` (describe every column):

```yaml
version: 2
models:
  - name: stg_player_games
    data_tests:
      - unique_combination_of_columns: {arguments: {combination_of_columns: [game_id, player_id]}}
      - row_count_between: {arguments: {min_count: 888844, max_count: 888844}}
    columns:
      - name: class
        data_tests:
          - accepted_values: {arguments: {values: ['FR', 'SO', 'JR', 'SR', 'GR']}}
      - name: minutes
        data_tests:
          - accepted_range: {arguments: {min_value: 0, max_value: 60}}
      - name: game_id
        data_tests:
          - relationships: {arguments: {to: "ref('stg_games')", field: game_id}}
  - name: stg_tournament_results
    data_tests:
      - row_count_between: {arguments: {min_count: 2117, max_count: 2117}}
      - expression_is_true: {arguments: {expression: "season = tournament_year - 1"}}
      - row_count_between:
          arguments: {min_count: 1, max_count: 1, group_by: [tournament_year], where: "ncaa_round = 'FINAL'"}
    columns:
      - name: win_seed
        data_tests:
          - accepted_range: {arguments: {min_value: 1, max_value: 16}}
      - name: ncaa_round
        data_tests:
          - accepted_values: {arguments: {values: ['FF', 'R64', 'R32', 'S16', 'E8', 'F4', 'FINAL']}}
  - name: stg_tournament_teams
    data_tests:
      - unique_combination_of_columns: {arguments: {combination_of_columns: [season, team_id]}}
      - row_count_between: {arguments: {min_count: 64, max_count: 68, group_by: [season]}}
      - row_count_between: {arguments: {min_count: 1, max_count: 1, group_by: [season], where: "is_champion"}}
    columns:
      - name: tournament_wins
        data_tests:
          - accepted_range: {arguments: {min_value: 0, max_value: 6}}
  - name: stg_team_season_history
    data_tests:
      - unique_combination_of_columns: {arguments: {combination_of_columns: [season, team_id]}}
    columns:
      - name: win_pct
        data_tests:
          - accepted_range: {arguments: {min_value: 0, max_value: 1}}
```

`data_tests/stg_tournament_champions_match_games.sql` (the two sources must agree where they overlap):

```sql
-- For tournaments 2014-2017, the historical champion equals the winner of the Sportradar final
SELECT t.tournament_year, t.team_id AS historical_champion, g.winner_team_id AS sportradar_champion
FROM {{ ref('stg_tournament_teams') }} t
JOIN {{ ref('stg_games') }} g ON g.season = t.season AND g.ncaa_round = 'FINAL'
WHERE t.is_champion AND t.team_id IS DISTINCT FROM g.winner_team_id
```

## Done when

```bash
scripts/dbt.sh build --select stg_player_games stg_tournament_results stg_tournament_teams stg_team_season_history
scripts/verify.sh
```

## Report back

- Row counts for the four views.
- Share of played player rows with `class`, by season.
- Result of the champions cross-check (should return no rows).

## Out of scope

Play-by-play (`mbb_pbp_sr`) and the older `mbb_historical_teams_games` table.
