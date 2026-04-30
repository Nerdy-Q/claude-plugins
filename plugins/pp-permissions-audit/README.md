# pp-permissions-audit

A Claude Code skill that **audits a Power Pages classic portal's permissions configuration**, Web Roles, Table Permissions, Site Settings, Web API enablement, and custom JS, to find misalignments and security risks.

## What this is

A **knowledge + analytical skill**. The skill ships a stdlib-only Python script that reads YAML and JS files, cross-references findings, and emits a markdown (or JSON) report of issues with severity levels (ERROR / WARN / INFO). The model interprets findings and proposes fixes, but never auto-applies them.

## What it catches

All 25 checks shipped by `audit.py`. Authoritative definitions in `audit.py`; this table is a navigation aid.

### ERROR (4): security risks or blockers

| Code | Finding |
|---|---|
| ERR-001 | Web API enabled but no Table Permission grants Read |
| ERR-002 | Orphaned Table Permission (no Web Roles assigned) |
| ERR-003 | Anonymous Users role granted Write/Create/Delete on a sensitive table |
| ERR-004 | `Webapi/<entity>/Fields` explicitly whitelists secured readable field(s) |

### WARN (12): likely bugs or risks

| Code | Finding |
|---|---|
| WRN-001 | Custom JS uses `<lookup>@odata.bind` without `_contact` / `_account` suffix on a polymorphic field, runtime 400 risk |
| WRN-002 | Web Role exists but no Table Permission references it |
| WRN-003 | Sitemarker referenced in Liquid but not defined |
| WRN-004 | Custom JS calls `/_api/` without anti-forgery token pattern, runtime 403 risk |
| WRN-005 | `<nav>@odata.bind` uses all-lowercase navigation property, likely a Logical Name where Navigation Property was needed |
| WRN-006 | `$select=<field>` in custom JS references a field that does not exist on the entity (verified against `dataverse-schema/`) |
| WRN-007 | FetchXML `<attribute name=>` references a field that does not exist on the root entity |
| WRN-008 | `Webapi/<entity>/Fields` lists field(s) that do not exist on the entity (stale or typo) |
| WRN-009 | `Webapi/<entity>/Fields = *` is used on an entity with secured readable fields |
| WRN-010 | Content Snippet referenced in Liquid but not defined |
| WRN-011 | Possible sensitive Site Setting exposed (looks like a secret or API key) |
| WRN-012 | Entity Form references a field that does not exist on the entity |

### INFO (9): observations and quality

| Code | Finding |
|---|---|
| INFO-001 | Table Permission allows Read but Web API isn't enabled (would 404) |
| INFO-002 | `Webapi/<entity>/Fields = *` exposes all fields (consider narrowing) |
| INFO-003 | Page requires auth but no role rule (any authenticated user can see) |
| INFO-004 | Role-permission junction not exported, role-aware checks skipped |
| INFO-005 | Page has empty base file but populated localized file, base-vs-localized blank-page bug |
| INFO-006 | `{% fetchxml %}` missing `count` attribute, performance |
| INFO-007 | Unsafe DotLiquid JSON escape, `replace: '"', '\\"'` produces 3 chars |
| INFO-008 | Possible N+1 query pattern in Liquid (`fetchxml` or `entities[...]` inside a `{% for %}`) |
| INFO-009 | Diverged base/localized files, sizes differ significantly |

## Run it directly

```bash
python3 <skill-cache>/scripts/audit.py <site-folder>
python3 <skill-cache>/scripts/audit.py <site-folder> -o report.md
python3 <skill-cache>/scripts/audit.py <site-folder> --json
```

The skill knows where the cached `audit.py` lives and will invoke it automatically when you ask it to audit a portal.

## Reference files

- `references/checks.md`, full list of audit checks with codes and trigger conditions
- `references/interpreting.md`, how to interpret each finding type, false-positive cases, when to act
- `references/remediation.md`, how to fix each finding type
- `references/api-config.md`, Power Pages Web API site setting reference (deep)
- `CI.md`, GitHub Actions / Azure Pipelines / pre-commit hook integration
- `examples/github-actions/power-pages-audit.yml`, drop-in workflow template
- `examples/git-hooks/`, git pre-commit hook template + installer (blocks commits on ERROR-class findings)

## What it catches in production

Smoke-tested against multiple real Power Pages portals (commercial + USGov, single-environment + dual-environment dev/client, single-portal + multi-division). Representative findings from those runs:

- **ERR-001** (Web API enabled with no Table Permission), common when site settings get added eagerly during dev but the matching permission never gets configured. Typical run: 5–20 findings per portal.
- **ERR-004 / WRN-009** (secured readable fields exposed through an explicit whitelist or wildcard), catches field-level security exposure risk when `dataverse-schema/` is present and the entity metadata marks fields as both secured and API-readable.
- **INFO-002** (`Webapi/<entity>/Fields = *` wildcards), common when permissions are set up via Studio defaults. Often 100+ findings on portals with many entities.
- **WRN-001** (polymorphic lookup without `_contact` / `_account` suffix), pre-empts a 400 Bad Request at runtime. Caught a real bug on a customer-type lookup that would have shipped to a production form.
- **WRN-004** (custom JS calling `/_api/` without anti-forgery token), pre-empts a 403. Caught files where the safeAjax pattern was missing.
- **INFO-005** (base-vs-localized file divergence), the canonical "page renders blank" bug. Caught half a dozen on a single portal.

The pre-emptive bug detection (WRN-001, WRN-004, INFO-005) is the kind of catch this skill is most valuable for, these would otherwise show up as runtime errors after deploy.

## What this skill does NOT do

- **Auto-apply fixes**, every fix is proposed to the user, not applied automatically. Permissions changes affect security; the user must approve each one.
- **Live-query Dataverse**, this is static analysis of local site source. It can't verify whether a Web Role is actually assigned to specific Contacts (that lives in Dataverse). For live verification, use the `dataverse` plugin (`dv-query`).
- **Audit Dataverse-side security**, System User roles, security roles on entities, business unit boundaries are out of scope. This skill audits the **portal layer** only.
- **Audit code sites** (React/Vue/Astro SPAs), different security model, different config files. NOT supported.

## Dependencies

- Python 3.7+
- Stdlib only (PyYAML used opportunistically if installed; falls back to a hand-rolled parser otherwise)

## License

MIT
