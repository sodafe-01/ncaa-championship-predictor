# NCAA Championship Prediction — Team Execution Plan

**Lead Architect briefing for a 7-person NCAA Data Strategy Team**

Below is a phase-by-phase plan mapped to your roles, tech stack, and the 66degrees judging criteria. Assume a compressed hackathon-style timeline; time boxes are bracketed so you can rescale.

---

## Team Allocation (7 people)

| Role | Count | Owns |
|------|-------|------|
| Team Captain | 1 | Catalog discovery, PM, pitch synthesis |
| Data Engineers | 2 | Schema, pipelines, table structuring |
| Data Scientists | 2 | BQML training, features, prediction logic |
| Analytics Engineers | 2 | `AI.GENERATE` prompt routines, agent config |

Run phases with **parallel swimlanes** — Engineering unblocks Science; Analytics + Captain build the agentic/pitch layer concurrently.

---

## Phase 1 — Data Discovery & Engineering `[~20%]`

**Owner: Team Captain (discovery) + Data Engineers (structuring)**

### 1a. Metadata scanning (Knowledge Catalog) — *Captain*
1. Enumerate all mapped BigQuery assets in the Knowledge Catalog; export the asset inventory (dataset → table → column, with tags/descriptions).
2. Filter for NCAA-relevant entities: team-season stats, game-level results, tournament brackets, player rosters, rankings/seeds, and advanced metrics (tempo, efficiency).
3. Score each dataset on **coverage, freshness, and grain** (game-level > season-aggregate for modeling). Flag join keys (`team_id`, `season`, `game_id`) and PII/quality risks.
4. Deliver a one-page **Data Map** that the Data Scientists can consume without re-discovering sources.

### 1b. Dataset structuring (BigQuery) — *Data Engineers*
1. Build a clean **staging → curated → feature** layer pattern:
   - `stg_*`: 1:1 typed copies of raw catalog sources.
   - `dim_*` / `fct_*`: conformed dimensions (teams, seasons, venues) + fact tables (games, tournament results).
   - `feat_team_season`: one row per team-season, the modeling spine.
2. Standardize keys and enforce types/partitioning (partition facts by `season`, cluster by `team_id`).
3. Engineer base features: win %, offensive/defensive efficiency, strength-of-schedule, momentum (last-N), seed, conference strength.
4. Add data-quality checks (row counts, null thresholds, key uniqueness) as SQL assertions so downstream models trust the inputs.

**Exit criteria:** `feat_team_season` + `fct_tournament_games` published and validated; Data Map signed off.

---

## Phase 2 — ML & AI Implementation `[~30%]`

**Owner: Data Scientists (BQML) + Analytics Engineers (`AI.GENERATE`)**

### 2a. BQML championship prediction — *Data Scientists*
1. **Frame the problem two ways:**
   - *Matchup model* (primary): binary classifier — P(team A beats team B) given paired features. This is the reusable unit.
   - *Advancement model* (optional): multiclass / round-survival probability.
2. **Feature selection:** start from Phase 1 features; use correlation + BQML feature importance to prune. Prefer differential features (A_stat − B_stat) for matchup framing.
3. **Train** with `CREATE MODEL ... OPTIONS(model_type=...)`:
   - Baseline `LOGISTIC_REG` for interpretability.
   - `BOOSTED_TREE_CLASSIFIER` for accuracy.
   - Compare via `ML.EVALUATE` (AUC, log loss); use `TRANSFORM` to keep preprocessing inside the model.
4. **Backtest** on prior tournaments (train on seasons ≤ N-1, predict season N). Report bracket accuracy vs. seed-only baseline.
5. **Simulate the bracket:** apply the matchup model round-by-round (Monte Carlo over uncertain matchups) to produce **P(champion) per team** — the headline number for the pitch.

### 2b. `AI.GENERATE` routines — *Analytics Engineers*
1. Wrap model outputs in narrative generation. Example patterns:
   - `AI.GENERATE` over a row of predicted probabilities → plain-English "why this team wins/loses" summary.
   - `AI.GENERATE_TABLE` to produce structured scouting cards (strength, weakness, X-factor) per team.
2. Ground prompts in **actual feature values** (pass efficiency, SoS, etc.) to prevent hallucination — the model states facts, the LLM narrates them.
3. Standardize prompt templates + few-shot examples; version them in a `prompts` table so they're auditable and reusable.

**Exit criteria:** Validated champion probabilities + auto-generated team scouting narratives.

---

## Phase 3 — Agentic Architecture Blueprint `[~20%]`

**Owner: Analytics Engineers + Captain**

End-to-end operational map:

```
                    ┌─────────────────────────┐
   User / Exec ───► │   Gemini Enterprise      │  (conversational UI,
   "Who wins &      │   orchestration + auth)  │   reasoning, synthesis)
    why?"           └───────────┬─────────────┘
                                │ delegates data questions
                                ▼
                    ┌─────────────────────────┐
                    │  BigQuery Data Agent(s)  │  (NL→SQL, grounded in
                    │  scoped to curated model │   Knowledge Catalog metadata)
                    └───────────┬─────────────┘
                                │ queries
              ┌─────────────────┼──────────────────┐
              ▼                 ▼                    ▼
      feat_team_season    BQML models         AI.GENERATE
      / fct_* tables      (ML.PREDICT)        narrative routines
              └─────────────────┴──────────────────┘
                                │
                                ▼
                     Grounded answer + P(champion)
                     + scouting narrative → back to Gemini → Exec
```

**Design principles to state explicitly in the pitch:**
- **Separation of concerns:** BigQuery Data Agent handles *retrieval + trusted SQL over the governed model*; Gemini Enterprise handles *reasoning, multi-step orchestration, and executive-facing synthesis*.
- **Grounding chain:** Catalog metadata → curated tables → BQML predictions → `AI.GENERATE` narrative. Every LLM claim is traceable to a query result (no ungrounded prediction).
- **Reusability:** the agent is pointed at a semantic layer, not hardcoded queries — swap the dataset, keep the pattern.

---

## Phase 4 — Executive Pitch Strategy (5–10 min) `[~20%]`

**Owner: Team Captain (synthesis), all contribute slides**

Suggested runsheet:

| Time | Section | Content |
|------|---------|---------|
| 0:00–1:00 | **Hook** | The champion prediction + confidence, upfront. "Our system says X wins with Y% probability." |
| 1:00–3:30 | **Architecture** | The Phase 3 diagram. Explain *why* Data Agent + Gemini split, why BQML-in-warehouse (no data movement, governed, fast). One design tradeoff you made and defended. |
| 3:30–6:30 | **Strategy / Findings** | Data-backed reasoning: top contenders, each team's strength/weakness from scouting cards, the key features that drive outcomes, backtest accuracy vs. baseline (credibility). |
| 6:30–8:30 | **Consulting angle (66degrees)** | How this agentic pattern generalizes to client work. |
| 8:30–10:00 | **Close + Q&A buffer** | Restate prediction, impact, next steps. |

**Consulting reuse pitch (66degrees):** frame the build as a **repeatable accelerator** — "Governed data + BQML + agentic narration" is a template for any client with a warehouse and a decision to make: churn/retention prediction, demand forecasting, risk scoring, sales pipeline win-probability. Same architecture (Catalog → curated model → BQML → Data Agent → Gemini), different domain. Sell it as a **2-week discovery-to-agent engagement pattern**, lowering time-to-value for clients already on GCP.

---

## Phase 5 — Assessment Matrix `[continuous]`

Self-score before submission; assign an owner to each criterion.

| Judging Criterion | How we satisfy it | Evidence to show | Owner |
|-------------------|-------------------|------------------|-------|
| **Technical Execution** | BQML models with backtests, in-warehouse `AI.GENERATE`, working Data Agent + Gemini flow | Live demo / `ML.EVALUATE` metrics, agent Q&A | Data Scientists |
| **Discovery & Growth** | Rigorous Catalog metadata scan → Data Map; documented learning of the stack | Data Map artifact, dataset scoring | Captain + Data Engineers |
| **Value & Impact** | Actionable champion prediction beating seed-only baseline; quantified consulting reuse | Accuracy delta, reuse business case | Data Scientists + Captain |
| **Storytelling** | Tight 5–10 min narrative, prediction-first, grounded scouting narratives | Pitch runsheet, `AI.GENERATE` scouting cards | Captain + Analytics Engineers |

> Note: the brief listed "Discovery & Grow**talue** & Impact" — read here as two criteria (**Discovery & Growth** and **Value & Impact**); adjust the rows if it's meant to be one.

---

## Critical Path & Risks
- **Blocker to watch:** Phase 2 can't start until `feat_team_season` is stable — Data Engineers must deliver the feature spine early (day 1). Have Data Scientists prototype on a sample in parallel.
- **Biggest risk:** ungrounded LLM claims. Mitigate by forcing `AI.GENERATE` to consume real feature values, and by demoing the grounding chain live.
- **Time trap:** over-engineering the model. A well-backtested logistic/boosted-tree matchup model + clean bracket simulation beats a fancy model with a broken narrative.
