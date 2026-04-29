#!/usr/bin/env bash
# Tests for validate_issue_url_for_current_repo() — closes the JOURNAL.md
# URL hijacking path (audit finding #13).
#
# We mock `gh repo view` via a shell function override so the validator
# sees a known "current repo" URL without needing a real git checkout.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PP_BIN="$SCRIPT_DIR/../bin/pp"

[ -f "$PP_BIN" ] || { echo "Cannot find bin/pp at $PP_BIN" >&2; exit 1; }

PASS=0
FAIL=0
FAIL_NAMES=()

# Run a validation check in a subshell with a mocked gh that returns
# the configured "current repo" URL. Assert pass/fail outcome.
run_url_test() {
    local label="$1" url="$2" mock_repo_url="$3" expect="$4"
    local exit_code

    (
        # shellcheck source=/dev/null
        . "$PP_BIN" >/dev/null 2>&1 || true

        # Override `gh`. Use a distinctive var name so dynamic scoping
        # doesn't collide with `local current_repo` inside the validator.
        gh() {
            if [ "$1" = "repo" ] && [ "$2" = "view" ]; then
                printf '%s\n' "$mock_repo_url"
                return 0
            fi
            return 1
        }
        # Force has_gh=1 in the validator's view (it uses `command -v gh`).
        # `command -v` looks up shell functions too, so the override is found.

        validate_issue_url_for_current_repo "$url"
    ) >/dev/null 2>&1
    exit_code=$?

    if [ "$expect" = "accept" ] && [ "$exit_code" -eq 0 ]; then
        PASS=$((PASS + 1))
        printf '  OK   %s (accepted)\n' "$label"
    elif [ "$expect" = "reject" ] && [ "$exit_code" -ne 0 ]; then
        PASS=$((PASS + 1))
        printf '  OK   %s (rejected)\n' "$label"
    else
        FAIL=$((FAIL + 1))
        FAIL_NAMES+=( "$label" )
        printf '  FAIL %s — expected=%s exit=%d\n' "$label" "$expect" "$exit_code" >&2
    fi
}

CURRENT="https://github.com/Nerdy-Q/claude-power-pages-plugins"

echo "Running validate_issue_url_for_current_repo tests"
echo

# Accept: legitimate same-repo URL
run_url_test "same-repo issue accepted" \
    "$CURRENT/issues/42" "$CURRENT" "accept"

# Reject: different repo (THE attack: cross-repo hijack via JOURNAL.md PR)
run_url_test "different-repo URL rejected" \
    "https://github.com/attacker/other-repo/issues/42" "$CURRENT" "reject"

# Reject: same owner, different repo
run_url_test "same-owner different-repo rejected" \
    "https://github.com/Nerdy-Q/different-repo/issues/42" "$CURRENT" "reject"

# Reject: malformed shape (path traversal style)
run_url_test "malformed URL rejected (path traversal)" \
    "https://github.com/Nerdy-Q/claude-power-pages-plugins/issues/42/../../../other/issues/1" "$CURRENT" "reject"

# Reject: prefix-confusion attack (URL starts with current repo URL but
# is actually a different repo)
run_url_test "prefix-confusion rejected" \
    "https://github.com/Nerdy-Q/claude-power-pages-plugins-evil/issues/42" "$CURRENT" "reject"

# Reject: non-issue URL (PR, release, blob, etc.)
run_url_test "PR URL rejected (not issue)" \
    "$CURRENT/pull/42" "$CURRENT" "reject"

run_url_test "blob URL rejected (not issue)" \
    "$CURRENT/blob/main/README.md" "$CURRENT" "reject"

# Reject: javascript: scheme (defense in depth — shouldn't reach the
# function but proves the regex anchors)
run_url_test "non-https scheme rejected" \
    "javascript:alert(1)" "$CURRENT" "reject"

# Reject: data: scheme
run_url_test "data scheme rejected" \
    "data:text/plain,hello" "$CURRENT" "reject"

# Reject: untrusted host (gitlab URL shape but evilgitlab.com)
run_url_test "wrong host rejected" \
    "https://evilgitlab.com/owner/repo/issues/1" "$CURRENT" "reject"

# GitLab dynamic mocking is omitted — the URL-shape regex covers GitLab
# patterns the same as GitHub, and the same-repo enforcement uses the
# same code path differing only in which CLI is invoked.

# Reject: subdomain spoof — host is "github.com.evil.com" not "github.com"
run_url_test "subdomain spoof rejected (github.com.evil.com)" \
    "https://github.com.evil.com/owner/repo/issues/1" "$CURRENT" "reject"

# Reject: port number injection (regex doesn't allow colon)
run_url_test "port number rejected" \
    "https://github.com:8080/Nerdy-Q/claude-power-pages-plugins/issues/1" "$CURRENT" "reject"

# Reject: http (not https) — would reveal token in cleartext
run_url_test "http scheme rejected" \
    "http://github.com/Nerdy-Q/claude-power-pages-plugins/issues/1" "$CURRENT" "reject"

# Reject: trailing slash after issue number
run_url_test "trailing slash rejected" \
    "$CURRENT/issues/42/" "$CURRENT" "reject"

# Reject: empty URL
run_url_test "empty URL rejected" \
    "" "$CURRENT" "reject"

# Reject: URL with shell metachars (would be caught by shape regex)
run_url_test "URL with semicolon rejected" \
    "https://github.com/owner/repo/issues/42; rm -rf /" "$CURRENT" "reject"

echo
if [ "$FAIL" -eq 0 ]; then
    printf '%d/%d passed\n' "$PASS" "$((PASS + FAIL))"
    exit 0
else
    printf '%d/%d passed; failures: %s\n' "$PASS" "$((PASS + FAIL))" "${FAIL_NAMES[*]}" >&2
    exit 1
fi
