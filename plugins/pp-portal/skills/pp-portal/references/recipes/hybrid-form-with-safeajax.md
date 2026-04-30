# Recipe: Hybrid Form with safeAjax + Web API POST

## What you'll build

An `Add Customer` page where Liquid renders the form HTML (labels, inputs, validation containers) and custom JavaScript submits the form via the Power Pages Web API. On success, the user is redirected to the new record's detail page; on failure, an inline error appears. This is the hybrid pattern in its purest form: server-rendered chrome, client-side mutation.

The flow:

1. User fills out form, clicks Submit
2. JS reads FormData, runs minimal client validation
3. JS POSTs JSON to `/_api/contacts` via `safeAjax`
4. Power Pages returns the new GUID in a response header
5. JS redirects to `/customer-details/?id=<guid>`

## Pre-flight checklist

| Requirement | Where | Value |
|---|---|---|
| `Webapi/contact/enabled` site setting | site-settings YAML | `true` (Active) |
| `Webapi/contact/fields` site setting | site-settings YAML | `firstname,lastname,emailaddress1,telephone1,parentcustomerid` (whitelist, never `*` for write-capable tables) |
| Table Permission allowing `Create` on `contact` | table-permissions YAML | Scope = Global (or appropriate); Create=true |
| Web Role grant on the calling Contact | Studio Contacts then Roles | The role that owns the Table Permission |

The four-line rule: if any one of these is missing, the POST fails with a confusing status code. Field whitelist missing then 400 "no field". Table Permission missing then 403. Site setting missing then 404. Web Role unassigned then 401.

> **Site setting names are lowercase after the prefix.** `Webapi/contact/enabled`, not `Webapi/Contact/Enabled` or `Webapi/contact/Enabled`. The `<entity>` segment is the **logical name** (lowercase), not schema name.

## Page setup

In Studio: **Pages then New page then Name `Add Customer` then Partial URL `add-customer` then Authentication = Authenticated Users.** Save.

```
web-pages/add-customer/
  AddCustomer.webpage.yml
  AddCustomer.webpage.copy.html
  AddCustomer.webpage.custom_javascript.js
  content-pages/
    AddCustomer.en-US.webpage.copy.html
```

## Step 1: Liquid renders the form chrome

```liquid
{% assign form_action_url = sitemarkers['Add Customer'].url | default: '/add-customer/' %}

<header class="mb-4">
  <h1>Add a customer</h1>
  <p class="text-muted">Fields marked <span aria-hidden="true">*</span> are required.</p>
</header>

<div id="addCustomerAlert" class="alert alert-danger d-none" role="alert" aria-live="polite"></div>

<form id="addCustomerForm" novalidate>
  <div class="row">
    <div class="col-md-6 mb-3">
      <label for="firstname" class="form-label">
        First name <span class="text-danger" aria-hidden="true">*</span>
      </label>
      <input type="text" class="form-control" id="firstname" name="firstname"
             required maxlength="50" autocomplete="given-name" />
    </div>

    <div class="col-md-6 mb-3">
      <label for="lastname" class="form-label">
        Last name <span class="text-danger" aria-hidden="true">*</span>
      </label>
      <input type="text" class="form-control" id="lastname" name="lastname"
             required maxlength="50" autocomplete="family-name" />
    </div>
  </div>

  <div class="mb-3">
    <label for="emailaddress1" class="form-label">
      Email <span class="text-danger" aria-hidden="true">*</span>
    </label>
    <input type="email" class="form-control" id="emailaddress1" name="emailaddress1"
           required maxlength="100" autocomplete="email" />
  </div>

  <div class="mb-3">
    <label for="telephone1" class="form-label">Phone</label>
    <input type="tel" class="form-control" id="telephone1" name="telephone1"
           maxlength="50" autocomplete="tel" />
  </div>

  <div class="d-flex gap-2">
    <button type="submit" id="submitBtn" class="btn btn-primary">Save customer</button>
    <a href="/customers/" class="btn btn-link">Cancel</a>
  </div>
</form>
```

Notes:

- `novalidate` on the `<form>` defers to JS for validation messages, keeps the experience consistent across browsers
- The empty alert div with `role="alert"` and `aria-live="polite"` is announced by screen readers when populated
- `autocomplete="given-name"` etc. are passed-down WCAG 2.2 SC 1.3.5 hints, free quality

## Step 2: Custom JS with the canonical safeAjax helper

```javascript
// AddCustomer.webpage.custom_javascript.js
(function (webapi, $) {
  'use strict';

  // Canonical safeAjax, see references/data/webapi-patterns.md
  // jQuery + validateLoginSession version (every standard Power Pages template ships these)
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
```

`validateLoginSession` is the portal's session-expiry guard, when the portal session has silently lapsed mid-form-fill, the response is a redirect to the login page rather than the expected JSON. `validateLoginSession` detects this and redirects, rather than running `success` with HTML masquerading as data. **Do not drop it** unless you have an alternative session check.

## Step 3: Submit handler

```javascript
$(function () {
  var $form    = $('#addCustomerForm');
  var $alert   = $('#addCustomerAlert');
  var $submit  = $('#submitBtn');

  $form.on('submit', function (e) {
    e.preventDefault();
    $alert.addClass('d-none').text('');

    // Minimal client validation, server is authoritative
    var firstname     = $('#firstname').val().trim();
    var lastname      = $('#lastname').val().trim();
    var emailaddress1 = $('#emailaddress1').val().trim();
    var telephone1    = $('#telephone1').val().trim();

    if (!firstname || !lastname || !emailaddress1) {
      return showError('Please complete the required fields.');
    }
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(emailaddress1)) {
      return showError('Please enter a valid email address.');
    }

    var payload = {
      firstname:     firstname,
      lastname:      lastname,
      emailaddress1: emailaddress1
    };
    if (telephone1) {
      payload.telephone1 = telephone1;
    }

    $submit.prop('disabled', true).text('Saving...');

    webapi.safeAjax({
      type:        'POST',
      url:         '/_api/contacts',
      contentType: 'application/json',
      data:        JSON.stringify(payload),
      success: function (data, textStatus, xhr) {
        // Step 4, read the new GUID and redirect
        var newId = getEntityId(xhr);
        if (!newId) {
          // Defensive: fall back to the customers list if we can not parse the header
          window.location.href = '/customers/';
          return;
        }
        window.location.href = '/customer-details/?id=' + encodeURIComponent(newId);
      },
      error: function (xhr) {
        $submit.prop('disabled', false).text('Save customer');
        showError(parseErrorMessage(xhr));
      }
    });
  });

  function showError(msg) {
    $alert.removeClass('d-none').text(msg);
    $alert[0].focus({ preventScroll: false });
  }
});
```

## Step 4: Read the new GUID from the response header

Microsoft's canonical Power Pages samples read **`entityid`**. The OData v4 spec defines this header as **`OData-EntityId`**. Read both, the portal layer normalizes inconsistently across versions.

```javascript
function getEntityId(xhr) {
  var headerVal = xhr.getResponseHeader('entityid')
               || xhr.getResponseHeader('OData-EntityId');
  if (!headerVal) return null;
  // Header value looks like: https://<env>.crm.dynamics.com/api/data/v9.2/contacts(<guid>)
  // ...or sometimes just: contacts(<guid>)
  var match = /\(([^)]+)\)/.exec(headerVal);
  return match ? match[1] : null;
}
```

If you want the full record back rather than just the GUID, add `Prefer: return=representation` to the request headers, the response body becomes the created record (and `entityid` is still set).

## Step 5: Error handling

OData errors come back as JSON when the request reaches Dataverse, and as HTML or plain text when the portal rejects it earlier:

```javascript
function parseErrorMessage(xhr) {
  // Try OData JSON first
  try {
    var parsed = JSON.parse(xhr.responseText || '{}');
    if (parsed && parsed.error && parsed.error.message) {
      return parsed.error.message;
    }
  } catch (_) { /* fall through */ }

  // Map well-known status codes to friendly messages
  switch (xhr.status) {
    case 0:   return 'Network error. Check your connection and try again.';
    case 401: return 'Your session has expired. Please sign in again.';
    case 403: return 'You do not have permission to add customers.';
    case 404: return 'The customer service is unavailable. Contact support.';
    case 412: return 'This record was modified by someone else. Refresh and try again.';
    default:  return 'Could not save the customer (status ' + xhr.status + '). Please try again.';
  }
}
```

| Status | Common cause |
|---|---|
| 401 (HTML) | User not authenticated; or anti-forgery token expired |
| 403 (HTML) | Anti-forgery token missing/invalid; or Table Permission denies Create |
| 404 (HTML) | `Webapi/contact/enabled` is missing or `false` |
| 400 (JSON) | Field name typo, polymorphic lookup missing suffix, field not in `Webapi/contact/fields` |
| 412 | ETag mismatch (only on PATCH; not relevant on POST) |
| 500 (JSON) | Plugin failure or business rule rejection, read `error.message` |

## Common variations

### Pre-fill from querystring

For "Add a customer for this Account" deep-linking from another page:

```liquid
{% assign account_id   = request.params['accountid'] %}
{% assign account_name = request.params['accountname'] %}
```

```javascript
var qs = new URLSearchParams(window.location.search);
$('#parentcustomerid_name').val(qs.get('accountname') || '');
// On submit, append the lookup binding:
if (qs.get('accountid')) {
  payload['parentcustomerid_account@odata.bind'] = '/accounts(' + qs.get('accountid') + ')';
}
```

### Polymorphic lookup setting

`parentcustomerid` on Contact is polymorphic (Account or Contact). The polymorphic suffix on `@odata.bind` is **mandatory**, bare `parentcustomerid@odata.bind` returns 400.

```javascript
// When parent is an Account:
payload['parentcustomerid_account@odata.bind'] = '/accounts(' + accountId + ')';
// When parent is a Contact:
payload['parentcustomerid_contact@odata.bind'] = '/contacts(' + contactId + ')';
```

### File attachment in the same form

Add a `<input type="file">`, then after the contact POST succeeds, chain a second POST to `/_api/annotations`. See `file-upload-annotations.md`.

## Gotchas

| Gotcha | Symptom | Fix |
|---|---|---|
| Anti-forgery token expires after ~20 min | 403 on submit after long form fill | `safeAjax` re-fetches token via `shell.getTokenDeferred()` on each call, but only if the helper is used; never cache the token at page load |
| Site-setting case wrong | 404 on POST | Lowercase after the prefix slash: `Webapi/contact/enabled` |
| Field not in `Webapi/contact/fields` whitelist | 400 with "No field 'x' on entity 'contact'" | Add the field to the whitelist; never use `*` on a write-capable table |
| Required-field state out of sync between Dataverse, Table Permission, and the form | 400 from Dataverse on a field the user did not fill | Server validates against Dataverse-level required-ness regardless of the form. Mirror those required fields in the form |
| Calling `JSON.stringify` on the FormData object | "[object FormData]" sent as body | Build a plain object and stringify it |
| Polymorphic lookup without suffix | 400 "not a valid navigation property" | Always include the entity suffix on customer-type lookups: `_contact` / `_account` |
| Submit double-fires | Two records created | Disable the submit button on first click, re-enable only on error |

## See also

- [../data/webapi-patterns.md](../data/webapi-patterns.md), canonical `safeAjax` helper, POST/PATCH/DELETE, `@odata.bind`, error decoding
- [../data/dataverse-naming.md](../data/dataverse-naming.md), Logical vs Schema vs Navigation Property names; case-sensitivity table
- [../data/permissions-and-roles.md](../data/permissions-and-roles.md), Table Permission scopes, Web API access requirements
- [../data/site-settings.md](../data/site-settings.md), `Webapi/<entity>/enabled` and `Webapi/<entity>/fields` rules
- [../pages/hybrid-page-idiom.md](../pages/hybrid-page-idiom.md), the broader hybrid pattern this recipe is the write half of
- [../quality/accessibility.md](../quality/accessibility.md#async-ui-updates--aria-live-regions), full `aria-live` pattern guide for announcing submit success and errors to screen readers
- [file-upload-annotations.md](file-upload-annotations.md), chaining a file upload after a record create
