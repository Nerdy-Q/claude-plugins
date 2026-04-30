# Project Detection

Before running any sync operation, identify which Power Pages project the user is working in. Different projects have different wrapper script names, different site folder names, and different PAC auth profiles.

## Detection algorithm

Run these checks in order. The first match wins.

### 1. Read project-specific CLAUDE.md (most authoritative)

```bash
cd $(git rev-parse --show-toplevel 2>/dev/null || pwd)
cat CLAUDE.md 2>/dev/null
```

Project CLAUDE.md files declare:
- Repo name and project board
- Site folder name (`<site>---<site>/`)
- Environment URL and Tenant ID
- PAC auth profile name
- Sync script names

If a `CLAUDE.md` is present at the repo root, **trust it as the source of truth**. The detection rules below are fallback heuristics for projects that don't have one yet.

### 2. Match by file signature (heuristic patterns)

| Repo signal | Likely project shape | Site folder location pattern | PAC profile pattern |
|---|---|---|---|
| `<prefix>-down.sh` at repo root | Single-portal, single-environment project (Pattern A wrapper family) | `<repo>/<prefix>-operations/<site>---<site>/` typical | `<prefix>-dev` or `<prefix>-client-dev` |
| `scripts/sync-down-dev.sh` AND branch `main` | Dual-environment project, dev branch (Pattern B wrapper family) | `<repo>/<site>---<site>/` at repo top level | `<project>-Dev` |
| `scripts/client-dev/sync-down-client-dev.sh` AND branch `client-dev` | Dual-environment project, client branch (Pattern B wrapper family) | `<repo>/client-dev/<site>---<site>/` | `<project>-Client-Dev` |
| `divisions/<name>/pages/<site>---<site>/` | Multi-division portfolio, one portal per business unit | `<repo>/divisions/<div>/pages/<site>---<site>/` | Often a single dev profile across all divisions |
| Bare `<site>---<site>/` with no scripts | Greenfield or one-off project | the bare folder | unknown, ask the user |

### 3. Generic fallback

If no project-specific signal matches, look for any directory matching the `<site>---<site>/` pattern with `web-pages/`, `web-templates/`, and `website.yml` inside. That's the site folder.

```bash
find . -maxdepth 4 -type d -name "*---*" 2>/dev/null \
  | while read d; do
      [ -f "$d/website.yml" ] && [ -d "$d/web-pages" ] && echo "$d"
    done
```

If exactly one match: use it. If multiple: ask the user. If zero: stop and ask whether this is a Power Pages project at all.

### 4. Multi-division portfolios

Some larger projects split multiple Power Pages sites across divisions or business units inside one repo:

```
<repo>/
├── cross-division/
├── divisions/
│   ├── <division-a>/
│   │   └── pages/
│   │       └── <site>---<site>/                              site folder for division A
│   ├── <division-b>/
│   │   └── pages/
│   │       └── <site>---<site>/                              site folder for division B
│   └── <division-c>/
│       └── pages/
│           └── <site>---<site>/                              etc.
```

For multi-division portfolios, **identify the specific division and site** before running sync. Each division may have its own portal in its own Dataverse environment, running `pac paportal upload` against the wrong division pushes code to the wrong site.

If the user says "sync the X division portal" or "deploy the Y site", route to the matching division's site folder. If ambiguous, ask.

## Confirming the project before any operation

Once detected, **always print** the following before running anything:

```
Detected project:    <name>
Repo root:           <path>
Site folder:         <site>---<site>/
PAC auth profile:    <profile>  (active: yes/no)
Environment URL:     <from `pac org who`>
Wrapper to invoke:   <script name>  (or "bare pac" if none)
```

Ask the user to confirm before running state-changing operations.

## Multi-environment workflows

Some projects deploy to two environments from the same repo (dev + client, or commercial + GCC). Branch names typically distinguish them:

| Branch | Env | Profile pattern | Folder under repo |
|---|---|---|---|
| `main` | Your dev env | `<project>-Dev` | `<site>---<site>/` (top-level) |
| `client-dev` | Client / downstream env | `<project>-Client-Dev` | `client-dev/<site>---<site>/` |

When syncing, **the active git branch determines which env** to target. If the user is on `main` but wants to sync the client env, ask them to checkout `client-dev` first, don't override branch implicitly.

For projects with `*-down.sh` and `*-down-client-dev.sh`, choose the script that matches the active branch.

## When detection is genuinely ambiguous

If you can't decide which project/env to operate against:

1. List all candidates (with the signals each one matched)
2. Ask the user to pick
3. Proceed only after explicit confirmation

Never guess, wrong guess on `up` operations pushes code to the wrong portal.
