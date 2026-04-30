---
name: pp-portal
description: Microsoft Power Pages classic portals, optimized for the current enhanced-model workflow around the native Power Pages Studio hybrid Liquid + Web API pattern. Server-rendered Liquid templates with client-side Web API calls in custom JS. Also covers portal-facing design-system composition and responsive defaults when the user asks for Material Design 3, Apple Human Interface Guidelines, Fluent 2, USWDS 3, shadcn/ui, mobile, tablet, accessibility, or crossover component patterns inside classic Power Pages. Use when working in *.webpage.copy.html, *.webtemplate.source.html, *.webpage.custom_javascript.js, or when the user mentions Power Pages, fetchxml, entitylist, entityform, webform, web roles, table permissions, sitemarkers, or pac paportal. NOT for full code sites / React-style SPAs (use Microsoft's power-pages plugin); for Dataverse-side work (schema authoring, data import, solutions), defer to Microsoft's dataverse plugin (dv-connect, dv-query, dv-metadata, dv-solution).
---

# Power Pages Portal (classic, hybrid)

Classic-portal reference for Microsoft Power Pages (formerly Power Apps Portals, formerly Dynamics 365 Portals). Optimized for the current enhanced-model workflow around the **server-rendered Liquid + client-side Web API** hybrid pattern that real production portals use in native Power Pages Studio-managed portal assets.

> **NOT for**: Power Pages **code sites** or React/Vue/Astro-style SPAs that call the Web API directly, those use Microsoft's `power-pages` plugin. NOT for Shopify, Jekyll, or generic Liquid, Power Pages uses **DotLiquid**, a .NET reimplementation with different filter behavior in important places (see [references/language/dotliquid-gotchas.md](references/language/dotliquid-gotchas.md)).

## When this skill applies

Apply this skill when any of these are true:

- File extension is `.liquid`, `.webpage.copy.html`, `.webtemplate.source.html`, `.contentsnippet.value.html`, `.webpage.custom_javascript.js`
- Directory contains `web-pages/`, `web-templates/`, `web-files/`, `content-snippets/`, `page-templates/`, `table-permissions/`, `web-roles/`, or `website.yml`
- User mentions Power Pages, Power Apps Portals, Dynamics 365 Portals, FetchXML, entitylist, entityform, webform, web roles, sitemarkers, or `pac paportal`
- Code uses `window.shell.getTokenDeferred()`, `__RequestVerificationToken`, or `/_api/<entity>`

## Companion plugins

This skill covers the **classic portal hybrid pattern**. For adjacent work, defer to the right plugin instead of stretching this one:

| Task | Plugin | Skill |
|---|---|---|
| Dataverse environment setup, auth, MCP registration | Microsoft's `dataverse` | `dv-connect` |
| Dataverse data CRUD, queries, sample data | Microsoft's `dataverse` | `dv-data`, `dv-query` |
| Dataverse schema authoring (tables, columns, relationships) | Microsoft's `dataverse` | `dv-metadata` |
| Dataverse solution import/export | Microsoft's `dataverse` | `dv-solution` |
| Dataverse environment-level admin | Microsoft's `dataverse` | `dv-admin` |
| Dataverse security roles (NOT Power Pages Web Roles) | Microsoft's `dataverse` | `dv-security` |
| Power Pages **code sites** (React/Vue/Astro SPAs) | Microsoft's `power-pages` | (whole plugin) |
| Canvas apps | Microsoft's `canvas-apps` | (whole plugin) |
| Model-driven apps | Microsoft's `model-apps` | (whole plugin) |
| MCP-app widgets for MCP tools | Microsoft's `mcp-apps` | (whole plugin) |

When a task spans this skill plus one of the above (e.g. "build a portal page that lists records from a new table"), do the **schema work in the dataverse plugin first**, then come back here for the portal-side rendering.

## Recipes

For step-by-step walkthroughs of common patterns, see `references/recipes/`:

- [recipes/paginated-list-page.md](references/recipes/paginated-list-page.md), server-rendered list page with search and pagination
- [recipes/hybrid-form-with-safeajax.md](references/recipes/hybrid-form-with-safeajax.md), Liquid form + JS Web API submit
- [recipes/dependent-dropdown.md](references/recipes/dependent-dropdown.md), cascading select boxes via /_api/
- [recipes/file-upload-annotations.md](references/recipes/file-upload-annotations.md), multi-file upload via /_api/annotations
- [recipes/role-gated-section.md](references/recipes/role-gated-section.md), show/hide UI by Web Role

## Power Pages classic site anatomy

A `pac paportal download` produces this canonical structure:

```
<site-name>---<site-name>/
├── website.yml                              # site root metadata
├── .portalconfig/                           # tenant/env-specific (often gitignored)
├── web-pages/                               # one folder per page
│   └── <page-slug>/
│       ├── <Page>.webpage.yml               # page metadata
│       ├── <Page>.webpage.copy.html         # ⚠ BASE Liquid template (THIS is loaded)
│       ├── <Page>.webpage.custom_javascript.js
│       ├── <Page>.webpage.custom_css.css
│       └── content-pages/
│           └── <Page>.en-US.webpage.copy.html  # localized, NOT loaded by default
├── web-templates/                           # reusable Liquid components
│   └── <name>/<Name>.webtemplate.source.html
├── page-templates/                          # page layouts (reference web-templates)
├── content-snippets/                        # editable content blocks
│   └── <name>/<Name>.contentsnippet.value.html
├── web-files/                               # CSS / JS / images served at /<filename>
├── basic-forms/                             # entityform metadata
├── advanced-forms/                          # webform (multi-step) metadata
├── entity-lists/                            # entitylist metadata
├── table-permissions/                       # YAML, CRUD rules per table per role
├── web-roles/                               # YAML, role definitions
├── site-settings/                           # YAML, k/v site config (CSP lives here)
└── sitemarkers/                             # YAML, named URL anchors for Liquid
```

## Four critical gotchas: read these first

### 1. Base file ↔ localized file pair must stay in sync

Power Pages stores **two physical copies** of every page asset: a base file (`<Page>.webpage.copy.html`) and one or more localized files (`content-pages/<lang>/<Page>.<lang>.webpage.copy.html`). The base is what most users get. The localized file renders only when the user requests a matching locale AND… implementation details vary.

**Two distinct failure modes:**

| Mode | Symptom | What happened |
|---|---|---|
| **A. Empty base** | Page renders blank | The base file is empty (Studio sometimes saves edits only to localized). Audit catches this as **INFO-005**. |
| **B. Diverged pair** | Some users see different content than others | Both files were edited at different times; they've drifted. Audit catches this as **INFO-009**. |

**The maintenance rule that prevents both**: when you edit ONE file in the pair, edit the OTHER too, or use `pp sync-pages <project>` to copy one to the other in bulk. The tooling does not auto-sync.

Files affected (each has a base + localized form): `*.webpage.copy.html`, `*.webpage.custom_javascript.js`, `*.webpage.custom_css.css`, `*.webpage.summary.html`.

**A common workflow that creates Mode A bugs**: dev edits a page in Studio (which saves to localized only) → commits → on another machine the page renders blank because the puller's Studio didn't auto-populate the localized version of *their* base. Always sync after Studio edits. See [references/pages/hybrid-page-idiom.md](references/pages/hybrid-page-idiom.md).

### 2. DotLiquid JSON serialization breaks JavaScript

`replace: '"', '\\"'` in DotLiquid produces **3 chars** (`\`, `\`, `"`), backslash escaping doesn't work the way it does in Shopify. Inline JSON inside `<script>` tags will silently break.

**Fix:** Always emit data via `<script type="application/json">` with **Unicode escapes**, then `JSON.parse` in your real script. See [references/language/dotliquid-gotchas.md](references/language/dotliquid-gotchas.md).

```html
<script id="rowsJSON" type="application/json">
[{% for row in rows %}{"name":"{{ row.name | replace: '"', '"' }}"}{% unless forloop.last %},{% endunless %}{% endfor %}]
</script>
<script>
  var rows = [];
  try { rows = JSON.parse(document.getElementById('rowsJSON').textContent || '[]'); }
  catch (e) { console.warn('rows parse failed', e); }
</script>
```

### 3. Polymorphic lookup `@odata.bind` requires a suffix

Customer-type fields (target Contact OR Account) need the disambiguating suffix on the navigation property, e.g. `contoso_Applicant_contact@odata.bind` or `contoso_Applicant_account@odata.bind`. Bare `contoso_Applicant@odata.bind` returns 400. Navigation property names are also **case-sensitive** and **entity-specific**, `contoso_Account@odata.bind` works on one entity but not on another with the same field name. See [references/data/webapi-patterns.md](references/data/webapi-patterns.md).

### 4. Dataverse uses 4 different "names" for the same thing: and Power Pages uses different ones in different contexts

Every entity has a **Logical Name** (lowercase, e.g. `acme_customer`), a **Schema Name** (often PascalCase, e.g. `acme_Customer`), a **Display Name** (`Acme Customer`), and an **Entity Set Name** (lowercase plural, e.g. `acme_customers`). Lookup columns add a fifth: their **Navigation Property Name**, which uses the schema-name casing.

| Where you write the name | What name it expects |
|---|---|
| Web API URL: `/_api/<entityset>` | Entity Set Name (lowercase plural) |
| Web API `$select=` / `$filter=` attribute references | Logical Name (lowercase), for lookups, the `_<attr>_value` form |
| Web API POST/PATCH payload field keys | Logical Name (lowercase), for lookups, use `<NavigationProperty>@odata.bind` instead |
| Web API `@odata.bind` and `$expand=` | **Navigation Property Name (PascalCase)** ⚠ |
| FetchXML in Liquid (entity, attribute, link-entity, condition) | Logical Name (lowercase), everywhere |

**The trap**: if you copy `acme_contact` from Studio's Columns view, you get the Logical Name (lowercase). If you then use it as `acme_contact@odata.bind`, you get **`'acme_contact' is not a valid navigation property`** at runtime, because the navigation property is `acme_Contact` (PascalCase, matching the schema name). The error message doesn't say "casing"; it just says "not a valid".

**Always read the Navigation Property name from `Entity.xml`** in your unpacked solution, the Maker Portal's **Relationships** view, or `/_api/$metadata`. Don't infer from the Logical Name. See [references/data/dataverse-naming.md](references/data/dataverse-naming.md) for the full cheat sheet, error-decoding table, and lookup recipes.

## Decision routing: which pattern fits this task?

| Task | Use | Why |
|---|---|---|
| Render a list/table on initial page load | **`{% fetchxml %}` in Liquid** ([references/data/fetchxml-patterns.md](references/data/fetchxml-patterns.md)) | Server-rendered, indexed by search engines, no flash of empty content |
| Filter/paginate via querystring | **`{% fetchxml %}` + `request.params`** | Works without JS, bookmarkable URLs |
| Submit a form (create/update) | **Web API POST/PATCH in custom JS** ([references/data/webapi-patterns.md](references/data/webapi-patterns.md)) | Form data isn't available to Liquid until next request |
| Dependent dropdown (city → branches) | **Web API GET in custom JS** with `$filter`, `$orderby` | Liquid can't react to client-side selection |
| File upload | **Web API POST to `/_api/annotations`** | Annotations entity stores attachment metadata; SharePoint integration is automatic if configured |
| Standard CRUD form with built-in validation | **`{% entityform %}`** ([references/language/tags.md](references/language/tags.md)) | Power Pages renders the form from Dataverse form metadata, minimal code |
| Multi-step wizard with branching | **`{% webform %}`** | Same as entityform but multi-step |
| Read-only list with search/sort/page | **`{% entitylist %}`** | Bound to a Dataverse view; built-in pagination and search |
| Custom UI that doesn't fit entity tags | **Hybrid: Liquid render scaffold + JS for interactivity** ([references/pages/hybrid-page-idiom.md](references/pages/hybrid-page-idiom.md)) | Most production pages |

## Reference files

The skill loads `SKILL.md` first (router + critical gotchas). Detail lives in topic-specific reference files the model pulls on demand, grouped by responsibility.

### Language

How DotLiquid itself works in Power Pages, the syntactic surface.

- [references/language/operators.md](references/language/operators.md), Liquid operators (`==`, `!=`, `contains`, `and`, `or`, truthy/falsy rules)
- [references/language/types.md](references/language/types.md), Liquid type system (string, number, boolean, array, hash, drop, dates)
- [references/language/tags.md](references/language/tags.md), Power Pages tags: `{% fetchxml %}`, `{% entitylist %}`, `{% entityform %}`, `{% webform %}`, `{% editable %}`, `{% chart %}`, `{% include %}`, `{% block %}`/`{% extends %}`
- [references/language/filters.md](references/language/filters.md), DotLiquid filter table with examples + Power Pages-specific extensions
- [references/language/objects.md](references/language/objects.md), `user`, `page`, `website`, `request`, `weblinks`, `snippets`, `sitemarkers`, `settings`, `now`, `params`
- [references/language/dotliquid-gotchas.md](references/language/dotliquid-gotchas.md), DotLiquid behavioral quirks (where it differs from Shopify Liquid)

### Data + integration

How the portal talks to Dataverse, names, queries, mutations, permissions, settings.

- [references/data/webapi-patterns.md](references/data/webapi-patterns.md), `safeAjax`, `__RequestVerificationToken`, GET/POST/PATCH/DELETE, `@odata.bind`, file upload via `/_api/annotations`
- [references/data/fetchxml-patterns.md](references/data/fetchxml-patterns.md), `{% fetchxml %}` count + paginate + filter, link-entity, aggregation
- [references/data/dataverse-naming.md](references/data/dataverse-naming.md), the 4-name model (Logical / Schema / Display / Entity Set), navigation property casing, error-decoding cheat sheet
- [references/data/permissions-and-roles.md](references/data/permissions-and-roles.md), Web Roles, Table Permissions scopes, Web API access requirements
- [references/data/site-settings.md](references/data/site-settings.md), site setting catalog (CSP, Web API enablement, feature flags)

### Pages + presentation

How a page is constructed and styled, the rendering surface users actually see.

- [references/pages/hybrid-page-idiom.md](references/pages/hybrid-page-idiom.md), Liquid render scaffold + JS mutate; base vs localized files
- [references/pages/styling-and-design.md](references/pages/styling-and-design.md), CSS load order, theme system, page templates vs web templates, Bootstrap 3→5 class mappings
- [references/pages/bundled-libraries.md](references/pages/bundled-libraries.md), what jQuery / Bootstrap / etc. ship with the platform and what's safe to assume

### Design systems + responsive composition

Use these when the user wants a portal that deliberately follows a named design system, combines systems, or needs stronger mobile/tablet guidance by default. Each per-system file embeds the full component catalog, token theory, license/foot-guns, and Power Pages implementation bias, model can answer most questions without fetching the canonical docs.

- [references/design-systems/README.md](references/design-systems/README.md), **start here**: layout, routing logic, what this layer does and doesn't cover
- [references/design-systems/system-selection.md](references/design-systems/system-selection.md), choose a primary system, borrow missing patterns safely, **special rule** for "primary is web-only but mobile-app feel needed (USWDS), ask iOS or Android"
- [references/design-systems/crossover-recipes.md](references/design-systems/crossover-recipes.md), concrete code: USWDS hero with Material 3 carousel, USWDS web with iOS-native feel, USWDS web with Android-native feel, Fluent 2 enterprise card with shadcn polish, shadcn product portal with USWDS form rigor, Apple HIG calm + USWDS civic seriousness
- [references/design-systems/responsive-defaults.md](references/design-systems/responsive-defaults.md), mobile-first, tablet, desktop, touch, density, forms, tables, motion defaults
- [references/design-systems/strict-csp.md](references/design-systems/strict-csp.md), assume strict CSP by default; keep design recommendations compatible with portal-local JS/CSS and tight `script-src`
- [references/design-systems/uswds-3.md](references/design-systems/uswds-3.md), U.S. Web Design System 3 (civic/government, web-only, no carousel, no mobile-app nav); full catalog + tokens
- [references/design-systems/material-3.md](references/design-systems/material-3.md), Material Design 3 (mobile-first, **carousel added in M3**, tonal palette, type scale); full catalog + tokens
- [references/design-systems/apple-hig.md](references/design-systems/apple-hig.md), Apple HIG (values + components reference; **critical: SF font and SF Symbols are not licensed for web**)
- [references/design-systems/fluent-2.md](references/design-systems/fluent-2.md), Microsoft Fluent 2 (closest fit to Power Pages out of the box, alias tokens, Segoe fallback); full v9 catalog
- [references/design-systems/shadcn-ui.md](references/design-systems/shadcn-ui.md), shadcn/ui (Radix + Tailwind under the hood; **treat as pattern source, not install target**); full registry + Lucide icon attribution

### Workflow + tooling

How you get code in and out of Dataverse and which adjacent tools to reach for.

- [references/workflow/sync-workflow.md](references/workflow/sync-workflow.md), `pac paportal` patterns, wrapper scripts, cache hangs, GCC vs commercial differences
- [references/workflow/microsoft-plugins.md](references/workflow/microsoft-plugins.md), when to defer to Microsoft's `dataverse` / `power-pages` / `canvas-apps` / `model-apps` / `mcp-apps` plugins instead of stretching this one

### Quality + compliance

Cross-cutting concerns that apply to everything above.

- [references/quality/accessibility.md](references/quality/accessibility.md), Microsoft's WCAG 2.2 / Section 508 / EN 301 549 commitment, what the platform handles, where customizations must intervene
- [references/quality/troubleshooting.md](references/quality/troubleshooting.md), blank pages, 401/403/404 from `/_api/`, OData errors, sync failures

## Permissions, roles, and security

Power Pages enforces **two layers**:

1. **Page-level access**, via `Page.webrole` references and the Authentication settings on the page record
2. **Record-level access**, via Table Permissions YAML, scoped by Web Role

A page that loads correctly for one user but errors for another is almost always a Table Permissions miss, not a Liquid bug. See [references/data/permissions-and-roles.md](references/data/permissions-and-roles.md).

User-context Liquid checks:

```liquid
{% if user %}                                {# authenticated #}
{% if user.roles contains 'Authenticated Users' %}
{% if user.contact.parentcustomerid.id %}    {# user belongs to an Account #}
```

## Sync workflow

Power Pages source code lives in **Dataverse**, not your repo. The workflow is:

```
pac paportal download → edit locally → pac paportal upload → test in browser
```

Naive `pac paportal download` regenerates files non-deterministically (timestamps, GUIDs reorder, `.portalconfig/` churn). Production projects wrap it in scripts that auto-stash known noise and only commit meaningful diffs. See [references/workflow/sync-workflow.md](references/workflow/sync-workflow.md) for:

- The `download` → `stash noise` → `commit` → `upload` cycle
- Wrapper script pattern (the `*-down.sh` / `*-up.sh` / `*-doctor.sh` / `*-commit.sh` family)
- Portal cache hangs after bulk uploads (and how to recover)
- PAC stale manifest errors after server-side deletes
- GCC vs commercial cloud differences

## NOT supported by this skill

- **Power Pages code sites** (React/Vue/Astro SPAs), use Microsoft's `power-pages` plugin
- **Shopify/Jekyll Liquid**, different objects, different tags, different filter behavior
- **Power Apps Canvas / Model-Driven apps**, different platform; use `canvas-apps` / `model-apps` plugins
- **Dataverse schema authoring** outside the portal, use the `dataverse` plugin (`dv-metadata`, `dv-data`, `dv-query`, `dv-solution`)
- **Power Automate Cloud Flows triggered from a portal**, Liquid embedding only; the flow itself is out of scope
