# Power Pages Sync Workflow

Power Pages source code lives in **Dataverse**, not your repo. The dev loop is:

```
pac paportal download → edit locally → commit → pac paportal upload → test in browser
```

Naive `pac paportal download` is non-deterministic, it regenerates files with timestamp drift, GUID reordering in `.portalconfig/`, and occasional whitespace churn. Production projects wrap it in shell scripts that auto-stash known noise so only meaningful diffs reach git.

## Authentication

Authenticate `pac` first:

```bash
pac auth list
pac auth select --name <profile-name>
pac org who                                        # confirm right env
```

If the env URL prints to stdout, you're authenticated. For multiple environments (dev/test/prod), keep one PAC profile per env, switch with `pac auth select`.

## Bare PAC commands

```bash
# Discover the website ID for the env
pac paportal list

# Download, REQUIRES website-id arg (you'll get this from `list`)
pac paportal download --path . --webSiteId <website-id> --modelVersion 2

# Upload (uploads everything new/modified relative to last sync)
pac paportal upload --path . --modelVersion 2

# Validate the local manifest matches what's on the server
pac paportal upload --path . --modelVersion 2 --validateBeforeUpload
```

`--modelVersion 2` is the Enhanced data model, required for any portal created in 2023 or later. Older portals use `--modelVersion 1`.

## Why you need a wrapper script

Plain `pac paportal download` produces ~2-5% noise on every run:

- `.portalconfig/manifest.yml` reorders dependency arrays
- `*.webpage.copy.html` files lose/gain trailing whitespace
- File-level YAML reorders fields alphabetically vs source-order
- Sometimes regenerates `.copy.html` from `.summary.html` even when the latter wasn't touched

Without a wrapper, every `git status` looks like 30 changed files with 2 real edits. With a wrapper:

```bash
sync-down-dev.sh                                   # download + auto-stash known noise
git status                                         # only real changes show
git add . && git commit -m "..."
sync-up-dev.sh                                     # upload
```

## Wrapper script anatomy

A typical wrapper:

```bash
#!/usr/bin/env bash
# sync-down-dev.sh, download portal, then auto-stash noise

set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
SITE_DIR="contoso---contoso"
PROFILE="contoso-dev"

cd "$ROOT"

# 1. Auth check
pac auth select --name "$PROFILE" >/dev/null
pac org who >/dev/null

# 2. Download, but never inside the site folder (that produces nested folders)
echo "Downloading portal…"
pac paportal download --path . --webSiteId "$WEBSITE_ID" --modelVersion 2

# 3. Auto-restore known noise files
echo "Stashing PAC noise…"

# .portalconfig/ reorders deterministically, restore from main if only ordering changed
git checkout HEAD -- .portalconfig/ 2>/dev/null || true

# .copy.html trailing-whitespace-only changes, strip and re-check
find "$SITE_DIR" -name "*.webpage.copy.html" -exec sed -i '' -e 's/[[:space:]]*$//' {} +

# 4. Show what's actually changed
git status

echo "Done. Review changes before commit."
```

```bash
#!/usr/bin/env bash
# sync-up-dev.sh, upload changes

set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
PROFILE="contoso-dev"

cd "$ROOT"

pac auth select --name "$PROFILE" >/dev/null

echo "Uploading…"
pac paportal upload --path . --modelVersion 2

echo "Done. Test in browser."
```

```bash
#!/usr/bin/env bash
# *-doctor.sh, health check

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

echo "=== Tooling ==="
which pac && pac --version
which dotnet && dotnet --version

echo "=== Auth ==="
pac auth list

echo "=== Local structure ==="
test -d "$SITE_DIR/web-pages" && echo "OK: web-pages exists"
test -f "$SITE_DIR/website.yml" && echo "OK: website.yml exists"

echo "=== Noise classifier ==="
git status --porcelain | awk '{print $2}' | sort | uniq -c | sort -rn | head -20
```

```bash
#!/usr/bin/env bash
# *-commit.sh, interactive selective commit

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

git status -s
read -p "Stage all? [y/N/p(atch)] " ans
case "$ans" in
  y|Y) git add -A ;;
  p|P) git add -p ;;
  *)   echo "Aborted"; exit 1 ;;
esac
git diff --cached --stat
read -p "Commit message: " msg
git commit -m "$msg"
read -p "Push? [y/N] " push
[ "$push" = y ] && git push
```

## Critical workflow rules

### NEVER run `pac paportal download` inside the site folder

```bash
# DON'T:
cd contoso---contoso/
pac paportal download …

# DO:
cd $(git rev-parse --show-toplevel)
pac paportal download --path .
```

Running inside the site folder creates a **nested** `contoso---contoso/contoso---contoso/` directory. This is the #1 PAC failure mode. Wrappers should always `cd` to the repo root before downloading.

### `.git` lives at the repo root, not inside the site folder

```
ContosoPortal/                                   ← .git lives HERE
├── .git/
├── contoso---contoso/                 ← site folder
│   ├── web-pages/
│   ├── web-templates/
│   └── ...
└── scripts/
```

Never move `.git` inside the site folder. PAC's download regenerates the site folder freely; if `.git` is there it gets clobbered.

### Site folder name is fixed by Power Pages: never rename

The site folder is `<website-name>---<website-name>/`. Power Pages sets this at site creation; renaming it breaks `pac paportal upload` (which uses the folder name as a sync key).

## Portal cache hangs after bulk uploads

Uploading many records at once (100+) can overwhelm Power Pages' cache layer. Symptoms:

- HTTP 000 (timeout) from the portal URL
- 30-second hangs followed by 503
- Pages render but custom CSS/JS missing
- Studio preview fails

The portal service is alive but unresponsive. **Recovery:**

1. Open Power Platform Admin Center:
   - Commercial: `admin.powerplatform.microsoft.com`
   - GCC: `admin.powerplatform.microsoft.us`
2. Find the portal → Restart
3. After restart, optionally Purge cache from Admin Center
4. Wait, may get 503 briefly during cache rebuild
5. Verify in browser

**Prevention**: upload incrementally (1-3 files at a time), verify the portal loads between each batch. Wrapper scripts with `--maxFiles N` or per-table chunking help here.

## PAC stale manifest errors

After deleting records on the server (basic forms, table permissions, web pages) without removing them locally, every `pac paportal upload` shows errors like:

```
PowerPageComponentDeletePlugin: <name> not found
adx_entitypermission not found: <id>
```

These are **cosmetic**, the upload still succeeds for valid files. But they pollute logs and can mask real errors.

**Fix**: delete the orphaned local files (the YAML metadata for deleted records) and commit. Wrapper script for this:

```bash
# Detect orphaned files: locally-existing YAMLs whose IDs aren't in the latest server manifest
pac paportal download --path /tmp/pac-fresh --webSiteId "$WEBSITE_ID" --modelVersion 2

# Find files that exist locally but not in fresh download
diff -rq "$SITE_DIR" "/tmp/pac-fresh/$SITE_DIR" | grep "Only in $SITE_DIR" | awk '{print $4}'
```

Then manually `rm` and commit.

## Commercial vs GCC differences

GCC (US Government Cloud) portals have these differences from Commercial:

| Aspect | Commercial | GCC |
|---|---|---|
| Admin Center | `admin.powerplatform.microsoft.com` | `admin.powerplatform.microsoft.us` |
| Web API host | `<env>.crm.dynamics.com` | `<env>.crm9.dynamics.com` (sometimes `.us`) |
| Sign-in tenant | usually Commercial Entra | Government Entra (different login URL) |
| CSP requirements | standard | requires GCC-specific domains: `gov.content.powerapps.us`, `content.powerapps.us`, `content.appsplatform.us` |
| Authentication endpoint | `login.microsoftonline.com` | `login.microsoftonline.us` |

Wrapper scripts that target both clouds should branch on the env URL or take a `--cloud commercial|gcc` flag.

## Schema export workflow

Separate from portal sync, Dataverse table/column metadata exports as a **solution**:

```bash
# Export
pac solution export \
  --name <SolutionName> \
  --path ./dataverse-schema/<SolutionName>.zip \
  --managed false

# Unpack zip into source-controllable directory
pac solution unpack \
  --zipfile ./dataverse-schema/<SolutionName>.zip \
  --folder ./dataverse-schema/<SolutionName>
```

Wrap in a `*-solution-down.sh`:

```bash
#!/usr/bin/env bash
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
SOLUTION="<SolutionName>"
pac solution export --name "$SOLUTION" --path "./dataverse-schema/${SOLUTION}.zip" --managed false
pac solution unpack --zipfile "./dataverse-schema/${SOLUTION}.zip" --folder "./dataverse-schema/${SOLUTION}"
echo "Solution unpacked. Review changes."
```

## Two-environment workflow (dev → client)

For projects where you develop in your own dev env and deploy to a client env (same site, different tenant):

- Use **two git branches**: `main` (your dev), `client-dev` (client env)
- Each branch has its own PAC profile
- Sync down to `main` from your dev, sync up to client from `client-dev`
- Apply changes from `main` → `client-dev` via `git cherry-pick` or `git checkout main -- <files>`
- Always upload to the client env **incrementally** (1-3 files per batch), bulk uploads hang the cache (see above)
