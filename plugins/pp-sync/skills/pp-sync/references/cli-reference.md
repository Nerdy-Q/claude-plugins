# `pp` CLI Reference

The `pp` command is a unified dispatcher for Power Pages portal sync, solution import/export, and permissions audit operations. It's backed by a project registry so you can run `pp down anchor` instead of remembering which wrapper script lives where with which CONFIG values.

## Installation (one-time)

```bash
# From the plugin cache:
~/.claude/plugins/cache/nq-claude-power-pages-plugins/pp-sync/<version>/install.sh

# Or from the source repo:
cd ~/Projects/claude-power-pages-plugins/plugins/pp-sync
./install.sh
```

This symlinks `bin/pp` to `~/.local/bin/pp` and creates `~/.config/nq-pp-sync/`. If `~/.local/bin/` isn't on your PATH, the installer tells you what to add to your shell rc.

After install, run `pp setup` for the interactive bootstrap.

## Platform support

`pp` currently targets macOS, Linux, and WSL. It assumes Bash plus common Unix tools (`find`, `sed`, `awk`, `grep`, `mktemp`, `realpath`, `cp`) and installs into `~/.local/bin/`.

Native Windows support is planned as a separate release path. Until that exists, WSL is the recommended way to use `pp-sync` on Windows machines.

## Commands

### Project registry

| Command | Description |
|---|---|
| `pp setup` | Interactive bootstrap — auto-detects Power Pages projects in `~/Projects/`, lists PAC profiles, walks through registering each |
| `pp list` (`pp ls`) | Show all registered projects with aliases and env URLs |
| `pp show <project>` | Show full config for a project |
| `pp project add [name]` | Register a new project (interactive) |
| `pp project edit <project>` | Open project config in `$EDITOR` |
| `pp project remove <project>` | Delete a project's config and any aliases pointing to it |
| `pp alias add <alias> <project>` | Add a shorthand alias |
| `pp alias list` | List all aliases |

### Active project / env switching

| Command | Description |
|---|---|
| `pp switch <project>` (`pp use`) | Set as the active project; also runs `pac auth select` to switch env |
| `pp status` | Show currently active project + live env from `pac org who` |

### Sync operations

All sync commands take a project as the first argument. The project arg can be the exact name, an alias, or a unique prefix.

| Command | Description |
|---|---|
| `pp down <project> [--no-clean]` | Download portal from Dataverse with auto noise-stash |
| `pp up <project> [--validate-only] [--force-bulk] [--bulk-threshold=N]` | Upload portal changes; warns if >50 changed files |
| `pp diff <project> [--diff] [--names-only] [--bulk-threshold=N]` | Preview what `pp up` would push — categorized changed-file list, no upload |
| `pp doctor <project>` | Health check — tooling, auth, structure, content counts |
| `pp generate-page <project> <Name>` | Scaffold a new hybrid-pattern page (base + en-US) |
| `pp sync-pages <project> [direction]` | Bulk-copy between base `<Page>.webpage.copy.html` and localized `content-pages/<lang>/` variants. Direction is `base-to-localized` or `localized-to-base`; omit for interactive prompt |
| `pp journal <project> {init|open|note|close} <args>` | Automated work tracking & Project Board integration |
| `pp solution-down <project> [solution]` | Export Dataverse solution + unpack |
| `pp solution-up <project> [solution]` | Pack + import Dataverse solution (DESTRUCTIVE) |
| `pp audit <project> [--severity ...] [--exit-code] [--json]` | Run permissions audit (delegates to `pp-permissions-audit`) |

### Help

| Command | Description |
|---|---|
| `pp help` (`pp -h`, `pp --help`) | Show command reference |

## Project name resolution

When you pass a project name to a command, `pp` resolves it in this order:

1. **Exact match** — `~/.config/nq-pp-sync/projects/<name>.conf` exists
2. **Alias** — `<name>` appears in `~/.config/nq-pp-sync/aliases` as a key
3. **Unique prefix** — `<name>` is a unique prefix of exactly one registered project
4. **Active project** — if no name passed, use `~/.config/nq-pp-sync/active`

Examples (assuming you've registered `anchor`, `contoso-dev`, `contoso-client`, `modernization-energy`):

```bash
pp down anchor              # exact
pp down petr                # ambiguous → error (matches both contoso-*)
pp down contoso-d         # unique prefix → contoso-dev
pp alias add petro contoso-dev
pp down petro               # alias
pp switch energy            # exact
pp down                     # uses active project (energy)
```

## Project config files

Each project lives in a single bash file at `~/.config/nq-pp-sync/projects/<name>.conf`. The file is sourced by `pp` at runtime, so any valid bash works. Supported variables:

| Variable | Required? | Description |
|---|---|---|
| `NAME` | Y | Display name (often same as filename) |
| `REPO` | Y | Path to the git repo root (`~` is expanded) |
| `SITE_DIR` | Y | Path to the site folder relative to `REPO` |
| `PROFILE` | Y | PAC auth profile name |
| `WEBSITE_ID` | for `down` | GUID from `pac paportal list` |
| `ENV_URL` | optional | For doctor cross-check |
| `MODEL_VERSION` | default: `2` | `1` = Standard, `2` = Enhanced |
| `SCHEMA_DIR` | default: `dataverse-schema` | Where solution unpack goes |
| `BRANCH` | optional | Default git branch for this env |
| `BOARD_URL` | optional | URL or ID of the GitHub/GitLab project board |
| `BOARD_SYSTEM` | default: `auto` | `github`, `gitlab`, or `none` |
| `AI_ATTR` | default: `yes` | Whether to tag notes as `[AI-Assisted]` |
| `SOLUTIONS` | optional | Bash array — `SOLUTIONS=("Foo" "Bar")` |
| `TAGS` | optional | Free-form tags; not used by pp itself |

Example:

```bash
# ~/.config/nq-pp-sync/projects/anchor.conf
NAME="Acme Portal"
REPO="$HOME/Projects/Contracts/Acme Corp"
SITE_DIR="acme-portal-operations/acme---acme"
PROFILE="acme-client-dev"
WEBSITE_ID="00000000-0000-0000-0000-000000000000"
ENV_URL="https://acme-dev.crm.dynamics.com/"
MODEL_VERSION="2"
SCHEMA_DIR="dataverse-schema"
BRANCH="main"
SOLUTIONS=("AcmePortalOperations")
TAGS="portal,client,commercial"
```

You can edit by hand or via `pp project edit <name>`.

## Aliases file

`~/.config/nq-pp-sync/aliases` is a simple key=value file, one alias per line:

```
petro=contoso-dev
petro-c=contoso-client
energy=modernization-energy
wam=modernization-wm
```

Edit by hand or via `pp alias add <alias> <project>`.

## CI integration

For GitHub Actions, the audit subcommand has CI-friendly flags:

```yaml
- name: Power Pages permissions audit
  run: |
    pp audit ${{ env.PP_PROJECT }} --severity ERROR --exit-code
```

Returns exit code 1 if any ERROR-class findings exist; 0 otherwise.

## Per-project shell aliases

For frequently-used projects, you can define shell aliases on top of `pp` aliases:

```bash
# in ~/.zshrc or ~/.bashrc
alias anchordown='pp down anchor'
alias anchorup='pp up anchor'
alias anchordoc='pp doctor anchor'
alias petrodown='pp down petro'
alias allaudit='for p in $(pp list | tail -n +3 | awk "{print \$1}"); do pp audit "$p" --severity ERROR; done'
```

## When `pp` doesn't fit

For one-off projects you don't want to register, the standalone `templates/*.sh` scripts still work. Drop them into a project's repo root, set the CONFIG block, and run them directly. They're independent of `pp` and don't read the registry.

When to use which:

- **`pp` registry**: you have multiple ongoing projects, want shorthand, want consistency across machines (commit the registry to a personal dotfiles repo)
- **`templates/*.sh`**: a project you only touch occasionally; or a project you want to ship its own wrappers checked into the project repo for teammates who don't have `pp` installed

## Migrating from templates to the registry

If you already have `templates/down.sh` etc. in a project, you can keep them — they continue to work. To migrate to `pp`:

1. Run `pp setup` (auto-detects the project)
2. Confirm the suggested config matches what's in the template's CONFIG block
3. `git rm templates/*.sh` if you don't want to keep them around (or leave for teammates)

## Troubleshooting

### `pp: command not found`

The installer didn't put `pp` on your PATH. Add `export PATH="$HOME/.local/bin:$PATH"` to your shell rc and reload.

### `Unknown project: foo`

The name didn't match any registered project, alias, or unique prefix. Check `pp list` for available names.

### `Ambiguous project name 'petr'`

Two or more projects start with `petr`. Either type more characters until unique, or use an alias (`pp alias add petro contoso-dev`).

### `pac auth list returned no profile X`

The configured PROFILE in your project's conf isn't registered in PAC. Either:
- Register it: `pac auth create --name X --environment <url>`
- Or edit the conf to use a different profile: `pp project edit <name>`

### Active project drift

If `pp status` shows a different env URL than the configured one for the active project, your PAC profile may have been reauthenticated to a different env. Run `pac auth select --name <profile>` then `pp status` again.
