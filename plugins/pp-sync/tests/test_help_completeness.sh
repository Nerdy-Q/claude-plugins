#!/usr/bin/env bash
# Help-text completeness test for `pp`.
#
# Every command keyword dispatched in bin/pp's case statement must appear in
# `pp help` output. This catches the "added a new command, forgot to update
# the help block" regression — common when a new subcommand is wired into
# the dispatch table but the help heredoc isn't touched in the same diff.
#
# Strategy: parse bin/pp for the dispatch case branches, separating top-level
# from inner (project/alias subcommand) blocks, then assert each keyword
# appears in `pp help` output. Aliases (alternates after `|`) are NOT
# required — they're shorthand and may be intentionally undocumented.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PP_BIN="$SCRIPT_DIR/../bin/pp"

[ -x "$PP_BIN" ] || { echo "cannot find pp at $PP_BIN" >&2; exit 1; }

PASS=0
FAIL=0
FAIL_NAMES=()

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

# Capture help output once. PP_CONFIG_DIR set so `pp help` doesn't probe a
# real ~/.config/nq-pp-sync/ that may or may not exist on the runner.
HELP_OUT=$(PP_CONFIG_DIR=$(mktemp -d) "$PP_BIN" help 2>&1)

[ -n "$HELP_OUT" ] || { echo "pp help produced no output" >&2; exit 1; }

# Parse the dispatch table by tracking case-block depth in awk. Top-level
# branches sit at depth 1 (inside `case "${1:-}"`); the inner project/alias
# sub-dispatchers create a depth 2 nest.
#
# Output format (TSV): <depth>\t<scope>\t<primary-keyword>
#   depth=1  scope=top      → top-level command
#   depth=2  scope=project  → `pp project <kw>` subcommand
#   depth=2  scope=alias    → `pp alias <kw>` subcommand
DISPATCH=$(awk '
    BEGIN { depth = 0; scope = "top" }
    /^[[:space:]]*case[[:space:]]/ {
        depth++
    }
    /^[[:space:]]*esac[[:space:]]*$/ {
        depth--
        if (depth <= 1) scope = "top"
        next
    }
    # Track scope on entering project) or alias) at depth 1
    depth == 1 && /^[[:space:]]+project\)/ { scope = "project_pending" }
    depth == 1 && /^[[:space:]]+alias\)/   { scope = "alias_pending" }
    depth == 2 && scope == "project_pending" { scope = "project" }
    depth == 2 && scope == "alias_pending"   { scope = "alias" }
    # Match dispatch entries: <kw>|alt) cmd_xxx "$@" ;;
    /^[[:space:]]+[a-z][a-z0-9|()-]*\)[[:space:]]+cmd_[a-z_]+[[:space:]]+"\$@"[[:space:]]+;;/ {
        match($0, /^[[:space:]]+[a-z0-9|-]+\)/);
        if (RLENGTH > 0) {
            kw = substr($0, RSTART, RLENGTH);
            gsub(/^[[:space:]]+|\)$/, "", kw);
            sub(/\|.*/, "", kw);  # take first alternative as primary
            if (depth == 1) {
                print "1\ttop\t" kw;
            } else if (depth == 2) {
                print "2\t" scope "\t" kw;
            }
        }
    }
' "$PP_BIN")

# --- Section 1: top-level commands ----------------------------------------

echo "Section 1 — top-level command help coverage"
echo

top_keywords=$(printf '%s\n' "$DISPATCH" | awk -F'\t' '$2 == "top" { print $3 }' | sort -u)

# Also include the noun-only top-level dispatchers (project, alias) — they
# don't dispatch directly but the keyword exists at depth 1.
for noun in project alias; do
    if grep -qE "^[[:space:]]+${noun}\)" "$PP_BIN"; then
        top_keywords=$(printf '%s\n%s\n' "$top_keywords" "$noun" | sort -u | sed '/^$/d')
    fi
done

for kw in $top_keywords; do
    # Help itself is the command producing the output — skip self-doc check
    if [ "$kw" = "help" ]; then continue; fi
    if printf '%s' "$HELP_OUT" | grep -qE "(^|[[:space:]])pp $kw([[:space:]]|\$)"; then
        assert_pass "$kw appears in pp help"
    else
        assert_fail "$kw missing from pp help" \
            "dispatched in bin/pp but not documented"
    fi
done

# --- Section 2: project subcommands ---------------------------------------

echo
echo "Section 2 — project sub-dispatcher coverage"
echo

project_subs=$(printf '%s\n' "$DISPATCH" | awk -F'\t' '$2 == "project" { print $3 }' | sort -u)

for sub in $project_subs; do
    if printf '%s' "$HELP_OUT" | grep -qE "pp project $sub([[:space:]]|\$)"; then
        assert_pass "project $sub appears in pp help"
    else
        # `list` is a documented alias for top-level `pp list`; relax
        # for that specific case
        if [ "$sub" = "list" ] && printf '%s' "$HELP_OUT" | grep -qE "pp list([[:space:]]|\$)"; then
            assert_pass "project list = pp list (top-level alias) — documented"
        else
            assert_fail "project $sub missing from pp help" \
                "dispatched but undocumented"
        fi
    fi
done

# --- Section 3: alias subcommands -----------------------------------------

echo
echo "Section 3 — alias sub-dispatcher coverage"
echo

alias_subs=$(printf '%s\n' "$DISPATCH" | awk -F'\t' '$2 == "alias" { print $3 }' | sort -u)

for sub in $alias_subs; do
    if printf '%s' "$HELP_OUT" | grep -qE "pp alias $sub([[:space:]]|\$)"; then
        assert_pass "alias $sub appears in pp help"
    else
        assert_fail "alias $sub missing from pp help"
    fi
done

# --- Section 4: every cmd_* function is dispatched ------------------------

echo
echo "Section 4 — every cmd_* function is reachable"
echo

# Defined functions: lines like `cmd_xyz()` at column 1
defined=$(grep -oE '^cmd_[a-z_]+' "$PP_BIN" | sed 's/^cmd_//' | sort -u)

# Dispatched functions: anywhere a `cmd_xyz "$@"` appears
dispatched=$(grep -oE 'cmd_[a-z_]+ "\$@"' "$PP_BIN" \
    | sed 's/^cmd_//; s/ "\$@"$//' | sort -u)

# Also include cmd_help — invoked from the top-level no-args branch via
# `cmd_help` directly without a case-clause.
if grep -qE '\bcmd_help\b' "$PP_BIN"; then
    dispatched=$(printf '%s\n%s\n' "$dispatched" "help" | sort -u | sed '/^$/d')
fi

for fn in $defined; do
    if printf '%s\n' "$dispatched" | grep -qx "$fn"; then
        assert_pass "cmd_$fn is reachable"
    else
        assert_fail "cmd_$fn defined but never dispatched (dead code?)"
    fi
done

# --- Summary --------------------------------------------------------------

echo
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
    printf '%d/%d passed\n' "$PASS" "$TOTAL"
    exit 0
else
    printf '%d/%d passed; failures: %s\n' "$PASS" "$TOTAL" "${FAIL_NAMES[*]}" >&2
    exit 1
fi
