# Interpreting Audit Findings

The audit identifies *misalignments* statically. Whether each one is a real bug, a false positive, or an intentional config depends on the project's intent. This file gives interpretation guidance for each finding code.

## ERR-001: Web API enabled but no Table Permission

**Likely real**: Yes. Most actionable error.

**What it means**: `Webapi/<entity>/Enabled = true` exists in `site-settings/`, but no Table Permission in `table-permissions/` allows Read on this entity. If anything calls `/_api/<entity>` from the portal it will 401 / 403.

**False-positive cases**:
- Permission exists in Power Pages Studio but isn't yet exported to YAML (run `pac paportal download` to refresh).
- Role-permission junction is in a separate file the audit doesn't read (rare; see INFO-004).

**To verify**: Check if any custom JS in `web-pages/**/*.webpage.custom_javascript.js` references this entity. If not, the Web API setting may be **dead config**, safe to remove.

## ERR-002: Orphaned Table Permission

**Likely real**: Yes (when the export format includes the role junction; otherwise audit emits INFO-004 instead).

**What it means**: Permission YAML exists with valid entity and operations, but `adx_entitypermission_webrole` is empty. Permission applies to nobody.

**False-positive cases**: Studio has the permission assigned to a role, but the assignment didn't make it into the YAML export. Re-run `pac paportal download` to refresh.

**To verify**: Open the Power Pages Studio and check the permission's Web Roles tab. If a role IS assigned there, the export is stale; re-download.

## ERR-003: Anonymous role with Write/Create/Delete

**Likely real**: Yes, but always intentional or always a bug. Manual review needed.

**What it means**: An unauthenticated visitor can perform a write operation on this table.

**Intentional cases**:
- Public contact form (anonymous Create on `contact`)
- Public ticket submission (anonymous Create on a custom table)
- Lead capture (anonymous Create on `lead`)

For these, ensure:
- The `Webapi/<entity>/Fields` whitelist is **narrow** (do not allow `*`)
- Captcha / bot protection is configured at the form level
- The permission allows Create only, not Read, Write, or Delete

**Unintentional cases**:
- A permission was duplicated and one copy kept the anonymous role flag
- The Anonymous Users implicit role got added to a permission unintentionally

## WRN-001: Polymorphic lookup without disambiguator

**Likely real**: Maybe. Heuristic match, verify against schema.

**What it means**: Custom JS does `<lookup>@odata.bind` and the lookup name suggests it might be a polymorphic (customer-type) field. Polymorphic fields require the `_contact` or `_account` suffix, e.g. `contoso_Applicant_contact@odata.bind`.

**To verify**:
1. Open `dataverse-schema/<solution>/Entities/<entity>/Entity.xml`
2. Look for `<attribute PhysicalName="<lookup>"`
3. If `Type="customer"`, the field is polymorphic, fix is needed
4. If `Type="lookup"` with a single target, the bare binding is fine, false positive

**Fix when real**: Determine which type (Contact or Account) is being referenced and use the corresponding suffix.

## WRN-002: Web Role with no Table Permission references

**Likely real**: Yes for stale roles, false-positive for "structural" roles.

**What it means**: A Web Role exists in `webrole.yml` but no Table Permission's role list includes this role's GUID. The role grants no record-level access.

**False-positive cases**:
- The role grants page-level access only (via Web Page Access Control Rules), it doesn't need Table Permissions
- The role is for an external integration (e.g., a Web Role that's only used in the portal's authentication policy, not for data access)

**To verify**: Search `web-pages/**/*.webpage.yml` and `webpagerule.yml` (if present) for the role's GUID. If found, the role has page-level use and can be ignored. Otherwise, consider removing the role.

## INFO-001: Permission without Web API

**Likely real**: Often intentional.

**What it means**: A Table Permission grants Read but no `Webapi/<entity>/Enabled` site setting exists. Server-side FetchXML in Liquid templates can use this permission; client-side `/_api/` cannot.

**Action**: No action needed if all access is via Liquid FetchXML. If you intend to call `/_api/<entity>` from custom JS, add the site setting (and a `Webapi/<entity>/Fields` whitelist).

## INFO-002: `fields = *` whitelist

**Likely real**: Always real, but severity depends on data sensitivity.

**What it means**: All fields on this entity are exposed via Web API. Fields added in the future will be exposed automatically.

**Action**:
- For tables with **only public-safe fields** (e.g., reference data, lookups, public-facing content): `*` is acceptable.
- For tables with **PII, financial, or confidential fields**: replace `*` with an explicit whitelist.
- Audit periodically as new fields are added.

## WRN-009: `fields = *` on entity with secured readable fields

**Likely real**: High-signal when schema is present.

**What it means**: The entity's `Entity.xml` shows one or more attributes with both `IsSecured = 1` and `ValidForReadApi = 1`, and the portal uses `Webapi/<entity>/Fields = *`. The wildcard is the risk here: it makes the exposure set implicit instead of deliberate.

**Action**:
- Treat this as stronger than INFO-002. Replace `*` with an explicit whitelist.
- Review whether any secured field truly belongs in a portal response.
- If a secured field must remain readable, document the rationale explicitly.

## ERR-004: Whitelist includes secured readable fields

**Likely real**: High-signal and usually actionable.

**What it means**: The explicit `Webapi/<entity>/Fields` setting names one or more fields whose `Entity.xml` attribute blocks have both `IsSecured = 1` and `ValidForReadApi = 1`. This is no longer an implicit wildcard problem; it is a direct allowlist decision.

**Action**:
- Confirm each flagged field is intentionally exposed to portal callers.
- Remove any field that does not have a clear business need.
- If the field must stay, verify the surrounding Table Permission scope and role access are as narrow as possible.

## INFO-003: Page requires auth but no role rule

**Likely real**: Often intentional (any-authenticated-user pages exist legitimately).

**What it means**: The page is gated to authenticated users, but doesn't restrict to specific Web Roles. A user in any role can reach the page.

**Action**: If the page should be role-restricted (e.g., only Contractors should see contractor-specific pages), add a Web Page Access Control Rule referencing the allowed roles.

## WRN-003: Sitemarker referenced in Liquid but not defined

**Likely real**: Yes, manifests as a missing link or broken nav.

**What it means**: A Liquid template uses `sitemarkers['Name']` but no `sitemarker.yml` record with that `adx_name` exists in the export.

**False-positive cases**: The sitemarker exists in the environment but wasn't downloaded. Re-run `pac paportal download`.

**To verify**: Search `sitemarker*.yml` for the missing name. If absent, the navigation link or destination it builds will render as `null`/empty in the portal.

## WRN-004: Custom JS calls `/_api/` without anti-forgery token

**Likely real**: Yes, calls will 403 at runtime.

**What it means**: A `*.webpage.custom_javascript.js` file makes Web API calls but does not reference `__RequestVerificationToken` or the standard `safeAjax` helper. Power Pages requires anti-forgery tokens on `/_api/` writes (and many reads).

**False-positive cases**: The token logic lives in a shared `web-files/*.js` and is called from this page. The audit doesn't follow `<script>` cross-references.

**To verify**: Test the affected page in a browser, a 403 from `/_api/` is the runtime symptom.

## WRN-005: All-lowercase navigation property in `@odata.bind`

**Likely real**: Likely, but check the schema first.

**What it means**: `<lookup>@odata.bind` uses an all-lowercase name. Custom-entity navigation properties usually use PascalCase (matching the schema name), all-lowercase suggests the developer used the Logical Name where the Navigation Property was needed.

**To verify**: Open `dataverse-schema/<solution>/Entities/<entity>/Entity.xml`, find the relationship, and check `<EntityRelationship Name="...">`. If the Navigation Property differs from the Logical Name, the binding will 400.

## WRN-006: `$select=` references a non-existent field

**Likely real**: Yes, query will 400.

**What it means**: Custom JS does `$select=<field>` and `<field>` does not appear as an attribute in the entity's `Entity.xml`.

**False-positive cases**: The field was added to Dataverse but the schema export is stale. Re-run `pac solution export/unpack`.

**To verify**: Check `Entity.xml` for the attribute, case matters. Logical names are lowercase.

## WRN-007: FetchXML attribute does not exist on root entity

**Likely real**: Yes, FetchXML will fail with a generic SOAP error.

**What it means**: A `<fetch>` block uses `<attribute name="x">` and `x` is not an attribute on the root `<entity>`.

**To verify**: Same as WRN-006, check `Entity.xml` for the attribute. If the field is on a linked entity, move the `<attribute>` inside the corresponding `<link-entity>` block.

## WRN-008: `Webapi/<entity>/Fields` lists non-existent field(s)

**Likely real**: Yes for typo'd fields, false-positive if schema is stale.

**What it means**: One or more comma-separated fields in the `Fields` site setting don't exist on the entity per `Entity.xml`. They have no effect, readers can request only fields that genuinely exist, but they're noise that hides the real allowlist.

**Action**: Remove the bogus entries or refresh the schema export.

## WRN-010: Content Snippet referenced but not defined

**Likely real**: Yes, content will render empty.

**What it means**: A Liquid template uses `snippets['Name']` but no Content Snippet record with that name exists in the export.

**False-positive cases**: Snippet exists in the environment but wasn't included in `pac paportal download` (rare).

**To verify**: Search `contentsnippet*.yml`. If the name truly doesn't exist, the page will render with empty content where the snippet should appear.

## WRN-011: Possible sensitive Site Setting exposed

**Likely real**: Sometimes, depends on the value pattern.

**What it means**: A Site Setting's value matches a heuristic for secrets (long random-looking string, OAuth client secret pattern, API-key-like prefix).

**False-positive cases**: The setting genuinely is a public key (e.g., a public reCAPTCHA site key) or a non-secret token.

**To verify**: Identify what the setting is for. If it's a secret consumed only by Power Pages internals (auth providers, Bing Maps, etc.), confirm it's NOT marked "Visible to Portal" in Studio.

## WRN-012: Form references unknown field

**Likely real**: Yes, form will fail to render or fail validation.

**What it means**: A Basic Form (`adx_entityform`) names a field via `adx_attributelogicalname` that doesn't exist on the target entity per `Entity.xml`.

**False-positive cases**: Field was added to Dataverse but the schema export is stale.

## INFO-005: Empty base file with populated localized variant

**Likely real**: Yes, the canonical "page renders blank" bug.

**What it means**: `web-pages/<page>/<Page>.webpage.copy.html` is empty (or just whitespace) but `web-pages/<page>/content-pages/<lang>/<Page>.<lang>.webpage.copy.html` has content. Power Pages serves the base file by default for un-localized requests, so visitors hitting the page in any other locale see a blank page.

**Action**: Copy the localized content into the base file (or use `pp sync-pages localized-to-base` to do it in bulk).

## INFO-006: FetchXML missing `count` attribute

**Always informational, but worth fixing for performance.**

**What it means**: `{% fetchxml %}` doesn't set `count="<n>"` on the `<fetch>` element. Without an explicit count, Power Pages applies its server default, which may be larger than the page actually needs and forces an unnecessary round-trip on subsequent pages.

**Action**: Add `count="50"` (or a value matching what the page actually displays).

## INFO-007: Unsafe DotLiquid JSON escape

**Likely real**: Often, DotLiquid is not Shopify Liquid here.

**What it means**: Liquid does `replace: '"', '\\"'` expecting the replacement to be `\"` (one backslash, one quote). DotLiquid produces THREE characters: `\`, `\`, `"`. JSON consumers see invalid escape sequences.

**To verify**: Render the page, view the HTML source, and inspect the JSON-embedded values. If you see `\\"` instead of `\"`, this finding is real.

**Workaround**: Use single-character replacement or build the JSON via `to_json` filter rather than manual escaping.

## INFO-008: N+1 query pattern in Liquid

**Likely real**: Yes, page slowness compounds with row count.

**What it means**: A `{% for %}` loop contains a nested `{% fetchxml %}` query or `entities[...]` lookup. Each iteration runs a separate query. A 50-row table becomes 50 queries.

**Action**: Move the query outside the loop. Pre-fetch all related records in one FetchXML, then filter inside the loop.

## INFO-009: Diverged base/localized files

**Likely real**: Yes, base and localized copies have drifted.

**What it means**: Both files have content but their sizes differ significantly. One was edited; the other wasn't synced.

**Action**: Decide which is current, then propagate to the other (`pp sync-pages` does this in bulk). Common when devs edit only the en-US localized file and forget the base.

## INFO-004: Junction not exported

**Always informational, not actionable.**

**What it means**: This site's export format doesn't include `adx_entitypermission_webrole` lists in per-record table-permission YAMLs. Role-aware checks are skipped.

**To enable role-aware audit**: Either upgrade `pac paportal` to a version that exports the junction, or use a project that exports in the consolidated `tablepermission.yml` format with inline `adx_entitypermission_webrole` lists. Newer pac paportal versions and the consolidated YAML style include the junction; older per-record exports often omit it.

## When to act vs. when to ignore

| Severity | Default response |
|---|---|
| ERROR | Investigate same day. Likely a runtime bug or security gap. |
| WARN | Review during the next sprint. Not blocking but worth tracking. |
| INFO | Keep on backlog. Periodic review (quarterly) suffices. |

For prod portals, treat ERROR-class findings as P0 until verified, even false positives are quickly dismissed, and real ones are typically high-impact.
