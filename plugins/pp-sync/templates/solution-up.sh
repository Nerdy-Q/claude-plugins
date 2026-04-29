#!/usr/bin/env bash
# solution-up.sh — Pack and import a Dataverse solution.
#
# DESTRUCTIVE: solution import immediately changes Dataverse schema in the target env.
# Always confirm the env before running. Always have a backup plan for prod.
#
# Usage:  ./solution-up.sh
#         ./solution-up.sh AnotherSolution

set -euo pipefail

# ============== CONFIG ==============
SOLUTION="${1:-${SOLUTION:-PUT_SOLUTION_UNIQUE_NAME_HERE}}"
PROFILE="${PROFILE:-PUT_PAC_PROFILE_HERE}"
SCHEMA_DIR="${SCHEMA_DIR:-./dataverse-schema}"
# =====================================

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$ROOT"

UNPACK_DIR="$SCHEMA_DIR/$SOLUTION"
ZIPFILE="$SCHEMA_DIR/${SOLUTION}.zip"

if [ ! -d "$UNPACK_DIR" ]; then
  echo "ERROR: $UNPACK_DIR does not exist. Did you run solution-down.sh first?" >&2
  exit 1
fi

# 1. Auth + env confirm (DOUBLE confirm for prod)
echo "→ Selecting PAC profile: $PROFILE"
pac auth select --name "$PROFILE" >/dev/null
ENV_URL=$(pac org who 2>&1 | awk -F': ' '/Environment Url/{print $2; exit}')
echo "→ Active env: $ENV_URL"
echo "⚠ Solution import is DESTRUCTIVE — it overwrites schema in the target env."
read -r -p "Confirm import '$SOLUTION' to $ENV_URL ? [y/N] " ans
[ "$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')" = "y" ] || { echo "Aborted."; exit 0; }

case "$ENV_URL" in
  *prod*)
    echo "⚠⚠⚠  PRODUCTION ENVIRONMENT  ⚠⚠⚠"
    read -r -p "Type the solution name '$SOLUTION' to confirm prod import: " confirm
    [ "$confirm" = "$SOLUTION" ] || { echo "Aborted."; exit 0; }
    ;;
esac

# 2. Pack
echo "→ Packing $UNPACK_DIR into $ZIPFILE"
pac solution pack \
  --folder "$UNPACK_DIR" \
  --zipfile "$ZIPFILE" \
  --packagetype Unmanaged

# 3. Import
echo "→ Importing… (may take several minutes)"
pac solution import \
  --path "$ZIPFILE" \
  --publish-changes \
  --activate-plugins

# 4. Cleanup
rm -f "$ZIPFILE"

echo
echo "Done. Verify in Maker Portal: $ENV_URL"
