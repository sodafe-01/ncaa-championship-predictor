# NCAA Championship Predictor — Data Engineering Plan

**Aligned to:** `team-spec.md` (texas_longhorns stations) + Phase 1 of `NCAA_Execution_Plan.md`  
**Slice:** **season 2017 only** (team spec: season 2017 = 2017–18)  
**Tooling:** dbt-BigQuery in `dbt/`, run via `scripts/dbt.sh`  
**Glossary:** keep Knowledge Catalog **NCAA Basketball Glossary** (terms → dbt docs + `stg_glossary_terms` / `dq_column_glossary`)

**Project:** `da-hackathon-2026`  
**Write dataset:** `texas_longhorns` (do not create datasets; do not write to raw)  
**Raw (read-only):** `ncaa_basketball`  
**Scans (read-only):** `ncaa_basketball_scan_results`

This is the DE contract. ML, `AI.GENERATE`, and the pitch are out of scope except for the tables they consume.

---

## 0. Locked decisions

| Decision | Rule |
|---|---|
| Season | `var ncaa_season = 2017`. Every `stg_` / `f_` filters to this. Team spec: 2017 = 2017–18. |
| Dataset | All models land in `texas_longhorns` (profile `dataset`). Do not set a custom `+schema` on folders — that would make dbt try to create `texas_longhorns_<folder>`. |
| Prefixes | DE1 `stg_`, `dq_`. DE2 `f_`, `mart_`. Do not ship `feat_` / `fct_` names. |
| Seeds | Allowed on `stg_tournament_games` for the “better seed wins” baseline. **Never** on `f_team_season` / `f_matchup`. |
| Glossary | Keep it. Copy NCAA Basketball Glossary definitions into dbt `description:` (`persist_docs`) and into `stg_glossary_terms` + `dq_column_glossary`. |
| PBP | Out of this slice (`mbb_pbp_sr`). |
| Historical pre-2013 | Out of this slice. |

**Exit criteria:** `f_team_season` + `stg_tournament_games` (NCAA tournament, 2017) published; dbt tests green; Data Map signed; glossary mapped onto curated columns.

---

## 1. Goal (2017 contracts)

| Table | Owner | Grain | Why |
|---|---|---|---|
| `stg_*` | DE1 | 1:1 with source, `season = 2017` | Tidy, typed, keys, no CIT/CBI as March Madness |
| `dq_*` | DE1 | check / column | Scan snapshot, glossary map, assertions |
| `f_team_game` | DE2 | team × game, 2017 regular season | Four factors, efficiency building blocks |
| `f_team_season` | DE2 | team × 2017 | Modeling spine (report card) |
| `f_matchup` | DE2 | 2017 tournament game | Two report cards, no seed |
| `mart_*` | DE2 | serving | Dashboard / Agents Hub (stub until ML/AI exist) |
| `stg_glossary_terms` | DE1 | glossary term | Catalog terms queryable in-warehouse |

---

## 2. What already exists (discovery)

### 2.1 Raw `ncaa_basketball`

| Table | Rows | Coverage | Role for 2017 |
|---|---:|---|---|
| `mbb_teams` | 351 | current D1 | `stg_teams` |
| `mbb_teams_games_sr` | 59,610 | 2013–2017 | **primary box scores**; filter `season = 2017` |
| `mbb_games_sr` | 29,805 | 2013–2017 | venue / tournament flags; dedupe `game_id` (99.91% unique) |
| `mbb_historical_tournament_games` | 2,117 | 1985–2017 | **labels + seeds**; filter `season = 2017` (~67 games) |
| `mbb_players_games_sr` | 888,844 | ~2013–2017 | returning-production inputs; filter 2017 |
| `mbb_historical_teams_seasons` / `_games` | large | through 2016 | **not used** in the 2017-only slice |
| `mbb_pbp_sr` | 4.2M | sample-scanned | out |
| `mascots`, `team_colors` | 351 | current | presentation only |

### 2.2 Scan results

`ncaa_basketball_scan_results.ncaa_basketball_20_sample_scans` (Dataplex, 2026-09-03). Use for `dq_profile_snapshot`. Notable: `neutral_site` ~60% null; tournament fields sparse by design; PBP profile is a sample.

### 2.3 NCAA Basketball Glossary (keep)

Organizers published ~151 terms plus column descriptions. DE1:

1. Export terms into `stg_glossary_terms` (name, definition, resource name).
2. Map curated columns in `dq_column_glossary`.
3. Paste definitions into YAML `description:` so `persist_docs` writes them to BigQuery (Catalog + Agents Hub).
4. Do not invent feature names that collide with glossary terms. Derived metrics: document the formula in the description.

Captain still owns Catalog UX; DE owns the in-warehouse copy so models stay grounded if Catalog is slow.

### 2.4 Season trap (still real, even with one year)

Source tables disagree on whether `season` is academic start, academic end, or tournament calendar year. For this slice:

1. Freeze `dim` logic in staging: **output column `season` always 2017** after the mapping DE1 documents in `docs` / model description.
2. Blocking test `dq_season_align`: 2017 tournament teams join 2017 `f_team_season` (not 2016).
3. If SR 2017 rows are 2017–18 and tournament `season = 2017` is March 2017, **fix the map before features**. Do not ship a silent off-by-one.

---

## 3. dbt layout (this repo)

```
dbt/
  dbt_project.yml          # profile ncaa_longhorns, var ncaa_season: 2017
  profiles.yml             # oauth → da-hackathon-2026.texas_longhorns (US)
  models/
    sources.yml            # ncaa_basketball + ncaa_catalog
    00_stg/                # DE1  stg_*
    01_dq/                 # DE1  dq_*
    02_features/           # DE2  f_*
    03_models/             # ML1  m_*, p_*   (empty)
    04_sim/                # ML2  sim_*, eval_* (empty)
    05_ai/                 # AE   ai_*  (disabled by default)
    06_marts/              # DE2  mart_*
scripts/dbt.sh
```

Run from repo root:

```bash
scripts/dbt.sh debug
scripts/dbt.sh compile
scripts/dbt.sh build --select tag:de1
scripts/dbt.sh build --select tag:de2
```

If oauth fails: `GCP_ACCESS_TOKEN="$(gcloud auth print-access-token)" scripts/dbt.sh debug`

**IAM:** build only your tagged models. Never `dbt run` the whole project onto someone else's prefix.

---

## 4. Split — DE1 vs DE2

Shared first (both, short): `scripts/dbt.sh debug` works; `ncaa_season: 2017` stays; DE2 publishes the `f_team_season` **column list** in `02_features/_features.yml` before writing SQL.

### DE1 — `00_stg/` + `01_dq/` (keys, 2017 filter, glossary, tests)

| Model | Source | Notes |
|---|---|---|
| `stg_teams` | `mbb_teams` | `team_id` = Sportradar `id`; keep `kaggle_team_id`, `code_ncaa` |
| `stg_teams_games_sr` | `mbb_teams_games_sr` | `season = {{ var('ncaa_season') }}`; completed games |
| `stg_games_sr` | `mbb_games_sr` | same filter; `QUALIFY ROW_NUMBER()` on `game_id` |
| `stg_tournament_games` | `mbb_historical_tournament_games` | 2017; NCAA championship tournament only (not CIT/CBI/NIT) |
| `stg_players_games_sr` | `mbb_players_games_sr` | 2017; for DE2 returning production |
| `stg_glossary_terms` | Knowledge Catalog glossary | keep glossary in-warehouse |
| `dq_profile_snapshot` | scan export | latest job per table |
| `dq_column_glossary` | glossary × curated columns | |
| `dq_assertions` | tests as a table + `schema.yml` tests | see §6 |

DE1 does **not** write `f_` or `mart_`.

### DE2 — `02_features/` + `06_marts/`

| Model | Notes |
|---|---|
| `f_team_game` | from `stg_teams_games_sr`; **exclude NCAA tournament games** (no label leak) |
| `f_team_season` | one row per team, 2017; see §5 |
| `f_matchup` | join `stg_tournament_games` to two copies of `f_team_season`; **no seed** |
| `mart_front_office` | stub grain now; fill after ML/AI |

DE2 does **not** change season mapping or restage sources.

**Handshake:** DE2 SQL starts when `stg_teams_games_sr` and `stg_tournament_games` exist with stable `team_id` + `season = 2017`.

---

## 5. `f_team_season` columns (DE2 contract)

Grain: `team_id`, `season` (= 2017). Regular season only.

| Column | Formula |
|---|---|
| `win_pct`, `games_played` | from `f_team_game` |
| `pts_for_pg`, `pts_against_pg` | averages |
| `off_eff`, `def_eff`, `net_eff` | points per 100 possessions; poss ≈ `FGA - ORB + TOV + 0.44*FTA` |
| `eFG_pct` | `(FGM + 0.5*3PM)/FGA` |
| `tov_pct` | `TOV / possessions` |
| `orb_pct` | `ORB / (ORB + opp DRB)` |
| `ft_rate` | `FTA / FGA` |
| `sos` | mean opponent `win_pct` or `net_eff` |
| `momentum_last6_win_pct` | last 6 regular-season games by date |
| `returning_min_pct` | from `stg_players_games_sr` if class/eligibility allows; else document NULL |

Opponent-adjusted ratings if time; unadjusted KenPom-lite is acceptable for a one-season slice. **No `seed`.**

---

## 6. DQ (DE1)

dbt tests on models **plus** `dq_assertions`.

**Blocking**

- unique `f_team_season(team_id, season)`
- not null `team_id`, `season`, `win_pct`, `games_played`
- unique tournament game grain
- `win_team_id <> lose_team_id`
- ≥ 95% of 2017 tournament teams match `f_team_season`
- `season_align` (2017 ↔ 2017)
- NCAA tournament games excluded from `f_team_game`
- `stg_teams_games_sr` 2017 row count within 1% of source filter (document delta)

**Warn:** `neutral_site` null vs scan; seed STRING→INT on staging only.

---

## 7. Sequence

| Order | Who | Task |
|---|---|---|
| 1 | both | `scripts/dbt.sh debug`; confirm `texas_longhorns` |
| 2 | DE2 | freeze `f_team_season` columns in `_features.yml` |
| 3 | DE1 | `stg_*` for 2017 + glossary extract |
| 4 | DE1 | `dq_profile_snapshot`, tests |
| 5 | DE2 | `f_team_game` → `f_team_season` → `f_matchup` |
| 6 | DE1 | blocking assertions green; Captain Data Map |

---

## 8. Risks

| Risk | Mitigation |
|---|---|
| 2017 means different years across sources | DE1 mapping + `dq_season_align` before DE2 aggregates |
| CIT/CBI labeled NCAA in Sportradar | Tournament labels from `mbb_historical_tournament_games`, not SR `tournament = 'NCAA'` |
| Label leak | Drop NCAA tourney games from `f_*` |
| Seed sneaking into the model | Prefix rule + YAML: seed only on `stg_tournament_games` |
| Writing a new dataset | profile `dataset: texas_longhorns`; never set model `+schema` |
| Glossary skipped | `stg_glossary_terms` + `persist_docs` required in DE1 exit |

---

## 9. Checklist

- [ ] `scripts/dbt.sh debug` (oauth or `GCP_ACCESS_TOKEN`)
- [ ] `stg_*` for 2017 sources + `stg_glossary_terms`
- [ ] `dq_profile_snapshot`, `dq_column_glossary`, `dq_assertions`
- [ ] `f_team_game`, `f_team_season`, `f_matchup` (no seed)
- [ ] Column descriptions from NCAA Basketball Glossary
- [ ] dbt tests green for `tag:de1` and `tag:de2`
- [ ] Data Map signed; handoff note (grain, 2017 definition, leak policy)

ML1 trains on `f_matchup` / `f_team_season` for **2017 only**.
