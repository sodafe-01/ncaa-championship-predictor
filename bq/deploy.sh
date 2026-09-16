#!/usr/bin/env bash
# Deploy BigQuery SQL artifacts to a project/dataset.
# Usage:
#   PROJECT=da-hackathon-2026 DATASET=texas_longhorns bash bq/deploy.sh            # deploy core files
#   PROJECT=... DATASET=... bash bq/deploy.sh bq/sql/05_v_team_scouting.sql        # deploy one file
# Optional: DRY_RUN=1 to validate without executing; CONNECTION=... for AI.GENERATE.
set -euo pipefail

PROJECT="${PROJECT:?set PROJECT (e.g. da-hackathon-2026)}"
DATASET="${DATASET:?set DATASET (e.g. texas_longhorns)}"
CONNECTION="${CONNECTION:-}"
DRY_RUN="${DRY_RUN:-0}"
LOCATION="${LOCATION:-US}"

# Core deploy order (05 is optional/manual because it needs a Vertex connection).
if [ "$#" -gt 0 ]; then
  FILES=("$@")
else
  FILES=(
    bq/sql/01_feat_team_season.sql
    bq/sql/02_matchup_training.sql
    bq/sql/03_matchup_model.sql
    bq/sql/04_v_champion_probabilities.sql
    bq/sql/06_backtest.sql
    bq/sql/00_descriptions.sql
  )
fi

FLAGS=(--use_legacy_sql=false --project_id="$PROJECT" --location="$LOCATION")
[ "$DRY_RUN" = "1" ] && FLAGS+=(--dry_run)

# Ensure target dataset exists (no-op if present).
bq --project_id="$PROJECT" --location="$LOCATION" mk -f --dataset "$PROJECT:$DATASET" >/dev/null 2>&1 || true

LBL=""; [ "$DRY_RUN" = "1" ] && LBL="[dry-run] "
for f in "${FILES[@]}"; do
  echo ">>> ${LBL}$f"
  sed -e "s/__PROJECT__/$PROJECT/g" \
      -e "s/__DATASET__/$DATASET/g" \
      -e "s|__CONNECTION__|$CONNECTION|g" \
      "$f" | bq query "${FLAGS[@]}"
done
echo "Done."
