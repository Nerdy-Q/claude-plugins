#!/usr/bin/env bash
# solution-down.sh — Export Dataverse solution and unpack into source-controllable form.
#
# Drop into a project's repo root. Set the SOLUTION + PROFILE values, chmod +x.
#
# Usage:  ./solution-down.sh
#         ./solution-down.sh AnotherSolution    # override SOLUTION

set -euo pipefail

# ============== CONFIG ==============
SOLUTION="${1:-${SOLUTION:-PUT_SOLUTION_UNIQUE_NAME_HERE}}"
PROFILE="${PROFILE:-PUT_PAC_PROFILE_HERE}"
SCHEMA_DIR="${SCHEMA_DIR:-./dataverse-schema}"
# =====================================

case "$SOLUTION$PROFILE" in
  *PUT_*_HERE*)
    echo "ERROR: pass solution name as arg ('./solution-down.sh MySolution') or set SOLUTION / PROFILE at the top." >&2
    exit 2
    ;;
esac

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$ROOT"

mkdir -p "$SCHEMA_DIR"
ZIPFILE="$SCHEMA_DIR/${SOLUTION}.zip"
UNPACK_DIR="$SCHEMA_DIR/${SOLUTION}"

# 1. Auth
echo "→ Selecting PAC profile: $PROFILE"
pac auth select --name "$PROFILE" >/dev/null
ENV_URL=$(pac org who 2>&1 | awk -F': ' '/Environment Url/{print $2; exit}')
echo "→ Active env: $ENV_URL"

# 2. Confirm before exporting (export takes 60-120s; user should know)
read -r -p "Export solution '$SOLUTION' from $ENV_URL ? [y/N] " ans
[ "$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')" = "y" ] || { echo "Aborted."; exit 0; }

# 3. Export — use a long timeout via curl-style; pac handles internally
echo "→ Exporting solution… (may take 60-120s)"
pac solution export \
  --name "$SOLUTION" \
  --path "$ZIPFILE" \
  --managed false

if [ ! -f "$ZIPFILE" ]; then
  echo "ERROR: export did not produce $ZIPFILE" >&2
  exit 1
fi
echo "→ Got $(du -h "$ZIPFILE" | cut -f1) export"

# 4. Unpack
echo "→ Unpacking to $UNPACK_DIR"
rm -rf "$UNPACK_DIR.new"
pac solution unpack \
  --zipfile "$ZIPFILE" \
  --folder "$UNPACK_DIR.new" \
  --packagetype Unmanaged

# 5. Atomic swap (avoids leaving a partially-unpacked dir on failure)
if [ -d "$UNPACK_DIR" ]; then
  rm -rf "$UNPACK_DIR.bak"
  mv "$UNPACK_DIR" "$UNPACK_DIR.bak"
fi
if mv "$UNPACK_DIR.new" "$UNPACK_DIR"; then
  rm -rf "$UNPACK_DIR.bak"
else
  echo "ERROR: mv to $UNPACK_DIR failed; previous copy preserved at $UNPACK_DIR.bak" >&2
  exit 1
fi

# 6. Optional: remove the .zip (it's reproducible from unpacked)
rm -f "$ZIPFILE"

echo "→ Entity count: $(find "$UNPACK_DIR/Entities" -maxdepth 1 -type d 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')"
echo "→ Files changed:"
# `{ grep || true; }` swallows grep's non-zero exit when it finds zero
# matches (clean re-export); without this, set -euo pipefail aborts the
# script before "Done" prints.
git status -s | { grep "$SCHEMA_DIR" || true; } | head -10

echo
echo "Done. Review diffs and commit when ready."
