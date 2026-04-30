# Recipe: Role-Gated UI Section

## What you'll build

A customer-details page where most of the layout is visible to everyone authenticated, but admin-only buttons (Delete, Reassign, Audit Log) only appear for users with the `Admin` Web Role. The check happens twice: server-side via Liquid (the real gate) and client-side via a defensive layer (purely UX, never security).

This recipe is for **role-based UI rendering**, not record-level access. Record-level rules belong on Table Permissions; this recipe is "should I show this button at all?"

## Pre-flight checklist

| Requirement | Where | Notes |
|---|---|---|
| Web Roles defined in Dataverse | `web-roles/` YAML | One per intended audience (e.g. `Admin`, `Support`, `Customer`) |
| Web Role assigned to the calling Contact | Studio Contacts then Roles, or `adx_contact_webrole` link table | Roles are not auto-applied; assign explicitly |
| Page accessible to all signed-in users | Page properties | If the entire page is admin-only, set Authentication = "Specific Roles" with role rule, different recipe |
| Table Permissions on the underlying data | table-permissions YAML | UI hiding is **not** security, back it with real Table Permissions |

The contract: this recipe hides UI elements. **The underlying data and write paths must enforce access independently.** A user who knows the URL of an admin action can still hit it, the buttons just are not visible. Power Pages does enforce row-level access via Table Permissions; this recipe never substitutes for that.

## Step 1: Liquid `has_role` server-side check

```liquid
{% assign customer_id = request.params['id'] | escape %}

<header class="d-flex justify-content-between align-items-start mb-4">
  <div>
    <h1>Customer details</h1>
    <p class="text-muted">ID: {{ customer_id }}</p>
  </div>

  <div class="btn-group" role="group" aria-label="Customer actions">
    {# Universal action, visible to anyone who can reach this page #}
    <a href="/edit-customer/?id={{ customer_id }}" class="btn btn-outline-primary">Edit</a>

    {# Admin-only actions #}
    {% if user | has_role: 'Admin' %}
      <a href="/customer-audit/?id={{ customer_id }}" class="btn btn-outline-secondary"
         data-role-required="Admin">
        Audit log
      </a>

      <button type="button" class="btn btn-outline-danger"
              id="reassignBtn"
              data-role-required="Admin">
        Reassign
      </button>

      <button type="button" class="btn btn-danger"
              id="deleteBtn"
              data-role-required="Admin">
        Delete
      </button>
    {% endif %}
  </div>
</header>
```

`{{ user | has_role: 'Admin' }}` returns true when:

1. `user` is non-nil (i.e., authenticated)
2. The user has at least one `adx_contact_webrole` link to a Web Role with the **exact** name `Admin`

> **Role names are case-sensitive strings.** `'Admin'` and `'admin'` are different roles. The runtime does an exact string compare against `adx_name` on `adx_webrole`. Mistyping the name silently returns false, there is no "did you mean..." warning.

Why server-side first? Three reasons:

- The Liquid never emits the HTML, so curl, view-source, and JS-disabled users all see the same gated UI
- No flash-of-unstyled-content where the admin button briefly shows then disappears
- The role name lives in a single place per page; client-side checks can drift

## Step 2: When to use this vs page-level access control

| Pattern | Use when |
|---|---|
| **Inline `has_role` Liquid check** | Same page contains content for multiple audiences; admins see extra buttons but the rest of the page is identical |
| **Web Page Access Control Rule** (page-level) | Whole page is gated, e.g. `/admin-tools/` should 404 for non-admins |
| **Authentication = "Specific Roles" on the page** | Same as above, but expressed as a property of the page rather than a separate access rule |
| **Table Permission scope** | The data itself differs by role, admins see all rows, customers see their own. UI is the same |

Decision tree:

```
Is the URL itself a secret?              -> Web Page Access Control Rule
Are the rows visible identical, only the actions differ?  -> Liquid has_role
Are the rows themselves different per user?               -> Table Permissions, with maybe Liquid for the action buttons on top
```

A page can use all three layers at once: Web Page Access Control Rule says "any signed-in user", Table Permissions filter the visible rows by ownership, and Liquid `has_role` adds admin-only action buttons. Each layer answers a different question.

## Step 3: Multi-role checks

Two equivalent shapes; pick by readability.

**Filter chain**, concise for small role lists:

```liquid
{% if user | has_role: 'Admin' or user | has_role: 'Support' %}
  ...staff-only UI...
{% endif %}
```

**Array contains**, natural when you have a longer list or need a "user has any of these" check:

```liquid
{% if user.roles contains 'Admin' or user.roles contains 'Support' or user.roles contains 'Auditor' %}
  ...staff-only UI...
{% endif %}
```

**ALL-of (intersection)**, uncommon but occasionally needed:

```liquid
{% if user | has_role: 'Admin' and user | has_role: 'BillingApprover' %}
  ...only users in BOTH roles...
{% endif %}
```

**NOT-of (exclusion)**, public content not shown to staff:

```liquid
{% unless user | has_role: 'Admin' %}
  <p>Customer-facing tip text...</p>
{% endunless %}
```

## Step 4: Defensive client-side hiding via data-attributes

For UX defense (e.g. ensuring a fast page nav doesn't briefly flash a stale-cached admin button), tag every gated element with `data-role-required` and run a JS pass on page load.

```html
<button id="deleteBtn"
        class="btn btn-danger"
        data-role-required="Admin">Delete</button>

<a href="/admin/audit"
   class="nav-link"
   data-role-required="Admin Auditor">Audit log</a>   <!-- space = ANY of these roles -->
```

```javascript
// site-wide JS in web-files/role-gates.js
(function () {
  'use strict';

  // Server bootstraps the user's roles into the page via Liquid:
  // <script id="userRoles" type="application/json">["Admin", "Support"]</script>
  var rolesEl = document.getElementById('userRoles');
  var userRoles = [];
  try {
    userRoles = JSON.parse(rolesEl ? rolesEl.textContent : '[]');
  } catch (e) {
    userRoles = [];
  }

  function userHasAny(required) {
    var needed = required.split(/\s+/).filter(Boolean);
    return needed.some(function (r) { return userRoles.indexOf(r) !== -1; });
  }

  document.querySelectorAll('[data-role-required]').forEach(function (el) {
    var required = el.getAttribute('data-role-required');
    if (!userHasAny(required)) {
      el.style.display = 'none';
      el.setAttribute('aria-hidden', 'true');
    }
  });
})();
```

Server-side bootstrap of the roles array (in your master `Layout` web template):

```liquid
<script id="userRoles" type="application/json">
[{% for r in user.roles %}{% unless forloop.first %},{% endunless %}"{{ r | replace: '"', '"' }}"{% endfor %}]
</script>
```

**The defensive layer is purely a backstop.** If the Liquid check above already excluded the element, `[data-role-required]` will not find it in the DOM and the JS does nothing. Both layers stay in sync because they read from the same Web Role data.

## Step 5: Anonymous-user pattern

Anonymous users have no Contact record, no Web Roles, and no `user` object:

```liquid
{% if user %}
  <p>Welcome back, {{ user.firstname | escape }}.</p>
{% else %}
  <p><a href="/SignIn?returnUrl={{ request.url | url_encode }}">Sign in</a> to view this content.</p>
{% endif %}
```

Combined with role checks, the full hierarchy:

```liquid
{% if user %}
  {% if user | has_role: 'Admin' %}
    ...admin UI...
  {% elsif user | has_role: 'Customer' %}
    ...customer UI...
  {% else %}
    ...generic authenticated UI...
  {% endif %}
{% else %}
  ...anonymous UI...
{% endif %}
```

`{% elsif %}` chains avoid double-rendering; without it a user with both `Admin` and `Customer` would see both blocks.

## Common variations

### Account-level access

If "admin" means "this user belongs to a privileged Account" rather than "this user has the Admin role," check the parent Account:

```liquid
{% if user.parentcustomerid.id and user.parentcustomerid.contoso_isstaff_account == true %}
  ...staff UI...
{% endif %}
```

`user.parentcustomerid` is the Account lookup on the Contact; the dot-access works because Power Pages exposes the user's own record fully expanded. To read columns of the parent Account you need the column to be in the portal's app user's read scope.

### Parent-account role inheritance

Power Pages can be configured so that roles assigned to the Account "cascade" to all its Contacts. This is a setting on the Web Role record (`adx_accountrolesenabled` or similar; verify in the env). When enabled:

```liquid
{# Same syntax, has_role transparently considers Account-inherited roles #}
{% if user | has_role: 'Acme Staff' %}
```

The Liquid filter does not care whether the role came from the Contact or the Account; it returns true if the role applies to this user via either route.

### Hiding navigation links

Same pattern, applied to top nav. In the master `Layout` web template:

```liquid
<nav>
  <a href="/dashboard/">Dashboard</a>

  {% if user | has_role: 'Admin' %}
    <a href="/admin/">Admin</a>
  {% endif %}

  {% if user.parentcustomerid.id %}
    <a href="/company/">My company</a>
  {% endif %}
</nav>
```

The `user.parentcustomerid.id` check is "this user has a parent Account", useful for showing company-mode UI to corporate users while hiding it from individual customers.

## Gotchas

| Gotcha | Symptom | Fix |
|---|---|---|
| Role name typo (case) | Button never shows | Role names are exact-match strings; verify against `adx_webrole.adx_name` |
| Newly-assigned role not honored immediately | User logs in, role still missing | Roles are loaded into the user's session at sign-in. The user must sign out and back in (or the portal session must lapse) to pick up new role assignments. Full lifecycle in [../data/permissions-and-roles.md → Web Role assignment lifecycle](../data/permissions-and-roles.md#web-role-assignment-lifecycle) |
| Liquid check passes but Web API call fails 403 | Button works in Studio preview; fails in production | UI checks are **not** security, your Table Permission must independently grant the action |
| `user.roles` returns Authenticated Users only | Custom roles missing | The Contact has not been assigned the role via `adx_contact_webrole`. New Contacts default to Authenticated Users only |
| Gating with `if user.contactid == record.ownerid` | Owner check works inconsistently | Owner-style checks belong in Table Permissions (Contact scope), not in Liquid |
| Anonymous user error: `user.contactid` blows up | Page errors for signed-out users | Always wrap user-property reads in `{% if user %}`; `nil` propagation does not protect against missing-method calls |
| Two Liquid blocks both render due to overlapping roles | Duplicate UI for users with both roles | Use `{% if %}/{% elsif %}/{% endif %}` chains, not consecutive `{% if %}` blocks |
| Client-side hiding before Liquid filter shows the element | Brief flash of admin UI for non-admin | Always do the Liquid check first; the JS layer is only a backstop for page-cache scenarios |

## Security boundary reminder

> Liquid `has_role` and the `data-role-required` JS pass are **UI/UX only**. They do not protect any data or any action. The user who knows the URL of `/admin/audit?id=<guid>` can navigate to it directly; the user who knows the Web API entityset can call it directly.
>
> **Every** action behind a gated button must also be gated by:
>
> 1. A Table Permission denying the operation to non-Admin roles, AND
> 2. Optionally a Web Page Access Control Rule denying the URL to non-Admin roles
>
> When in doubt, run the page through the `audit-permissions` agent (Microsoft's `power-pages` plugin) and confirm there's no path from a non-Admin Contact to the protected data.

## See also

- [../data/permissions-and-roles.md](../data/permissions-and-roles.md), Web Roles, Table Permissions scopes, two-layer access model, [Web Role assignment lifecycle](../data/permissions-and-roles.md#web-role-assignment-lifecycle) (the session-cache gotcha and how to test around it)
- [../language/objects.md](../language/objects.md), `user`, `user.roles`, `user.parentcustomerid`, `user.contactid`
- [../language/filters.md](../language/filters.md), `has_role` filter and other user filters
- [../language/tags.md](../language/tags.md), `{% if %}` / `{% elsif %}` / `{% unless %}` control flow
- [paginated-list-page.md](paginated-list-page.md), uses `user.parentcustomerid` for company-scope filtering
