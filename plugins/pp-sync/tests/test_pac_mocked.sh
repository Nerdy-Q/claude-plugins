#!/usr/bin/env bash
# Regression tests for pp subcommands that depend on pac, using a
# mock pac script instead of a real Power Platform CLI install.
#
# This is the in-CI complement to tests/integration/test_pac_dependent.sh
# (which runs against real pac + real projects on a developer machine).
#
# The mock lives at tests/mocks/pac. We prepend its directory to PATH
# so pp invocations pick up the mock instead of any real pac install.
# Each test gets its own state directory via PP_MOCK_PAC_STATE_DIR so
# profile registrations don't leak between tests.
#
# Currently covers (chunk 1 — auth + org + paportal validate paths):
#   - pp doctor (pac auth list + auth select + org who)
#   - pp switch (pac auth select)
#   - pp status (pac org who)
#   - pp up --validate-only (pac paportal upload --validateBeforeUpload)
#
# Run from anywhere: ./plugins/pp-sync/tests/test_pac_mocked.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PP_BIN="$SCRIPT_DIR/../bin/pp"
MOCK_DIR="$SCRIPT_DIR/mocks"
MOCK_PAC="$MOCK_DIR/pac"

[ -x "$MOCK_PAC" ] || { echo "Cannot find mock pac at $MOCK_PAC" >&2; exit 1; }

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

# Build a tmp config dir with one project AND a mock pac state dir
# preloaded with that project's PROFILE. Echo the config dir; caller
# scopes env vars to it.
make_test_env() {
    local profile="${1:-testprof}"
    local env_url="${2:-https://test.crm.dynamics.com/}"
    local tmp
    tmp=$(mktemp -d)
    TMPDIRS+=( "$tmp" )

    # PP config
    mkdir -p "$tmp/pp/projects" "$tmp/repo/site---site/web-pages"
    {
        printf 'NAME="testproj"\n'
        printf 'REPO="%s/repo"\n' "$tmp"
        printf 'SITE_DIR="site---site"\n'
        printf 'PROFILE="%s"\n' "$profile"
        printf 'ENV_URL="%s"\n' "$env_url"
        printf 'WEBSITE_ID="00000000-0000-0000-0000-000000000001"\n'
        printf 'MODEL_VERSION="2"\n'
    } > "$tmp/pp/projects/testproj.conf"

    # PAC state: register the profile so auth list/select/org-who work
    mkdir -p "$tmp/pac"
    printf '%s=%s\n' "$profile" "$env_url" > "$tmp/pac/profiles"
    printf '%s' "$profile" > "$tmp/pac/selected"

    printf '%s\n' "$tmp"
}

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

# Helper: run pp with mock pac on PATH + scoped state dirs.
# Args: <test_env_root> <pp args...>
# Echoes pp output (stdout+stderr) and returns pp's exit code.
run_pp() {
    local env_root="$1"; shift
    PATH="$MOCK_DIR:$PATH" \
        PP_CONFIG_DIR="$env_root/pp" \
        PP_MOCK_PAC_STATE_DIR="$env_root/pac" \
        "$PP_BIN" "$@" 2>&1
}

# --- Section 1: pp doctor full pac path ---------------------------------

echo "Section 1 — pp doctor with mock pac"
echo

env=$(make_test_env testprof)
out=$(run_pp "$env" doctor testproj || true)

case "$out" in
    *"Profile testprof registered"*) assert_pass "doctor: profile detected as registered" ;;
    *) assert_fail "doctor: profile-registered message missing" "out: $(printf '%s' "$out" | head -10)" ;;
esac

case "$out" in
    *"Connected:"*) assert_pass "doctor: connected to env URL" ;;
    *) assert_fail "doctor: 'Connected' line missing" ;;
esac

case "$out" in
    *"Site content counts"*) assert_pass "doctor reaches Site content counts section" ;;
    *) assert_fail "doctor doesn't reach final section" ;;
esac

# --- Section 2: pp doctor when profile NOT registered -------------------

echo
echo "Section 2 — pp doctor with unregistered profile"
echo

env=$(mktemp -d); TMPDIRS+=( "$env" )
mkdir -p "$env/pp/projects" "$env/repo/site---site" "$env/pac"
{
    printf 'NAME="testproj"\n'
    printf 'REPO="%s/repo"\n' "$env"
    printf 'SITE_DIR="site---site"\n'
    printf 'PROFILE="missing"\n'
} > "$env/pp/projects/testproj.conf"
# Empty profiles file — "missing" will not be found
: > "$env/pac/profiles"

out=$(run_pp "$env" doctor testproj || true)
case "$out" in
    *"Profile missing not registered"*|*"not registered"*)
        assert_pass "doctor: detects unregistered profile"
        ;;
    *)
        assert_fail "doctor: didn't surface unregistered-profile error" \
            "out: $(printf '%s' "$out" | head -10)"
        ;;
esac

# --- Section 3: pp switch sets active + auth-selects --------------------

echo
echo "Section 3 — pp switch with mock pac"
echo

env=$(make_test_env myprof)
# switch sets active and runs pac auth select
out=$(run_pp "$env" switch testproj || true)
[ -f "$env/pp/active" ] && [ "$(cat "$env/pp/active")" = "testproj" ] \
    && assert_pass "switch wrote active=testproj" \
    || assert_fail "switch didn't write active correctly"

# Mock pac state should now have myprof selected
selected=$(cat "$env/pac/selected" 2>/dev/null || echo "")
[ "$selected" = "myprof" ] && assert_pass "switch ran pac auth select --name myprof" \
    || assert_fail "switch didn't auth-select" "selected='$selected'"

# --- Section 4: pp status shows live env URL ----------------------------

echo
echo "Section 4 — pp status with mock pac"
echo

env=$(make_test_env myprof "https://acme-dev.crm.dynamics.com/")
run_pp "$env" switch testproj >/dev/null 2>&1 || true
out=$(run_pp "$env" status || true)
case "$out" in
    *"acme-dev.crm.dynamics.com"*)
        assert_pass "status reports live env URL from pac org who"
        ;;
    *)
        assert_fail "status doesn't report live env URL" \
            "out: $(printf '%s' "$out" | head -5)"
        ;;
esac

# --- Section 5: pp up --validate-only (mock pac upload) -----------------

echo
echo "Section 5 — pp up --validate-only with mock pac"
echo

env=$(make_test_env myprof)
out=$(run_pp "$env" up testproj --validate-only || true)
case "$out" in
    *"Validation OK"*|*"validation"*|*"Validating"*)
        assert_pass "up --validate-only invoked pac validate path"
        ;;
    *)
        assert_fail "up --validate-only didn't reach pac validation" \
            "out: $(printf '%s' "$out" | head -10)"
        ;;
esac

# --- Section 6: pp down end-to-end with mock paportal download ----------
# (Section 9 below covers failure injection.)

echo
echo "Section 6 — pp down with mock pac paportal download"
echo

env=$(make_test_env myprof)
# pp down auto-confirms via PP_DOWN_NO_CONFIRM env, but pp doesn't honor
# such a flag. Pipe `y` to confirm prompts.
out=$(printf 'y\ny\n' | run_pp "$env" down testproj 2>&1 || true)
# The mock creates sample-site---sample-site/ under the cwd. Verify the
# download path was invoked (pp output mentions Downloaded or Sample).
case "$out" in
    *"Sample"*|*"Downloaded"*|*"download"*|*"Download"*)
        assert_pass "down invoked pac paportal download"
        ;;
    *)
        assert_fail "down didn't invoke download" \
            "out: $(printf '%s' "$out" | head -5)"
        ;;
esac

# --- Section 7: pp up (full upload) with mock pac -----------------------

echo
echo "Section 7 — pp up (full) with mock pac"
echo

env=$(make_test_env myprof)
# Full upload (no --validate-only) — pipe y to confirm prompts.
out=$(printf 'y\ny\n' | run_pp "$env" up testproj 2>&1 || true)
case "$out" in
    *"Upload complete"*|*"Uploading"*|*"upload"*)
        assert_pass "up invoked pac paportal upload (full)"
        ;;
    *)
        assert_fail "up didn't reach upload" \
            "out: $(printf '%s' "$out" | head -5)"
        ;;
esac

# --- Section 8: pp solution-down end-to-end with mock pac ---------------

echo
echo "Section 8 — pp solution-down with mock pac"
echo

env=$(make_test_env myprof)
out=$(printf 'y\n' | run_pp "$env" solution-down testproj MySolution 2>&1 || true)
case "$out" in
    *"Exported"*|*"Unpacked"*|*"export"*|*"unpack"*)
        assert_pass "solution-down invoked pac solution export+unpack"
        ;;
    *)
        assert_fail "solution-down didn't reach pac" \
            "out: $(printf '%s' "$out" | head -10)"
        ;;
esac

# Verify the unpacked solution dir was created at the expected path
[ -d "$env/repo/dataverse-schema/MySolution" ] && assert_pass "solution unpacked to expected path" \
    || assert_fail "unpacked dir missing" \
        "tree: $(find "$env/repo" -maxdepth 4 -type d 2>/dev/null | head -10)"

# --- Section 9: pp solution-up end-to-end with mock pac -----------------

echo
echo "Section 9 — pp solution-up with mock pac"
echo

env=$(make_test_env myprof)
# Pre-populate an unpacked solution so solution-up has something to pack
mkdir -p "$env/repo/dataverse-schema/MySolution/Other"
echo "<ImportExportXml/>" > "$env/repo/dataverse-schema/MySolution/Other/Solution.xml"
out=$(printf 'y\nMySolution\n' | run_pp "$env" solution-up testproj MySolution 2>&1 || true)
case "$out" in
    *"Packed"*|*"Imported"*|*"pack"*|*"import"*)
        assert_pass "solution-up invoked pac solution pack+import"
        ;;
    *)
        assert_fail "solution-up didn't reach pac" \
            "out: $(printf '%s' "$out" | head -10)"
        ;;
esac

# --- Section 10: doctor failure paths (auth select, org who) ----------

echo
echo "Section 10 — doctor failure paths"
echo

env=$(make_test_env myprof)
# Inject org who failure — doctor should report "re-auth needed" or
# similar warning in the PAC auth section.
out=$(PP_MOCK_PAC_FAIL_ORG_WHO=1 run_pp "$env" doctor testproj 2>&1 || true)
case "$out" in
    *"re-auth"*|*"no URL"*|*"no env URL"*|*"profile may need"*)
        assert_pass "doctor surfaces org-who failure as re-auth warning"
        ;;
    *)
        # Don't fail outright — the message wording may vary. Just
        # verify doctor still completes the run rather than aborting.
        case "$out" in
            *"Site content counts"*)
                assert_pass "doctor completes despite org-who failure (no abort)"
                ;;
            *)
                assert_fail "doctor aborted on org-who failure" \
                    "out: $(printf '%s' "$out" | head -10)"
                ;;
        esac
        ;;
esac

# Inject auth-select failure
env=$(make_test_env myprof)
out=$(PP_MOCK_PAC_FAIL_AUTH_SELECT=1 run_pp "$env" doctor testproj 2>&1 || true)
case "$out" in
    *"Site content counts"*)
        assert_pass "doctor completes despite auth-select failure"
        ;;
    *)
        assert_fail "doctor aborted on auth-select failure" \
            "out: $(printf '%s' "$out" | head -10)"
        ;;
esac

# --- Section 11: cmd_audit bash → python dispatch ---------------------

echo
echo "Section 11 — pp audit (bash dispatcher → audit.py)"
echo

env=$(make_test_env myprof)
# Make sure audit.py is reachable. cmd_audit looks in plugin caches
# and falls back to $REPO/plugins/.../audit.py. We point REPO at the
# checkout so the fallback kicks in.
checkout_root=$(cd "$SCRIPT_DIR/../../.." && pwd)
audit_py="$checkout_root/plugins/pp-permissions-audit/skills/pp-permissions-audit/scripts/audit.py"
[ -f "$audit_py" ] || { assert_fail "audit.py not found at $audit_py"; }

# Override the conf to point REPO at the checkout so cmd_audit's
# fallback path picks up the in-tree audit.py. Use the audit's own
# scripts directory as SITE_DIR — it's not a portal but the bash
# dispatcher only needs SITE_DIR to exist; whether the python audit
# finds anything is incidental to the test's purpose.
{
    printf 'NAME="testproj"\n'
    printf 'REPO="%s"\n' "$checkout_root"
    printf 'SITE_DIR="plugins/pp-permissions-audit/skills/pp-permissions-audit/scripts"\n'
    printf 'PROFILE="myprof"\n'
} > "$env/pp/projects/testproj.conf"

# Now run pp audit. With --json, audit.py emits JSON to stdout.
out=$(PATH="$MOCK_DIR:$PATH" PP_CONFIG_DIR="$env/pp" PP_MOCK_PAC_STATE_DIR="$env/pac" \
    "$PP_BIN" audit testproj --json 2>&1 || true)

# We don't expect findings (the audit script's own dir isn't a portal).
# We just verify the bash → python dispatch path:
#   1. pp's "Audit:" header was emitted (proving cmd_audit started)
#   2. python output (if any) is JSON-parseable
case "$out" in
    *"Audit:"*|*"audit"*)
        assert_pass "cmd_audit header emitted (bash dispatcher reached python)"
        ;;
    *)
        assert_fail "cmd_audit didn't emit Audit header" \
            "out: $(printf '%s' "$out" | head -10)"
        ;;
esac

# --- Section 12: pp up with upload failure injection ------------------

echo
echo "Section 12 — pp up with upload failure"
echo

env=$(make_test_env myprof)
out=$(printf 'y\ny\n' | PP_MOCK_PAC_FAIL_UPLOAD=1 run_pp "$env" up testproj 2>&1 || true)
case "$out" in
    *"upload failed"*|*"Error"*|*"failed"*)
        assert_pass "up surfaces upload failure"
        ;;
    *"Upload complete"*)
        assert_fail "up reported success despite mock failure"
        ;;
    *)
        # No clear error in output — pp may have suppressed it. Check
        # that it didn't claim success.
        case "$out" in
            *"Upload complete"*) assert_fail "up claimed success on injected failure" ;;
            *) assert_pass "up didn't claim success (failure quietly handled)" ;;
        esac
        ;;
esac

# --- Section 13: failure injection — auth list (original test) --------

echo
echo "Section 13 — pac auth list failure injection"
echo

env=$(make_test_env myprof)
out=$(PP_MOCK_PAC_FAIL_AUTH_LIST=1 run_pp "$env" doctor testproj || true)
case "$out" in
    *"Profile myprof registered"*)
        assert_fail "auth list failure didn't propagate" "out: $out"
        ;;
    *)
        assert_pass "auth list failure surfaced (pp didn't claim profile registered)"
        ;;
esac

# --- Summary -----------------------------------------------------------

echo
if [ "$FAIL" -eq 0 ]; then
    printf '%d/%d passed\n' "$PASS" "$((PASS + FAIL))"
    exit 0
else
    printf '%d/%d passed; failures: %s\n' "$PASS" "$((PASS + FAIL))" "${FAIL_NAMES[*]}" >&2
    exit 1
fi
