#!/usr/bin/env bash
# Regression tests for the journal active-issue state tracking
# introduced in v2.9.5. Closes the "note/close picks closed issue"
# correctness gap and the "concurrent open interleaves entries" race.
#
# Run: ./plugins/pp-sync/tests/test_journal_state.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PP_BIN="$SCRIPT_DIR/../bin/pp"

[ -f "$PP_BIN" ] || { echo "Cannot find bin/pp at $PP_BIN" >&2; exit 1; }

PASS=0
FAIL=0
FAIL_NAMES=()

TMPDIRS=()
cleanup_tmpdirs() {
    local tmp
    # `${arr[@]:-}` for bash 3.2 set -u compatibility — empty array
    # reference would otherwise abort.
    for tmp in "${TMPDIRS[@]:-}"; do
        [ -n "$tmp" ] && rm -rf "$tmp"
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

# Source bin/pp so we can call helper functions directly. Set up a
# minimal env first so the helpers' references resolve.
make_env() {
    local tmp
    tmp=$(mktemp -d)
    TMPDIRS+=( "$tmp" )
    mkdir -p "$tmp/pp/projects" "$tmp/repo"
    {
        printf 'NAME="proj"\n'
        printf 'REPO="%s/repo"\n' "$tmp"
        printf 'SITE_DIR="."\n'
        printf 'PROFILE="profile"\n'
    } > "$tmp/pp/projects/proj.conf"
    ( cd "$tmp/repo" && git init -q && git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init ) >/dev/null 2>&1
    printf '%s\n' "$tmp"
}

# --- Section 1: state file lifecycle ------------------------------------

echo "Section 1 — journal_set / journal_active / journal_clear"
echo

env_root=$(make_env)
test_url="https://github.com/Nerdy-Q/claude-power-pages-plugins/issues/42"

result=$(
    (
        export PP_CONFIG_DIR="$env_root/pp"
        export PP_PROJECTS_DIR="$env_root/pp/projects"
        export PP_ALIASES_FILE="$env_root/pp/aliases"
        : > "$PP_ALIASES_FILE"
        # shellcheck source=/dev/null
        . "$PP_BIN" >/dev/null 2>&1 || true
        # shellcheck disable=SC2034  # REPO is read by sourced helpers
        REPO="$env_root/repo"

        # Initially empty
        a1=$(journal_active_issue_for proj || true)
        # Set
        journal_set_active_issue proj "$test_url"
        a2=$(journal_active_issue_for proj)
        # Clear
        journal_clear_active_issue proj
        a3=$(journal_active_issue_for proj || true)
        # Output as comma-separated for the parent test
        printf '%s|%s|%s\n' "$a1" "$a2" "$a3"
    )
)
IFS='|' read -r a1 a2 a3 <<< "$result"
[ -z "$a1" ] && assert_pass "no state file → empty active issue" \
    || assert_fail "expected empty initial state" "got '$a1'"
[ "$a2" = "$test_url" ] && assert_pass "set then read returns the URL" \
    || assert_fail "set/read mismatch" "set='$test_url' got='$a2'"
[ -z "$a3" ] && assert_pass "clear → empty active issue" \
    || assert_fail "clear didn't empty state" "got '$a3'"

# --- Section 2: open writes state, close clears it ----------------------

echo
echo "Section 2 — open|close lifecycle (no remote board, local-only)"
echo

env_root=$(make_env)
state_file="$env_root/pp/state/proj/active-issue"

PP_CONFIG_DIR="$env_root/pp" "$PP_BIN" journal proj init >/dev/null 2>&1 || true
PP_CONFIG_DIR="$env_root/pp" "$PP_BIN" journal proj open "Test task" >/dev/null 2>&1 || true

# With no board configured, open writes "Started local journal entry"
# and (per v2.9.5 fix) calls journal_clear_active_issue. So state file
# should NOT exist after a board-less open.
[ ! -f "$state_file" ] && assert_pass "open without board: state file not created (nothing to track)" \
    || assert_fail "open without board: state file unexpectedly exists" \
        "contents: $(cat "$state_file" 2>/dev/null)"

# Verify JOURNAL.md got the entry atomically (one task header)
header_count=$(grep -c '^## \[' "$env_root/repo/JOURNAL.md" 2>/dev/null || echo 0)
[ "$header_count" = "1" ] && assert_pass "open wrote exactly one task header" \
    || assert_fail "expected 1 task header, got $header_count"

# --- Section 3: stale-state safety — open clears prior state ------------

echo
echo "Section 3 — stale state from prior open is cleared on new open"
echo

env_root=$(make_env)
mkdir -p "$env_root/pp/state/proj"
echo "https://github.com/old/stale/issues/99" > "$env_root/pp/state/proj/active-issue"

PP_CONFIG_DIR="$env_root/pp" "$PP_BIN" journal proj init >/dev/null 2>&1 || true
PP_CONFIG_DIR="$env_root/pp" "$PP_BIN" journal proj open "New task" >/dev/null 2>&1 || true

# Without a board, the new open should clear the stale state.
state_after=$(cat "$env_root/pp/state/proj/active-issue" 2>/dev/null || echo "")
[ -z "$state_after" ] && assert_pass "stale state cleared by board-less open" \
    || assert_fail "stale state not cleared" "still: '$state_after'"

# --- Section 4: backward-compat — reads JOURNAL.md when state absent ----

echo
echo "Section 4 — JOURNAL.md fallback when state file doesn't exist"
echo

env_root=$(make_env)
# Pre-existing JOURNAL.md from a pre-v2.9.5 era
cat > "$env_root/repo/JOURNAL.md" <<'EOF'
# Work Journal

## [2026-04-29 12:00] TASK: legacy task
Issue: https://github.com/Nerdy-Q/claude-power-pages-plugins/issues/77
---
EOF

result=$(
    (
        export PP_CONFIG_DIR="$env_root/pp"
        export PP_PROJECTS_DIR="$env_root/pp/projects"
        export PP_ALIASES_FILE="$env_root/pp/aliases"
        : > "$PP_ALIASES_FILE"
        # shellcheck source=/dev/null
        . "$PP_BIN" >/dev/null 2>&1 || true
        # shellcheck disable=SC2034  # REPO is read by sourced helpers
        REPO="$env_root/repo"
        journal_active_issue_for proj
    )
)
expected="https://github.com/Nerdy-Q/claude-power-pages-plugins/issues/77"
[ "$result" = "$expected" ] && assert_pass "fallback reads Issue: line from JOURNAL.md" \
    || assert_fail "fallback failed" "got '$result' expected '$expected'"

# --- Section 5: concurrent open writes don't interleave entries ---------

echo
echo "Section 5 — concurrent open is atomic (single-write, no interleave)"
echo

env_root=$(make_env)
PP_CONFIG_DIR="$env_root/pp" "$PP_BIN" journal proj init >/dev/null 2>&1 || true

# Run 5 concurrent opens with distinct titles. Then verify each title
# appears exactly once on its own line.
for i in 1 2 3 4 5; do
    PP_CONFIG_DIR="$env_root/pp" "$PP_BIN" journal proj open "ConcurrentTask$i" >/dev/null 2>&1 &
done
wait

# Each "## [TIME] TASK: ConcurrentTaskN" should appear exactly once,
# and no two task headers should be on the same line.
all_titles_present=1
for i in 1 2 3 4 5; do
    count=$(grep -c "TASK: ConcurrentTask$i$" "$env_root/repo/JOURNAL.md" 2>/dev/null || echo 0)
    [ "$count" = "1" ] || { all_titles_present=0; printf '  task %d: %s occurrences\n' "$i" "$count" >&2; }
done
[ "$all_titles_present" = "1" ] && assert_pass "all 5 concurrent task headers present, exactly once each" \
    || assert_fail "concurrent open interleaved or dropped task headers"

# Verify no header line is corrupted (contains another task title)
corrupt_lines=$(grep -E 'ConcurrentTask[1-5].*ConcurrentTask[1-5]' "$env_root/repo/JOURNAL.md" 2>/dev/null | wc -l | tr -d ' ')
[ "${corrupt_lines:-0}" = "0" ] && assert_pass "no two task headers on same line (no interleaving)" \
    || assert_fail "concurrent writes interleaved on a single line" \
        "$(grep -E 'ConcurrentTask[1-5].*ConcurrentTask[1-5]' "$env_root/repo/JOURNAL.md")"

# --- Section 6: project remove cleans up state dir ---------------------

echo
echo "Section 6 — project remove cleans state dir"
echo

env_root=$(make_env)
mkdir -p "$env_root/pp/state/proj"
echo "https://github.com/foo/bar/issues/1" > "$env_root/pp/state/proj/active-issue"

printf 'y\n' | PP_CONFIG_DIR="$env_root/pp" "$PP_BIN" project remove proj >/dev/null 2>&1 || true

[ ! -d "$env_root/pp/state/proj" ] && assert_pass "project remove deleted state/<project>/" \
    || assert_fail "state dir survived project remove"

# --- Summary -----------------------------------------------------------

echo
if [ "$FAIL" -eq 0 ]; then
    printf '%d/%d passed\n' "$PASS" "$((PASS + FAIL))"
    exit 0
else
    printf '%d/%d passed; failures: %s\n' "$PASS" "$((PASS + FAIL))" "${FAIL_NAMES[*]}" >&2
    exit 1
fi
