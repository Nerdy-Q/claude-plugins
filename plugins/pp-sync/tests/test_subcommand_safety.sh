#!/usr/bin/env bash
# Regression tests for v2.7.2 / v2.7.3 fixes covering pp subcommand
# code paths beyond the parser. Each section closes a real bug found
# in an independent review of the prior release.
#
# Sections:
#   - cmd_generate_page page-name validation (path traversal + injection)
#   - cmd_journal Issue: line filtering (cross-repo inline URL lockout)
#   - cmd_solution_down/up pick out-of-range crash
#   - cmd_doctor pipefail tolerance outside git tree
#
# Run from anywhere: ./plugins/pp-sync/tests/test_subcommand_safety.sh

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

# Build a tmp $PP_CONFIG_DIR with a registered project + a fake REPO that
# contains the minimum directory structure pp expects. Echoes the conf
# dir path so the caller can scope env vars + assertions to it.
make_project() {
    local name="${1:-test}"
    local solutions="${2:-}"
    local tmp
    tmp=$(mktemp -d)
    TMPDIRS+=( "$tmp" )
    mkdir -p "$tmp/projects" "$tmp/repo/site---site/web-pages" "$tmp/repo/dataverse-schema"
    {
        printf 'NAME="%s"\n' "$name"
        printf 'REPO="%s/repo"\n' "$tmp"
        printf 'SITE_DIR="site---site"\n'
        printf 'PROFILE="testprof"\n'
    } > "$tmp/projects/$name.conf"
    if [ -n "$solutions" ]; then
        printf 'SOLUTIONS=(%s)\n' "$solutions" >> "$tmp/projects/$name.conf"
    fi
    printf '%s\n' "$tmp"
}

assert_no_files_outside_site_dir() {
    local conf="$1"
    # Use awk for the negative match — grep -v exits 1 when nothing
    # passes the filter, which trips pipefail; awk just produces no
    # output and exits 0 cleanly.
    local count
    count=$(find "$conf/repo" -type f 2>/dev/null \
        | awk '!/\/site---site\//' \
        | wc -l | tr -d ' ')
    if [ "${count:-0}" -gt 0 ]; then
        printf 'FOUND files outside site_dir:\n' >&2
        find "$conf/repo" -type f 2>/dev/null | awk '!/\/site---site\//' >&2
        return 1
    fi
}

# --- Section 1: cmd_generate_page page-name validation --------------------

echo "Section 1 — cmd_generate_page page-name validation"
echo

run_page_name_reject() {
    local label="$1" page_name="$2"
    local conf
    conf=$(make_project)
    local output
    output=$(PP_CONFIG_DIR="$conf" "$PP_BIN" generate-page test "$page_name" 2>&1 || true)
    # Validation must reject — script either dies with "must match" or
    # the explicit traversal-shape error.
    if [[ "$output" != *"must match"* ]] && [[ "$output" != *"may not contain"* ]] && [[ "$output" != *"empty slug"* ]]; then
        FAIL=$((FAIL + 1))
        FAIL_NAMES+=( "$label" )
        printf '  FAIL %s — accepted bad name; output: %s\n' "$label" "$output" >&2
        return
    fi
    # AND no files were created outside the site_dir
    if ! assert_no_files_outside_site_dir "$conf"; then
        FAIL=$((FAIL + 1))
        FAIL_NAMES+=( "$label" )
        printf '  FAIL %s — files leaked outside site_dir\n' "$label" >&2
        return
    fi
    PASS=$((PASS + 1))
    printf '  OK   %s (rejected, no files leaked)\n' "$label"
}

run_page_name_reject "path traversal: ../../etc/foo"  "../../etc/foo"
run_page_name_reject "leading dotdot: ..foo"           "..foo"
run_page_name_reject "trailing dotdot: foo.."          "foo.."
run_page_name_reject "slash injection: Foo/Bar"        "Foo/Bar"
run_page_name_reject "backslash: Foo\\bar"             'Foo\bar'
run_page_name_reject "semicolon injection: Foo;rm"     'Foo;rm -rf /'
run_page_name_reject "double-quote injection"          'Foo"; rm; "'
run_page_name_reject "command substitution: \$(...)"   'Foo$(touch /tmp/page-pwn)'
run_page_name_reject "backtick: \`...\`"               'Foo`touch /tmp/page-pwn`'

# Names that pass identifier validation but slugify to empty —
# v2.9.4 added an explicit empty-slug check after identifier
# validation. Without this guard, the slug would be "" and page_dir
# would resolve to SITE_DIR/web-pages/ itself, polluting the parent.
run_page_name_reject "whitespace-only name"            "   "
run_page_name_reject "pure dots"                       "..."
run_page_name_reject "pure dashes"                     "---"

# Verify the trap files were NOT created
if [ -e /tmp/page-pwn ]; then
    FAIL=$((FAIL + 1))
    FAIL_NAMES+=( "page-name injection executed" )
    printf '  FAIL injection ran: /tmp/page-pwn was created\n' >&2
    rm -f /tmp/page-pwn
else
    PASS=$((PASS + 1))
    printf '  OK   no injection trap files created\n'
fi

# --- Section 2: cmd_journal Issue: line filtering -------------------------

echo
echo "Section 2 — cmd_journal Issue: line filtering"
echo

# Test the URL extraction logic in isolation. The fix changed:
#   grep -oE 'https://(github|gitlab)\.com/...'    [picks any URL]
# to:
#   grep -E '^Issue: https://(github|gitlab)\.com/' | sed 's/^Issue: //'
# This ensures inline cross-repo URLs in user notes don't lock the user
# out of subsequent journal note/close operations.

extract_last_issue_url() {
    grep -E '^Issue: https://(github|gitlab)\.com/' "$1" \
        | tail -1 | sed 's/^Issue: //' || true
}

assert_url_extracted() {
    local label="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        PASS=$((PASS + 1))
        printf '  OK   %s\n' "$label"
    else
        FAIL=$((FAIL + 1))
        FAIL_NAMES+=( "$label" )
        printf '  FAIL %s — expected=%q actual=%q\n' "$label" "$expected" "$actual" >&2
    fi
}

# Fixture 1: single Issue: line, no inline URLs
tmp=$(mktemp -d); TMPDIRS+=( "$tmp" )
cat > "$tmp/JOURNAL.md" <<'EOF'
## [2026-04-29 12:00] TASK: alpha
Issue: https://github.com/Nerdy-Q/claude-power-pages-plugins/issues/42
---
EOF
got=$(extract_last_issue_url "$tmp/JOURNAL.md")
assert_url_extracted "single Issue: line" \
    "https://github.com/Nerdy-Q/claude-power-pages-plugins/issues/42" "$got"

# Fixture 2: Issue: line + inline cross-repo URL in a note (THE bug)
cat > "$tmp/JOURNAL.md" <<'EOF'
## [2026-04-29 12:00] TASK: alpha
Issue: https://github.com/Nerdy-Q/claude-power-pages-plugins/issues/42
---
- **Note**: see also https://github.com/other-org/other-repo/issues/9 for context
- **Note**: more discussion at https://github.com/yet-another/repo/pull/1
EOF
got=$(extract_last_issue_url "$tmp/JOURNAL.md")
assert_url_extracted "Issue: line + inline cross-repo URLs (the v2.7.3 bug fixed)" \
    "https://github.com/Nerdy-Q/claude-power-pages-plugins/issues/42" "$got"

# Fixture 3: multiple Issue: lines from multiple tasks — picks LAST
cat > "$tmp/JOURNAL.md" <<'EOF'
## [2026-04-29 12:00] TASK: alpha
Issue: https://github.com/Nerdy-Q/claude-power-pages-plugins/issues/1
---
## [2026-04-29 13:00] TASK: beta
Issue: https://github.com/Nerdy-Q/claude-power-pages-plugins/issues/2
---
EOF
got=$(extract_last_issue_url "$tmp/JOURNAL.md")
assert_url_extracted "multiple Issue: lines — pick last" \
    "https://github.com/Nerdy-Q/claude-power-pages-plugins/issues/2" "$got"

# Fixture 4: only inline URLs, no Issue: lines — extraction returns empty
cat > "$tmp/JOURNAL.md" <<'EOF'
- **Note**: see https://github.com/some/repo/issues/5
- **Note**: also https://github.com/another/repo/issues/9
EOF
got=$(extract_last_issue_url "$tmp/JOURNAL.md")
assert_url_extracted "only inline URLs — empty extraction" "" "$got"

# Fixture 5: empty file — empty extraction
: > "$tmp/JOURNAL.md"
got=$(extract_last_issue_url "$tmp/JOURNAL.md")
assert_url_extracted "empty journal — empty extraction" "" "$got"

# Fixture 6: gitlab Issue: line
cat > "$tmp/JOURNAL.md" <<'EOF'
Issue: https://gitlab.com/Nerdy-Q/foo/-/issues/3
EOF
got=$(extract_last_issue_url "$tmp/JOURNAL.md")
assert_url_extracted "gitlab Issue: line" \
    "https://gitlab.com/Nerdy-Q/foo/-/issues/3" "$got"

# Fixture 7: Issue: line with trailing whitespace tolerance
printf 'Issue: https://github.com/Nerdy-Q/claude-power-pages-plugins/issues/7   \n' > "$tmp/JOURNAL.md"
got=$(extract_last_issue_url "$tmp/JOURNAL.md")
# Trailing spaces are part of what gets captured. Test that the URL
# itself is intact at the start of the captured string.
case "$got" in
    "https://github.com/Nerdy-Q/claude-power-pages-plugins/issues/7"*)
        PASS=$((PASS + 1))
        printf '  OK   trailing whitespace tolerated (URL prefix matches)\n'
        ;;
    *)
        FAIL=$((FAIL + 1))
        FAIL_NAMES+=( "trailing whitespace" )
        printf '  FAIL trailing whitespace: got=%q\n' "$got" >&2
        ;;
esac

# --- Section 3: cmd_solution_down/up pick out-of-range --------------------

echo
echo "Section 3 — cmd_solution_down pick range validation"
echo

run_solution_pick() {
    local label="$1" pick="$2" expect="$3"
    local conf
    conf=$(make_project test '"FooSolution" "BarSolution"')
    # Feed the pick to the interactive prompt; "y" to confirm if needed.
    local output
    output=$(printf '%s\n' "$pick" | PP_CONFIG_DIR="$conf" "$PP_BIN" solution-down test 2>&1 || true)

    case "$expect" in
        reject)
            # Must die with the friendly "Pick must be between" message,
            # NOT with bash's "unbound variable" or "bad array subscript".
            if [[ "$output" == *"Pick must be between"* ]]; then
                PASS=$((PASS + 1))
                printf '  OK   %s (rejected with friendly error)\n' "$label"
            elif [[ "$output" == *"unbound variable"* ]] \
                || [[ "$output" == *"bad array subscript"* ]]; then
                FAIL=$((FAIL + 1))
                FAIL_NAMES+=( "$label" )
                printf '  FAIL %s — crashed with bash error instead of friendly die\n' "$label" >&2
                printf '       output: %s\n' "$output" >&2
            else
                FAIL=$((FAIL + 1))
                FAIL_NAMES+=( "$label" )
                printf '  FAIL %s — unexpected output: %s\n' "$label" "$output" >&2
            fi
            ;;
        accept)
            # Validation passed; failure later (no pac CLI) is fine.
            if [[ "$output" == *"Pick must be between"* ]]; then
                FAIL=$((FAIL + 1))
                FAIL_NAMES+=( "$label" )
                printf '  FAIL %s — rejected valid pick\n' "$label" >&2
            else
                PASS=$((PASS + 1))
                printf '  OK   %s (validation passed)\n' "$label"
            fi
            ;;
    esac
}

run_solution_pick "pick out of range high (99)"  "99"  "reject"
run_solution_pick "pick zero (0)"                "0"   "reject"
run_solution_pick "pick way out of range (1000)" "1000" "reject"
run_solution_pick "pick valid (1)"               "1"   "accept"
run_solution_pick "pick valid (2)"               "2"   "accept"

# CLI arg path traversal — solution name from `pp solution-down acme X`
# must validate against [A-Za-z0-9_.-]+
echo
echo "Section 3b — solution name CLI arg validation"
echo

run_solution_cli_arg() {
    local label="$1" arg="$2"
    local conf
    conf=$(make_project test '"FooSolution"')
    local out
    out=$(PP_CONFIG_DIR="$conf" "$PP_BIN" solution-down test "$arg" 2>&1 || true)
    if [[ "$out" == *"must match"* ]]; then
        PASS=$((PASS + 1))
        printf '  OK   %s (rejected: %s)\n' "$label" "$arg"
    elif [[ "$out" == *"unbound variable"* ]] || [[ "$out" == *"bad array"* ]]; then
        FAIL=$((FAIL + 1))
        FAIL_NAMES+=( "$label" )
        printf '  FAIL %s — bash crash instead of friendly reject\n' "$label" >&2
    else
        FAIL=$((FAIL + 1))
        FAIL_NAMES+=( "$label" )
        printf '  FAIL %s — accepted bad solution name\n' "$label" >&2
        printf '       out: %s\n' "$out" >&2
    fi
}

run_solution_cli_arg "path traversal: ../../etc/foo"    "../../etc/foo"
run_solution_cli_arg "slash injection: Foo/Bar"         "Foo/Bar"
run_solution_cli_arg "shell metachar: Foo\$bar"         'Foo$bar'
run_solution_cli_arg "semicolon: Foo;rm"                'Foo;rm'

# --- Section 4: cmd_doctor outside git tree ------------------------------

echo
echo "Section 4 — cmd_doctor pipefail tolerance"
echo

# Run pp doctor against a project whose REPO is NOT a git tree. Under
# strict mode, the `git status | wc | tr` pipeline tripped pipefail
# because git exits 128 in non-git directories. The fix added `|| echo 0`
# to each counter pipeline.
test_doctor_outside_git() {
    local conf
    conf=$(make_project)
    # Note: REPO is /tmp/.../repo — not a git tree. pac is missing
    # (so doctor will warn about that), but we only care that the
    # script DOESN'T abort before reaching the file-count section.
    local output
    output=$(PP_CONFIG_DIR="$conf" "$PP_BIN" doctor test 2>&1 || true)
    # The site-content section runs LAST. If pipefail aborted earlier,
    # this section never appears.
    if [[ "$output" == *"Site content counts"* ]]; then
        PASS=$((PASS + 1))
        printf '  OK   doctor reaches Site content counts section outside git tree\n'
    else
        FAIL=$((FAIL + 1))
        FAIL_NAMES+=( "doctor outside git tree" )
        printf '  FAIL doctor aborted before reaching site-counts section\n' >&2
        printf '       output: %s\n' "$output" >&2
    fi
}

test_doctor_outside_git

# --- Summary ---------------------------------------------------------------

echo
if [ "$FAIL" -eq 0 ]; then
    printf '%d/%d passed\n' "$PASS" "$((PASS + FAIL))"
    exit 0
else
    printf '%d/%d passed; failures: %s\n' "$PASS" "$((PASS + FAIL))" "${FAIL_NAMES[*]}" >&2
    exit 1
fi
