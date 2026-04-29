---
name: pp-sync
description: Run Power Pages classic portal sync workflows safely — pac paportal download/upload, pac solution export/unpack, project-aware wrapper-script delegation, and bulk-upload safety guards. Use when the user wants to sync a Power Pages portal, run acmedown/up, sync-down-dev, contosodoctor, deploy portal changes, pull schema, or recover from a hung portal cache. NOT for code sites (React/Vue/Astro SPAs).
---

# Power Pages Sync — action skill

Execute portal sync flows safely. Each operation has a checklist that **must run in order**. Do not skip steps, even if a later step looks more relevant to the immediate request — earlier steps protect against the most common failure modes (working in the wrong directory, wrong auth profile, accidental destructive operations).

## Preferred interface: `pp` CLI

If the user has run `pp setup` and registered their projects, **use the `pp` CLI** — it bakes the safety checks below into a single command and reads project config from the registry, so you don't need to ask for site dir / profile / website ID each time.

```bash
pp list                                    # show registered projects
pp down anchor                             # sync down (alias + prefix resolution)
pp up petro                                # sync up
pp doctor wam                              # health check
pp solution-down energy                    # export solution
pp audit anchor --severity ERROR --exit-code  # run permissions audit
pp switch contoso-client                 # switch active project + pac auth
```

Full reference: [cli-reference.md](references/cli-reference.md). Subcommand resolution order is: exact name → alias → unique prefix → active project (`pp switch`).

**Detect whether the user has `pp` installed**:

```bash
command -v pp >/dev/null && pp list >/dev/null 2>&1
```

If yes, prefer `pp <op> <project>` over the per-project wrapper scripts. If no, fall back to wrapper scripts (or propose `~/.claude/plugins/cache/nq-claude-power-pages-plugins/pp-sync/<version>/install.sh` to install).

## When to apply

User says any of:
- "sync down / sync up the portal"
- "run acmedown / acmeup / sync-down-dev / sync-up-dev / contosodoctor / `*-doctor` / `*-commit`"
- "pull the portal", "push portal changes", "deploy portal", "upload to the portal"
- "pull / export the solution", "push / import the solution"
- "the portal is hung", "the portal cache is broken", "503 from the portal"

## Operations supported

| Operation | `pp` subcommand | Wrapper script alternative | Bare command fallback |
|---|---|---|---|
| **down** | `pp down` | `*-down.sh` / `*-paportal-down.sh` / `sync-down-dev.sh` | `pac paportal download --path . --webSiteId <id> --modelVersion <n>` |
| **up** | `pp up` | `*-up.sh` / `*-paportal-up.sh` / `sync-up-dev.sh` | `pac paportal upload --path . --modelVersion <n>` |
| **diff** | `pp diff` | (none) | `git diff` over the site folder + manual filtering |
| **doctor** | `pp doctor` | `*-doctor.sh` / `contosodoctor.sh` | manual checks (see `references/safety-checks.md`) |
| **generate-page** | `pp generate-page` | (internal template) | manual mkdir + copy |
| **sync-pages** | `pp sync-pages` | (internal logic) | manual copy between base and `content-pages/<lang>/` variants |
| **journal** | `pp journal` | (internal logic) | `gh` / `glab` / `git commit` |
| **solution-down** | `pp solution-down` | `*-solution-down.sh` | `pac solution export` then `pac solution unpack` |
| **solution-up** | `pp solution-up` | `*-solution-up.sh` | `pac solution pack` then `pac solution import` |
| **audit** | `pp audit` | (internal logic) | `python3 audit.py <site-dir>` |
| **commit** | _no `pp` subcommand_ | `templates/commit.sh` | `git status` + `git add -p` + `git commit` |
| **portal-restart** | _no `pp` subcommand_ | (none — admin center action) | Open Power Platform Admin Center → Restart |

## Mandatory checklist for ANY sync operation

Every operation begins with these steps. Do not skip.

### Step 1: Detect the project

Before running anything, identify which Power Pages project this is. See [project-detection.md](references/project-detection.md) for the full algorithm. Quick form:

1. `git rev-parse --show-toplevel` → repo root
2. Look for project-specific markers: `acme-down.sh`, `sync-down-dev.sh`, `contosodoctor.sh`, `divisions/<name>/pages/...`, `dataverse-schema/<solution>/`, `*.webpage.copy.html`
3. Read the project's CLAUDE.md if present — it defines the canonical script names, env URL, and any project-specific quirks
4. Identify the **site folder** — the `<site>---<site>/` directory containing `web-pages/`, `web-templates/`, `website.yml`. This is the sync target.

If you can't identify the project, **stop and ask the user**. Do not run sync against an unknown layout.

### Step 2: Confirm the operation

Show the user what you intend to run, including:

- The detected project name
- The detected site folder
- The wrapper script you'll invoke (or "bare pac" if none exists)
- The PAC auth profile that will be used
- The target environment URL (read from `pac org who`)
- For **up** operations: the file count that will be uploaded

Ask for confirmation **before** running any state-changing command. Down operations also need confirmation if the working tree has uncommitted changes that the download might overwrite.

### Step 3: Working-directory safety check

```bash
cd $(git rev-parse --show-toplevel)
```

**Never** `cd` into the site folder before downloading. Running `pac paportal download` inside `<site>---<site>/` creates a nested `<site>---<site>/<site>---<site>/` directory — the #1 PAC failure mode.

If the cwd ends with `---<name>/`, abort and `cd` to the parent.

### Step 4: Auth check

```bash
pac auth list                                       # verify the right profile is registered
pac auth select --name <profile>                    # select if not active
pac org who                                         # confirm env URL matches expectation
```

**The active PAC profile must match the project's intended environment.** When you have multiple PAC profiles registered (one per client engagement), cross-tenant accidents — signing into Project A while the working tree is for Project B — cause `pac paportal upload` to push code to the wrong portal. Read the URL from `pac org who` and confirm it matches the project's expected env URL before any upload.

If the profiles don't match, stop and ask the user which env they want.

### Step 5: Run the operation

Prefer wrapper scripts. They encode project-specific safety logic (path resolution, noise auto-stash, GCC vs Commercial branching) the bare `pac` commands lack.

Decision rule:

```
if a wrapper script for this operation exists in repo:
    invoke wrapper
else:
    fall back to bare pac (see references/direct-pac.md)
```

For each operation, the wrapper script naming pattern is in [wrapper-scripts.md](references/wrapper-scripts.md).

### Step 6: Post-flight

- For **down**: run `git status`. Show the user a summary of what changed. Recommend reviewing diffs before commit.
- For **up**: parse the `pac paportal upload` output for "uploaded N components" / errors. Report counts and any errors.
- For **solution-down**: confirm the unpack target dir contains expected entity folders.
- Always report **what the next sensible action would be** (commit, test, verify in browser).

## Critical safety rules

### Bulk uploads can hang the portal cache

Uploading many files at once (typically 100+) overwhelms Power Pages' cache layer. Symptoms: HTTP 000, 30-second hangs, 503. The portal needs a manual restart from Admin Center to recover.

**For any upload over ~50 files**:
1. Warn the user explicitly.
2. Recommend incremental upload (1-3 files per batch, verify between batches).
3. If the user insists on bulk, document the risk in the conversation and proceed.

See [safety-checks.md](references/safety-checks.md) for incremental-upload patterns.

### `--no-verify` is forbidden

Do not pass `--no-verify` to `git commit` or skip pre-commit hooks. If a hook fails, surface the failure and ask the user; don't bypass.

### Destructive options need explicit user confirmation

Any of the following require explicit user confirmation, not implicit:

- `git reset --hard`
- `git checkout -- <file>` (discards local changes)
- `pac paportal upload` (changes server state)
- `pac solution import` (changes Dataverse schema)
- `pac admin delete` (deletes environment — never run from this skill)
- Running operations against a profile whose env URL is `*prod*` or `*production*` — confirm twice

### Cross-tenant safety

Power Pages developers often have multiple PAC profiles registered — one per client engagement, plus dev/test/prod variants per engagement. The active profile in `pac auth list` (asterisk) determines where `pac paportal upload` pushes code.

A common shape:

- `<client-a>-dev` — your client A's dev env (commercial cloud)
- `<client-a>-prod` — same client's production env (commercial cloud)
- `<client-b>-client-dev` — client B's dev env (US government cloud — different sign-in, different admin URL)
- `<your-org>-dev` — your own organization's dev env

**Always print the active profile's env URL before any state-changing operation** so the user can confirm they're not about to push client A's code into client B's tenant. The most common cross-tenant accident is having one profile active in PAC while the working tree is for a different project.

### GCC (Government Cloud) operations

GCC environments need different admin URLs and have stricter auth flow:

| Aspect | Commercial | GCC |
|---|---|---|
| Admin Center | `admin.powerplatform.microsoft.com` | `admin.powerplatform.microsoft.us` |
| Sign-in | `login.microsoftonline.com` | `login.microsoftonline.us` |
| Web API host | `<env>.crm.dynamics.com` | `<env>.crm9.dynamics.com` (or `.us`) |

Detect GCC by env URL pattern (`crm9.dynamics.com` or `dynamics.us`). If GCC, use the GCC admin URL in any guidance you provide to the user.

## Reference files

- [cli-reference.md](references/cli-reference.md) — full `pp` CLI reference (commands, project resolution, config file format, CI integration)
- [project-detection.md](references/project-detection.md) — how to identify the active project and site folder when `pp` isn't set up
- [wrapper-scripts.md](references/wrapper-scripts.md) — three common naming patterns (project-prefix, env-suffix, verb-only) and what each wrapper typically does
- [direct-pac.md](references/direct-pac.md) — bare `pac paportal` and `pac solution` commands when no wrapper exists
- [safety-checks.md](references/safety-checks.md) — pre-flight, post-flight, incremental upload, recovery from hung portal
- [solution-sync.md](references/solution-sync.md) — `pac solution export/unpack/pack/import` workflow

## Templates (drop-in scripts for new projects)

This skill ships ready-to-use wrapper scripts in `templates/` that you can drop into any new Power Pages project. See [templates/README.md](../../templates/README.md) for installation instructions. The scripts handle:

- Working-directory and auth safety (cd to repo root, profile confirmation)
- Bulk-upload warnings (>50 files)
- Auto noise-stash on download
- Prod env double-confirmation
- Post-upload smoke test of the portal URL

When the user is in a project **without** existing wrappers, propose installing the templates:

```bash
PLUGIN_CACHE=~/.claude/plugins/cache/nq-claude-power-pages-plugins/pp-sync/<version>
cp $PLUGIN_CACHE/templates/*.sh /path/to/repo/
chmod +x /path/to/repo/*.sh
# then edit the CONFIG block at the top of each script
```

## What this skill does NOT do

- **Edit Liquid or JS files** — that's plain text editing, not a sync operation. Use the `pp-portal` skill for templating help.
- **Audit permissions** — use the `pp-permissions-audit` skill.
- **Configure Power Pages from scratch** — use Microsoft's `power-pages` plugin for site creation flows.
- **Manage Dataverse schema directly** — use the `dataverse` plugin (`dv-metadata`, `dv-solution`).
- **Run any operation without confirmation** — every state-changing command gets a confirmation prompt; that's not optional.
