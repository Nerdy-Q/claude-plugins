# FetchXML in Liquid: Production Patterns

Power Pages' `{% fetchxml %}` block runs a Dataverse query at **page render time** and exposes the results to the rest of the Liquid template. Results are filtered by the **current user's Table Permissions** automatically, there's no separate auth.

## The block syntax

```liquid
{% fetchxml my_query %}
<fetch mapping="logical">
  <entity name="contact">
    <attribute name="contactid" />
    <attribute name="fullname" />
  </entity>
</fetch>
{% endfetchxml %}

{% assign rows = my_query.results.entities %}
{% for row in rows %}
  {{ row.fullname }}
{% endfor %}
```

The variable name after `fetchxml` (`my_query` here) is what you reference downstream. Results live at `<name>.results.entities` (an array). Total count for paged queries is at `<name>.results.total_record_count`.

## Pattern: count + paginate + filter (the bread-and-butter list page)

This is the canonical pattern for any "list of records with search and pagination" page. You do **two** queries, one aggregate for the total count, one paged for the visible rows.

```liquid
{% assign search = request.params['search'] | default: '' | strip %}
{% assign current_page = request.params['page'] | default: 1 | plus: 0 %}
{% if current_page < 1 %}{% assign current_page = 1 %}{% endif %}
{% assign page_size = 200 %}
{% assign search_wild = '%' | append: search | append: '%' %}

{% fetchxml count_query %}
<fetch mapping="logical" aggregate="true">
  <entity name="contact">
    <attribute name="contactid" alias="total" aggregate="count" />
    {% if search != '' %}
    <filter type="or">
      <condition attribute="fullname"        operator="like" value="{{ search_wild }}" />
      <condition attribute="emailaddress1"   operator="like" value="{{ search_wild }}" />
      <condition attribute="telephone1"      operator="like" value="{{ search_wild }}" />
    </filter>
    {% endif %}
  </entity>
</fetch>
{% endfetchxml %}

{% assign total = 0 %}
{% for item in count_query.results.entities %}
  {% if forloop.first %}{% assign total = item.total | plus: 0 %}{% endif %}
{% endfor %}

{% assign total_pages = total | minus: 1 | divided_by: page_size | plus: 1 %}
{% if total == 0 %}{% assign total_pages = 1 %}{% endif %}
{% if current_page > total_pages %}{% assign current_page = total_pages %}{% endif %}

{% fetchxml results_query %}
<fetch mapping="logical" count="{{ page_size }}" page="{{ current_page }}" returntotalrecordcount="true">
  <entity name="contact">
    <attribute name="contactid" />
    <attribute name="fullname" />
    <attribute name="companyname" />
    <attribute name="telephone1" />
    <attribute name="emailaddress1" />
    <order attribute="fullname" />
    {% if search != '' %}
    <filter type="or">
      <condition attribute="fullname"      operator="like" value="{{ search_wild }}" />
      <condition attribute="emailaddress1" operator="like" value="{{ search_wild }}" />
      <condition attribute="telephone1"    operator="like" value="{{ search_wild }}" />
    </filter>
    {% endif %}
  </entity>
</fetch>
{% endfetchxml %}

{% assign rows = results_query.results.entities %}
```

Notes:

- `mapping="logical"` is a Power Pages convention, technically optional per Microsoft's FetchXML schema, but recommended for clarity (and for consistency with every other portal `{% fetchxml %}` block in the wild)
- `aggregate="true"` on the count fetch; the inner `<attribute aggregate="count" />` is the standard counting pattern
- `count` and `page` on the paged fetch (1-indexed)
- `returntotalrecordcount="true"` is optional but populates `results.total_record_count`
- `request.params['x']` reads querystring values; `| default: '' | strip` is the safe coercion
- `| plus: 0` coerces strings to numbers, `request.params` values are always strings
- Search fallback uses SQL `LIKE` wildcards (`%`); for full-text use `Contains` (case-insensitive in CRM English collations)

## Pattern: link-entity for joining

Joining to a parent record, with a left join (outer):

```liquid
{% fetchxml results_query %}
<fetch mapping="logical">
  <entity name="contact">
    <attribute name="contactid" />
    <attribute name="fullname" />
    <link-entity name="account" from="accountid" to="parentcustomerid" link-type="outer" alias="parent_account">
      <attribute name="name"    alias="parent_account_name" />
      <attribute name="address1_city" alias="parent_account_city" />
    </link-entity>
  </entity>
</fetch>
{% endfetchxml %}

{% for row in results_query.results.entities %}
  {{ row.fullname }}, {{ row.parent_account_name }} ({{ row.parent_account_city }})
{% endfor %}
```

- `link-type="outer"` = LEFT JOIN. Default is `inner`.
- `alias` is **required** when you reference the joined attributes from Liquid; without it the columns get cryptic auto-aliases (`account1.name`).
- Aliased attributes appear as flat properties on the result row, not nested.

## Pattern: filter by current user

Power Pages exposes the current user as `user` (a Contact record). Common filters:

```liquid
{# Records this user owns / is the contact for #}
<filter>
  <condition attribute="contoso_applicant_contact" operator="eq" value="{{ user.contactid }}" />
</filter>

{# Records belonging to this user's parent Account #}
{% assign parent_account_id = user.parentcustomerid.id %}
<filter>
  <condition attribute="contoso_account" operator="eq" value="{{ parent_account_id }}" />
</filter>

{# Anonymous-safe, fall back to no-records when not logged in #}
{% if user %}
<filter>
  <condition attribute="contoso_applicant_contact" operator="eq" value="{{ user.contactid }}" />
</filter>
{% else %}
<filter>
  <condition attribute="contactid" operator="null" />  {# returns zero rows #}
</filter>
{% endif %}
```

## Pattern: aggregate with grouping

Sum or count grouped by a field:

```liquid
{% fetchxml summary_query %}
<fetch mapping="logical" aggregate="true">
  <entity name="invoice">
    <attribute name="invoiceid" alias="total_count" aggregate="count" />
    <attribute name="totalamount" alias="total_amount" aggregate="sum" />
    <attribute name="statecode" alias="state" groupby="true" />
  </entity>
</fetch>
{% endfetchxml %}

{% for row in summary_query.results.entities %}
  state {{ row.state }}: {{ row.total_count }} invoices, ${{ row.total_amount | round: 2 }}
{% endfor %}
```

`groupby="true"` is required on every dimension; only aggregated columns may appear without `groupby`.

## Pattern: get a single record by ID

```liquid
{% assign rec_id = request.params['id'] %}
{% fetchxml record_query %}
<fetch mapping="logical">
  <entity name="contact">
    <all-attributes />
    <filter>
      <condition attribute="contactid" operator="eq" value="{{ rec_id }}" />
    </filter>
  </entity>
</fetch>
{% endfetchxml %}

{% assign rec = record_query.results.entities | first %}
{% if rec %}
  {{ rec.fullname }}
{% else %}
  <p>Record not found.</p>
{% endif %}
```

`<all-attributes />` selects everything. Useful for detail pages where you want the full record without listing each column. **Trade-off**: heavier query and you can't alias lookups, so you read raw `_<attr>_value` columns.

## Reading lookup values

A lookup column on the result row exposes three flat properties:

| Liquid | Meaning |
|---|---|
| `{{ row.parentcustomerid.id }}` | GUID |
| `{{ row.parentcustomerid.name }}` | display name (formatted value) |
| `{{ row.parentcustomerid.logicalname }}` | target entity logical name (for polymorphic) |

**Warning**: when you use `<all-attributes />`, you instead see `_parentcustomerid_value` (the GUID only). For consistent dot-notation access, list lookup columns explicitly with `<attribute name="parentcustomerid" />` instead of `<all-attributes />`.

## Performance gotchas

- **`{% fetchxml %}` runs synchronously during render.** A page with 8 unrelated queries makes 8 sequential round-trips. If first-byte time matters, consolidate or move slow queries to client-side Web API.
- **Default page size appears to be 50** if you don't specify `count`, observed platform behavior, not officially documented. Always set `count` explicitly for predictable behavior (200 is a common ceiling; 5000 is the hard server cap).
- **`fetchxml` results are NOT cached by the portal.** Every page render re-runs every query. Use Site Settings or content snippets for genuinely static lookups.
- **Aggregation queries can fail with "AggregateQueryRecordLimit exceeded"** when the underlying dataset is over ~50000 rows. Increase `aggregate.recordlimit` site setting or filter the dataset first.

## Debugging

- Add `<all-attributes />` temporarily to confirm data shape
- Use `{{ row | json }}` filter to dump a single row's JSON inline
- Use `{{ query.results.total_record_count }}` to verify pagination math
- `<filter type="or">` requires explicit `type`, bare `<filter>` is implicit AND
- A 0-row result with no error = silent permission filtering. Check Table Permissions for the calling Web Role.

## FetchXML attribute reference (per Microsoft)

These are the attributes Microsoft documents on each FetchXML element. Power Pages' `{% fetchxml %}` block accepts the same schema, anything missing here is either ignored or rejected by the runtime. Required attributes are marked.

> **Critical gotcha, never self-close `<attribute />`.** Power Pages' Liquid parser sometimes mis-handles self-closing forms. **Always** write `<attribute name="..."></attribute>` with an explicit closing tag, even though the element has no children. The same applies to `<order>`, `<all-attributes>`, etc., when they appear inside Liquid `{% fetchxml %}` blocks. A self-closed `<attribute />` can silently produce empty results or cryptic parse errors that don't surface until render.

### `<fetch>` (root)

| Attribute | Values / Notes |
|---|---|
| `mapping` | `logical` (recommended for portals) |
| `version` | FetchXML version, e.g. `1.0` |
| `count` | Page size for this fetch |
| `page` | 1-indexed page number |
| `paging-cookie` | Server-issued continuation token from a previous response |
| `utc-offset` | Time-zone offset for date filtering |
| `aggregate` | `true` to enable aggregate functions |
| `aggregatelimit` | Override the per-tenant aggregate row cap |
| `distinct` | `true` to deduplicate rows |
| `returntotalrecordcount` | `true` populates `results.total_record_count` |
| `no-lock` | `true` skips read locks (perf, not for transactional reads) |
| `top` | Cap total rows; mutually exclusive with `count` + `page` |

### `<entity>`

| Attribute | Values / Notes |
|---|---|
| `name` | **Required.** Logical name of the table |

### `<attribute>`

| Attribute | Values / Notes |
|---|---|
| `name` | **Required.** Logical name of the column |
| `alias` | Output column name; required when reading from Liquid in some scenarios |
| `aggregate` | `avg` / `count` / `countcolumn` / `max` / `min` / `sum` |
| `groupby` | `true`, required on every non-aggregated dimension when `aggregate="true"` |
| `dategrouping` | `day` / `week` / `month` / `quarter` / `year` |
| `distinct` | `true` for distinct values of this column |

### `<filter>`

| Attribute | Values / Notes |
|---|---|
| `type` | `and` (default) or `or` |
| `hint` | Query plan hint (advanced) |
| `isquickfindfields` | `true` for Quick Find behavior |

### `<condition>`

| Attribute | Values / Notes |
|---|---|
| `column` | Column reference (alternative to `attribute` in some shapes) |
| `entityname` | Alias of a `<link-entity>` to filter against |
| `attribute` | Logical name of the column |
| `operator` | **Required.** `eq`, `ne`, `gt`, `lt`, `like`, `in`, `not-in`, `null`, `not-null`, `eq-userid`, `eq-businessid`, etc. |
| `aggregate` | Aggregate function for HAVING-style filters |
| `alias` | Alias for grouped/aggregated conditions |
| `value` | Comparison value (or use `<value>` child for multiple) |
| `valueof` | Compare against another column's value |

### `<order>`

| Attribute | Values / Notes |
|---|---|
| `attribute` | **Required.** Column to sort by |
| `alias` | Sort by an aliased column |
| `descending` | `true` for DESC; default ASC |
| `entityname` | Sort by a column on a linked entity |

### `<link-entity>`

| Attribute | Values / Notes |
|---|---|
| `name` | **Required.** Logical name of the joined table |
| `from` | Column on the joined table |
| `to` | Column on the parent table |
| `alias` | Output prefix for joined columns; required to read aliased columns from Liquid |
| `link-type` | `inner` (default), `outer`, `any`, `not any`, `all`, `not all`, `exists`, `in` |
| `intersect` | `true` for an N:N intersect entity |
| `visible` | `false` to hide the join in the result shape |

## Pagination control patterns

The count + paginate pattern above gives you `current_page` and `total_pages`. Rendering the controls is a separate concern, and the right shape depends on dataset size, available real estate, and accessibility expectations. Five patterns, mix as needed.

All snippets assume the surrounding loop has already computed:

```liquid
{% assign current_page = request.params['page'] | default: 1 | plus: 0 %}
{% assign total_pages  = …                                       %}   {# from count_query #}
{% assign search       = request.params['search'] | default: '' | strip %}
{% assign base_url     = '/customers'                            %}
```

Each example builds links with `url_escape` on user-supplied values, see [../language/objects.md](../language/objects.md#request) for why hand-concatenation is unsafe.

### 1. Full-range pagination (small datasets, < 20 pages)

Render every page number. Cheap, scannable, accessible by default.

```liquid
<nav aria-label="pagination">
  <ul class="pagination">
    {% if current_page > 1 %}
      {% assign prev = current_page | minus: 1 %}
      <li class="page-item">
        <a class="page-link" href="{{ base_url }}?page={{ prev }}&search={{ search | url_escape }}" rel="prev">Previous</a>
      </li>
    {% else %}
      <li class="page-item disabled"><span class="page-link">Previous</span></li>
    {% endif %}

    {% for n in (1..total_pages) %}
      {% if n == current_page %}
        <li class="page-item active" aria-current="page">
          <span class="page-link">{{ n }} <span class="visually-hidden">(current)</span></span>
        </li>
      {% else %}
        <li class="page-item">
          <a class="page-link" href="{{ base_url }}?page={{ n }}&search={{ search | url_escape }}">{{ n }}</a>
        </li>
      {% endif %}
    {% endfor %}

    {% if current_page < total_pages %}
      {% assign next = current_page | plus: 1 %}
      <li class="page-item">
        <a class="page-link" href="{{ base_url }}?page={{ next }}&search={{ search | url_escape }}" rel="next">Next</a>
      </li>
    {% else %}
      <li class="page-item disabled"><span class="page-link">Next</span></li>
    {% endif %}
  </ul>
</nav>
```

### 2. Windowed pagination (large datasets)

Show 5-7 page numbers around the current page with ellipses for the gaps. Use this once `total_pages` exceeds about 20.

```liquid
{% assign window     = 2 %}                            {# pages on each side of current #}
{% assign window_lo  = current_page | minus: window %}
{% assign window_hi  = current_page | plus:  window %}
{% if window_lo < 1 %}{% assign window_lo = 1 %}{% endif %}
{% if window_hi > total_pages %}{% assign window_hi = total_pages %}{% endif %}

<nav aria-label="pagination">
  <ul class="pagination">
    {# First page + leading ellipsis #}
    {% if window_lo > 1 %}
      <li class="page-item">
        <a class="page-link" href="{{ base_url }}?page=1&search={{ search | url_escape }}">1</a>
      </li>
      {% if window_lo > 2 %}
        <li class="page-item disabled"><span class="page-link">&hellip;</span></li>
      {% endif %}
    {% endif %}

    {# Window #}
    {% for n in (window_lo..window_hi) %}
      {% if n == current_page %}
        <li class="page-item active" aria-current="page">
          <span class="page-link">{{ n }} <span class="visually-hidden">(current)</span></span>
        </li>
      {% else %}
        <li class="page-item">
          <a class="page-link" href="{{ base_url }}?page={{ n }}&search={{ search | url_escape }}">{{ n }}</a>
        </li>
      {% endif %}
    {% endfor %}

    {# Trailing ellipsis + last page #}
    {% if window_hi < total_pages %}
      {% assign before_last = total_pages | minus: 1 %}
      {% if window_hi < before_last %}
        <li class="page-item disabled"><span class="page-link">&hellip;</span></li>
      {% endif %}
      <li class="page-item">
        <a class="page-link" href="{{ base_url }}?page={{ total_pages }}&search={{ search | url_escape }}">{{ total_pages }}</a>
      </li>
    {% endif %}
  </ul>
</nav>
```

The two `if` guards on the ellipses prevent rendering `1 … 2` (no gap), only show the ellipsis when there's at least one page hidden.

### 3. First / Last / Jump-to controls

Add a jump-to-page input next to a windowed pager, for users who need to land precisely.

```liquid
<form action="{{ base_url }}" method="get" class="d-flex align-items-center gap-2">
  <input type="hidden" name="search" value="{{ search }}" />
  <label for="goto" class="form-label mb-0">Go to page</label>
  <input id="goto" name="page" type="number" min="1" max="{{ total_pages }}"
         value="{{ current_page }}" class="form-control form-control-sm" style="width: 6rem" />
  <button class="btn btn-sm btn-outline-secondary" type="submit">Go</button>
  <span class="text-muted">of {{ total_pages }}</span>
</form>
```

Pair this with **First** / **Last** anchors when the dataset is in the hundreds-of-pages range:

```liquid
<a class="page-link" href="{{ base_url }}?page=1&search={{ search | url_escape }}" aria-label="First page">&laquo; First</a>
<a class="page-link" href="{{ base_url }}?page={{ total_pages }}&search={{ search | url_escape }}" aria-label="Last page">Last &raquo;</a>
```

The form-POST nature of the jump-to control automatically clamps via the `min` / `max` HTML5 validation; the page-render code should also clamp `current_page` against `total_pages` (the canonical pattern earlier in this file already does).

### 4. Compact "Page X of Y, prev/next"

Minimal control for mobile or short lists. No numbered links, just direction + status.

```liquid
<nav aria-label="pagination" class="d-flex justify-content-between align-items-center">
  {% if current_page > 1 %}
    {% assign prev = current_page | minus: 1 %}
    <a class="btn btn-sm btn-outline-secondary" href="{{ base_url }}?page={{ prev }}&search={{ search | url_escape }}" rel="prev">&laquo; Previous</a>
  {% else %}
    <span class="btn btn-sm btn-outline-secondary disabled">&laquo; Previous</span>
  {% endif %}

  <span aria-live="polite">Page {{ current_page }} of {{ total_pages }}</span>

  {% if current_page < total_pages %}
    {% assign next = current_page | plus: 1 %}
    <a class="btn btn-sm btn-outline-secondary" href="{{ base_url }}?page={{ next }}&search={{ search | url_escape }}" rel="next">Next &raquo;</a>
  {% else %}
    <span class="btn btn-sm btn-outline-secondary disabled">Next &raquo;</span>
  {% endif %}
</nav>
```

The `aria-live="polite"` on the status span means screen readers announce "Page 3 of 12" after navigation without interrupting the user.

### 5. Bootstrap-classed example (BS3 vs BS5)

Classic Power Pages portals default to **Bootstrap 3**; sites migrated via `pac pages bootstrap-migrate` (see [site-settings.md](site-settings.md) `Site/BootstrapV5Enabled`) use **Bootstrap 5**. The `.pagination` wrapper class is identical; the differences are on items and accessibility helpers.

| Concern | Bootstrap 3 | Bootstrap 5 |
|---|---|---|
| Item wrapper | `<li>` directly inside `<ul class="pagination">` | `<li class="page-item">` |
| Link class | bare `<a>` inside `<li>` | `<a class="page-link">` |
| Active state | `<li class="active">` | `<li class="page-item active">` + `aria-current="page"` |
| Disabled state | `<li class="disabled">` | `<li class="page-item disabled">` |
| Hidden text | `<span class="sr-only">` | `<span class="visually-hidden">` |

Bootstrap 3 example for the canonical "previous, numbered window, next" shape (acme_customer dataset):

```liquid
<nav aria-label="pagination">
  <ul class="pagination">
    {% if current_page > 1 %}
      {% assign prev = current_page | minus: 1 %}
      <li><a href="{{ base_url }}?page={{ prev }}&search={{ search | url_escape }}" rel="prev">&laquo;</a></li>
    {% else %}
      <li class="disabled"><span>&laquo;</span></li>
    {% endif %}

    {% for n in (window_lo..window_hi) %}
      {% if n == current_page %}
        <li class="active"><span>{{ n }} <span class="sr-only">(current)</span></span></li>
      {% else %}
        <li><a href="{{ base_url }}?page={{ n }}&search={{ search | url_escape }}">{{ n }}</a></li>
      {% endif %}
    {% endfor %}

    {% if current_page < total_pages %}
      {% assign next = current_page | plus: 1 %}
      <li><a href="{{ base_url }}?page={{ next }}&search={{ search | url_escape }}" rel="next">&raquo;</a></li>
    {% else %}
      <li class="disabled"><span>&raquo;</span></li>
    {% endif %}
  </ul>
</nav>
```

The Bootstrap 5 versions of patterns 1, 2, and 4 above already use the v5 conventions (`page-item`, `page-link`, `visually-hidden`, `aria-current`).

### Accessibility callouts

Every snippet above ships with the four checks pagination needs to clear WCAG 2.1 AA:

- **Landmark**, `<nav aria-label="pagination">` so the pager appears in the page's regions list and assistive tech can jump straight to it
- **Current page**, `aria-current="page"` on the active item, NOT just visual styling, color-blind and screen-reader users need the semantic
- **Status announcement**, "Page X of Y" rendered as accessible text, not only as visual decoration; pair with `aria-live="polite"` on the compact form so updates announce without interrupting
- **Hidden helper text**, `(current)` inside `<span class="visually-hidden">` (or `sr-only` on BS3) inside the active link so the screen reader output is "Page 3, current" rather than just "Page 3"

Disabled previous/next controls render as `<span>` not `<a>`, a disabled link is still tab-focusable and announces as a link, both of which are confusing. The span avoids that footgun.

For the full WCAG-AA pattern set including focus management, color contrast, and keyboard navigation, see [../quality/accessibility.md](../quality/accessibility.md).

> Verified against Microsoft Learn 2026-04-29.
