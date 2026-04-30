# Hybrid Page Idiom: Liquid Render Scaffold + JS Mutate

The most common pattern in production Power Pages portals: the page template uses **Liquid + FetchXML for the initial render** (search-engine-friendly, fast first paint, no flash of empty content), then **client-side JavaScript using Web API for interactivity** (forms, dependent dropdowns, mutations).

This is **not** an entityform/entitylist, those have generated chrome. Hybrid pages are custom UI that's still bound to Dataverse data.

## File anatomy

A hybrid page lives in `web-pages/<slug>/` and consists of paired files:

```
web-pages/customers/
├── Customers.webpage.yml                          # page metadata
├── Customers.webpage.copy.html                    # ⚠ BASE Liquid (loaded by default)
├── Customers.webpage.custom_javascript.js         # ⚠ BASE JS (loaded by default)
├── Customers.webpage.custom_css.css               # BASE CSS
└── content-pages/
    └── Customers.en-US.webpage.copy.html          # localized, NOT loaded by default
    └── Customers.en-US.webpage.custom_javascript.js  # localized JS, NOT loaded by default
```

**Critical**: Power Pages serves the BASE files (`<Page>.webpage.copy.html`, etc.). The `content-pages/<lang>/...` files are localized variants that are **only used if** the user's locale matches AND the base file is empty. If the base file is populated, localized files are ignored. **The number-one reason a page renders blank is a populated localized file with an empty base file.**

When you create a new page in Power Pages Studio, it puts your content in the base file by default. When you edit via `pac paportal upload` after editing locally, both must stay in sync, many production scripts copy base→localized as part of their commit workflow.

## The render-scaffold-then-mutate pattern

### Step 1: Liquid renders the initial state

```liquid
{# Customers.webpage.copy.html #}

{% assign search       = request.params['search'] | default: '' | strip %}
{% assign current_page = request.params['page']   | default: 1 | plus: 0 %}
{% assign page_size    = 50 %}

{% fetchxml results %}
<fetch mapping="logical" count="{{ page_size }}" page="{{ current_page }}" returntotalrecordcount="true">
  <entity name="contact">
    <attribute name="contactid" />
    <attribute name="fullname" />
    <attribute name="emailaddress1" />
    <attribute name="telephone1" />
    <order attribute="fullname" />
    {% if search != '' %}
    <filter type="or">
      <condition attribute="fullname"      operator="like" value="%{{ search }}%" />
      <condition attribute="emailaddress1" operator="like" value="%{{ search }}%" />
    </filter>
    {% endif %}
  </entity>
</fetch>
{% endfetchxml %}

{% assign rows = results.results.entities %}
{% assign customers_url = sitemarkers['Customers'].url | default: '/customers' %}
{% assign add_url       = sitemarkers['Add Customer'].url | default: '/add-customer' %}

<div id="customerPage"
     data-base-url="{{ customers_url }}"
     data-current-page="{{ current_page }}"
     data-total-pages="{{ results.results.total_record_count | divided_by: page_size | plus: 1 }}">

  <header class="d-flex justify-content-between mb-3">
    <h1>Customers</h1>
    <a href="{{ add_url }}" class="btn btn-primary">Add customer</a>
  </header>

  <form method="get" action="{{ customers_url }}" class="mb-3">
    <input type="hidden" name="page" value="1" />
    <input type="search" name="search" placeholder="Search…" value="{{ search | escape }}" class="form-control" />
  </form>

  <table class="table">
    <thead>
      <tr><th>Name</th><th>Email</th><th>Phone</th><th></th></tr>
    </thead>
    <tbody id="customersTbody">
      {% for row in rows %}
        <tr data-id="{{ row.contactid }}">
          <td>{{ row.fullname    | escape }}</td>
          <td>{{ row.emailaddress1 | escape }}</td>
          <td>{{ row.telephone1    | escape }}</td>
          <td>
            <button class="btn btn-link btn-delete" data-id="{{ row.contactid }}">Delete</button>
          </td>
        </tr>
      {% endfor %}
    </tbody>
  </table>
</div>
```

Notes:

- The Liquid does the heavy lifting: counted, filtered, paginated, ordered. Page renders fully-formed.
- Querystring drives state, bookmarkable, shareable, refresh-safe.
- `data-*` attributes carry state to JavaScript without re-querying.
- `escape` is essential on all user-derived content.

### Step 2: JavaScript adds interactivity

```javascript
// Customers.webpage.custom_javascript.js
(function () {
  'use strict';

  // safeAjax helper, see references/webapi-patterns.md
  function safeAjax(options) { /* ... */ }

  document.addEventListener('click', function (e) {
    var btn = e.target.closest('.btn-delete');
    if (!btn) return;
    e.preventDefault();
    if (!confirm('Delete this customer?')) return;

    var id  = btn.dataset.id;
    var row = btn.closest('tr');
    btn.disabled = true;

    safeAjax({
      url:    '/_api/contacts(' + id + ')',
      method: 'DELETE'
    })
    .then(function () {
      row.remove();
    })
    .catch(function (err) {
      btn.disabled = false;
      alert('Could not delete: ' + (err.message || err));
    });
  });
})();
```

Notes:

- IIFE `(function(){...})()` to avoid leaking globals, Power Pages includes site-wide JS, no module isolation.
- Event delegation on `document` instead of binding per-row, because rows can change.
- No optimistic-UI shortcut, wait for the response then mutate the DOM. Power Pages doesn't expose a real-time event stream.

## Bootstrap data into JS without DotLiquid escape hell

If your JS needs richer data than `data-*` attributes allow, emit JSON in a `<script type="application/json">` block:

```liquid
<script id="rowsJSON" type="application/json">
[{% for row in rows %}{
  "id":    "{{ row.contactid }}",
  "name":  "{{ row.fullname      | replace: '"', '"' }}",
  "email": "{{ row.emailaddress1 | replace: '"', '"' }}"
}{% unless forloop.last %},{% endunless %}{% endfor %}]
</script>

<script>
  var rows = [];
  try {
    rows = JSON.parse(document.getElementById('rowsJSON').textContent || '[]');
  } catch (e) {
    console.warn('rows parse failed', e);
  }
  // … use rows
</script>
```

Why this works:

- `<script type="application/json">`, the browser does not execute the content; a JSON syntax error doesn't crash other scripts.
- `"` is the valid JSON Unicode escape for `"`, the standard `replace: '"', '\\"'` filter chain in DotLiquid produces three characters (backslash, backslash, quote) instead of two, which silently breaks JSON parsing. See [../language/dotliquid-gotchas.md](../language/dotliquid-gotchas.md).
- **Do NOT use `| escape`**, it produces HTML entities (`&quot;`) that stay literal inside `<script>` tags.

## Wizard pattern (multi-step, server-side state)

For multi-step flows where each step needs server-side validation or saves a partial record, prefer `{% webform %}` (Multi-step Form) over a hybrid wizard. Webform handles state automatically.

For wizards that don't fit Multi-step Form's chrome, a hybrid wizard works:

1. Liquid renders the chrome (header, progress bar, all step containers in DOM, hidden CSS-toggled).
2. JS handles step navigation client-side.
3. On Next, JS calls `/_api/<entity>` POST to save partial state. The portal returns the new GUID; subsequent steps PATCH that record.
4. On Last → Submit, JS calls a final PATCH to flip a status field, then redirects to a confirmation page.

This pattern is significantly more code than `{% webform %}` and you take on responsibility for state recovery (what happens if the user closes the tab on step 4?). Use it only when Multi-step Form's UI is genuinely insufficient.

## Pitfalls and counter-patterns

### "Just use AJAX for everything" (anti-pattern)

Tempting to skip Liquid FetchXML and have the page render empty, then load all data client-side. Don't. Costs:

- **SEO**: search engines see an empty page.
- **First paint**: blank screen until the first XHR completes.
- **Indexing**: Power Pages public-content sitemaps depend on rendered HTML.
- **Direct-link UX**: paging via querystring breaks if there's no server-side render.

The hybrid pattern wins because the **initial state** is server-rendered (fast, indexed) and **mutations** are client-side (interactive, no full-page reload).

### "Just use entityform for everything" (different anti-pattern)

Tempting because entityform is free. Costs:

- Limited UI customization, the chrome is generated.
- One form per page (can't combine).
- Hard to add dependent dropdowns or conditional fields.
- Hard to integrate with non-Dataverse APIs.

When the form is genuinely a CRUD operation on a single entity with standard validation, `{% entityform %}` is the right tool. When the form has any of: dependent fields, custom validation, branching logic, multiple writes, go hybrid.

### Forgetting to sync base + localized files

Power Pages stores **two physical copies** of every page asset: a base file (`<Page>.webpage.copy.html`) and one or more localized files (`content-pages/<lang>/<Page>.<lang>.webpage.copy.html`). Both must stay synced. The tooling does not auto-sync.

**Two failure modes** to avoid:

| Mode | What it looks like | How it happens |
|---|---|---|
| **Empty base** | Page renders blank | Studio sometimes saves edits only to the localized file, when another developer pulls, their base is empty. |
| **Diverged pair** | Some users see different content than others | Both files were edited at different times; they've drifted. The base still wins for non-localized requests, but localized users see the older / newer version unintentionally. |

**Files affected** (each has both a base and a `content-pages/<lang>/` form):
- `<Page>.webpage.copy.html`
- `<Page>.webpage.custom_javascript.js`
- `<Page>.webpage.custom_css.css`
- `<Page>.webpage.summary.html`

**Pick a maintenance pattern and stick to it across the team.** Three workable patterns:

1. **Base-only**: edit the base file in your IDE; never touch the localized files; treat them as auto-generated mirrors. Run a post-edit hook (or `pp sync-pages <project>`) that copies base → localized after each edit. Simplest for non-localized portals (English-only).
2. **Localized-only**: edit the localized file in your IDE; treat the base as auto-generated. Same hook in reverse. Common when Studio is the primary edit interface (Studio's "Edit page" tends to update localized).
3. **Bidirectional**: edit either, run a sync that uses the most recent timestamp as authoritative. More moving parts; needs a tool.

Whichever you pick, **document it in the project's CLAUDE.md** so the team is consistent.

**Detect divergence**: the audit's INFO-005 catches "empty base + populated localized" (mode A). INFO-009 catches "both populated but diverged" (mode B).

**Fix divergence**: `pp sync-pages <project>` copies one direction in bulk (you choose base→localized or localized→base based on which has the latest content).

**Don't let `git status` lie to you.** After a `pac paportal download`, look for paired `.webpage.copy.html` files where one side has a substantive change and the other doesn't. PAC will happily fetch both files in their current state, divergence on the server stays divergent on disk.

### Loading too much CSS/JS

Power Pages serves all custom CSS/JS for a page on every request, there's no bundler. Site-wide JS lives in `web-files/`; page-specific JS lives in `<Page>.webpage.custom_javascript.js`. Keep page-specific files small; push shared logic to `web-files/<bundle>.js` and add a `<script src="/<bundle>.js">` reference.
