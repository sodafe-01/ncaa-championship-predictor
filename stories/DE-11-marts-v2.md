# DE-11 — Marts v2: title odds, backtests, scouting, agent Q&A

**Lane:** DE2 · **Depends on:** DE-10, ML1 (T6–T7), ML2 (T8–T10), AE (T11–T13), Captain (T16 question list) · **Unblocks:** the dashboard's Prediction, Why and Trust pages, the Data Agent, the pitch · **Task:** T14 (part 2)

## Status rule

Blocked until the upstream tables exist. Before writing SQL, read the upstream models' YAML for their real column names. If they differ from this proposal, agree the names with the owner instead of guessing.

## As built (2026-09-16)

The upstream lanes were built in the same pass, so their names were set together with these marts: ML1 `m_game_win*`, `p_matchup`, `m_explain_topk`; ML2 `m_next_season_eval`, `f_team_projection`, `projected_field`, `projected_bracket`, `sim_games`, `sim_results`, `sim_paths`, `eval_backtest`; AE `ai_team_scouting`; Captain `agent/examples.md` (this repo keeps agent files in `agent/`, not `agents/`). All four marts build and every listed test passes, including `mart_title_odds_sum_to_one`, `mart_backtest_core_coverage` and `marts_have_column_descriptions` (now depending on the DE-11 marts too, so it runs after they persist their descriptions). Differences from the proposal:

1. **Scenarios** use the season start year: `backtest_2014` … `backtest_2017` (the March 2015-2018 tournaments) and `proj_2018` (2018-19).
2. **`mart_title_odds`** adds `is_forecast`, `adj_margin_low` and `adj_margin_high` (the forecast's ~80% band). For the forecast, `adj_margin` and `strength_rank` are the projected rating and rank rather than `mart_team_profile` values, which don't exist for 2018-19.
3. **`mart_backtest`** covers three model families per season (`logistic_reg`, the chosen family; `boosted_tree`; `rating_only`, the forecast family) and adds `is_core_season` and `is_chosen_model`. The champion's odds rank is filled on the chosen family only, because the simulations use it. March 2018 is included, with a NULL seed baseline.
4. **`mart_team_scouting`** `top_drivers` comes from the team-profile rows of `m_explain_topk` (the team against an average tournament team); for the forecast it describes the 2017-18 profile.

Report back:

- **Forecast top 10 by `p_champion` (2018-19):** Villanova 0.386, Duke 0.145, Michigan State 0.089, Virginia 0.074, Kentucky 0.043, Kansas 0.033, Tennessee 0.026, Michigan 0.021, Purdue 0.021, North Carolina 0.019. The projection's class-based returning shares can't see early NBA departures or transfers.
- **Core backtests (chosen logistic model):** log loss 0.504 / 0.553 / 0.514 against a seed baseline of 0.532 / 0.637 / 0.554 and a record baseline of 0.759 / 0.612 / 0.738 for the March 2015 / 2016 / 2017 tournaments. The champion ranked 4th (Duke, 10.3%), 6th (Villanova, 5.2%) and 3rd (North Carolina, 11.7%) in pre-tournament odds.
- **March 2018 extension (record baseline only):** log loss 0.582 vs a record baseline of 0.712; the champion Villanova ranked 2nd (20.8%).

## Goal

The presentation-ready tables behind the prediction: title odds per team, the backtest scorecard, AI scouting reports and the rehearsed agent questions, all documented in plain English.

## Files you own

- `models/06_marts/mart_title_odds.sql`
- `models/06_marts/mart_backtest.sql`
- `models/06_marts/mart_team_scouting.sql`
- `models/06_marts/mart_agent_qa.sql`
- `models/06_marts/_marts_v2.yml`
- `data_tests/mart_title_odds_sum_to_one.sql`

## Inputs (confirm names against their YAML)

`sim_results` (ML2), `eval_backtest` (ML2), `ai_team_scouting` (AE), `m_explain_topk` (ML1), `mart_team_profile` (DE-10), the Captain's rehearsed questions in `agents/examples.md`.

## Output contract (proposed)

### `mart_title_odds` — one row per scenario × team

`scenario` uses ML2's values (tasks.md names the forecast `proj_2018`; backtests one per season).

| Column | Type | Meaning |
|---|---|---|
| scenario, season, season_label | | |
| team_id, team_name, conference, color_hex, logo_url | | |
| seed | INT64 | real seed for 2014-15 to 2016-17 backtests, projected seed for the forecast, NULL for the 2017-18 backtest |
| region | STRING | |
| p_round_of_32, p_sweet_16, p_elite_8, p_final_four, p_final, p_champion | FLOAT64 | simulated probability of reaching each round |
| odds_rank | INT64 | 1 = highest `p_champion` |
| adj_margin, strength_rank | | from `mart_team_profile` |
| actual_last_round | STRING | backtests only |
| is_actual_champion | BOOL | backtests only |

### `mart_backtest` — one row per season × model

Core coverage is the 2015–2017 tournaments (`season` 2014–2016). Surface the 2018 tournament row only when ML2 completes that final extension; its absence does not block the core mart or demo.

| Column | Type | Meaning |
|---|---|---|
| season, season_label, model_name | | |
| games_scored | INT64 | |
| log_loss, brier, accuracy | FLOAT64 | |
| seed_baseline_log_loss | FLOAT64 | NULL for 2017-18 (no seeds) |
| record_baseline_log_loss | FLOAT64 | |
| beat_seed_baseline, beat_record_baseline | BOOL | |
| champion_name | STRING | |
| champion_odds_rank | INT64 | |
| champion_p_champion | FLOAT64 | |

### `mart_team_scouting` — one row per scenario × team

scenario, season, team_id, team_name, strengths (STRING, bullet-joined for Looker Studio), weaknesses, style, x_factor, top_drivers (STRING from `ML.EXPLAIN_PREDICT`), generated_at (TIMESTAMP).

### `mart_agent_qa` — one row per rehearsed question

question_id, question, expected_sql, expected_answer, verified_on (DATE), notes.

## Tests first

- `unique_combination_of_columns`: (`scenario`, `team_id`) for odds and scouting; (`season`, `model_name`) for backtests; `question_id` unique.
- Core `mart_backtest` coverage includes `season` 2014–2016. Require `season = 2017` only when the March 2018 extension is declared complete.
- `accepted_range` 0–1 on every probability column.
- `data_tests/mart_title_odds_sum_to_one.sql`: return scenarios where `ABS(SUM(p_champion) - 1) > 0.01`.
- `marts_have_column_descriptions` (from DE-10) covers these marts automatically.

## Done when

```bash
scripts/dbt.sh build --select mart_title_odds mart_backtest mart_team_scouting mart_agent_qa
scripts/verify.sh
```

## Report back

- Forecast top 10 by `p_champion`.
- The 2015–2017 core backtest table with both baselines; report the 2018 record-only row separately if the extension exists.

## Out of scope

The simulation, models and prompts themselves (ML1, ML2, AE).
