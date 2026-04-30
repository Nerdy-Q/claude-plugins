---
name: pp-permissions-audit
description: Audit a Power Pages classic portal's Web Roles, Table Permissions, Site Settings, and Web API configuration for misalignments, orphaned permissions, missing Webapi/<entity>/enabled site settings, exposed `fields = *` whitelists, broken polymorphic lookups in custom JS, anonymous-role exposure, performance bottlenecks (N+1 queries), and metadata gaps (missing snippets). Use when the user reports unexpected 401/403/404 from /_api/, missing data, slow page loads, role-specific access bugs, or wants a portal security/quality review. NOT for code sites.
---

# Power Pages Permissions & Quality Audit

Static analysis of a Power Pages classic site's configuration. The skill reads YAML metadata, Liquid templates, and custom JavaScript, cross-references findings, and produces a prioritized report of security risks, performance bottlenecks, and metadata misalignments.

## When to apply

User says any of:

- "audit my Power Pages permissions"
- "review the portal security/quality"
- "I'm getting 401 / 403 / 404 from /_api/<something>, why?"
- "this page works for me but not for <other-user>"
- "make sure I'm not exposing any sensitive fields"
- "why is this page so slow to load?"
- "I'm seeing blank content where a snippet should be"
- "did I miss any FetchXML best practices?"

## How this skill works

1. **Detect the site folder**, `<site>---<site>/` containing `web-pages/`, `web-templates/`, `table-permissions/`, `web-roles/`, `site-settings/`. If multiple sites exist (Modernization Suite), ask the user which one.
2. **Run the audit script**, `scripts/audit.py <site-folder>`. The script reads YAML and JS files and emits a structured report.
3. **Interpret the findings**, the script identifies issues but the *fix* depends on the user's intent. Walk through findings with the user.
4. **Optionally write fixes**, only after the user picks which findings to address. Never auto-apply fixes.

## Running the audit

```bash
python3 <skill-path>/scripts/audit.py <site-folder>
```

The script is **stdlib only** (no `pip install` needed), Power Pages YAML is flat enough to parse with `re`. If the user wants more rigorous YAML parsing, they can `pip install pyyaml` and the script will use it automatically when available.

Output is markdown:

```markdown
# Power Pages Permissions Audit Report
Site: <name>  Path: <path>  Generated: <timestamp>

## Summary
- ERROR    3
- WARN     8
- INFO    12

## Findings

### ERROR-001: WebAPI enabled but no Table Permission
Entity: contoso_contractor
...
```

## What this skill audits

See [checks.md](references/checks.md) for the full list. Highlights:

| Severity | Check |
|---|---|
| ERROR | Web API enabled (`Webapi/<entity>/enabled = true`) but no Table Permission grants Read for any Web Role |
| ERROR | Table Permission with empty `adx_webroles` array (orphaned) |
| ERROR | Anonymous Users role granted Write/Delete on a sensitive table |
| ERROR | `Webapi/<entity>/Fields` explicitly whitelists field-secured readable columns |
| INFO | Table Permission grants Read but Web API site setting is missing, Web API will 404 |
| INFO | Web Page requires authentication but no Web Role rule (any auth user can see) |
| WARN | Custom JS has `<lookup>@odata.bind` without `_contact` / `_account` suffix on a polymorphic field, runtime 400 |
| WARN | Web Role exists but no Table Permission references it |
| WARN | `Webapi/<entity>/Fields = *` on an entity that has field-secured readable columns |
| WARN | Liquid references `snippets['Name']` that isn't defined locally (also covers Sitemarkers) |
| WARN | Basic Form references a field that does not exist in the schema |
| INFO | **N+1 query pattern detected in Liquid (lookup inside `{% for %}`)** |
| INFO | **`{% fetchxml %}` block is missing a `count` attribute** |
| WARN | **Site Setting appears to contain a secret and is visible to portal** |

## Interpreting findings

Three categories of fix:

1. **Add missing config**: Web API site setting is missing, add it to `site-settings/`
2. **Tighten config**: `fields = *` is broader than necessary, narrow to a whitelist
3. **Remove dead config**: orphaned permission with no roles, delete the YAML file

The script flags issues. **You** make the call about which to fix and how, based on whether the data is genuinely sensitive, whether the role is intended to have access, etc. Always discuss findings with the user before applying fixes.

See [interpreting.md](references/interpreting.md) and [remediation.md](references/remediation.md) for guidance on each finding type.

## What this skill does NOT do

- **Auto-apply fixes**, every fix is proposed to the user, not applied automatically. Permissions changes affect security; the user must approve each one.
- **Live-query Dataverse**, this is static analysis of the local site source. It can't verify whether a Web Role is actually assigned to specific Contacts (that lives in Dataverse, not the site source). For live verification, use the `dataverse` plugin (`dv-query`) to inspect Dataverse directly.
- **Audit Dataverse-side security**, System User roles, security roles on entities, business unit boundaries are out of scope. This skill audits the **portal layer** only.
- **Replace manual security review**, the audit catches misalignments it can detect statically. It cannot judge whether the portal's intended security model is correct in the first place; that's a human decision.

## Reference files

- [checks.md](references/checks.md), full list of audit checks with descriptions
- [interpreting.md](references/interpreting.md), how to interpret each finding type
- [remediation.md](references/remediation.md), how to fix each finding type
- [api-config.md](references/api-config.md), Power Pages Web API site setting requirements (deep reference)

## Audit script

The audit logic lives in `scripts/audit.py`. Read it to understand the exact checks. To extend the audit:

1. Add a `check_*` function in `audit.py`
2. Call it from `main()`
3. Document the new check in `references/checks.md`

PRs welcome.
