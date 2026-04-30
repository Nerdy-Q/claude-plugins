# Safety Checks: Pre-flight, Post-flight, Recovery

Sync operations against a live portal are **stateful** and partially irreversible. These checks protect against the most common ways a sync goes wrong.

## Pre-flight (before any operation)

### Check 1: Working directory

```bash
cd $(git rev-parse --show-toplevel 2>/dev/null || pwd)
basename "$PWD"                                     # should NOT end with ---<name>
```

If the cwd matches `*---*` (the site-folder pattern) you're inside the site folder. Move up one level. Running `pac paportal download` here creates a nested copy.

### Check 2: Auth profile

```bash
pac auth list
pac org who
```

Two failure modes:

- **No active profile** (no asterisk in `pac auth list`), `pac org who` fails. Run `pac auth select --name <profile>`.
- **Wrong profile active**, env URL doesn't match what the user expects. Confirm before continuing.

### Check 3: Working tree state (for download)

```bash
git status -s
```

If the working tree has uncommitted changes, `pac paportal download` may overwrite them. Either:

- Commit first: `git commit -am "checkpoint before sync"`
- Stash: `git stash push -m "before sync"`
- Confirm with the user that the changes are expected to be overwritten

### Check 4: Branch state (for projects with multi-env branches)

```bash
git branch --show-current
```

For projects where branch determines the target env:
- `main` → dev env
- `client-dev` → client env

If the active branch doesn't match the target env, ask the user to checkout the right branch first. **Never** override branch implicitly.

### Check 5: Site folder structure

```bash
SITE_DIR=<site>---<site>
test -f "$SITE_DIR/website.yml" && \
test -d "$SITE_DIR/web-pages" && \
test -d "$SITE_DIR/web-templates" && \
echo "OK" || echo "BROKEN, repair before sync"
```

If the site folder is missing core directories, the previous sync may have failed mid-way. Don't pile another sync on top, investigate first.

### Check 6: Pending PAC noise

```bash
git status -s | head -20
```

If there are dozens of changed files all in `.portalconfig/` or with whitespace-only diffs, a previous download left noise. Run the project's `*-doctor.sh` if available, or manually clean:

```bash
git checkout HEAD -- .portalconfig/
find <site-dir> -name "*.webpage.copy.html" -exec sed -i '' -e 's/[[:space:]]*$//' {} +
git status                                          # verify cleanup
```

## Post-flight (after any operation)

### After download:

```bash
git status -s | wc -l                               # how many files changed
git diff --stat | tail -1                           # summary
```

Report to the user:
- File count
- Major directories affected (web-pages, web-templates, table-permissions, etc.)
- Whether any deletions happened (records removed on the server)
- Recommended next action: review diffs, commit, or run another sync if something looks off

### After upload:

```bash
# Wait briefly for the portal to digest (cache warm-up)
sleep 5

# Smoke-test the portal URL
curl -sI "https://<portal-url>/" | head -1
```

A 200 means the portal is up. A 503 means cache is rebuilding (normal for ~30s after upload). A 502/504 means the cache is hung, see Recovery below.

### After solution-down:

```bash
ls ./dataverse-schema/<Solution>/Entities/ | wc -l   # entity count, sanity check
```

If the entity count is wildly different from what you expect, the solution may not contain what you thought. Investigate.

## Bulk upload: safety pattern

Power Pages can hang the portal cache if you upload too many files at once. Empirical thresholds:

| File count | Risk | Recommendation |
|---|---|---|
| 1-30 | Low | Single upload OK |
| 30-50 | Moderate | Single upload usually OK; watch for warnings |
| 50-100 | High | Strongly recommend incremental |
| 100+ | Very high | **Must** upload incrementally |

### Incremental upload pattern (manual)

```bash
# 1. Identify what would be uploaded
git diff --name-only HEAD~1 HEAD | grep -v ".portalconfig/" | head -100

# 2. Stash everything except a small batch
git stash --keep-index                              # stash unstaged
# (repeat upload + verify cycle)
```

### Incremental upload pattern (semi-automated)

If your wrapper script supports it, prefer wrapper-driven incremental upload. If not, propose adding a wrapper that batches uploads by directory:

```bash
for dir in basic-forms advanced-forms entity-lists web-templates web-files content-snippets web-pages page-templates table-permissions web-roles site-settings sitemarkers; do
  echo "=== Syncing $dir ==="
  # Power Pages has no native subset upload, so this is conceptual.
  # In practice, you partition via stash-and-pop or by chunking commits.
done
```

## Recovery: portal cache hung

Symptoms:

- HTTP 000 (timeout) from the portal URL
- 30-second hangs followed by 503
- Pages render but custom CSS/JS missing
- Studio preview fails / hangs
- Subsequent `pac paportal upload` runs return errors immediately

The portal service is **alive** but the cache is jammed.

### Recovery steps:

1. **Open Power Platform Admin Center**:
   - Commercial: `admin.powerplatform.microsoft.com`
   - GCC: `admin.powerplatform.microsoft.us`
2. Navigate to **Resources → Power Pages sites**
3. Find your site in the list
4. Click the site → **Restart**
5. Optionally, **Purge cache** from the same admin page
6. Wait ~30-60 seconds. Expect 503 briefly during cache rebuild.
7. Verify in browser: load the portal homepage. Should return 200.

### Why this happens

The Power Pages cache layer pre-loads compiled Liquid templates and metadata at site start. Bulk uploads overwhelm the recompile queue, leading to a state where the cache is stuck mid-rebuild. Restart drains the queue and rebuilds from scratch.

### Prevention

- Upload incrementally (see above)
- Verify between batches by loading a portal page in the browser
- Avoid uploading during peak portal usage hours
- For the largest changes (e.g., a new design system rollout), schedule a maintenance window

## Recovery: accidental upload to wrong env

If a user accidentally uploaded to a prod or client env instead of dev:

1. **Don't panic-restore from PAC.** Power Pages doesn't have native rollback.
2. **Identify what changed.** Use the Power Pages Studio version history if enabled.
3. **Revert via re-download from the *correct* env, then re-upload to the wrong one**, i.e., overwrite the bad upload with the good config from the right env.
4. For schema (Dataverse) changes via solution import, restore from the most recent backup. Power Platform Admin Center → environment → Backups.

This is why pre-flight env confirmation matters. Catching the wrong-env at confirmation time is free; catching it after a prod upload is expensive.

## Recovery: corrupted local state

If `pac paportal upload` keeps reporting bizarre errors and your local site folder looks weird:

1. Stash or commit anything you don't want to lose
2. Delete the entire site folder (`rm -rf <site>---<site>/` and `rm -rf .portalconfig/`)
3. Re-download from scratch (`pac paportal download ...`)
4. Re-apply your local changes from the stash/commits selectively

This is the "nuclear restart", last resort, but reliable.
