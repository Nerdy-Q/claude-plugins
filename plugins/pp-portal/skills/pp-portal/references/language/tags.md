# Power Pages Liquid Tag Reference

Verified reference for every Liquid tag Power Pages ships, grouped by category as Microsoft Learn organizes them. Scope is the tag surface, for filters and objects, see the sibling references.

Categories map directly to Microsoft Learn pages under `learn.microsoft.com/en-us/power-pages/configure/liquid/`:

- [Control flow](https://learn.microsoft.com/en-us/power-pages/configure/liquid/control-flow-tags), `if`, `unless`, `case`
- [Iteration](https://learn.microsoft.com/en-us/power-pages/configure/liquid/iteration-tags), `for`, `cycle`, `tablerow`
- [Variable](https://learn.microsoft.com/en-us/power-pages/configure/liquid/variable-tags), `assign`, `capture`
- [Template](https://learn.microsoft.com/en-us/power-pages/configure/liquid/template-tags), `include`, `block`, `extends`, `comment`, `raw`, `substitution`, `fetchxml`, `codecomponent`
- [Dataverse](https://learn.microsoft.com/en-us/power-pages/configure/liquid/dataverse-liquid-tags), `chart`, `powerbi`, `editable`, `entitylist`, `entityview`, `searchindex`, `entityform`, `webform`

This file gives full attribute coverage for the Power-Pages-specific tags (template + Dataverse) and a quick reference for the standard Liquid tags. For the standard tags, link out for full operator/filter docs.

## Tag selection guide

| You want to render | Use | Notes |
|---|---|---|
| A configured Dataverse list with paging/search/sort | `entitylist` + nested `entityview` | Both metadata-driven; one form/list per page rule applies to forms, not lists |
| A specific saved view inline | `entityview` (standalone) | Useful when you don't need the entitylist chrome |
| A Dataverse search result page | `searchindex` | Lucene-strict filter syntax |
| A single-step CRUD form | `entityform` | One per page; web-template page templates only |
| A multi-step wizard form | `webform` | One per page; same hosting rules as `entityform` |
| A saved Dataverse chart | `chart` | GUIDs only |
| An embedded Power BI tile/report | `powerbi` | `path` required; `authentication_type` defaults to Anonymous |
| Inline-editable snippet/page text | `editable` | `liquid: true` is the default, pre-parsed |
| A code component (PCF) | `codecomponent` | Pass props as `propName:'value'` |
| FetchXML query results | `fetchxml` | Self-closing `<attribute/>` is forbidden |
| A reusable Liquid partial | `include` | Comma-separated kwargs, no `with` keyword |
| Page Template inheritance | `extends` + `block` | `extends` MUST be the first content in the file |
| Bypass header/footer cache | `substitution` | Wrap dynamic per-request fragments |
| Hide content from rendering | `comment` | Body is parsed but not output |
| Show Liquid syntax literally | `raw` | Body is not parsed |

If none of the above fits, drop to the hybrid page idiom, see [../pages/hybrid-page-idiom.md](../pages/hybrid-page-idiom.md).

---

## Control flow tags

Quick reference. See the [Microsoft Learn page](https://learn.microsoft.com/en-us/power-pages/configure/liquid/control-flow-tags) for all operators.

### `if` / `elsif` / `else` / `endif`

```liquid
{% if user %}
  Hello {{ user.fullname }}.
{% elsif request.params.guest %}
  Guest mode.
{% else %}
  Please sign in.
{% endif %}
```

### `unless` / `else` / `endunless`

Inverse of `if`. Body renders when the expression is falsy.

```liquid
{% unless user.contact.statecode == 0 %}
  Account inactive.
{% endunless %}
```

### `case` / `when` / `else` / `endcase`

```liquid
{% case page.adx_name %}
  {% when 'Home' %}<h1>Welcome</h1>
  {% when 'About' %}<h1>About us</h1>
  {% else %}<h1>{{ page.title }}</h1>
{% endcase %}
```

Truthiness: only `false` and `nil` are falsy. Empty strings, `0`, and empty arrays are truthy. Operators include `==`, `!=`, `<`, `>`, `<=`, `>=`, `contains`, `and`, `or`.

---

## Iteration tags

See [Microsoft Learn](https://learn.microsoft.com/en-us/power-pages/configure/liquid/iteration-tags).

### `for` / `endfor`

```liquid
{% for contact in contacts %}
  {{ contact.fullname }}
{% endfor %}

{# limit, offset, reversed #}
{% for r in results limit:5 offset:10 reversed %}{{ r.title }}{% endfor %}

{# numeric range #}
{% for i in (1..5) %}{{ i }}{% endfor %}
```

Loop variables inside the body: `forloop.index` (1-based), `forloop.index0`, `forloop.first`, `forloop.last`, `forloop.length`, `forloop.rindex`.

### `cycle`

Cycles through a list each time it's hit. Useful for alternating row classes.

```liquid
{% for row in rows %}
  <tr class="{% cycle 'odd', 'even' %}">{{ row.name }}</tr>
{% endfor %}
```

### `tablerow` / `endtablerow`

Renders an HTML table with one cell per item. Supports `cols:N`, `limit:N`, `offset:N`, and the same range syntax as `for`.

```liquid
<table>
{% tablerow product in products cols:3 limit:9 %}
  {{ product.name }}
{% endtablerow %}
</table>
```

`tablerow` emits its own `<tr>` and `<td>` markup, wrap it in a `<table>` only.

---

## Variable tags

See [Microsoft Learn](https://learn.microsoft.com/en-us/power-pages/configure/liquid/variable-tags).

### `assign`

```liquid
{% assign full_name = contact.firstname | append: ' ' | append: contact.lastname %}
{{ full_name }}
```

Filters chain on the right of `=`. The variable is scoped to the rendering context (web template, page, layout), not global across the site.

### `capture` / `endcapture`

Assigns rendered content to a variable instead of emitting it.

```liquid
{% capture greeting %}
  Hello {{ user.firstname | default: 'guest' }}.
{% endcapture %}
{{ greeting }}
```

Whitespace inside `capture` is preserved verbatim, use `{%- ... -%}` (whitespace-trimming) markers if you need it stripped.

---

## Template tags

See [Microsoft Learn](https://learn.microsoft.com/en-us/power-pages/configure/liquid/template-tags).

### `include`

Renders a Web Template by name and inlines its output.

```liquid
{% include 'Page Header' %}
{% include 'Customer Card' customer: row, highlight: true %}
```

| Concern | Detail |
|---|---|
| Argument syntax | Comma-separated `key: value` pairs. **No `with` keyword** (that's Shopify Liquid, not Power Pages). |
| Argument scope | Available as locals inside the included template. |
| Web Template lookup | By the `adx_webtemplate.adx_name` value, case-sensitive. |
| Recursion | Allowed but easy to runaway, guard with a depth flag. |

### `block` / `endblock`

Defines a named region inside a Page Template that child pages can override.

```liquid
<head>
  <title>{% block title %}{{ website.adx_name }}{% endblock %}</title>
</head>
<main>{% block content %}{% endblock %}</main>
```

The text between `block` and `endblock` is the default, used when no child overrides.

### `extends`

Declares that the current template inherits from another, replacing its blocks.

```liquid
{% extends 'Site Layout' %}

{% block title %}Customers, {{ website.adx_name }}{% endblock %}
{% block content %}
  <h1>Customers</h1>
  ...
{% endblock %}
```

| Rule | Detail |
|---|---|
| Position | `{% extends %}` MUST be the first content in the template. Any text, whitespace-significant markup, or other tag before it breaks inheritance. |
| Allowed siblings | Only `{% block %}` tags. Liquid output, HTML, comments outside blocks are ignored. |
| Single parent | One `extends` per template. Chains are allowed (parent can extend grandparent). |

### `comment` / `endcomment`

Body is parsed but produces no output.

```liquid
{% comment %}
  TODO: replace with real value once Q3 lookup is wired up.
  {{ this_still_executes_but_output_is_dropped }}
{% endcomment %}
```

### `raw` / `endraw`

Body is emitted verbatim, Liquid syntax inside is not interpreted. Use to display literal `{% ... %}` in docs or code samples.

```liquid
<pre>
{% raw %}
{{ contact.fullname }}
{% endraw %}
</pre>
```

### `substitution` / `endsubstitution`

Marks a fragment as cache-busted. Power Pages caches output of Page Templates and Web Templates for performance; content inside `substitution` re-renders on every request, even when the surrounding template is cached.

```liquid
<header>{% include 'Site Header' %}</header>
{% substitution %}
  {# Per-request: greeting bound to the signed-in user #}
  {% if user %}<p>Welcome back, {{ user.firstname }}.</p>{% endif %}
{% endsubstitution %}
```

Use sparingly, every substitution defeats output caching for that fragment.

### `fetchxml` / `endfetchxml`

Runs a FetchXML query against Dataverse and binds the results to a variable.

```liquid
{% fetchxml accounts %}
<fetch>
  <entity name="account">
    <attribute name="name"></attribute>
    <attribute name="accountid"></attribute>
    <filter type="and">
      <condition attribute="statecode" operator="eq" value="0"></condition>
    </filter>
  </entity>
</fetch>
{% endfetchxml %}

{% for a in accounts.results.entities %}
  {{ a.name }}
{% endfor %}
```

| Property of result variable | What it is |
|---|---|
| `accounts.results.entities` | Array of result records. Attribute access via `record.<logicalname>`. |
| `accounts.results.MoreRecords` | Boolean, true if a next page exists. |
| `accounts.results.PagingCookie` | Opaque cookie to pass back via the FetchXML `paging-cookie` attribute. |
| `accounts.results.TotalRecordCount` | Set only when the query opts in via `returntotalrecordcount="true"`. |
| `accounts.xml` | The original FetchXML string. |

**Hard rule:** self-closing `<attribute name="..."/>` is forbidden, Power Pages' FetchXML parser rejects it. Always use `<attribute name="..."></attribute>`. Same applies to `<all-attributes>`. See [../data/fetchxml-patterns.md](../data/fetchxml-patterns.md) for query patterns and aggregate rules.

### `codecomponent`

Renders a Power Apps Component Framework (PCF) control inline.

```liquid
{% codecomponent name:Contoso.WeatherWidget zip_code:'55044' units:'imperial' %}
```

| Attribute | Required | Notes |
|---|---|---|
| `name` | Yes | Fully qualified PCF control name (`Namespace.Name`). |
| (any other) | No | Property bindings, passed to the control as inputs. Strings need quotes; Liquid expressions don't. |

The control must be added to the site via Power Pages Studio (Set up → Code components) before it can render.

---

## Dataverse Liquid tags

See [Microsoft Learn](https://learn.microsoft.com/en-us/power-pages/configure/liquid/dataverse-liquid-tags). These tags require Power Pages' Dataverse integration; they don't work in plain DotLiquid.

### `chart`

Renders a Dataverse chart by GUID.

```liquid
{% chart id:"a3a09e29-eb71-4abd-9067-2d2a4a0bc4bf" viewid:"00000000-0000-0000-00aa-000010001005" %}
```

| Attribute | Required | Type | Notes |
|---|---|---|---|
| `id` | Yes | GUID | Chart record ID, from the chart designer URL. |
| `viewid` | Yes | GUID | Saved view to feed the chart. The chart's entity must match the view. |

Both attributes accept Liquid expressions, but the resolved values must be GUIDs.

### `powerbi`

Embeds a Power BI dashboard, report, or tile.

```liquid
{% powerbi authentication_type:"powerbiembedded"
           path:"https://app.powerbi.com/groups/.../reports/..."
           tileid:"..."
           roles:"Region Manager" %}
```

| Attribute | Required | Default | Notes |
|---|---|---|---|
| `path` | Yes |, | Full Power BI item URL (workspace + report/dashboard/tile). |
| `authentication_type` | No | `Anonymous` | One of `Anonymous`, `AAD`, `powerbiembedded`. Case-insensitive. |
| `tileid` | No |, | When embedding a single tile from a dashboard. |
| `roles` | No |, | RLS roles to apply. **Only honored when `authentication_type` is `powerbiembedded`.** |

Anonymous embedding requires the Power BI item to be published to web. AAD requires the visitor to be signed in to a tenant with access. `powerbiembedded` uses Power Pages' service principal and supports row-level security via `roles`.

### `editable`

Marks an object as inline-editable for users with the appropriate Web Role permissions.

```liquid
{% editable snippets['Footer Disclaimer'] %}
{% editable page 'adx_copy', type: 'html', escape: false %}
{% editable weblinks['Primary Navigation'], tag: 'nav', class: 'nav-primary' %}
```

Positional arguments:

| Position | Required | What it is |
|---|---|---|
| 1st | Yes | The editable object, typically `snippets[...]`, `weblinks[...]`, `page`, or a similar bindable object. |
| 2nd | No | Attribute or key name when the object exposes multiple editable fields (e.g. `'adx_copy'` on `page`). |

Named arguments:

| Name | Type | Default | Notes |
|---|---|---|---|
| `class` | string |, | CSS class added to the wrapping element. |
| `default` | string |, | Fallback content when the bound value is empty. |
| `escape` | bool | `false` | When true, HTML-encode the value before output. |
| `liquid` | bool | **`true`** | Parse the value as Liquid before rendering. **This is the default, pass `liquid: false` to opt out.** |
| `tag` | string | `'div'` | HTML element used for the wrapper. |
| `title` | string |, | Tooltip / aria title for the edit affordance. |
| `type` | string | `'html'` | One of `'html'` or `'text'`. Affects the inline editor used. |

Security implication of the default `liquid: true`: anyone with edit permission on a snippet/page can author Liquid that runs server-side. Restrict the Web Role.

### `entitylist` / `endentitylist`

Renders a configured List (Power Pages Studio → Lists). Inside the body, the list metadata is exposed as `entitylist`, but **rows are not, they come from a nested `{% entityview %}` block.**

```liquid
{% entitylist name:"Active Accounts" %}
  <h2>{{ entitylist.adx_name }}</h2>
  {% entityview %}
    <table class="table">
      <thead>
        <tr>
          {% for col in entityview.columns %}<th>{{ col.name }}</th>{% endfor %}
        </tr>
      </thead>
      <tbody>
        {% for record in entityview.records %}
          <tr>
            {% for col in entityview.columns %}
              <td>{{ record[col.logical_name] }}</td>
            {% endfor %}
          </tr>
        {% endfor %}
      </tbody>
    </table>
    <p>Page {{ entityview.page }} of {{ entityview.pages }}</p>
  {% endentityview %}
{% endentitylist %}
```

Identifier attributes, pass **exactly one**:

| Attribute | Type | Notes |
|---|---|---|
| `id` | GUID | Direct reference to the `adx_entitylist` record. |
| `name` | string | The list's `adx_name`. Most readable; case-sensitive. |
| `key` | GUID or string | GUID matches `id`; string matches `name`. Useful when the value is data-driven. |

Plus:

| Attribute | Type | Notes |
|---|---|---|
| `language_code` | int | LCID for localization. Defaults to the current site language. |

Variable rebinding:

```liquid
{% entitylist active_accounts = name:"Active Accounts" %}
  {{ active_accounts.adx_name }}
{% endentitylist %}
```

When you rebind, the inner variable replaces `entitylist`. Use this when nesting two lists.

**Common mistakes:**
- `{% entitylist name:"..." page:"2" %}`, `page` is **not** an entitylist attribute. It belongs on `entityview`.
- `{% entitylist name:"..." key:"contactid" %}`, `key` takes a list identifier, not a column name. This silently fails to resolve.
- `for row in entitylist.records`, there is no `entitylist.records`. Iterate `entityview.records` inside a nested `{% entityview %}`.

### `entityview` / `endentityview`

Two modes:

1. **Nested inside `{% entitylist %}`**, inherits the list's entity and uses the list's default view unless overridden. This is the documented way to render rows.
2. **Standalone**, render a saved view inline without list chrome. Requires either `id` or both `logical_name` and `name`.

```liquid
{# Standalone, by view name #}
{% entityview logical_name:"contact", name:"Active Contacts", page_size:25 %}
  {% for c in entityview.records %}{{ c.fullname }}<br/>{% endfor %}
{% endentityview %}

{# Standalone, by view GUID #}
{% entityview id:"3a4f...." %}
  ...
{% endentityview %}
```

Identifier attributes, pass either `id` OR (`logical_name` + `name`):

| Attribute | Required when | Type | Notes |
|---|---|---|---|
| `id` | Standalone, by GUID | GUID | The `savedquery.savedqueryid` for system views. |
| `logical_name` | Standalone, by name | string | The Dataverse table logical name (e.g. `"contact"`). |
| `name` | Standalone, by name | string | The view's display name. |

Optional attributes (apply in both modes):

| Attribute | Type | Default | Notes |
|---|---|---|---|
| `filter` | string |, | One of `'user'` or `'account'`. Constrains rows to the signed-in user or their parent account. |
| `metafilter` | string |, | Metadata filter expression. **Only valid when nested inside `entitylist`**, the parent list defines the filter UX. |
| `order` | string |, | `"<logicalname> ASC"` or `"<logicalname> DESC"`. Overrides the view's default sort. |
| `page` | int | `1` | 1-based page number. |
| `page_size` | int | `10` (or inherited from `entitylist`) | Records per page. When nested, parent list's page size wins unless overridden here. |
| `search` | string |, | Free-text search applied across the view's search-enabled columns. |
| `language_code` | int | site default | LCID. |

Body variables: `entityview.records`, `entityview.columns`, `entityview.total_records`, `entityview.total_pages`, `entityview.page`, `entityview.first_page`, `entityview.last_page`, `entityview.previous_page`, `entityview.next_page`.

### `searchindex` / `searchendindex`

Runs a query against the Power Pages search index (configured via the Search settings).

```liquid
{% searchindex query:request.params.q,
               filter:'+_logicalname:knowledgearticle',
               page:request.params.page,
               page_size:20 %}
  {% if searchindex.results.size > 0 %}
    <ul>
      {% for r in searchindex.results %}
        <li><a href="{{ r.url }}">{{ r.title }}</a>, {{ r.fragment }}</li>
      {% endfor %}
    </ul>
    <p>Page {{ searchindex.page }} of {{ searchindex.pages }}, {{ searchindex.total_records }} hits</p>
  {% else %}
    <p>No matches.</p>
  {% endif %}
{% endsearchindex %}
```

| Attribute | Type | Default | Notes |
|---|---|---|---|
| `query` | string |, | User-supplied search text. Lucene query syntax is parsed loosely. |
| `filter` | string |, | Lucene-strict filter expression. Mismatched parens or unescaped specials throw a runtime error. |
| `logical_names` | string (CSV) | all indexed entities | Comma-separated logical names to restrict the search (e.g. `"knowledgearticle,adx_webpage"`). |
| `page` | int | `1` | 1-based. |
| `page_size` | int | `10` | Records per page. |

Body variables: `searchindex.results`, `searchindex.page`, `searchindex.pages`, `searchindex.total_records`. Each result exposes `title`, `url`, `fragment` (highlighted excerpt), `entity_logicalname`, and `id`.

### `entityform`

Renders a single-step Dataverse form configured via Power Pages Studio → Forms.

```liquid
{% entityform name:"Contact Edit Form" %}
```

| Attribute | Required | Type | Notes |
|---|---|---|---|
| `name` | Yes (or `id`) | string | The Form record's `adx_name`. Case-sensitive. |
| `id` | Yes (or `name`) | GUID | Direct reference. |

That's the entire surface. Entity, mode (Insert/Edit/ReadOnly), Dataverse main form, success message, redirect URL, captcha, and pre-fill behavior all live in the Form record.

**Hosting rules** (this is where most "form doesn't render" bugs come from):

- The page hosting `entityform` must use a **web-template-based Page Template**, not a Rewrite-based one. Studio defaults old templates to Rewrite, check the Page Template's `adx_type`.
- **Only one** `entityform` OR `webform` per page. A second tag on the same page silently renders nothing, no error, no warning. If you need two forms, split into two pages.
- Anonymous users can render the form when the Form record allows anonymous access; submission still requires either authentication or the configured captcha.

Pre-filling values: configure URL parameters on the Form record, then visit `/page?firstname=Jane`. Don't read the querystring in Liquid.

### `webform`

Renders a multi-step form configured via Power Pages Studio → Multistep Forms.

```liquid
{% webform name:"Application Wizard" %}
```

| Attribute | Required | Type | Notes |
|---|---|---|---|
| `name` | Yes (or `id`) | string | The Multistep Form's `adx_name`. |
| `id` | Yes (or `name`) | GUID | Direct reference. |

Same hosting rules as `entityform`: web-template-based Page Template only; one `webform` or `entityform` per page; subsequent tags silently fail to render. Step branching, conditional logic, attachments, and per-step JS all live in the Multistep Form metadata.

Client-side step events fire on `$(document)`:

```javascript
$(document).on('webform-step-change', function (event, data) {
  // data.fromStep, data.toStep
});
$(document).on('webform-pre-submit', function () { /* last step pre-submit */ });
```

---

## Tag attribute syntax conventions

Power Pages tag attributes follow one consistent shape:

```liquid
{% tag attr1:"value", attr2:expression, attr3:'literal' %}
```

| Convention | Detail |
|---|---|
| Pair separator | Colon between key and value (`name:"x"`), comma between pairs. |
| Optional commas | Most tags accept either commas or whitespace between pairs. Use commas, it's unambiguous and matches Microsoft samples. |
| String values | Wrap in `"..."` or `'...'`. Both work. |
| Expression values | Drop quotes for Liquid expressions: `page:request.params.page`. |
| `with` keyword | **Not supported.** That's Shopify Liquid. Power Pages uses comma-separated kwargs even for `include`. |
| Integer/boolean values | Unquoted: `page_size:25`, `escape:false`. |

Standard Liquid tags (`if`, `for`, `assign`, etc.) use Liquid's normal syntax, not the colon form, only Power Pages-specific tags adopt this attribute style.

---

## Tag combinations and gotchas

| Pattern | Detail |
|---|---|
| `extends` must be first | Any non-block content before `{% extends %}` breaks inheritance silently, child blocks render outside the parent layout. Strip leading whitespace too if your template starts with a BOM or blank lines. |
| One form per page | `entityform` and `webform` enforce a single-instance-per-page rule. Subsequent tags don't error, they render nothing. Diagnose by checking the Page Template type (must be web-template-based). |
| `entitylist` rows come from `entityview` | There is no `entitylist.records`. Always nest `{% entityview %}{% endentityview %}` inside `{% entitylist %}{% endentitylist %}` to render rows. The `metafilter` attribute is only valid in this nested form. |
| Table Permissions are automatic | `entitylist`/`entityview`/`entityform`/`webform` all honor Web Role + Table Permissions. Empty results with a populated view usually mean the calling Web Role lacks Read scope on the underlying table. |
| FetchXML self-closing tags | `<attribute name="x"/>` and `<all-attributes/>` are rejected. Always use opening + closing form. |
| `editable` is Liquid by default | `liquid: true` is the default. Authors with edit permission can run server-side Liquid. Restrict the Web Role accordingly, or pass `liquid: false` for plain text/HTML snippets. |
| `substitution` defeats caching | Wrap only the per-request fragment, not the whole template. Excessive use makes pages slower than no cache at all. |
| `chart` needs both GUIDs | The chart's entity must match the view's entity. Mismatches render an empty box with no error. |
| `powerbi` `roles` is conditional | RLS `roles` only apply with `authentication_type:"powerbiembedded"`. Anonymous and AAD modes ignore the attribute. |
| `codecomponent` requires registration | The PCF control must be added to the site in Studio first. Liquid doesn't load it on demand. |
| `searchindex` Lucene strictness | `filter` is parsed strictly, unescaped `+`, `-`, `(`, `)`, `:` will throw. Sanitize user input before interpolating. |
| Web template name lookup is case-sensitive | `{% include 'page header' %}` won't match a template named "Page Header". |

For deeper FetchXML patterns (joins, aggregates, paging) and form/list integration patterns, see the sibling references in this skill.

> Verified against Microsoft Learn 2026-04-29.
