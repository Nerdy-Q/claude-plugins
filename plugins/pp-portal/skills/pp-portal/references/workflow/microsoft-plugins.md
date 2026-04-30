# Microsoft's Power Platform Plugins: When to Defer

`pp-portal` is the **hybrid classic-portal skill**. Microsoft maintains a fleet of official Claude Code plugins covering the rest of the Power Platform surface. When a request is in their wheelhouse, install and use **theirs**, don't rebuild it inside `pp-portal`.

This file is the routing map.

## The Microsoft marketplace

Source: `https://github.com/microsoft/power-platform-skills`

One marketplace, multiple plugins. Each plugin targets a different Power Platform surface and ships its own focused skills.

```bash
# Add the marketplace once:
claude plugin marketplace add https://github.com/microsoft/power-platform-skills
```

## Plugin inventory

### `dataverse`, platform-side data and schema

The most common companion to `pp-portal`. Eight skills, all `dv-` prefixed:

| Skill | Use for |
|---|---|
| `dv-overview` | Router/decision-tree skill that picks among the others |
| `dv-connect` | One-step env setup, MCP server registration, `.env` writing, PAC CLI auth bootstrap |
| `dv-data` | CRUD records, bulk import, CSV, multi-table FK loads, AI-generated sample data (Python SDK) |
| `dv-metadata` | Schema authoring, tables, columns, relationships, forms, views (Python SDK + Web API) |
| `dv-query` | Bulk reads, multi-page iteration, analytics, pandas DataFrame workflows |
| `dv-solution` | Solution lifecycle, create, export, import, promote across envs |
| `dv-admin` | Env-level admin, bulk delete, retention, audit, OrgDB settings, recycle bin, 37 PPAC toggles |
| `dv-security` | Security roles, user access, application users, business units, admin elevation |

### `power-pages`, Microsoft's, **for code sites only**

Built for **Power Pages code sites**, React/Vue/Angular/Astro SPAs that call the Web API directly. **NOT** for classic Liquid portals (that's `pp-portal`'s job).

15 skills + 4 specialized agents (data-model-architect, table-permissions-architect, webapi-settings-architect, webapi-integration).

### `canvas-apps`

Build Canvas Apps via the Canvas Authoring MCP server. For `pa-yaml` format and `.msapp` deployment.

### `model-apps`

Build and deploy generative pages for Power Apps model-driven apps. For genux + model-driven app development.

### `code-apps-preview`

Power Apps **Code Apps**, React + Vite + Power Platform connectors. Different surface from Power Pages code sites.

### `mcp-apps`

Generate MCP App widgets for MCP tools.

## Decision routing

### Dataverse-side scenarios → `dataverse` plugin

| User request | Skill |
|---|---|
| "Set up a new Power Pages dev environment" / "authenticate to Dataverse" / "register the Dataverse MCP server" | `dv-connect` |
| "Query Dataverse data outside the portal" / "run a multi-page Web API query" / "load data into pandas" | `dv-query` |
| "Create a new Dataverse table" / "add a column" / "set up a relationship/lookup" / "modify a form" | `dv-metadata` |
| "Insert/update/delete records in Dataverse" / "bulk import a CSV" / "load FK-related data" / "seed sample data" | `dv-data` |
| "Export the Dataverse solution" / "import the solution to another env" / "promote to prod" | `dv-solution` |
| "Bulk delete in Dataverse" / "configure audit" / "retention policy" / "OrgDB setting" | `dv-admin` |
| "Assign a Dataverse security role" / "add a user" / "create an application user" / "elevate myself to admin" | `dv-security` |

### Power Pages **code sites** → Microsoft's `power-pages` plugin

| User request | Plugin |
|---|---|
| "Build a React SPA Power Page" / "deploy code site" / "Vite + Power Pages" | `power-pages` (Microsoft's) |
| "Set up Power Pages Web API for code site" / "Code Site data model" | `power-pages` (Microsoft's) |

### Other Power Apps surfaces

| User request | Plugin |
|---|---|
| "Build a Canvas App" / "modify pa-yaml" / "deploy msapp" | `canvas-apps` |
| "Build a model-driven app" / "create generative pages" | `model-apps` |
| "Power Apps Code Apps with React" | `code-apps-preview` |
| "MCP App widget" / "MCP tool UI" | `mcp-apps` |

### What `pp-portal` is for (so the contrast is clear)

| Surface | Stay here |
|---|---|
| `*.webpage.copy.html`, `*.webtemplate.source.html`, `*.webpage.custom_javascript.js` | `pp-portal` |
| Hybrid Liquid + Web API custom JS | `pp-portal` |
| `{% fetchxml %}` blocks in Liquid | `pp-portal` |
| `{% entitylist %}`, `{% entityform %}`, `{% webform %}`, `{% editable %}`, `{% chart %}` | `pp-portal` |
| Power Pages Web API in custom JS (`safeAjax` + `__RequestVerificationToken`) | `pp-portal` |
| Portal Web Roles + Table Permissions + Site Settings YAML | `pp-portal` |
| `pac paportal sync` workflow | `pp-portal` / `pp-sync` |

## Recognition triggers

When the user's request lands in another plugin's wheelhouse, recognize the mismatch and recommend, don't silently rebuild.

| User request | Recognize as | Recommend |
|---|---|---|
| "Connect me to Dataverse" / "set up MCP for Dataverse" | Dataverse env setup | `dv-connect` + offer to install `dataverse` plugin |
| "Add a new column to the contact table" | Dataverse schema | `dv-metadata` + offer to install `dataverse` plugin |
| "Run this FetchXML and put results in a DataFrame" | Multi-page query analytics | `dv-query` + `dataverse` plugin |
| "Export the solution to test env" | Solution lifecycle | `dv-solution` |
| "Build a React Power Page" | Code site | Microsoft's `power-pages` plugin |
| "Edit `Customers.webpage.copy.html`" | Hybrid classic portal | Stay in `pp-portal` |
| "Run `pac paportal upload`" | Portal sync | Stay in `pp-sync` |

## Install commands

```bash
# Microsoft's dataverse plugin (most common companion):
claude plugin marketplace add https://github.com/microsoft/power-platform-skills
claude plugin install dataverse@power-platform-skills

# Other Microsoft plugins from the same marketplace (install on demand):
claude plugin install power-pages@power-platform-skills        # for code sites
claude plugin install canvas-apps@power-platform-skills
claude plugin install model-apps@power-platform-skills
claude plugin install code-apps-preview@power-platform-skills
claude plugin install mcp-apps@power-platform-skills
```

## How `pp-portal` proposes installation

When the user's request lands in another plugin's wheelhouse:

1. **Recognize** the wheelhouse mismatch
2. **Tell the user**: "This is X-territory; Microsoft's Y plugin is the right tool"
3. **Offer to install**: "Want me to add their marketplace and install Y?"
4. **Don't silently rebuild** the functionality

Example response when the user says "I need to add a new column to the Contact table":

> That's Dataverse schema work, not portal work. Microsoft's `dataverse` plugin has a `dv-metadata` skill purpose-built for that, it uses the Python SDK + Web API and handles forms and views in one go.
>
> Want me to add Microsoft's `power-platform-skills` marketplace and install `dataverse`? Then I'll hand off to `dv-metadata`.

## Why we don't rebuild

Microsoft's plugins are:

- **Maintained by Microsoft**, first-party source of truth
- **Version-pinned to PAC CLI updates**, they track tool churn so we don't have to
- **Get security fixes** through the official release pipeline
- **Tested across environment versions** (Commercial, GCC, GCC High)

Building parallel `pp-portal` versions of `dv-metadata` or `dv-data` would:

- Duplicate work Microsoft already ships
- Drift from Microsoft's source of truth as PAC CLI evolves
- Create version confusion for the developer ("is this the official one or the pp-portal one?")

`pp-portal`'s value is in covering the **hybrid classic-portal surface** that Microsoft's plugins explicitly don't:

- Their `power-pages` plugin is for **code sites** (SPA)
- Their `dataverse` plugin is **platform-side**, not portal-side
- Nobody else covers Liquid + Web API custom JS in classic portals

That gap is the reason `pp-portal` exists. Everything else, hand off.

## Cross-references

- See [../data/webapi-patterns.md](../data/webapi-patterns.md) for Power Pages Web API in **classic portals** (NOT to be confused with Microsoft's `power-pages` plugin's Web API, which is for code sites)
- See [sync-workflow.md](sync-workflow.md) for `pac paportal` patterns (also not in Microsoft's plugins)
- See `pp-sync`'s `pp` CLI for portal-sync workflow

---

> Verified against Microsoft's `power-platform-skills` marketplace 2026-04-29.
