# CI / CD and merge gating

The pipeline is defined in `.github/workflows/ci.yml` and is built around the
team's **dbt** project (`dbt/`, run via `scripts/dbt.sh`).

## Jobs

| Job | Trigger | What it does | Needs secret? |
|-----|---------|--------------|---------------|
| **validate** | every PR + push to `main` | `ruff` lint + `dbt parse` (compiles the DAG, checks refs/sources/macros). Cheap, no BigQuery. | No |
| **e2e** | PR only | Full `dbt build` into an **ephemeral** dataset `ci_pr_<run_id>` with `n_sims=100`, runs all dbt tests, then drops the dataset. Proves the whole pipeline runs before merge. | Yes |
| **deploy** | push to `main` | Full `dbt build` + tests into the shared `texas_longhorns` dataset. | Yes |

`validate` is the **required status check** — a PR cannot merge unless the dbt
project compiles. `e2e` adds real end-to-end proof once BigQuery CI is enabled.

## Enabling the BigQuery jobs

1. Create a CI service account with write access to the dataset:
   ```bash
   gcloud iam service-accounts create ncaa-ci --project da-hackathon-2026
   SA=ncaa-ci@da-hackathon-2026.iam.gserviceaccount.com
   gcloud projects add-iam-policy-binding da-hackathon-2026 \
     --member="serviceAccount:$SA" --role=roles/bigquery.jobUser
   bq add-iam-policy-binding --member="serviceAccount:$SA" \
     --role=roles/bigquery.dataViewer da-hackathon-2026:ncaa_basketball
   bq add-iam-policy-binding --member="serviceAccount:$SA" \
     --role=roles/bigquery.dataEditor da-hackathon-2026:texas_longhorns
   gcloud iam service-accounts keys create key.json --iam-account="$SA"
   gh secret set GCP_SA_KEY < key.json --repo sodafe-01/ncaa-championship-predictor
   rm key.json
   ```
2. Turn the BigQuery jobs on:
   ```bash
   gh variable set CI_BQ_ENABLED --body true --repo sodafe-01/ncaa-championship-predictor
   ```

## Branch protection (gating)

`main` requires:
- a pull request,
- the **validate** check to pass,
- the branch to be **up to date with `main`** before merging (forces conflicts to
  be resolved in the PR, so a merge can't silently break `main`).

Direct pushes to `main` are disabled for non-admins.

## Note for contributors with stale branches

Branches cut before the CI/cleanup landed may re-introduce the removed `bq/`
pipeline or delete `docs/`. **Rebase onto `main` before opening/merging a PR**
(`git fetch origin && git rebase origin/main`) so the up-to-date check passes and
you don't clobber current files.
