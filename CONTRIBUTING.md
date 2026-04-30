# Contributing

Thanks for your interest in improving the Power Pages plugins. These plugins exist because real production Power Pages projects have a long tail of gotchas the model can't infer from generic Liquid docs alone — every PR that codifies one more gotcha makes the model more useful for everyone.

## Plugin layout

```
claude-power-pages-plugins/
├── .claude-plugin/marketplace.json     # marketplace manifest
└── plugins/
    └── <plugin>/
        ├── .claude-plugin/plugin.json  # plugin manifest
        ├── README.md
        ├── skills/<skill>/
        │   ├── SKILL.md                # frontmatter + body
        │   └── references/             # topic-specific reference files
        └── (optional bin/, scripts/, templates/)
```

## Where to make changes

| Change type | File to edit |
|---|---|
| New audit check | `plugins/pp-permissions-audit/skills/pp-permissions-audit/scripts/audit.py` (add a `check_*` function, register in `main()`, document in `references/checks.md`) |
| New Liquid pattern, gotcha, or troubleshooting recipe | The relevant file under `plugins/pp-portal/skills/pp-portal/references/<category>/` (categories: `language/`, `data/`, `pages/`, `workflow/`, `quality/`) |
| New `pp` subcommand | `plugins/pp-sync/bin/pp` (add a `cmd_*` function, register in `main()`, document in `references/cli-reference.md`) |
| New wrapper script template | `plugins/pp-sync/templates/<name>.sh` plus an entry in `templates/README.md` |
| New skill on top of existing plugins | New plugin under `plugins/<name>/`, register in `marketplace.json` |

## Examples must be generic

All shipped examples use **fictional companies and placeholder syntax**. No client identifiers, no real GUIDs, no real env URLs.

| Use | Don't use |
|---|---|
| `acme.crm.dynamics.com` (Acme = canonical fictional commercial) | Real customer URLs |
| `contoso.crm9.dynamics.com` (Contoso = canonical fictional government) | Real GCC URLs |
| `acme_<field>` / `contoso_<field>` for prefix examples | Real publisher prefixes |
| `00000000-0000-0000-0000-000000000000` for GUIDs | Real GUIDs |
| `you@your-org.com` / `service-account@acme.com` for emails | Real emails |
| `<your-prefix>_<field>` for placeholder syntax | Real custom field names |

## Testing changes

### `pp-permissions-audit`

```bash
# Run against a real local site folder you have access to:
python3 plugins/pp-permissions-audit/skills/pp-permissions-audit/scripts/audit.py \
    /path/to/<site>---<site>/ --severity ERROR
```

The audit script is stdlib-only — no `pip install` required.

### `pp` CLI

```bash
cd plugins/pp-sync
./install.sh                                                    # symlinks pp to ~/.local/bin/
pp help
pp setup                                                        # bootstrap with your local projects
```

### Plugin manifest validation

```bash
python3 scripts/sync_versions.py                              # sync versions.json into live files
claude plugin validate plugins/<plugin>
claude plugin validate .                                        # marketplace
```

## Version management

Use [versions.json](versions.json) as the single source of truth for the live versioned values currently managed by the repo:

| Field | What it controls |
|---|---|
| `marketplace.version` | The umbrella release version. Must match the topmost `## [X.Y.Z]` header in `CHANGELOG.md` — `sync_versions.py` enforces this. |
| `plugins.<name>` | Per-plugin manifest versions (auto-propagated into each `plugins/<name>/.claude-plugin/plugin.json`). |
| `docs.pp_permissions_audit_ci_ref` | Pinned tag used in `pp-permissions-audit/CI.md` and the shipped GitHub Actions template. |

After changing any value, run:

```bash
python3 scripts/sync_versions.py
```

CI runs `python3 scripts/sync_versions.py --check`, so version drift will fail validation. The marketplace.version ↔ CHANGELOG header check is one-way: the script reads CHANGELOG (historical record, never auto-rewritten) and refuses if `versions.json` disagrees.

### Cutting a release

1. Update `versions.json` — bump `marketplace.version` and any per-plugin versions that advanced.
2. Add a new `## [X.Y.Z] — YYYY-MM-DD` section at the top of `CHANGELOG.md` with full notes.
3. Add the matching `[X.Y.Z]: https://github.com/...` link reference at the bottom.
4. Run `python3 scripts/sync_versions.py` to propagate per-plugin versions into manifests + auto-update `pp-permissions-audit/CI.md` and the GitHub Actions template.
5. Commit, open PR, let CI verify.
6. After merge, tag `vX.Y.Z` and `git push --tags`.
7. Create a GitHub Release with notes (use the CHANGELOG section as the source).

### Local marketplace install

```bash
claude plugin marketplace add /path/to/claude-power-pages-plugins
claude plugin install pp-portal@nq-claude-power-pages-plugins
```

## Adding an audit rule

1. **Add a `check_*` function** to `plugins/pp-permissions-audit/skills/pp-permissions-audit/scripts/audit.py`. The function receives an `AuditState` and calls `state.add(severity, code, title, detail, location=...)`. Codes follow `ERR-NNN`, `WRN-NNN`, `INFO-NNN` numbering — pick the next free number in the relevant range.
2. **Register it in `main()`** — look for the `check_*` invocations toward the bottom of `audit.py` and add yours.
3. **Document the code in three places:**
   - `plugins/pp-permissions-audit/skills/pp-permissions-audit/references/checks.md` (definition + trigger)
   - `plugins/pp-permissions-audit/skills/pp-permissions-audit/references/interpreting.md` (likely-real?, what it means, false-positive cases)
   - `plugins/pp-permissions-audit/skills/pp-permissions-audit/references/remediation.md` (concrete fix steps)
4. **Update the count in `plugins/pp-permissions-audit/README.md`** ("All 25 checks shipped") and the root `README.md` ("25 checks including...").
5. **Write a unit test** in `plugins/pp-permissions-audit/skills/pp-permissions-audit/scripts/test_audit.py`. The test must:
   - Create a minimal site fixture (use `make_minimal_site()` helper)
   - Trigger the rule
   - Assert the code appears in `self.codes(report)`
   - Where appropriate, also assert a negative case (clean fixture → code does NOT fire)
6. Run `python3 -m unittest plugins/pp-permissions-audit/skills/pp-permissions-audit/scripts/test_audit.py` — all tests must still pass.
7. CI's link checker validates references; `sync_versions.py --check` enforces version coherence; a marketplace.version bump is required if the rule meaningfully changes behavior of an existing check.

Every audit rule shipped today has both positive coverage (rule fires on a fixture that should trigger it) and (where applicable) negative coverage (rule does NOT fire on a fixture that should be clean).

## Test suites

The marketplace runs four test suites in CI. Run any of them locally:

```bash
# pp-permissions-audit — Python unit tests (audit.py rule logic)
python3 -m unittest plugins/pp-permissions-audit/skills/pp-permissions-audit/scripts/test_audit.py

# pp-sync — bash regression tests
bash plugins/pp-sync/tests/test_load_project.sh           # 12 cases — strict conf parser
bash plugins/pp-sync/tests/test_register_atomic.sh        # 6 cases — pp project add atomicity
bash plugins/pp-sync/tests/test_journal_url_validation.sh # 16 cases — journal URL hardening
```

The bash suites use fixture files under `plugins/pp-sync/tests/fixtures/` and a source-safe pattern that loads `bin/pp` without dispatching commands. See `plugins/pp-sync/tests/README.md` for fixture conventions and how to add a new test.

When adding a new `pp` subcommand or registration path, add fixtures + assertions to the matching suite. The suites are wired into `.github/workflows/plugin-validate.yml` automatically.

## Static analysis

CI runs ShellCheck at `--severity=warning` against every shell script. Install locally:

```bash
brew install shellcheck     # macOS
apt-get install shellcheck  # Debian/Ubuntu
shellcheck --severity=warning plugins/pp-sync/bin/pp
```

All shipped scripts pass clean. PRs that introduce SC2086 (unquoted vars), SC2155 (`local x=$(cmd)`), SC2164 (bare `cd`), or other warning-class issues will fail CI.

## Conventions

- **Plugin slugs**: short, kebab-case
- **Skill descriptions**: include both positive triggers ("use when…") and explicit negatives ("NOT for…")
- **Reference files**: keep `SKILL.md` lean (router + critical gotchas); push depth into topic-specific files in `references/`
- **No comments unless the WHY is non-obvious** — well-named code over inline narration

## Reporting issues

- Bugs in the audit (false positives / false negatives): include the smallest YAML or JS snippet that reproduces, plus the expected behavior
- Missing Liquid pattern: PR a new section in the relevant `pp-portal` reference file (under the appropriate category subdir)
- `pp` CLI bugs: include the project conf, the command, and the actual vs expected output

## License

Contributions are licensed under MIT, same as the project. By submitting a PR you agree to license your contribution under those terms.
