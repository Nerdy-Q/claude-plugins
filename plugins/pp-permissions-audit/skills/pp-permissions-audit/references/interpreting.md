# Interpreting Audit Findings

The audit identifies *misalignments* statically. Whether each one is a real bug, a false positive, or an intentional config depends on the project's intent. This file gives interpretation guidance for each finding code.

## ERR-001 — Web API enabled but no Table Permission

**Likely real**: Yes. Most actionable error.

**What it means**: `Webapi/<entity>/Enabled = true` exists in `site-settings/`, but no Table Permission in `table-permissions/` allows Read on this entity. If anything calls `/_api/<entity>` from the portal it will 401 / 403.

**False-positive cases**:
- Permission exists in Power Pages Studio but isn't yet exported to YAML (run `pac paportal download` to refresh).
- Role-permission junction is in a separate file the audit doesn't read (rare; see INFO-004).

**To verify**: Check if any custom JS in `web-pages/**/*.webpage.custom_javascript.js` references this entity. If not, the Web API setting may be **dead config** — safe to remove.

## ERR-002 — Orphaned Table Permission

**Likely real**: Yes (when the export format includes the role junction; otherwise audit emits INFO-004 instead).

**What it means**: Permission YAML exists with valid entity and operations, but `adx_entitypermission_webrole` is empty. Permission applies to nobody.

**False-positive cases**: Studio has the permission assigned to a role, but the assignment didn't make it into the YAML export. Re-run `pac paportal download` to refresh.

**To verify**: Open the Power Pages Studio and check the permission's Web Roles tab. If a role IS assigned there, the export is stale; re-download.

## ERR-003 — Anonymous role with Write/Create/Delete

**Likely real**: Yes — but always intentional or always a bug. Manual review needed.

**What it means**: An unauthenticated visitor can perform a write operation on this table.

**Intentional cases**:
- Public contact form (anonymous Create on `contact`)
- Public ticket submission (anonymous Create on a custom table)
- Lead capture (anonymous Create on `lead`)

For these, ensure:
- The `Webapi/<entity>/Fields` whitelist is **narrow** (do not allow `*`)
- Captcha / bot protection is configured at the form level
- The permission allows Create only — not Read, Write, or Delete

**Unintentional cases**:
- A permission was duplicated and one copy kept the anonymous role flag
- The Anonymous Users implicit role got added to a permission unintentionally

## WRN-001 — Polymorphic lookup without disambiguator

**Likely real**: Maybe. Heuristic match — verify against schema.

**What it means**: Custom JS does `<lookup>@odata.bind` and the lookup name suggests it might be a polymorphic (customer-type) field. Polymorphic fields require the `_contact` or `_account` suffix, e.g. `contoso_Applicant_contact@odata.bind`.

**To verify**:
1. Open `dataverse-schema/<solution>/Entities/<entity>/Entity.xml`
2. Look for `<attribute PhysicalName="<lookup>"`
3. If `Type="customer"`, the field is polymorphic — fix is needed
4. If `Type="lookup"` with a single target, the bare binding is fine — false positive

**Fix when real**: Determine which type (Contact or Account) is being referenced and use the corresponding suffix.

## WRN-002 — Web Role with no Table Permission references

**Likely real**: Yes for stale roles, false-positive for "structural" roles.

**What it means**: A Web Role exists in `webrole.yml` but no Table Permission's role list includes this role's GUID. The role grants no record-level access.

**False-positive cases**:
- The role grants page-level access only (via Web Page Access Control Rules) — it doesn't need Table Permissions
- The role is for an external integration (e.g., a Web Role that's only used in the portal's authentication policy, not for data access)

**To verify**: Search `web-pages/**/*.webpage.yml` and `webpagerule.yml` (if present) for the role's GUID. If found, the role has page-level use and can be ignored. Otherwise, consider removing the role.

## INFO-001 — Permission without Web API

**Likely real**: Often intentional.

**What it means**: A Table Permission grants Read but no `Webapi/<entity>/Enabled` site setting exists. Server-side FetchXML in Liquid templates can use this permission; client-side `/_api/` cannot.

**Action**: No action needed if all access is via Liquid FetchXML. If you intend to call `/_api/<entity>` from custom JS, add the site setting (and a `Webapi/<entity>/Fields` whitelist).

## INFO-002 — `fields = *` whitelist

**Likely real**: Always real, but severity depends on data sensitivity.

**What it means**: All fields on this entity are exposed via Web API. Fields added in the future will be exposed automatically.

**Action**:
- For tables with **only public-safe fields** (e.g., reference data, lookups, public-facing content): `*` is acceptable.
- For tables with **PII, financial, or confidential fields**: replace `*` with an explicit whitelist.
- Audit periodically as new fields are added.

## WRN-009 — `fields = *` on entity with secured readable fields

**Likely real**: High-signal when schema is present.

**What it means**: The entity's `Entity.xml` shows one or more attributes with both `IsSecured = 1` and `ValidForReadApi = 1`, and the portal uses `Webapi/<entity>/Fields = *`. The wildcard is the risk here: it makes the exposure set implicit instead of deliberate.

**Action**:
- Treat this as stronger than INFO-002. Replace `*` with an explicit whitelist.
- Review whether any secured field truly belongs in a portal response.
- If a secured field must remain readable, document the rationale explicitly.

## ERR-004 — Whitelist includes secured readable fields

**Likely real**: High-signal and usually actionable.

**What it means**: The explicit `Webapi/<entity>/Fields` setting names one or more fields whose `Entity.xml` attribute blocks have both `IsSecured = 1` and `ValidForReadApi = 1`. This is no longer an implicit wildcard problem; it is a direct allowlist decision.

**Action**:
- Confirm each flagged field is intentionally exposed to portal callers.
- Remove any field that does not have a clear business need.
- If the field must stay, verify the surrounding Table Permission scope and role access are as narrow as possible.

## INFO-003 — Page requires auth but no role rule

**Likely real**: Often intentional (any-authenticated-user pages exist legitimately).

**What it means**: The page is gated to authenticated users, but doesn't restrict to specific Web Roles. A user in any role can reach the page.

**Action**: If the page should be role-restricted (e.g., only Contractors should see contractor-specific pages), add a Web Page Access Control Rule referencing the allowed roles.

## INFO-004 — Junction not exported

**Always informational, not actionable.**

**What it means**: This site's export format doesn't include `adx_entitypermission_webrole` lists in per-record table-permission YAMLs. Role-aware checks are skipped.

**To enable role-aware audit**: Either upgrade `pac paportal` to a version that exports the junction, or use a project that exports in the consolidated `tablepermission.yml` format with inline `adx_entitypermission_webrole` lists. Newer pac paportal versions and the consolidated YAML style include the junction; older per-record exports often omit it.

## When to act vs. when to ignore

| Severity | Default response |
|---|---|
| ERROR | Investigate same day. Likely a runtime bug or security gap. |
| WARN | Review during the next sprint. Not blocking but worth tracking. |
| INFO | Keep on backlog. Periodic review (quarterly) suffices. |

For prod portals, treat ERROR-class findings as P0 until verified — even false positives are quickly dismissed, and real ones are typically high-impact.
