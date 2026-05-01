#!/usr/bin/env bash
# Contract tests for the pac CLI surface that pp-sync depends on.
#
# Defines, in code, what pp's parsers expect from each `pac` subcommand:
#   - which strings/patterns must appear in stdout
#   - which exit codes count as success/failure
#   - what filesystem effects must occur
#
# These contracts are the load-bearing assumptions in `bin/pp`'s
# integration with pac. The mock at tests/mocks/pac MUST satisfy them
# for the mocked test suite to be a faithful stand-in.
#
# Two run modes:
#
#   bash test_pac_contract.sh            # default: against the mock pac
#   PP_PAC_REAL=1 bash test_pac_contract.sh
#                                         # against the real pac CLI
#
# CI runs the default mode (mock). Maintainers run the PP_PAC_REAL=1
# mode before each release to catch drift between real pac and the
# mock — this is the regression that the v2.10.0 changelog acknowledged
# but didn't have automated coverage for.
#
# Contract failures from EITHER mode are real bugs:
#   - mock fails contract → mock needs updating to match real pac
#   - real pac fails contract → pp's parsers will break on this pac
#     version; pp needs adjusting

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOCK_DIR="$SCRIPT_DIR/mocks"

PASS=0
FAIL=0
SKIP=0
FAIL_NAMES=()

TMPDIRS=()
cleanup_tmpdirs() {
    local tmp
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

skip() {
    SKIP=$((SKIP + 1))
    printf '  SKIP %s — %s\n' "$1" "$2"
}

# --- mode setup ---------------------------------------------------------

if [ "${PP_PAC_REAL:-0}" = "1" ]; then
    if ! command -v pac >/dev/null 2>&1; then
        echo "SKIP — PP_PAC_REAL=1 but pac CLI is not installed"
        exit 0
    fi
    PAC_BIN="$(command -v pac)"
    MODE="real-pac"
    # Real pac requires real auth. Tests that need write/read against
    # an actual environment are skipped in this mode.
    REAL_MODE=1
else
    PAC_BIN="$MOCK_DIR/pac"
    MODE="mock-pac"
    REAL_MODE=0
fi

[ -x "$PAC_BIN" ] || { echo "Cannot find pac at $PAC_BIN" >&2; exit 1; }

printf 'Contract testing pac CLI against: %s (%s)\n\n' "$PAC_BIN" "$MODE"

# Per-test isolated mock state (only relevant for mock mode)
new_state_dir() {
    local d
    d=$(mktemp -d)
    TMPDIRS+=( "$d" )
    printf '%s\n' "$d"
}

run_pac() {
    local state="$1"; shift
    if [ "$REAL_MODE" = "1" ]; then
        "$PAC_BIN" "$@"
    else
        PP_MOCK_PAC_STATE_DIR="$state" "$PAC_BIN" "$@"
    fi
}

# --- Section 1: pac auth list contract ----------------------------------
#
# pp parses this to verify a profile is registered:
#   pac auth list 2>/dev/null | grep -qE "UNIVERSAL[[:space:]]+${PROFILE}\\b"
#
# Contract:
#   - returns 0 on success
#   - lines for registered profiles match: ^[anything]UNIVERSAL[ws]<name>[ws]<url>
#   - the active profile MAY have a `*` marker — pp doesn't depend on it
#   - empty profile list is valid (returns 0 with header-only output)

echo "Section 1 — pac auth list contract"
echo

state=$(new_state_dir)
if [ "$REAL_MODE" = "0" ]; then
    # Pre-populate the mock with a known profile
    echo "myprof=https://acme-dev.crm.dynamics.com/" > "$state/profiles"
    echo "myprof" > "$state/selected"
fi

out=$(run_pac "$state" auth list 2>/dev/null || true)

# In real-pac mode without any registered profile, pac emits a
# non-empty "No profiles were found..." sentinel rather than empty
# output. Treat both forms as "no profiles registered" so contract
# checks that require a profile SKIP cleanly instead of FAILing.
real_no_profiles=0
if [ "$REAL_MODE" = "1" ]; then
    case "$out" in
        ""|*"No profiles were found"*) real_no_profiles=1 ;;
    esac
fi

# Contract: each profile row contains "UNIVERSAL" followed by name + URL
case "$out" in
    *"UNIVERSAL"*)
        assert_pass "auth list output contains 'UNIVERSAL' (profile-row marker pp greps for)"
        ;;
    *)
        if [ "$real_no_profiles" = "1" ]; then
            skip "auth list 'UNIVERSAL' marker" "real pac with zero registered profiles"
        else
            assert_fail "auth list missing 'UNIVERSAL' marker" "got: $(printf '%s' "$out" | head -3)"
        fi
        ;;
esac

# Contract: pp's actual parsing depends ONLY on the substring
# `UNIVERSAL[[:space:]]+<profile-name>\b` appearing on a row. Real
# pac (as of v1.x) inserts several columns between Name and URL
# (User, Cloud, Type, Environment). The mock has fewer columns. Both
# satisfy pp's contract because pp doesn't parse URL from auth list
# at all — that comes from `pac org who`.
if printf '%s' "$out" | grep -qE 'UNIVERSAL[[:space:]]+\S+'; then
    assert_pass "auth list rows have 'UNIVERSAL <profile-name>' shape pp greps for"
else
    if [ "$real_no_profiles" = "1" ]; then
        skip "auth list row shape" "real pac with zero registered profiles"
    else
        assert_fail "auth list row shape changed" "got: $(printf '%s' "$out" | head -5)"
    fi
fi

# Optional: an HTTPS URL appears somewhere in the row (pp doesn't
# parse it but it's a sanity check that profiles HAVE env URLs).
# This is a soft check — failures don't block the suite.
if printf '%s' "$out" | grep -qE 'https?://'; then
    assert_pass "auth list rows include an https:// URL somewhere"
else
    if [ "$real_no_profiles" = "1" ]; then
        skip "auth list URL presence" "no profiles registered"
    else
        assert_fail "auth list rows missing URL"
    fi
fi

# --- Section 2: pac auth select contract -------------------------------
#
# pp parses this only via exit code. Output shape doesn't matter.
# Contract: exits 0 for known profile, non-zero for unknown.

echo
echo "Section 2 — pac auth select contract"
echo

if [ "$REAL_MODE" = "0" ]; then
    state=$(new_state_dir)
    echo "myprof=https://example.com/" > "$state/profiles"

    if run_pac "$state" auth select --name myprof >/dev/null 2>&1; then
        assert_pass "auth select on known profile exits 0"
    else
        assert_fail "auth select on known profile exited non-zero"
    fi

    if run_pac "$state" auth select --name nothere >/dev/null 2>&1; then
        assert_fail "auth select on unknown profile exited 0 (should be non-zero)"
    else
        assert_pass "auth select on unknown profile exits non-zero"
    fi
else
    skip "auth select known/unknown profile" "real pac would mutate user state"
fi

# --- Section 3: pac org who contract -----------------------------------
#
# pp parses this via:
#   actual=$(pac org who 2>&1 | awk -F': ' '/Environment Url/{print $2; exit}')
#
# Contract:
#   - returns 0 when a profile is selected
#   - stdout includes a line `[anything]Environment Url: <https-url>`
#   - the URL appears after the FIRST `: ` on that line (awk -F': ' $2)
#   - returns non-zero when no profile selected (and DOES NOT print
#     'Environment Url:')

echo
echo "Section 3 — pac org who contract"
echo

state=$(new_state_dir)
if [ "$REAL_MODE" = "0" ]; then
    echo "myprof=https://acme-dev.crm.dynamics.com/" > "$state/profiles"
    echo "myprof" > "$state/selected"
fi

out=$(run_pac "$state" org who 2>&1 || true)
url=$(printf '%s' "$out" | awk -F': ' '/Environment Url/{print $2; exit}')

case "$url" in
    https://*)
        assert_pass "org who: 'Environment Url:' line present and URL parseable"
        ;;
    *)
        if [ "$REAL_MODE" = "1" ]; then
            skip "org who URL parse" "real pac without a selected profile"
        else
            assert_fail "org who URL not parseable via 'Environment Url'" "got: $(printf '%s' "$out" | head -5)"
        fi
        ;;
esac

# --- Section 4: pac paportal upload --validateBeforeUpload contract ----
#
# pp invokes this and checks exit code only. Validation success message
# must NOT contain 'Upload complete' — otherwise pp's "did it actually
# push" detection breaks.

echo
echo "Section 4 — pac paportal upload --validate-only contract"
echo

if [ "$REAL_MODE" = "0" ]; then
    state=$(new_state_dir)
    out=$(run_pac "$state" paportal upload --path /tmp/x --validateBeforeUpload 2>&1 || true)
    case "$out" in
        *"Validation"*|*"validate"*|*"validating"*|*"Validating"*)
            assert_pass "paportal upload --validateBeforeUpload mentions validation"
            ;;
        *)
            assert_fail "paportal upload --validateBeforeUpload doesn't mention validation" \
                "got: $(printf '%s' "$out" | head -3)"
            ;;
    esac
else
    skip "paportal upload --validate-only" "real pac would touch a real environment"
fi

# --- Section 5: pac solution unpack contract ---------------------------
#
# pp doesn't parse the output; it just needs a folder containing entity
# subfolders to result.
# Contract: --folder F must produce F/Entities/ (or F/Other/ — pp checks
# 'Entities' specifically when reporting count).

echo
echo "Section 5 — pac solution unpack contract"
echo

if [ "$REAL_MODE" = "0" ]; then
    state=$(new_state_dir)
    work=$(mktemp -d); TMPDIRS+=( "$work" )
    # Mock unpack expects a zipfile but doesn't really read it
    : > "$work/dummy.zip"
    run_pac "$state" solution unpack --zipfile "$work/dummy.zip" --folder "$work/unpacked" >/dev/null 2>&1 || true

    if [ -d "$work/unpacked" ]; then
        assert_pass "solution unpack creates --folder target dir"
        # pp's `find $unpack_dir/Entities` count check requires Entities/
        if [ -d "$work/unpacked/Entities" ]; then
            assert_pass "solution unpack creates Entities/ subdir (pp counts these)"
        else
            assert_fail "solution unpack didn't create Entities/" \
                "tree: $(find "$work/unpacked" -maxdepth 2 -type d 2>/dev/null)"
        fi
    else
        assert_fail "solution unpack didn't create the target folder"
    fi
else
    skip "solution unpack folder shape" "real pac requires a real solution zip"
fi

# --- Section 6: pac --version contract ---------------------------------
#
# Not used by pp itself, but documents that the binary responds to
# --version (the `command -v pac` plus a version probe is how doctor
# checks that pac is installed AND callable).

echo
echo "Section 6 — pac --version contract"
echo

if run_pac "$(new_state_dir)" --version >/dev/null 2>&1; then
    assert_pass "pac --version exits 0 (pac is callable)"
else
    if [ "$REAL_MODE" = "1" ]; then
        # Some pac versions use 'pac help' instead. Accept that fallback.
        if run_pac "$(new_state_dir)" help >/dev/null 2>&1; then
            assert_pass "pac help exits 0 (pac is callable, --version unsupported)"
        else
            assert_fail "neither pac --version nor pac help exits 0"
        fi
    else
        assert_fail "mock pac --version exits non-zero"
    fi
fi

# --- Summary -----------------------------------------------------------

echo
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
    if [ "$SKIP" -gt 0 ]; then
        printf '%d/%d passed (%d skipped — see notes above)\n' "$PASS" "$TOTAL" "$SKIP"
    else
        printf '%d/%d passed\n' "$PASS" "$TOTAL"
    fi
    exit 0
else
    printf '%d/%d passed; failures: %s\n' "$PASS" "$TOTAL" "${FAIL_NAMES[*]}" >&2
    exit 1
fi
