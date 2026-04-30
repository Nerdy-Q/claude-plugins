# Recipe: Paginated List Page with Search

## What you'll build

A `Customers` page that renders a server-rendered, search-filterable, paginated table of contacts. The kind of "list of records" page nearly every portal has: a search box at the top, a Bootstrap table in the middle, page links at the bottom. Everything happens in Liquid, no Web API call, no client-side fetch. The page is bookmarkable, refresh-safe, and indexable by search engines.

When the user types a query and submits, the page reloads with `?search=acme&page=1` in the URL. Liquid reads those params, runs two FetchXML queries (one count, one paged), and renders the result.

## Pre-flight checklist

| Requirement | Where | Notes |
|---|---|---|
| Read permission on `contact` | Table Permission YAML | Scope = Global for staff; Account/Contact for self-service |
| Web Role assigned to caller | Studio Contacts → Roles | Authenticated Users alone is not enough, the role must own the Table Permission |
| **No Web API site settings needed** |, | Liquid `{% fetchxml %}` runs server-side under the portal app user; it bypasses `Webapi/<entity>/enabled` |

The last row trips people up. `{% fetchxml %}` and `/_api/<entityset>` are two different access paths, they share Table Permissions, but only the Web API path needs `Webapi/contact/enabled = true`.

## Page setup

In Studio: **Pages → New page → Name `Customers` → Partial URL `customers` → Page Template = your standard layout (a web-template-based template, not entity list / entity form).** Save.

On disk after `pac paportal download`:

```
web-pages/customers/
├── Customers.webpage.yml
├── Customers.webpage.copy.html              ← edit this
├── Customers.webpage.custom_javascript.js   ← stays empty for this recipe
└── content-pages/
    └── Customers.en-US.webpage.copy.html    ← keep in sync with base
```

## Step 1: Liquid count query for total

Read the querystring, derive the search string and current page, then run an aggregate FetchXML to know how many total rows match. The count is what drives pagination math.

```liquid
{% assign search       = request.params['search'] | default: '' | strip %}
{% assign current_page = request.params['page']   | default: 1 | plus: 0 %}
{% if current_page < 1 %}{% assign current_page = 1 %}{% endif %}
{% assign page_size    = 25 %}
{% assign search_wild  = '%' | append: search | append: '%' %}

{% fetchxml count_query %}
<fetch mapping="logical" aggregate="true">
  <entity name="contact">
    <attribute name="contactid" alias="total" aggregate="count"></attribute>
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

{% assign total = 0 %}
{% for item in count_query.results.entities %}
  {% if forloop.first %}{% assign total = item.total | plus: 0 %}{% endif %}
{% endfor %}

{% assign total_pages = total | minus: 1 | divided_by: page_size | plus: 1 %}
{% if total == 0 %}{% assign total_pages = 1 %}{% endif %}
{% if current_page > total_pages %}{% assign current_page = total_pages %}{% endif %}
```

Why two queries instead of one with `returntotalrecordcount="true"`? Because the page-count math has to happen **before** the paged query runs (so we can clamp `current_page`). Doing it in one query works for "next/prev" links but breaks "jump to page N".

## Step 2: Liquid paged query for visible rows

Same filter, but with `count` and `page` for pagination, and explicit `<attribute>` elements instead of `<all-attributes />` so lookup columns expose `.id` / `.name` properties.

```liquid
{% fetchxml results_query %}
<fetch mapping="logical" count="{{ page_size }}" page="{{ current_page }}" returntotalrecordcount="true">
  <entity name="contact">
    <attribute name="contactid"></attribute>
    <attribute name="fullname"></attribute>
    <attribute name="emailaddress1"></attribute>
    <attribute name="telephone1"></attribute>
    <attribute name="parentcustomerid"></attribute>
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

{% assign rows         = results_query.results.entities %}
{% assign customers_url = sitemarkers['Customers'].url | default: '/customers/' %}
```

`sitemarkers['Customers']` is the named anchor for this page. Defining it once and reading it everywhere means a future URL rename doesn't require touching the form action or the pagination links.

## Step 3: Render the search form

```liquid
<header class="d-flex justify-content-between align-items-center mb-3">
  <h1>Customers</h1>
  <a href="/add-customer/" class="btn btn-primary">Add customer</a>
</header>

<form method="get" action="{{ customers_url }}" class="mb-3" role="search">
  <label for="customerSearch" class="visually-hidden">Search customers</label>
  <div class="input-group">
    <input type="search"
           id="customerSearch"
           name="search"
           value="{{ search | escape }}"
           placeholder="Search by name, email, or phone"
           class="form-control" />
    <input type="hidden" name="page" value="1" />
    <button type="submit" class="btn btn-outline-secondary">Search</button>
  </div>
</form>
```

Notes:

- `method="get"`, the search state has to live in the URL for bookmarkability
- `name="page" value="1"` resets paging on a new search, without it, a search from page 7 stays on page 7 with a new filter and likely shows zero rows
- `value="{{ search | escape }}"` round-trips the previous query into the input; `escape` is non-negotiable on user input

## Step 4: Render the results table

```liquid
{% if rows.size == 0 %}
  <div class="alert alert-info">
    {% if search != '' %}
      No customers match "{{ search | escape }}".
    {% else %}
      No customers yet.
    {% endif %}
  </div>
{% else %}
  <p class="text-muted">{{ total }} customer{% if total != 1 %}s{% endif %} found.</p>

  <table class="table table-striped table-hover">
    <caption class="visually-hidden">List of customers</caption>
    <thead>
      <tr>
        <th scope="col">Name</th>
        <th scope="col">Email</th>
        <th scope="col">Phone</th>
        <th scope="col">Company</th>
      </tr>
    </thead>
    <tbody>
      {% for row in rows %}
        <tr>
          <td>
            <a href="/customer-details/?id={{ row.contactid }}">
              {{ row.fullname | escape | default: '(no name)' }}
            </a>
          </td>
          <td>{{ row.emailaddress1 | escape }}</td>
          <td>{{ row.telephone1 | escape }}</td>
          <td>{{ row.parentcustomerid.name | escape }}</td>
        </tr>
      {% endfor %}
    </tbody>
  </table>
{% endif %}
```

`{{ row.parentcustomerid.name }}` reads the lookup's display name, only works because we explicitly listed `<attribute name="parentcustomerid"></attribute>` in the FetchXML. With `<all-attributes />` you'd see `_parentcustomerid_value` instead, a bare GUID with no name.

## Step 5: Render pagination links

```liquid
{% if total_pages > 1 %}
  <nav aria-label="Customer pages">
    <ul class="pagination">
      {% assign prev_page = current_page | minus: 1 %}
      {% assign next_page = current_page | plus:  1 %}

      <li class="page-item {% if current_page == 1 %}disabled{% endif %}">
        <a class="page-link"
           href="{{ customers_url }}?search={{ search | url_encode }}&page={{ prev_page }}"
           {% if current_page == 1 %}aria-disabled="true" tabindex="-1"{% endif %}>
          Previous
        </a>
      </li>

      {% for i in (1..total_pages) %}
        <li class="page-item {% if i == current_page %}active{% endif %}">
          <a class="page-link"
             href="{{ customers_url }}?search={{ search | url_encode }}&page={{ i }}"
             {% if i == current_page %}aria-current="page"{% endif %}>
            {{ i }}
          </a>
        </li>
      {% endfor %}

      <li class="page-item {% if current_page == total_pages %}disabled{% endif %}">
        <a class="page-link"
           href="{{ customers_url }}?search={{ search | url_encode }}&page={{ next_page }}">
          Next
        </a>
      </li>
    </ul>
  </nav>
{% endif %}
```

For larger result sets, replace the `(1..total_pages)` loop with a windowed range (current ± 3) plus jump-to-first/jump-to-last links, at 200 pages the all-numbers approach overflows the viewport.

## Common variations

### Filter by current user

Show only contacts owned by the signed-in user's Account:

```liquid
{% assign account_id = user.parentcustomerid.id %}
<filter>
  <condition attribute="parentcustomerid" operator="eq" value="{{ account_id }}" />
</filter>
```

For an anonymous-safe version that returns zero rows when not logged in, see the "filter by current user" pattern in `../data/fetchxml-patterns.md`.

### Join to the parent Account

If the table doesn't carry city/state but the Account does, use `<link-entity>`:

```liquid
<link-entity name="account" from="accountid" to="parentcustomerid" link-type="outer" alias="acct">
  <attribute name="address1_city"  alias="city" />
  <attribute name="address1_stateorprovince" alias="state" />
</link-entity>
```

Then read `{{ row.city }}` / `{{ row.state }}` (flat, aliased columns are not nested).

## Gotchas

| Gotcha | Symptom | Fix |
|---|---|---|
| **Page size > 5000** | Server caps; fewer rows than expected | Stay under 200 for UI pages; the hard server cap is 5000 |
| **`<all-attributes />` on lookup-heavy entities** | `row.parentcustomerid.name` is empty | List lookup columns explicitly; lookup dot-access only works on named attributes |
| **Self-closed `<attribute />`** | Silent empty results, cryptic parse errors | Always write `<attribute name="x"></attribute>` with explicit closing tag (Power Pages Liquid parser) |
| **Studio preview shows zero rows but the live URL works** | Studio's preview runs as Studio user, not portal user | Test against the live portal URL with a real Web Role |
| **`request.params['page']` is a string** | Math comparisons silently wrong | `\| plus: 0` to coerce to number |
| **Search wildcard built inline** | `value="%{{ search }}%"` injects unescaped `%` | Build `search_wild` once with `\| append:` and reference; lets you sanity-check it |
| **Default page size is 50 if `count` omitted** | Pagination math wrong on page 2 | Always set `count` explicitly |

## See also

- [../data/fetchxml-patterns.md](../data/fetchxml-patterns.md), count + paginate + filter snippet (canonical), link-entity, current-user filters
- [../data/permissions-and-roles.md](../data/permissions-and-roles.md), Table Permission scopes, debugging "no records appear"
- [../language/objects.md](../language/objects.md), `request.params`, `user`, `sitemarkers`
- [../language/dotliquid-gotchas.md](../language/dotliquid-gotchas.md), string/number coercion, escape behavior
- [../pages/hybrid-page-idiom.md](../pages/hybrid-page-idiom.md), the broader render-then-mutate pattern this recipe is the read-only half of
