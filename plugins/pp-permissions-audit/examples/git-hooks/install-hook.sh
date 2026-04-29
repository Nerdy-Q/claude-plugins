#!/usr/bin/env bash
# Power Pages permissions audit — pre-commit hook installer
#
# Run from the root of your Power Pages project's git repo:
#   ~/.claude/plugins/cache/nq-claude-power-pages-plugins/pp-permissions-audit/<version>/examples/git-hooks/install-hook.sh
#
# What it does:
#   1. Verifies cwd is a git repo
#   2. Locates the pre-commit template (next to this installer)
#   3. Backs up any existing .git/hooks/pre-commit to .pre-commit.bak.<timestamp>
#   4. Symlinks (preferred) or copies the template into .git/hooks/pre-commit
#   5. chmod +x the result
#
# To uninstall: `rm .git/hooks/pre-commit` (and optionally restore the .bak).

set -euo pipefail

# ----- 1. Verify cwd is a git repo -----------------------------------------
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null || true)
if [ -z "$GIT_DIR" ]; then
  echo "ERROR: not a git repository (cwd: $(pwd))" >&2
  echo "Run this installer from the root of your Power Pages project's repo." >&2
  exit 1
fi

# ----- 2. Locate the pre-commit template -----------------------------------
# Resolve the directory holding this installer, even if invoked via symlink.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TEMPLATE="$SCRIPT_DIR/pre-commit"

if [ ! -f "$TEMPLATE" ]; then
  # Fall back to the plugin cache (in case someone copies just this installer).
  PLUGIN_CACHE="$HOME/.claude/plugins/cache/nq-claude-power-pages-plugins/pp-permissions-audit"
  if [ ! -d "$PLUGIN_CACHE" ]; then
    PLUGIN_CACHE="$HOME/.claude/plugins/cache/nq-claude-plugins/pp-permissions-audit"
  fi
  TEMPLATE=$(find "$PLUGIN_CACHE" -maxdepth 4 -path '*/examples/git-hooks/pre-commit' 2>/dev/null \
             | sort -V | tail -1)
fi

if [ -z "$TEMPLATE" ] || [ ! -f "$TEMPLATE" ]; then
  echo "ERROR: pre-commit template not found." >&2
  echo "Expected next to this installer or under:" >&2
  echo "  ~/.claude/plugins/cache/nq-claude-power-pages-plugins/pp-permissions-audit/<version>/examples/git-hooks/pre-commit" >&2
  exit 1
fi

# ----- 3. Back up any existing hook ----------------------------------------
HOOK_DIR="$GIT_DIR/hooks"
HOOK_PATH="$HOOK_DIR/pre-commit"
mkdir -p "$HOOK_DIR"

if [ -e "$HOOK_PATH" ] || [ -L "$HOOK_PATH" ]; then
  TS=$(date -u +%Y%m%dT%H%M%SZ)
  BACKUP="$HOOK_DIR/pre-commit.bak.$TS"
  mv "$HOOK_PATH" "$BACKUP"
  echo "Backed up existing hook: $BACKUP"
fi

# ----- 4. Symlink (preferred) or copy --------------------------------------
# Symlink keeps the hook in sync if the plugin updates. On platforms where
# symlinks fail (e.g. some Windows + msys configs without dev-mode), fall
# back to a copy.
if ln -s "$TEMPLATE" "$HOOK_PATH" 2>/dev/null; then
  INSTALL_MODE="symlink"
else
  cp "$TEMPLATE" "$HOOK_PATH"
  INSTALL_MODE="copy"
fi

chmod +x "$HOOK_PATH"

# ----- 5. Report -----------------------------------------------------------
cat <<EOF
pp-permissions-audit pre-commit hook installed.

  Location: $HOOK_PATH
  Source:   $TEMPLATE
  Mode:     $INSTALL_MODE

Test it without committing real work:
  git commit --allow-empty -m 'test pp-audit hook'

Bypass on a one-off (NOT recommended):
  git commit --no-verify

Uninstall:
  rm "$HOOK_PATH"
EOF
