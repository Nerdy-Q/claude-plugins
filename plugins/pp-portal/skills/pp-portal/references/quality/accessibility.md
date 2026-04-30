# Accessibility in Power Pages

Power Pages portals carry the bulk of Microsoft's accessibility liability through the **platform-rendered chrome** (basic forms, multistep forms, lists, subgrids, login, themes). Every byte of HTML *you* add, Liquid templates, content snippets, custom CSS, custom JS, FetchXML-rendered tables, is **your** liability. Microsoft is explicit:

> "When you customize your Power Pages site, you're responsible for meeting accessibility standards."

For government, regulated, or nonprofit portals this matters: a Power Pages site that is technically conformant out-of-the-box can still fail WCAG once you add a single hand-rolled web template.

## Microsoft's commitment

Power Pages publicly conforms to **three** standards (per the [official accessibility page](https://learn.microsoft.com/power-pages/admin/accessibility)):

| Standard | Power Pages status |
|---|---|
| WCAG 2.2 (W3C) | Conforms |
| US Section 508 (GSA) | Conforms |
| EN 301 549 (ETSI, EU) | Conforms |

**Conformance level is not stated as A / AA / AAA on the page**, but the testing guidance points specifically at *Accessibility Insights Assessment*, which "measures compliance with WCAG 2.2 Level AA success criteria", that is the operative bar. Treat **WCAG 2.2 Level AA** as the target for any custom work. Note: Microsoft's own page includes a slightly stale sentence saying customizations must adhere to "WCAG 2.1, US Section 508, or ETSI EN 301 549" in the Liquid-templates section. The conformance commitment elsewhere on the same page is 2.2; build to 2.2.

For US federal / state / municipal contracts, Section 508 conformance is the contracting hook. EN 301 549 is the equivalent for EU public-sector procurement.

Conformance Reports (VPATs/ACRs) are published at [Microsoft Accessibility Conformance Reports](https://cloudblogs.microsoft.com/industry-blog/government/2018/09/11/accessibility-conformance-reports/). Bid documents typically require attaching the latest report.

## What Power Pages handles for you

The platform-rendered components were built to WCAG 2.2:

| Surface | A11y handled by Microsoft |
|---|---|
| Basic forms (`{% entityform %}`) | Labels from Dataverse display names, required-field indicators, validation summary, error linking, keyboard tab order, native HTML inputs |
| Multistep forms (`{% webform %}`) | Same as basic forms, plus step-progress announcement |
| Entity lists (`{% entitylist %}` / list components) | Native `<table>` with `<th>`, sortable column headers, pagination controls with accessible labels |
| Subgrid dialogs (Create / Edit / Details) | Modal focus trap, `Dismiss Button Sr Text` override field, configurable title for screen readers |
| Login pages | Focus order, labels, error announcements |
| Themes (Styling workspace) | Preset themes meet contrast minimums (post-Sept 2022) |

**The trap**: every one of these can be defeated. Wrap an `{% entityform %}` in a `<div role="presentation">` and you've stripped the form landmark. Override label text with raw HTML and you can break the `for`/`id` association. Custom-style a button to look like a link and screen readers still announce "button". The platform does *its* job; what you add around it is on you.

## Built-in form a11y options

Two basic-form / multistep-form options are explicitly documented as accessibility settings. Both default to behaviors you almost always want:

| Option | Default | What it does |
|---|---|---|
| **ToolTips Enabled** | `false` | Adds the Dataverse attribute description as the `title=` attribute on each input. Screen readers read this on focus. **Turn on** if your Dataverse columns have description text, it's free a11y. |
| **Enable Validation Summary Links** | `true` | Renders anchor links in the validation summary that scroll to the failing field on click. **Leave on**, turning it off makes long forms unusable for keyboard users. |

Subgrid dialog fields with explicit a11y semantics:

| Field | Purpose |
|---|---|
| **Dismiss Button Sr Text** | Screen-reader-only text on the modal close button (overrides default "Close"). Set this if the modal context is non-obvious, e.g., "Close edit project dialog". |
| **Title** | Title bar text. Read by screen readers as the dialog name. Always set explicitly; don't rely on the default. |
| **Loading Message** | What screen readers announce while the modal loads. |

Adjacent form options that *aren't* labeled accessibility but affect it:

- **Validation Summary Header Text**, set this; the default is empty and gives screen-reader users no context for the error list
- **Instructions**, rendered above the form. Use this for instructions that apply globally; instructions inside individual fields are buried for AT users
- **Set Recommended Fields as Required** / **Make All Fields Required**, these change which fields render with `aria-required`. Wrong setting = lying to assistive tech

## There is no Power Pages accessibility checker

Canvas Apps has an Accessibility Checker built into the Studio. **Power Pages does not.** Microsoft's official testing guidance for Power Pages is to use **third-party tools** outside the design studio:

| Tool | Use | Where |
|---|---|---|
| **Accessibility Insights, FastPass** | Quick automated scan of dozens of WCAG checks | Browser extension on a published site |
| **Accessibility Insights, Assessment** | Full WCAG 2.2 Level AA workflow with manual checks | Browser extension; documents results |
| **Lighthouse** (Edge / Chrome DevTools) | Quick automated a11y score | DevTools → Lighthouse tab → Accessibility category |
| **Windows Narrator** / **NVDA** / **VoiceOver** | Manual screen-reader testing | OS-level |
| **Edge Immersive Reader** | Sanity check that text content is readable | Edge browser |

Site Checker (in Power Platform admin center) is **not** an accessibility tool, it's a configuration diagnostic (footer cache, broken pages, etc.). Security Scan is also unrelated, it scans for XSS / vulnerable libraries, not WCAG.

**Practical loop**: deploy to a non-prod portal → run Accessibility Insights FastPass (catches ~25–30 of the auto-detectable WCAG failures) → manually walk the page with NVDA or Narrator → fix → repeat. For a production sign-off, run Accessibility Insights *Assessment* on every distinct page template.

## WCAG 2.2 Level AA: the customization checklist

What you must verify on every custom page or web template.

### Perceivable

| Requirement | Power Pages-specific note |
|---|---|
| **1.1.1 Non-text content**, alt on every `<img>` | Decorative images: `alt=""`. Snippet `Logo alt text` is configurable, always set it, never leave default. Liquid: `<img src="{{ snippets['Logo URL'] }}" alt="{{ snippets['Logo alt text'] }}">` |
| **1.3.1 Info and relationships**, semantic HTML | Don't use `<div onclick>` for buttons; use `<button>`. FetchXML tables: emit real `<table><caption><th scope="col">` |
| **1.4.1 Use of color**, color is not the only signal | Status indicators must include text or icon, not just a colored dot. The Styling workspace gives you a small color palette, keep semantic-color text labels in your Liquid |
| **1.4.3 Contrast (minimum)**, 4.5:1 normal, 3:1 large | Power Pages preset themes (post-Sept 2022) meet this. Sites created before Sept 2022 may need re-theming, see [Adjusting the background color](https://learn.microsoft.com/power-pages/known-issues#adjusting-the-background-color-for-your-power-pages-site) |
| **1.4.10 Reflow**, works at 400% zoom | Test by zooming Edge to 400% on a 1280px viewport. No horizontal scroll except for tables/maps. Bootstrap-grid pages from the templates pass; custom CSS with fixed `width: 1200px` fails |
| **1.4.11 Non-text contrast**, 3:1 for UI components | Custom button borders, focus rings, form-field outlines must hit 3:1 against background |

### Operable

| Requirement | Power Pages-specific note |
|---|---|
| **2.1.1 Keyboard**, all functionality keyboardable | Custom JS with `mousedown` / `mouseup` only is broken. Dependent dropdowns, AJAX search, all must work with Tab + Enter |
| **2.1.2 No keyboard trap** | Modal dialogs must return focus to the trigger on close. Subgrid dialogs do this for you; hand-rolled overlays often don't |
| **2.4.1 Bypass blocks**, skip link or landmarks | Power Pages templates do not include a skip link by default. Add one (see pattern below) |
| **2.4.3 Focus order** | DOM order = focus order. CSS `order:` and `flex-direction: row-reverse` defeat this, verify with Tab |
| **2.4.6 Headings and labels** | Every page needs an `<h1>`. Page Header web template renders the page title, `{% include 'page_header' %}` |
| **2.4.7 Focus visible** | Don't `outline: none` without a replacement `:focus` style. Many corporate-branded portals do this; it's an instant Section 508 fail |
| **2.5.8 Target size (minimum, 2.2)**, 24×24 CSS px | New in 2.2. Audit any icon-only buttons, sort arrows, subgrid action icons |

### Understandable

| Requirement | Power Pages-specific note |
|---|---|
| **3.1.1 Language of page** | `<html lang="{{ website.selected_language.code }}">` in your page-template root web template |
| **3.2.2 On input**, change of context only on submit | Auto-submitting `<select>` `onchange` is a fail unless announced. Use a Submit button, or add an `aria-live` notice |
| **3.3.1 Error identification** | Basic-form validation summary covers this. Custom forms must announce errors via `role="alert"` or `aria-live="assertive"` |
| **3.3.2 Labels or instructions** | Every form input has a `<label for>`. Don't use placeholder-only labels, they vanish on type |
| **3.3.3 Error suggestion** | Validation messages from Dataverse may be terse, override via Localized Form Field error messages or client-side validation text |
| **3.3.7 Redundant entry (2.2)** | New in 2.2. Multistep forms must not re-ask for data already provided. `{% webform %}` preserves step data automatically; verify in custom step logic |
| **3.3.8 Accessible authentication (2.2)** | New in 2.2. CAPTCHA on basic forms is a 3.3.8 risk if it requires cognitive function with no alternative, provide an alternative path or use Microsoft's reCAPTCHA invisible mode |

### Robust

| Requirement | Power Pages-specific note |
|---|---|
| **4.1.2 Name, role, value** | Custom widgets need `role=`, `aria-label=`, and state attributes (`aria-expanded`, `aria-checked`). Native HTML elements give you this for free; custom JS widgets do not |
| **4.1.3 Status messages (live regions)** | AJAX pages must announce updates. See live-region pattern below |

## Common Power Pages a11y gotchas

Most-frequent findings on real portal audits.

| Gotcha | Why it happens | Fix |
|---|---|---|
| **No skip link** | Default templates omit it | Add `<a class="skip-link" href="#main">Skip to main content</a>` and a `#main` id on `<main>` |
| **`<h1>` missing or duplicated** | Custom layouts forget Page Header; or content snippets inject another `<h1>` | One `<h1>` per page from `{% include 'page_header' %}`; content uses `<h2>+` |
| **Buttons that are really links and vice versa** | Pre-July-2024 button components used `<button onclick="window.location.href=…">`. Newer ones use `<a class="btn">` | If it navigates, it's an `<a>`. If it triggers an action, it's a `<button>`. Audit pre-2024 sites |
| **Focus disappears after AJAX update** | Power Pages Web API calls re-render a region; focus snaps to `<body>` | Move focus explicitly to the new content (see pattern below) |
| **Custom dropdowns with no keyboard support** | Replacing `<select>` with a Bootstrap dropdown built from `<div>`s | Use native `<select>` unless you implement the full ARIA combobox pattern |
| **Color-only field-validation indication** | Red border, no text, no icon | Add `aria-invalid="true"` and an associated `<span class="error">` linked via `aria-describedby` |
| **Iframe-rendered web resources unlabeled** | `Render Web Resources Inline = false` defaults to iframe with no title | Set `Render Web Resources Inline = true`, OR add a `title=` attribute to the iframe |
| **Themes from before Sept 2022** | Older preset themes had below-AA contrast | Re-theme via Styling workspace; see Microsoft's [known-issues remediation](https://learn.microsoft.com/power-pages/known-issues#adjusting-the-background-color-for-your-power-pages-site) |
| **`title=` tooltip as the only label** | Tooltip-as-label is unreliable on touch devices and not always read by AT | Use `<label>` for inputs; reserve `title=` for supplementary description |

## Async UI updates: aria-live regions

The single biggest accessibility gap on Power Pages portals after a custom JS layer is added: screen readers do **not** auto-announce DOM changes that come from XHR. Without an `aria-live` region, a user with NVDA / JAWS / VoiceOver gets no indication that loading finished, the table refreshed, the form was saved, or an error appeared. The page silently changes around them.

Power Pages-specific surfaces that hit this:

- Form submit success / error (custom safeAjax pattern, not the platform `{% entityform %}`)
- Dependent dropdowns populating after a `/_api/<entity>` GET resolves
- Pagination next / prev re-rendering a results region
- Inline validation messages added by client-side JS
- Search-as-you-type filtering an `{% fetchxml %}`-rendered table

### Two patterns: polite vs assertive

| Pattern | Attribute | When the announcement fires | Use for |
|---|---|---|---|
| **Status messages** (transient, low-priority) | `aria-live="polite"` | When the screen reader is idle (after the current utterance finishes) | "Loading 5 results", "Saved", "Page 3 of 8" |
| **Alerts** (errors, validation failures) | `aria-live="assertive"` or `role="alert"` | Interrupts whatever the screen reader was reading | Form validation failure, save error, session expired |

**Default to polite.** `assertive` and `role="alert"` are disruptive, using them for "Loading..." spam will train users to ignore your announcements. Reserve them for genuine errors or anything the user must hear before they continue.

### The empty-then-populate pattern

The most reliable way to announce an async update: put the live region in the page **before** anything happens, leave it empty, then write to it from JS once the change occurs. Live regions added to the DOM and immediately written to are unreliable across browsers and AT combos, Edge + NVDA in particular often misses them.

```html
<div id="status" aria-live="polite" aria-atomic="true" class="sr-only"></div>

<script>
  // Update text from JS, screen reader announces automatically
  document.getElementById('status').textContent = 'Loading 5 office branches';
</script>
```

The `.sr-only` class is the visually-hidden pattern from the [Visually hidden, screen-reader-accessible text](#visually-hidden-screen-reader-accessible-text) section below, keep the region present in the DOM but invisible.

### Why `aria-atomic="true"`

Without `aria-atomic`, partial DOM updates can be announced as their diff. If the live region currently reads "Loading 5..." and you append " results", some screen readers will announce only " results", leaving the user with no context. With `aria-atomic="true"`, the entire region is re-read on every change. For status text that's a short complete sentence, you almost always want this.

### Common mistakes

| Mistake | Why it breaks | Fix |
|---|---|---|
| Adding `aria-live` to an element **after** content is inserted | Screen reader doesn't observe a region that wasn't live when the change happened | Render the empty `<div aria-live="polite">` server-side; only write into it from JS |
| Using `aria-live="assertive"` for non-critical status | Interrupts the user mid-thought; trains them to mute your region | Use `polite` unless it's a genuine error |
| Forgetting `aria-atomic="true"` | "Loading 5 results" gets read as two fragments on subsequent updates | Set `aria-atomic="true"` on status regions |
| Multiple live regions on the same page firing at once | Announcements queue or get dropped | Use one status region and one alert region per logical area; reuse them |
| Writing via `innerHTML` with markup | AT may read the markup or skip the change entirely | Use `textContent`; if rich content is required, `innerHTML` set then a tiny `setTimeout(0)` to rewrite to a sibling can work, but textContent is the safe default |
| `display: none` on the live region | Many AT skip hidden regions entirely | Use the `sr-only` clip pattern, not `display: none` |

### Async patterns for typical Power Pages flows

**Form submit (safeAjax POST).** Pair the form with both a polite status and an assertive alert:

```html
<form id="addCustomer">…</form>
<div id="formStatus" aria-live="polite" aria-atomic="true" class="sr-only"></div>
<div id="formError"  role="alert" class="alert alert-danger d-none"></div>
```

```javascript
function onSubmit(e) {
  e.preventDefault();
  document.getElementById('formStatus').textContent = 'Saving';
  safeAjax({…}).done(function () {
    document.getElementById('formStatus').textContent = 'Customer saved';
  }).fail(function (xhr) {
    var err = document.getElementById('formError');
    err.textContent = parseError(xhr) || 'Save failed. Try again.';
    err.classList.remove('d-none');
  });
}
```

**Dependent dropdown.** Announce on both load-start and load-complete so a slow response doesn't feel like nothing happened:

```javascript
function loadBranches(stateId) {
  var help = document.getElementById('branchHelp');
  help.textContent = 'Loading office branches';
  return webapi.get('/contoso_branches?$filter=_contoso_state_value eq ' + stateId)
    .then(function (data) {
      populateSelect(data.value);
      help.textContent = data.value.length + ' office branches loaded';
    });
}
```

**Pagination.** After re-rendering the results region, announce the page position to confirm the change registered:

```javascript
function renderPage(n, total) {
  rebuildResultsTable(currentPageData);
  document.getElementById('pagerStatus').textContent = 'Page ' + n + ' of ' + total;
}
```

### When in doubt

Test with NVDA + Edge (or VoiceOver + Safari) on the actual portal, not Studio preview, which strips some platform JS and lies about runtime behavior. If the screen reader says nothing when the UI changes, the live region is missing or wrong. If it interrupts the user every second, you've got `assertive` where you wanted `polite`.

The [dependent-dropdown recipe](../recipes/dependent-dropdown.md) and the [hybrid form with safeAjax recipe](../recipes/hybrid-form-with-safeajax.md) both use these patterns inline.

## Custom JS / Liquid patterns

### Skip link

In your page-template root web template, immediately after `<body>`:

```html
<a class="skip-link" href="#main-content">Skip to main content</a>
<header role="banner">…</header>
<nav role="navigation" aria-label="Primary">…</nav>
<main id="main-content" role="main" tabindex="-1">
  {% include 'page_copy' %}
</main>
```

CSS to make it visible only when focused:

```css
.skip-link {
  position: absolute; left: -9999px; top: 0;
  background: #fff; color: #000; padding: 0.5rem 1rem;
  z-index: 1000;
}
.skip-link:focus { left: 0; outline: 2px solid currentColor; }
```

### Focus management after AJAX update

After a Web API GET that re-renders a results region, move focus to the region so AT users hear the change. Build the new DOM safely (avoid `innerHTML` with untrusted strings, Power Pages Web API responses are user-influenced data) and then move focus:

```javascript
function renderResults(items) {
  var container = document.getElementById('results');
  // Clear safely; build with DOM APIs (or a sanitizer like DOMPurify if HTML required)
  while (container.firstChild) { container.removeChild(container.firstChild); }
  items.forEach(function (item) {
    var row = document.createElement('div');
    row.className = 'result-row';
    row.textContent = item.name;            // textContent, not innerHTML
    container.appendChild(row);
  });
  // Make the region focusable and shift focus so AT users hear the update
  container.setAttribute('tabindex', '-1');
  container.focus();
}
```

If a snippet of trusted server-rendered HTML genuinely must be injected (e.g., a Liquid-rendered table fragment from a server-side endpoint you control), sanitize first with DOMPurify. Never `innerHTML =` raw Web API responses.

### Live regions for status messages

For non-blocking status (search complete, autosave success):

```html
<div id="status" role="status" aria-live="polite" aria-atomic="true" class="sr-only"></div>
```

For errors (form validation, save failures):

```html
<div id="errors" role="alert" aria-live="assertive" class="sr-only"></div>
```

```javascript
document.getElementById('status').textContent = 'Found ' + count + ' results';
```

The element must exist in the DOM **before** you write to it. Creating a live region on demand and immediately writing to it does not announce reliably across browsers. Always write via `textContent`, not `innerHTML`.

### Visually hidden, screen-reader-accessible text

```css
.sr-only {
  position: absolute; width: 1px; height: 1px;
  padding: 0; margin: -1px; overflow: hidden;
  clip: rect(0,0,0,0); white-space: nowrap; border: 0;
}
```

Use for the skip link in non-focused state, hidden form labels (when visual design omits them), and live regions.

### Accessible custom validation

```html
<div class="form-group">
  <label for="email">Email <span aria-hidden="true">*</span><span class="sr-only">required</span></label>
  <input type="email" id="email" name="email" required
         aria-required="true"
         aria-invalid="false"
         aria-describedby="email-error">
  <span id="email-error" class="error" role="alert"></span>
</div>
```

```javascript
function setError(input, message) {
  input.setAttribute('aria-invalid', message ? 'true' : 'false');
  document.getElementById(input.id + '-error').textContent = message || '';
}
```

## FetchXML → table rendering with proper a11y

Default Liquid `for` loops emit a `<table>` without semantics. Real audits flag every one of these. Minimal compliant pattern:

```liquid
{% fetchxml rows %}
  <fetch>
    <entity name="contoso_application">
      <attribute name="contoso_name" />
      <attribute name="contoso_status" />
      <attribute name="createdon" />
      <order attribute="createdon" descending="true" />
    </entity>
  </fetch>
{% endfetchxml %}

{% if rows.results.entities.size == 0 %}
  <p>No applications found.</p>
{% else %}
  <table class="table table-striped" aria-describedby="apps-summary">
    <caption id="apps-summary" class="sr-only">
      {{ rows.results.entities.size }} applications, sorted by date submitted (newest first)
    </caption>
    <thead>
      <tr>
        <th scope="col">Name</th>
        <th scope="col">Status</th>
        <th scope="col">Submitted</th>
      </tr>
    </thead>
    <tbody>
      {% for r in rows.results.entities %}
        <tr>
          <th scope="row">{{ r.contoso_name | escape }}</th>
          <td>{{ r.contoso_status.label | escape }}</td>
          <td><time datetime="{{ r.createdon | date: '%Y-%m-%d' }}">{{ r.createdon | date: '%b %-d, %Y' }}</time></td>
        </tr>
      {% endfor %}
    </tbody>
  </table>
{% endif %}
```

Rules: `<caption>` always (visually hide via `.sr-only` if it would clutter the design); `scope="col"` on header cells; `scope="row"` on the first cell of each row when it identifies the row; real `<time datetime=>` for dates; an explicit empty-state message rather than a silent empty table.

## Testing process

A workable Power Pages testing flow that catches >90% of issues before launch.

| Phase | Tool | Catches | Time per page |
|---|---|---|---|
| Build-time | axe-core (npm `@axe-core/cli`) on a published page | Color contrast, label associations, ARIA validity, image alt | 5–10s |
| Build-time | Lighthouse a11y audit (Edge DevTools) | Same as axe + a few unique checks; gives a numeric score for stakeholders | 30s |
| Manual | Accessibility Insights, FastPass | The full ~30 automated WCAG 2.2 checks, in browser | 1 min |
| Manual | Accessibility Insights, Assessment | Manual-verification workflow for the rest of WCAG 2.2 AA | 30–60 min per template |
| Manual | NVDA + Edge OR VoiceOver + Safari | Real screen-reader UX (label clarity, focus order, announcement timing) | 5–15 min per page |
| Manual | Keyboard-only navigation | Focus traps, missing focus styles, custom-widget keyboard support | 5 min per page |
| Manual | 400% zoom in Edge | Reflow failures | 2 min per page |

For an iterative dev loop, axe-core via the browser extension on every save is the highest-ROI single tool. For sign-off documentation, Accessibility Insights Assessment produces a saveable report you can hand to compliance reviewers.

**Sign-off rule**: a Power Pages portal that ships to a government / regulated client without at least one full Accessibility Insights Assessment pass on each distinct page template is exposed. The platform conformance covers chrome and forms; everything else is yours.

> Verified against Microsoft Learn 2026-04-29.
