# Remediation Guide

How to fix each finding type. **Apply fixes only after the user has approved each one** — permissions changes affect security.

## ERR-001 — Web API enabled but no Table Permission

### Decision: keep the Web API, add a permission

If something genuinely needs to call `/_api/<entity>`:

1. Identify the calling Web Role(s)
2. Decide on Scope: Global / Account / Contact / Self / Parent
3. Decide on Operations: Read only, or Read + Write etc.
4. Create Table Permission YAML:

```yaml
# table-permissions/<descriptive-name>.tablepermission.yml
adx_entitylogicalname: <entity>
adx_entityname: <Descriptive Display Name>
adx_scope: 1            # 1=Global, 2=Account, 3=Contact, 4=Self, 5=Parent
adx_read: true
adx_create: false
adx_write: false
adx_delete: false
adx_append: false
adx_appendto: false
adx_entitypermission_webrole:
  - <role-guid-1>
  - <role-guid-2>
```

5. Sync: `pac paportal upload --path . --modelVersion 2`
6. Verify the calling code now succeeds

### Decision: remove the Web API setting

If nothing actually calls `/_api/<entity>` (dead config):

1. Find the site setting in `sitesetting.yml` (consolidated style) or `site-settings/<file>.sitesetting.yml`
2. Set `statecode: 1` (inactive) — or delete the setting outright if it was added by mistake
3. Sync

## ERR-002 — Orphaned Table Permission

### Decision: re-attach to a role

If the permission represents real intent that just lost its role assignment:

1. Open the permission YAML
2. Add the appropriate Web Role GUID(s) to `adx_entitypermission_webrole`
3. Sync

### Decision: delete

If the permission is dead config (a duplicate or a leftover from an experiment):

1. Verify in Power Pages Studio that no role currently references it
2. Delete the YAML file
3. Sync — the upload will detect and remove the permission record

## ERR-003 — Anonymous role with write operations

### Decision: tighten

If the operation should be authenticated only:

1. Open the permission YAML
2. Replace the Anonymous Users role GUID with the appropriate authenticated role GUID
3. Sync

### Decision: keep but constrain

If anonymous create is genuinely needed (public contact form etc.):

1. Verify `adx_create: true` only — `adx_read`, `adx_write`, `adx_delete` should be `false`
2. Add a narrow `Webapi/<entity>/Fields` whitelist — never `*`
3. Configure CAPTCHA on the form (Site Setting `Authentication/Registration/CaptchaEnabled = true` and `Authentication/Registration/Captcha/<page>` references)
4. Add server-side validation via plugins if write is allowed

## ERR-004 — Web API whitelist includes secured readable fields

1. Open the `Webapi/<entity>/Fields` site setting
2. Compare the listed fields against the entity's `Entity.xml` attribute blocks
3. Remove any field the audit flagged as secured unless the portal truly needs to expose it
4. If the portal does need it, document the business reason and verify the caller is restricted to the minimum necessary role/scope
5. Re-test the affected `/_api/<entity>` calls after tightening the list

## WRN-001 — Polymorphic lookup without disambiguator

1. Identify the entity that owns this lookup. Look at the calling URL to infer which table the new record is being created in.
2. Read `dataverse-schema/<solution>/Entities/<entity>/Entity.xml`
3. Find the lookup attribute by name. If `Type="customer"`, the field is polymorphic.
4. Determine which target (Contact or Account) the calling code intends:
   - Contact: change to `<lookup>_contact@odata.bind` and the URI to `/contacts(<guid>)`
   - Account: change to `<lookup>_account@odata.bind` and the URI to `/accounts(<guid>)`
5. Test the affected page/flow before deploying

If the field isn't polymorphic, the original binding is correct — close the finding as false-positive.

## WRN-002 — Orphaned Web Role

### Decision: assign permissions

If the role should grant access but currently doesn't:

1. Decide what the role should be able to do
2. Create or update Table Permissions to include this role's GUID in `adx_entitypermission_webrole`

### Decision: keep for page-level access

If the role is intentionally page-only (no record-level permissions):

1. Verify it's referenced in `web-pages/**/*.webpage.yml` Web Role rules
2. Document the intent in your project notes — this finding will recur otherwise

### Decision: delete

If the role is genuinely obsolete:

1. Confirm no Contacts are assigned to this role (in Studio: Web Roles → the role → Contacts tab)
2. Confirm no page rules reference it
3. Delete the role from `webrole.yml` (or its per-file YAML)
4. Sync

## INFO-001 — Permission without Web API

If client-side `/_api/<entity>` calls are intended:

1. Add `Webapi/<entity>/Enabled = true` to `sitesetting.yml`
2. Add `Webapi/<entity>/Fields = <comma,separated,list>` (NEVER `*` for sensitive entities)
3. Sync

If access is purely server-side via FetchXML in Liquid: leave as-is, this finding is informational.

## INFO-002 — Fields wildcard

1. Identify the calling code: which fields does it actually need?
2. Build the comma-separated whitelist from `<select>` clauses in custom JS and FetchXML attributes in templates
3. Replace `Webapi/<entity>/Fields` value from `*` to the explicit list
4. Test all calling code to confirm nothing references a field that was implicitly exposed by `*`
5. Sync

The transition from `*` to a whitelist often catches dead code that was reading fields nobody knew were exposed.

## WRN-009 — Wildcard on entity with secured readable fields

1. Treat the wildcard as the first thing to remove
2. Inventory which fields the portal actually reads from this entity
3. Replace `Webapi/<entity>/Fields = *` with only those fields
4. Double-check whether any secured field truly belongs in a portal response; if yes, prefer documenting that decision explicitly in the whitelist review
5. Re-run the audit to confirm the warning clears

## INFO-003 — Page requires auth but no role rule

1. Decide which roles should access this page
2. In Studio: Page → Permissions → Web Roles → Add (or edit `webpageaccesscontrolrule` and link to the page)
3. Sync

If the intent IS "any authenticated user," document it explicitly so the finding is dismissable next time.

## INFO-004 — Junction not exported

This is informational only. To get role-aware audit checks:

- Update `pac paportal` to the latest version (`pac install latest`)
- Re-export with the new version
- The export should now include `adx_entitypermission_webrole` inline

If updating PAC isn't an option, the audit's entity-level checks (ERR-001, INFO-001, INFO-002, INFO-003) still work — only role-aware checks (ERR-002, ERR-003, WRN-002) are skipped.

## After applying fixes

1. **Re-run the audit** to confirm the finding is resolved
2. **Sync up**: `pac paportal upload --path . --modelVersion 2`
3. **Test in browser**: load the affected page or call the affected `/_api/<entity>` endpoint
4. **Commit** with a clear message linking the finding code(s) you addressed

## What to do when in doubt

For any finding you're not sure about:

1. Don't apply a "fix" — it might break the intended behavior
2. Talk to whoever set up the original permissions config
3. If nobody remembers, do a controlled experiment: change one finding, test, observe, then either keep or revert
