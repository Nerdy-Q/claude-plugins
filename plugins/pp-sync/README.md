# pp-sync

A Claude Code action skill for running **Power Pages classic portal sync workflows** safely. Ships two ergonomic levels:

1. **`pp` CLI** — unified dispatcher backed by a project registry. `pp down anchor` from anywhere; aliases, prefix-matching, switch/status, cross-plugin audit. Recommended for daily use.
2. **`templates/*.sh`** — drop-in standalone wrappers for projects you don't want to register globally.

Plus the skill (this directory's `skills/pp-sync/`) which guides Claude through pre-flight safety checks when assisting with sync operations interactively.

## Platform support

`pp-sync` is currently designed for macOS, Linux, and WSL. The `pp` CLI, installer, completions, and wrapper templates are Bash-based and assume standard Unix utilities plus a POSIX-style filesystem layout.

Native Windows support is planned as a separate release path, likely via dedicated PowerShell tooling rather than treating Git Bash behavior as the compatibility contract.

## What this is

A **rigid action skill** — has a checklist of steps that must run in order. Detects which Power Pages project is active by scanning for known wrapper-script patterns (project-prefix, env-suffix, or verb-only), confirms the operation with the user, runs pre-flight safety checks, delegates to existing wrapper scripts when present, and falls back to bare `pac` commands when not.

## Operations supported

| Operation | What it does |
|---|---|
| **down** | Download portal from Dataverse to local |
| **up** | Upload local changes to Dataverse |
| **diff** | Preview what `up` would push (no upload) |
| **doctor** | Health check (auth, tooling, structure, noise) |
| **generate-page** | Scaffold a new hybrid-pattern page (base + en-US) |
| **sync-pages** | Bulk-copy between base and localized webpage variants |
| **journal** | Automated work tracking & Project Board integration |
| **solution-down** | Export Dataverse solution + unpack |
| **solution-up** | Pack + import Dataverse solution |
| **audit** | Run permissions audit (delegates to `pp-permissions-audit`) |

For interactive commits, use `git` directly or copy `templates/commit.sh` into your project. Portal cache recovery is an Admin Center action — see `references/safety-checks.md`.

## Reference files

- `references/project-detection.md` — algorithm for identifying the active project, site folder, branch-driven env routing
- `references/wrapper-scripts.md` — three common naming patterns (project-prefix, env-suffix, verb-only) and what each wrapper does
- `references/direct-pac.md` — bare `pac paportal` and `pac solution` commands when no wrapper exists
- `references/safety-checks.md` — pre-flight, post-flight, incremental upload, recovery from hung portal cache and wrong-env mistakes
- `references/solution-sync.md` — `pac solution export/unpack/pack/import` workflow, plugin deployment, two-env promotion

## Critical safety rules this skill enforces

- Never `cd` into the site folder before downloading (creates nested copies)
- Always confirm the active PAC profile and env URL before any state-changing operation
- Bulk uploads (50+ files) get an explicit warning + incremental recommendation
- Solution import to prod requires double confirmation
- Cross-tenant safety: when you have multiple PAC profiles registered (one per client engagement), the wrong one being active = uploading to the wrong portal. The skill prints the active profile + env URL before any state-changing operation

## What this skill does NOT do

- Edit Liquid or JS files — use the `pp-portal` skill
- Audit permissions — use the `pp-permissions-audit` skill
- Configure Power Pages from scratch — use Microsoft's `power-pages` plugin
- Manage Dataverse schema interactively — use the `dataverse` plugin

## License

MIT
