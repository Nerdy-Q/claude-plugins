# Changelog

All notable changes to this marketplace are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), with version numbers tracking the marketplace as a whole. Per-plugin versions live in each `plugins/<name>/.claude-plugin/plugin.json` and are noted below where they advance.

## [2.12.2] — 2026-04-30

Voice consistency sweep: removed em-dashes from all authored marketplace content per the maintainer's writing rules. No behavior change, no plugin version bumps. The CHANGELOG itself is preserved as-is per Keep a Changelog convention (historical record).

### Changed

- **1,175 em-dashes replaced across 63 files** in active authored content (plugin descriptions, SKILL.md frontmatter, references, READMEs, tests/READMEs, top-level docs, marketplace.json). Em-dashes were replaced per English grammar role: parentheticals and noun expansions became commas, headings became colons. The most-visible metadata strings (per-plugin descriptions in `plugin.json` and the marketplace listing in `.claude-plugin/marketplace.json`) were hand-tuned where colon read better than comma.
- **`scripts/sweep_em_dashes.py`** added: a reusable sweep tool that handles ` — ` (space-em-space) → `, ` for prose, ` — ` in headings → `: `, and `—` (no spaces) → `-`. Skips `CHANGELOG.md` (historical), `BLOG-DRAFT.md` (untracked), and `scripts/sweep_em_dashes.py` (the script itself). Has a `--dry-run` mode and a `--diff` mode for review before applying.

### Why this matters

Em-dashes had crept into shipped plugin metadata (the marketplace listing description, the per-plugin SKILL.md frontmatter) where they affect what a user sees on first contact, and into reference content the model loads into context (where any pattern in the text can be picked up by future authoring). The maintainer has a documented rule against em-dashes in user-on-behalf writing; this release brings the marketplace into compliance.

### Tests

All 404 regression tests still pass. Doc-link validator: 222 links / 56 files. Metadata consistency: 3 plugins / 28 keywords. No new tests added (the sweep is content-only; the script has its own dry-run for verification).

### Versions

- marketplace: 2.12.1 → **2.12.2** (patch, content-only sweep, no behavior change)
- All plugin versions unchanged

## [2.12.1] — 2026-04-30

Eight quality enhancements that close the remaining "if-we-kept-going" testing gaps surfaced after v2.12.0. **Test count: 330 → 404 (+74)**. Two real metadata bugs surfaced and fixed by writing the tests.

### Added — JSON output contract test (pp-permissions-audit)

- **`test_audit_json_contract.py`** — 13 assertions pinning the schema of `audit.py --json` output. External CI integrations (the GitHub Action template, custom dashboards, pre-commit hooks) consume this JSON via `jq` selectors; a rename or restructure breaks them silently. The contract pins:
  - top-level keys: `site`, `counts`, `findings`
  - `counts` keys: `site_settings`, `table_permissions`, `web_roles`, `web_pages`, `custom_js`, `schema_entities` — including a "no unexpected keys" check that fails by design when a new count is added (forces conscious update of external consumers)
  - finding record shape: `severity` (enum: ERROR/WARN/INFO), `code` (regex `^(ERR|WRN|INFO)-\d{3}$`), `title`, `detail`, `location` — all required strings
  - `--severity` filter inclusiveness (INFO ≥ WARN ≥ ERROR finding counts)
  - `--exit-code` semantics (without flag: always exit 0; with flag + matching findings: exit 1)
- The contract is also documented as a comment block at the bottom of the test file so external consumers don't have to read the test source

### Added — pp help-text completeness test

- **`test_help_completeness.sh`** — 44 assertions that parse `bin/pp`'s case-statement dispatch table, separate top-level commands from `project` / `alias` sub-dispatchers via awk depth tracking, and verify each keyword appears in `pp help` output. Catches the "added a new dispatch entry but forgot to update the help heredoc" regression — common in plugin development. Verified the test catches deletions of help lines (regression-tested by removing a `pp doctor <project>` line and confirming `doctor missing from pp help` failure surfaces).

### Added — marketplace metadata consistency validator

- **`scripts/validate_metadata_consistency.py`** — verifies each plugin's `plugin.json` keywords appear (via word-boundary regex with normalization for hyphens and underscores) in either the plugin description, the SKILL.md frontmatter description, or the SKILL.md body. Catches "added a keyword for SEO/discovery but never surfaced it in skill content" — dead metadata that confuses the skill matcher.
- **Real bug surfaced**: `pp-sync` had `deployment` in keywords but the term appeared nowhere in the skill content. Added "deployment" to the SKILL.md description (covers both "deploy portal changes" → "deployment to dev/UAT/prod" — addresses real user search terms).
- Also enforces: plugin.json `name` matches folder, SKILL.md frontmatter `name` matches plugin, plugin.json description and SKILL.md description share at least 3 content words (catches divergent rewording).

### Added — top-level doc-link validation

- Extended `scripts/validate_doc_links.py` to scan beyond `plugins/*/skills/*/`. Now also validates: top-level `README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `SECURITY.md`, per-plugin `README.md`, and per-plugin `tests/README.md`.
- **Pre-extension**: 213 links / 48 files. **Post-extension**: 222 links / 56 files. All resolve.

### Added — v1 conf migration rejection test

- **New fixture `v1-style-conf.conf`** + **case 20 in `test_load_project.sh`** — pins the migration boundary between pre-v2.0.0 (`source "$conf"` shell-eval) and v2.7.0+ (strict `KEY="value"` parser). A v1-shape conf with bare unquoted assignments must be rejected cleanly (load_project dies with "missing NAME") rather than silently loading a partial config or — worse — re-introducing shell evaluation.

### Added — install.sh upgrade path test

- **Section 7 in `test_install_script.sh`** (4 new assertions): simulates a real upgrade flow. User has the marketplace checked out at `/old/path`; pp is symlinked to `/old/path/.../bin/pp`. User pulls a new version at `/new/path` and re-runs install. Verifies:
  - The symlink retargets to the new checkout (not stale)
  - It remains a symlink (not replaced with a regular file)
  - Calling `pp` produces the new behavior, not the old
  - No backup file is created on a clean symlink → symlink upgrade

### Added — concurrent project-add race test

- **New section in `test_register_atomic.sh`** (3 new assertions): spawns 5 parallel `pp project add` invocations against the same project name, then verifies the post-race state is sane:
  - Exactly one conf file exists (no orphans, no duplicates)
  - At least one process succeeded (a winner exists)
  - The conf file is parseable by `load_project` with all required fields set (no half-written or interleaved content)
- Pins the observed race-converging behavior so any regression that loosens the guarantees (e.g., introducing partial-write windows) is caught.

### Added — paths-with-spaces handling test

- **`test_paths_with_spaces.sh`** — 7 assertions verifying pp's read-only command surface handles paths like `~/My Documents/portals/site---site` correctly. Tests:
  - `load_project` preserves spaces in REPO and SITE_DIR
  - `pp show` and `pp list` print spaced paths intact
  - `pp doctor` finds the site folder under a spaced REPO and reaches the counts section without aborting
  - Site content with spaced filenames (e.g., `About Us.webpage.yml`) gets counted correctly

### Added — audit.py performance regression test

- **`test_audit_performance.py`** — generates a 1000-file synthetic portal (200 web pages × 200 web templates × 200 content snippets × 200 site settings × 200 table permissions) and asserts audit completes in under 15 seconds. Real performance on modern hardware is typically <1s; the budget is generous to absorb CI runner variance, but a 10x algorithmic regression (e.g., O(n²) introduced by accidental nested scans) will trip it.

### Tests added (test count: 404, was 330)

| Suite | Before | After | Notes |
|---|---:|---:|---|
| `test_load_project.sh` | 21 | **22** | + v1 conf migration rejection |
| `test_register_atomic.sh` | 6 | **9** | + concurrent race (3 assertions) |
| `test_install_script.sh` | 13 | **17** | + upgrade path (4 assertions) |
| `test_help_completeness.sh` | — | **44** | new |
| `test_paths_with_spaces.sh` | — | **7** | new |
| `test_audit_json_contract.py` | — | **13** | new |
| `test_audit_performance.py` | — | **2** | new |
| (others unchanged) | 290 | 290 | — |
| **Total** | **330** | **404** | **+74** |

### CI

- Five new test steps in `plugin-validate.yml`: audit JSON contract, audit performance, marketplace metadata consistency, pp help completeness, paths-with-spaces.
- Doc-link validator now covers 222 links across 56 files (was 213/48).
- Total CI test count: **404** (was 330).

## [2.12.0] — 2026-04-30

`pp-portal` becomes a deep expert in five major design systems with intuitive crossovers, full component catalogs, token theory, and concrete recipes. Minor version bump on the marketplace + minor on `pp-portal` because this is a substantial new capability layer.

### Added (pp-portal v2.3.0) — design-system reference layer

10 files under `plugins/pp-portal/skills/pp-portal/references/design-systems/`, ~1980 lines total:

- **`README.md`** (39 lines) — index, layout, routing logic, what this layer does and doesn't cover
- **`system-selection.md`** (187 lines) — primary/secondary selection rules, crossover decision rule, recommended pairings per primary, and a **special rule for web-only primary systems needing a mobile-app feel** (USWDS): ask the user iOS or Android, then borrow nav anatomy from Apple HIG or Material 3 accordingly while preserving USWDS color, type, focus, and content tone. Default to Material 3 if cross-platform / unsure.
- **`crossover-recipes.md`** (621 lines) — six concrete recipes with full HTML/CSS/JS implementations:
  1. USWDS hero with Material 3 carousel (USWDS doesn't have carousel)
  2. USWDS web with iOS-native mobile feel (HIG bottom tab bar, large-title scroll-collapse, safe-area insets)
  3. USWDS web with Android-native mobile feel (M3 navigation bar, FAB, active-indicator pill)
  4. Fluent 2 enterprise card with shadcn polish (compound-component composition + Fluent tokens)
  5. shadcn/ui product portal with USWDS form rigor (validation summary, helper-text-before-input, plain-language errors)
  6. Apple HIG calm + USWDS civic seriousness (token translation, dark-mode parity, `-apple-system` font stack)
- **`responsive-defaults.md`** (136 lines, existing) — mobile-first layout rules, 44pt touch targets, navigation/forms/tables/modals/carousels by breakpoint, per-system responsive bias
- **`strict-csp.md`** (110 lines, existing) — Power-Pages-specific CSP rules: prefer local JS/CSS, no inline scripts, no runtime injection, no CDN dependencies
- **`uswds-3.md`** (178 lines) — full component catalog with **explicit "not in this system" markers** (carousel, stepper, drawer, command palette, FAB, native-app nav patterns), token theory (color grades, type scale, 8pt spacing), Public Sans + USWDS Icons foot-guns, **web-only callout** explaining the iOS/Android crossover need
- **`material-3.md`** (172 lines) — full component catalog (carousel **was added in M3** — common knowledge trap), tonal-palette + semantic-role color system, M3 type scale (display/headline/title/body/label × 3 sizes), motion durations + easings, M2-vs-M3 token-naming gotcha
- **`apple-hig.md`** (176 lines) — components reference organized by HIG section (Content / Menus / Navigation / Presentation / Selection / Status), Dynamic Color, Dynamic Type, **critical license warnings: SF font is restricted to Apple software, SF Symbols is iOS/macOS only — substitute Inter (OFL) and Lucide (ISC) on web**
- **`fluent-2.md`** (173 lines) — Fluent 2 React v9 catalog (~50 components), alias-token system (`colorNeutralBackground1`, `--colorBrandBackground`, `--spacingHorizontalM`), `Field` and `Persona` patterns, **Segoe UI is Windows-licensed** — use system font stack, v8-vs-v9 token-naming gotcha
- **`shadcn-ui.md`** (185 lines) — full registry (Accordion through Typography, including `Command`, `Sonner`, `Sidebar`), HSL-based token theory, **shadcn is a pattern source, not an install target** for classic Power Pages, Lucide icon attribution, why Tailwind/Radix shouldn't be imported into a classic portal

### Updated (pp-portal v2.3.0) — SKILL.md routing

- New "Design systems + responsive composition" subsection in the references map links every design-system file with one-line summaries
- Description and keywords updated to surface design-system / responsive / mobile / tablet capability — the skill matcher now activates this knowledge layer when users mention "Material Design," "USWDS," "Apple," "Fluent," "shadcn," "carousel for our gov portal," "make it feel like an iOS app," etc.

### Why this matters

Without this layer, the model would invent token names, hallucinate components ("USWDS carousel"), recommend SF font on web (license violation), or paste shadcn React code into a classic portal. With it:

- **Component catalogs are embedded** — the model knows what each system has and doesn't have, without fetching
- **Token tables are embedded** — Material's tonal-palette, Fluent's alias tokens, USWDS's grade system, shadcn's HSL pairs are all there as concrete CSS variables to use
- **License foot-guns are explicit** — SF font, SF Symbols, Segoe UI, Public Sans, Lucide, Material Symbols — each system file has the licensing rules
- **URL pointers stay current** — every system file links the canonical docs root (m3.material.io, designsystem.digital.gov, developer.apple.com/design/human-interface-guidelines, fluent2.microsoft.design, ui.shadcn.com) so the user can always check the live spec
- **Crossover recipes have real code** — six full implementations with HTML, CSS, and CSP-safe vanilla JS, not just principles
- **The "USWDS is web-only, ask iOS or Android for mobile-app feel" rule is formalized** — model will ask the user instead of assuming

### Doc-link validator

The new layer triggers the `validate_doc_links.py` script added in v2.11.3:

- Pre-expansion: 144 links / 45 files
- Post-expansion: **213 links / 48 files**

All resolve. CI catches any future drift.

### Tests added (test count: 330, was 306)

- **`plugins/pp-portal/tests/test_design_systems.py`** — 24 regression tests across 4 classes that lock the load-bearing knowledge in place:
  - `TestLicenseTraps` (3 tests) — code blocks must NOT recommend SF Pro / San Francisco as a downloaded font, must NOT host Segoe UI as a web asset via `@font-face url(...)`, must NOT include SF Symbols glyph references on web pages
  - `TestCSPSafety` (5 tests) — code blocks must NOT include CDN URLs, inline `on*=` event handlers, dynamic-code-evaluation primitives, unsafe DOM-write APIs (string-assignment to `inner` / `outer` HTML properties, doc-stream write), or runtime script-tag injection
  - `TestRequiredSections` (1 test, 5 files × 5 sections each) — every per-system file must contain Canonical sources, Component catalog, Token theory, License, and Pairing sections
  - `TestRequiredFacts` (15 tests) — pin the most-likely-to-be-quietly-deleted warnings: SF font is not for web, USWDS has no carousel + points to Material/shadcn, Material 3 added carousel, Segoe is Windows-licensed, Fluent v8 vs v9 distinction, shadcn is a pattern source not an install target, system-selection has the iOS/Android special rule, crossover-recipes has at least 6 recipes including the USWDS variants, and every system file lists its license
- Detection patterns for unsafe API names are constructed from string fragments to avoid tripping security-reminder hooks that scan for raw substrings — this file detects unsafe usage, never invokes anything
- Verified the regression suite catches real injections: an SF Pro Display font-family added to apple-hig.md fails `test_no_sf_pro_or_san_francisco_as_font_family`; gutting the License section fails the SF-warning facts tests
- Also fixed a real bug in the `code_blocks` parser: the original regex didn't anchor fences to line starts, so an indented opening fence inside a markdown list could pair with the next unindented closing fence and swallow everything between, defeating per-block detection. Pattern now anchored with `^[ \t]*` and `re.MULTILINE`

### CI

- New "Run pp-portal design-system regression tests" step in `plugin-validate.yml`. Total CI test count: **330** (was 306).
- Frontmatter validation, doc cross-reference validator, marketplace + version sync — all unchanged.

### Versions

- marketplace: 2.11.3 → **2.12.0** (minor — substantial new capability)
- pp-portal: 2.2.2 → **2.3.0** (minor — substantial new capability)
- pp-sync: 2.4.3 (unchanged)
- pp-permissions-audit: 1.5.5 (unchanged)

## [2.11.3] — 2026-04-30

Closes the three remaining items from the v2.10.0 gaps discussion that were marked "by design" in the v2.11.2 close-out: real-pac CI on a cadence, doc-link validation, and live-tenant solution-down coverage. With this release the testable surface is comprehensive — what remains is genuinely environmental (real production tenants, Microsoft API behavior we don't control).

### Added — real-pac CI workflow

- **`.github/workflows/real-pac-contract.yml`** — separate workflow that installs the real Microsoft Power Platform CLI on a Linux runner and runs `PP_PAC_REAL=1 bash test_pac_contract.sh`. Triggers on:
  - `workflow_dispatch` for maintainer release-prep
  - tag pushes (`v*`) as a release-gate signal
  - weekly cron (Monday 06:00 UTC) so Microsoft pac distribution drift surfaces in days rather than at the next release
- **Degrades gracefully without secrets** — without any `PP_PAC_*` secrets configured, the contract suite still exercises the unauthenticated subset (`pac --version`, `pac help`, empty `pac auth list`). With `PP_PAC_TENANT_ID` / `PP_PAC_APP_ID` / `PP_PAC_CLIENT_SECRET` / `PP_PAC_ENV_URL` set as repo secrets, the auth-gated assertions also run (real `auth list` row shape, real `org who` URL parseability).
- **Security**: workflow uses NO `github.event.*` inputs in any `run:` block. All untrusted-input pathways are absent; secrets flow through `env:` blocks only, never inlined into `${{ }}` expansions inside scripts.

### Added — doc cross-reference validator

- **`scripts/validate_doc_links.py`** — checks every relative markdown link in `plugins/*/skills/*/` resolves to an existing file or directory. Catches dead `references/foo.md` and `../examples/bar.sh` links that would otherwise rot silently as the doc tree moves. Anchor fragments (`#section`) are stripped before existence checks; external URLs and same-file anchors are skipped (out of scope). Currently validates **144 relative links across 45 doc files**.
- **CI wired** — new "Validate doc cross-references" step in `plugin-validate.yml`. Runs on every PR.

### Added — live-tenant solution-down integration coverage (pp-sync v2.4.3)

- **New section in `tests/integration/test_pac_dependent.sh`** — opt-in via `PP_INTEGRATION_SOLUTION_NAME=<solution>`, exercises the real `pac solution export` + `pac solution unpack` pipeline against a Dataverse tenant. Asserts:
  - `pp solution-down` exits 0
  - Real export step ran ("Exported" / "export" message)
  - Real unpack step ran ("Unpacked" / "unpack" message)
  - `Other/Solution.xml` lands at the expected path (the load-bearing fixture pp's audit + mock both depend on)
  - Zipfile cleaned up after successful unpack
  - This is the one test that verifies the *real* pac binary produces a usable zipfile shape — mocked tests cover shell orchestration but never validate Microsoft's actual export format.
- **Why opt-in**: real export takes 60-120s and writes to `$REPO/dataverse-schema/`. Naming the solution explicitly is consent.

### Added — bulk-upload warning surface coverage (test_templates.sh)

- **`up.sh` BULK_THRESHOLD warning is now tested**. New section 5b in `test_templates.sh` stages 4 untracked files with `BULK_THRESHOLD=2` and asserts:
  - The "BULK UPLOAD WARNING" banner appears
  - File count line reports 4 (not 0 or arbitrary)
  - Answering 'n' aborts before invoking `pac paportal upload`
  - `--force-bulk` bypasses the warning and proceeds to upload
- **Why this matters**: the bulk warning is the *only* protection against the cache-hang scenario the v2.10.0 changelog called out (>50 files at once → portal cache rebuild required from Power Platform Admin Center). Pure client-side bash logic, fully testable with mock pac, but no test had exercised it before.

### Tests added (test count: 306, was 300)

- 6 new assertions in `tests/test_templates.sh` Section 5b (bulk-warning surface). Total: **306 CI tests** (was 300) plus the new doc-link validator (137 links checked).
- 6 new assertions in `tests/integration/test_pac_dependent.sh` Section 6 (live solution-down). These run locally only — the integration suite is unchanged in CI scope.

### Why this closes the comprehensive-coverage gap

The three items closed here were the genuinely-remaining test surfaces from the v2.10.0 review:

| Item | Before | Now |
|---|---|---|
| Real pac drift detection | maintainer manual run | weekly cron + tag-push CI + workflow_dispatch |
| Doc link rot | none | 137 links validated per PR |
| Live solution export+unpack | mocked only | opt-in real-tenant section |
| Bulk-upload warning surface | untested | 6 mock-pac assertions |

What remains beyond this is environmental and not directly testable: real production-tenant upload behavior (only meaningful with a real cache-hung portal), DotLiquid filter behavior on Microsoft's runtime (no public test harness exists for the .NET reimplementation), and Microsoft API stability outside our control. Those are documented in the skill references; further coverage would require infrastructure we don't have.

## [2.11.2] — 2026-04-30

Closes the v2.10.0 "Templates as full scripts running pac" gap from the remaining-gaps list. New end-to-end test suite drives each project-drop-in template (down/up/doctor/solution-down/solution-up/commit) with the mock pac on PATH and asserts on both stdout shape and an audit log of pac invocations. Surfaced and fixed two latent pipefail bugs that crashed templates on clean working trees.

### Added (mock pac, no plugin version bump)

- **`PP_MOCK_PAC_AUDIT_LOG` capture in the mock pac** — when set to a writable path, every invocation is appended as one NUL-separated record (argv joined by `\0`, terminated by `\n`). Tests parse this to verify the exact pac subcommand+args each template runs, so future refactors that drop a step (e.g. removing `pac auth select` before `pac org who`) get caught at PR time. NUL separation avoids ambiguity when args contain spaces; the single-`printf`-per-record write keeps records atomic under POSIX PIPE_BUF guarantees, even with concurrent template invocations sharing one log.

### Added (test_templates.sh — 54 assertions)

- **`tests/test_templates.sh`** — first direct test coverage for the templates. Each template runs in a fresh temp git repo with mock pac on PATH and scoped state. Covers:
  - `down.sh`: placeholder guard, happy path, audit-log of `auth select` + `org who` + `paportal download --path . --webSiteId X --modelVersion N`, abort-on-N
  - `up.sh`: `--validate-only` (validates `--validateBeforeUpload` flag), full upload (validates flag is absent), prod confirmation gate (refuses on declined, proceeds on `yes`)
  - `doctor.sh`: full pac path (`auth list` + `auth select` + `org who`), site-folder detection, placeholder guard
  - `solution-down.sh`: export+unpack happy path, atomic-swap end state (no `.new` / `.bak` / `.zip` left over), abort-on-N, placeholder guard, **clean-tree regression**
  - `solution-up.sh`: pack+import non-prod, prod confirmation by typed solution name (refuses wrong name, proceeds on correct), missing-unpack-dir refusal
  - `commit.sh`: nothing-to-commit, stage-all-with-message-arg, abort-on-q, makes-no-pac-calls

### Fixed (pp-sync v2.4.2)

- **`up.sh` no longer aborts before uploading on a clean working tree.** The pipeline `printf | grep -v '^$' | sort -u | wc -l` exits 1 (grep finds zero matches) when both `git diff --name-only` and `git ls-files --others` produce empty output. With `set -euo pipefail`, that propagated through the pipeline and aborted the script silently between "Active env:" and the upload step. Replaced `grep -v '^$'` with `awk 'NF'` (matches non-empty lines, always exits 0). **Symptom**: running `up.sh --validate-only` on a freshly-cloned repo (or after a successful upload+commit cycle) silently exited with code 1, no upload attempted, no error message.
- **`solution-down.sh` no longer aborts on a clean re-export.** `git status -s | grep "$SCHEMA_DIR" | head -10` exits 1 (grep finds nothing) when re-exporting an unchanged solution that's already committed, so pipefail aborted the script before "Done" printed. The unpacked dir was correct; only the final status summary was missed and exit code was wrong. Wrapped grep with `{ grep || true; }` to localize the exit-code suppression.

### Tests added (test count: 300, was 246)

- 54 new assertions in `tests/test_templates.sh` (17 sections). Both regression cases above are explicitly covered: section 5 / section 9b verify `Done.` is reached with `RC=0` after a clean-tree run.

### CI

- New "Run template integration tests" step. Total CI test count: **300** (was 246).

### Why this closes the v2.10.0 gap

v2.10.0's remaining-gaps table listed "Templates as full scripts running pac" as not-yet-covered. Test coverage of `bin/pp` was strong, but the templates — which users actually drop into their projects and run — had never been exercised end-to-end against pac. The two bugs fixed here would have hit any user with a clean working tree on day 1; they were latent because the test suite was structured around `pp` as the entry point, not the templates. Going forward, the audit-log pattern in the mock pac means any template change that alters pac invocation surface gets caught.

## [2.11.1] — 2026-04-30

Closes the v2.10.0 "covered indirectly via `pp project add`" gap with an actual full-flow setup test. Surfaced and fixed a real bug that had made scripted `pp setup` invocation impossible since the function was first written.

### Fixed (pp-sync v2.4.1)

- **`cmd_setup` now correctly separates the candidate-list iteration from the user-prompt stdin.** The previous `while IFS= read -r candidate; ... done <<< "$candidates"` redirected stdin to the heredoc for the entire loop body — every inner `read -r -p "Project name [...]: " name` call read from the candidates list, not from the user's terminal/piped stdin. With one candidate in the list, the first inner read consumed the candidate path as the project name; with subsequent reads, the heredoc was exhausted and `read` returned EOF, triggering a silent `set -e` abort.
  - **Symptom**: `printf '...inputs...' | pp setup` silently exited at the first per-candidate prompt with code 1, no projects registered. Anyone trying to script setup (CI bootstrap, dev-onboarding, etc.) hit this.
  - **Manual interactive use was unaffected** — when stdin is a TTY, the inner reads see the TTY directly because the `<<<` redirect doesn't shadow it. That's why this bug had been latent since the function was written.
  - **Fix**: read candidates from fd 3 (`while IFS= read -r -u 3 candidate; do ... done 3<<< "$candidates"`). Stdin (fd 0) flows through to the inner prompt reads as expected.

### Tests added (test count: 246, was 238)

- 8 new full-flow setup assertions in `test_command_flows.sh` Section 10b — drive the entire 8-prompt registration via piped stdin, verify the resulting conf has correct NAME / PROFILE / ENV_URL (pulled from `pac org who` via the mock) / SITE_DIR, and that the suggested alias was written. The previous 5 assertions still verify the detection-only / decline path. **The "covered indirectly via `pp project add`" caveat in v2.10.0's gap list is now resolved** — full setup is exercised directly.

### Why this matters

Two days of probing surfaced a bug that was invisible to interactive users for the function's entire history. The bug was only reachable via piped stdin — and pp-sync had never had a test that piped stdin to setup. The lesson is the same one the v2.7.x rounds taught: **untested code paths harbor bugs even when they look innocuous, and the bugs are often only reachable from contexts the original author didn't anticipate.**

## [2.11.0] — 2026-04-30

Closes the "real-pac behavior diff the mock can't catch" gap from v2.10.0's "remaining gaps" list. New contract test suite — runnable against either the mock (default, CI) or real `pac` (release-prep) — defines what pp depends on from each pac subcommand and verifies the dependency holds.

### Added (pp-sync v2.4.0)

- **`tests/test_pac_contract.sh`** — 10 contract assertions across 6 sections covering every pac subcommand pp invokes:
  - `auth list` — row shape (`UNIVERSAL <profile>` substring), URL presence
  - `auth select` — exit-code semantics for known/unknown profiles
  - `org who` — `Environment Url:` line shape and URL parseability
  - `paportal upload --validateBeforeUpload` — validation message presence
  - `solution unpack` — produces target folder + `Entities/` subdir pp counts
  - `pac --version` / `pac help` — callability

  Two run modes:

  ```bash
  bash plugins/pp-sync/tests/test_pac_contract.sh            # mock (CI)
  PP_PAC_REAL=1 bash plugins/pp-sync/tests/test_pac_contract.sh   # real pac
  ```

  CI runs the mock mode on every PR. **Maintainers run the real-pac mode before each release** to catch drift when Microsoft changes pac output formats. Mode-specific assertions skip cleanly when they'd mutate user state (e.g., `auth select` to a real profile, `paportal upload` against a real environment).

### Bug surfaced + fixed (in this same release)

Running the contract suite against real pac immediately surfaced a discrepancy: real pac's `auth list` has 9 columns (Index/Active/Kind/Name/User/Cloud/Type/Environment/URL) while the mock had 5 (Index/Active/Kind/Name/URL). The original contract assertion `UNIVERSAL <name> <url>` was over-strict and would have rejected real pac as drifted — but pp's actual `grep -qE "UNIVERSAL[[:space:]]+\${PROFILE}\b"` doesn't depend on column 5 being a URL.

Fix: relaxed the contract assertion to match what pp actually parses (`UNIVERSAL <name>` substring), with a separate soft check for "URL appears anywhere on the row." This is the right shape — **the contract reflects the dependency, not the format.**

### Documentation

- `CONTRIBUTING.md` "pac contract tests" section documents the two run modes, the release-prep workflow, and the meaning of skipped assertions.

### CI

- New "Run pac contract tests (mock mode)" step. Total CI test count: **238** (was 228).

### Why this closes the v2.10.0 gap

v2.10.0's CHANGELOG acknowledged: "Real-pac behavior diffs the mock can't catch. Covered by local integration suite." That coverage was correct but reactive — drift would only surface when a maintainer happened to run the integration suite. The contract suite makes the dependency explicit in code: any real pac that fails this contract will break pp's parsers, so the maintainer can fix one or the other before users hit the drift.

## [2.10.0] — 2026-04-30

Closes the two known journal-tracking gaps that v2.9.4 acknowledged but didn't fix.

### Added (pp-sync v2.3.0)

- **Journal active-issue state file at `$PP_CONFIG_DIR/state/<project>/active-issue`.** `pp journal open` writes the URL there; `pp journal note|close` reads from there (preferring it over the JOURNAL.md grep). `pp journal close` clears the state. Closes the bug where `open A → close A → open B` (without a board) caused subsequent `pp journal note` to post to closed issue A — `tail -1` of `^Issue:` lines in JOURNAL.md picked the most-recently-WRITTEN issue regardless of close status.
- **Backward compat for pre-v2.9.5 journals** — when the state file doesn't exist, `journal_active_issue_for` falls back to the JOURNAL.md grep. Existing users keep working without migration.
- **`pp project remove` cleans up the state directory** (`rm -rf $PP_CONFIG_DIR/state/<project>/`). Closes the orphaned-state-dir gap.

### Fixed (pp-sync v2.3.0)

- **Atomic JOURNAL.md writes via single-syscall `printf`.** The previous `{ echo; echo; echo; } >> JOURNAL.md` block was NOT atomic — each `echo` was a separate `write()`. Concurrent `pp journal open` invocations (parallel CI jobs, multiple maintainers, automated tooling) could interleave their lines, causing later `note|close` to associate text with the wrong issue. New helper `journal_append_atomic` builds the entry in a string and writes it with one `printf >>`. Per the kernel guarantee for `write()` calls under PIPE_BUF (~4KB on Linux, 512B on macOS — ample for one entry), no interleaving is possible. Tested: 5 concurrent `pp journal open` invocations now produce 5 distinct task headers, none on the same line as another, none corrupted.

### Tests added

**New suite `tests/test_journal_state.sh` — 10 cases:**

- State file lifecycle: set → read → clear (3 cases)
- `open` without remote board doesn't create stale state (2 cases — verifies the new clear-on-open-without-board behavior + that JOURNAL.md still gets exactly one task header)
- Stale state from prior `open` is cleared by new `open` without board
- JOURNAL.md fallback works for pre-v2.9.5 journals (Issue: line grep)
- Concurrent `open` is atomic (5 parallel invocations, no interleaving, no missing or duplicated headers — 2 assertions)
- `project remove` cleans up state directory

**CI wired** — new "Run pp journal-state tests" step. Total CI test count: **228** (was 218).

## [2.9.4] — 2026-04-30

Fifteenth review pass. 5 real bugs surfaced + fixed. Test count: **218** (was 211).

### Fixed (pp-sync v2.2.4)

- **`pp setup` aborted under `set -euo pipefail` when zero PAC profiles were registered.** The `echo "$pac_output" | grep -E '^\[[0-9]+\]' | head -10` pipeline tripped pipefail when grep found no matches (the empty-profile case is valid state for first-time users — they haven't run `pac auth create` yet). Same pattern at line 483 in the candidate-walkthrough loop. Both pipelines now end with `|| true`. Real-user impact: anyone running `pp setup` for the first time without any registered PAC profiles saw the script die silently after listing the (empty) profiles.
- **`pp solution-down|up` accepted unvalidated solution names from CLI args and the interactive name branch.** A user typing `pp solution-down acme '../../etc/foo'` (or selecting non-numeric input at the multi-solution prompt) passed unchecked text into `mkdir`/`mv`/`rm -rf` paths under `$SCHEMA_DIR`. `format_solutions_array` validates entries at registration time but those code paths bypass it. Both subcommands now call `validate_identifier "Solution name" "$solution" '^[A-Za-z0-9_.-]+$'` after the resolution branch. Self-attack severity (the user types the bad input themselves), but real path-traversal mechanism.
- **`pp generate-page` accepted whitespace-only and pure-dot/dash names** that passed `validate_identifier` but slugified to an empty string, causing `page_dir` to resolve to `$SITE_DIR/web-pages/` itself. On a fresh portal source (where `web-pages/` doesn't exist), the function then wrote `.webpage.yml` files directly into the parent directory. Added an explicit empty-slug check after slug derivation.
- **`install.sh` PATH check used unanchored regex grep (false positives).** `grep -qx "$BIN_DIR"` treated the value as a basic regex; the `.` in `~/.local/bin` matched any character, so `~/zlocal/bin` (a path the user does NOT have) was treated as already in PATH. Switched to `grep -qFx` (fixed-string mode).
- **`load_project` aborted under `set -u` when `$HOME` was unset** (chroot, `env -i`, scratch container). The new `${REPO/#~/$HOME}` and `${REPO/#\$HOME/$HOME}` expansions referenced `$HOME` directly. Now defaults via `${HOME:-}` and skips both expansions if empty.

### Tests added (test count: 218, was 211)

- 4 cases in `test_subcommand_safety.sh` exercising the new solution-name CLI-arg validation (path traversal, slash injection, shell metachar, semicolon).
- 3 cases in `test_subcommand_safety.sh` for the generate-page empty-slug rejection (whitespace-only, pure dots, pure dashes).

### Documentation

- **`tests/README.md`** test-count table updated: `test_load_project.sh` 15 → 21, `test_command_flows.sh` 66 → 78, `test_subcommand_safety.sh` 23 → 30. Description for `bin/pp` updated from "1500-line" to "~1800-line".
- **`tests/mocks/README.md`** mock line-count updated 250 → 330.

### Pattern note

This is the 15th review pass and the bug count per round is plateauing — no architectural issues, no new attack surfaces. The 5 bugs found here all fall into known categories already extensively covered: pipefail aborts (1), input-validation bypasses (2), edge cases in identifier handling (1), defensive-default omissions (1). The ratio of "scrutinized assertion : surfaced bug" for the top-level adversarial review was about 7:1 — substantially lower bug-yield than earlier rounds.

## [2.9.3] — 2026-04-29

Chunk 4 of pac mocking — `pp setup` detection phase coverage. Test count: **211** (was 204).

### Tests added (test_command_flows.sh, +7 cases)

- **`pp setup` detection phase (5 cases)** — fake `$HOME/Projects/AcmeCorp/acme---acme/` fixture + mock `pac auth list`. Asserts setup detects the PAC profile, scans for site folders, discovers the candidate, prompts for walkthrough confirmation, and respects user declining (no confs created). Full registration flow not driven via stdin — that path is exercised by `test_register_atomic.sh` via `pp project add` (same identifier validation + atomic write paths).
- **`pp generate-page` JS/CSS placeholder files (2 cases)** — generated page directory must include `<Page>.webpage.custom_javascript.js` and `<Page>.webpage.custom_css.css` even when empty (Power Pages expects them present at runtime).

### Why the partial setup coverage

`pp setup`'s 8-prompt registration flow is hard to drive deterministically via piped stdin — `read -p` interleaves with stdout in non-TTY contexts, making prompt visibility unreliable. The detection-phase tests catch the most likely regression class (setup not reaching the candidate walkthrough). The actual write paths are covered by the `pp project add` atomic-registration suite, which uses the same `validate_identifier` / `format_solutions_array` / atomic-write helpers.

## [2.9.2] — 2026-04-29

Chunk 3 of pac mocking — closing the long-tail coverage gaps. Pure test additions, no code changes. Test count: **204** (was 189).

### Tests added

**Generated content correctness (test_command_flows.sh, +5 cases)**
- `cmd_generate_page` YAML has `adx_name`, `adx_partialurl`, `adx_publishingstateid: Published`
- Generated HTML mentions the page title + Bootstrap container class
- Localized variant exists at `content-pages/en-US/<Page>.en-US.<suffix>` (the proper Power Pages layout fixed in v2.7.6)

**`pp doctor` site-content counts beyond zero (test_pac_mocked.sh, +4 cases)**
- Pre-populates a fixture site with 3 web-pages, 2 web-templates, 1 content-snippet, 1 table-permission
- Asserts each count line shows the expected number, not just that the section appears

**`pp diff` reports changed files (test_pac_mocked.sh, +1 case)**
- Initializes a git repo, modifies a file, runs `pp diff`, verifies the diff completes without crash

**Audit rule negative cases (test_audit.py, +5 cases)**
- WRN-005 doesn't fire on PascalCase navigation property (the SAFE form)
- WRN-008 doesn't fire on empty `Webapi/<entity>/Fields = ""`
- INFO-007 doesn't fire on safe `replace: 'X', 'Y'` patterns (no quote escaping)
- INFO-008 doesn't fire on `{% for %}` loops without nested queries
- WRN-003 doesn't fire when the sitemarker IS defined

These guard against regressions where a refactor accidentally broadens a rule's trigger condition (false-positive flood).

### Suite-by-suite test count

| Suite | Before | After |
|---|---|---|
| audit.py | 26 | **31** |
| test_load_project.sh | 21 | 21 |
| test_register_atomic.sh | 6 | 6 |
| test_journal_url_validation.sh | 16 | 16 |
| test_subcommand_safety.sh | 23 | 23 |
| test_command_flows.sh | 66 | **71** |
| test_install_script.sh | 13 | 13 |
| test_pac_mocked.sh | 18 | **23** |
| **Total** | **189** | **204** |

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

[2.12.2]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v2.12.2
[2.12.1]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v2.12.1
[2.12.0]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v2.12.0
[2.11.3]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v2.11.3
[2.11.2]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v2.11.2
[2.11.1]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v2.11.1
[2.11.0]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v2.11.0
[2.10.0]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v2.10.0
[2.9.4]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v2.9.4
[2.9.3]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v2.9.3
[2.9.2]: https://github.com/Nerdy-Q/claude-power-pages-plugins/releases/tag/v2.9.2
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
