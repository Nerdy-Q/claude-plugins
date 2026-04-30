# Power Pages Recipes

Step-by-step walkthroughs of common production patterns. Each recipe is a complete "here's how you build this thing end-to-end", Liquid template + custom JS + permissions + site settings + gotchas, not just snippets.

The reference files in `../data/`, `../language/`, `../pages/`, and `../quality/` are the **canonical surface** (Microsoft documentation distilled into reference tables). The recipes are the **applied surface**: how those primitives compose into the four or five page shapes you'll build over and over.

## The five recipes

| Recipe | One-liner | Tags |
|---|---|---|
| [paginated-list-page.md](paginated-list-page.md) | Server-rendered table with search box and page links, the read side of CRUD | data-fetch, navigation |
| [hybrid-form-with-safeajax.md](hybrid-form-with-safeajax.md) | Liquid renders the form; JS submits to `/_api/<entityset>` and redirects on success | form-submit, security |
| [dependent-dropdown.md](dependent-dropdown.md) | Account picks populates Branches via Web API GET, the cascade pattern | data-fetch, navigation |
| [file-upload-annotations.md](file-upload-annotations.md) | Multi-file upload via `/_api/annotations` with progress UI | attachment, form-submit |
| [role-gated-section.md](role-gated-section.md) | Show/hide UI by Web Role, Liquid first, JS as defense-in-depth | security |

## Start here if...

| You're building... | Read this first |
|---|---|
| **A table of records that needs search and pagination** | [paginated-list-page.md](paginated-list-page.md) |
| **A "create a record" form** | [hybrid-form-with-safeajax.md](hybrid-form-with-safeajax.md) |
| **A select that fills a second select** | [dependent-dropdown.md](dependent-dropdown.md) |
| **An "Attach files to this record" feature** | [file-upload-annotations.md](file-upload-annotations.md) |
| **An admin-only button or panel** | [role-gated-section.md](role-gated-section.md) |
| **A details/edit page** | Combine [paginated-list-page.md](paginated-list-page.md) (single-record FetchXML) + [hybrid-form-with-safeajax.md](hybrid-form-with-safeajax.md) (PATCH instead of POST) |
| **A wizard / multi-step form** | Probably `{% webform %}` (Multi-step Form). See `../language/tags.md`. Only fall back to a hybrid wizard when the chrome is genuinely insufficient |

## How recipes relate to references

Each recipe assumes you've at least skimmed the relevant reference file. If you find yourself stuck on a step, the recipe will link out to the reference for deeper context. The recipes are tutorial-shaped (linear, complete); the references are encyclopedia-shaped (random-access, exhaustive).

| When the recipe says... | Look in... |
|---|---|
| "Add the canonical safeAjax helper" | `../data/webapi-patterns.md` |
| "Set `Webapi/<entity>/enabled = true`" | `../data/site-settings.md` |
| "Use a Table Permission with Account scope" | `../data/permissions-and-roles.md` |
| "Use the entity set name in the URL" | `../data/dataverse-naming.md` |
| "Build the FetchXML count + paginate query" | `../data/fetchxml-patterns.md` |
| "Wrap user-derived content with `escape`" | `../language/filters.md` |
| "Read `user.roles` / `request.params['x']`" | `../language/objects.md` |
| "The `if`/`elsif`/`for` loops" | `../language/tags.md` |
| "Why JSON in Liquid is weird" | `../language/dotliquid-gotchas.md` |
| "What `aria-live` should announce on load" | `../quality/accessibility.md` |
| "Is the page rendering blank?" | `../quality/troubleshooting.md` |

## Conventions

All recipes use the fictional companies **Acme**, **Contoso**, and **Acme/Contoso** custom entities (`contoso_officebranch`, `contoso_application`, etc.), no client identifiers. Where a recipe needs a Web Role name, it uses `Admin`, `Support`, `Customer`, `Anonymous Users`, or `Authenticated Users`. Where a recipe needs a sitemarker, it picks a name that matches the page (`Customers`, `Add Customer`, `Attach Files`).

Code blocks use language tags (`liquid`, `javascript`, `html`, `yaml`, `bash`) so the syntax highlighter is honest about what's being shown. When a code block mixes Liquid and HTML (which is most of them on the server side), the tag is `liquid`.

## What's intentionally NOT here

- **`{% entityform %}` walkthroughs**, when an entityform is the right tool, you don't need a recipe; the chrome is generated. See `../language/tags.md` for the tag reference.
- **`{% entitylist %}` walkthroughs**, same reason.
- **Master layout / site-wide JS / theme customization**, these live in `../pages/styling-and-design.md` because they're not page recipes, they're site-level concerns.
- **OAuth / B2C identity setup**, environment-level configuration, not page-level patterns. See `../data/site-settings.md` Authentication section.
