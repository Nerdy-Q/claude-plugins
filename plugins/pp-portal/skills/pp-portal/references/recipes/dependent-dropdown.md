# Recipe: Dependent Dropdown (Account → Office Branches)

## What you'll build

A page where choosing an Account in the first dropdown dynamically populates a second dropdown with that Account's office branches. The same shape works for Country → State → City, Category → Subcategory, Project → Tasks, etc. Initial render is server-side (Liquid lists Accounts), but the cascade is client-side (Web API GET).

The flow:

1. Liquid renders the parent `<select>` populated with Accounts and an empty child `<select>`
2. JS listens for `change` on the parent
3. On change, JS fires `GET /_api/contoso_officebranches?$filter=_contoso_account_value eq <id>`
4. JS replaces the child's options with the response

## Pre-flight checklist

| Requirement | Where | Notes |
|---|---|---|
| `Webapi/contoso_officebranch/enabled` site setting | site-settings YAML | `true` (Active). Use the **logical name** (lowercase). |
| `Webapi/contoso_officebranch/fields` site setting | site-settings YAML | `contoso_officebranchid,contoso_officebranch,contoso_account` (just what you select on) |
| Read Table Permission on `contoso_officebranch` | table-permissions YAML | Scope appropriate to caller (Global for staff; Account for company users) |
| Read Table Permission on `account` | table-permissions YAML | The parent dropdown reads this on initial render via Liquid |
| Web Role assigned | Studio | Owns both Table Permissions |

The parent dropdown is read by Liquid at render, so it goes through Table Permissions but **not** through `Webapi/account/...` settings (those are only for client-side calls). The child dropdown is read by JS, so it needs both layers.

## Page setup

In Studio: **Pages then New page then Name `Branch Picker` then Partial URL `branch-picker`.**

```
web-pages/branch-picker/
  BranchPicker.webpage.yml
  BranchPicker.webpage.copy.html
  BranchPicker.webpage.custom_javascript.js
  content-pages/
    BranchPicker.en-US.webpage.copy.html
```

## Step 1: Liquid renders the parent select with empty child

```liquid
{% fetchxml accounts_query %}
<fetch mapping="logical">
  <entity name="account">
    <attribute name="accountid"></attribute>
    <attribute name="name"></attribute>
    <order attribute="name" />
  </entity>
</fetch>
{% endfetchxml %}

{% assign accounts = accounts_query.results.entities %}

<div class="mb-3">
  <label for="accountSelect" class="form-label">Account</label>
  <select id="accountSelect" name="accountid" class="form-select"
          aria-controls="branchSelect"
          aria-describedby="branchHelp">
    <option value="">-- Choose an account --</option>
    {% for a in accounts %}
      <option value="{{ a.accountid }}">{{ a.name | escape }}</option>
    {% endfor %}
  </select>
</div>

<div class="mb-3">
  <label for="branchSelect" class="form-label">Office branch</label>
  <select id="branchSelect" name="branchid" class="form-select" disabled>
    <option value="">-- Choose an account first --</option>
  </select>
  <div id="branchHelp" class="form-text" aria-live="polite"></div>
</div>
```

Notes:

- The child select starts `disabled`. The user can't tab into it until there's something to choose.
- `aria-controls` ties the parent to the child for screen readers, when the parent changes, AT users know the child is the dependent target.
- `aria-live="polite"` on the help div lets us announce "Loading branches..." to AT without grabbing focus.

## Step 2: JS listens for change

```javascript
// BranchPicker.webpage.custom_javascript.js
(function (webapi, $) {
  'use strict';

  // Canonical safeAjax, see references/data/webapi-patterns.md
  function safeAjax(ajaxOptions) {
    var deferredAjax = $.Deferred();
    shell.getTokenDeferred().done(function (token) {
      if (!ajaxOptions.headers) {
        $.extend(ajaxOptions, { headers: { '__RequestVerificationToken': token } });
      } else {
        ajaxOptions.headers['__RequestVerificationToken'] = token;
      }
      $.ajax(ajaxOptions)
        .done(function (data, textStatus, jqXHR) {
          validateLoginSession(data, textStatus, jqXHR, deferredAjax.resolve);
        })
        .fail(deferredAjax.reject);
    }).fail(function () { deferredAjax.rejectWith(this, arguments); });
    return deferredAjax.promise();
  }
  webapi.safeAjax = safeAjax;
})(window.webapi = window.webapi || {}, jQuery);

$(function () {
  var $account = $('#accountSelect');
  var $branch  = $('#branchSelect');
  var $help    = $('#branchHelp');

  $account.on('change', function () {
    var accountId = $account.val();

    // Always reset the child when the parent changes
    $branch.prop('disabled', true).empty()
      .append('<option value="">-- Loading... --</option>');
    $help.text('Loading branches...');

    if (!accountId) {
      $branch.empty().append('<option value="">-- Choose an account first --</option>');
      $help.text('');
      return;
    }

    loadBranches(accountId);
  });
});
```

## Step 3: GET to the child entity set

```javascript
function loadBranches(accountId) {
  var $branch = $('#branchSelect');
  var $help   = $('#branchHelp');

  webapi.safeAjax({
    type: 'GET',
    url:  '/_api/contoso_officebranches'
        + '?$select=contoso_officebranchid,contoso_officebranch'
        + '&$filter=_contoso_account_value eq ' + accountId
        + '&$orderby=contoso_officebranch',
    success: function (data) {
      populateBranches(data.value || []);
    },
    error: function (xhr) {
      $branch.empty()
        .append('<option value="">-- Could not load branches --</option>')
        .prop('disabled', true);
      $help.text('Unable to load branches. Please try again.');
      console.warn('branch fetch failed', xhr.status, xhr.responseText);
    }
  });
}
```

Critical mechanics:

| Element | Form |
|---|---|
| **URL path** | `/_api/<entity-set-name>`, entity set name is **lowercase plural with prefix** (`contoso_officebranches`) |
| **Lookup filter** | `_<lookup>_value eq <guid>`, leading underscore, `_value` suffix, **no quotes around the GUID**, no curly braces |
| **`$select`** | Always specify it; without it you get every column on the entity, slowing the response |
| **`$orderby`** | Use the **logical name** (lowercase), not display name |

A 400 with "no field" almost always means you wrote `contoso_account eq <id>` (the bare lookup) instead of `_contoso_account_value eq <id>` (the filter form).

## Step 4: Populate the child select

```javascript
function populateBranches(branches) {
  var $branch = $('#branchSelect');
  var $help   = $('#branchHelp');

  $branch.empty();

  if (branches.length === 0) {
    $branch.append('<option value="">-- No branches for this account --</option>')
           .prop('disabled', true);
    $help.text('This account has no office branches.');
    return;
  }

  $branch.append('<option value="">-- Choose a branch --</option>');
  branches.forEach(function (b) {
    var $opt = $('<option></option>')
      .attr('value', b.contoso_officebranchid)
      .text(b.contoso_officebranch);
    $branch.append($opt);
  });

  $branch.prop('disabled', false);
  $help.text(branches.length + ' branch' + (branches.length === 1 ? '' : 'es') + ' available.');
}
```

`$('<option></option>').text(...)` is the safe way to set text, using `.html(value)` would expose you to XSS if any branch name contains markup.

## Step 5: Optional third-level cascade (Branch → Rooms)

Same pattern, one more chain link. Each level resets all downstream selects.

```javascript
$('#branchSelect').on('change', function () {
  var branchId = $(this).val();
  $('#roomSelect').prop('disabled', true).empty()
    .append('<option value="">-- Loading... --</option>');

  if (!branchId) {
    $('#roomSelect').empty().append('<option value="">-- Choose a branch first --</option>');
    return;
  }

  webapi.safeAjax({
    type: 'GET',
    url:  '/_api/contoso_rooms'
        + '?$select=contoso_roomid,contoso_roomname'
        + '&$filter=_contoso_branch_value eq ' + branchId
        + '&$orderby=contoso_roomname',
    success: function (data) { populateRooms(data.value || []); }
  });
});

// Plus: when account changes, reset BOTH branch AND room
$('#accountSelect').on('change', function () {
  $('#roomSelect').empty().append('<option value="">-- Choose a branch first --</option>');
});
```

## Common variations

### Text-search instead of dropdown

When the parent has hundreds of options, a `<select>` is unusable. Replace it with a text input + a typeahead. Same Web API call, but `$filter=contains(name, '<query>')` + `$top=10`:

```javascript
url: '/_api/accounts'
   + '?$select=accountid,name'
   + '&$filter=contains(name, \'' + encodeURIComponent(query) + '\')'
   + '&$top=10'
```

Mind the single quotes in `contains()`, strings need them; GUIDs do not.

### Debouncing typeahead requests

```javascript
var debounceTimer;
$('#accountSearch').on('input', function (e) {
  clearTimeout(debounceTimer);
  var q = e.target.value;
  debounceTimer = setTimeout(function () { searchAccounts(q); }, 250);
});
```

250 ms is a comfortable default, enough to coalesce a fast typist's keystrokes, fast enough to feel responsive.

### Accessibility: announce loading state to screen readers

The `aria-live="polite"` div in Step 1 is half the story. The other half is updating it consistently:

| Phase | Help text |
|---|---|
| Idle (no parent selected) | (empty) |
| Loading | `Loading branches...` |
| Loaded with results | `5 branches available.` |
| Loaded with zero results | `This account has no office branches.` |
| Error | `Unable to load branches. Please try again.` |

Don't use `aria-live="assertive"`, it interrupts the user mid-action. `polite` queues the announcement until the user pauses.

## Gotchas

| Gotcha | Symptom | Fix |
|---|---|---|
| Bare lookup name in `$filter` | 400 "no property 'contoso_account'" | Use `_contoso_account_value`, not `contoso_account` |
| GUID quoted in `$filter` | 400 "syntax error" | GUIDs in OData `$filter` are **bare**: `eq d8a3...e4`, no quotes |
| Entity-set name vs logical name confusion | 404 on URL | URL is `/_api/<entity-set-name>` (plural with prefix); `$select` columns are logical names |
| `$select` omitted | Slow page, big payloads | Always list the columns you need |
| `$orderby` uses display name | 400 "no property 'Office Branch'" | Use the logical name (lowercase) |
| Caching parent options client-side | Stale list when admin adds new accounts | Re-render on each page load (Liquid does this automatically); skip the temptation to localStorage-cache |
| Race condition (user changes parent twice fast) | Older response overwrites newer | Track a request token: increment on each `change`, ignore responses for stale tokens |
| User selects parent then immediately tabs to the disabled child | Tab order awkward | Either keep the child disabled, or move focus to it programmatically once enabled |

### Race condition pattern

```javascript
var requestToken = 0;
$('#accountSelect').on('change', function () {
  var myToken = ++requestToken;
  webapi.safeAjax({ /* ... */ })
    .then(function (data) {
      if (myToken !== requestToken) return;  // a newer request superseded this one
      populateBranches(data.value || []);
    });
});
```

## See also

- [../data/webapi-patterns.md](../data/webapi-patterns.md), `safeAjax`, GET with `$select` / `$filter` / `$orderby`, "Dependent dropdown pattern" canonical example
- [../data/dataverse-naming.md](../data/dataverse-naming.md), entity-set name vs logical name; lookup `_value` form
- [../data/permissions-and-roles.md](../data/permissions-and-roles.md), Web API access (site setting + table permission + web role)
- [../quality/accessibility.md](../quality/accessibility.md#async-ui-updates--aria-live-regions), full `aria-live` pattern guide (polite vs assertive, empty-then-populate, `aria-atomic`)
- [hybrid-form-with-safeajax.md](hybrid-form-with-safeajax.md), full safeAjax helper context if you need POST in the same page
