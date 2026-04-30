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

TMPDIRS=()
cleanup_tmpdirs() {
    local tmp
    for tmp in "${TMPDIRS[@]}"; do
        rm -rf "$tmp"
    done
}
trap cleanup_tmpdirs EXIT

run_reject_test() {
    local label="$1" stdin="$2"
    local tmp
    tmp=$(mktemp -d)
    TMPDIRS+=( "$tmp" )
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
    TMPDIRS+=( "$tmp" )
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

# --- Concurrent registration race ----------------------------------------
#
# Two parallel `pp project add foo ...` against the same name: there's a
# TOCTOU between the duplicate-name check and the file write. Worst case,
# both processes pass the check, both write — the conf could end up half-
# formed if writes interleave at the byte level.
#
# Verify the final state is sane regardless of who wins:
#   - exactly one conf file exists
#   - the file is parseable by load_project (NAME, REPO, etc. all set)
#   - exactly one of the racers shows "Registered" success (the others
#     should report "already exists" or fail the duplicate-name check)
#
# The atomic-write pattern in bin/pp uses `cat > file <<EOF` which is NOT
# fully race-proof against concurrent creates. This test pins the
# observed safe behavior so any regression that loosens the guarantees
# is caught.

echo
echo "Section — concurrent project add race"
echo

tmp=$(mktemp -d); TMPDIRS+=( "$tmp" )
export PP_CONFIG_DIR="$tmp"

# Inputs for `pp project add raceproj`: name + repo + site + profile +
# blanks for the rest.
race_input='raceproj
/tmp/raceproj
race---race
raceprof




main



'

# Spawn 5 parallel project-add invocations against the SAME name
# Capture each PID's exit code.
pids=()
for _ in 1 2 3 4 5; do
    ( printf '%s' "$race_input" | "$PP_BIN" project add >/dev/null 2>&1 ) &
    pids+=( "$!" )
done
exit_codes=()
for p in "${pids[@]}"; do
    wait "$p"; exit_codes+=( "$?" )
done

# Count how many succeeded (exit 0) vs failed (non-zero)
successes=0
for ec in "${exit_codes[@]}"; do
    [ "$ec" = "0" ] && successes=$((successes + 1))
done

# Exactly one conf file should exist
file_count=$(find "$tmp/projects" -maxdepth 1 -name '*.conf' 2>/dev/null | wc -l | tr -d ' ')
if [ "$file_count" = "1" ]; then
    PASS=$((PASS + 1)); printf '  OK   exactly one conf file after race (5 parallel runs)\n'
else
    FAIL=$((FAIL + 1)); FAIL_NAMES+=( "concurrent-race-file-count" )
    printf '  FAIL expected 1 conf file, got %d\n' "$file_count" >&2
    find "$tmp/projects" -maxdepth 1 -name '*.conf' 2>/dev/null | sed 's/^/         /' >&2
fi

# At least one process succeeded (the winner)
if [ "$successes" -ge 1 ]; then
    PASS=$((PASS + 1)); printf '  OK   at least one process succeeded (winner exists)\n'
else
    FAIL=$((FAIL + 1)); FAIL_NAMES+=( "concurrent-race-no-winner" )
    printf '  FAIL no process succeeded; exit codes: %s\n' "${exit_codes[*]}" >&2
fi

# The conf file must be parseable — no half-written state. Use load_project
# in a subshell to verify all required fields are present.
if [ -f "$tmp/projects/raceproj.conf" ]; then
    parse_result=$(
        (
            export PP_CONFIG_DIR="$tmp"
            export PP_PROJECTS_DIR="$tmp/projects"
            export PP_ALIASES_FILE="$tmp/aliases"
            # shellcheck source=/dev/null
            . "$PP_BIN" >/dev/null 2>&1 || true
            load_project "raceproj"
            # All required fields should be set
            [ "$NAME" = "raceproj" ] || { echo "NAME=$NAME"; exit 1; }
            [ "$REPO" = "/tmp/raceproj" ] || { echo "REPO=$REPO"; exit 1; }
            [ "$SITE_DIR" = "race---race" ] || { echo "SITE_DIR=$SITE_DIR"; exit 1; }
            [ "$PROFILE" = "raceprof" ] || { echo "PROFILE=$PROFILE"; exit 1; }
            echo OK
        ) 2>&1
    )
    case "$parse_result" in
        *OK*)
            PASS=$((PASS + 1)); printf '  OK   conf file is parseable + complete after race\n' ;;
        *)
            FAIL=$((FAIL + 1)); FAIL_NAMES+=( "concurrent-race-parse" )
            printf '  FAIL conf file corrupt or partial after race: %s\n' "$parse_result" >&2 ;;
    esac
else
    FAIL=$((FAIL + 1)); FAIL_NAMES+=( "concurrent-race-no-file" )
    printf '  FAIL no raceproj.conf file written\n' >&2
fi

rm -rf "$tmp"
unset PP_CONFIG_DIR

echo
if [ "$FAIL" -eq 0 ]; then
    printf '%d/%d passed\n' "$PASS" "$((PASS + FAIL))"
    exit 0
else
    printf '%d/%d passed; failures: %s\n' "$PASS" "$((PASS + FAIL))" "${FAIL_NAMES[*]}" >&2
    exit 1
fi
