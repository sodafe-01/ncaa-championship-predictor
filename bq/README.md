# BigQuery Artifacts

Version-controlled BigQuery SQL for the NCAA championship predictor, wired to:

- **Project:** `da-hackathon-2026`
- **Build dataset:** `texas_longhorns` (writable by our team)
- **Read-only source:** `da-hackathon-2026.ncaa_basketball`

## Files (deploy order)

| File | Creates | Notes |
|------|---------|-------|
| `sql/01_feat_team_season.sql` | `feat_team_season` table | D-I team-season feature spine |
| `sql/02_matchup_training.sql` | `matchup_training` table | Balanced tournament matchups |
| `sql/03_matchup_model.sql` | `matchup_model` (BQML) | Logistic-regression classifier |
| `sql/04_v_champion_probabilities.sql` | `v_champion_probabilities` view | Championship-probability proxy |
| `sql/06_backtest.sql` | `matchup_model_backtest` + `backtest_results` | Temporal split, model vs seed baseline |
| `sql/00_descriptions.sql` | table descriptions | Grounds the Data Agent |
| `sql/05_v_team_scouting.sql` | `v_team_scouting` view | **Optional** — needs a Vertex AI connection |

## Model performance

| Metric | Value |
|--------|-------|
| In-sample AUC (`ML.EVALUATE`) | 0.776 |
| Out-of-sample accuracy (2010+, 932 matchups) | 68.9% |
| Seed-only baseline accuracy | 68.6% |

**Finding:** seed + regular-season win% alone barely beats the seed baseline.
Next lever: add efficiency, tempo, and strength-of-schedule features from
`mbb_teams_games_sr` to create real edge over seeding.

Placeholders `__PROJECT__` / `__DATASET__` / `__CONNECTION__` are substituted at deploy time.

## Deploy locally

```bash
# Validate only (no cost, no writes)
DRY_RUN=1 PROJECT=da-hackathon-2026 DATASET=texas_longhorns bash bq/deploy.sh

# Deploy core artifacts
PROJECT=da-hackathon-2026 DATASET=texas_longhorns bash bq/deploy.sh

# Deploy the optional AI.GENERATE scouting view (after creating a connection)
PROJECT=da-hackathon-2026 DATASET=texas_longhorns \
  CONNECTION=projects/da-hackathon-2026/locations/us/connections/vertex_ai \
  bash bq/deploy.sh bq/sql/05_v_team_scouting.sql
```

## CI/CD

`.github/workflows/bigquery-ci.yml`:

- **Pull requests** → dry-run validates every SQL file (syntax + schema, no cost).
- **Push to `main`** → deploys core artifacts to `texas_longhorns`.

Auth uses `google-github-actions/auth` with a service-account key stored in the
`GCP_SA_KEY` repo secret. Project/dataset come from repo **variables**
`GCP_PROJECT_ID` and `BQ_DATASET`.

### Slack notifications

Deploy/validation results post to Slack channel `#C0C2D1ZSR5G`
(66degrees workspace). Requires:

- Repo secret `SLACK_BOT_TOKEN` — a Slack bot token (`xoxb-…`) with the
  `chat:write` scope.
- The Slack app must be invited to the channel: `/invite @your-app`.

Channel ID is set via the `SLACK_CHANNEL_ID` env in the workflow.
