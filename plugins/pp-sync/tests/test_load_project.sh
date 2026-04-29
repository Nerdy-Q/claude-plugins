#!/usr/bin/env bash
# Regression tests for load_project() — the safe key=value parser that
# replaced `source "$conf"` after the 2026-04-29 audit (finding #1).
#
# Each fixture under fixtures/ exercises a specific behavior. The test
# sources bin/pp (which now guards main "$@" with a source-safe return),
# loads the fixture, and asserts on the resulting variable values OR on
# the script's exit status (when malicious input must be rejected).
#
# Run from anywhere: ./plugins/pp-sync/tests/test_load_project.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PP_BIN="$SCRIPT_DIR/../bin/pp"
FIXTURES="$SCRIPT_DIR/fixtures"

[ -f "$PP_BIN" ] || { echo "Cannot find bin/pp at $PP_BIN" >&2; exit 1; }
[ -d "$FIXTURES" ] || { echo "Cannot find fixtures at $FIXTURES" >&2; exit 1; }

PASS=0
FAIL=0
FAIL_NAMES=()

# Run a single test in a subshell so variable resets and aborts don't leak.
# Args:
#   $1: fixture name (basename without .conf)
#   $2: expected outcome — "ok" (load succeeds, assertions pass) or "die"
#   $3: bash code to eval after load (visible to load_project's variables)
run_test() {
    local fixture="$1" expect="$2" assertions="${3:-true}"
    local conf_dir
    conf_dir="$(mktemp -d)"
    mkdir -p "$conf_dir/projects"
    cp "$FIXTURES/$fixture.conf" "$conf_dir/projects/test.conf"

    local output exit_code
    output=$(
        (
            export PP_CONFIG_DIR="$conf_dir"
            export PP_PROJECTS_DIR="$conf_dir/projects"
            export PP_ALIASES_FILE="$conf_dir/aliases"
            # shellcheck source=/dev/null
            . "$PP_BIN" >/dev/null 2>&1 || true
            load_project "test"
            eval "$assertions"
        ) 2>&1
    )
    exit_code=$?
    rm -rf "$conf_dir"

    if [ "$expect" = "ok" ] && [ "$exit_code" -eq 0 ]; then
        PASS=$((PASS + 1))
        printf '  OK   %s\n' "$fixture"
    elif [ "$expect" = "die" ] && [ "$exit_code" -ne 0 ]; then
        PASS=$((PASS + 1))
        printf '  OK   %s (rejected as expected)\n' "$fixture"
    else
        FAIL=$((FAIL + 1))
        FAIL_NAMES+=( "$fixture" )
        printf '  FAIL %s — expected=%s exit=%d\n' "$fixture" "$expect" "$exit_code" >&2
        printf '       output: %s\n' "$output" >&2
    fi
}

# --- Test cases ------------------------------------------------------------

echo "Running load_project regression tests"
echo

# 1. Happy path — minimal valid conf parses correctly
run_test "minimal-valid" "ok" '
    [ "$NAME" = "minimal" ] || { echo "NAME=$NAME"; exit 1; }
    [ "$REPO" = "/tmp/repo" ] || { echo "REPO=$REPO"; exit 1; }
    [ "$SITE_DIR" = "site---site" ] || { echo "SITE_DIR=$SITE_DIR"; exit 1; }
    [ "$PROFILE" = "myprofile" ] || { echo "PROFILE=$PROFILE"; exit 1; }
    exit 0
'

# 2. SOLUTIONS array parses as multiple entries
run_test "with-solutions" "ok" '
    expected="FooSolution BarSolution BazSolution"
    got="${SOLUTIONS[*]}"
    [ "$got" = "$expected" ] || { echo "SOLUTIONS=[$got] expected=[$expected]"; exit 1; }
    exit 0
'

# 3. Empty SOLUTIONS array yields empty array
run_test "empty-solutions" "ok" '
    [ "${#SOLUTIONS[@]}" -eq 0 ] || { echo "SOLUTIONS not empty: ${SOLUTIONS[*]}"; exit 1; }
    exit 0
'

# 4. CRITICAL: command injection via REPO value must NOT execute.
#    The fixture has REPO="$(touch /tmp/pp-pwn-test-DO-NOT-EXECUTE)".
#    A correct parser preserves this as a literal string.
run_test "injection-via-repo" "ok" '
    case "$REPO" in
        *touch*) exit 0 ;;
        *) echo "REPO not literal: $REPO"; exit 1 ;;
    esac
'

# 5. CRITICAL: command injection via SOLUTION value must NOT execute
run_test "injection-via-solution" "ok" '
    case "${SOLUTIONS[0]:-}" in
        *rm*) exit 0 ;;
        *) echo "SOLUTIONS[0] not literal: ${SOLUTIONS[0]:-<empty>}"; exit 1 ;;
    esac
'

# 6. Unknown keys are warned-and-skipped, not assigned
run_test "unknown-key" "ok" '
    if [ -n "${MALICIOUS_KEY:-}" ]; then
        echo "MALICIOUS_KEY leaked: $MALICIOUS_KEY"
        exit 1
    fi
    [ "$NAME" = "unknown-key" ] || { echo "NAME=$NAME"; exit 1; }
    exit 0
'

# 7. Missing required field → die
run_test "missing-name" "die" "true"

# 8. Control character (CR) inside a value → die
run_test "control-char-cr" "die" "true"

# 9. CRITICAL: backtick command substitution must NOT execute
run_test "backtick-injection" "ok" '
    case "$REPO" in
        *touch*) exit 0 ;;
        *) echo "REPO not literal: $REPO"; exit 1 ;;
    esac
'

# 10. Mixed valid and junk content — valid keys load, junk is skipped,
#     unknown keys (PATH, RANDOM_KEY) do NOT leak into shell variables.
run_test "mixed-valid-and-junk" "ok" '
    [ "$NAME" = "mixed" ] || { echo "NAME=$NAME"; exit 1; }
    [ "$REPO" = "/tmp/repo" ] || { echo "REPO=$REPO"; exit 1; }
    [ "$SITE_DIR" = "site---site" ] || { echo "SITE_DIR=$SITE_DIR"; exit 1; }
    [ "$PROFILE" = "myprofile" ] || { echo "PROFILE=$PROFILE"; exit 1; }
    # SOLUTIONS should still parse despite the junk lines above it
    [ "${SOLUTIONS[*]}" = "Real Other" ] || { echo "SOLUTIONS=${SOLUTIONS[*]}"; exit 1; }
    exit 0
'

# 11. CRITICAL: PATH/LD_PRELOAD/HOME poisoning. The conf attempts to
#     set process-critical environment variables. The parser MUST NOT
#     touch them — only allowlisted keys are assigned.
run_test "path-poisoning" "ok" '
    case "$PATH" in
        */tmp/evil*) echo "PATH POISONED: $PATH"; exit 1 ;;
    esac
    case "${LD_PRELOAD:-}" in
        */tmp/evil*) echo "LD_PRELOAD POISONED: $LD_PRELOAD"; exit 1 ;;
    esac
    case "$HOME" in
        */tmp/evil-home*) echo "HOME POISONED: $HOME"; exit 1 ;;
    esac
    # Sanity: legitimate keys still loaded
    [ "$NAME" = "path-poison" ] || { echo "NAME=$NAME"; exit 1; }
    exit 0
'

# 12. Legitimate values with spaces (paths, URLs, comma-separated tags)
run_test "legitimate-spaces" "ok" '
    [ "$REPO" = "/Users/me/My Projects/Acme Corp" ] || { echo "REPO=$REPO"; exit 1; }
    [ "$SITE_DIR" = "acme portal/acme---acme" ] || { echo "SITE_DIR=$SITE_DIR"; exit 1; }
    [ "$ENV_URL" = "https://acme-dev.crm.dynamics.com/" ] || { echo "ENV_URL=$ENV_URL"; exit 1; }
    [ "$TAGS" = "portal, client, commercial" ] || { echo "TAGS=$TAGS"; exit 1; }
    exit 0
'

# --- Summary ---------------------------------------------------------------

echo
if [ "$FAIL" -eq 0 ]; then
    printf '%d/%d passed\n' "$PASS" "$((PASS + FAIL))"
    exit 0
else
    printf '%d/%d passed; failures: %s\n' "$PASS" "$((PASS + FAIL))" "${FAIL_NAMES[*]}" >&2
    exit 1
fi
