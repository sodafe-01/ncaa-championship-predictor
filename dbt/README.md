# dbt project for texas_longhorns

Season slice: **2017** (`var ncaa_season`). Dataset: `da-hackathon-2026.texas_longhorns`.

## One-time setup

From the repo root:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

`.venv` is already gitignored. Do not use a global `pip install dbt`.

## Daily use (no `dbt.sh`)

dbt is not on your PATH until the venv is active. Profiles live in this repo (`dbt/profiles.yml`), not in `~/.dbt` (that file is a different project).

```bash
source .venv/bin/activate
export DBT_PROFILES_DIR="$PWD/dbt"
cd dbt
dbt debug
dbt compile
dbt build --select tag:de1
```

After `source .venv/bin/activate`, `which dbt` should show `.../ncaa-championship-predictor/.venv/bin/dbt`.

`scripts/dbt.sh` is optional. It does the same venv + profiles-dir wiring if you prefer not to export the env vars.
