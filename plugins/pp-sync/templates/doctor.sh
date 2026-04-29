#!/usr/bin/env bash
# doctor.sh — Power Pages portal health check.
#
# Read-only — safe to run any time. Verifies tooling, auth, and structure.
# Recommended as the first thing to run when something feels off.
#
# Usage:  ./doctor.sh

set -uo pipefail

# ============== CONFIG ==============
SITE_DIR="${SITE_DIR:-PUT_SITE_FOLDER_HERE---PUT_SITE_FOLDER_HERE}"
PROFILE="${PROFILE:-PUT_PAC_PROFILE_HERE}"
# =====================================

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$ROOT" || exit 1

OK="✓"
WARN="⚠"
FAIL="✗"

echo "Power Pages Doctor"
echo "=================="
echo "Repo root: $ROOT"
echo

# 1. Tooling
echo "## Tooling"
for tool in pac git python3 dotnet curl; do
  if command -v "$tool" >/dev/null 2>&1; then
    case "$tool" in
      pac)  ver=$(pac --version 2>/dev/null | head -1 || true) ;;
      git)  ver=$(git --version | awk '{print $3}') ;;
      *)    ver=$($tool --version 2>&1 | head -1) ;;
    esac
    echo "  $OK $tool — $ver"
  else
    echo "  $FAIL $tool — NOT FOUND"
  fi
done
echo

# 2. PAC auth
echo "## PAC Authentication"
if pac auth list 2>/dev/null | grep -q "$PROFILE"; then
  echo "  $OK Profile $PROFILE registered"
  if pac auth select --name "$PROFILE" >/dev/null 2>&1; then
    echo "  $OK Profile $PROFILE selected"
    ENV_URL=$(pac org who 2>&1 | awk -F': ' '/Environment Url/{print $2; exit}')
    if [ -n "$ENV_URL" ]; then
      echo "  $OK Connected to: $ENV_URL"
    else
      echo "  $FAIL pac org who failed"
    fi
  else
    echo "  $FAIL Could not activate $PROFILE"
  fi
else
  echo "  $FAIL Profile $PROFILE not registered. Run: pac auth create --name $PROFILE --environment <env-url>"
fi
echo

# 3. Repo structure
echo "## Repo structure"
[ -d "$SITE_DIR" ] && echo "  $OK Site folder $SITE_DIR exists" || echo "  $FAIL Site folder $SITE_DIR MISSING"
[ -f "$SITE_DIR/website.yml" ] && echo "  $OK website.yml present" || echo "  $FAIL website.yml MISSING"
[ -d "$SITE_DIR/web-pages" ] && echo "  $OK web-pages/ exists" || echo "  $FAIL web-pages/ MISSING"
[ -d "$SITE_DIR/web-templates" ] && echo "  $OK web-templates/ exists" || echo "  $FAIL web-templates/ MISSING"
[ -d "$SITE_DIR/table-permissions" ] && echo "  $OK table-permissions/ exists" || echo "  $WARN table-permissions/ missing (may be in consolidated YAML)"
echo

# 4. Git working tree
echo "## Git status"
DIRTY=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
BRANCH=$(git branch --show-current 2>/dev/null || echo "(no branch)")
echo "  Branch:           $BRANCH"
echo "  Dirty files:      $DIRTY"
if [ "$DIRTY" -gt 50 ]; then
  echo "  $WARN High dirty count — possibly PAC noise. Consider: ./down.sh; git diff to review."
fi
echo

# 5. Counts
echo "## Site content counts"
echo "  Web pages:        $(find "$SITE_DIR/web-pages" -name "*.webpage.yml" 2>/dev/null | wc -l | tr -d ' ')"
echo "  Web templates:    $(find "$SITE_DIR/web-templates" -name "*.webtemplate.source.html" 2>/dev/null | wc -l | tr -d ' ')"
echo "  Content snippets: $(find "$SITE_DIR/content-snippets" -name "*.contentsnippet.value.html" 2>/dev/null | wc -l | tr -d ' ')"
echo "  Table perms:      $(find "$SITE_DIR/table-permissions" -name "*.tablepermission.yml" 2>/dev/null | wc -l | tr -d ' ')"
echo "  Custom JS files:  $(find "$SITE_DIR/web-pages" "$SITE_DIR/web-files" -name "*.js" 2>/dev/null | wc -l | tr -d ' ')"
echo

# 6. Noise classifier — flag suspicious churn
echo "## Noise classifier"
NOISE=$(git status --porcelain 2>/dev/null | awk '$2 ~ /\.portalconfig\// {n++} END{print n+0}')
echo "  .portalconfig changes: $NOISE  (often cosmetic — review before committing)"
WS_ONLY=$(git diff --check 2>/dev/null | wc -l | tr -d ' ' || echo 0)
echo "  Whitespace-only diffs: $WS_ONLY"
echo

echo "Done."
