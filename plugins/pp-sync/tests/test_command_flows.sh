#!/usr/bin/env bash
# Command-flow regression tests — happy path + error cases for the pp
# subcommands the existing suites don't exercise. Each section closes
# a class of bugs (atomicity, ambiguity, state consistency, idempotency)
# that hand-testing tends to miss.
#
# Sections:
#   1. project name resolution (exact / alias / prefix / ambiguous / none)
#   2. cmd_show
#   3. cmd_list (empty + populated)
#   4. cmd_alias_add / cmd_alias_list
#   5. cmd_project_remove (atomicity + alias cleanup + active reset)
#   6. cmd_switch / cmd_status (active state)
#   7. cmd_journal init (idempotency + template content)
#   8. cmd_generate_page happy path (file structure)
#   9. cmd_sync_pages (direction validation + actual copy)
#  10. cmd_help (exits 0, lists all subcommands)
#
# Run from anywhere: ./plugins/pp-sync/tests/test_command_flows.sh

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

# --- helpers --------------------------------------------------------------

# Build a tmp $PP_CONFIG_DIR with one or more registered projects.
# Args: name1 name2 name3 ...
make_registry() {
    local tmp
    tmp=$(mktemp -d)
    TMPDIRS+=( "$tmp" )
    mkdir -p "$tmp/projects"
    local name
    for name in "$@"; do
        mkdir -p "$tmp/repo-$name/site---site/web-pages"
        {
            printf 'NAME="%s"\n' "$name"
            printf 'REPO="%s/repo-%s"\n' "$tmp" "$name"
            printf 'SITE_DIR="site---site"\n'
            printf 'PROFILE="testprof"\n'
        } > "$tmp/projects/$name.conf"
    done
    printf '%s\n' "$tmp"
}

assert_pass() {
    local label="$1"
    PASS=$((PASS + 1))
    printf '  OK   %s\n' "$label"
}

assert_fail() {
    local label="$1" detail="${2:-}"
    FAIL=$((FAIL + 1))
    FAIL_NAMES+=( "$label" )
    printf '  FAIL %s\n' "$label" >&2
    [ -n "$detail" ] && printf '       %s\n' "$detail" >&2 || true
}

assert_contains() {
    local label="$1" expected="$2" haystack="$3"
    if [[ "$haystack" == *"$expected"* ]]; then
        assert_pass "$label"
    else
        assert_fail "$label" "expected substring '$expected' in: $haystack"
    fi
}

assert_not_contains() {
    local label="$1" forbidden="$2" haystack="$3"
    if [[ "$haystack" != *"$forbidden"* ]]; then
        assert_pass "$label"
    else
        assert_fail "$label" "forbidden substring '$forbidden' in: $haystack"
    fi
}

# --- Section 1: project name resolution ----------------------------------

echo "Section 1 — project name resolution"
echo

reg=$(make_registry alpha beta contoso-dev contoso-client)

# Exact match
out=$(PP_CONFIG_DIR="$reg" "$PP_BIN" show alpha 2>&1 || true)
assert_contains "exact match: 'alpha' resolves to alpha" "alpha" "$out"

# Unique prefix
out=$(PP_CONFIG_DIR="$reg" "$PP_BIN" show be 2>&1 || true)
assert_contains "unique prefix: 'be' resolves to beta" "beta" "$out"

# Ambiguous prefix should fail with a clear error
out=$(PP_CONFIG_DIR="$reg" "$PP_BIN" show contoso 2>&1 || true)
assert_contains "ambiguous prefix produces error" "Ambiguous" "$out"
assert_contains "ambiguous prefix lists candidates: contoso-dev" "contoso-dev" "$out"
assert_contains "ambiguous prefix lists candidates: contoso-client" "contoso-client" "$out"

# No match
out=$(PP_CONFIG_DIR="$reg" "$PP_BIN" show nomatch 2>&1 || true)
assert_contains "no-match produces 'Unknown project' error" "Unknown project" "$out"

# Alias resolution
echo "petro=contoso-dev" > "$reg/aliases"
out=$(PP_CONFIG_DIR="$reg" "$PP_BIN" show petro 2>&1 || true)
assert_contains "alias resolution: 'petro' resolves to contoso-dev" "contoso-dev" "$out"

# Alias takes precedence over exact match? No — exact match is checked
# first, then alias, then prefix. So if a project named "petro" existed,
# the alias would NOT shadow it. Verify:
mkdir -p "$reg/projects"
{
    printf 'NAME="petro"\n'
    printf 'REPO="/tmp/x"\n'
    printf 'SITE_DIR="s"\n'
    printf 'PROFILE="p"\n'
} > "$reg/projects/petro.conf"
out=$(PP_CONFIG_DIR="$reg" "$PP_BIN" show petro 2>&1 || true)
assert_contains "exact match wins over alias: 'petro' shows petro project" "Repo:           /tmp/x" "$out"

# --- Section 2: cmd_show ---------------------------------------------------

echo
echo "Section 2 — cmd_show"
echo

reg=$(make_registry alpha)
out=$(PP_CONFIG_DIR="$reg" "$PP_BIN" show alpha 2>&1 || true)
assert_contains "show outputs project name" "alpha" "$out"
assert_contains "show outputs Repo:" "Repo:" "$out"
assert_contains "show outputs Site dir:" "Site dir:" "$out"
assert_contains "show outputs PAC profile:" "PAC profile:" "$out"
assert_contains "show outputs Config file:" "Config file:" "$out"

# Show against non-existent project
out=$(PP_CONFIG_DIR="$reg" "$PP_BIN" show ghost 2>&1 || true)
assert_contains "show against ghost: error" "Unknown project" "$out"

# --- Section 3: cmd_list --------------------------------------------------

echo
echo "Section 3 — cmd_list"
echo

# Empty registry
empty=$(mktemp -d); TMPDIRS+=( "$empty" )
mkdir -p "$empty/projects"
out=$(PP_CONFIG_DIR="$empty" "$PP_BIN" list 2>&1 || true)
assert_contains "empty registry: friendly message" "No projects" "$out"

# Populated registry
reg=$(make_registry alpha beta gamma)
out=$(PP_CONFIG_DIR="$reg" "$PP_BIN" list 2>&1 || true)
assert_contains "list shows alpha" "alpha" "$out"
assert_contains "list shows beta" "beta" "$out"
assert_contains "list shows gamma" "gamma" "$out"
assert_contains "list has PROJECT header" "PROJECT" "$out"

# --- Section 4: cmd_alias_add / cmd_alias_list ----------------------------

echo
echo "Section 4 — alias add/list"
echo

reg=$(make_registry alpha beta)

# Valid alias
out=$(PP_CONFIG_DIR="$reg" "$PP_BIN" alias add a alpha 2>&1 || true)
assert_contains "valid alias add succeeds" "Alias added" "$out"
[ -f "$reg/aliases" ] && grep -q "^a=alpha$" "$reg/aliases" && assert_pass "alias written to file" \
    || assert_fail "alias written to file"

# Alias to non-existent target → die
out=$(PP_CONFIG_DIR="$reg" "$PP_BIN" alias add ghost ghostproject 2>&1 || true)
assert_contains "alias to ghost target: rejected" "Unknown target" "$out"
grep -q "^ghost=" "$reg/aliases" 2>/dev/null \
    && assert_fail "ghost alias should NOT be written" \
    || assert_pass "ghost alias not written (atomic reject)"

# Invalid alias name → die
out=$(PP_CONFIG_DIR="$reg" "$PP_BIN" alias add 'ev;il' alpha 2>&1 || true)
assert_contains "shell-metachar alias name rejected" "must match" "$out"

# alias list — output is space-separated `<alias>  <target>`
out=$(PP_CONFIG_DIR="$reg" "$PP_BIN" alias list 2>&1 || true)
assert_contains "alias list shows alias 'a'" "a" "$out"
assert_contains "alias list shows target 'alpha'" "alpha" "$out"

# Duplicate alias replaces (current behavior)
out=$(PP_CONFIG_DIR="$reg" "$PP_BIN" alias add a beta 2>&1 || true)
assert_contains "duplicate alias replaces target" "Alias added" "$out"
target_after=$(grep '^a=' "$reg/aliases" | cut -d= -f2)
[ "$target_after" = "beta" ] && assert_pass "duplicate alias overwrites old target" \
    || assert_fail "duplicate alias overwrite" "got '$target_after', expected 'beta'"

# Alias file contains exactly one 'a=' entry
count=$(grep -c '^a=' "$reg/aliases" || echo 0)
[ "$count" = "1" ] && assert_pass "no duplicate alias rows" \
    || assert_fail "no duplicate alias rows" "got $count rows"

# --- Section 5: cmd_project_remove (atomicity) ----------------------------

echo
echo "Section 5 — cmd_project_remove"
echo

reg=$(make_registry alpha beta gamma)
echo "a=alpha" > "$reg/aliases"
echo "g=gamma" >> "$reg/aliases"
echo "alpha" > "$reg/active"

# Remove alpha — should delete conf AND alias AND clear active
out=$(printf 'y\n' | PP_CONFIG_DIR="$reg" "$PP_BIN" project remove alpha 2>&1 || true)
assert_contains "remove succeeds" "Removed alpha" "$out"
[ ! -f "$reg/projects/alpha.conf" ] && assert_pass "alpha conf file removed" \
    || assert_fail "alpha conf file still exists"
grep -q "^a=alpha$" "$reg/aliases" 2>/dev/null \
    && assert_fail "alias row still references removed alpha" \
    || assert_pass "alias row removed"
[ ! -f "$reg/active" ] && assert_pass "active file cleared" \
    || assert_fail "active file not cleared" "contents: $(cat "$reg/active")"

# Other aliases untouched
grep -q "^g=gamma$" "$reg/aliases" \
    && assert_pass "unrelated alias preserved" \
    || assert_fail "unrelated alias g=gamma was wiped"

# Remove non-existent project → die
out=$(PP_CONFIG_DIR="$reg" "$PP_BIN" project remove ghost 2>&1 || true)
assert_contains "remove ghost: rejected" "Unknown project" "$out"

# --- Section 6: cmd_switch / cmd_status -----------------------------------

echo
echo "Section 6 — switch / status"
echo

reg=$(make_registry alpha beta)

# Status with no active project
out=$(PP_CONFIG_DIR="$reg" "$PP_BIN" status 2>&1 || true)
assert_contains "status with no active: friendly message" "No active project" "$out"

# Switch sets active
out=$(PP_CONFIG_DIR="$reg" "$PP_BIN" switch alpha 2>&1 || true)
[ -f "$reg/active" ] && [ "$(cat "$reg/active")" = "alpha" ] \
    && assert_pass "switch wrote active=alpha" \
    || assert_fail "switch did not write active correctly" "active='$(cat "$reg/active" 2>/dev/null)'"

# Status with active set
out=$(PP_CONFIG_DIR="$reg" "$PP_BIN" status 2>&1 || true)
assert_contains "status with active: shows project name" "alpha" "$out"
assert_not_contains "status doesn't say 'no active'" "No active project" "$out"

# Switch to other project, status reflects new active
PP_CONFIG_DIR="$reg" "$PP_BIN" switch beta >/dev/null 2>&1 || true
out=$(PP_CONFIG_DIR="$reg" "$PP_BIN" status 2>&1 || true)
assert_contains "status reflects switched-to beta" "beta" "$out"

# --- Section 7: cmd_journal init -----------------------------------------

echo
echo "Section 7 — cmd_journal init"
echo

reg=$(make_registry alpha)
project_repo="$reg/repo-alpha"

# init creates JOURNAL.md
out=$(PP_CONFIG_DIR="$reg" "$PP_BIN" journal alpha init 2>&1 || true)
[ -f "$project_repo/JOURNAL.md" ] && assert_pass "journal init creates JOURNAL.md" \
    || assert_fail "JOURNAL.md not created" "output: $out"

# Template includes the project name
content=$(cat "$project_repo/JOURNAL.md" 2>/dev/null || echo "")
assert_contains "JOURNAL.md includes project name" "alpha" "$content"
assert_contains "JOURNAL.md has Project Context section" "Project Context" "$content"

# Idempotent: second init does NOT overwrite
echo "MANUAL EDIT" >> "$project_repo/JOURNAL.md"
PP_CONFIG_DIR="$reg" "$PP_BIN" journal alpha init >/dev/null 2>&1 || true
content=$(cat "$project_repo/JOURNAL.md")
assert_contains "init is idempotent (preserves manual edits)" "MANUAL EDIT" "$content"

# --- Section 8: cmd_generate_page happy path ------------------------------

echo
echo "Section 8 — cmd_generate_page happy path"
echo

reg=$(make_registry alpha)
project_repo="$reg/repo-alpha"
site_dir="$project_repo/site---site"

# Generate a page with a valid name
out=$(PP_CONFIG_DIR="$reg" "$PP_BIN" generate-page alpha "My New Page" 2>&1 || true)
page_dir="$site_dir/web-pages/my-new-page"
[ -d "$page_dir" ] && assert_pass "page dir created" \
    || assert_fail "page dir not created" "output: $out"
[ -f "$page_dir/My New Page.webpage.yml" ] && assert_pass "base YAML created" \
    || assert_fail "base YAML missing"
[ -f "$page_dir/My New Page.webpage.copy.html" ] && assert_pass "base HTML created" \
    || assert_fail "base HTML missing"
[ -d "$page_dir/content-pages" ] && assert_pass "content-pages dir created" \
    || assert_fail "content-pages dir missing"
[ -d "$page_dir/content-pages/en-US" ] && assert_pass "content-pages/en-US dir created" \
    || assert_fail "content-pages/en-US dir missing"
[ -f "$page_dir/content-pages/en-US/My New Page.en-US.webpage.copy.html" ] && assert_pass "localized HTML created in lang dir" \
    || assert_fail "localized HTML missing in lang dir"
[ -f "$page_dir/content-pages/en-US/My New Page.en-US.webpage.custom_javascript.js" ] && assert_pass "localized JS created in lang dir" \
    || assert_fail "localized JS missing in lang dir"
[ ! -f "$page_dir/content-pages/My New Page.en-US.webpage.copy.html" ] && assert_pass "no legacy flat localized HTML created" \
    || assert_fail "legacy flat localized HTML should not exist"
[ ! -f "$page_dir/content-pages/My New Page.en-US.webpage.custom_javascript.js" ] && assert_pass "no legacy flat localized JS created" \
    || assert_fail "legacy flat localized JS should not exist"

# Existing page → die
out=$(PP_CONFIG_DIR="$reg" "$PP_BIN" generate-page alpha "My New Page" 2>&1 || true)
assert_contains "duplicate generate-page rejected" "already exists" "$out"

# --- Section 9: cmd_sync_pages -------------------------------------------

echo
echo "Section 9 — cmd_sync_pages"
echo

reg=$(make_registry alpha)
project_repo="$reg/repo-alpha"
page_dir="$project_repo/site---site/web-pages/test-page"
mkdir -p "$page_dir/content-pages/en-US" "$page_dir/content-pages/fr-FR"
echo "BASE CONTENT" > "$page_dir/test-page.webpage.copy.html"
echo "OLD LOCALIZED" > "$page_dir/content-pages/en-US/test-page.en-US.webpage.copy.html"
echo "ANCIEN LOCALIZED" > "$page_dir/content-pages/fr-FR/test-page.fr-FR.webpage.copy.html"

# base-to-localized: base content should overwrite all localized variants
out=$(PP_CONFIG_DIR="$reg" "$PP_BIN" sync-pages alpha base-to-localized 2>&1 || true)
loc_en=$(cat "$page_dir/content-pages/en-US/test-page.en-US.webpage.copy.html" 2>/dev/null || echo "")
loc_fr=$(cat "$page_dir/content-pages/fr-FR/test-page.fr-FR.webpage.copy.html" 2>/dev/null || echo "")
[ "$loc_en" = "BASE CONTENT" ] && assert_pass "base-to-localized copied en-US content" \
    || assert_fail "base-to-localized en-US failed" "loc_en='$loc_en'"
[ "$loc_fr" = "BASE CONTENT" ] && assert_pass "base-to-localized copied fr-FR content" \
    || assert_fail "base-to-localized fr-FR failed" "loc_fr='$loc_fr'"

# Reset and test the other direction
rm -f "$page_dir/content-pages/fr-FR/test-page.fr-FR.webpage.copy.html"
echo "NEW BASE" > "$page_dir/test-page.webpage.copy.html"
echo "LOCALIZED CONTENT" > "$page_dir/content-pages/en-US/test-page.en-US.webpage.copy.html"

# localized-to-base: localized should overwrite base
out=$(PP_CONFIG_DIR="$reg" "$PP_BIN" sync-pages alpha localized-to-base 2>&1 || true)
base=$(cat "$page_dir/test-page.webpage.copy.html" 2>/dev/null || echo "")
[ "$base" = "LOCALIZED CONTENT" ] && assert_pass "localized-to-base copied content" \
    || assert_fail "localized-to-base failed" "base='$base'"

# Invalid direction
out=$(printf 'invalid\n' | PP_CONFIG_DIR="$reg" "$PP_BIN" sync-pages alpha 2>&1 || true)
assert_contains "invalid sync-pages direction rejected" "Invalid choice" "$out"

# Invalid explicit direction should also reject rather than no-op
out=$(PP_CONFIG_DIR="$reg" "$PP_BIN" sync-pages alpha bogus 2>&1 || true)
assert_contains "invalid explicit sync-pages direction rejected" "Invalid sync-pages direction" "$out"

# --- Section 10: cmd_help ------------------------------------------------

echo
echo "Section 10 — cmd_help"
echo

out=$("$PP_BIN" help 2>&1)
status=$?
[ "$status" = "0" ] && assert_pass "help exits 0" \
    || assert_fail "help non-zero exit" "status=$status"
assert_contains "help lists 'down'" "pp down" "$out"
assert_contains "help lists 'up'" "pp up" "$out"
assert_contains "help lists 'doctor'" "pp doctor" "$out"
assert_contains "help lists 'audit'" "pp audit" "$out"
assert_contains "help lists 'setup'" "setup" "$out"
assert_contains "help lists 'journal'" "journal" "$out"

# --- Summary ---------------------------------------------------------------

echo
if [ "$FAIL" -eq 0 ]; then
    printf '%d/%d passed\n' "$PASS" "$((PASS + FAIL))"
    exit 0
else
    printf '%d/%d passed; failures: %s\n' "$PASS" "$((PASS + FAIL))" "${FAIL_NAMES[*]}" >&2
    exit 1
fi
