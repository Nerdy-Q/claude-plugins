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
claude plugin validate plugins/<plugin>
claude plugin validate .                                        # marketplace
```

### Local marketplace install

```bash
claude plugin marketplace add /path/to/claude-power-pages-plugins
claude plugin install pp-portal@nq-claude-power-pages-plugins

## Near-term hardening

The audit now has regression tests. The next test surface worth adding is `pp-sync/bin/pp`:

- project-config generation fixtures (`pp setup`, `pp project add`)
- changed-file counting and bulk-upload warnings
- repo-local vs plugin-cache audit fallback behavior
```

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
