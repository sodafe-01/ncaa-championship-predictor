# DE-02 — Report-card contract: `f_team_season` columns + skeleton

**Lane:** DE2 · **Depends on:** DE-01 · **Unblocks:** ML1, ML2 and AE, who build against these names · **Task:** T4 (part 1)

## Goal

Freeze the report card's column names, types and meanings before any math exists, and publish a skeleton table with the right grain so other stations can start right away. You can write the YAML while DE-01 is still building.

## Files you own

- `models/02_features/f_team_season.sql` (skeleton now; DE-07 fills it in)
- `models/02_features/_f_team_season.yml`

## Inputs

`ref('stg_team_games')`, `ref('stg_games')`.

## Output contract (frozen when this story is done)

Table. Grain: one row per `season` × `scope` × `team_id`. Division I teams only (351 per season). Seasons `var('first_model_season')` to `var('last_season')` (2014–2017).

- `pre_ncaa` scope: closed games dated strictly before that season's first proper NCAA tournament game (conference tournaments included). Use it for anything that predicts the tournament; never approximate this as only `postseason_kind != 'NCAA'`.
- `full` scope: every closed game, postseason included. Use it to describe a finished season.

Columns in this exact order. The skeleton casts NULL for every column filled by a later story.

| Column | Type | Meaning | Filled by |
|---|---|---|---|
| season | INT64 | start year | DE-02 |
| season_label | STRING | e.g. '2017-18' | DE-02 |
| scope | STRING | 'pre_ncaa' or 'full' | DE-02 |
| team_id | STRING | | DE-02 |
| market | STRING | school name | DE-02 |
| alias | STRING | short code | DE-02 |
| conf_alias | STRING | most common per-game `conf_alias` for the team-season; best available, not audited historical membership | DE-02 |
| games | INT64 | closed games in scope, any opponent | DE-02 |
| wins | INT64 | | DE-02 |
| losses | INT64 | | DE-02 |
| win_pct | FLOAT64 | wins / games | DE-02 |
| d1_games | INT64 | valid D1-vs-D1 games used for efficiency | DE-07 |
| tempo | FLOAT64 | possessions per game | DE-07 |
| raw_oe | FLOAT64 | points scored per 100 possessions | DE-07 |
| raw_de | FLOAT64 | points allowed per 100 possessions | DE-07 |
| raw_net | FLOAT64 | raw_oe − raw_de | DE-07 |
| adj_oe | FLOAT64 | raw_oe adjusted for opponent defense and venue | DE-07 |
| adj_de | FLOAT64 | raw_de adjusted for opponent offense and venue | DE-07 |
| adj_net | FLOAT64 | adj_oe − adj_de: the main strength rating | DE-07 |
| sos_adj_net | FLOAT64 | average opponent adj_net | DE-07 |
| conference_strength | FLOAT64 | mean `adj_net` for all teams with the same season, scope and `conf_alias` | DE-07 |
| efg_pct | FLOAT64 | (FGM + 0.5 × 3PM) / FGA | DE-07 |
| tov_pct | FLOAT64 | turnovers per possession | DE-07 |
| orb_pct | FLOAT64 | ORB / (ORB + opponent DRB) | DE-07 |
| ftr | FLOAT64 | FTA / FGA | DE-07 |
| opp_efg_pct | FLOAT64 | opponents' efg_pct | DE-07 |
| opp_tov_pct | FLOAT64 | opponents' turnovers per possession | DE-07 |
| drb_pct | FLOAT64 | DRB / (DRB + opponent ORB) | DE-07 |
| opp_ftr | FLOAT64 | opponents' FTA / FGA | DE-07 |
| three_par | FLOAT64 | 3PA / FGA | DE-07 |
| three_pct | FLOAT64 | 3PM / 3PA | DE-07 |
| ft_pct | FLOAT64 | FTM / FTA | DE-07 |
| last10_net | FLOAT64 | raw net efficiency over the last 10 D1 games in scope | DE-07 |
| ap_rank_last | INT64 | AP rank at the team's last game in scope; NULL = unranked | DE-07 |
| experience_index | FLOAT64 | minutes-weighted class (FR = 1 … GR = 5); 2017-18 only | DE-07 |
| ret_min_share | FLOAT64 | share of minutes expected back next season | DE-06 → DE-07 |
| ret_pts_share | FLOAT64 | share of points expected back next season | DE-06 → DE-07 |
| ret_basis | STRING | 'actual' (2014-15 to 2016-17) or 'class_proxy' (2017-18) | DE-06 → DE-07 |
| program_win_pct_5y | FLOAT64 | win % over the previous five seasons | DE-07 |
| rank_adj_net | INT64 | 1 = best adj_net in season × scope | DE-07 |
| pctl_adj_oe | FLOAT64 | 0–1, 1 = best | DE-07 |
| pctl_adj_de | FLOAT64 | 0–1, 1 = best (lowest adj_de) | DE-07 |
| pctl_adj_net | FLOAT64 | 0–1, 1 = best | DE-07 |
| pctl_tempo | FLOAT64 | 0–1, 1 = fastest | DE-07 |
| pctl_efg_pct | FLOAT64 | 0–1, 1 = best | DE-07 |
| pctl_tov_pct | FLOAT64 | 0–1, 1 = fewest turnovers | DE-07 |
| pctl_orb_pct | FLOAT64 | 0–1, 1 = best | DE-07 |
| pctl_ftr | FLOAT64 | 0–1, 1 = most free-throw attempts | DE-07 |
| pctl_three_par | FLOAT64 | 0–1, 1 = most three-point heavy | DE-07 |
| pctl_opp_efg_pct | FLOAT64 | 0–1, 1 = best defense (lowest opponent efg) | DE-07 |

## Build notes

- First NCAA game per season is `MIN(scheduled_date) WHERE postseason_kind = 'NCAA'` in `stg_games`: 2014-03-18, 2015-03-17, 2016-03-15, 2017-03-14, 2018-03-13. Conference tournaments always end before it.
- D1 teams: `division_alias = 'D1'` on the team's own row (351 every season).
- Count only `is_closed` games.
- `conference_strength` belongs to DE2 and is calculated in DE-07 after final `adj_net`; ML2 consumes this column rather than recomputing conference aggregates.
- Conference membership is source-provided and may not perfectly reproduce historical realignment. Carry this caveat into YAML descriptions and downstream marts.
- Skeleton pattern: `CAST(NULL AS FLOAT64) AS tempo`, and so on, in contract order.
- Describe every column in the YAML; the Data Agent and Knowledge Catalog read these descriptions.

## Tests first

`models/02_features/_f_team_season.yml`:

```yaml
version: 2
models:
  - name: f_team_season
    data_tests:
      - unique_combination_of_columns: {arguments: {combination_of_columns: [season, scope, team_id]}}
      - row_count_between: {arguments: {min_count: 351, max_count: 351, group_by: [season, scope]}}
      - expression_is_true: {arguments: {expression: "wins + losses = games"}}
    columns:
      - name: scope
        data_tests:
          - accepted_values: {arguments: {values: ['pre_ncaa', 'full']}}
      - name: win_pct
        data_tests:
          - accepted_range: {arguments: {min_value: 0, max_value: 1}}
      - name: season
        data_tests: [not_null]
      - name: team_id
        data_tests: [not_null]
```

## Done when

```bash
scripts/dbt.sh build --select f_team_season
scripts/verify.sh
```

Then mark the contract **frozen** in `docs/stories/README.md` and tell ML1, ML2 and the AE that these names are final.

## Report back

- Rows per season × scope (expect 351 each).
- Villanova 2017-18 record in both scopes (expect 30-4 in `pre_ncaa` and 36-4 in `full`).

## Out of scope

Every computed metric (DE-05, DE-06, DE-07).
