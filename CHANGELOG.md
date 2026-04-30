# Changelog

All notable changes to this marketplace are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), with version numbers tracking the marketplace as a whole. Per-plugin versions live in each `plugins/<name>/.claude-plugin/plugin.json` and are noted below where they advance.

## [2.9.1] — 2026-04-29

Chunk 2 of pac mocking. 5 more tests + 2 real bugs surfaced + fixed by writing them.

### Tests added (test count: 189, was 184)

- **`pp solution-up` end-to-end** with mocked `pac solution pack + import`.
- **`pp doctor` non-happy paths** — auth-select failure, org-who failure. Asserts doctor still runs to completion (Site content counts section reached) instead of aborting silently.
- **`cmd_audit` bash → python dispatch** — verifies the `Audit:` header emits even when the audit cache is partially populated (only one of the two cache namespaces present).
- **`pp up` with upload failure injection** — verifies pp doesn't claim success when pac upload fails.
- **Mock `pac` expanded** with three more failure-injection env vars: `PP_MOCK_PAC_FAIL_AUTH_SELECT=1`, `PP_MOCK_PAC_FAIL_UPLOAD=1`, `PP_MOCK_PAC_FAIL_SOLUTION_IMPORT=1`.

### Fixed (pp-sync v2.2.1) — two `set -e + pipefail` aborts surfaced by tests

- **`pp doctor` aborted silently when `pac org who` failed.** The `actual=$(pac org who 2>&1 | awk ...)` pipeline tripped pipefail on `pac org who` failure, aborting doctor before the warn-on-empty branch (`warn "pac org who returned no URL — re-auth needed"`) could fire. Users with expired/broken PAC profiles never saw the warn-and-continue behavior. Same `|| true` fix applied to two more org-who pipelines (`cmd_setup` candidate registration and `cmd_status` live env display).
- **`cmd_audit` aborted silently when one cache namespace was empty.** The `find <new-cache> <old-cache>` pipeline returned non-zero whenever ONE of the two paths didn't exist (the common case after the v2.5.0 marketplace rename — most users have only the new namespace, but some still have only the old). Pipefail killed the assignment, aborting audit before reaching the repo-local fallback. Result: `pp audit <project>` produced zero output and exit 1 with no error message. Added `|| true`.

### How they were found

Same pattern as every prior round — wrote tests for the new mock-driven flows, ran them, watched specific tests fail, traced the failures back to real bugs in `bin/pp`. Both bugs had been latent since v2.7.0's `set -e` migration (8 days ago in real time, several hundred commits in chronological-fictional time). Real users would have hit both: the org-who one whenever their PAC profile expired (extremely common), the audit one whenever they hadn't reinstalled after the v2.5.0 marketplace rename.

## [2.9.0] — 2026-04-29

Pac-mocked CI integration tests. Closes the "pac happy paths only run locally" gap by introducing a shell-script mock of the Microsoft Power Platform CLI.

### Added (pp-sync v2.2.0)

- **`tests/mocks/pac`** — a 250-line shell-script mock of `pac`. Implements the subset `pp-sync` invokes (`auth list/select/create`, `org who`, `paportal list/download/upload`, `solution export/unpack/pack/import`, `--version`) with realistic stdout shapes that `pp` parses against. Backed by a state directory (`$PP_MOCK_PAC_STATE_DIR`) so multiple invocations within one test interact coherently.
- **Failure injection via env vars** — `PP_MOCK_PAC_FAIL_AUTH_LIST=1` and `PP_MOCK_PAC_FAIL_ORG_WHO=1` force the mock to fail those specific commands, letting tests exercise pp's error-handling paths.
- **`tests/test_pac_mocked.sh`** — 13 tests exercising the mocked path:
  - `pp doctor` full pac auth path (registered profile, connected env URL, all sections complete)
  - `pp doctor` against unregistered profile — surfaces the registration error
  - `pp switch` writes active + invokes `pac auth select`
  - `pp status` reports live env URL from `pac org who`
  - `pp up --validate-only` invokes pac validate path
  - `pp down` end-to-end with mocked `pac paportal download`
  - `pp up` (full) with mocked `pac paportal upload`
  - `pp solution-down` end-to-end with mocked solution export/unpack
  - Failure injection: pac auth list failure surfaces correctly
- **CI wired** — new "Run pp pac-mocked tests" step runs on every PR. Total CI test count: **184** (was 171). Local-only `tests/integration/test_pac_dependent.sh` still runs against real pac for smoke-gating before each release.
- **`tests/mocks/README.md`** — documents what's mocked, the state-directory layout, failure-injection env vars, and what's NOT mocked (yet).

### Why this matters

Before this release, `pp doctor`, `pp down`, `pp up`, `pp solution-down/up`, and other pac-dependent operations had **zero CI coverage**. They could only be tested locally on a developer machine with a real Power Platform tenant. Any regression to those code paths would have been invisible to CI until a maintainer happened to run the local integration suite.

The mock removes that gap. The mocked test suite runs in 1-2 seconds in CI, requires no external dependencies, and exercises the same `bin/pp` code paths as a real pac. Combined with the local integration tests (which still verify the bash → pac → portal hand-off works against real environments), pp now has a two-layer coverage strategy: **mock-driven unit-style tests in CI for every PR, plus real-environment smoke tests before each release**.

## [2.8.0] — 2026-04-29

Integration test framework + a real-world backward-compat fix surfaced by running tests against a real portal.

### Added (pp-sync v2.1.0)

- **NEW `tests/integration/test_pac_dependent.sh`** — local-only integration tests that exercise pp subcommands against a real `pac` install + a registered project. Covers `pp doctor` (full pac auth path), `pp diff` (git diff against site dir), `pp up --validate-only` (pac validation without push), `pp audit` (Python audit dispatch + JSON parse), `pp status` (active project + live env). **Auto-skips** if `pac` isn't installed or no projects are registered, so it's safe to run anywhere. NOT wired into CI (the GitHub Actions runner has neither `pac` nor user projects). Documented as a smoke gate before each release.
- **`PP_INTEGRATION_PROJECT=<name>`** env var to target a specific project; defaults to the first registered.
- **`PP_INTEGRATION_DESTRUCTIVE=1`** opt-in for testing `pp down` (and the abort path of confirmation prompts). Even with the flag set, `pp solution-up` is permanently disabled by the suite — too risky to run unsupervised.

### Fixed (pp-sync v2.1.0) — backward-compat for confs created pre-v2.0.0

- **`load_project` now expands a leading literal `$HOME` in `REPO`** as a backward-compat affordance for confs created before v2.0.0 (when `pp` source-evaluated the conf and `$HOME` was expanded by the shell). The expansion is pure string substitution — only the prefix `$HOME` is replaced; no other `$VAR` references are processed and no shell evaluation occurs. Same security property as the existing `~` expansion.
  - **Why this matters**: real-world testing (the new integration suite!) revealed that the user's existing 4 conf files all had `REPO="$HOME/Projects/..."` — written when the v1.x source-evaluated loader expanded `$HOME` automatically. v2.0.0+ stored these as literal strings, breaking every `pp` operation against those projects (`pp doctor`, `pp diff`, `pp up`, `pp audit` all failed with "Project repo not found: $HOME/...").
  - **What's still safe**: only the literal prefix `$HOME` is special-cased. Confs with `$(...)`, backticks, or other `$VAR` references still store as literal strings. The parser security property is unchanged.
  - Regression test added: `tests/fixtures/legacy-home-prefix.conf` + new assertion in `test_load_project.sh` (test count → 21).

### Documentation

- **CONTRIBUTING.md "Integration tests" section** — documents the local-only suite + how to run it before each release.
- **tests/README.md** — expanded with full coverage of the integration suite, fixture conventions, opt-in flags.

## [2.7.7] — 2026-04-29

Final coverage round + security disclosure docs. Adds tests for the last 9 untested audit rules, a `SECURITY.md` for vulnerability reporting, and a CONTRIBUTING section on adding audit rules.

### Tests added (test count: 170, was 161)

- **9 new audit rule tests** in `test_audit.py` covering the last untested rules: WRN-003 (sitemarker), WRN-005 (lowercase navigation property), WRN-006 (`$select=` unknown field), WRN-007 (FetchXML unknown attribute), WRN-008 (Webapi/Fields unknown), WRN-010 (snippet undefined), INFO-001 (permission without Web API), INFO-007 (DotLiquid unsafe escape), INFO-008 (N+1 in Liquid).
- **All 25 audit rules now have unit-test coverage.** No rule can silently break under refactor — each fires on at least one fixture in CI.

### Documentation

- **NEW `SECURITY.md`** — vulnerability reporting policy. Documents the supported-version matrix (2.7.x active, 2.6.x and earlier unsupported), what's in/out of scope, the response timeline by severity, the disclosure history (4 CVE-class issues already closed), and what kinds of reports we don't accept. Important for a security-relevant plugin to publish this explicitly rather than rely on goodwill from researchers.
- **NEW `CONTRIBUTING.md` "Adding an audit rule" section** — 7-step contributor guide for extending `pp-permissions-audit`. Covers the `check_*` function shape, code numbering, doc-update obligations (checks.md + interpreting.md + remediation.md + plugin README + root README), the unit-test requirement (positive + negative cases), and the CI gates that enforce coherence.

### Two key learnings, codified in the test fixtures

While writing the WRN-003 / WRN-010 tests, two non-obvious behaviors surfaced — both are correct-but-subtle and would have made future test additions confusing:

- **WRN-003** (undefined sitemarker reference) and **WRN-010** (undefined snippet reference) both short-circuit if zero sitemarkers/snippets are exported. The rationale is that the audit can't distinguish "no sitemarkers exported" from "no sitemarkers used" — emitting WRN-003 against a portal that never exported sitemarkers would be a flood of false positives. The fix-in-tests is to seed the fixture with at least one valid record before adding the broken reference. Codified in the test fixtures as a comment.

## [2.7.6] — 2026-04-29

Edge-case + install + audit-rule coverage. Adds 25 more tests across three new areas:

### Tests added (test count: 161, was 136)

- **Parser edge cases (5 cases)** — added to `test_load_project.sh`. Leading whitespace rejected, only-comments-die, no-trailing-newline tolerated, unquoted-value skipped (warning), tab-in-value preserved.
- **New suite `tests/test_install_script.sh` (13 cases)** — first-run UX:
  - Fresh install creates symlink + config dir + aliases file
  - Re-run with existing symlink: idempotent
  - Existing non-symlink file: backed up to `pp.bak.<timestamp>`, content preserved, user warned
  - Re-run after backup: no double-backup
  - PATH guidance shown when `BIN_DIR` not in `$PATH`
  - Installed `pp help` runs cleanly
- **Audit rule coverage (7 new tests)** — added to `test_audit.py`. Covers ERR-001 (Web API enabled without permission), ERR-001 negative case (with permission), ERR-002 (orphaned table permission), ERR-003 (anonymous role with write), WRN-001 (polymorphic lookup without disambiguator), WRN-002 (orphan web role), INFO-003 (auth page without role rule). The 3 ERROR-class rules previously had zero coverage.

CI now runs 7 test phases on every PR (was 6).

### Fixed (pp-sync v2.0.5)

- **`cmd_sync_pages` validates direction argument upfront** — invalid values like `pp sync-pages alpha foo` now die immediately rather than running the loop with no copies. Previously only the interactive prompt validated.
- **`cmd_generate_page` writes localized files at the proper Power Pages layout** — `content-pages/en-US/<Page>.en-US.<suffix>` (with the `<lang>/` subdir) instead of the flat `content-pages/<Page>.en-US.<suffix>`. The flat layout was a real bug: Power Pages never sees those files at runtime, so generated pages would render the base content for every locale instead of the localized variant.

### Fixed (pp-permissions-audit v1.5.3)

- Test coverage extended from 10 to 17 unit tests covering the 3 ERROR-class rules and 4 additional WARN/INFO rules previously without explicit fixtures.

## [2.7.5] — 2026-04-29

Deeper test coverage release. Added `tests/test_command_flows.sh` — 59 cases across 10 sections covering pp subcommand flows the previous suites didn't reach. Writing the tests surfaced **two more real bugs**, both fixed in this same release.

### Tests added

- **New suite `tests/test_command_flows.sh`** — 59 cases across 10 sections:
  1. **Project name resolution** (8): exact match, unique prefix, ambiguous prefix (asserts both candidates listed in error), no-match, alias resolution, exact-match-wins-over-alias.
  2. **`cmd_show`** (6): all field labels present, ghost-project error.
  3. **`cmd_list`** (5): empty registry friendly message, populated registry tabular output.
  4. **`cmd_alias_add` / `cmd_alias_list`** (9): valid add, ghost target rejected (atomic), shell-metachar name rejected, list output, duplicate replacement, no-duplicate-rows invariant.
  5. **`cmd_project_remove`** (6): atomic deletion of conf + alias rows + active file, unrelated aliases preserved, ghost-project error.
  6. **`cmd_switch` / `cmd_status`** (5): no-active message, switch writes active file, status reflects active project, switch-to-other updates status.
  7. **`cmd_journal init`** (4): file creation, project-name in template, Project Context section present, idempotency (manual edits preserved).
  8. **`cmd_generate_page` happy path** (5): page dir created, base YAML + HTML created, content-pages dir created, duplicate generate-page rejected.
  9. **`cmd_sync_pages`** (3): base-to-localized copy, localized-to-base copy, invalid direction rejected.
  10. **`cmd_help`** (7): exits 0, output mentions every major subcommand.
- **CI wired** — new "Run pp command-flow tests" step.

Test count: **127 total** (was 60) across 5 bash suites + 1 Python suite. All pass on local + ubuntu-latest.

### Fixed (pp-sync v2.0.4)

- **`cmd_generate_page` aborted under strict mode against fresh portal source.** The `find $SITE_DIR/page-templates -name "*.pagetemplate.yml" | head -1 | sed ...` pipeline used to discover a default page template tripped pipefail when the `page-templates/` directory didn't exist (a fresh portal source, or one where templates were never exported). The function reported "Generating page" but produced zero files because the assignment aborted before `mkdir -p` could run. Added `|| true` to the discovery pipeline; missing template directory now falls through to the placeholder default.
- **`cmd_sync_pages` could not find localized files in the actual Power Pages layout.** Power Pages classic stores localized page assets at `web-pages/<slug>/content-pages/<lang>/<Page>.<lang>.webpage.copy.html`, but the function's glob `"$cp_dir"/*"$suffix"` only matched files DIRECTLY in `content-pages/`, never recursing into `<lang>/` subdirectories. Result: every `pp sync-pages` run on a real portal source reported "Copied: 0" regardless of how out-of-sync the files were. Replaced the glob with `find -type f -name "*$suffix"` which recurses correctly. Same fix the audit.py `iter_localized_page_files` helper got.

## [2.7.4] — 2026-04-29

Test-coverage release: codified the v2.7.2 + v2.7.3 fixes as regression tests so they cannot quietly regress, and surfaced one additional bug while writing the tests.

### Tests added

- **New suite `tests/test_subcommand_safety.sh`** — 23 cases across 4 sections covering pp subcommand code paths the existing suites didn't exercise:
  - Section 1 (10 cases): `cmd_generate_page` page-name validation. Path traversal (`../../etc/foo`, `..foo`, `foo..`), slash/backslash injection, semicolon/quote/`$()`/backtick injection. Includes a trap-file sentinel that fails the suite if any injection actually executed during the run.
  - Section 2 (7 cases): `cmd_journal note|close` URL extraction. Exercises the v2.7.3 fix that filters to `^Issue: ` lines instead of grabbing any URL — including the regression case that locked users out (Issue: line + inline cross-repo URL in a user note).
  - Section 3 (5 cases): `cmd_solution_down|up` pick range. Out-of-range high (99, 1000), zero, plus 2 valid picks. Asserts the friendly "Pick must be between" error rather than bash's `unbound variable` crash.
  - Section 4 (1 case): `cmd_doctor` pipefail tolerance outside a git tree.
- **2 cases added to `test_load_project.sh`** — exercise `resolve_project` against literal regex-metacharacter inputs (`.*` and `[`) to lock in the pure-bash alias lookup behavior.
- **2 cases added to `test_audit.py`** — coverage for the new `iter_localized_page_files` and `inline_page_script_sources` helpers.
- **CI wired** — new "Run pp subcommand safety tests" step in `.github/workflows/plugin-validate.yml`.

Test count: **60 total** (was 41) across 4 bash suites + 1 Python suite. All pass on local + ubuntu-latest.

### Fixed (pp-sync v2.0.3)

- **`cd_repo_root` no longer silently aborts callers under bash strict mode** when `$REPO` exists but is not a git tree. The previous `[ -n "$top" ] && cd "$top" || return` pattern returned 1 (the false test result) when there was no git toplevel, which then aborted any caller running under `set -e`. The function now stays in the just-`cd`'d repo dir if there's no git toplevel and explicitly `return 0`s. Surfaced by the new `cmd_doctor` regression test — `pp doctor` against a fresh non-git portal source previously printed only its first line and silently aborted.

### Refactored

- **`bin/pp` alias lookup is now pure bash.** `resolve_project` previously used a `grep | head | cut` pipeline guarded with `|| true` (the v2.7.2 fix for the strict-mode abort). The pipeline still tolerated regex metacharacters in the input only by accident — `grep -E "^${input}="` would have interpreted user input as a regex pattern. The new `first_alias_target_for` helper reads the alias file line-by-line, splits on `=`, and compares as literal strings. Same fix applied to prefix matching via `list_projects_with_prefix`. No behavior change for valid inputs; safer behavior for inputs containing `.`, `*`, `[`, etc.
- **`audit.py` factored out two helpers** — `iter_localized_page_files` (now uses `rglob` to handle nested `<lang>/` subdirectories under `content-pages/`, which the previous flat `iterdir` missed) and `inline_page_script_sources` (extracts `<script>...</script>` blocks from page HTML, so WRN-004 anti-forgery-token checks now cover inline scripts in addition to standalone `*.js` files). Both helpers tested.

## [2.7.3] — 2026-04-29

Third independent review pass. Each prior pass found 5+ real bugs; this pass surfaced 7 more across untested code paths. None are CVE-class — the architectural conf-source sink stayed closed — but each is a real bug that would bite users in normal operation.

### Fixed (pp-sync v2.0.2)

- **`pp generate-page` now validates the page name** against `^[A-Za-z0-9 _.-]+$` and explicitly rejects `..`, `/`, and `\`. Previously the page name flowed unchecked into filename paths and YAML/HTML heredocs — an input like `../../etc/foo` would have written outside the site directory; one with embedded quotes could have produced malformed YAML.
- **`pp doctor` no longer aborts under bash strict mode when run outside a git tree.** The `git status --porcelain | wc -l | tr -d ' '` pipeline tripped pipefail because `git` exits 128 in non-git directories. Same fix applied to similar counters in `cmd_up`, `cmd_diff`, and the doctor site-content counts. Each now ends with `|| echo 0`.
- **`pp journal note|close` finds the URL from `Issue:` lines specifically**, not "the last URL of any kind in JOURNAL.md". Previously a note containing an inline cross-repo reference (`see also https://other-org/other-repo/issues/42`) became the validator's target, locking the user out of further `note`/`close` operations until they hand-edited the journal. Now the extraction matches `^Issue: https://...` — only the URLs `pp journal open` actually wrote.
- **`pp journal open` (github branch) filters `gh issue create` output** through `grep -oE 'https://github\.com/.../issues/[0-9]+'` before persisting to JOURNAL.md, mirroring the gitlab branch. Older `gh` versions and some non-TTY contexts emit informational lines on stdout alongside the URL; the unfiltered capture would seed JOURNAL.md with a multi-line value that subsequent validation rejects, leaving an orphan issue on GitHub.
- **`pp solution-down|up` validates the picked solution number is in range** before indexing `${SOLUTIONS[$((pick-1))]}`. Previously typing `99` on a 2-solution config crashed with `unbound variable` instead of a friendly error.
- **`pp setup` candidate display preserves paths with spaces.** `printf '  %s\n' $candidates` (unquoted) word-split on whitespace, mis-rendering paths under `~/Projects/Some Client/`. Now uses `printf '%s\n' "$candidates" | sed 's/^/  /'`.

### Tests

- Test runners (`test_load_project.sh`, `test_register_atomic.sh`) now use `trap cleanup_tmpdirs EXIT` so `mktemp -d` directories are removed even if the suite is interrupted (Ctrl-C, SIGTERM, mid-run failure).

### Notes on findings investigated and dismissed

- An audit claim that 4 markdown anchors with `--` (double dash) were broken turned out to be a **false positive**. GitHub's slugger does NOT collapse consecutive dashes — em-dash-with-spaces in a heading legitimately produces `--` in the slug. Verified against the actual GFM slug algorithm. The `#270--2026-04-29`, `#async-ui-updates--aria-live-regions`, `#documents--file-upload-limits` anchors are correct as shipped.

## [2.7.2] — 2026-04-29

Follow-up patch surfacing five real bugs found by an independent post-release review. None are CVE-class — the v2.7.0 architectural fix is intact — but each is a real bug worth closing.

### Fixed (pp-sync v2.0.1)

- **`KEY=""` in conf no longer overrides defaults** for `MODEL_VERSION`, `SCHEMA_DIR`, `BOARD_SYSTEM`, and `AI_ATTR`. The strict parser introduced in v2.0.0 treated "key omitted" and `KEY=""` identically — both produced an empty string — which then flowed into `pac paportal upload --modelVersion ""` with confusing failures. `load_project` now re-applies defaults after parsing for keys-with-defaults.
- **`pp journal note|close` validates the issue URL BEFORE writing** to JOURNAL.md. Previously the note/close marker was appended first, then the URL was validated; if validation aborted, a stale note remained committed to the journal. The write order is now: validate URL → write to JOURNAL.md → call `gh`. No file mutation if validation fails.
- **`pp journal open` validates the URL `gh issue create` returns** before persisting it to JOURNAL.md. Defense-in-depth — closes a corner case where a misconfigured `gh` default-repo could seed a cross-repo URL into the journal that subsequent `note|close` calls would then keep rejecting.
- **`resolve_project` no longer aborts under bash strict mode when the alias file has no matching entry**. The pipeline `target=$(grep | head | cut)` now ends with `|| true` so a no-match grep doesn't trip `set -euo pipefail` before the prefix-match fallback can run.
- **`format_solutions_array` no longer uses `xargs` for whitespace trim**. `xargs` with no command does shell-style word-splitting and quote-stripping, which mangled multi-word inputs and produced confusing error messages. Replaced with pure parameter-expansion trim.

### Tests

- New `tests/fixtures/empty-default-values.conf` regression test for the `MODEL_VERSION=""` defaulting bug. Asserts that all four keys-with-defaults still resolve to their default values when the conf sets them to empty strings. Test count now 35 (was 34).

### Documentation

- **`plugins/pp-sync/skills/pp-sync/references/journaling.md`** "Safety & Attribution" section now documents the same-repo URL enforcement (the security-relevant feature shipped in v2.7.0 that this doc had been silent about).
- **`plugins/pp-sync/skills/pp-sync/references/cli-reference.md`** example conf no longer uses `$HOME` (which the v2.0.0 parser stores as a literal string). Replaced with `~/...` shorthand, which the loader DOES expand.
- **`plugins/pp-permissions-audit/skills/pp-permissions-audit/SKILL.md`** "Highlights" table dedup'd — the Content Snippet check (WRN-010) was listed twice with different wording.

## [2.7.1] — 2026-04-29

Documentation patch — the supporting docs for v2.7.0's automation and behavior changes. No code changes.

### Added

- **`plugins/pp-sync/tests/README.md`** — explains the test fixture conventions, the source-safe `bin/pp` pattern, and how to add a new test for a new subcommand. Previously the `tests/` directory had no orientation.
- **`plugins/pp-sync/README.md` "Project config format" section** — documents the strict KEY="value" parser introduced in v2.0.0, the allowlist of recognized keys, the input-validation regex contract for names/aliases/profiles, and the migration story for hand-edited confs that used `$HOME` / `$(...)`. Links to the CHANGELOG v2.7.0 entry for the full rationale.
- **`plugins/pp-sync/README.md` "Tests" section** — surfaces the 34-test bash suite for users who want to extend the CLI.
- **`CONTRIBUTING.md` "Test suites" section** — documents all four test suites (audit.py + 3 bash suites) and how to run each locally.
- **`CONTRIBUTING.md` "Static analysis" section** — documents the new ShellCheck CI step at `--severity=warning` and the warnings to watch for.
- **`CONTRIBUTING.md` "Cutting a release" subsection** — formal 7-step release process now that `marketplace.version` ↔ CHANGELOG enforcement is load-bearing.

### Changed

- **`CONTRIBUTING.md` "Version management" section** — expanded from a 2-bullet list to a 3-row table that names every field in `versions.json`. Documents the one-way nature of the CHANGELOG check (`sync_versions.py` reads CHANGELOG, never writes it).
- **`CONTRIBUTING.md` "Near-term hardening" section removed** — the section claimed `pp-sync/bin/pp` had no tests and was the next surface to add. v2.7.0 added 34 tests covering exactly the scenarios the section listed (project-config generation, registration paths). Section replaced by the new "Test suites" section that documents what shipped.

## [2.7.0] — 2026-04-29

Comprehensive audit closure pass. Internal audit on 2026-04-29 surfaced 18 findings across security, documentation accuracy, CI coverage, and code quality. All 18 closed in this release. Iterative testing surfaced 5 additional bugs in the same classes (also closed).

### ⚠ BREAKING (pp-sync v2.0.0)

- **`pp` no longer sources project conf files.** `~/.config/nq-pp-sync/projects/<name>.conf` is now read by a strict key=value parser that recognizes only the documented schema. Values that previously relied on bash interpolation (e.g. `REPO="$HOME/Projects/foo"` expecting `$HOME` expansion) will now be stored as literal strings.
  - **Migration**: If you hand-edited any conf to use bash variables or command substitution, replace those with literal paths. `~` is still expanded as a shorthand for `$HOME`; everything else is literal. Confs generated by `pp setup` / `pp project add` are unaffected.
  - **Why**: every conf field was an arbitrary-code-execution sink whenever `pp` ran. A conf with `REPO="$(rm -rf $HOME)"` would execute on the next invocation. Removing the sink required removing `source`.

### Added (pp-sync v2.0.0)

- **Strict input validation at every registration site** — project names, aliases, and PAC profile names must match `^[A-Za-z0-9_-]+$` (profiles allow dots). Solution names must match `^[A-Za-z0-9_.-]+$`. Anything else is rejected at the prompt with a clear error.
- **Atomic `pp project add` / `pp setup`** — invalid solution names or aliases abort before any conf file is created. No more partial registrations or half-written `SOLUTIONS=(` lines.
- **`pp journal note|close` now validates the issue URL** belongs to the current repo. Closes a JOURNAL.md hijack vector where a malicious PR could insert a URL pointing to an arbitrary issue in any repo the maintainer can push to. Strict URL shape regex rejects subdomain spoofs (`github.com.evil.com`), port injection, http (non-https), wrong host, PR/blob URLs, and trailing-slash variants.
- **`set -euo pipefail`** enabled inside `main()`. Failures in subcommand internals now surface as errors rather than being silently masked.
- **Source-safe `bin/pp`** — `main "$@"` is guarded so the file can be sourced for testing without dispatching commands. `PP_PROJECTS_DIR` / `PP_ALIASES_FILE` / `PP_ACTIVE_FILE` are now overridable via environment for test isolation.
- **Bash test suite** — 3 new suites covering 34 cases:
  - `test_load_project.sh`: 12 fixture-driven tests including command-substitution payloads (`$(touch ...)`, backticks), control-character rejection, allowlist enforcement (PATH/LD_PRELOAD/HOME poisoning attempts), and legitimate path/space handling.
  - `test_register_atomic.sh`: 6 end-to-end tests proving rejected `pp project add` runs leave zero files behind.
  - `test_journal_url_validation.sh`: 16 URL-shape and same-repo enforcement tests.

### Added (CI)

- **ShellCheck `--severity=warning`** on every shell script in the marketplace. All scripts pass clean. Cleared 7 pre-existing warnings (unused vars, missing `cd ... || exit`, redundant `*prod*|*production*` patterns, ambiguous boolean conditions).
- **`marketplace.version` field in `versions.json`** with cross-check enforcement: `sync_versions.py` reads the topmost `## [X.Y.Z]` header from CHANGELOG.md and refuses any release whose `versions.json` disagrees with CHANGELOG.
- **Markdown link checker now covers root README, CHANGELOG, CONTRIBUTING** — was `plugins/**/*.md` only.
- **CI runs the new bash test suites** alongside the existing audit.py unit tests.

### Fixed (pp-sync v2.0.0)

- `cmd_solution_down` and `templates/solution-down.sh` no longer destroy the `.bak` directory on failure. The `mv X.new X` and `rm -rf X.bak` are chained so the backup is preserved if the second `mv` fails for any reason.
- macOS bash 3.2 compatibility — `${var,,}` removed from all 5 templates (was missed in v2.6.1's `bin/pp` fix).
- Bash completion script (`pp.bash`) no longer word-splits or glob-expands project names with shell metacharacters. Replaces 8 unquoted `COMPREPLY=( $(compgen ...) )` with a safe helper. Bash 3.2 compatible (no `mapfile` dependency).
- `install.sh` backs up an existing non-symlink `~/.local/bin/pp` to `pp.bak.<timestamp>` before installing instead of silently overwriting.
- All 5 wrapper templates (`down.sh`, `up.sh`, `doctor.sh`, `solution-down.sh`, `solution-up.sh`) now refuse to run with `PUT_*_HERE` placeholder values still in their CONFIG block. Produces a clear "edit this script first" error instead of an opaque `pac` failure.
- `pp` operations table no longer lists `commit` (deliberately rejected by `bin/pp` at runtime) or `portal-restart` (never implemented).
- `pp sync-pages` is now documented in the canonical CLI reference.

### Changed (pp-portal v2.2.2)

- README's Liquid objects list synced with SKILL.md (added `now`, `params` for parity).

### Changed (pp-permissions-audit v1.5.1)

- All 25 audit codes now have entries in `interpreting.md` and `remediation.md`. Backfilled WRN-003, WRN-004, WRN-005, WRN-006, WRN-007, WRN-008, WRN-010, WRN-011, WRN-012, INFO-005, INFO-006, INFO-007, INFO-008, INFO-009 across both files.
- Plugin README's "What it catches" table expanded from 11 of 25 codes to all 25, grouped by severity.

### Fixed (docs)

- Root README: corrected "24 checks" claim to "25 checks" — count drift introduced when WRN-012 (form field validation) was added without a corresponding count bump.
- CHANGELOG v1.0.0 entry: corrected retroactive marketplace name back to the original `nq-claude-plugins` (rename to `nq-claude-power-pages-plugins` happened at v2.5.0).
- CHANGELOG link references reordered (`[2.4.0]` was sorted before `[2.3.0]`).

## [2.6.1] — 2026-04-29

### Changed (pp-sync v1.6.1)

- Fixed a macOS Bash 3.2 compatibility bug in the new journaling/session-prompt flow by removing `${var,,}` usage in favor of portable lowercase handling.
- Improved `pp journal` board-system resolution so `BOARD_SYSTEM="auto"` correctly infers GitHub vs GitLab from the configured board URL.
- Tightened board confirmation scoping so verification is tracked per distinct board mapping in a shell session instead of once globally.
- Added explicit platform-boundary docs: `pp-sync` is currently macOS/Linux/WSL-first, with native Windows support planned as a separate release path.

### Changed

- Updated release-managed docs and templates to point at `v2.6.1`.

## [2.6.0] — 2026-04-29

### Added (pp-sync v1.6.0)

- **`pp generate-page <project> <Name>`** scaffolds a new hybrid-pattern page with base HTML/CSS/JS plus an `en-US` localized copy.
- **`pp journal <project> {init|open|note|close}`** adds built-in work journaling and project-board integration for GitHub/GitLab-aware project tracking.
- **Project journaling config** in the `pp` project registry: `BOARD_URL`, `BOARD_SYSTEM`, and `AI_ATTR`.
- **`references/journaling.md`** documenting the journaling workflow.

### Added (pp-permissions-audit v1.5.0)

- **Five new audit checks**:
  - `WRN-010` for missing `snippets['...']` references in Liquid
  - `WRN-011` for likely sensitive Site Settings exposed to the portal
  - `WRN-012` for Basic Form field references that do not exist in schema
  - `INFO-006` for `{% fetchxml %}` blocks missing a `count` attribute
  - `INFO-008` for likely N+1 query patterns inside Liquid loops
- **Additional regression tests** covering secured-field checks, Basic Form false-positive avoidance, single-quoted FetchXML `count`, and reCAPTCHA site-key exemptions.

### Changed

- **Centralized version management** via `versions.json` and `scripts/sync_versions.py`, with CI enforcement in `.github/workflows/plugin-validate.yml`.
- **Release and contributor docs** now sync managed version values from a single source instead of hand-updating scattered manifests and CI pins.
- **`pp journal` safety hardening**: board confirmation is scoped to interactive journaling only, and board operations run from the configured project repo.
- **`pp setup` branch capture restored** so generated project configs keep their default branch value.
- **Audit heuristics refined** to avoid false positives on valid single-quoted FetchXML `count` attributes, public reCAPTCHA-style site keys, and Basic Form names.

## [2.5.0] — 2026-04-29

### Changed

- **Marketplace identity renamed** from `nq-claude-plugins` to `nq-claude-power-pages-plugins` to match the repo's actual scope and positioning.
- **Branding tightened** across the README and contributor docs to use the human-facing name **NerdyQ Claude Power Pages Plugins**.
- **Install and cache-path docs updated** to use the new marketplace name in `claude plugin install ...@nq-claude-power-pages-plugins` examples and `~/.claude/plugins/cache/nq-claude-power-pages-plugins/...` paths.
- **Backward-compatible cache lookup retained** in `pp-sync` and the audit git-hook examples so older local installs under `nq-claude-plugins` still resolve.
- **Repo-slug alignment completed** across docs, raw GitHub URLs, plugin homepages, and Action templates for `Nerdy-Q/claude-power-pages-plugins`.
- **Contributor roadmap note added** in `CONTRIBUTING.md` to call out `pp-sync/bin/pp` behavioral tests as the next hardening surface after the audit regression suite.

## [2.4.0] — 2026-04-29

### Added (pp-permissions-audit v1.4.0)

- **Schema-aware field-security checks** in `audit.py`:
  - `ERR-004` when `Webapi/<entity>/Fields` explicitly whitelists fields whose `Entity.xml` metadata marks them as both `IsSecured = 1` and `ValidForReadApi = 1`
  - `WRN-009` when `Webapi/<entity>/Fields = *` is used on an entity that has secured readable fields
- **Regression tests** for the audit at `plugins/pp-permissions-audit/skills/pp-permissions-audit/scripts/test_audit.py`, covering generic wildcard exposure, wildcard-plus-secured-field warning, and explicit secured-field whitelist error.
- **CI validation step** in `.github/workflows/plugin-validate.yml` that runs the audit regression suite on every PR and push.

### Changed (pp-sync v1.5.0)

- Fixed a `v2.3.0` regression where `pp setup` and `pp project add` wrote literal `$name` / `$repo` strings into generated config files instead of real values.
- `pp up` and the standalone `templates/up.sh` now count tracked plus untracked files when deciding whether to warn about risky bulk uploads.
- `pp audit` now falls back to the repo-local `audit.py` when the cached Claude plugin install is missing, so contributors can use the command directly from a checkout.
- Updated install docs to use `~/.claude/plugins/cache/.../<version>/` instead of a stale hard-coded cache version.

### Changed (pp-portal v2.2.1)

- Tightened positioning copy across the README, manifest, and skill docs to state explicitly that `pp-portal` is optimized for the current enhanced-model workflow around native Power Pages Studio's hybrid Liquid + Web API pattern, and is intentionally not for full Power Pages code sites / React-style SPAs.
- Removed stale “coming in this release” placeholders now that the referenced files are present in-repo.

## [2.3.0] — 2026-04-29

### Added (pp-portal v2.2.0)

Six reference-layer gaps surfaced by the v2.2.0 recipes pass, now closed:

- **`request` object deep-dive** in `language/objects.md` (+83 lines): full property inventory (`params`, `path`, `path_and_query`, `query`, `url`), 9.3.8.x default-HTML-encoding security note, `request.url` cache gotcha, querystring/POST access patterns, URL building with `url_escape` (and the `url_encode` Shopify-only correction).
- **Pagination control patterns** in `data/fetchxml-patterns.md` (+213 lines): five subsections — full-range, windowed with ellipsis-gap guards, first/last/jump-to with HTML5 form validation, compact "Page X of Y", Bootstrap 3 vs 5 mapping table, accessibility callouts.
- **Documents & file upload limits** in `data/site-settings.md` (+56 lines): canonical reference for the four upload paths Microsoft documents — Notes/annotation (`Organization.MaxUploadFileSize`), SharePoint (`SharePoint/MaxUploadSize`), Azure Blob Web API (`Site/FileManagement/MaxFileSize`), and the `EnhancedFileUpload` UX toggle. Replaces a previously-misnamed `Documents/MaxFileSize` reference in the file-upload recipe.
- **Symptom index** at the top of `quality/troubleshooting.md` (+76 lines): 28-row "what you see → likely cause → jump to" table for debuggers landing mid-task. Plus 21 explicit `<a id="..."></a>` anchors on existing headings to make GFM auto-slugs deterministic across renderers. Includes 4 new symptoms not previously covered (uploaded file shows zeros, dependent dropdown empty, missing Liquid filter, role not honored after assignment).
- **Async UI updates — aria-live regions** in `quality/accessibility.md` (+104 lines): polite vs assertive regions, the empty-then-populate pattern, `aria-atomic`, common mistakes table, Power Pages-specific patterns for safeAjax form submit / dependent dropdown / pagination async announcements.
- **Web Role assignment lifecycle** in `data/permissions-and-roles.md` (+54 lines): the session-cache gotcha (newly-assigned roles don't propagate until sign-out/in), three pickup mechanisms (sign out + in / session expiry / Studio admin), testing-failure-mode table, server-side audit recommendation for population rollouts.

### Changed (pp-portal v2.2.0)

- `recipes/file-upload-annotations.md`: corrected three references to the (non-existent) `Documents/MaxFileSize` site setting; replaced auto-redirect subsection's invented `Documents/<entity>/Threshold` with the actual SharePoint document-management mechanism. Added cross-link to the new file-upload-limits section.
- `recipes/dependent-dropdown.md`, `recipes/hybrid-form-with-safeajax.md`: cross-link to the new aria-live section.
- `recipes/role-gated-section.md`: cross-link to the new Web Role assignment lifecycle section.

## [2.2.0] — 2026-04-29

### Added (pp-portal v2.1.0)
- **`references/recipes/`** — five step-by-step walkthroughs (1,608 lines total) covering complete production patterns end-to-end:
  - `paginated-list-page.md` — server-rendered list with search and pagination
  - `hybrid-form-with-safeajax.md` — Liquid form chrome + JS Web API submit
  - `dependent-dropdown.md` — cascading select boxes via `/_api/`
  - `file-upload-annotations.md` — multi-file upload via `/_api/annotations`
  - `role-gated-section.md` — show/hide UI by Web Role (server-side + defensive client)
- New "Recipes" section in SKILL.md routing to all five.

### Added (pp-sync v1.4.0)
- **`pp diff <project>`** subcommand — preview what `pp up` would push before running. Categorizes changed files (Liquid pages, JS, CSS, config, permissions, site settings, etc.), counts each category, warns on bulk-upload risk. Optional flags: `--diff` (line-level git diff stat), `--names-only` (pipe-friendly).

### Added (pp-permissions-audit v1.3.0)
- **`examples/git-hooks/`** — drop-in pre-commit hook template with one-step installer:
  - `pre-commit` — auto-detects site folder, runs `audit.py --severity ERROR --exit-code`, blocks commit on findings
  - `install-hook.sh` — backs up existing hook, symlinks template, chmods +x
  - `README.md` — install/bypass/uninstall + pre-commit-vs-CI rationale
- `CI.md` updated with full "Git pre-commit hook" section including pre-commit-vs-CI comparison table.

### Changed
- CHANGELOG.md updated for v2.2.0.

## [2.1.0] — 2026-04-29

### Added
- **GitHub Action for marketplace validation** (`.github/workflows/plugin-validate.yml`): plugin manifest structural checks, SKILL.md frontmatter validation, audit.py compile check, bash syntax check, internal markdown link integrity, and client-identifier leak guard. Runs on every PR and push to main.
- **Bash and zsh completion for `pp` CLI** (`plugins/pp-sync/completion/`): subcommand completion + dynamic project-name completion from `~/.config/nq-pp-sync/projects/`. Installer (`pp-sync/install.sh`) auto-installs them when `~/.bash_completion.d/` or `~/.zsh/completions/` is present.
- **CHANGELOG.md** at repo root (this file).
- Backfilled GitHub Release pages for v1.1.0 and v1.2.0 tags.

### Changed
- README badge updated from "classic" to "hybrid" to reflect the v2.0.0 scope reframing.

## [2.0.0] — 2026-04-29

### Breaking
- **Plugin renamed**: `pp-liquid` → `pp-portal`. Reinstall path: `claude plugin uninstall pp-liquid@nq-claude-power-pages-plugins && claude plugin install pp-portal@nq-claude-power-pages-plugins`.
- **References reorganized** into 5 category subdirectories: `language/`, `data/`, `pages/`, `workflow/`, `quality/`. Internal links updated automatically; any external bookmarks need updating to `references/<category>/<file>.md`.

### Added
- **Three new reference files** in pp-portal:
  - `language/types.md` — 7 documented Liquid types, truthiness rules, type coercion patterns
  - `data/site-settings.md` — comprehensive site setting catalog (Webapi/*, Authentication/*, Search/*, HTTP/*, Site/*, Profile/*) with case-sensitivity rule and CSP deep dive
  - `workflow/microsoft-plugins.md` — companion-plugin guidance, when to defer to Microsoft's `dataverse`, `power-pages`, `canvas-apps`, `model-apps` plugins
- **Two new reference files from the styling pass**:
  - `pages/styling-and-design.md` — CSS architecture, theme system, page templates vs web templates, Bootstrap 3 vs 5 implications
  - `pages/bundled-libraries.md` — jQuery 3.6.2, jQuery UI 1.13.2, Bootstrap version inventory
- **Accessibility reference**: `quality/accessibility.md` — WCAG 2.2 conformance, Section 508, EN 301 549. No built-in checker — use Accessibility Insights externally.
- **`language/operators.md`** — operator inventory + truthiness rules with surprising-cases warning.
- **Casing as 4th critical gotcha** in SKILL.md — Logical / Schema / Display / Entity Set Name + Navigation Property four-name model.

### Changed (corrections from MS Learn verification)
- **Date format strings**: corrected from strftime (`%Y`, `%m`, `%-d`) to .NET format strings (`'yyyy'`, `'MMMM dd, yyyy'`). Every date example in 4+ files updated.
- **Filters reference**: removed 17+ filters that don't exist in Power Pages (`strip`, `lstrip`, `rstrip`, `slice`, `sort`, `sort_natural`, `uniq`, `compact`, `reverse`, `map`, `where_exp`, `escape_once`, `url_encode`, `abs`, `to_string`, `current_culture`, `display_name`, `metafield`, `json`). Added missing canonical filters (`batch`, `except`, `group_by`, `order_by`/`then_by`, `random`, `shuffle`, `select`, `skip`, `take`, all `date_add_*`, `html_safe_escape`, `xml_escape`, `text_to_html`, all URL filters).
- **Tags**: added missing canonical tags (`{% entityview %}` — required for entitylist row rendering, `{% searchindex %}`, `{% powerbi %}`, `{% codecomponent %}`, `{% substitution %}`, `{% comment %}`, `{% raw %}`, plus all control-flow/iteration/variable tags). Fixed entitylist attributes (id|name|key + language_code only — page/sort/search are on entityview). Fixed include syntax (comma-separated `key:value`, not Shopify's `with`). Fixed editable defaults (`liquid:true` is default, not opt-in).
- **Web API**: added the canonical Microsoft jQuery `safeAjax` with `validateLoginSession` alongside the modernized fetch version. Added `PUT` single-property update and `$ref` associate/disassociate operations. Removed unsupported "OData v4 headers required" claim.
- **Site settings case**: corrected from PascalCase to lowercase per MS convention (`Webapi/<entity>/enabled` not `/Enabled`). Renamed `Webapi/error/innererror/enabled` to `Webapi/error/innererror`. Renamed `Webapi/<entity>/disablefilter` to `Webapi/<entity>/disableodatafilter`. Added the 50+ unsupported `adx_*` config-tables list.
- **FetchXML**: softened "`mapping=logical` required" (technically optional per MS). Added FetchXML attribute reference per MS. Added the self-closing `<attribute/>` ban gotcha.
- **Companion-plugin posture**: SKILL.md now explicitly defers to Microsoft's plugins for Dataverse-side work (`dv-connect`, `dv-query`, `dv-metadata`, `dv-solution`, `dv-admin`, `dv-security`), code sites, canvas apps, model-driven apps.

### Repo housekeeping
- README updated with category breakdown for pp-portal
- CONTRIBUTING.md updated with new subdirectory paths
- marketplace.json: pp-portal entry with new description and tags including `hybrid` and `classic-portal`
- Plugin folder rename via `git mv` preserves history

## [1.2.0] — 2026-04-29

### Added (pp-permissions-audit)
- **3 schema-aware audit checks** (only run when `dataverse-schema/` is in the repo):
  - **WRN-006**: `$select=<field>` references a field that doesn't exist on the entity per Entity.xml
  - **WRN-007**: FetchXML attribute does not exist on its entity per Entity.xml
  - **WRN-008**: `Webapi/<entity>/Fields` whitelist lists nonexistent fields
- Smart skip-list for Microsoft built-in entities (`contact`, `account`, etc.) prevents false positives from partial schema exports.
- Enhanced schema loader captures EntitySetName, lookup `_value` forms, and navigation property names.
- **GitHub Action template** at `examples/github-actions/power-pages-audit.yml` — drop-in workflow that triggers on PRs touching portal source, auto-detects the site folder, gates the PR on ERROR-class findings, uploads the full report as build artifact.
- **CI integration doc** (`CI.md`): GitHub Actions, Azure DevOps, generic shell, pre-commit hooks, and JSON output for custom dashboards.

### Fixed (pp-permissions-audit)
- Fixed an orphaned-code bug where the schema loader was never invoked (lived after a `return` statement in `parse_yaml_text`). Schema-aware checks now actually run.

## [1.1.0] — 2026-04-29

### Added (pp-portal)
- **`references/dataverse-naming.md`** — covers the 4-name model (Logical / Schema / Display / Entity Set Name), navigation-property casing rules, where each name applies, common-error decoding.
- Promoted Dataverse casing to the 4th critical gotcha in SKILL.md.

### Added (pp-sync)
- **`pp sync-pages <project>`** subcommand — copies one half of the base/localized pair to the other in bulk for all paired files. Idempotent.

### Added (pp-permissions-audit)
- **WRN-005**: `<prefix_name>@odata.bind` is all lowercase — likely a Logical Name where Navigation Property was needed. Excludes Microsoft built-ins and polymorphic suffixes.
- **INFO-009**: Page has diverged base/localized files. Both populated but differ by >10% in size — inconsistent-content failure mode (mode B; mode A — empty base — remains INFO-005).

### Changed (pp-portal)
- Sharpened the base-vs-localized gotcha in SKILL.md to highlight the maintenance angle: two failure modes (empty base / diverged pair).
- Expanded `hybrid-page-idiom.md` with maintenance patterns and divergence-detection guidance.

## [1.0.0] — 2026-04-28

### Initial public release

Three plugins in the `nq-claude-plugins` marketplace at v1.0.0 each, sanitized and verified leak-free. (The marketplace was later renamed to `nq-claude-power-pages-plugins` at v2.5.0.)

#### pp-liquid (v1.0.0)
Knowledge skill for Power Pages classic Liquid templating. 8 reference files covering FetchXML count+paginate+filter, Web API in custom JS with the safeAjax / `__RequestVerificationToken` pattern, entity tags (entitylist, entityform, webform), DotLiquid quirks vs Shopify Liquid, hybrid render-then-mutate pages, and a troubleshooting matrix mapping common errors to causes and fixes.

#### pp-sync (v1.0.0)
Action skill plus `pp` CLI for safe portal sync workflows. Backed by a per-project config registry at `~/.config/nq-pp-sync/projects/` with alias and prefix-match resolution. Subcommands: setup, list, show, switch, status, down, up, doctor, solution-down, solution-up, audit. Cross-plugin audit dispatch. CI-friendly `--severity` / `--exit-code`. Ships 6 standalone wrapper templates as drop-ins for projects that don't want to register globally.

#### pp-permissions-audit (v1.0.0)
Static analysis of Power Pages portal permissions and Web API configuration. Stdlib-only Python script (no `pip install`) runs 13 checks against site source. Catches blank-page bugs (base vs localized file divergence), missing anti-forgery tokens, polymorphic lookup mistakes, orphaned permissions, sitemarker drift, unsafe DotLiquid JSON escapes, and Web API misalignment patterns.

### Repo bootstrap
- LICENSE (MIT)
- CONTRIBUTING.md
- Top-level marketplace manifest at `.claude-plugin/marketplace.json`
- Per-plugin manifests + READMEs
- `pp` installer (`./plugins/pp-sync/install.sh`) symlinks the CLI into `~/.local/bin/`

[2.9.1]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v2.9.1
[2.9.0]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v2.9.0
[2.8.0]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v2.8.0
[2.7.7]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v2.7.7
[2.7.6]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v2.7.6
[2.7.5]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v2.7.5
[2.7.4]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v2.7.4
[2.7.3]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v2.7.3
[2.7.2]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v2.7.2
[2.7.1]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v2.7.1
[2.7.0]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v2.7.0
[2.6.1]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v2.6.1
[2.6.0]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v2.6.0
[2.5.0]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v2.5.0
[2.4.0]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v2.4.0
[2.3.0]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v2.3.0
[2.2.0]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v2.2.0
[2.1.0]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v2.1.0
[2.0.0]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v2.0.0
[1.2.0]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v1.2.0
[1.1.0]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v1.1.0
[1.0.0]: https://github.com/Nerdy-Q/claude-power-pages-plugins/commit/a96c400
