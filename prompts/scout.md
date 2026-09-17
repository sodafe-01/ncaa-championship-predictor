# Scout prompt (AE, task T11)

Used by `dbt/models/05_ai/ai_team_scouting.sql`, which builds one prompt per scenario and tournament team and calls
`AI.GENERATE` (`gemini-2.5-flash`, temperature 0, no thinking budget). The SQL is the source of truth; keep this
file in step with it.

## Guardrails

- The prompt carries only the team's numbers: no team name, conference, season outcome or seed. Gemini knows
  real history (including results after April 2018), so it must not be able to identify the team.
- It says to use only the numbers provided.
- Output is constrained by `output_schema => 'strengths ARRAY<STRING>, weaknesses ARRAY<STRING>, style STRING, x_factor STRING'`.
- The table is materialized; build it on purpose with `scripts/dbt.sh build --select tag:ai`. The demo never calls Gemini.

## Template

```
You are a college basketball scout writing for executives. Use ONLY the numbers below. Do not use any outside
knowledge about teams, players, coaches, seasons or tournament results, and do not guess which team this is.
Ratings are points per 100 possessions against an average opponent on a neutral court. Percentiles compare the
team with all 351 Division I teams that season (1.00 = best unless noted).

Profile before the NCAA tournament (<season_label>):
- Record: <wins>-<losses>
- Adjusted offense: <adj_oe> (percentile <pctl_adj_oe>)
- Adjusted defense: <adj_de> points allowed (percentile <pctl_adj_de>; lower allowed is better)
- Adjusted margin: <adj_net> (rank <rank_adj_net> of 351)
- Tempo: <tempo> possessions per game (percentile <pctl_tempo>, 1.00 = fastest)
- Effective field-goal percentage: <efg_pct> (percentile <pctl_efg_pct>)
- Turnovers per possession: <tov_pct> (percentile <pctl_tov_pct>, 1.00 = fewest)
- Offensive rebound rate: <orb_pct> (percentile <pctl_orb_pct>)
- Free throws attempted per shot: <ftr> (percentile <pctl_ftr>)
- Share of shots that are threes: <three_par> (percentile <pctl_three_par>, 1.00 = most threes)
- Three-point percentage: <three_pct>
- Opponents' effective field-goal percentage: <opp_efg_pct> (percentile <pctl_opp_efg_pct>, 1.00 = best defense)
- Strength of schedule (average opponent margin): <sos_adj_net>
- Net margin over the last 10 games: <last10_net>

[forecast scenario only]
Projection for next season:
- Projected adjusted margin: <projected_adj_net> (80% band <projected_low> to <projected_high>), projected rank <projected_rank>
- Share of minutes expected back (class-based estimate): <ret_min_share>

Return 2-3 strengths and 2-3 weaknesses as short phrases that cite the numbers, a one-sentence playing style,
and one x_factor sentence naming the single number most likely to decide its tournament games.
```
