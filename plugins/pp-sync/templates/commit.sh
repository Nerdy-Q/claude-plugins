#!/usr/bin/env bash
# commit.sh — Interactive selective commit for Power Pages projects.
#
# Reviews status, prompts for staging mode, accepts a commit message, optionally pushes.
#
# Usage:  ./commit.sh
#         ./commit.sh "your commit message"   # skip the prompt
#
# Drop into a project's repo root. No project-specific config required.

set -euo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$ROOT"

# 1. Show current status
echo "## Current status"
git status -s
TOTAL=$(git status -s | wc -l | tr -d ' ')
echo
if [ "$TOTAL" -eq 0 ]; then
  echo "Nothing to commit."
  exit 0
fi
echo "$TOTAL changed files."
echo

# 2. Stage selection
read -r -p "Stage: [a]ll / [p]atch (interactive) / [s]elect by file / [q]uit ? " mode
case "$mode" in
  a|A) git add -A ;;
  p|P) git add -p ;;
  s|S)
    while read -r -p "File (blank to finish): " f; do
      [ -z "$f" ] && break
      git add "$f"
    done
    ;;
  *) echo "Aborted."; exit 0 ;;
esac

# 3. Show staged diff stat
echo
echo "## Staged changes"
git diff --cached --stat | tail -10

# 4. Commit message
if [ "$#" -ge 1 ]; then
  msg="$*"
else
  read -r -p "Commit message: " msg
  [ -z "$msg" ] && { echo "Aborted (empty message)."; exit 0; }
fi

# 5. Commit
git commit -m "$msg"

# 6. Optional push
read -r -p "Push to remote? [y/N] " push
if [ "$(printf '%s' "$push" | tr '[:upper:]' '[:lower:]')" = "y" ]; then
  BRANCH=$(git branch --show-current)
  git push -u origin "$BRANCH"
fi

echo "Done."
