# Wrapper Script Naming Patterns

Each Power Pages project tends to have its own family of wrapper scripts that encode project-specific safety logic (path handling, noise auto-stash, GCC vs Commercial branching, incremental upload). Always prefer the wrapper over bare `pac`, wrappers handle nuances the bare commands don't.

## Naming patterns

Three patterns dominate in production Power Pages projects:

| Pattern | Shape | Example filenames |
|---|---|---|
| **A. Project-prefix** | `<project>-<verb>.sh` | `acme-down.sh`, `acme-up.sh`, `acmedoctor.sh`, `acme-commit.sh` |
| **B. Environment-suffix** | `<verb>-<env>.sh` (one per env) | `sync-down-dev.sh`, `sync-up-dev.sh`, `sync-down-client-dev.sh`, `sync-up-client-dev.sh` |
| **C. Verb-only** | `<verb>.sh` | `down.sh`, `up.sh`, `doctor.sh`, `sync.sh` (the standalone templates this plugin ships) |

Pattern A is common for single-environment projects. Pattern B is common for projects deploying to two environments from one repo (dev + client). Pattern C is the simplest fallback and what the plugin's standalone `templates/*.sh` use.

Discover which is in use:

```bash
ls *.sh scripts/*.sh 2>/dev/null | grep -iE "(down|up|doctor|commit|sync|paportal|solution)"
```

## Operation → wrapper script mapping

| Operation | Pattern A (project-prefix) | Pattern B (env-suffix, dev branch) | Pattern B (env-suffix, client-dev branch) |
|---|---|---|---|
| Download portal | `acme-down.sh` | `scripts/sync-down-dev.sh` | `scripts/client-dev/sync-down-client-dev.sh` |
| Upload portal | `acme-up.sh` | `scripts/sync-up-dev.sh` | `scripts/client-dev/sync-up-client-dev.sh` |
| Doctor (health check) | `acmedoctor.sh` | `scripts/projectdoctor.sh` | `scripts/client-dev/client-dev-doctor.sh` |
| Commit (interactive) | `acme-commit.sh` | `scripts/project-commit.sh` | `scripts/client-dev/client-dev-commit.sh` |
| Solution download | `acme-solution-down.sh` | `scripts/project-solution-down.sh` | `scripts/client-dev/client-dev-solution-down.sh` |
| Solution upload | `acme-solution-up.sh` | `scripts/project-solution-up.sh` | `scripts/client-dev/client-dev-solution-up.sh` |
| Icons (if applicable) | (rare) | `scripts/project-icons-down.sh` / `-up.sh` | (matches main branch's wrappers) |

For projects without any wrappers, fall back to bare `pac paportal` (see [direct-pac.md](direct-pac.md)), or propose installing the plugin's `templates/*.sh` (Pattern C) as a starting point.

## What each wrapper typically does

### `*-down.sh` (Download)

```
1. cd to repo root (NEVER inside the site folder)
2. pac auth select to ensure right profile is active
3. pac org who, verify env URL
4. pac paportal download --path . --webSiteId <id> --modelVersion 2
5. Auto-restore known noise files (.portalconfig manifest, trailing whitespace in *.copy.html)
6. git status, show what actually changed
```

### `*-up.sh` (Upload)

```
1. cd to repo root
2. pac auth select
3. pac org who, confirm correct env
4. pac paportal upload --path . --modelVersion 2
5. Parse output for errors / warnings
6. Report counts: components uploaded, files skipped, errors
```

Some wrappers add validation (`--validateBeforeUpload`) for safety. Some add incremental upload (a loop that uploads N files at a time and pauses for the cache).

### `*doctor.sh` (Health Check)

```
1. Tooling check: pac, dotnet, git, jq versions
2. Auth check: pac auth list, pac org who
3. Structure check: site folder exists, web-pages/, web-templates/, website.yml present
4. Noise classifier: which files are noise vs real changes
5. Report
```

Doctor scripts are read-only, safe to run any time. Use them as the **first thing** before any uncertain sync operation.

### `*-commit.sh` (Interactive Commit)

```
1. git status -s
2. Prompt: stage all / patch / abort
3. Show diff stat
4. Prompt for commit message
5. git commit
6. Optional push prompt
```

These scripts often add timestamping or commit-message templates. Read the script to know what conventions apply.

### `*-solution-down.sh` (Solution Export + Unpack)

```
1. pac solution export --name <Solution> --path ./dataverse-schema/<Solution>.zip --managed false
2. pac solution unpack --zipfile <zip> --folder ./dataverse-schema/<Solution>
3. (sometimes) clean up zip after unpack
```

### `*-solution-up.sh` (Pack + Import)

```
1. pac solution pack --folder ./dataverse-schema/<Solution> --zipfile <Solution>.zip
2. pac solution import --path <Solution>.zip --publish-changes
```

Solution import is **destructive in-env**, it overwrites existing components in the target environment. Always confirm with the user before running.

## How to invoke a wrapper

Always run via the script's full or relative path; never assume it's in PATH:

```bash
cd $(git rev-parse --show-toplevel)
./acme-down.sh                                       # Pattern A: project-prefix
./scripts/sync-down-dev.sh                           # Pattern B: env-suffix (dev branch)
./scripts/client-dev/sync-down-client-dev.sh         # Pattern B: env-suffix (client-dev branch)
```

If a wrapper script lacks the executable bit, the user can `chmod +x` it. Don't `chmod` files implicitly without asking, file mode changes are a form of state mutation.

## Reading a wrapper before invoking

If you've never seen this wrapper before, read it first:

```bash
cat ./acme-down.sh                             # or whichever
```

Look for:
- What `cd` does it perform?
- What PAC profile does it assume / select?
- Does it `git stash` or `git checkout` anything destructively?
- Does it run `pac` with `--validateBeforeUpload`?
- Does it have GCC-specific branching?

If the wrapper does anything you don't expect, surface it to the user before running.

## When wrappers don't exist

For projects without wrappers (multi-division portfolios, new projects, freshly-cloned repos missing scripts), use bare `pac` commands with explicit safety checks. See [direct-pac.md](direct-pac.md).

It's also reasonable to **propose creating wrappers** modeled on Pattern A or B, they're 30-50 lines each and pay for themselves in the first week of use. The plugin's `templates/*.sh` (Pattern C) are a quick drop-in.
