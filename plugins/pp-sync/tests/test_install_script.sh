#!/usr/bin/env bash
# Regression tests for plugins/pp-sync/install.sh — the first-run setup
# script that symlinks bin/pp into ~/.local/bin/, creates the config dir,
# and (when present) installs shell completions.
#
# Each test runs install.sh against a $BIN_DIR + $PP_CONFIG_DIR pointing
# at a tmpdir, then asserts on the resulting filesystem state.
#
# Run from anywhere: ./plugins/pp-sync/tests/test_install_script.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_SH="$PLUGIN_DIR/install.sh"
PP_BIN="$PLUGIN_DIR/bin/pp"

[ -f "$INSTALL_SH" ] || { echo "Cannot find install.sh at $INSTALL_SH" >&2; exit 1; }
[ -f "$PP_BIN" ] || { echo "Cannot find bin/pp at $PP_BIN" >&2; exit 1; }

PASS=0
FAIL=0
FAIL_NAMES=()

TMPDIRS=()
cleanup_tmpdirs() {
    local tmp
    for tmp in "${TMPDIRS[@]}"; do
        rm -rf "$tmp"
    done
}
trap cleanup_tmpdirs EXIT

assert_pass() {
    PASS=$((PASS + 1))
    printf '  OK   %s\n' "$1"
}

assert_fail() {
    FAIL=$((FAIL + 1))
    FAIL_NAMES+=( "$1" )
    printf '  FAIL %s\n' "$1" >&2
    [ -n "${2:-}" ] && printf '       %s\n' "$2" >&2 || true
}

# Run install.sh in a sandbox: BIN_DIR + PP_CONFIG_DIR pointing into a
# tmpdir. Echo the tmp's BIN_DIR so the caller can assert on its state.
run_install() {
    local tmp
    tmp=$(mktemp -d)
    TMPDIRS+=( "$tmp" )
    BIN_DIR="$tmp/bin" PP_CONFIG_DIR="$tmp/config" \
        bash "$INSTALL_SH" >"$tmp/stdout" 2>"$tmp/stderr" || true
    printf '%s\n' "$tmp"
}

# --- Section 1: fresh install --------------------------------------------

echo "Section 1 — fresh install"
echo

tmp=$(run_install)
bin="$tmp/bin/pp"
cfg="$tmp/config"

# The symlink exists and points at the source bin/pp
if [ -L "$bin" ]; then
    target=$(readlink "$bin")
    if [ "$target" = "$PP_BIN" ]; then
        assert_pass "fresh install: bin/pp symlink created"
    else
        assert_fail "fresh install: symlink target wrong" "got '$target' expected '$PP_BIN'"
    fi
else
    assert_fail "fresh install: bin/pp symlink not created"
fi

# Config dir + projects subdir + aliases file
[ -d "$cfg/projects" ] && assert_pass "config dir created" \
    || assert_fail "config dir missing"
[ -f "$cfg/aliases" ] && assert_pass "aliases file created" \
    || assert_fail "aliases file missing"

# Stdout mentions next-step `pp setup`
grep -q "pp setup" "$tmp/stdout" \
    && assert_pass "install output mentions 'pp setup'" \
    || assert_fail "install output missing 'pp setup' mention"

# --- Section 2: re-run replaces existing symlink -------------------------

echo
echo "Section 2 — re-run with existing symlink"
echo

# Run install twice in the same sandbox
tmp=$(mktemp -d); TMPDIRS+=( "$tmp" )
BIN_DIR="$tmp/bin" PP_CONFIG_DIR="$tmp/config" \
    bash "$INSTALL_SH" >/dev/null 2>&1 || true
# Verify symlink exists from first run
[ -L "$tmp/bin/pp" ] || { assert_fail "first run failed"; exit 1; }
# Run again — symlink must still be valid
BIN_DIR="$tmp/bin" PP_CONFIG_DIR="$tmp/config" \
    bash "$INSTALL_SH" >/dev/null 2>&1 || true
if [ -L "$tmp/bin/pp" ] && [ "$(readlink "$tmp/bin/pp")" = "$PP_BIN" ]; then
    assert_pass "re-run with existing symlink: still points at PP_BIN"
else
    assert_fail "re-run broke the symlink"
fi

# --- Section 3: re-run backs up existing regular file --------------------

echo
echo "Section 3 — existing non-symlink file is backed up"
echo

tmp=$(mktemp -d); TMPDIRS+=( "$tmp" )
mkdir -p "$tmp/bin"
# Plant a non-symlink "pp" — could be a different tool the user already has
echo '#!/bin/sh
echo "OLD PP TOOL"' > "$tmp/bin/pp"
chmod +x "$tmp/bin/pp"

BIN_DIR="$tmp/bin" PP_CONFIG_DIR="$tmp/config" \
    bash "$INSTALL_SH" >"$tmp/stdout" 2>"$tmp/stderr" || true

# The original file should be backed up to pp.bak.<timestamp>
backup_count=$(find "$tmp/bin" -maxdepth 1 -name 'pp.bak.*' -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "$backup_count" -ge 1 ]; then
    assert_pass "existing non-symlink: backed up to pp.bak.*"
else
    assert_fail "existing non-symlink: NO backup created" \
        "files in bin/: $(ls "$tmp/bin/")"
fi

# The new symlink replaces the original at $tmp/bin/pp
if [ -L "$tmp/bin/pp" ] && [ "$(readlink "$tmp/bin/pp")" = "$PP_BIN" ]; then
    assert_pass "existing non-symlink: replaced with our symlink"
else
    assert_fail "existing non-symlink: symlink not installed"
fi

# Backup file content matches the original
backup_file=$(find "$tmp/bin" -maxdepth 1 -name 'pp.bak.*' -type f 2>/dev/null | head -1)
if [ -n "$backup_file" ] && grep -q "OLD PP TOOL" "$backup_file"; then
    assert_pass "backup preserves original content"
else
    assert_fail "backup content lost"
fi

# Install output warns the user
grep -q "Backing up" "$tmp/stdout" \
    && assert_pass "user warned about backup" \
    || assert_fail "no warning about backup in install output"

# --- Section 4: idempotent re-run on backed-up state ---------------------

echo
echo "Section 4 — re-run after backup creates no double-backup"
echo

# From section 3's state, run again — should NOT create another backup
# (existing $bin/pp is now our symlink, replace path is taken)
BIN_DIR="$tmp/bin" PP_CONFIG_DIR="$tmp/config" \
    bash "$INSTALL_SH" >/dev/null 2>&1 || true

backup_count=$(find "$tmp/bin" -maxdepth 1 -name 'pp.bak.*' -type f 2>/dev/null | wc -l | tr -d ' ')
[ "$backup_count" = "1" ] && assert_pass "no double-backup on idempotent re-run" \
    || assert_fail "expected 1 backup, found $backup_count"

# --- Section 5: PATH guidance is shown when BIN_DIR not in PATH -----------

echo
echo "Section 5 — PATH guidance"
echo

tmp=$(mktemp -d); TMPDIRS+=( "$tmp" )
# Run with BIN_DIR explicitly not in PATH (which is true since it's a tmpdir)
BIN_DIR="$tmp/notinpath" PP_CONFIG_DIR="$tmp/config" \
    bash "$INSTALL_SH" >"$tmp/stdout" 2>&1 || true

grep -q "is not in your PATH" "$tmp/stdout" \
    && assert_pass "PATH-not-in-path warning shown" \
    || assert_fail "PATH warning missing from output"

grep -q "export PATH=" "$tmp/stdout" \
    && assert_pass "PATH export instruction shown" \
    || assert_fail "PATH export instruction missing"

# --- Section 6: bin/pp is callable after install -------------------------

echo
echo "Section 6 — installed pp is callable"
echo

tmp=$(run_install)
PATH="$tmp/bin:$PATH" "$tmp/bin/pp" help >/dev/null 2>&1 \
    && assert_pass "installed pp can run 'help'" \
    || assert_fail "installed pp failed to run"

# --- Summary -------------------------------------------------------------

echo
if [ "$FAIL" -eq 0 ]; then
    printf '%d/%d passed\n' "$PASS" "$((PASS + FAIL))"
    exit 0
else
    printf '%d/%d passed; failures: %s\n' "$PASS" "$((PASS + FAIL))" "${FAIL_NAMES[*]}" >&2
    exit 1
fi
