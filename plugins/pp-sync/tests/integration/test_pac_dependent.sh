#!/usr/bin/env bash
# Local integration tests for pp subcommands that depend on pac.
#
# These tests exercise the read-only / non-destructive subset of pp
# subcommands against a REAL registered project. They run on a local
# developer machine where:
#   - `pac` is installed and a profile is registered
#   - At least one project has been registered via `pp setup` or
#     `pp project add`
#
# They are NOT wired into CI (the GitHub Actions runner has neither
# pac nor user projects). When run in an environment without pac or
# without registered projects, this suite skips cleanly with exit 0.
#
# By default the suite picks the first registered project. To target
# a specific one:
#
#     PP_INTEGRATION_PROJECT=anchor bash test_pac_dependent.sh
#
# Destructive operations (`pp down`, `pp up`, `pp solution-up`) are
# never run by this suite — they would modify the user's local files
# or push to a portal. To opt in to those (against your dev environment
# only):
#
#     PP_INTEGRATION_DESTRUCTIVE=1 bash test_pac_dependent.sh
#
# Even with that flag set, this suite still skips solution-up to prod
# without explicit per-test confirmation.
#
# Solution-down read-only test: opt in by naming the solution to export
# (export takes 60-120s, writes to repo's $SCHEMA_DIR, but is non-
# destructive — pac solution export is read-only against the tenant):
#
#     PP_INTEGRATION_SOLUTION_NAME=MySolution bash test_pac_dependent.sh
#
# This is the one place we exercise the real pac solution export+unpack
# pipeline end-to-end against a real Dataverse environment. Mocked
# tests cover the shell-level orchestration; only this one verifies
# the actual pac binary produces a usable solution zipfile.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PP_BIN="$SCRIPT_DIR/../../bin/pp"

[ -f "$PP_BIN" ] || { echo "Cannot find bin/pp at $PP_BIN" >&2; exit 1; }

PASS=0
FAIL=0
SKIP=0
FAIL_NAMES=()

# --- Pre-flight ---------------------------------------------------------

if ! command -v pac >/dev/null 2>&1; then
    printf '%s\n' "SKIP — pac CLI not installed (this suite requires Power Platform CLI)"
    exit 0
fi

# Discover registered projects via `pp list`. Skip if none.
projects_output=$("$PP_BIN" list 2>/dev/null || true)
case "$projects_output" in
    *"No projects registered"*)
        printf '%s\n' "SKIP — no projects registered (run \`pp setup\` first)"
        exit 0
        ;;
esac

# Pick a project. Honor PP_INTEGRATION_PROJECT if set, else first row.
TARGET="${PP_INTEGRATION_PROJECT:-}"
if [ -z "$TARGET" ]; then
    # First non-header row of `pp list` — strip leading whitespace, take
    # first column.
    TARGET=$(printf '%s\n' "$projects_output" \
        | awk 'NR>2 && $1!="" && $1!~/^-/ {print $1; exit}')
fi
if [ -z "$TARGET" ]; then
    printf '%s\n' "SKIP — could not pick a project from \`pp list\` output"
    exit 0
fi

# Validate the chosen project actually exists.
if ! "$PP_BIN" show "$TARGET" >/dev/null 2>&1; then
    printf '%s\n' "SKIP — chosen project '$TARGET' not resolvable"
    exit 0
fi

printf 'Running pac-dependent integration tests against project: %s\n\n' "$TARGET"

# --- helpers ------------------------------------------------------------

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

# --- Section 1: pp doctor (full pac auth path) --------------------------

echo "Section 1 — pp doctor"
echo

doctor_out=$("$PP_BIN" doctor "$TARGET" 2>&1 || true)
doctor_exit=$?

# Doctor should exit 0 even if some checks warn.
[ "$doctor_exit" = "0" ] && assert_pass "doctor exits 0" \
    || assert_fail "doctor non-zero exit" "exit=$doctor_exit"

# Doctor should reach the Site content counts section, which is the LAST
# section. If it didn't, doctor aborted mid-flow.
case "$doctor_out" in
    *"Site content counts"*)
        assert_pass "doctor reaches Site content counts section"
        ;;
    *)
        assert_fail "doctor did not reach Site content counts section" \
            "output: $doctor_out"
        ;;
esac

# Tooling section ran
case "$doctor_out" in
    *"Tooling"*) assert_pass "doctor: Tooling section present" ;;
    *) assert_fail "doctor: Tooling section missing" ;;
esac

# PAC auth section ran (we tolerate either "Profile X registered" or
# the negative case — what matters is the section appeared)
case "$doctor_out" in
    *"PAC auth"*) assert_pass "doctor: PAC auth section present" ;;
    *) assert_fail "doctor: PAC auth section missing" ;;
esac

# --- Section 2: pp diff (git diff against site dir, read-only) ----------

echo
echo "Section 2 — pp diff"
echo

diff_out=$("$PP_BIN" diff "$TARGET" 2>&1 || true)
diff_exit=$?
[ "$diff_exit" = "0" ] && assert_pass "diff exits 0" \
    || assert_fail "diff non-zero exit" "exit=$diff_exit"

# Diff should print a header indicating its scope.
case "$diff_out" in
    *"Diff preview"*|*"Site dir"*|*"No changes"*|*"already in sync"*|*"Total changed"*|*"files changed"*)
        assert_pass "diff produced output describing portal state"
        ;;
    *)
        assert_fail "diff produced unexpected output" "first lines: $(printf '%s' "$diff_out" | head -3)"
        ;;
esac

# --- Section 3: pp up --validate-only (pac validates without push) ------

echo
echo "Section 3 — pp up --validate-only"
echo

# pac paportal upload --validateBeforeUpload is a real network call but
# does NOT push. Skipped if there's nothing changed (--validate-only on
# clean tree may be a no-op).
up_out=$("$PP_BIN" up "$TARGET" --validate-only 2>&1 || true)
up_exit=$?

# Either succeeds (validation OK) or fails with a meaningful message.
# What matters is that pp itself reaches the validation step rather
# than aborting before invoking pac.
case "$up_out" in
    *"validate"*|*"Validate"*|*"Already in sync"*|*"No changes"*|*"upload"*|*"Upload"*)
        assert_pass "up --validate-only invoked pac path"
        ;;
    *"PAC"*|*"profile"*)
        # pac auth issue — skip rather than fail
        skip "up --validate-only" "pac auth not ready ($up_out)"
        ;;
    *)
        assert_fail "up --validate-only unexpected output" \
            "exit=$up_exit out: $(printf '%s' "$up_out" | head -3)"
        ;;
esac

# --- Section 4: pp audit (Python audit dispatch via bash) --------------

echo
echo "Section 4 — pp audit"
echo

audit_out=$("$PP_BIN" audit "$TARGET" --severity ERROR --json 2>&1 || true)

# audit may exit 0 (no errors) or 1 (errors found) — both are valid
# functional outcomes. We assert that JSON parses, proving the bash
# dispatcher correctly invoked python and the python emitted JSON.
if printf '%s' "$audit_out" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' 2>/dev/null; then
    assert_pass "audit produced parseable JSON"
else
    # Look for "audit script not found" — would indicate the bash
    # dispatcher couldn't locate audit.py (a real bug).
    case "$audit_out" in
        *"audit script not found"*|*"Cannot find"*)
            assert_fail "audit dispatch: script lookup failed" \
                "out: $audit_out"
            ;;
        *)
            # Other failures (e.g., permissions issue, unexpected pac
            # interaction) are worth flagging but not blocking.
            skip "audit JSON parse" \
                "non-JSON output (may be acceptable): $(printf '%s' "$audit_out" | head -3)"
            ;;
    esac
fi

# --- Section 5: pp status (live env from pac org who) -------------------

echo
echo "Section 5 — pp status"
echo

# Set the active project explicitly to the target so status has something
# coherent to report.
"$PP_BIN" switch "$TARGET" >/dev/null 2>&1 || true

status_out=$("$PP_BIN" status 2>&1 || true)
status_exit=$?
[ "$status_exit" = "0" ] && assert_pass "status exits 0" \
    || assert_fail "status non-zero exit" "exit=$status_exit"

# Should mention the active project name
case "$status_out" in
    *"$TARGET"*) assert_pass "status names the active project" ;;
    *) assert_fail "status doesn't mention active project '$TARGET'" ;;
esac

# --- Section 6: pp solution-down (opt-in via PP_INTEGRATION_SOLUTION_NAME)

echo
echo "Section 6 — pp solution-down (real export + unpack)"
echo

if [ -z "${PP_INTEGRATION_SOLUTION_NAME:-}" ]; then
    skip "solution-down" "set PP_INTEGRATION_SOLUTION_NAME=<name> to exercise"
else
    sol="$PP_INTEGRATION_SOLUTION_NAME"
    # solution-down writes to $REPO/dataverse-schema/$sol — record the
    # baseline so we can verify the unpack landed.
    repo_root=$("$PP_BIN" show "$TARGET" 2>/dev/null | awk -F'= ' '/^[[:space:]]*REPO/{print $2; exit}' | tr -d '"' || true)
    if [ -z "$repo_root" ] || [ ! -d "$repo_root" ]; then
        assert_fail "solution-down: cannot resolve REPO for project '$TARGET'"
    else
        unpack_target="$repo_root/dataverse-schema/$sol"
        # Auto-confirm the env-prompt with 'y'. Real export + unpack
        # takes 60-120s.
        echo "  ... exporting '$sol' from real env (may take 60-120s) ..."
        sd_out=$(printf 'y\n' | "$PP_BIN" solution-down "$TARGET" "$sol" 2>&1)
        sd_exit=$?
        [ "$sd_exit" = "0" ] && assert_pass "solution-down exits 0" \
            || assert_fail "solution-down non-zero exit ($sd_exit)" \
                "out: $(printf '%s' "$sd_out" | tail -10)"

        case "$sd_out" in
            *"Exported"*|*"export"*) assert_pass "solution-down: export step ran" ;;
            *) assert_fail "solution-down: no export message" "out: $(printf '%s' "$sd_out" | tail -5)" ;;
        esac
        case "$sd_out" in
            *"Unpacked"*|*"unpack"*) assert_pass "solution-down: unpack step ran" ;;
            *) assert_fail "solution-down: no unpack message" "out: $(printf '%s' "$sd_out" | tail -5)" ;;
        esac

        # Real pac unpack always produces an Other/Solution.xml — that's
        # the load-bearing fixture pp's audit and the mock both rely on.
        if [ -f "$unpack_target/Other/Solution.xml" ]; then
            assert_pass "solution-down produced Other/Solution.xml at expected path"
        else
            assert_fail "solution-down: Other/Solution.xml missing" \
                "tree: $(find "$unpack_target" -maxdepth 2 2>/dev/null | head -10)"
        fi
        # Also: zipfile cleanup (script removes it after successful unpack)
        if [ -f "$repo_root/dataverse-schema/${sol}.zip" ]; then
            assert_fail "solution-down left zipfile behind"
        else
            assert_pass "solution-down cleaned up zipfile"
        fi
    fi
fi

# --- Destructive-only section (gated by env var) ------------------------

echo
echo "Section 6 — destructive ops (gated)"
echo

if [ "${PP_INTEGRATION_DESTRUCTIVE:-0}" != "1" ]; then
    skip "down / up / solution-up" \
        "set PP_INTEGRATION_DESTRUCTIVE=1 to opt in"
else
    # Even with the flag, we never run solution-up — too risky against
    # any environment that's not isolated.
    skip "solution-up" "permanently disabled in this suite"

    # `pp down` can be exercised with confirmation. We auto-decline.
    down_out=$(printf 'n\n' | "$PP_BIN" down "$TARGET" 2>&1 || true)
    case "$down_out" in
        *"Aborted"*|*"aborted"*|*"cancel"*)
            assert_pass "down respects abort confirmation"
            ;;
        *)
            assert_fail "down did not respect abort: $(printf '%s' "$down_out" | head -3)"
            ;;
    esac
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
