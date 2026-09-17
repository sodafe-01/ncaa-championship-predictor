#!/usr/bin/env bash
# Run dbt with a fresh gcloud access token. Plain `dbt` oauth fails in this project.
# Usage (from repo root):
#   scripts/dbt.sh debug
#   scripts/dbt.sh build --select tag:de1
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DBT_DIR="${ROOT}/dbt"
export DBT_PROFILES_DIR="${DBT_DIR}"

if [[ -n "${DBT_BIN:-}" ]]; then
  :
elif [[ -x "${ROOT}/.venv/bin/dbt" ]]; then
  DBT_BIN="${ROOT}/.venv/bin/dbt"
elif command -v dbt >/dev/null 2>&1; then
  DBT_BIN="$(command -v dbt)"
elif [[ -x "${HOME}/s2t-dbt-env/bin/dbt" ]]; then
  DBT_BIN="${HOME}/s2t-dbt-env/bin/dbt"
else
    echo "dbt not found. python3 -m venv .venv && .venv/bin/pip install -r requirements.txt" >&2
  exit 1
fi

TARGET="${DBT_TARGET:-token}"
if [[ "${TARGET}" == "token" && -z "${GCP_ACCESS_TOKEN:-}" ]]; then
  # dbt cannot refresh this token, so it must outlive the whole run. `gcloud auth print-access-token`
  # returns a cached token that can be minutes from expiry (a full build failed mid-run that way);
  # `gcloud auth application-default print-access-token` mints a fresh ~60-minute token on every call.
  # Fall back to the cached gcloud token when Application Default Credentials aren't set up.
  if ! GCP_ACCESS_TOKEN="$(gcloud auth application-default print-access-token 2>/dev/null)" \
    || [[ -z "${GCP_ACCESS_TOKEN}" ]]; then
    echo "dbt.sh: no Application Default Credentials; using the cached gcloud token (may expire mid-run)." >&2
    GCP_ACCESS_TOKEN="$(gcloud auth print-access-token)"
  fi
  export GCP_ACCESS_TOKEN
fi

cd "${DBT_DIR}"
exec "${DBT_BIN}" "$@" --project-dir "${DBT_DIR}" --profiles-dir "${DBT_PROFILES_DIR}" --target "${TARGET}"
