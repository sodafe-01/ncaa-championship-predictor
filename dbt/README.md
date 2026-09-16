# dbt project for texas_longhorns

Vars: `first_model_season=2014`, `last_season=2017`, `forecast_season=2018`. Dataset: `da-hackathon-2026.texas_longhorns`.

## Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

`dbt-core` 1.12 is not used here: its parser wheel fails TLS on this machine. 1.11.7 matches a known-good install.

## Run

Always go through the token wrapper (plain dbt oauth fails in this project):

```bash
scripts/dbt.sh debug
scripts/dbt.sh compile
scripts/dbt.sh build --select tag:de1
scripts/verify.sh
```

A bare `scripts/dbt.sh build` uses selector `routine` and skips `tag:ai`.
