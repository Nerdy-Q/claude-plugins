# Direct `pac` Commands (Fallback When No Wrapper Exists)

When a project has no wrapper scripts, fall back to bare `pac` commands. These are the "manual" sync flows, every step explicit, every safety check is on you.

## Prerequisites

```bash
pac --version                                       # confirm PAC CLI installed (no --version arg; bare `pac` prints banner)
pac auth list                                       # see registered profiles
pac auth select --name <profile>                    # activate the right profile
pac org who                                         # confirm env URL
```

If `pac` is not installed, see [setup-tools.md] elsewhere or install via:
- macOS: `brew install --cask powerplatform-cli`
- Windows: `winget install Microsoft.PowerPlatformCLI`
- Linux: download from learn.microsoft.com/power-platform/developer/cli/introduction

## Discovering the website ID

`pac paportal download` requires `--webSiteId` (a GUID). Find it:

```bash
pac paportal list                                   # lists portals on the active env with their IDs
```

Output looks like:

```
Site Name                          Website ID                              Active
Acme Portal                          00000000-0000-0000-0000-000000000000    Yes
```

Cache the website ID in a project's CLAUDE.md or in an `.env` so it's not re-discovered each time.

## Determining the model version

Power Pages portals come in two data model versions:

| Model Version | Used by | Detection |
|---|---|---|
| 1 (Standard) | Older portals (pre-2023) | Studio shows "Standard" / no Code Sites option |
| 2 (Enhanced) | Newer portals (2023+) | Studio shows "Enhanced" / Code Sites available |

Check the model version in Power Pages Studio → Settings → Site Details, or in `website.yml`:

```yaml
adx_modelversion: 2                                 # 2 = Enhanced
```

All sync commands need `--modelVersion <n>` matching the portal. Wrong value silently produces partial syncs.

## Download (sync-down)

```bash
cd $(git rev-parse --show-toplevel)                 # CRITICAL: not inside site folder

pac paportal download \
  --path . \
  --webSiteId <guid> \
  --modelVersion 2
```

What this produces:

- Site folder: `<site>---<site>/` with `web-pages/`, `web-templates/`, `web-files/`, `content-snippets/`, `page-templates/`, `table-permissions/`, `web-roles/`, `site-settings/`, `sitemarkers/`, `basic-forms/`, `advanced-forms/`, `entity-lists/`, `website.yml`
- `.portalconfig/` directory with manifests and snapshots

Common post-download cleanup:

```bash
# 1. Restore .portalconfig if only ordering changed
git checkout HEAD -- .portalconfig/ 2>/dev/null || true

# 2. Strip trailing whitespace in *.copy.html (PAC adds it non-deterministically)
find <site-folder> -name "*.webpage.copy.html" -exec sed -i '' -e 's/[[:space:]]*$//' {} +
# Linux: sed -i (no '')

# 3. Show what actually changed
git status
```

## Upload (sync-up)

```bash
cd $(git rev-parse --show-toplevel)

pac paportal upload \
  --path . \
  --modelVersion 2
```

`pac paportal upload` is **incremental**, it uploads only files changed since the last sync. The local manifest tracks state.

For safety, always preview first:

```bash
pac paportal upload \
  --path . \
  --modelVersion 2 \
  --validateBeforeUpload
```

This validates without committing, so you can catch reference errors before they hit the server.

For projects with **>50 changed files** about to upload, do it incrementally to avoid hanging the portal cache. There's no built-in `--batch-size` flag, use git or directory-level batching:

```bash
# Example: upload one entity set at a time
for entity in basic-forms advanced-forms entity-lists web-templates; do
  echo "Syncing $entity"
  # No clean way to scope `pac paportal upload` to a subset, so the workaround
  # is git-stash everything else, upload, unstash next batch.
  # Wrappers handle this; bare pac doesn't.
done
```

If bulk upload is unavoidable and the portal hangs, see [safety-checks.md](safety-checks.md) for recovery.

## Solution export and unpack

```bash
# 1. Export
pac solution export \
  --name <SolutionUniqueName> \
  --path ./dataverse-schema/<Solution>.zip \
  --managed false                                   # always unmanaged for source control
```

Find solution unique names with:

```bash
pac solution list
```

Note: `--name` takes the **unique** name (e.g., `ContosoPrograms`), not the friendly name (e.g., "Contoso Programs Table"). They're often similar but not identical.

```bash
# 2. Unpack into source-controllable dir
pac solution unpack \
  --zipfile ./dataverse-schema/<Solution>.zip \
  --folder ./dataverse-schema/<Solution> \
  --packagetype Unmanaged
```

After unpack, the folder contains:

```
<Solution>/
├── Entities/
│   ├── <entity1>/
│   │   ├── Entity.xml
│   │   ├── FormXml/
│   │   ├── Views/
│   │   └── ...
├── OptionSets/
├── PluginAssemblies/
├── PluginTypes/
├── SdkMessageProcessingSteps/
├── Workflows/
├── Other/
└── solution.xml
```

Commit this. The `.zip` file should be `.gitignore`'d, it's reproducible from the unpacked folder.

## Solution pack and import

```bash
# 1. Pack
pac solution pack \
  --folder ./dataverse-schema/<Solution> \
  --zipfile ./dataverse-schema/<Solution>.zip \
  --packagetype Unmanaged

# 2. Import (destructive, overwrites in-env)
pac solution import \
  --path ./dataverse-schema/<Solution>.zip \
  --publish-changes \
  --activate-plugins
```

Solution import is **the most destructive operation in this skill**. It changes Dataverse schema in the target environment immediately. Always:

1. Confirm the active PAC profile is correct (`pac org who`)
2. Confirm the user wants this
3. For prod environments, confirm twice
4. Have a rollback plan (recent backup, or solution layering / patch versions)

Recommend importing to a non-prod env first, testing, then promoting.

## Cleaning up after a sync

After a successful download:

- `git status`, review changes
- `git diff`, read meaningful diffs
- Discard noise (PAC reordering, whitespace) before commit
- Commit only when changes reflect intent

After a successful upload:

- Verify in browser by visiting the portal URL
- Check for 5xx in Power Platform Admin Center → site → metrics
- If a published page renders blank, check base vs localized file sync (see `pp-portal` skill, `references/pages/hybrid-page-idiom.md`)

## Auth troubleshooting

```bash
pac auth list                                       # any profiles? right one active?
pac auth select --name <profile>                    # if not active
pac org who                                         # confirm URL

# If no profiles exist OR you need a new one:
pac auth create --name <name> --environment <env-url>
```

For service principal auth (CI/CD only, not for daily dev):

```bash
pac auth create \
  --name <name> \
  --tenant <tenant-id> \
  --applicationId <client-id> \
  --clientSecret <secret> \
  --environment <env-url>
```

Service principal auth doesn't work for `pac paportal upload` to portals, the portal layer requires interactive user auth. Use SP auth only for `pac solution import` and Dataverse Web API.
