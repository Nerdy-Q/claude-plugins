#!/usr/bin/env bash
# Integration test for atomic project registration.
#
# When `pp project add` rejects user input (invalid project name, profile,
# or solution name), no .conf file should be left behind. This guards
# against a regression where solution-name validation in the middle of
# the conf-writing loop left a partial `SOLUTIONS=(` line in the file.
#
# Run from anywhere: ./plugins/pp-sync/tests/test_register_atomic.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PP_BIN="$SCRIPT_DIR/../bin/pp"

[ -f "$PP_BIN" ] || { echo "Cannot find bin/pp at $PP_BIN" >&2; exit 1; }

PASS=0
FAIL=0
FAIL_NAMES=()

run_reject_test() {
    local label="$1" stdin="$2"
    local tmp
    tmp=$(mktemp -d)
    export PP_CONFIG_DIR="$tmp"

    local output exit_code
    output=$(printf '%s' "$stdin" | "$PP_BIN" project add 2>&1)
    exit_code=$?

    local file_count=0
    if [ -d "$tmp/projects" ]; then
        file_count=$(find "$tmp/projects" -maxdepth 1 -name '*.conf' | wc -l | tr -d ' ')
    fi

    if [ "$exit_code" -ne 0 ] && [ "$file_count" -eq 0 ]; then
        PASS=$((PASS + 1))
        printf '  OK   %s (rejected, no partial file)\n' "$label"
    else
        FAIL=$((FAIL + 1))
        FAIL_NAMES+=( "$label" )
        printf '  FAIL %s — exit=%d files=%d\n' "$label" "$exit_code" "$file_count" >&2
        printf '       output: %s\n' "$output" >&2
        if [ "$file_count" -gt 0 ]; then
            printf '       partial file:\n' >&2
            sed 's/^/         /' "$tmp/projects/"*.conf >&2
        fi
    fi
    rm -rf "$tmp"
}

run_accept_test() {
    local label="$1" stdin="$2" expect_solutions="$3"
    local tmp
    tmp=$(mktemp -d)
    export PP_CONFIG_DIR="$tmp"

    local output exit_code
    output=$(printf '%s' "$stdin" | "$PP_BIN" project add 2>&1)
    exit_code=$?

    local conf_file
    conf_file=$(find "$tmp/projects" -name '*.conf' 2>/dev/null | head -1)

    if [ "$exit_code" -eq 0 ] && [ -n "$conf_file" ]; then
        # Verify SOLUTIONS line either present (with quotes) or absent
        local has_solutions
        has_solutions=$(grep -c '^SOLUTIONS=' "$conf_file" 2>/dev/null || true)
        if [ "$expect_solutions" = "yes" ] && [ "$has_solutions" -gt 0 ]; then
            PASS=$((PASS + 1))
            printf '  OK   %s (registered, SOLUTIONS present)\n' "$label"
        elif [ "$expect_solutions" = "no" ] && [ "$has_solutions" -eq 0 ]; then
            PASS=$((PASS + 1))
            printf '  OK   %s (registered, no SOLUTIONS)\n' "$label"
        else
            FAIL=$((FAIL + 1))
            FAIL_NAMES+=( "$label" )
            printf '  FAIL %s — SOLUTIONS expected=%s got_count=%d\n' "$label" "$expect_solutions" "$has_solutions" >&2
            sed 's/^/         /' "$conf_file" >&2
        fi
    else
        FAIL=$((FAIL + 1))
        FAIL_NAMES+=( "$label" )
        printf '  FAIL %s — exit=%d conf=%s\n' "$label" "$exit_code" "${conf_file:-<none>}" >&2
        printf '       output: %s\n' "$output" >&2
    fi
    rm -rf "$tmp"
}

echo "Running pp project add atomic-registration tests"
echo

# Reject cases: each malicious input must abort BEFORE writing any conf
run_reject_test "malicious project name" \
    'evil;cmd
'

run_reject_test "malicious PAC profile" \
    'cleanname
/tmp/repo
site
bad profile;cmd
'

run_reject_test "malicious solution name" \
    'cleanname2
/tmp/repo
site
goodprof


Foo;rm,Bar




'

run_reject_test "malicious alias" \
    'cleanname3
/tmp/repo
site
goodprof


Foo
main



evil;alias
'

# Accept cases: clean input registers successfully
run_accept_test "valid registration with solutions" \
    'goodproj
/tmp/repo
site---site
goodprof


FooSolution,BarSolution
main



good-alias
' "yes"

run_accept_test "valid registration without solutions" \
    'minimalproj
/tmp/repo
site---site
goodprof




main



' "no"

echo
if [ "$FAIL" -eq 0 ]; then
    printf '%d/%d passed\n' "$PASS" "$((PASS + FAIL))"
    exit 0
else
    printf '%d/%d passed; failures: %s\n' "$PASS" "$((PASS + FAIL))" "${FAIL_NAMES[*]}" >&2
    exit 1
fi
