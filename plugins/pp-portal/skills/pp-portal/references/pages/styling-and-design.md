# Power Pages Styling and Page Design

The CSS, theme, and page-design surface that wraps every Liquid page Power Pages renders. This file covers what a Liquid developer needs to know to make `{% fetchxml %}` results, custom hybrid pages, and entity-tag forms inherit theme colors, sit correctly inside the layout chrome, and respond to Studio styling changes.

> **Scope:** styling for **classic Power Pages** (Bootstrap-based, Liquid-rendered). Code sites (React/Vue/Astro SPAs) ship their own asset pipeline and ignore everything below.

## How a Power Pages page is assembled

Every rendered page is the composition of three concerns, layered top-down:

| Layer | Source | Editable from |
|---|---|---|
| **Layout chrome** (`<html>`, header, footer, navigation, body grid) | The page's **Page Template** → its **Web Template** (or fall back to website-level Header/Footer Templates) | Code only (Web Templates are Liquid + HTML; Studio cannot edit layout structure) |
| **Page content** (sections, columns, components inside the body) | The **Web Page** record's `adx_copy` (Liquid + HTML) | Studio Pages workspace + VS Code for the Web |
| **Visual styling** (colors, fonts, spacing, shadows) | CSS files: `bootstrap.min.css` + `theme.css` + `portalbasictheme.css` + custom CSS | Styling workspace + uploaded custom CSS files |

The Liquid developer's job is mostly the middle row, but they need to understand the other two to know which classes inherit the theme and which need explicit styling.

## CSS architecture

### File load order and precedence

Every Power Pages page loads three CSS files by default, in this order, plus any custom CSS files in the order shown in the Manage CSS panel:

```
1. bootstrap.min.css      ← framework reset + components
2. theme.css              ← Studio Styling workspace writes here (colors/fonts/buttons/sections)
3. portalbasictheme.css   ← Power Pages-specific component styles (entity tags, validation, etc.)
4. <custom CSS files…>    ← in panel order, top→bottom
```

**Override precedence (later wins):**

```
bootstrap.min.css  <  theme.css  <  custom CSS files (top of list)  <  portalbasictheme.css  <  custom CSS files (bottom of list)
```

This ordering is the surprising part. Microsoft documents it as: "Any custom CSS file is at lower priority than the default `portalbasictheme.css` and higher than `theme.css`." The Manage CSS panel lists files top→bottom in **load order**, but the panel note says "files listed at bottom take higher precedence", which means moving a file **down** the list makes it win cascade conflicts.

### Custom CSS lives where?

| Location | What goes there | When to use |
|---|---|---|
| **Web Files** (uploaded via Manage CSS or Portal Management → Web Files) | Site-wide stylesheets, served at `/<filename>.css` | Default. All shared theming/overrides go here. Files appear in the Manage CSS panel automatically when MIME type is `text/css`. |
| `<Page>.webpage.custom_css.css` (per-page) | CSS scoped to one Web Page | Page-specific overrides that shouldn't leak to other pages. Loads after the global custom CSS files. |
| `<Web Template>.webtemplate.source.html` `<style>` block | Component-level CSS scoped to a Web Template | Self-contained template that ships with its own styles. Avoid for site-wide rules. |
| Inline `style="..."` on elements | One-off tweaks | Studio's paintbrush tool writes here. Wins everything except `!important` in custom CSS. |

**Hard rule:** never deactivate, delete, or reorder `bootstrap.min.css`, `theme.css`, or `portalbasictheme.css`. The design studio errors out if you do, and recovery requires the Portal Management app to restore the default state and order.

### Custom CSS file constraints

| Constraint | Detail |
|---|---|
| Max size | 1 MB per file |
| Applies to | All themes (custom CSS is theme-independent, uploading does not bind to one theme) |
| Storage | `adx_webfile` records, `mimetype` = `text/css` |
| Delete | Delete the Web File record in Portal Management; then **Sync configuration** in Studio |
| Edit | Manage CSS → ellipsis → Edit code (opens VS Code for the Web) |

## Theme system

### What the Styling workspace produces

The Studio Styling workspace writes everything it controls into **`theme.css`**. There is no separate theme JSON, no documented CSS variable contract, and no `@font-size-base`-style Sass variable surface in the rendered output, Studio compiles your selections directly into static CSS rules in `theme.css`.

The workspace ships **13 preset themes**. Each theme defines:

| Configurable | Range |
|---|---|
| Color palette | 9 mapped colors + 3 user-selected slots (12 total). Hex, RGB, or color picker. |
| Background color | One per theme. Known issue affects sites created before Sept 23, 2022, see [Adjusting the background color](https://learn.microsoft.com/en-us/power-pages/known-issues#adjusting-the-background-color-for-your-power-pages-site). |
| Font styles | Heading 1–6 + body. Family, weight, size, color. **Basic fonts + 30+ Google Fonts** available. |
| Button styles | Primary/secondary button colors, borders, radius. |
| Section margins | Spacing between sections on a page. |

When you select a preset and tweak it, Studio shows a "modified" indicator next to the theme name. Reset → ellipsis → "Reset to default" rewrites `theme.css` from the preset.

### Why this matters for the Liquid developer

There is **no documented CSS variable surface** to target. If you write `var(--primary-color)` in custom CSS hoping to inherit Studio's primary color, it will not work, Studio's output is plain CSS rules against Bootstrap selectors and a few Power-Pages-specific class names, not custom properties.

To make custom UI inherit theme colors, the practical patterns are:

1. **Use Bootstrap classes the theme already styles** (`.btn-primary`, `.bg-primary`, `.text-primary`, `.alert-danger`, `.panel-default`, etc. for BS3; `.card`, `.btn-primary`, `.alert-danger` etc. for BS5). Studio's `theme.css` overrides these, so your custom UI picks up theme colors automatically.
2. **Define your own CSS variables in custom CSS** and update them when themes change. There is no Studio hook to do this, you must manually mirror Studio's palette into your own `--my-primary: #0F5C63;` variables.
3. **Read computed styles in JS** if you need theme colors at runtime: `getComputedStyle(document.querySelector('.btn-primary')).backgroundColor`.

### Color palette mapping

The preset palette maps slots to elements (button bg, button text, header bg, link color, etc.). Microsoft does not publish the slot→selector mapping, so the only way to discover which slot drives which element is to change a slot in Studio and observe the rendered CSS in `theme.css`. **If you customize an individual element via the paintbrush, the slot mapping no longer applies until you Reset to default.**

## Page templates vs Web templates

The two-record model is the design-time separation Power Pages uses:

| Concept | Record | Owns |
|---|---|---|
| **Web Template** | `adx_webtemplate` | The actual Liquid + HTML source |
| **Page Template** | `adx_pagetemplate` | The chrome decision (use header/footer? which Web Template? legacy ASPX?) |
| **Web Page** | `adx_webpage` | The page slug, sitemap position, and `adx_copy` content; references one Page Template |

Resolution order at request time:

```
URL  →  Web Page (matches partial URL)
        ↓
        Web Page.adx_pagetemplate  →  Page Template
                                       ↓
                                       if type = Web Template:  render Web Template (Liquid)
                                       if type = Rewrite:       render legacy ASPX
                                       ↓
                                       Web Template renders, ${page.adx_copy} interpolates the
                                       Web Page's body content into a {% include 'page_copy' %} hole
```

### Page Template attributes

| Field | Detail |
|---|---|
| `Type` | **Web Template** (modern, Liquid-driven) or **Rewrite** (legacy ASPX). New page templates should always be Web Template. |
| `Web Template` | Reference to the `adx_webtemplate` record that renders this page. Required when Type = Web Template. |
| `Rewrite URL` | ASPX path. Required when Type = Rewrite. Limited to default ASPX pages. |
| `Use Website Header and Footer` | Default checked. When checked, the Web Template renders only the body, the website-level header/footer wrap it. When unchecked, the Web Template renders the entire response from `<!DOCTYPE>` onward. |
| `Is Default` | The default selected option in Studio's "create new page" dropdown. |
| `Table Name` | Restricts which Power Pages content tables can use this template. Almost always `adx_webpage`. |

### Why entityform/webform require Web Template type

`{% entityform %}` and `{% webform %}` only render when the hosting page uses a **Web-Template-based** Page Template. A Rewrite-based page template silently fails to render the form, no error, no warning, just an empty space. Diagnose by checking the Page Template's `adx_type` field. This is the single most common cause of "my form doesn't show up."

### Built-in Web Templates

Power Pages ships these as `{% include %}`-able partials. The "Layout" templates are designed to be `{% extends %}`-ed:

| Name | Purpose |
|---|---|
| `layout_1_column` | Single column with breadcrumbs + page title |
| `layout_2_column_wide_left` | Two columns; main copy on left |
| `layout_2_column_wide_right` | Two columns; main copy on right |
| `layout_3_column_wide_middle` | Three columns; main copy middle |
| `page_copy` | Renders editable `adx_copy` HTML with embedded Liquid |
| `page_header` | Page title block |
| `breadcrumbs` | Ancestor-chain links |
| `top_navigation` | Primary nav bar with dropdowns |
| `side_navigation` | Vertical tree-view nav |
| `child_link_list_group` | Children of current page in a Bootstrap list-group |
| `weblink_list_group` | Web Link Set rendered as a list-group |
| `search` | Basic search form |
| `snippet` | Renders an editable Content Snippet by name |
| `ad`, `blogs`, `events_upcoming`, `forums`, `poll` | Module-specific |

### Header and footer

By default, the website uses Power Pages' built-in header/footer Web Templates. To replace them, set the website record's **Header Template** and **Footer Template** lookups to your custom Web Templates. Custom headers must take over rendering primary nav, sign-in/out, search, none of those come back automatically.

The Pages workspace **cannot delete** the header or footer; they are structural. To customize them you edit the Web Templates directly via VS Code for the Web ("Edit site header" → "Edit code").

## Bootstrap classes used by entity tags

Power Pages ships two supported Bootstrap versions: **3.3.6** (default for legacy and pre-enhanced-data-model sites) and **5.x** (only available with the [enhanced data model](https://learn.microsoft.com/en-us/power-pages/admin/enhanced-data-model)). To check a site's version, inspect the `bootstrap.min.css` Web File or look for the `Site/BootstrapV5Enabled` Site Setting.

### What entity tags render (BS3 default)

| Tag | Default chrome | Key classes to target |
|---|---|---|
| `{% entitylist %}` (with nested `entityview`) | `<table class="table table-striped">` inside a wrapper `<div>`; pagination via `<ul class="pagination">`; search input via `.input-group`; view-switch dropdown via `.dropdown` | `.entitylist`, `.entity-grid`, `.table.table-striped`, `.view-toolbar`, `.grid-actions` |
| `{% entityform %}` | Bootstrap horizontal form; `<div class="form-group">` per field; labels in `.col-sm-3`, inputs in `.col-sm-9`; submit button `.btn.btn-primary`; validation summary `.validation-summary.alert.alert-danger.alert-block` | `.entityform`, `.form-group`, `.help-block` (validation messages), `.has-error`, `.has-success` |
| `{% webform %}` | Same form chrome as entityform plus a step indicator `<ul class="progress-bar">`-style breadcrumb at top | `.webform`, `.entityform`, `.webform-progress` |
| `{% chart %}` | `<div>` container; chart rendered by Power Pages' chart JS into `<canvas>` or SVG | `.chart-container` |
| `{% powerbi %}` | `<iframe>` or `<div>` with embedded report | `.powerbi-container` |

The **default validation summary class** is configurable via the basic form's `Validation Summary CSS Class` field, default value `validation-summary alert alert-error alert-block` (note: `alert-error` is the BS3 class, BS5 changed this to `alert-danger`).

### Custom-CSS targeting recipes

```css
/* Tighten an entitylist table */
.entitylist .table { font-size: 0.9rem; }
.entitylist .table thead th { background: #f5f5f5; }

/* Highlight required form fields */
.entityform .form-group.required > label::after {
  content: " *";
  color: #c00;
}

/* Make validation messages more visible */
.entityform .validation-summary.alert {
  border-left: 4px solid #c00;
  font-weight: 500;
}

/* Style a fetchxml-rendered Bootstrap table to match entitylist */
.fetchxml-table .table { /* same selectors entitylist uses */ }
```

## Bootstrap 3 → Bootstrap 5: what changes for the data developer

If you migrate a site (`pac pages bootstrap-migrate -p <folder>`), Microsoft's tool rewrites known class names, but custom CSS that targets BS3 classes does not auto-update. Audit your custom CSS for these:

| BS3 → BS5 | Where it bites |
|---|---|
| `.panel`, `.panel-default`, `.panel-heading`, `.panel-body`, `.panel-footer` → `.card`, `.card-header`, `.card-body`, `.card-footer` | Any custom panel UI; the web-template-component sample in MS Learn uses `.panel-*` heavily |
| `.btn-default` → `.btn-secondary` | Theme button styling; entity-tag default buttons |
| `.alert-error` → `.alert-danger` | Validation summary class, set `Validation Summary CSS Class` on the form record |
| `.well` → `.card` (or removed) | Snippet wrappers in older custom code |
| Glyphicons → removed (use Bootstrap Icons or your own) | `<span class="glyphicon glyphicon-edit">` no longer renders |
| `.col-xs-N` → `.col-N` (xs implicit) | Grid breakpoints |
| `.col-sm-offset-N` → `.offset-sm-N` | Layout offsets |
| `.hidden-xs/sm/md/lg` → `.d-none .d-sm-block` etc. | Responsive visibility |
| `.text-muted` (still works) | Same name in both |
| `.form-horizontal` (BS3) → built-in form layout (BS5 dropped horizontal-by-default) | Entity form rendering shifts; form-group classes also changed |

**Site setting that controls BS5:** `Site/BootstrapV5Enabled` (created automatically when you migrate or create a new site under enhanced data model). To revert to BS3, run the upload command to replace the V5 folder with a V3 folder, **then delete `Site/BootstrapV5Enabled`** from Site Settings, then clear server cache.

**Hard constraint:** site developers should not replace Bootstrap with Tailwind, Bulma, or other frameworks. Several Power Pages internals (entity tags, Studio's design surface, validation rendering) depend on Bootstrap selectors being present. Your custom CSS layers on top, it does not replace the framework.

## Studio surface vs code-only surface

| Capability | Studio (Pages/Styling workspace) | VS Code for the Web | Portal Management app |
|---|---|---|---|
| Edit page sections + components | Yes (WYSIWYG) | Yes (raw HTML/Liquid) | Edit `Copy (HTML)` field |
| Add/remove sections | Yes | Indirectly (HTML editing) | Indirectly |
| Style a section/component (paintbrush) | Yes (writes inline `style=`) | No (you can write inline manually) | No |
| Edit the global theme (color/font) | Yes | No | No |
| Upload custom CSS | Yes | Edit the file content | Manage as Web File |
| Reorder/disable custom CSS | Yes | No | No |
| Edit a Web Template | No | Yes | Yes |
| Create a Web Template | No | No | Yes (Content → Web Templates) |
| Edit a Page Template | No | No | Yes (Website → Page Templates) |
| Create a Page Template | No | No | Yes |
| Edit Header/Footer Web Template | "Edit site header" → opens VS Code | Yes | Yes |
| Edit a Content Snippet | Inline `editable` regions on page | Yes | Yes (Content → Content Snippets) |
| Edit Custom JS / Custom CSS on a page | "Edit code" → opens VS Code | Yes | Web page record → Advanced tab |
| Configure Site Settings | No | No | Yes (Website → Site Settings) |

**Studio paintbrush precedence:** styles applied via the paintbrush write inline `style=` attributes on the rendered HTML. Inline styles win over external CSS unless your custom CSS uses `!important`. So the cascade in practice is:

```
bootstrap.min.css  <  theme.css  <  custom CSS (no !important)  <  portalbasictheme.css
   <  custom CSS (lower in panel)  <  Studio paintbrush inline styles  <  custom CSS with !important
```

## Content snippets in the design context

Snippets are editable content blocks decoupled from page Liquid. They are the design-system primitive for "text or HTML that branding/marketing will edit, but the structure is fixed."

### Three ways to render a snippet

```liquid
{# 1. Raw value, use when the snippet is plain content, no edit affordance #}
{{ snippets["Footer Disclaimer"] }}

{# 2. Inline editable, users with permission see an edit pencil on the page #}
{% editable snippets["Footer Disclaimer"] %}

{# 3. Built-in include wrapper, equivalent to #2 but uses the canonical 'snippet' Web Template #}
{% include 'snippet' snippet_name:'Footer Disclaimer' %}
```

| Snippet attribute | Detail |
|---|---|
| `Type` | `Text` or `HTML`. HTML allows tags + Liquid; Text is plain. |
| `Content Snippet Language` | One snippet per language. Power Pages picks the row matching the user's locale. |
| `Value` | The body. May contain Liquid (the `editable` tag and `include 'snippet'` both pre-parse Liquid by default). |

### Common design-related snippets

Default sites ship snippets like (names vary by template): `Account/SignIn/PageTitle`, `Profile/SignInCallToAction`, `Footer/Disclaimer`, `Search/Title`, `Logo` (sometimes). The Studio Pages workspace surfaces some of these as inline-editable regions automatically; for the rest, the developer wires them up via `{% editable %}`.

### Snippets vs site settings: when to use which

| Use a Content Snippet for | Use a Site Setting for |
|---|---|
| Display text, HTML fragments, marketing copy | Configuration values (booleans, IDs, URLs, feature flags) |
| Anything the marketing team should edit | Anything that affects code behavior, not display |
| Localized content (one per language) | Single value per site |
| `Footer Disclaimer`, `Welcome message` | `Search/Enabled`, `Site/BootstrapV5Enabled`, `Webapi/<entity>/Enabled` |

## Logo, favicon, and navigation

| Asset | Where it lives | How to change |
|---|---|---|
| Logo image | Web File (`/logo.png` or whatever the template names it). Some templates render it from a Content Snippet. | Replace the Web File, or edit the snippet. The header Web Template controls the actual `<img src=…>` reference. |
| Favicon | Web File at `/favicon.ico` or referenced via a `<link rel="icon">` in the header Web Template | Replace the Web File. |
| Primary navigation | **Web Link Set** named `Primary Navigation` (rendered by the `top_navigation` built-in Web Template) | Studio Pages workspace → site map; or Portal Management → Web Link Sets → Primary Navigation |
| Footer links | Usually a Web Link Set + footer Web Template | Edit footer Web Template + Web Link Set |
| Sign-in / profile menu | `top_navigation` built-in template renders these from the user object + a few snippets | Override by replacing `top_navigation` or by setting a custom Header Template on the website record |

## Patterns: rendering Dataverse data with theme-consistent chrome

The recurring "render data with proper chrome" pattern: use `{% fetchxml %}` for the data, then wrap the result in Bootstrap classes that the theme already styles. The result inherits theme colors and fonts automatically.

### Themed list (Bootstrap-styled FetchXML results)

```liquid
{% fetchxml customers %}
<fetch mapping="logical">
  <entity name="contact">
    <attribute name="contactid"></attribute>
    <attribute name="fullname"></attribute>
    <attribute name="emailaddress1"></attribute>
    <attribute name="telephone1"></attribute>
    <order attribute="fullname"></order>
    <filter type="and">
      <condition attribute="statecode" operator="eq" value="0"></condition>
    </filter>
  </entity>
</fetch>
{% endfetchxml %}

<div class="container">
  <h2 class="page-header">{% editable snippets["Customers/PageTitle"] | default: "Customers" %}</h2>

  {% if customers.results.entities.size > 0 %}
    <div class="table-responsive">
      <table class="table table-striped table-hover">
        <thead>
          <tr>
            <th>Name</th><th>Email</th><th>Phone</th>
          </tr>
        </thead>
        <tbody>
          {% for c in customers.results.entities %}
            <tr>
              <td>{{ c.fullname }}</td>
              <td><a href="mailto:{{ c.emailaddress1 }}">{{ c.emailaddress1 }}</a></td>
              <td>{{ c.telephone1 }}</td>
            </tr>
          {% endfor %}
        </tbody>
      </table>
    </div>
  {% else %}
    <div class="alert alert-info">No customers to display.</div>
  {% endif %}
</div>
```

`.table`, `.table-striped`, `.table-hover`, `.alert`, `.alert-info`, `.page-header` are all Bootstrap classes that `theme.css` overrides for color, the rendered table picks up the active theme's primary/accent colors with no further work.

### Themed card grid (BS3 panels / BS5 cards)

```liquid
{# BS3 #}
<div class="row">
  {% for r in reviews.results.entities %}
    <div class="col-md-4">
      <div class="panel panel-default">
        <div class="panel-heading">
          {{ r.cr54f_name }}
          <span class="badge pull-right">{{ r.cr54f_rating }}</span>
        </div>
        <div class="panel-body">{{ r.cr54f_content }}</div>
      </div>
    </div>
  {% endfor %}
</div>

{# BS5, same data, migrated chrome #}
<div class="row g-3">
  {% for r in reviews.results.entities %}
    <div class="col-md-4">
      <div class="card">
        <div class="card-header d-flex justify-content-between">
          <span>{{ r.cr54f_name }}</span>
          <span class="badge bg-secondary">{{ r.cr54f_rating }}</span>
        </div>
        <div class="card-body">{{ r.cr54f_content }}</div>
      </div>
    </div>
  {% endfor %}
</div>
```

### Custom page layout that inherits the global header/footer

```html
{# web-templates/two-column/Two Column.webtemplate.source.html #}
<div class="container">
  <div class="page-heading">
    <ul class="breadcrumb">
      {% for crumb in page.breadcrumbs %}
        <li><a href="{{ crumb.url }}">{{ crumb.title }}</a></li>
      {% endfor %}
      <li class="active">{{ page.title }}</li>
    </ul>
    <div class="page-header"><h1>{{ page.title }}</h1></div>
  </div>
  <div class="row">
    <div class="col-sm-4 col-lg-3">{% block sidebar %}{% endblock %}</div>
    <div class="col-sm-8 col-lg-9">{% block content %}{% endblock %}</div>
  </div>
</div>
```

Then a Page Template record with **Type = Web Template**, **Web Template = Two Column**, **Use Website Header and Footer = checked**, and the Web Page references this Page Template. Children pages do `{% extends 'Two Column' %}` and override the blocks.

## Common mistakes and gotchas

| Mistake | Symptom | Fix |
|---|---|---|
| Rewrite-based Page Template hosting `entityform` | Form silently doesn't render | Convert Page Template to Web Template type |
| Hardcoded `#0F5C63` in custom CSS | Studio theme changes don't propagate to your custom UI | Use Bootstrap class names or define your own variables and update them with each theme change |
| `var(--primary-color)` in custom CSS expecting Studio variables | Empty value; styles default | There is no documented CSS variable surface; Studio writes plain CSS rules |
| Custom CSS targets BS3 classes (`.panel`, `.btn-default`) on a BS5 site | Styles miss after migration | Audit and rename per the BS3→BS5 mapping table |
| Custom CSS file deactivated to "test" | Manage CSS panel errors and won't open | Restore via Portal Management → Web Files; reactivate the missing default; Sync configuration |
| Two `entityform` tags on one page | Second one renders nothing | Split into two pages (one form per page is hard-wired) |
| Edited `theme.css` directly (e.g. via Web Files) | Studio resets it on next Save Changes | Always use the Studio Styling workspace; if you need overrides, put them in custom CSS instead |
| `{% include 'snippet' snippet_name: my_var %}` where `my_var` is empty | Renders empty without error | Use `default:` filter: `snippet_name: my_var | default: 'Fallback'` |
| Studio paintbrush wins over your custom CSS | Custom rules ignored | Either remove the inline style via Studio (delete the paintbrush change) or add `!important` to the custom CSS rule |
| Custom CSS rule moved to top of Manage CSS list expecting "first wins" | Other files override it | The bottom of the list wins; move the file down |
| Header/footer changes not reflecting | Output cache stale | Header/footer caching is per-template; clear server-side cache (Admin → Clear server-side cache → metadata/configuration) |
| Custom CSS file > 1 MB | Upload rejected | Split into multiple files or minify |

> Verified against Microsoft Learn 2026-04-29.
