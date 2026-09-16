# dbt project for texas_longhorns

Vars: `first_model_season=2014`, `last_season=2017`, `forecast_season=2018`. Dataset: `da-hackathon-2026.texas_longhorns`.

## Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Run from the venv

`profiles.yml` lives in this folder, not in `~/.dbt`. Set `DBT_PROFILES_DIR` from the **repo root** (not from inside `dbt/`, or the path becomes `dbt/dbt`):

```bash
source .venv/bin/activate
export DBT_PROFILES_DIR="$PWD/dbt"
cd dbt
dbt debug
```

Already in `dbt/`? Use `export DBT_PROFILES_DIR="$PWD"` instead.

If ADC oauth fails in this project:

```bash
scripts/dbt.sh debug
```

That uses the `token` target and sets `GCP_ACCESS_TOKEN` for you.

A bare `scripts/dbt.sh build` uses selector `routine` and skips `tag:ai`.
