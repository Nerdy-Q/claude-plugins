# Bundled Libraries on Power Pages

Every Power Pages site ships with a fixed set of client-side libraries already loaded on every rendered page. Knowing exactly which libraries are auto-loaded, and which globals Microsoft injects on top of them, keeps you from shipping duplicates, breaking the portal's internal scripts, or assuming a helper exists when it doesn't.

This file is the canonical inventory: what's always available, what's only available in some contexts, and what is **not** bundled despite popular belief.

## Always available

These load on every page of every Power Pages site, in this order, before any custom JS or web template runs:

| Library | Version | Notes |
|---|---|---|
| jQuery | 3.6.2 | Exposed as both `$` and `jQuery`. Upgraded from 1.x in portal release 9.5.1.x. |
| jQuery UI | 1.13.2 | Upgraded in 9.5.10.x. Used internally for date pickers, dialogs. |
| Bootstrap CSS + JS | 3.3.6 (legacy) **or** 5.x (enhanced) | See Bootstrap version detection below. **Bootstrap 4.x is not supported.** |
| PCF runtime | 1.6.1188 | Loaded **only** when the page hosts a PCF (PowerApps Component Framework) control. Skipped otherwise since 9.5.10.x for performance. |
| `bootstrap.min.css` | matches BS version | Default Power Pages stylesheet |
| `theme.css` | per-site | Site-specific theme overlay |
| `portalbasictheme.css` | per-site | Power Pages basic theme baseline |

**Microsoft's guidance:** do not replace Bootstrap with another CSS framework. The portal's internal scripts and rendered controls (forms, lists, navigation, the entity-form chrome) depend on Bootstrap class names. Tailwind, Bulma, etc. can be added alongside Bootstrap, but not in place of it.

## Microsoft-injected globals on authenticated pages

These are injected by the portal runtime, not by a bundled library, and are present only when an authenticated user is on the page (anonymous-only pages will not have them):

| Global | Shape | Purpose |
|---|---|---|
| `window.shell.getTokenDeferred()` | jQuery `Deferred` resolving with the `__RequestVerificationToken` string | Anti-CSRF token for Web API calls |
| `window.Microsoft.Dynamic365.Portal.User` | object with identity metadata for the signed-in contact | Referenced in SPA / Code Sites docs |
| `validateLoginSession(data, textStatus, jqXHR, callback)` | function | Undocumented but referenced in Microsoft's `safeAjax` sample. May be present. |

Always feature-detect before using:

```javascript
if (window.shell && typeof window.shell.getTokenDeferred === 'function') {
  // safe to call
}
```

`window.shell` is **absent on anonymous-only pages.** Code that calls `getTokenDeferred()` unconditionally will throw on the home page if the user isn't signed in.

## Important: `webapi.safeAjax` is NOT pre-loaded

A common misconception: developers see `webapi.safeAjax(...)` in Microsoft's Web API code samples and assume it's a portal-provided global. It is not. Microsoft documents `safeAjax` as a **boilerplate pattern you copy into your own JavaScript**, typically a custom JS file or web file. Calling `webapi.safeAjax(...)` on a page where you haven't pasted that helper will throw `ReferenceError: webapi is not defined`.

See `webapi-patterns.md` for the canonical helper to copy.

## NOT bundled: bring your own

These are **not** loaded by Power Pages. If you need them, you must include them yourself via a content snippet (typically `Head/Fonts` or a custom-JS file) or via the standard `<link>` / `<script>` machinery.

| Library | Status |
|---|---|
| **Font Awesome** | **NOT bundled.** Power Pages ships with Bootstrap 3 Glyphicons by default. |
| React, Vue, Angular | Not bundled. SPA / Code Sites bring their own framework. |
| lodash, Axios, Day.js | Not bundled. |
| Moment.js | Not bundled (use `Date` or import explicitly). |
| Bootstrap 4 | **Not supported on Power Pages.** Either 3.3.6 or 5.x. |

**The Font Awesome misconception**, many tutorials, starter templates, and older portal community posts assume FA is available because earlier Microsoft starter templates injected a partial FA stylesheet for icon classes used in their default content. The current Power Pages runtime does **not** ship FA. If you use `<i class="fa fa-...">` without first including Font Awesome, the icons silently render as empty boxes.

If you add Font Awesome, **pin it to a major version** in your CDN URL. Floating versions (`@latest` or unpinned major) can break the Power Pages internal date-picker icon when FA's class names shift.

## Bootstrap version detection

Power Pages supports two data models with different Bootstrap versions:

| Data model | Bootstrap |
|---|---|
| Legacy data model | 3.3.6 |
| Enhanced data model | 5.x |

Three signals tell you which one your site is on:

1. **Read the bootstrap.min.css web file content**, version is in the file header comment.
2. **Check the `Site/EnableBootstrap5` site setting**, flips the environment-wide preference toward 5.x.
3. **`pac pages bootstrap-migrate`**, the PAC CLI command that performs the one-way 3 → 5 upgrade environment-wide. Once run, the site cannot be reverted via PAC.

Practical rule: until you've verified BS version, **write Bootstrap markup that works in both 3 and 5** (avoid `data-bs-*` for BS5-only attributes, avoid BS3-only `panel` and `well` classes).

## Common mistakes

| Mistake | Fix |
|---|---|
| Loading a second copy of jQuery via CDN | Power Pages already provides 3.6.2. Don't load a second one, multiple jQuery versions clobber each other and break portal internals. |
| Using `<i class="fa fa-...">` without including FA | Add a Font Awesome stylesheet via the `Head/Fonts` content snippet (pinned to a major version). |
| Calling `webapi.safeAjax(...)` assuming it's pre-loaded | Paste the canonical `safeAjax` helper into your custom JS first. See `webapi-patterns.md`. |
| Calling `window.shell.getTokenDeferred()` on anonymous pages | Feature-detect first; gracefully degrade or skip the request. |
| Replacing Bootstrap with Tailwind/Bulma/etc | Add alongside Bootstrap, not in place of, portal internals depend on BS classes. |
| Assuming Bootstrap 4 patterns work | They don't. The site is either 3.3.6 or 5.x. Confirm before writing markup. |
| Loading PCF runtime manually | Don't. Power Pages auto-loads it on pages that need it. |

## See also

- `webapi-patterns.md`, the canonical `safeAjax` helper and the Web API request flow that depends on `window.shell.getTokenDeferred()`.
- `dotliquid-gotchas.md`, Liquid-side patterns for emitting JSON safely into pages that the bundled jQuery / vanilla JS will consume.

## Sources

Verified against the following Microsoft Learn pages:

- `/power-pages/configure/web-api-http-requests-handle-errors`
- `/power-pages/configure/bootstrap-overview`
- `/power-pages/configure/bootstrap-version-5`
- `/power-pages/configure/manage-css`
- `/power-pages/admin/portalupdate9501x`
- `/power-pages/admin/pagesversion9510x`
- `/power-pages/configure/web-api-overview`

> Verified against Microsoft Learn 2026-04-29.
