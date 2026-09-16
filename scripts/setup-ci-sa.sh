#!/usr/bin/env bash
# One-shot setup to enable the BigQuery CI/CD jobs (e2e + deploy).
# MUST be run by a project Owner of da-hackathon-2026 who also owns the
# texas_longhorns dataset (e.g. srabasti.banerjee@66degrees.com).
#
# Creates a CI service account, grants BigQuery access, mints a key, and stores
# it as the GitHub secret GCP_SA_KEY, then flips CI_BQ_ENABLED=true.
#
# Prereqs: gcloud + bq + gh (authenticated), python3.
set -euo pipefail

PROJECT="da-hackathon-2026"
DATASET="texas_longhorns"
SRC_DATASET="ncaa_basketball"
REPO="sodafe-01/ncaa-championship-predictor"
SA_NAME="ncaa-ci"
SA="${SA_NAME}@${PROJECT}.iam.gserviceaccount.com"

echo ">>> 1/6 Create service account (idempotent)"
gcloud iam service-accounts create "${SA_NAME}" --project "${PROJECT}" \
  --display-name "NCAA CI (GitHub Actions)" 2>/dev/null || echo "    exists, continuing"

echo ">>> 2/6 Grant project-level BigQuery Job User + Data Viewer"
gcloud projects add-iam-policy-binding "${PROJECT}" \
  --member="serviceAccount:${SA}" --role="roles/bigquery.jobUser" >/dev/null
gcloud projects add-iam-policy-binding "${PROJECT}" \
  --member="serviceAccount:${SA}" --role="roles/bigquery.dataViewer" >/dev/null
echo "    granted jobUser + dataViewer (reads ${SRC_DATASET})"

echo ">>> 3/6 Grant WRITER on ${DATASET} via dataset ACL"
TMP="$(mktemp).json"
bq show --format=prettyjson "${PROJECT}:${DATASET}" > "${TMP}"
python3 - "$TMP" "$SA" <<'PY'
import json, sys
path, sa = sys.argv[1], sys.argv[2]
d = json.load(open(path))
access = d.setdefault("access", [])
if not any(e.get("userByEmail") == sa and e.get("role") in ("WRITER", "roles/bigquery.dataEditor") for e in access):
    access.append({"role": "WRITER", "userByEmail": sa})
json.dump(d, open(path, "w"), indent=2)
print("    added WRITER for", sa)
PY
bq update --source "${TMP}" "${PROJECT}:${DATASET}"
rm -f "${TMP}"

echo ">>> 4/6 Create a service-account key"
KEY="$(mktemp).json"
gcloud iam service-accounts keys create "${KEY}" --iam-account="${SA}"

echo ">>> 5/6 Store key as GitHub secret GCP_SA_KEY"
gh secret set GCP_SA_KEY < "${KEY}" --repo "${REPO}"
rm -f "${KEY}"

echo ">>> 6/6 Enable the BigQuery CI jobs"
gh variable set CI_BQ_ENABLED --body true --repo "${REPO}"

echo "Done. Open a PR (or push to main) to see e2e / deploy run."
