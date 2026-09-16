# DE-11 — Marts v2: title odds, backtests, scouting, agent Q&A

**Lane:** DE2 · **Depends on:** DE-10, ML1 (T6–T7), ML2 (T8–T10), AE (T11–T13), Captain (T16 question list) · **Unblocks:** the dashboard's Prediction, Why and Trust pages, the Data Agent, the pitch · **Task:** T14 (part 2)

## Status rule

Blocked until the upstream tables exist. Before writing SQL, read the upstream models' YAML for their real column names. If they differ from this proposal, agree the names with the owner instead of guessing.

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
