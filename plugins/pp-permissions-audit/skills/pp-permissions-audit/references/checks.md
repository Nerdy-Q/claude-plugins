# Audit Checks Reference

Full list of checks the audit script performs, with codes, severity, and what triggers each.

## ERROR-class

| Code | Title | Triggered when |
|---|---|---|
| ERR-001 | Web API enabled for `<entity>` but no Table Permission grants Read | A `Webapi/<entity>/Enabled = true` site setting exists but no Table Permission with `adx_read: true` references the same entity. Web API calls would return 401/403. |
| ERR-002 | Orphaned Table Permission `<name>` | A Table Permission has empty `adx_entitypermission_webrole`. Skipped if the export format doesn't include the role junction (see INFO-004). |
| ERR-003 | Anonymous Users role granted `<ops>` on `<entity>` | A role marked `adx_anonymoususersrole: true` is referenced in a permission with Write, Create, or Delete on a non-trivial table. |
| ERR-004 | `Webapi/<entity>/Fields` explicitly whitelists secured readable field(s) | **Schema-aware check**. An explicit Web API whitelist includes field logical names whose `Entity.xml` attribute blocks have both `IsSecured = 1` and `ValidForReadApi = 1`. This is a direct exposure decision and should be reviewed as a security issue. |

## WARN-class

| Code | Title | Triggered when |
|---|---|---|
| WRN-001 | Possible polymorphic lookup without disambiguator | Custom JS contains a `<lookup>@odata.bind` pattern where the lookup name matches a polymorphic-field hint (`applicant`, `customer`, `owner`, `regarding`, `objectid`) and lacks a `_contact` / `_account` / `_systemuser` suffix. Likely runtime 400. |
| WRN-002 | Web Role `<name>` has no Table Permission references | A Web Role exists in `webrole.yml` but no Table Permission's `adx_entitypermission_webrole` includes its GUID. Either obsolete or grants nothing. |
| WRN-003 | Sitemarker `<name>` referenced in Liquid but not defined | A web template / page / snippet uses `sitemarkers['<name>']` but no Sitemarker record with this name exists in `sitemarker.yml`. The Liquid expression returns `nil`, breaking URL construction. |
| WRN-004 | Custom JS calls `/_api/` without anti-forgery token pattern | A `*.webpage.custom_javascript.js` file contains `/_api/<entity>` calls but never references `__RequestVerificationToken`, `getTokenDeferred`, or a `safeAjax` helper. Power Pages returns 403 without the token. |
| WRN-005 | `<prefix_name>@odata.bind` is all lowercase, likely a Logical Name where Navigation Property was needed | Custom JS has a `<custom>_<lowercase>@odata.bind` payload key. Custom-entity navigation properties typically use PascalCase (schema-name casing). Lowercase form is the **Logical Name** of the lookup attribute, not the navigation property, Power Pages returns `'<name>' is not a valid navigation property`. Built-in nav props like `parentcustomerid` and `_contact`/`_account` polymorphic suffixes are excluded. |
| WRN-006 | `$select=<field>` references a field that does not exist on `<entity>` | **Schema-aware check** (only runs when `dataverse-schema/` is in the repo). Custom JS has `/_api/<entityset>?$select=...` with a field name not present in the entity's `Entity.xml`. Skips Microsoft built-in entities (we only see partial customizations). Likely a typo or stale reference after a column rename. |
| WRN-007 | FetchXML attribute `<name>` does not exist on `<entity>` | **Schema-aware check**. A `{% fetchxml %}` block uses an `<attribute name="...">` not present in the entity's `Entity.xml`. Common after a column rename or removal, the FetchXML wasn't updated. Will fail at page render time. |
| WRN-008 | `Webapi/<entity>/Fields` lists field(s) that do not exist on `<entity>` | **Schema-aware check**. The Site Setting whitelist references attributes not in `Entity.xml`. Doesn't break the API (silently ignored) but signals config drift after a column rename or removal. Update the whitelist. |
| WRN-009 | Web API on `<entity>` uses `fields = *` and the entity has secured readable fields | **Schema-aware check**. The entity has one or more attributes with both `IsSecured = 1` and `ValidForReadApi = 1`, and the portal uses `Webapi/<entity>/Fields = *`. This is riskier than a narrow whitelist because the exposure set is implicit. |
| WRN-010 | Content Snippet `<name>` referenced in Liquid but not defined | A web template / page / snippet uses `snippets['<name>']` but no Content Snippet record with this name exists in the local export. The Liquid expression returns `nil`. If this snippet was intended to provide content, the UI will be blank or broken. |
| WRN-011 | Possible sensitive Site Setting exposed: `<name>` | Setting contains common sensitive patterns (`key`, `secret`, `token`, etc.) and is of non-trivial length. Could be leaked to the client-side via `window.Microsoft.Dynamic.Settings`. |
| WRN-012 | Form `<name>` references unknown field `<val>` | **Schema-aware check**. A Basic Form references an attribute logical name that does not exist on the target entity's `Entity.xml`. Will cause runtime errors on the portal. |

## INFO-class

| Code | Title | Triggered when |
|---|---|---|
| INFO-001 | Table Permission allows Read on `<entity>` but Web API is not enabled | Permission exists but no `Webapi/<entity>/Enabled = true` site setting. Fine for FetchXML-only access; `/_api/<entity>` calls would 404. |
| INFO-002 | Web API on `<entity>` exposes all fields (`fields = *`) | `Webapi/<entity>/Fields = *` instead of an explicit whitelist. Fields added later are auto-exposed. |
| INFO-003 | Page `<name>` requires auth but has no role rule | A Web Page requires registration but has no associated Web Page Access Control Rule. Any authenticated user can reach it. |
| INFO-004 | Role-permission junction not exported | The site's `pac paportal` export format doesn't include `adx_entitypermission_webrole` lists. Role-aware checks (ERR-002, ERR-003, WRN-002) are skipped for this site. |
| INFO-005 | Page `<slug>` has empty base file but populated localized file | The base `<Page>.webpage.copy.html` (or `.custom_javascript.js`, etc.) is under 50 bytes while the matching `content-pages/<lang>/...` is over 200 bytes. **Blank-page mode A**: Power Pages renders the base by default; localized content renders only when base is empty AND a matching language is requested. Most users see the empty base. |
| INFO-006 | `{% fetchxml %}` missing `count` attribute | A FetchXML query doesn't specify a `count`. For best performance and to prevent unexpected large payloads, always specify a `count` (e.g. `count='50'`). |
| INFO-007 | Unsafe DotLiquid JSON escape (`replace: '"', '\\"'`) | A web template / page / snippet uses the broken DotLiquid escape pattern that produces 3 chars (`\\"`) instead of the intended 2 (`\"`). Breaks JSON parsing in `<script>` blocks. Use `replace: '"', '"'` instead. |
| INFO-008 | Possible N+1 query pattern in Liquid | A `{% for %}` loop contains a `{% fetchxml %}` or `entities[...]` lookup. This executes a Dataverse query for EVERY iteration of the loop, severely impacting page load performance. |
| INFO-009 | Page `<slug>` has diverged base/localized files | Both base file and a `content-pages/<lang>/...` localized file are populated (>200 bytes each), but their sizes differ by more than 10%. **Inconsistent-content mode B**: some users see one version, others see the other depending on which Power Pages serves them. Pick one as authoritative and copy to the other. |

## Why some checks are heuristic

- **WRN-001** uses name-substring matching to flag *possible* polymorphic lookups. Power Pages doesn't expose the polymorphic-vs-singular field type in the per-page YAML; the script can't be 100% sure. Always cross-check against the entity schema before applying a fix. False positives are expected; false negatives are unlikely.
- **WRN-002** skips implicit roles (`Anonymous Users`, `Authenticated Users`) which always have an "implicit" association via the role flag, they don't need to be referenced by GUID.
- **ERR-001** falls back to entity-only matching (without role validation) when the export format omits the role junction (INFO-004 case). It still catches the most common misalignment (Web API enabled, zero permissions exist), but won't catch role-specific gaps.
- **ERR-004 / WRN-009** rely on `Entity.xml` carrying accurate `IsSecured` and `ValidForReadApi` flags for the entity. They skip Microsoft built-in entities because custom-solution exports only include partial metadata for those tables.

## Adding a new check

1. Add a `check_*` function in `audit.py`. Take the `AuditState` and call `state.add(severity, code, title, detail, location)`.
2. Call it from `main()`.
3. Pick a code following the pattern (ERR-NNN / WRN-NNN / INFO-NNN). Reserve a fresh number.
4. Document the check in this file.
5. Update `interpreting.md` and `remediation.md` if the new check needs interpretation/fix guidance.

PRs and forks welcome.
