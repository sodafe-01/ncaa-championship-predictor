#!/usr/bin/env bash
# Local checks that do not need BigQuery.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

RUFF_BIN="${ROOT}/.venv/bin/ruff"
if [[ ! -x "${RUFF_BIN}" ]]; then
  if command -v ruff >/dev/null 2>&1; then
    RUFF_BIN="$(command -v ruff)"
  else
    echo "ruff not found. pip install -r requirements.txt into .venv" >&2
    exit 1
  fi
fi

"${RUFF_BIN}" check scripts

DBT_BIN="${ROOT}/.venv/bin/dbt"
if [[ ! -x "${DBT_BIN}" ]]; then
  if command -v dbt >/dev/null 2>&1; then
    DBT_BIN="$(command -v dbt)"
  else
    echo "dbt not found." >&2
    exit 1
  fi
fi

export DBT_PROFILES_DIR="${ROOT}/dbt"
# parse does not call BigQuery; a dummy token satisfies oauth-secrets interpolation
export GCP_ACCESS_TOKEN="${GCP_ACCESS_TOKEN:-parse-only}"
"${DBT_BIN}" parse --project-dir "${ROOT}/dbt" --profiles-dir "${ROOT}/dbt"
