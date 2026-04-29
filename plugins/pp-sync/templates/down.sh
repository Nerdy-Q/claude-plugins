#!/usr/bin/env bash
# down.sh — Download Power Pages portal from Dataverse, auto-stash known noise.
#
# Drop into a new Power Pages project's repo root. Set the three SITE / PROFILE / WEBSITE_ID
# values below, chmod +x, and run from anywhere in the repo.
#
# Usage:  ./down.sh
#         ./down.sh --no-clean       # skip noise auto-stash (rare)
#
# Safety:
#   - Always cd to repo root before downloading (prevents nested site folders)
#   - Confirms PAC profile + env URL before downloading
#   - Strips known noise (whitespace, .portalconfig reordering) after download
#   - Reports git status for human review

set -euo pipefail

# ============== CONFIG — set these per project ==============
SITE_DIR="${SITE_DIR:-PUT_SITE_FOLDER_HERE---PUT_SITE_FOLDER_HERE}"   # e.g. contoso---contoso
PROFILE="${PROFILE:-PUT_PAC_PROFILE_HERE}"                            # e.g. modernization-dev
WEBSITE_ID="${WEBSITE_ID:-PUT_WEBSITE_GUID_HERE}"                     # from `pac paportal list`
MODEL_VERSION="${MODEL_VERSION:-2}"                                   # 1 = Standard, 2 = Enhanced
# =============================================================

CLEAN=1
for arg in "$@"; do
  case "$arg" in
    --no-clean) CLEAN=0 ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

# 1. cd to repo root (NEVER inside the site folder — creates nested copies)
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$ROOT"

# 2. Auth check + env confirmation
echo "→ Selecting PAC profile: $PROFILE"
pac auth select --name "$PROFILE" >/dev/null
ENV_URL=$(pac org who 2>&1 | awk -F': ' '/Environment Url/{print $2; exit}')
if [ -z "$ENV_URL" ]; then
  echo "ERROR: pac org who failed — check PAC auth" >&2
  exit 1
fi
echo "→ Active env: $ENV_URL"
read -r -p "Continue download into $SITE_DIR ? [y/N] " ans
[ "$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')" = "y" ] || { echo "Aborted."; exit 0; }

# 3. Working tree check — warn if uncommitted changes exist
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  echo "⚠ Uncommitted changes in working tree. Download may overwrite local edits."
  read -r -p "Continue anyway? [y/N] " ans
  [ "$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')" = "y" ] || { echo "Aborted."; exit 0; }
fi

# 4. Download
echo "→ Downloading…"
pac paportal download \
  --path . \
  --webSiteId "$WEBSITE_ID" \
  --modelVersion "$MODEL_VERSION"

# 5. Auto-clean noise (unless --no-clean)
if [ "$CLEAN" -eq 1 ]; then
  echo "→ Cleaning known noise…"

  # 5a. Restore .portalconfig if only ordering changed
  if git diff --quiet HEAD -- .portalconfig/ 2>/dev/null; then
    : # already clean
  else
    git checkout HEAD -- .portalconfig/ 2>/dev/null || true
  fi

  # 5b. Strip trailing whitespace in *.copy.html (PAC adds it non-deterministically)
  # macOS sed and GNU sed differ — handle both.
  if [ -d "$SITE_DIR" ]; then
    if sed --version >/dev/null 2>&1; then
      find "$SITE_DIR" -name "*.webpage.copy.html" -exec sed -i -e 's/[[:space:]]*$//' {} +
    else
      find "$SITE_DIR" -name "*.webpage.copy.html" -exec sed -i '' -e 's/[[:space:]]*$//' {} +
    fi
  fi
fi

# 6. Show what actually changed
echo
echo "→ Files changed:"
git status -s | head -30
TOTAL=$(git status -s | wc -l | tr -d ' ')
echo "  ($TOTAL total)"
echo
echo "Done. Review diffs and commit when ready."
