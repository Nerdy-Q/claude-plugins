# Changelog

All notable changes to this marketplace are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), with version numbers tracking the marketplace as a whole. Per-plugin versions live in each `plugins/<name>/.claude-plugin/plugin.json` and are noted below where they advance.

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
