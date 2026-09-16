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

> **Requires a project Owner** of `da-hackathon-2026` who also owns the
> `texas_longhorns` dataset (creating a service account + editing dataset ACLs
> needs IAM-admin, which regular contributors do not have).

Run the one-shot helper:

```bash
bash scripts/setup-ci-sa.sh
```

It creates the `ncaa-ci` service account, grants `bigquery.jobUser` +
`bigquery.dataViewer` (project) and `WRITER` on `texas_longhorns`, mints a key,
stores it as the `GCP_SA_KEY` GitHub secret, and sets `CI_BQ_ENABLED=true`.

If your org disables service-account keys, use **Workload Identity Federation**
instead (keyless) and switch the `auth` step in `ci.yml` to
`workload_identity_provider`.

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
