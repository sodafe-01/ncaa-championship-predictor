#!/usr/bin/env bash
# Always run dbt through this script from the repo root:
#   scripts/dbt.sh debug
#   scripts/dbt.sh build --select tag:de1
#
# Default target `dev` uses gcloud ADC (method: oauth).
# If that fails (hackathon IAM), run:
#   GCP_ACCESS_TOKEN="$(gcloud auth print-access-token)" scripts/dbt.sh debug
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
  echo "dbt not found. From the repo root run:" >&2
  echo "  python3 -m venv .venv && .venv/bin/pip install -r requirements.txt" >&2
  echo "Then retry: scripts/dbt.sh debug" >&2
  exit 1
fi

TARGET="${DBT_TARGET:-dev}"
if [[ -n "${GCP_ACCESS_TOKEN:-}" ]]; then
  TARGET=token
fi

cd "${DBT_DIR}"
exec "${DBT_BIN}" "$@" --project-dir "${DBT_DIR}" --profiles-dir "${DBT_PROFILES_DIR}" --target "${TARGET}"
