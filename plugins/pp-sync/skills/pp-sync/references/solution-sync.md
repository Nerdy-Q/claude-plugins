# Dataverse Solution Sync

Power Pages portals consist of two parts:
1. **Portal source** (web-pages, templates, files), synced via `pac paportal download/upload`
2. **Dataverse schema** (entities, columns, plugins, optionsets), synced via `pac solution export/unpack`

This file covers part 2. For part 1 see [direct-pac.md](direct-pac.md) and [wrapper-scripts.md](wrapper-scripts.md).

## When to sync the solution

Solution sync is **separate from portal sync**. You generally need to sync the solution when:

- Schema changes (new tables, new columns, new optionsets) need to make it from one env to another
- You want the schema source-controlled in git
- Plugins (server-side C# logic) are being deployed
- A new env is being set up and needs to mirror an existing one's schema

Solution sync is **NOT needed** for:
- Pure Liquid / CSS / JS edits, those are portal source, not schema
- Adding a new web page in Studio, that's portal source
- Adding a Site Setting, those usually live in portal source (`site-settings/` in the site folder)

## Export → Unpack (download direction)

```bash
# 1. Find the solution unique name
pac solution list

# 2. Export
pac solution export \
  --name <SolutionUniqueName> \
  --path ./dataverse-schema/<Solution>.zip \
  --managed false                                   # always unmanaged for source control
```

`--managed false` is important: managed solutions can't be unpacked back into a source-controllable form. Always export unmanaged for dev work.

Common gotchas:

- **`--name` takes the unique name**, not the friendly name. `ContosoPrograms` not `"Contoso Programs Table"`.
- **Export takes 30-120 seconds** for non-trivial solutions. PAC will appear stuck, it's not.
- **Activity entities (Email, Phone Call, Task, Appointment) sometimes break export**. If export fails with activity errors, exclude activities by exporting a **slimmed solution**: create a new solution in Studio that contains only the entities you want, then export that.

```bash
# 3. Unpack into a directory tree
pac solution unpack \
  --zipfile ./dataverse-schema/<Solution>.zip \
  --folder ./dataverse-schema/<Solution> \
  --packagetype Unmanaged
```

Output structure:

```
dataverse-schema/<Solution>/
├── Entities/
│   ├── <table_name>/
│   │   ├── Entity.xml                              # entity metadata
│   │   ├── FormXml/                                # forms
│   │   ├── Views/                                  # saved queries
│   │   ├── PluginAssemblies/
│   │   └── ...
├── OptionSets/
│   └── <optionset_name>.xml
├── PluginAssemblies/                               # if plugins are in this solution
├── PluginTypes/
├── SdkMessageProcessingSteps/                      # plugin step registrations
├── Workflows/
├── Other/                                          # miscellaneous
└── solution.xml                                    # solution-level metadata
```

`<Solution>.zip` should be `.gitignore`'d, it's reproducible from the unpacked folder.

## Pack → Import (upload direction)

```bash
# 1. Pack the source-controlled folder back into a zip
pac solution pack \
  --folder ./dataverse-schema/<Solution> \
  --zipfile ./dataverse-schema/<Solution>.zip \
  --packagetype Unmanaged

# 2. Import to the target environment
pac solution import \
  --path ./dataverse-schema/<Solution>.zip \
  --publish-changes \
  --activate-plugins
```

`--publish-changes` is required for the imported components to be live (otherwise they're imported but not published). `--activate-plugins` does the same for plugin step registrations.

## Why solution import is the most destructive operation

Solution import **immediately and irreversibly**:

- Creates new tables, columns, optionsets in the target env
- Modifies existing tables/columns to match the imported version
- Registers new plugin assemblies and steps (running C# code in your env)
- Activates workflows (server-side automations)

There's no transaction wrapper. If import fails partway, the env is left half-imported.

**Before solution import**:

1. **Confirm the env URL**, `pac org who`. Wrong env = schema corruption in someone else's portal.
2. **Confirm the user wants this**, explicit confirmation, not implicit.
3. **For prod environments**, confirm twice. Suggest backing up first via Admin Center → Backups → Create.
4. **Have a rollback plan**:
   - For schema changes: restore from backup
   - For plugin changes: keep the previous solution version handy
   - For breaking column rename: prepare a column-restore plan in advance

## Two-environment promotion workflow

Common pattern: develop in your dev env, promote to client env.

```
Dev env (NQ tenant)              Client env (client tenant)
   │                                │
   │  1. pac solution export        │
   ↓                                │
   <Solution>.zip                   │
   │                                │
   │  2. pac solution unpack        │
   ↓                                │
   ./dataverse-schema/<Solution>/   │
   │                                │
   │  3. git diff, commit           │
   │                                │
   │  4. pac auth select <client>   │
   │                                ↓
   │  5. pac solution pack ────────→
   │                                │
   │  6. pac solution import        │
                                    │
                                    ↓
                                  Client env
```

Steps 4-6 happen with the client PAC profile active. Steps 1-3 with the dev profile.

## NQ vs GCC schema divergence

For projects deployed to both NQ Commercial and a State GCC client environment, the **same logical schema can drift**:

- Field names sometimes differ (e.g., a NQ column was created with one casing, the GCC one with another)
- Field types can differ (one env has `contoso_tankcapacitygallons` as `Edm.String`, another as `Edm.Decimal`)
- Default values, max lengths, requiredness can drift

Document divergence in a `SCHEMA_DIVERGENCE.md` file in `dataverse-schema/`. When promoting NQ → GCC:

1. Pack the NQ source
2. **Don't import directly**, review for any GCC-specific renames first
3. If GCC has different field names, you'll need to either:
   - Migrate GCC field names to match NQ (preferred for new fields)
   - Maintain a translation layer in your portal Liquid (acceptable for legacy fields you can't easily rename)

## Plugins (server-side C#) deployment

Plugins live in:
- `plugins/<PluginsProject>/`, your C# source
- `dataverse-schema/<Solution>/PluginAssemblies/`, the compiled binary metadata
- `dataverse-schema/<Solution>/SdkMessageProcessingSteps/`, when each plugin runs

Workflow:

```bash
# 1. Build C# plugin
cd plugins/<PluginsProject>
dotnet build -c Release

# 2. Use Plugin Registration Tool (PRT) or pac plugin register to update the assembly
pac plugin push --assembly <path-to-dll>

# 3. After registering, re-export the solution to capture plugin metadata
pac solution export ...

# 4. Commit the updated solution source
```

Plugins **deploy through the solution**, but **the assembly itself is uploaded separately** via `pac plugin push` or PRT. The solution carries the registration metadata; the assembly carries the bytes.

For projects with plugins, the `*-solution-up.sh` wrapper should:

1. Build C# (`dotnet build`)
2. Push assembly (`pac plugin push`)
3. Pack and import the solution

## Schema validation

After a solution import, smoke-test:

```bash
# List entities to confirm they imported
pac solution list

# Export back and diff against source, should be near-empty diff
pac solution export --name <Solution> --path /tmp/verify.zip --managed false
pac solution unpack --zipfile /tmp/verify.zip --folder /tmp/verify --packagetype Unmanaged
diff -r dataverse-schema/<Solution>/ /tmp/verify/ | head -50
```

Diff should show only Last Modified timestamps, GUID re-orderings, or other ignorable noise. Substantive differences mean the import didn't apply cleanly.

## Solution layering

For mature projects, consider **solution layering**: a base solution containing core schema, plus patches/extensions on top. This lets you ship schema changes incrementally without re-importing everything.

```
Contoso ProgramsCore               (base, unchanged for months)
  ├─ Contoso ProgramsExtension_v1  (patch, added a few fields)
  └─ Contoso ProgramsExtension_v2  (patch, added a few more)
```

Patches import faster and are less destructive. But they add complexity, for small projects, a single solution is simpler.

## Icons and assets in solutions

Some projects use Web Resources within Dataverse for shared icons / images that aren't part of the portal's `web-files/`:

```
dataverse-schema/<IconsSolution>/WebResources/
  ├── contoso_/icon-pen.svg
  ├── contoso_/icon-oil-can.svg
  └── ...
```

These are exported via the same `pac solution export` flow. For projects with separate icons solution (e.g., `contoso-icons-down.sh`), it's just another solution name in the same workflow.
