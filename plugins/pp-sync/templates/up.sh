#!/usr/bin/env bash
# up.sh — Upload local Power Pages portal changes to Dataverse with bulk-upload safety.
#
# Drop into a new project's repo root. Set the SITE_DIR / PROFILE values, chmod +x.
#
# Usage:  ./up.sh
#         ./up.sh --validate-only    # dry run, no actual upload
#         ./up.sh --force-bulk       # skip the 50-file warning
#
# Safety:
#   - Always cd to repo root before uploading
#   - Confirms PAC profile + env URL before uploading
#   - Warns when about to upload more than 50 files (cache hang risk)
#   - Reports counts after upload

set -euo pipefail

# ============== CONFIG — set these per project ==============
SITE_DIR="${SITE_DIR:-PUT_SITE_FOLDER_HERE---PUT_SITE_FOLDER_HERE}"
PROFILE="${PROFILE:-PUT_PAC_PROFILE_HERE}"
MODEL_VERSION="${MODEL_VERSION:-2}"
BULK_THRESHOLD="${BULK_THRESHOLD:-50}"
# =============================================================

VALIDATE_ONLY=0
FORCE_BULK=0
for arg in "$@"; do
  case "$arg" in
    --validate-only) VALIDATE_ONLY=1 ;;
    --force-bulk)    FORCE_BULK=1 ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

# 1. cd to repo root
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

# Extra warning for prod env URLs
case "$ENV_URL" in
  *prod*)
    echo "⚠⚠⚠  PRODUCTION ENVIRONMENT  ⚠⚠⚠"
    read -r -p "Are you SURE you want to upload to prod? Type 'yes' to continue: " ans
    [ "$ans" = "yes" ] || { echo "Aborted."; exit 0; }
    ;;
esac

# 3. Estimate change count by tracked + untracked files in SITE_DIR
TRACKED=$(git diff --name-only HEAD -- "$SITE_DIR" 2>/dev/null || true)
UNTRACKED=$(git ls-files --others --exclude-standard -- "$SITE_DIR" 2>/dev/null || true)
CHANGED=$(printf '%s\n%s\n' "$TRACKED" "$UNTRACKED" | grep -v '^$' | sort -u | wc -l | tr -d ' ')
echo "→ Estimated changed files in $SITE_DIR: $CHANGED"

if [ "$CHANGED" -gt "$BULK_THRESHOLD" ] && [ "$FORCE_BULK" -eq 0 ]; then
  cat <<EOF

⚠ BULK UPLOAD WARNING
You're about to upload $CHANGED files. Power Pages can hang the portal cache
when many files upload at once (>$BULK_THRESHOLD), requiring a manual restart from
Power Platform Admin Center.

Recommended: upload incrementally (group by directory, verify between batches).

Options:
  --validate-only    do a dry run first
  --force-bulk       proceed despite the warning (you've been told)

EOF
  read -r -p "Continue with bulk upload? [y/N] " ans
  [ "$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')" = "y" ] || { echo "Aborted."; exit 0; }
fi

# 4. Upload (or validate)
if [ "$VALIDATE_ONLY" -eq 1 ]; then
  echo "→ Validating without committing…"
  pac paportal upload \
    --path . \
    --modelVersion "$MODEL_VERSION" \
    --validateBeforeUpload
else
  echo "→ Uploading…"
  pac paportal upload \
    --path . \
    --modelVersion "$MODEL_VERSION"
fi

# 5. Post-upload smoke test — try to load the portal
PORTAL_URL=$(echo "$ENV_URL" | sed 's|crm\.dynamics\.com|powerappsportals.com|; s|crm9\.dynamics\.com|powerappsportals.us|')
if [ -n "$PORTAL_URL" ]; then
  echo
  echo "→ Smoke-testing $PORTAL_URL"
  STATUS=$(curl -sI -o /dev/null -w "%{http_code}" --max-time 30 "$PORTAL_URL" || echo "000")
  case "$STATUS" in
    200) echo "  ✓ Portal returns 200" ;;
    503) echo "  ⚠ 503 (cache rebuilding) — wait 30-60s and retry" ;;
    000) echo "  ⚠ Timeout — portal may be hung. Check Power Platform Admin Center." ;;
    *)   echo "  ⚠ HTTP $STATUS — investigate" ;;
  esac
fi

echo
echo "Done."
