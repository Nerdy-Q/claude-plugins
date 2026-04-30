# pp-portal

A Claude Code skill for working in **classic Microsoft Power Pages** portals — the **hybrid Liquid + Web API pattern**. Server-rendered Liquid templates render the initial state; custom JavaScript calls `/_api/<entity>` for interactivity. Covers Web Templates, FetchXML in Liquid, Web API in custom JS, hybrid render-then-mutate pages, DotLiquid quirks, `pac paportal` sync, accessibility, and design-system composition for Material Design 3, Apple HIG, Fluent 2, USWDS 3, and shadcn/ui-style portals.

## What this is

This is a **knowledge skill**, not a runner skill. It provides the model with reference patterns, gotchas, and decision routing for hybrid Power Pages portals.

## Scope

- Power Pages classic portals (Studio + `pac paportal`-managed sites)
- Hybrid Liquid + Web API custom pages
- FetchXML query patterns (`{% fetchxml %}`)
- Power Pages entity tags (`{% entitylist %}`, `{% entityform %}`, `{% webform %}`)
- Web Roles, Table Permissions, Site Settings model
- DotLiquid-specific gotchas (JSON escape, date filters, comment syntax)
- `pac paportal` sync workflow patterns
- Accessibility (WCAG 2.2 / Section 508 / EN 301 549) commitments and gaps
- Design-system routing and crossover guidance for Material 3, Apple HIG, Fluent 2, USWDS 3, and shadcn/ui
- Responsive defaults for mobile and tablet optimization

**NOT for:**

- Power Pages **code sites** (React/Vue/Astro SPAs) — use Microsoft's `power-pages` plugin
- Shopify or Jekyll Liquid — different objects, tags, and filter behavior
- Power Apps Canvas / Model-Driven apps — use `canvas-apps` / `model-apps`
- Dataverse schema authoring outside the portal — use Microsoft's `dataverse` plugin (`dv-metadata`, `dv-data`, `dv-query`, `dv-solution`)

## Companion plugins

The portal sits on top of Dataverse. For adjacent work, defer to the right plugin instead of stretching this one:

| Task | Plugin | Skill |
|---|---|---|
| Dataverse environment setup, auth, MCP registration | Microsoft's `dataverse` | `dv-connect` |
| Dataverse data CRUD, queries, sample data | Microsoft's `dataverse` | `dv-data`, `dv-query` |
| Dataverse schema authoring (tables, columns, relationships) | Microsoft's `dataverse` | `dv-metadata` |
| Dataverse solution import/export | Microsoft's `dataverse` | `dv-solution` |
| Dataverse environment-level admin | Microsoft's `dataverse` | `dv-admin` |
| Dataverse security roles (NOT Power Pages Web Roles) | Microsoft's `dataverse` | `dv-security` |
| Power Pages **code sites** | Microsoft's `power-pages` | (whole plugin) |
| Canvas apps | Microsoft's `canvas-apps` | (whole plugin) |
| Model-driven apps | Microsoft's `model-apps` | (whole plugin) |
| MCP-app widgets | Microsoft's `mcp-apps` | (whole plugin) |

## Reference files

The skill loads `SKILL.md` first (router + critical gotchas). Detail lives in topic-specific reference files the model pulls on demand, grouped by responsibility:

### Language

- `references/language/operators.md` — Liquid operators, truthy / falsy
- `references/language/types.md` — Liquid type system
- `references/language/tags.md` — Power Pages tags (`{% fetchxml %}`, `{% entitylist %}`, `{% entityform %}`, `{% webform %}`, `{% editable %}`, `{% chart %}`, `{% include %}`, `{% block %}`/`{% extends %}`)
- `references/language/filters.md` — DotLiquid filter table + Power Pages-specific extensions
- `references/language/objects.md` — `user`, `page`, `website`, `request`, `weblinks`, `snippets`, `sitemarkers`, `settings`, `now`, `params`
- `references/language/dotliquid-gotchas.md` — DotLiquid behavioral differences from Shopify Liquid

### Data + integration

- `references/data/webapi-patterns.md` — `safeAjax`, GET/POST/PATCH/DELETE, `@odata.bind`, file upload
- `references/data/fetchxml-patterns.md` — count + paginate + filter, link-entity, aggregation
- `references/data/dataverse-naming.md` — the 4-name model + navigation property casing + error decoding
- `references/data/permissions-and-roles.md` — Web Roles, Table Permissions, Web API access requirements
- `references/data/site-settings.md` — site setting catalog

### Pages + presentation

- `references/pages/hybrid-page-idiom.md` — Liquid render scaffold + JS mutate; base vs localized
- `references/pages/styling-and-design.md` — CSS load order, theme system, Bootstrap 3→5 mappings
- `references/pages/bundled-libraries.md` — what jQuery / Bootstrap / etc. ship with the platform

### Design systems + responsive composition

- `references/design-systems/README.md` — index + routing logic; **start here**
- `references/design-systems/system-selection.md` — primary-system choice, safe crossover rules, **special rule for "USWDS is web-only — ask user iOS or Android for mobile-app feel"**
- `references/design-systems/crossover-recipes.md` — six concrete HTML/CSS/JS recipes: USWDS hero with Material 3 carousel, USWDS web with iOS-native feel, USWDS web with Android-native feel, Fluent 2 enterprise card with shadcn polish, shadcn product portal with USWDS form rigor, Apple HIG calm + USWDS civic seriousness
- `references/design-systems/responsive-defaults.md` — mobile-first and tablet defaults for layouts, forms, tables, and motion
- `references/design-systems/strict-csp.md` — strict-CSP-safe UI guidance for local JS/CSS, no runtime script injection, and low-dependency patterns
- `references/design-systems/uswds-3.md` — USWDS 3: full component catalog + tokens; **web-only, no native-app nav**
- `references/design-systems/material-3.md` — Material 3: full catalog (carousel was added in M3), tonal palette, type scale
- `references/design-systems/apple-hig.md` — Apple HIG: components reference + **critical SF font / SF Symbols license trap**
- `references/design-systems/fluent-2.md` — Fluent 2 React v9 catalog, alias tokens, Segoe UI fallback strategy
- `references/design-systems/shadcn-ui.md` — shadcn/ui registry; **pattern source, not install target**

### Workflow + tooling

- `references/workflow/sync-workflow.md` — `pac paportal` patterns, wrapper scripts, cache hangs
- `references/workflow/microsoft-plugins.md` — when to defer to Microsoft's plugins instead

### Quality + compliance

- `references/quality/accessibility.md` — WCAG 2.2 / Section 508 / EN 301 549, platform vs customization
- `references/quality/troubleshooting.md` — blank pages, 401/403/404, OData errors, sync failures

## Install

```bash
claude plugin marketplace add https://github.com/Nerdy-Q/claude-power-pages-plugins
claude plugin install pp-portal@nq-claude-power-pages-plugins
```

Or from a local checkout:

```bash
git clone https://github.com/Nerdy-Q/claude-power-pages-plugins
claude plugin marketplace add ./claude-power-pages-plugins
claude plugin install pp-portal@nq-claude-power-pages-plugins
```

## Verify it loaded

After install, ask Claude something like:

> What's the right pattern for a USWDS-first Power Pages portal that needs a carousel hero and still has to stay accessible on mobile?

The model should load `SKILL.md` and the relevant design-system references automatically.

## License

MIT
