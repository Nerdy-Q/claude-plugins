#!/usr/bin/env bash
# End-to-end tests for the project-drop-in templates in plugins/pp-sync/templates/.
#
# Each template (down.sh, up.sh, doctor.sh, solution-down.sh, solution-up.sh,
# commit.sh) is dropped into a project repo to glue together pac, git, and a
# few prompts. They've never had direct test coverage — only pp-sync's bin/pp
# (which sources the templates indirectly) was tested. v2.10.0's CHANGELOG
# explicitly listed this as a remaining gap.
#
# Strategy:
#   1. Spin up a fresh temp git repo per template
#   2. Put the mock pac on PATH (state + audit log scoped to the temp dir)
#   3. Override the template's PUT_*_HERE placeholders via env vars
#   4. Pipe Y/N answers to confirmation prompts on stdin
#   5. Assert on stdout shape AND on the audit log to verify pac invocations
#
# The audit log is the load-bearing assertion: it pins the exact pac
# subcommand+args each template runs, so refactors that accidentally drop a
# step (e.g. removing pac auth select before pac org who) get caught here.
#
# Run: bash plugins/pp-sync/tests/test_templates.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_DIR="$PLUGIN_ROOT/templates"
MOCK_DIR="$SCRIPT_DIR/mocks"
MOCK_PAC="$MOCK_DIR/pac"

[ -x "$MOCK_PAC" ] || { echo "Cannot find mock pac at $MOCK_PAC" >&2; exit 1; }
[ -d "$TEMPLATE_DIR" ] || { echo "Cannot find templates dir at $TEMPLATE_DIR" >&2; exit 1; }

PASS=0
FAIL=0
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

# Make a fresh temp dir containing:
#   - an initialized git repo at $tmp/repo (with one initial commit)
#   - a mock pac state dir at $tmp/pac (with $1 profile registered + selected)
#   - an empty audit log at $tmp/audit.log
#
# Args: <profile_name> [<env_url>]
# Echoes the temp root.
make_template_env() {
    local profile="${1:-testprof}"
    local env_url="${2:-https://acme-dev.crm.dynamics.com/}"
    local tmp
    tmp=$(mktemp -d)
    TMPDIRS+=( "$tmp" )

    mkdir -p "$tmp/repo" "$tmp/pac"
    (
        cd "$tmp/repo" || exit 1
        git init -q
        git config user.email t@t
        git config user.name t
        # An initial commit gives us a HEAD for `git diff HEAD` etc.
        : > .gitkeep
        git add .gitkeep
        git commit -q -m initial
    )

    printf '%s=%s\n' "$profile" "$env_url" > "$tmp/pac/profiles"
    printf '%s' "$profile" > "$tmp/pac/selected"
    : > "$tmp/audit.log"

    printf '%s\n' "$tmp"
}

# Read a NUL-separated audit log into one space-joined invocation per line.
# tr converts each NUL to a space; the trailing newline already terminates
# the record. So `pac auth list` becomes "auth list ".
audit_lines() {
    local log="$1"
    [ -f "$log" ] || return 0
    tr '\0' ' ' < "$log"
}

# Assert audit log contains a line matching a glob pattern.
# Args: <test_root> <name> <pattern>
assert_audit_match() {
    local root="$1" name="$2" pat="$3"
    local lines
    lines=$(audit_lines "$root/audit.log")
    case "$lines" in
        *$pat*) assert_pass "audit log contains: $name" ;;
        *)
            assert_fail "audit log missing: $name" "log:
$(printf '%s' "$lines" | sed 's/^/         /')"
            ;;
    esac
}

# Run a template in a sub-shell with mock pac on PATH and scoped state.
# Args: <test_root> <template_relpath> [<additional env vars in form K=V>] -- [<template args>]
# Reads stdin from caller (so caller can pipe Y/N answers).
# Echoes combined stdout+stderr; returns template's exit code.
#
# `"${arr[@]+"${arr[@]}"}"` is the bash 3.2-safe way to expand a possibly-
# empty array under `set -u`. Bash 4.4+ relaxed this; macOS still ships 3.2.
run_template() {
    local root="$1"; shift
    local template="$1"; shift
    local -a env_vars=()
    local -a args=()
    local seen_dash=0
    local arg
    for arg in "$@"; do
        if [ "$arg" = "--" ]; then
            seen_dash=1
            continue
        fi
        if [ "$seen_dash" = "0" ]; then
            env_vars+=( "$arg" )
        else
            args+=( "$arg" )
        fi
    done
    (
        cd "$root/repo" || exit 1
        export PATH="$MOCK_DIR:$PATH"
        export PP_MOCK_PAC_STATE_DIR="$root/pac"
        export PP_MOCK_PAC_AUDIT_LOG="$root/audit.log"
        local pair
        for pair in "${env_vars[@]+"${env_vars[@]}"}"; do
            # KEY=VALUE strings — shellcheck SC2163 thinks we want to
            # export a variable literally named "pair"; we don't.
            # shellcheck disable=SC2163
            export "$pair"
        done
        bash "$TEMPLATE_DIR/$template" "${args[@]+"${args[@]}"}" 2>&1
    )
}

# --- Section 1: down.sh refuses unedited placeholders -------------------

echo "Section 1 — down.sh placeholder guard"
echo

env=$(make_template_env testprof)
# No env overrides → SITE_DIR/PROFILE/WEBSITE_ID stay as PUT_*_HERE.
out=$(run_template "$env" down.sh -- 2>&1; echo "RC=$?")
case "$out" in
    *"edit this script first"*) assert_pass "down.sh refuses unedited placeholders" ;;
    *) assert_fail "down.sh didn't refuse placeholders" "out: $(printf '%s' "$out" | head -5)" ;;
esac
case "$out" in
    *"RC=2"*) assert_pass "down.sh exits 2 on placeholder guard" ;;
    *) assert_fail "down.sh wrong exit code" "out: $out" ;;
esac
# Audit log should be empty — pac was never invoked
[ ! -s "$env/audit.log" ] && assert_pass "down.sh placeholder path makes no pac calls" \
    || assert_fail "down.sh hit pac despite placeholder guard" "log: $(audit_lines "$env/audit.log")"

# --- Section 2: down.sh full happy path ---------------------------------

echo
echo "Section 2 — down.sh happy path"
echo

env=$(make_template_env testprof)
# Pipe one 'y' to the "Continue download" confirmation. Working tree is
# clean (only initial commit), so the dirty-tree branch is skipped.
out=$(printf 'y\n' | run_template "$env" down.sh \
    SITE_DIR=site---site PROFILE=testprof \
    WEBSITE_ID=00000000-0000-0000-0000-000000000001 \
    MODEL_VERSION=2 -- 2>&1; echo "RC=$?")

case "$out" in
    *"Active env: https://acme-dev.crm.dynamics.com/"*)
        assert_pass "down.sh reports active env URL"
        ;;
    *)
        assert_fail "down.sh didn't print active env" "out: $(printf '%s' "$out" | head -10)"
        ;;
esac
case "$out" in
    *"Done."*"RC=0"*) assert_pass "down.sh reaches Done with RC=0" ;;
    *) assert_fail "down.sh didn't reach Done with RC=0" "out: $(printf '%s' "$out" | tail -10)" ;;
esac

assert_audit_match "$env" "auth select --name testprof"   "auth select --name testprof"
assert_audit_match "$env" "org who"                        "org who"
assert_audit_match "$env" "paportal download --path ."     "paportal download --path . "
assert_audit_match "$env" "paportal download --webSiteId"  "--webSiteId 00000000-0000-0000-0000-000000000001"
assert_audit_match "$env" "paportal download --modelVersion 2" "--modelVersion 2"

# --- Section 3: down.sh aborts on No --------------------------------------

echo
echo "Section 3 — down.sh aborts on N"
echo

env=$(make_template_env testprof)
out=$(printf 'n\n' | run_template "$env" down.sh \
    SITE_DIR=site---site PROFILE=testprof \
    WEBSITE_ID=00000000-0000-0000-0000-000000000001 -- 2>&1)
case "$out" in
    *"Aborted"*) assert_pass "down.sh aborts when user answers N" ;;
    *) assert_fail "down.sh didn't abort on N" "out: $(printf '%s' "$out" | head -5)" ;;
esac
# Should have done auth + org-who, but NOT paportal download
case "$(audit_lines "$env/audit.log")" in
    *"paportal download"*)
        assert_fail "down.sh ran paportal download despite N answer"
        ;;
    *)
        assert_pass "down.sh skipped paportal download on N"
        ;;
esac

# --- Section 4: up.sh --validate-only --------------------------------------

echo
echo "Section 4 — up.sh --validate-only"
echo

env=$(make_template_env testprof)
mkdir -p "$env/repo/site---site"
# No prod confirm needed (env URL is acme-dev). Pipe 'y' just in case
# bulk threshold triggers (it won't — no files changed).
out=$(printf 'y\n' | run_template "$env" up.sh \
    SITE_DIR=site---site PROFILE=testprof MODEL_VERSION=2 \
    BULK_THRESHOLD=50 -- --validate-only 2>&1; echo "RC=$?")

assert_audit_match "$env" "auth select --name testprof" "auth select --name testprof"
assert_audit_match "$env" "org who" "org who"
assert_audit_match "$env" "paportal upload --validateBeforeUpload" "paportal upload --path . --modelVersion 2 --validateBeforeUpload"

# Regression: clean working tree should not trip pipefail in CHANGED count.
# Smoke test (curl) may fail with 000 in offline CI — accept any HTTP
# outcome, just check the script reached Done with RC=0.
case "$out" in
    *"Done."*"RC=0"*) assert_pass "up.sh --validate-only ran to completion (RC=0)" ;;
    *) assert_fail "up.sh didn't reach Done with RC=0" "out: $(printf '%s' "$out" | tail -10)" ;;
esac

# --- Section 5: up.sh full upload (non-prod) -------------------------------

echo
echo "Section 5 — up.sh full upload"
echo

env=$(make_template_env testprof)
mkdir -p "$env/repo/site---site"
out=$(printf 'y\n' | run_template "$env" up.sh \
    SITE_DIR=site---site PROFILE=testprof MODEL_VERSION=2 \
    BULK_THRESHOLD=50 -- 2>&1)

# Full upload (no --validate-only) — verify the upload call has neither
# --validateBeforeUpload nor a prod confirmation prompt.
assert_audit_match "$env" "paportal upload (full)" "paportal upload --path . --modelVersion 2 "
case "$(audit_lines "$env/audit.log")" in
    *"--validateBeforeUpload"*)
        assert_fail "up.sh sent --validateBeforeUpload on full upload"
        ;;
    *)
        assert_pass "up.sh full upload omits --validateBeforeUpload"
        ;;
esac

# --- Section 6: up.sh prod gate (refuses without 'yes') --------------------

echo
echo "Section 6 — up.sh prod confirmation"
echo

env=$(make_template_env testprof "https://acme-prod.crm.dynamics.com/")
mkdir -p "$env/repo/site---site"
# Answer 'no' to the "Type 'yes'" prompt — script should abort, never call upload.
out=$(printf 'no\n' | run_template "$env" up.sh \
    SITE_DIR=site---site PROFILE=testprof -- 2>&1)
case "$out" in
    *"PRODUCTION ENVIRONMENT"*) assert_pass "up.sh shows prod warning" ;;
    *) assert_fail "up.sh didn't show prod warning" "out: $(printf '%s' "$out" | head -10)" ;;
esac
case "$out" in
    *"Aborted"*) assert_pass "up.sh aborts when prod confirm declined" ;;
    *) assert_fail "up.sh didn't abort on declined prod confirm" "out: $(printf '%s' "$out" | tail -5)" ;;
esac
case "$(audit_lines "$env/audit.log")" in
    *"paportal upload"*) assert_fail "up.sh ran upload despite declined prod confirm" ;;
    *) assert_pass "up.sh skipped upload on declined prod confirm" ;;
esac

# Now verify the inverse: typing 'yes' lets it through.
env=$(make_template_env testprof "https://acme-prod.crm.dynamics.com/")
mkdir -p "$env/repo/site---site"
out=$(printf 'yes\n' | run_template "$env" up.sh \
    SITE_DIR=site---site PROFILE=testprof -- 2>&1)
assert_audit_match "$env" "paportal upload after prod 'yes'" "paportal upload --path . --modelVersion 2 "

# --- Section 7: doctor.sh full pac path ------------------------------------

echo
echo "Section 7 — doctor.sh"
echo

env=$(make_template_env myprof)
mkdir -p "$env/repo/site---site/web-pages" "$env/repo/site---site/web-templates"
touch "$env/repo/site---site/website.yml"
out=$(run_template "$env" doctor.sh \
    SITE_DIR=site---site PROFILE=myprof -- 2>&1)

assert_audit_match "$env" "auth list" "auth list"
assert_audit_match "$env" "auth select --name myprof" "auth select --name myprof"
assert_audit_match "$env" "org who" "org who"

case "$out" in
    *"Power Pages Doctor"*) assert_pass "doctor.sh prints header" ;;
    *) assert_fail "doctor.sh missing header" "out: $(printf '%s' "$out" | head -5)" ;;
esac
case "$out" in
    *"Site folder site---site exists"*) assert_pass "doctor.sh detects site folder" ;;
    *) assert_fail "doctor.sh missing site folder check" ;;
esac
case "$out" in
    *"Site content counts"*) assert_pass "doctor.sh reaches counts section" ;;
    *) assert_fail "doctor.sh didn't reach counts" "out: $(printf '%s' "$out" | tail -10)" ;;
esac

# --- Section 8: doctor.sh placeholder guard -------------------------------

echo
echo "Section 8 — doctor.sh placeholder guard"
echo

env=$(make_template_env myprof)
out=$(run_template "$env" doctor.sh -- 2>&1; echo "RC=$?")
case "$out" in
    *"edit this script first"*"RC=2"*) assert_pass "doctor.sh refuses placeholders w/ exit 2" ;;
    *) assert_fail "doctor.sh placeholder guard broken" "out: $out" ;;
esac

# --- Section 9: solution-down.sh ------------------------------------------

echo
echo "Section 9 — solution-down.sh"
echo

env=$(make_template_env myprof)
out=$(printf 'y\n' | run_template "$env" solution-down.sh \
    SOLUTION=MySolution PROFILE=myprof SCHEMA_DIR=./dataverse-schema -- 2>&1; echo "RC=$?")

assert_audit_match "$env" "auth select --name myprof" "auth select --name myprof"
assert_audit_match "$env" "org who" "org who"
assert_audit_match "$env" "solution export --name MySolution" "solution export --name MySolution"
assert_audit_match "$env" "solution unpack" "solution unpack --zipfile"

# Regression: solution-down must reach Done even when grep "$SCHEMA_DIR"
# in the final status report finds no matches (clean re-export). Latent
# pipefail bug fixed in v2.11.2.
case "$out" in
    *"Done."*"RC=0"*) assert_pass "solution-down.sh reaches Done with RC=0" ;;
    *) assert_fail "solution-down.sh didn't reach Done with RC=0" "out: $(printf '%s' "$out" | tail -10)" ;;
esac

# Verify the atomic-swap end state: $SCHEMA_DIR/MySolution exists, no .new or .bak left over.
[ -d "$env/repo/dataverse-schema/MySolution" ] && assert_pass "solution-down.sh produced unpacked dir" \
    || assert_fail "solution-down.sh missing unpacked dir" \
        "tree: $(find "$env/repo/dataverse-schema" -maxdepth 2 2>/dev/null)"
[ ! -d "$env/repo/dataverse-schema/MySolution.new" ] && assert_pass "solution-down.sh cleaned up .new" \
    || assert_fail "solution-down.sh left .new dir behind"
[ ! -f "$env/repo/dataverse-schema/MySolution.zip" ] && assert_pass "solution-down.sh removed zipfile" \
    || assert_fail "solution-down.sh left zipfile behind"

# --- Section 9b: solution-down.sh on a tree where SCHEMA_DIR is committed -

echo
echo "Section 9b — solution-down.sh on clean SCHEMA_DIR (regression)"
echo

env=$(make_template_env myprof)
# First export, then commit the result. A second export with no real
# differences produces git status -s output that doesn't match SCHEMA_DIR
# at all → grep finds nothing → pipefail tripwire (fixed in v2.11.2).
out=$(printf 'y\n' | run_template "$env" solution-down.sh \
    SOLUTION=MySolution PROFILE=myprof SCHEMA_DIR=./dataverse-schema -- 2>&1)
( cd "$env/repo" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m baseline >/dev/null )

out=$(printf 'y\n' | run_template "$env" solution-down.sh \
    SOLUTION=MySolution PROFILE=myprof SCHEMA_DIR=./dataverse-schema -- 2>&1; echo "RC=$?")
case "$out" in
    *"Done."*"RC=0"*) assert_pass "solution-down.sh re-export on clean tree reaches Done" ;;
    *) assert_fail "solution-down.sh re-export aborts on clean tree" "out: $(printf '%s' "$out" | tail -10)" ;;
esac

# --- Section 10: solution-down.sh aborts on N -----------------------------

echo
echo "Section 10 — solution-down.sh aborts on N"
echo

env=$(make_template_env myprof)
out=$(printf 'n\n' | run_template "$env" solution-down.sh \
    SOLUTION=MySolution PROFILE=myprof -- 2>&1)
case "$out" in
    *"Aborted"*) assert_pass "solution-down.sh aborts on N" ;;
    *) assert_fail "solution-down.sh didn't abort on N" "out: $(printf '%s' "$out" | head -5)" ;;
esac
case "$(audit_lines "$env/audit.log")" in
    *"solution export"*) assert_fail "solution-down.sh ran export despite N" ;;
    *) assert_pass "solution-down.sh skipped export on N" ;;
esac

# --- Section 11: solution-down.sh placeholder guard -----------------------

echo
echo "Section 11 — solution-down.sh placeholder guard"
echo

env=$(make_template_env myprof)
out=$(run_template "$env" solution-down.sh -- 2>&1; echo "RC=$?")
case "$out" in
    *"pass solution name as arg"*"RC=2"*) assert_pass "solution-down.sh refuses placeholders" ;;
    *) assert_fail "solution-down.sh placeholder guard broken" "out: $out" ;;
esac

# --- Section 12: solution-up.sh non-prod path -----------------------------

echo
echo "Section 12 — solution-up.sh non-prod"
echo

env=$(make_template_env myprof)
# Pre-populate the unpacked solution dir
mkdir -p "$env/repo/dataverse-schema/MySolution/Other"
echo "<ImportExportXml/>" > "$env/repo/dataverse-schema/MySolution/Other/Solution.xml"
out=$(printf 'y\n' | run_template "$env" solution-up.sh \
    SOLUTION=MySolution PROFILE=myprof SCHEMA_DIR=./dataverse-schema -- 2>&1)

assert_audit_match "$env" "solution pack" "solution pack --folder ./dataverse-schema/MySolution"
assert_audit_match "$env" "solution import" "solution import --path ./dataverse-schema/MySolution.zip"

[ ! -f "$env/repo/dataverse-schema/MySolution.zip" ] && assert_pass "solution-up.sh cleaned up zipfile" \
    || assert_fail "solution-up.sh left zipfile behind"

# --- Section 13: solution-up.sh prod requires solution-name typed ---------

echo
echo "Section 13 — solution-up.sh prod confirmation"
echo

env=$(make_template_env myprof "https://acme-prod.crm.dynamics.com/")
mkdir -p "$env/repo/dataverse-schema/MySolution/Other"
echo "<ImportExportXml/>" > "$env/repo/dataverse-schema/MySolution/Other/Solution.xml"

# Wrong name typed → abort, no import
out=$(printf 'y\nNotMySolution\n' | run_template "$env" solution-up.sh \
    SOLUTION=MySolution PROFILE=myprof -- 2>&1)
case "$out" in
    *"Aborted"*) assert_pass "solution-up.sh aborts on wrong solution name" ;;
    *) assert_fail "solution-up.sh didn't abort on wrong name" "out: $(printf '%s' "$out" | tail -10)" ;;
esac
case "$(audit_lines "$env/audit.log")" in
    *"solution import"*) assert_fail "solution-up.sh ran import despite wrong prod-confirm name" ;;
    *) assert_pass "solution-up.sh skipped import on wrong prod-confirm name" ;;
esac

# Correct name → import proceeds
env=$(make_template_env myprof "https://acme-prod.crm.dynamics.com/")
mkdir -p "$env/repo/dataverse-schema/MySolution/Other"
echo "<ImportExportXml/>" > "$env/repo/dataverse-schema/MySolution/Other/Solution.xml"
out=$(printf 'y\nMySolution\n' | run_template "$env" solution-up.sh \
    SOLUTION=MySolution PROFILE=myprof -- 2>&1)
assert_audit_match "$env" "solution import after prod-confirm" "solution import --path"

# --- Section 14: solution-up.sh refuses missing UNPACK_DIR ----------------

echo
echo "Section 14 — solution-up.sh missing unpack dir"
echo

env=$(make_template_env myprof)
# No pre-population of dataverse-schema/MySolution
out=$(run_template "$env" solution-up.sh \
    SOLUTION=MySolution PROFILE=myprof -- 2>&1; echo "RC=$?")
case "$out" in
    *"does not exist"*"RC=1"*) assert_pass "solution-up.sh exits 1 if unpack dir missing" ;;
    *) assert_fail "solution-up.sh didn't refuse missing unpack dir" "out: $out" ;;
esac

# --- Section 15: commit.sh — nothing to commit ----------------------------

echo
echo "Section 15 — commit.sh nothing-to-commit"
echo

env=$(make_template_env myprof)
out=$(run_template "$env" commit.sh -- 2>&1)
case "$out" in
    *"Nothing to commit"*) assert_pass "commit.sh reports nothing to commit" ;;
    *) assert_fail "commit.sh missing nothing-to-commit message" "out: $(printf '%s' "$out" | head -5)" ;;
esac
# Audit log should be empty — commit.sh never invokes pac
[ ! -s "$env/audit.log" ] && assert_pass "commit.sh makes no pac calls" \
    || assert_fail "commit.sh invoked pac (it shouldn't)" "log: $(audit_lines "$env/audit.log")"

# --- Section 16: commit.sh — stage all + message arg ----------------------

echo
echo "Section 16 — commit.sh stage-all path"
echo

env=$(make_template_env myprof)
echo "new content" > "$env/repo/newfile.txt"
# Commit with message-as-arg (skips message prompt) and answer N to push.
out=$(printf 'a\nn\n' | run_template "$env" commit.sh -- "test commit" 2>&1)
case "$out" in
    *"## Staged changes"*|*"newfile.txt"*) assert_pass "commit.sh staged the new file" ;;
    *) assert_fail "commit.sh didn't stage" "out: $(printf '%s' "$out" | head -10)" ;;
esac
# Verify the commit landed
last_msg=$(cd "$env/repo" && git log -1 --format=%s 2>/dev/null)
case "$last_msg" in
    "test commit") assert_pass "commit.sh created commit with arg message" ;;
    *) assert_fail "commit.sh didn't commit correctly" "last_msg='$last_msg'" ;;
esac

# Audit log should still be empty
[ ! -s "$env/audit.log" ] && assert_pass "commit.sh stage path makes no pac calls" \
    || assert_fail "commit.sh hit pac" "log: $(audit_lines "$env/audit.log")"

# --- Section 17: commit.sh aborts on q ------------------------------------

echo
echo "Section 17 — commit.sh aborts on q"
echo

env=$(make_template_env myprof)
echo "more content" > "$env/repo/another.txt"
out=$(printf 'q\n' | run_template "$env" commit.sh -- 2>&1)
case "$out" in
    *"Aborted"*) assert_pass "commit.sh aborts on q" ;;
    *) assert_fail "commit.sh didn't abort on q" "out: $(printf '%s' "$out" | tail -5)" ;;
esac

# --- Summary -----------------------------------------------------------

echo
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
    printf '%d/%d passed\n' "$PASS" "$TOTAL"
    exit 0
else
    printf '%d/%d passed; failures: %s\n' "$PASS" "$TOTAL" "${FAIL_NAMES[*]}" >&2
    exit 1
fi
