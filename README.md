# NerdyQ Claude Power Pages Plugins

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Power Pages](https://img.shields.io/badge/Power%20Pages-hybrid%20Liquid%20%2B%20Web%20API-purple.svg)](https://learn.microsoft.com/en-us/power-pages/)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin%20marketplace-orange.svg)](https://docs.claude.com/en/docs/claude-code/plugins)

Open-source Claude Code plugins from [NerdyQ](https://github.com/Nerdy-Q) for **Microsoft Power Pages classic portals**: optimized for the current enhanced-model workflow around native Power Pages Studio's **hybrid Liquid + Web API** pattern, plus safe `pac paportal` sync workflows and static-analysis security audit.

If you build classic Power Pages sites, particularly the hybrid native pattern where Liquid renders the initial state in Studio-managed portal assets and custom JS calls `/_api/<entity>` for interactivity, this marketplace turns Claude Code into a Power Pages-aware pair programmer that knows the gotchas, runs the right `pac` commands with the right safety guards, and audits your portal's permissions for misalignment. It is intentionally scoped away from full Power Pages code sites built as React-style SPAs; for those, use Microsoft's `power-pages` plugin.

## Plugins

| Plugin | Purpose |
|---|---|
| [`pp-portal`](plugins/pp-portal/) | Microsoft Power Pages classic portals, hybrid Liquid + Web API pattern. Categorized references: language (operators / tags / filters / objects / DotLiquid gotchas), data (Web API / FetchXML / Dataverse naming / permissions), pages (hybrid idiom / styling / bundled libraries), design systems (USWDS 3 / Material 3 / Apple HIG / Fluent 2 / shadcn/ui / responsive crossover), workflow (sync), quality (accessibility / troubleshooting) |
| [`pp-sync`](plugins/pp-sync/) | Action skill + `pp` CLI for running portal sync workflows safely, `pac paportal` + project registry + alias resolution + bulk-upload safety guards + 6 ready-to-drop wrapper templates |
| [`pp-permissions-audit`](plugins/pp-permissions-audit/) | Static-analysis audit of a portal's Web Roles, Table Permissions, Site Settings, Web API config, AND (when `dataverse-schema/` is present) FetchXML + `$select=` field references, 25 checks including base-vs-localized blank-page detection, polymorphic lookup pre-emption, missing anti-forgery tokens, schema-aware field validation, secured-field exposure detection, missing snippet references, FetchXML performance guardrails, and divergent base/localized pair detection. Drop-in [GitHub Action template](plugins/pp-permissions-audit/CI.md) for PR gating. |

## Install

```bash
claude plugin marketplace add https://github.com/Nerdy-Q/claude-power-pages-plugins
claude plugin install pp-portal@nq-claude-power-pages-plugins
claude plugin install pp-sync@nq-claude-power-pages-plugins
claude plugin install pp-permissions-audit@nq-claude-power-pages-plugins
```

After installing `pp-sync`, run its installer once to put the `pp` CLI on your PATH:

```bash
~/.claude/plugins/cache/nq-claude-power-pages-plugins/pp-sync/<version>/install.sh
pp setup    # interactive bootstrap, auto-detects PAC profiles + site folders
```

## Platform support

- `pp-portal`: platform-agnostic reference content
- `pp-permissions-audit`: Python-based and generally cross-platform
- `pp-sync`: currently macOS/Linux/WSL-first because the CLI, installer, and wrappers are Bash-based

Native Windows support for `pp-sync` is planned as a separate release path rather than implied compatibility through Git Bash or PowerShell.

## Marketplace structure

```
claude-power-pages-plugins/
├── .claude-plugin/
│   └── marketplace.json              # marketplace manifest
├── plugins/
│   └── <plugin-name>/
│       ├── .claude-plugin/
│       │   └── plugin.json           # plugin manifest
│       ├── README.md
│       └── skills/<skill-name>/
│           ├── SKILL.md              # skill entry point (frontmatter + body)
│           └── references/...        # topic-specific reference files
```

## Add a new plugin

1. Create `plugins/<name>/` with `.claude-plugin/plugin.json`
2. Add a `skills/<name>/SKILL.md` (or commands, agents, or MCP server)
3. Add an entry to `.claude-plugin/marketplace.json` under `plugins`
4. From any Claude Code session: `claude plugin install <name>@nq-claude-power-pages-plugins`

If the marketplace was already added, re-add it to refresh: `claude plugin marketplace add <path>`.

## Conventions

- **Plugin slugs**: short, kebab-case, prefixed with the platform if ambiguous (`pp-*` for Power Pages classic portals; `dv-*` is reserved for Microsoft's `dataverse` plugin)
- **Skill descriptions**: must include both positive triggers ("use when…") and explicit negatives ("NOT for…") so the description-gated skill loader doesn't drift onto unrelated tasks
- **Reference files**: keep `SKILL.md` lean (overview + critical gotchas + decision routing); push detail to `references/<topic>.md` so the model lazy-loads only what it needs
- **No client-specific identifiers in shipped content**, anonymize examples using fictional company names (Acme, Contoso) or placeholder syntax (`<your-prefix>_<field>`)

## License

MIT
