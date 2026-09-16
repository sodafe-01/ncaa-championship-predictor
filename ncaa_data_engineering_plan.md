# NCAA Championship Predictor — Data Engineering Plan

**Scope:** Phase 1 of `NCAA_Execution_Plan.md` (Data Discovery & Engineering), plus the DE contracts that unblock BQML, `AI.GENERATE`, and the Data Agent.

**Project:** `da-hackathon-2026`  
**Raw (read-only):** `ncaa_basketball`  
**Catalog scans (read-only):** `ncaa_basketball_scan_results`  
**Glossary:** Knowledge Catalog **NCAA Basketball Glossary**  
**Owners:** Data Engineers (2). Captain owns the one-page Data Map sign-off.

This plan is grounded in live table metadata and Dataplex data-profile scans as of 2026-09-03. It is **not** an ML, prompt, or pitch plan.

---

## 1. Goal

Publish a governed warehouse layer that Data Scientists can train on without re-discovering sources:

| Contract table | Grain | Why it exists |
|---|---|---|
| `feat_team_season` | one row per `team_id` × `season` | Modeling spine (regular-season form going into March) |
| `fct_tournament_games` | one row per NCAA tournament game | Labels, seeds, bracket structure, backtest holdouts |
| `fct_team_game` | one row per team per game | Efficiency, momentum, SoS building blocks |

**Exit criteria (from the execution plan):** `feat_team_season` + `fct_tournament_games` published and validated; Data Map signed off.

Hard constraints:

- Do **not** write to `ncaa_basketball` or `ncaa_basketball_scan_results`.
- Treat both as source systems. All transforms land in a **team-owned** dataset (proposed: `ncaa_predictor`; rename to the team mascot dataset if one is assigned).
- Prefer SQL in BigQuery (views / tables). No data leaves GCP.

---

## 2. What already exists (discovery findings)

### 2.1 Raw tables in `ncaa_basketball`

| Table | Rows | Size | Coverage | Grain | Role in this build |
|---|---:|---:|---|---|---|
| `mbb_teams` | 351 | 0.2 MB | Current D1 directory | 1 row / team | `dim_team` (canonical Sportradar `id`) |
| `mbb_historical_teams_seasons` | 54,884 | 6 MB | 1894–2016 | 1 row / team-season | Win/loss baseline; **too coarse for efficiency** |
| `mbb_historical_teams_games` | 571,448 | 117 MB | 1996–2016 | 2 rows / game (one per team) | Long-history scores; **no box-score four factors** |
| `mbb_historical_tournament_games` | 2,117 | 0.5 MB | 1985–2017 | 1 row / tournament game | **Primary label + seed source** |
| `mbb_games_sr` | 29,805 | 48 MB | 2013–2017 | 1 row / game (home + away cols) | Venue / neutral / conference flags |
| `mbb_teams_games_sr` | 59,610 | 95 MB | 2013–2017 | 2 rows / game | **Primary feature source** (box scores) |
| `mbb_players_games_sr` | 888,844 | 421 MB | ~2013–2017 | 1 row / player-game | Optional depth / usage features; not on the critical path |
| `mbb_pbp_sr` | 4,160,393 | 3.2 GB | ~2013–2017 | event | **Out of v1.** Sample scan only (~832k of 4.2M rows). Too large for a day-1 spine |
| `mascots`, `team_colors` | 351 each | tiny | current D1 | 1 row / team | Pitch / agent cosmetics only |

Knowledge Catalog data-profile labels are already published onto the raw tables (scans in `us-central1`). Column descriptions on the raw DDL should be treated as glossary-adjacent documentation and copied into curated table OPTIONS.

### 2.2 Scan results in `ncaa_basketball_scan_results`

Table `ncaa_basketball_20_sample_scans` is a Dataplex data-profile export (partitioned on `DATE(job_start_time)`). All 10 raw tables were scanned on 2026-09-03.

Use it as the **quality source of truth**, not as a modeling table:

- Build the Data Map (null %, uniqueness, min/max, top-N) from this table instead of ad-hoc `COUNTIF`.
- Flag columns with `percent_null >= 20` before they leak into features (`neutral_site` ~60%, `conference_game` ~40%, most tournament fields ~93% because they are sparse by design).
- `mbb_games_sr.game_id` uniqueness is **99.91%**, not 100% — staging must `QUALIFY ROW_NUMBER()`.
- PBP scan is a **sample**. Do not treat those null rates as full-table truth.

### 2.3 NCAA Basketball Glossary

The glossary is the semantic layer for agents and for column descriptions. DE work with it:

1. Export terms (name, definition, related assets) into `ref_glossary_terms`.
2. Map each curated column to a glossary term (`ref_column_glossary`).
3. Copy term definitions into BigQuery column OPTIONS so the Data Agent is grounded even without a live Dataplex call.
4. Do not invent feature names that collide with glossary terms (`seed`, `season`, `team_id`, `efficiency`, etc.). If a feature is derived, prefix `feat_` and document the formula next to the term.

### 2.4 Season-key hazard (must resolve on day 1)

These tables do **not** share one `season` definition:

- `mbb_historical_tournament_games.season` = calendar year of the tournament (2017 March Madness). `academic_year` is a separate column.
- `mbb_historical_teams_seasons` / `mbb_historical_teams_games` use academic-year style seasons and **stop at 2016**.
- Sportradar tables run **2013–2017**.

**Canonical season for this project:** the year the NCAA tournament is played (example: 2016–17 regular season → `season = 2017`). Staging must remap academic-year tables with `season_canonical = academic_year + 1` (or use `academic_year` from the tournament table) and prove the join with a seed-year audit (2015–2017).

Without this, `feat_team_season` will silently miss 2017 labels or join the wrong regular season onto the wrong bracket.

### 2.5 What we will not copy

Other hackathon teams already wrote `stg_*` / `mart_*` in datasets such as `ohio_buckeyes` and `arizona_wildcats`. Those are **out of bounds**. Reuse patterns, not their tables.

---

## 3. Target architecture

```
Knowledge Catalog
  NCAA Basketball Glossary          ncaa_basketball_scan_results
           │                                      │
           ▼                                      ▼
     ref_glossary_terms                  dq_profile_snapshot
           │                                      │
           └──────────────┬───────────────────────┘
                          ▼
                 ncaa_basketball  (RAW, read-only)
                          │
                          ▼
                 stg_*  (typed, 1:1, season_canonical, surrogate keys)
                          │
              ┌───────────┼────────────┐
              ▼           ▼            ▼
          dim_team   dim_season   dim_conference
              │           │            │
              └───────────┼────────────┘
                          ▼
              fct_team_game   fct_tournament_games
                          │
                          ▼
                    feat_team_season     ◄── Data Scientists train here
                          │
                          ▼
                    dq_assertions        ◄── SQL tests, published as a table
```

Layer rules:

| Layer | Prefix | Materialization | Allowed transforms |
|---|---|---|---|
| Raw | none | existing tables | none |
| Staging | `stg_` | VIEW or TABLE | rename, cast, dedupe, season canonicalize, filter completed games |
| Conformed | `dim_`, `fct_` | TABLE, partitioned | joins, grain enforcement |
| Feature | `feat_` | TABLE | aggregations, derived metrics |
| Reference / DQ | `ref_`, `dq_` | TABLE | glossary, scan snapshot, assertion results |

Physical design for facts:

- Partition `fct_team_game` and `fct_tournament_games` by `season` (INT64 range partition, 1985–2018).
- Cluster by `team_id` (facts) / `win_team_id` (tournament).
- Cluster `feat_team_season` by `season`, `team_id`.

---

## 4. Workstreams

Two engineers, parallel after the Data Map is drafted.

### Workstream A — Discovery, keys, glossary (Engineer 1 + Captain)

1. Publish `dq_profile_snapshot` from `ncaa_basketball_scan_results.ncaa_basketball_20_sample_scans` (latest `job_end_time` per table).
2. Score each raw table on coverage, freshness, grain (template in §5).
3. Build `dim_team_crosswalk`: `team_id` (Sportradar) ↔ `kaggle_team_id` ↔ `code_ncaa` ↔ `alias` ↔ `market`.
4. Resolve `season_canonical` with an explicit mapping table `dim_season`.
5. Export NCAA Basketball Glossary → `ref_glossary_terms` + `ref_column_glossary`.
6. Write the one-page Data Map (Captain signs).

### Workstream B — Warehouse build (Engineer 2, then both)

1. Create dataset `ncaa_predictor` (or assigned team dataset) in `US`.
2. Staging views for the six in-scope sources (§6).
3. `dim_team`, `dim_season`, `dim_conference`.
4. `fct_team_game` from `stg_teams_games_sr` (v1 window 2013–2017). Optionally union historical scores as a thin `fct_team_game_hist` later — **not required for the BQML window**.
5. `fct_tournament_games` from `stg_tournament_games`, NCAA tournament only, with `season_canonical` and both team keys.
6. `feat_team_season` (§7).
7. `dq_assertions` (§8).
8. Grant Data Scientists `roles/bigquery.dataViewer` on the curated dataset; keep raw datasets read-only.

**Critical path:** A3/A4 (keys + season) must finish before B4–B6. Data Scientists may prototype on a 2016 sample of `stg_teams_games_sr` in parallel, but they do not train on un-canonical seasons.

---

## 5. Data Map (to fill, then freeze)

Score: **H** / **M** / **L**. Grain preference from the execution plan: game-level > season-aggregate.

| Asset | Coverage | Freshness | Grain | Join keys | Quality risks | Use |
|---|---|---|---|---|---|---|
| `mbb_teams` | H (351 D1) | current snapshot, not historical conf | team | `id` | Conference is *current*, not as-of-season | dim |
| `mbb_teams_games_sr` | H for 2013–17 | stale (ends 2017) | team-game | `game_id`,`team_id`,`season` | `neutral_site` 60% null; sparse tournament flags | **primary fct** |
| `mbb_games_sr` | same | same | game | `game_id` | `game_id` not perfectly unique | flags / venue |
| `mbb_historical_tournament_games` | H 1985–2017 | ends 2017 | game | `win_team_id`,`lose_team_id`,`season` | `season` ≠ academic year; 67 games/year (64 + First Four) | **labels** |
| `mbb_historical_teams_seasons` | H long | ends 2016 | team-season | `team_id`,`season` | no efficiency; season def | fallback W-L only |
| `mbb_historical_teams_games` | H 1996–2016 | ends 2016 | team-game | `team_id`,`scheduled_date` | string dates; no `game_id`; two rows/game | pre-2013 only |
| `mbb_players_games_sr` | M | same as SR | player-game | `game_id`,`player_id` | `class` ~80% null | v2 |
| `mbb_pbp_sr` | L for v1 | same; sample scan | event | `game_id` | 3.2 GB; sample profile | out of v1 |
| `mascots` / `team_colors` | n/a | current | team | `id` | irrelevant to prediction | presentation |
| scan export | H | 2026-09-03 | column | `dataset_id`,`table_id`,`column_name` | PBP sampled | DQ |
| NCAA Basketball Glossary | H (terms) | catalog | term | term resource name | must confirm location (`global` vs region) | semantics |

**Modeling window decision:** train/backtest on **2014–2017 tournaments**, using Sportradar box scores for features. Historical W-L (pre-2013) is optional for narrative (“program history”), not for the matchup model. This matches the execution plan’s “don’t over-engineer” risk.

---

## 6. Staging specs

Each `stg_*` is 1:1 with a source, plus:

- `season_canonical INT64`
- `_src STRING` (table name)
- `_loaded_at TIMESTAMP`

| Staging object | Source | Dedup key | Filters |
|---|---|---|---|
| `stg_teams` | `mbb_teams` | `id` | none |
| `stg_teams_games_sr` | `mbb_teams_games_sr` | `game_id`,`team_id` | `status` completed / not cancelled if that field is usable |
| `stg_games_sr` | `mbb_games_sr` | `game_id` (keep latest `created`) | same |
| `stg_tournament_games` | `mbb_historical_tournament_games` | `season`,`game_date`,`win_team_id`,`lose_team_id` | none in staging; NCAA-vs-NIT filter happens in the fact |
| `stg_team_seasons_hist` | `mbb_historical_teams_seasons` | `team_id`,`season` | `division = 1` or `current_division` D1 where possible |
| `stg_team_games_hist` | `mbb_historical_teams_games` | `team_id`,`scheduled_date`,`opp_id` | D1 vs D1 if `current_division` allows |

Key standardization in staging (not later):

- Team PK: `team_id STRING` = Sportradar id (`mbb_teams.id`, `*_team_id`, `h_id` / `a_id`).
- Always keep `kaggle_team_id` and `code_ncaa` as alternate keys on `dim_team`.
- Cast `scheduled_date` in historical games from STRING → DATE.
- Normalize `win` to BOOL; points to INT64.
- Do not drop high-null columns in staging; drop them when selecting into features.

---

## 7. Feature spine — `feat_team_season`

**Grain:** `team_id`, `season_canonical`.  
**Population:** D1 teams that played a regular season in that year **and** (for tournament rows) can join to `fct_tournament_games`.

Regular-season only: exclude NCAA tournament games from feature aggregates so we do not leak the label. Use `mbb_games_sr.tournament` / `tournament_type`:

- Feature games: `tournament IS NULL` OR conference tournaments (optional — **default v1: exclude all `tournament IS NOT NULL`** so features are true regular season).
- Labels: `fct_tournament_games` where the game is the Division I championship tournament (regionals + Final Four). Do **not** treat CIT/CBI rows in Sportradar (`tournament_type` in CIT/CBI) as March Madness.

### 7.1 Base features (execution plan list)

| Feature | Formula / source | Notes |
|---|---|---|
| `win_pct` | `SUM(win)/COUNT(*)` on `fct_team_game` | |
| `games_played` | count | |
| `pts_for_pg`, `pts_against_pg` | averages | |
| `off_eff`, `def_eff` | points per 100 possessions | Possessions ≈ `FGA - ORB + TOV + 0.44*FTA` (KenPom-lite) from `mbb_teams_games_sr` |
| `net_eff` | `off_eff - def_eff` | |
| `eFG_pct` | `(FGM + 0.5*3PM)/FGA` | Four Factors |
| `tov_pct` | `TOV / possessions` | |
| `orb_pct` | `ORB / (ORB + opp DRB)` | needs opponent rebounds (present on `mbb_teams_games_sr`) |
| `ft_rate` | `FTA / FGA` | |
| `sos` | average opponent `win_pct` (or opponent `net_eff`) same season | compute in a second pass |
| `momentum_last6_win_pct` | last 6 regular-season games by `scheduled_date` | |
| `seed` | `win_seed`/`lose_seed` from tournament table for that team-season | missing for non-tourney teams; leave NULL |
| `conf_strength` | mean `net_eff` of conference mates | `conf_id` on SR rows is **current** conference — document this limitation |

v2 (only if DS asks and time remains): player-usage concentration from `mbb_players_games_sr`; home/neutral splits; KenPom-style luck (actual vs expected win%).

### 7.2 Downstream contract

Data Scientists will pair two rows of `feat_team_season` into matchup differentials (`a_stat - b_stat`). DE does **not** have to pre-build the matchup table, but should add a view `v_tourney_matchup_features` that joins `fct_tournament_games` to two copies of `feat_team_season` so DS is not blocked.

---

## 8. Data-quality assertions

Implement as SQL that writes `dq_assertions(check_name, grain, expected, actual, status, run_at)`. Fail the publish job if any `status = 'FAIL'` on blocking checks.

**Blocking**

| Check | Rule |
|---|---|
| `feat_pk` | unique (`team_id`,`season_canonical`) |
| `feat_not_null` | `team_id`, `season_canonical`, `win_pct`, `games_played` not null |
| `tourney_pk` | unique game grain |
| `tourney_two_teams` | `win_team_id <> lose_team_id` |
| `tourney_join_rate` | ≥ 95% of 2014–2017 tournament teams match `feat_team_season` |
| `season_align` | 2017 tournament teams have `feat` rows labeled 2017, not 2016 |
| `no_label_leak` | NCAA tournament games excluded from `feat_*` aggregates |
| `row_count_sr` | `stg_teams_games_sr` within 1% of raw 59,610 (after completed-game filter, document delta) |

**Non-blocking (warn)**

- `neutral_site` null rate vs scan (~60%).
- `seed` parsed as INT (raw is STRING).
- Historical season table ends 2016 — expected.
- `game_id` duplicate count on `mbb_games_sr`.

Refresh `dq_profile_snapshot` if scans are re-run; do not hard-code null thresholds from this document.

---

## 9. Sequence (hackathon-compressed)

Assume Phase 1 is ~20% of total time. Inside that:

| Order | Task | Hours (indicative) | Depends on |
|---|---|---|---|
| 1 | Dataset + IAM + `dim_season` decision | 0.5 | — |
| 2 | Data Map v0 from scan export + glossary dump | 2 | 1 |
| 3 | Staging views + `dim_team` crosswalk | 2 | 2 |
| 4 | `fct_team_game` + `fct_tournament_games` | 2 | 3 |
| 5 | `feat_team_season` + matchup view | 3 | 4 |
| 6 | DQ assertions + Captain sign-off | 1.5 | 5 |

Day-1 deliverable for DS: even a **2016-only** `feat_team_season` sample. Full 2014–2017 spine before they train the boosted tree.

---

## 10. Agent / catalog contract (DE portion only)

The execution plan’s agent reads curated tables, not raw. DE must:

1. Set table and column `OPTIONS(description=...)` from the NCAA Basketball Glossary.
2. Label curated tables in Catalog (or at least document resource names) so the Captain can point the Data Agent at `ncaa_predictor`, not `ncaa_basketball`.
3. Keep `ref_glossary_terms` queryable for Analytics Engineers who will ground `AI.GENERATE` in real feature values.

DE does **not** configure Gemini Enterprise or write prompt tables.

---

## 11. Risks (DE-owned)

| Risk | Impact | Mitigation |
|---|---|---|
| Season definition mismatch | Wrong regular season joined to 2017 bracket | `dim_season` + blocking `season_align` check |
| Current-conference on SR rows | `conf_strength` is wrong for teams that changed conference | Prefer `conf_*` from the game row; still document “as stored by Sportradar” |
| Label leakage | Inflated backtest | Exclude NCAA tournament games from features |
| CIT/CBI mixed with NCAA | Fake tournament labels | Filter `fct_tournament_games` via historical tournament table, not SR `tournament = 'NCAA'` |
| PBP rabbit hole | Miss the feature spine | Out of v1 |
| Writing to raw datasets | Breaks shared hackathon sources | Team dataset only |
| Over-building hist 1894–2012 | Burns Phase 1 time | Features from 2013–2017 SR only |

---

## 12. Deliverables checklist

- [ ] One-page Data Map (Captain signed)
- [ ] `ncaa_predictor` dataset (or assigned team dataset)
- [ ] `stg_*` for six in-scope sources
- [ ] `dim_team`, `dim_season`, `dim_conference`
- [ ] `fct_team_game`, `fct_tournament_games`
- [ ] `feat_team_season` + `v_tourney_matchup_features`
- [ ] `ref_glossary_terms`, `ref_column_glossary`
- [ ] `dq_profile_snapshot`, `dq_assertions` (blocking checks green)
- [ ] Column descriptions aligned to NCAA Basketball Glossary
- [ ] Handoff note to DS: grain, season definition, leak policy, known nulls

When this list is done, Phase 2 (BQML) is unblocked. Everything after `feat_team_season` is owned by Data Scientists and Analytics Engineers.
