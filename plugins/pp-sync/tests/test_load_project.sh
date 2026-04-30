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

# Each run_test creates a tmpdir; track them so a SIGINT/SIGTERM doesn't
# leak temp directories under /tmp.
TMPDIRS=()
cleanup_tmpdirs() {
    local tmp
    for tmp in "${TMPDIRS[@]}"; do
        rm -rf "$tmp"
    done
}
trap cleanup_tmpdirs EXIT

# Run a single test in a subshell so variable resets and aborts don't leak.
# Args:
#   $1: fixture name (basename without .conf)
#   $2: expected outcome — "ok" (load succeeds, assertions pass) or "die"
#   $3: bash code to eval after load (visible to load_project's variables)
run_test() {
    local fixture="$1" expect="$2" assertions="${3:-true}"
    local conf_dir
    conf_dir="$(mktemp -d)"
    TMPDIRS+=( "$conf_dir" )
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

# 13. Empty-string values for keys-with-defaults must re-default, not blank
#     (regression for v2.7.2: parser treats `KEY=""` and "key omitted"
#     identically, so the post-parse re-default pass must run).
run_test "empty-default-values" "ok" '
    [ "$MODEL_VERSION" = "2" ] || { echo "MODEL_VERSION=$MODEL_VERSION (expected 2)"; exit 1; }
    [ "$SCHEMA_DIR" = "dataverse-schema" ] || { echo "SCHEMA_DIR=$SCHEMA_DIR"; exit 1; }
    [ "$BOARD_SYSTEM" = "auto" ] || { echo "BOARD_SYSTEM=$BOARD_SYSTEM"; exit 1; }
    [ "$AI_ATTR" = "yes" ] || { echo "AI_ATTR=$AI_ATTR"; exit 1; }
    exit 0
'

run_resolve_project_test() {
    local test_name="$1" input="$2" expected_status="$3" assertions="${4:-true}"
    local conf_dir
    conf_dir="$(mktemp -d)"
    TMPDIRS+=( "$conf_dir" )
    mkdir -p "$conf_dir/projects"
    printf 'NAME="alpha"\nREPO="/tmp"\nSITE_DIR="site"\nPROFILE="prof"\n' > "$conf_dir/projects/alpha.conf"
    printf 'NAME="beta"\nREPO="/tmp"\nSITE_DIR="site"\nPROFILE="prof"\n' > "$conf_dir/projects/beta.conf"

    local output exit_code
    output=$(
        (
            export PP_CONFIG_DIR="$conf_dir"
            export PP_PROJECTS_DIR="$conf_dir/projects"
            export PP_ALIASES_FILE="$conf_dir/aliases"
            : > "$PP_ALIASES_FILE"
            # shellcheck source=/dev/null
            . "$PP_BIN" >/dev/null 2>&1 || true
            result="$(resolve_project "$input")"
            status=$?
            [ "$status" -eq "$expected_status" ] || { echo "status=$status result=$result"; exit 1; }
            eval "$assertions"
        ) 2>&1
    )
    exit_code=$?
    rm -rf "$conf_dir"

    if [ "$exit_code" -eq 0 ]; then
        PASS=$((PASS + 1))
        printf '  OK   %s\n' "$test_name"
    else
        FAIL=$((FAIL + 1))
        FAIL_NAMES+=( "$test_name" )
        printf '  FAIL %s\n' "$test_name" >&2
        printf '       output: %s\n' "$output" >&2
    fi
}

run_resolve_project_test "resolve-project-literal-dotstar" ".*" "1" '
    [ -z "${result:-}" ] || { echo "unexpected result=$result"; exit 1; }
    exit 0
'

run_resolve_project_test "resolve-project-literal-bracket" "[" "1" '
    [ -z "${result:-}" ] || { echo "unexpected result=$result"; exit 1; }
    exit 0
'

# 14. Leading whitespace on KEY="value" lines is NOT supported. The
#     parser is strict by design — confs generated by `pp setup` /
#     `pp project add` always emit lines starting at column 0. A
#     hand-edited conf with indented lines should fail loudly with
#     "missing required field" rather than silently using empty
#     values. (The "unparsable line" warning fires per ignored line.)
run_test "leading-whitespace-rejected" "die" "true"

# 15. A conf with only comments (no key=value lines) → die on missing
#     required fields, not parse error.
run_test "only-comments" "die" "true"

# 16. File without a trailing newline must still parse the last line.
run_test "no-trailing-newline" "ok" '
    [ "$NAME" = "no-newline" ] || { echo "NAME=$NAME"; exit 1; }
    [ "$PROFILE" = "p" ] || { echo "PROFILE=$PROFILE"; exit 1; }
    exit 0
'

# 17. KEY=value (no quotes) is not the supported format. The parser
#     must skip with a warning, not silently assign or crash.
run_test "unquoted-value" "ok" '
    # Required fields all parse; the unquoted TAGS line is skipped.
    [ "$NAME" = "unquoted-test" ] || { echo "NAME=$NAME"; exit 1; }
    [ -z "$TAGS" ] || { echo "TAGS leaked: $TAGS"; exit 1; }
    exit 0
'

# 18. Tab characters in values are preserved (not normalized to spaces).
run_test "tab-in-value" "ok" '
    case "$TAGS" in
        *$'"'"'\t'"'"'*) exit 0 ;;
        *) echo "TAGS missing tab: $TAGS"; exit 1 ;;
    esac
'

# 19. Backward-compat: confs created before v2.0.0 stored REPO as
#     "$HOME/path" expecting the shell to expand it. v2.0.0+ stores it
#     as a literal string by default. The loader expands a leading
#     literal `$HOME` (and `~`) so existing user confs keep working.
#     The expansion is pure string substitution — no shell evaluation.
run_test "legacy-home-prefix" "ok" '
    expected="$HOME/Projects/some/path"
    [ "$REPO" = "$expected" ] || { echo "REPO=$REPO expected=$expected"; exit 1; }
    exit 0
'

# 20. v1-style conf (every assignment unquoted, shell-source-style — the
#     pre-v2.0.0 format) MUST be rejected. The strict parser was added in
#     v2.7.0 to close a CVE-class arbitrary-code-execution sink (`source
#     "$conf"` evaluating attacker-controlled lines). v1 confs should
#     produce a clean "missing NAME" failure rather than silently loading
#     a partial conf or — worse — re-introducing shell evaluation.
#
#     This test pins the migration boundary: v1 → v2 is non-silent.
run_test "v1-style-conf" "die" "true"

# --- Summary ---------------------------------------------------------------

echo
if [ "$FAIL" -eq 0 ]; then
    printf '%d/%d passed\n' "$PASS" "$((PASS + FAIL))"
    exit 0
else
    printf '%d/%d passed; failures: %s\n' "$PASS" "$((PASS + FAIL))" "${FAIL_NAMES[*]}" >&2
    exit 1
fi
