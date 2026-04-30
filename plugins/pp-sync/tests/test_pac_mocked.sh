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

# --- Section 9: failure injection ---------------------------------------

echo
echo "Section 9 — failure injection via PP_MOCK_PAC_FAIL_*"
echo

env=$(make_test_env myprof)
# Inject auth-list failure
out=$(PP_MOCK_PAC_FAIL_AUTH_LIST=1 run_pp "$env" doctor testproj || true)
# pp doctor uses pac auth list to verify the profile; with auth list
# failing, the "Profile X registered" check should NOT fire.
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
