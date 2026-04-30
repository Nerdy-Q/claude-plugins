# Power Pages Liquid Objects Reference

Power Pages exposes a fixed set of Liquid objects available in any web template, web page copy, content snippet, or page template. These are NOT the same as Shopify's globals (`product`, `cart`, `section`, etc.), Power Pages has its own canonical inventory, defined and maintained by Microsoft.

This reference is the verified Microsoft Learn object catalog: every object that ships with Power Pages, every property the docs name, and the gotchas the docs name alongside them. Objects are split into two groups:

- **Global objects**, always available, every render
- **Per-section objects**, available inside a specific tag, loop, or context

A short sub-objects section at the end documents the shapes returned by `entities`, table permissions, and a few internal types referenced from the globals.

---

## Global objects

### entities

Direct lookup of a Dataverse record by GUID. Returns `null` if the record doesn't exist or the user lacks Read permission via Table Permissions.

```liquid
{% assign account = entities.account['936DA01F-9ABD-4D9D-80C7-02AF85C822A8'] %}
{% if account %}
  <h2>{{ account.name }}</h2>
  <p>{{ account.address1_city }}, {{ account.address1_stateorprovince }}</p>
{% endif %}
```

Form: `entities.<logical_name>['<guid>']` → an Entity object (see Sub-objects below). The lookup respects Table Permissions exactly as Forms and Lists do, no permission, no record. There is no "list all" form on `entities`; for that you want `{% fetchxml %}` or `{% entityview %}`.

### now

Current date/time in **UTC**.

```liquid
{{ now }}                              ISO timestamp (UTC)
{{ now | date: '%Y-%m-%d' }}           2026-04-29
{{ now | date: '%B %-d, %Y' }}         April 29, 2026
```

**Gotcha:** `now` is **cached by the portal web app and not refreshed on every render**. Don't rely on it for sub-minute precision, ticking clocks, or anything that needs to reflect "the actual moment this page rendered." For a fresh-on-every-request timestamp, use a `{% substitution %}` block or compute it server-side via Web API.

### page

The currently rendering Web Page record, plus a few sitemap-derived helpers.

| Property | Meaning |
|---|---|
| `page.id` | Web Page GUID |
| `page.title` | Page title |
| `page.url` | Page URL (relative) |
| `page.parent` | Parent sitemap node (`null` if root) |
| `page.children` | Array of child sitemap nodes |
| `page.breadcrumbs` | Array of ancestor sitemap nodes (root → parent) |
| `page.<attribute or relationship name>` | Any attribute or relationship on the underlying Web Page entity (e.g., `page.adx_copy`, `page.adx_summary`) |

```liquid
<title>{{ page.title }}, {{ website.name }}</title>
<h1>{{ page.title }}</h1>
{{ page.adx_copy }}

<nav class="breadcrumb">
  {% for crumb in page.breadcrumbs %}
    <a href="{{ crumb.url }}">{{ crumb.title }}</a>
  {% endfor %}
</nav>
```

### params

Shortcut for `request.params`. Identical hash; reads better in template prose.

```liquid
{% assign id = params['id'] %}                 same as request.params['id']
```

### request

The HTTP request context. Five properties; one Dictionary; a security default and a caching gotcha that you need to know about together.

| Property | Type | Meaning |
|---|---|---|
| `request.url` | string | Full absolute request URL, scheme, host, path, querystring |
| `request.path` | string | Path portion only (e.g., `/customers/`) |
| `request.path_and_query` | string | Path + querystring (e.g., `/customers/?q=acme&page=2`) |
| `request.query` | string | Querystring portion only (e.g., `?q=acme&page=2`) |
| `request.params` | Dictionary | Combined hash of all querystring values and form-POST values, keyed by name |

```liquid
{{ request.url }}              https://contoso.powerappsportals.com/customers/?q=acme&page=2
{{ request.path }}             /customers/
{{ request.path_and_query }}   /customers/?q=acme&page=2
{{ request.query }}            ?q=acme&page=2
{{ request.params['q'] }}      acme
```

#### HTML-encoding default (since 9.3.8.x)

`request` outputs are **HTML-encoded by default** since portal release 9.3.8.x. The Site Setting `Site/EnableDefaultHtmlEncoding` controls it (default `True`). With encoding on, a querystring value like `?q=<script>alert(1)</script>` rendered via `{{ request.params['q'] }}` emits the harmless string `&lt;script&gt;alert(1)&lt;/script&gt;`, not executable HTML.

This is on purpose. It stops trivial reflected-XSS via querystring values dumped into markup, and it covers the most common code-shape, `<p>You searched for: {{ request.params['q'] }}</p>`, without forcing every author to remember `| escape`.

The same setting controls auto-encoding on `user` outputs. Leave it on. If you genuinely need a raw value (e.g., piping through to a JSON island where you'll JSON-encode it differently), assign through an explicit filter pipeline and own the consequences:

```liquid
{# Explicit JSON-encoding for a JS island, bypassing the HTML-encode default safely #}
<script>
  var query = {{ request.params['q'] | json }};
</script>
```

The `| json` filter properly escapes for a JS-string context, never use raw concatenation into `<script>` blocks.

#### Caching gotcha: `request.url` and substitution

`request.url` is **cached** for subsequent requests in some output-caching scenarios (header/footer output cache, page-level cache fragments). The cached URL may be from the first request that populated the cache, not the current request. Two consequences:

1. Don't rely on `request.url` inside cached templates for per-request behavior (active-link highlighting, canonical tags, sign-in returnurl building), wrap the consumer in `{% substitution %}…{% endsubstitution %}` so it re-renders per request
2. For self-relative links, prefer **partial URLs** over full ones, `~{WebFile path}` resolves at render time and survives caching, e.g. `<a href="{{ '~/customers' }}">`

```liquid
{# Wrong inside cached header/footer, captures first-request URL, reused for everyone #}
<link rel="canonical" href="{{ request.url }}" />

{# Right, substitution forces per-request render #}
{% substitution %}<link rel="canonical" href="{{ request.url }}" />{% endsubstitution %}
```

#### Reading querystring values safely

`request.params` is a **Dictionary**, values come back as strings (or `null` if the key is absent). There is no auto-coercion to `int` or `bool`. The safe pattern uses `default` for the missing case and `strip` for whitespace:

```liquid
{% assign s = request.params['q']    | default: '' | strip %}
{% assign p = request.params['page'] | default: 1  | plus: 0 %}
{% assign show_archived = request.params['archived'] %}
{% if show_archived == 'true' %} … {% endif %}
```

For typed access, use type filters from [filters.md](filters.md):

| Need | Filter |
|---|---|
| Number from string | `\| plus: 0` (or `\| integer` where supported) |
| Bool from `true`/`false` string | `== 'true'` comparison |
| Trim whitespace | `\| strip` |
| Default if missing | `\| default: <value>` |

#### Reading form-POST values

The same `request.params` Dictionary surfaces **form-POST values** under the same accessor, there's no separate `request.form` or `request.body`. A form posted via `<form method="post">` with `<input name="comment">` reads as `{{ request.params['comment'] }}` on the rendering page. The HTML-encoding default applies to form-POST values too, same security guarantee, same opt-out path.

#### Building URLs with querystrings

**Anti-pattern**, hand-concatenated URLs without escaping:

```liquid
{# BAD, breaks if q contains & or = or # #}
<a href="/search?q={{ q }}&page={{ page }}">…</a>
```

**Pattern**, pipe through `url_escape` for each value:

```liquid
{% assign url = '/search?q=' | append: (q | url_escape) | append: '&page=' | append: page %}
<a href="{{ url }}">Search</a>
```

`url_escape` is the Power Pages-canonical filter for percent-encoding URL components. **`url_encode` is Shopify-only and does not exist in DotLiquid / Power Pages**, see [filters.md](filters.md) for the full filter inventory and migration map. (Note: a few older internal templates still use `url_encode`; treat any sighting as a bug to fix when you touch the file.)

For the sign-in return-URL pattern:

```liquid
<a href="/SignIn?returnurl={{ request.path_and_query | url_escape }}">Sign in</a>
```

#### See also

- [filters.md](filters.md), `url_escape`, `default`, `strip`, type filters, `json`
- [tags.md](tags.md), `{% substitution %}` for cache-bust regions
- [../recipes/](../recipes/), search-and-pagination recipes that read `request.params` end-to-end

### settings

Hash of Site Setting values by name. Site Settings are arbitrary key/value pairs configured in Dataverse.

```liquid
{% assign max_size = settings['UploadMaxSizeBytes'] | default: '10485760' | plus: 0 %}

{% if settings['Maintenance/Enabled'] == 'true' %}
  <div class="alert alert-warning">{{ settings['Maintenance/Message'] }}</div>
{% endif %}
```

All Site Setting values are **strings**, coerce to numbers with `| plus: 0`, to bools by string-comparing (`== 'true'`). There is no native int/bool form; use type filters.

### sitemap

The site's navigation tree. Two entry points: `sitemap.current` (the node for the page being rendered) and `sitemap.root` (the top of the tree). Both return a **sitemap node**.

| Sitemap node property | Meaning |
|---|---|
| `title` | Display title |
| `url` | Resolved URL |
| `description` | Description text (if set) |
| `entity` | The underlying Web Page entity |
| `parent` | Parent node (`null` at root) |
| `children` | Array of child nodes |
| `breadcrumbs` | Array of ancestor nodes (root → parent) |
| `is_sitemap_current` | `true` if this is the current page |
| `is_sitemap_ancestor` | `true` if this is an ancestor of the current page |

```liquid
<ul class="primary-nav">
  {% for child in sitemap.root.children %}
    <li class="{% if child.is_sitemap_current %}is-current{% elsif child.is_sitemap_ancestor %}is-ancestor{% endif %}">
      <a href="{{ child.url }}">{{ child.title }}</a>
    </li>
  {% endfor %}
</ul>
```

### sitemarkers

Hash of named URL anchors. Sitemarker records map a logical name to a Web Page so Liquid code can refer to pages by intent without hardcoding URLs.

```liquid
{% assign customers_url = sitemarkers['Customers'].url | default: '/customers' %}
<a href="{{ customers_url }}">All customers</a>
```

The only documented property is `.url`. There is also a catch-all `[attribute or relationship name]` accessor for the underlying Web Page entity, but **`.title` and `.id` are not in the docs**, earlier internal references treated them as documented and they aren't. If you need title or ID, resolve through the entity attribute accessor or via `entities.adx_webpage` directly.

The `| default: '/customers'` fallback is defensive, if a sitemarker is renamed in Studio, the page won't 404.

### snippets

Hash of Content Snippet values by name. Snippets are editable content blocks for non-developers.

```liquid
{{ snippets['Footer Disclaimer'] }}
{% editable snippets['Footer Disclaimer'] type: 'html' %}      makes it inline-editable
```

Snippets are localizable, Power Pages picks the language version matching the user's locale automatically.

### user

The currently authenticated user's Contact record, plus role and badge helpers. `null` for anonymous visitors.

| Property | Meaning |
|---|---|
| `user.id` | Contact GUID |
| `user.contactid` | Contact GUID (alias) |
| `user.fullname` | Full display name |
| `user.firstname` / `user.lastname` | Name components |
| `user.emailaddress1` | Primary email |
| `user.parentcustomerid` | Lookup to parent Account (returns an Associated Table Reference: `.id`, `.logical_name`, `.name`) |
| `user.roles` | Array of Web Role names the user has |
| `user.basic_badges_url` | URL for the user's basic badges (community feature) |
| `user.<attribute or relationship name>` | Any other Contact attribute or relationship the portal exposes |

```liquid
{% if user %}                                      Hello {{ user.firstname }}
{% else %}                                         <a href="/SignIn">Sign in</a>
{% endif %}

{% if user.roles contains 'State Employee' %}      State-only block
{% endif %}

{% assign account_id = user.parentcustomerid.id %} GUID of user's Account
```

`user` reads honor field-level security on the Contact entity. Custom attributes only work if the portal has read access via the user's Web Role.

**Security gotcha (since 9.3.8.x):** `user` outputs are **HTML-encoded by default**, controlled by the same `Site/EnableDefaultHtmlEncoding` setting as `request`. This stops a rogue user with a `<script>` in their fullname from popping XSS into every page that says "Hello {{ user.firstname }}". Leave the setting on.

### weblinks

Hash of Web Link Sets. Used for navigation menus, footer links, anything with a curated link list.

| Web Link Set property | Meaning |
|---|---|
| `name` | Set name |
| `title` | Set title (display) |
| `copy` | HTML copy block for the set |
| `weblinks` | Array of Web Link entries |

```liquid
{% assign main_menu = weblinks['Main Menu'] %}
<nav>
  <ul>
    {% for link in main_menu.weblinks %}
      <li><a href="{{ link.url }}">{{ link.name }}</a></li>
    {% endfor %}
  </ul>
</nav>
```

Each Web Link entry exposes:

| Web Link property | Meaning |
|---|---|
| `name` | Link display name |
| `url` | Link URL |
| `description` | Description text |
| `tooltip` | Tooltip text |
| `image` | Web Link Image (`alternate_text`, `height`, `url`, `width`) |
| `display_image_only` | Render image without text |
| `display_page_child_links` | Auto-render the target page's children |
| `is_external` | `true` for off-site links |
| `nofollow` | Apply `rel="nofollow"` |
| `open_in_new_window` | Open in a new tab |
| `is_sitemap_current` | Link is the current page |
| `is_sitemap_ancestor` | Link is an ancestor of the current page |
| `weblinks` | Child Web Links (sub-menus) |

Web Links can be nested, descend with `link.weblinks` for sub-menus.

### website

The current site (Power Pages portal record).

| Property | Meaning |
|---|---|
| `website.id` | Website GUID |
| `website.name` | Site display name |
| `website.sign_in_url` | Sign-in URL |
| `website.sign_out_url` | Sign-out URL |
| `website.sign_in_url_substitution` | Sign-in URL appropriate for use inside `{% substitution %}` |
| `website.sign_out_url_substitution` | Sign-out URL appropriate for use inside `{% substitution %}` |
| `website.<attribute or relationship name>` | Any attribute on the underlying `adx_website` entity |

The `_substitution` variants exist because the regular `sign_in_url` / `sign_out_url` are computed for the page's render context. Inside cached substitution blocks they would resolve incorrectly; the substitution variants render correctly there.

### language

The current site language. **Only available when multi-language is enabled** on the site.

| Property | Meaning |
|---|---|
| `language.code` | Locale code (e.g., `en-US`) |
| `language.name` | Display name (e.g., `English (United States)`) |
| `language.url` | URL path component for the language |
| `language.url_substitution` | Substitution-safe variant of the URL |

```liquid
{% if language %}
  <html lang="{{ language.code }}">
{% endif %}
```

---

## Per-section objects

These objects only resolve inside a specific tag, loop, or context. Outside their context they are `null` or undefined.

### entitylist

Available inside `{% entitylist %}` blocks. Describes the configuration of the rendering List.

| Property | Meaning |
|---|---|
| `create_enabled` | Bool, create button shown |
| `create_url` | URL for create action |
| `detail_enabled` | Bool, record details enabled |
| `detail_id_parameter` | Querystring parameter for detail ID (default `id`) |
| `detail_label` | Label for detail link |
| `detail_url` | URL for detail action |
| `empty_list_text` | Text shown when no records match |
| `enable_entity_permissions` | Bool, Table Permissions enforced |
| `entity_logical_name` | Underlying Dataverse table name |
| `filter_account_attribute_name` | Attribute used for parent-account filtering |
| `filter_apply_label` | Filter apply button label |
| `filter_definition` | Filter XML definition |
| `filter_enabled` | Bool, filtering on |
| `filter_portal_user_attribute_name` | Attribute used for portal-user filtering |
| `filter_website_attribute_name` | Attribute used for website filtering |
| `language_code` | Active language code |
| `page_size` | Records per page |
| `primary_key_name` | Primary key attribute name |
| `search_enabled` | Bool, search box on |
| `search_placeholder` | Search box placeholder text |
| `search_tooltip` | Search box tooltip text |
| `views` | Array of List views |
| `[attribute logical name]` | Any attribute on the underlying List entity |

Each entry in `views` is a **View** object:

| View property | Meaning |
|---|---|
| `columns` | Array of View Column objects |
| `entity_logical_name` | Underlying table name |
| `id` | View GUID |
| `language_code` | Active language code |
| `name` | View name |
| `primary_key_logical_name` | Primary key attribute name |
| `sort_expression` | Default sort expression |

Each View Column:

| View Column property | Meaning |
|---|---|
| `attribute_type` | Attribute type (string, integer, etc.) |
| `logical_name` | Attribute logical name |
| `name` | Display name |
| `sort_ascending` | Bool, currently sorted ascending |
| `sort_descending` | Bool, currently sorted descending |
| `sort_disabled` | Bool, sort disabled |
| `sort_enabled` | Bool, sort enabled |
| `width` | Column width |

### entityview

Available inside `{% entityview %}` blocks. Describes a paged, filtered, sorted view of records.

| Property | Meaning |
|---|---|
| `columns` | Array of View Column objects (same shape as in `entitylist.views`) |
| `entity_permission_denied` | Bool, Table Permissions denied access |
| `entity_logical_name` | Underlying Dataverse table |
| `first_page` | Page number of the first page (always 1) |
| `id` | View GUID |
| `language_code` | Active language code |
| `last_page` | Page number of the last page |
| `name` | View name |
| `next_page` | Page number of the next page (`null` on last page) |
| `page` | Current page number |
| `pages` | Array of all page numbers |
| `page_size` | Records per page |
| `previous_page` | Page number of the previous page (`null` on first page) |
| `primary_key_logical_name` | Primary key attribute name |
| `records` | Array of records on the current page |
| `sort_expression` | Active sort expression |
| `total_pages` | Total page count |
| `total_records` | Total record count across all pages |

```liquid
{% entityview logical_name:'contact', name:'Active Contacts', page_size:10 %}
  {% if entityview.entity_permission_denied %}
    <p>You don't have permission to view this list.</p>
  {% else %}
    <p>Showing page {{ entityview.page }} of {{ entityview.total_pages }} ({{ entityview.total_records }} records)</p>
    <ul>
      {% for record in entityview.records %}
        <li>{{ record.fullname }}</li>
      {% endfor %}
    </ul>
  {% endif %}
{% endentityview %}
```

### forloop

Available inside `{% for %}` loops.

| Property | Meaning |
|---|---|
| `forloop.first` | `true` on first iteration |
| `forloop.last` | `true` on final iteration |
| `forloop.index` | 1-based index |
| `forloop.index0` | 0-based index |
| `forloop.rindex` | 1-based reverse index (length down to 1) |
| `forloop.rindex0` | 0-based reverse index (length-1 down to 0) |
| `forloop.length` | Total iteration count |

### tablerowloop

Available inside `{% tablerow %}` blocks. Same `forloop` properties plus column position helpers.

| Property | Meaning |
|---|---|
| `tablerowloop.col` | 1-based column index in current row |
| `tablerowloop.col0` | 0-based column index in current row |
| `tablerowloop.col_first` | `true` in the first column of a row |
| `tablerowloop.col_last` | `true` in the last column of a row |
| `tablerowloop.first` / `last` / `index` / `index0` / `rindex` / `rindex0` / `length` | Same semantics as `forloop` |

### knowledge

Available throughout the site (knowledge management feature). Two entry points: `knowledge.articles` and `knowledge.categories`.

```liquid
{% assign popular = knowledge.articles | popular: 5 %}
{% assign recent  = knowledge.articles | recent: 5 %}
{% assign top_cats = knowledge.categories | top_level %}
```

Article filters: `popular`, `recent`. Category filters: `recent`, `top_level`.

Each article:

| Article property | Meaning |
|---|---|
| `article_public_number` | Public article number |
| `comment_count` | Comments on the article |
| `content` | Article HTML body |
| `current_user_can_comment` | Bool, comment permission check |
| `is_rating_enabled` | Bool, ratings enabled |
| `keywords` | Comma-separated keywords |
| `name` | Article name |
| `rating` | Numeric rating |
| `title` | Article title |
| `view_count` | View counter |

Each category:

| Category property | Meaning |
|---|---|
| `categorynumber` | Category number |
| `name` | Category name |
| `title` | Category title |

### searchindex

Available inside `{% searchindex %}` blocks. Exposes site search results.

| Property | Meaning |
|---|---|
| `approximate_total_hits` | Approximate total hit count |
| `page` | Current page number |
| `page_size` | Results per page |
| `results` | Array of search result objects |

Each result:

| Result property | Meaning |
|---|---|
| `entity` | The underlying Dataverse record |
| `fragment` | Highlighted excerpt (`null` for fuzzy/wildcard queries) |
| `id` | Record GUID |
| `logical_name` | Table name |
| `number` | Result number in the page |
| `score` | Relevance score |
| `title` | Result title |
| `url` | Result URL |

The `fragment` being `null` for fuzzy/wildcard queries is documented and intentional, those query types don't produce a single highlight span. Code accordingly.

### log (tag)

Not strictly an object, included here because it's the documented diagnostic surface and it pairs with everything else.

```liquid
{% log message:'About to render entitylist' level:'Info' %}
{% log message:'User has no roles' level:'Warning' %}
{% log message:'Lookup failed' level:'Error' %}
```

`level` accepts `Info`, `Warning`, `Error`. Output is visible in the **Power Pages Dev Tools** browser extension when the diagnostic setting is enabled, it does not appear in the rendered page.

### Legacy section objects

The following objects are documented but tied to legacy Dynamics 365 Portals modules. New work should use modern equivalents (Web API, Power Pages forms, Dataverse) rather than build on these. They are listed for completeness; for full property tables refer to the [official Microsoft Learn page](https://learn.microsoft.com/en-us/power-pages/configure/liquid/liquid-objects).

- **ads**, `ads['Name']` and `ads.placements['Name']`. Returns Ad and Ad Image objects. Legacy.
- **blogs**, `blogs.posts`, `blogs['Blog Name']`. Blog and blog post objects. Legacy.
- **events**, Event records. Legacy.
- **forums**, Forum threads and posts. Legacy.
- **polls**, Polls and poll options. Legacy.

---

## Sub-objects

These shapes are returned from the globals above. They are not separately addressable but worth documenting because most non-trivial templates touch them.

### Entity

The shape returned by `entities.<logical_name>['<guid>']` and any direct entity reference (e.g., `page` exposes its underlying entity attributes through this same accessor).

| Property | Meaning |
|---|---|
| `id` | Record GUID |
| `logical_name` | Table logical name |
| `notes` | Array of Note objects attached to the record |
| `permissions` | Table Permissions object for this record |
| `url` | Record URL (where applicable) |
| `[attribute or relationship name]` | Any attribute or relationship, single-value lookups return Associated Table References, option set values return Option Set Value objects |

### Associated Table Reference

Returned by lookup attributes (e.g., `user.parentcustomerid`).

| Property | Meaning |
|---|---|
| `id` | Referenced record GUID |
| `logical_name` | Referenced table name |
| `name` | Referenced record's primary name |

### Note

Returned by `entity.notes`.

| Property | Meaning |
|---|---|
| `entity` | The underlying annotation (`annotation`) entity |
| `documentbody` | Note body content |
| `url` | Note attachment URL |

### Option Set Value

Returned by option set attributes.

| Property | Meaning |
|---|---|
| `label` | Display label |
| `value` | Numeric option value |

### Table Permissions

Returned by `entity.permissions`. The full set of can-do flags for the current user against that record.

| Property | Meaning |
|---|---|
| `can_append` | User can append other records to this one |
| `can_append_to` | User can append this record to others |
| `can_create` | User can create records of this table |
| `can_delete` | User can delete this record |
| `can_read` | User can read this record |
| `can_write` | User can update this record |
| `rules_exist` | Table Permissions are configured for this table at all |

```liquid
{% if record.permissions.can_write %}
  <a href="/edit?id={{ record.id }}">Edit</a>
{% endif %}
```

`rules_exist` is the gotcha: if no Table Permissions exist for the table, the `can_*` flags follow the site's "default deny" behavior, they aren't a permission grant on their own.

### Reflexive Relationship

Returned by self-referencing relationships.

| Property | Meaning |
|---|---|
| `is_reflexive` | `true` (always, for this shape) |
| `referenced` | Records this record references |
| `referencing` | Records that reference this record |

---

## Common patterns: cheat sheet

```liquid
{# Login redirect with return URL #}
<a href="/SignIn?returnurl={{ request.path_and_query | url_escape }}">Sign in</a>

{# Active nav class #}
<a class="nav-link {% if request.path == link.url %}active{% endif %}" href="{{ link.url }}">{{ link.name }}</a>

{# Anonymous-safe user context #}
{% if user %}
  <p>Hello, {{ user.firstname }}</p>
{% else %}
  <p>Welcome, guest</p>
{% endif %}

{# Resolve sitemarker with fallback #}
{% assign customers_url = sitemarkers['Customers'].url | default: '/customers' %}

{# Site Setting as integer with default #}
{% assign max_size = settings['UploadMaxSizeBytes'] | default: '10485760' | plus: 0 %}

{# Site Setting as bool #}
{% if settings['Maintenance/Enabled'] == 'true' %}…{% endif %}

{# Permission-gated edit link #}
{% if record.permissions.can_write %}
  <a href="/edit?id={{ record.id }}">Edit</a>
{% endif %}

{# Breadcrumbs from the page #}
<nav class="breadcrumb">
  {% for crumb in page.breadcrumbs %}
    <a href="{{ crumb.url }}">{{ crumb.title }}</a>
  {% endfor %}
</nav>

{# Multi-language aware lang attribute #}
{% if language %}<html lang="{{ language.code }}">{% endif %}

{# Format a date, DotLiquid lacks `time_ago_in_words`, so format directly #}
{{ record.modifiedon | date: '%b %-d, %Y at %-I:%M %p' }}

{# Diagnostic trace visible in Power Pages Dev Tools #}
{% log message:'Rendered customer list' level:'Info' %}
```

---

> Verified against Microsoft Learn 2026-04-29.
