# Crossover Recipes

Concrete code patterns for the most-asked design-system crossovers in Power Pages. Each recipe identifies a **primary system** (whose tokens, type, and a11y posture are preserved) and a **secondary system** (whose component anatomy is borrowed). Code is CSP-safe (no inline scripts, no runtime injection) and Power-Pages-implementable (no React, no build pipeline assumed).

For the rules that govern these recipes, see [system-selection.md](system-selection.md). For per-system tokens and catalogs, see the individual system files.

---

## Recipe 1: USWDS hero with Material 3 carousel

**When to use**: Civic / grants / public-service portal that the stakeholder insists must rotate featured items. USWDS deliberately removed carousel; Material 3 added it.

**Primary**: USWDS 3 (typography, color, focus, plain language)
**Borrowed from**: Material 3 (carousel anatomy + motion principles)

```html
<section class="usa-section pp-carousel" aria-roledescription="carousel" aria-label="Featured programs">
  <div class="usa-prose">
    <h2 id="featured-heading">Featured programs</h2>
  </div>
  <div class="pp-carousel__track" role="group" aria-labelledby="featured-heading">
    <div class="pp-carousel__slide" role="group" aria-roledescription="slide" aria-label="1 of 3">
      <article class="usa-card">
        <header class="usa-card__header"><h3 class="usa-card__heading">Small Business Grants</h3></header>
        <div class="usa-card__body"><p>Funding opportunities for businesses under 50 employees.</p></div>
        <footer class="usa-card__footer"><a class="usa-button" href="/grants/sb">Learn more</a></footer>
      </article>
    </div>
    <!-- additional slides -->
  </div>
  <div class="pp-carousel__controls">
    <button type="button" class="usa-button usa-button--outline" data-pp-carousel="prev" aria-label="Previous slide">&lsaquo; Prev</button>
    <button type="button" class="usa-button usa-button--outline" data-pp-carousel="pause" aria-pressed="false">Pause</button>
    <button type="button" class="usa-button usa-button--outline" data-pp-carousel="next" aria-label="Next slide">Next &rsaquo;</button>
  </div>
</section>
```

```css
/* Keep USWDS tokens; only borrow Material 3 carousel layout/motion */
.pp-carousel { padding-block: var(--theme-spacing-section, 4rem); }
.pp-carousel__track {
  display: flex; gap: 1rem; overflow-x: auto;
  scroll-snap-type: x mandatory; scroll-behavior: smooth;
  scrollbar-width: thin;
}
.pp-carousel__slide { flex: 0 0 100%; scroll-snap-align: start; }
@media (min-width: 64em) { .pp-carousel__slide { flex-basis: calc(33.333% - 0.667rem); } }
.pp-carousel__controls { display: flex; gap: 0.5rem; margin-block-start: 1rem; }

@media (prefers-reduced-motion: reduce) {
  .pp-carousel__track { scroll-behavior: auto; }
}
```

```javascript
// /web-files/pp-carousel.js, local file, no runtime injection
(function () {
  document.querySelectorAll('.pp-carousel').forEach(initCarousel);
  function initCarousel(root) {
    var slides = root.querySelectorAll('.pp-carousel__slide');
    var current = 0, paused = false;
    var motionOK = !window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    function go(idx) {
      current = (idx + slides.length) % slides.length;
      slides[current].scrollIntoView({ behavior: motionOK ? 'smooth' : 'auto', inline: 'start', block: 'nearest' });
    }
    root.querySelector('[data-pp-carousel="next"]').addEventListener('click', function () { go(current + 1); });
    root.querySelector('[data-pp-carousel="prev"]').addEventListener('click', function () { go(current - 1); });
    var pauseBtn = root.querySelector('[data-pp-carousel="pause"]');
    pauseBtn.addEventListener('click', function () {
      paused = !paused;
      pauseBtn.setAttribute('aria-pressed', String(paused));
      pauseBtn.textContent = paused ? 'Play' : 'Pause';
    });

    root.addEventListener('keydown', function (e) {
      if (e.key === 'ArrowLeft') go(current - 1);
      if (e.key === 'ArrowRight') go(current + 1);
    });

    // Material 3 default: do NOT auto-advance. Enable explicitly only if the stakeholder requires it.
    // if (motionOK) setInterval(function () { if (!paused) go(current + 1); }, 6000);
  }
})();
```

**Why this works**:
- USWDS tokens, button styling, card structure, focus rings preserved
- Material 3 carousel anatomy (multi-browse on desktop, single-slide on mobile via flex-basis) borrowed
- No auto-advance by default (Material 3 accessibility default; USWDS would have insisted anyway)
- Keyboard support, pause control, reduced-motion respect

---

## Recipe 2: USWDS web with iOS-native mobile feel

**When to use**: USWDS-primary government portal that must feel like an iOS app on phones (PWA install, mobile-first service kiosk, "feels like an app" stakeholder request, and the user has chosen iOS feel).

**Primary**: USWDS 3 (color, type, content tone, focus, accessibility posture)
**Borrowed from**: Apple HIG (bottom tab bar, large title with scroll-collapse, sheet presentation)

```html
<header class="pp-mobile-header" data-pp-large-title>
  <h1 class="pp-mobile-header__title">My Benefits</h1>
</header>
<main class="pp-mobile-main">
  <!-- page content -->
</main>
<nav class="pp-tab-bar" aria-label="Primary">
  <a class="pp-tab-bar__item" href="/home" aria-current="page">
    <svg aria-hidden="true" class="pp-tab-bar__icon"><!-- Lucide: home --></svg>
    <span>Home</span>
  </a>
  <a class="pp-tab-bar__item" href="/applications">
    <svg aria-hidden="true" class="pp-tab-bar__icon"><!-- Lucide: file-text --></svg>
    <span>Applications</span>
  </a>
  <a class="pp-tab-bar__item" href="/messages">
    <svg aria-hidden="true" class="pp-tab-bar__icon"><!-- Lucide: message-square --></svg>
    <span>Messages</span>
  </a>
  <a class="pp-tab-bar__item" href="/account">
    <svg aria-hidden="true" class="pp-tab-bar__icon"><!-- Lucide: user --></svg>
    <span>Account</span>
  </a>
</nav>
```

```css
/* iOS feel: safe-area inset for notch/home-bar, large title scroll-collapse, translucent tab bar */
.pp-mobile-header {
  position: sticky; top: 0;
  background: var(--pp-uswds-bg, #fff);
  padding: 1rem; padding-top: max(1rem, env(safe-area-inset-top));
  border-bottom: 1px solid var(--pp-uswds-base-light, #dfe1e2);
  transition: padding 200ms;
}
.pp-mobile-header__title { font-size: 2rem; margin: 0; }  /* USWDS type scale, iOS-large-title rhythm */

/* Scroll-collapse: title shrinks as user scrolls */
.pp-mobile-header[data-collapsed] .pp-mobile-header__title { font-size: 1.125rem; }
.pp-mobile-header[data-collapsed] { padding-block: 0.5rem; }

.pp-tab-bar {
  position: fixed; bottom: 0; left: 0; right: 0;
  display: flex; justify-content: space-around;
  background: rgba(255,255,255,0.92);
  backdrop-filter: saturate(180%) blur(16px);  /* iOS-native translucent feel */
  border-top: 1px solid var(--pp-uswds-base-light, #dfe1e2);
  padding-bottom: env(safe-area-inset-bottom);  /* iOS home indicator */
}
.pp-tab-bar__item {
  flex: 1; display: flex; flex-direction: column; align-items: center; gap: 2px;
  padding: 0.5rem; min-height: 44px;  /* HIG + WCAG touch target */
  color: var(--pp-uswds-base-dark, #565c65);
  text-decoration: none; font-size: 0.75rem;
}
.pp-tab-bar__item[aria-current="page"] {
  color: var(--pp-uswds-primary, #005ea2);  /* USWDS color preserved */
}

@media (min-width: 64em) { .pp-tab-bar { display: none; } }

@media (prefers-reduced-motion: reduce) {
  .pp-mobile-header { transition: none; }
}
```

```javascript
// /web-files/pp-large-title.js
(function () {
  var header = document.querySelector('[data-pp-large-title]');
  if (!header) return;
  var threshold = 80;
  function onScroll() {
    if (window.scrollY > threshold) header.setAttribute('data-collapsed', '');
    else header.removeAttribute('data-collapsed');
  }
  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();
})();
```

**Why this works**:
- USWDS color tokens (`--pp-uswds-primary`, base dark/light) preserved on every surface
- iOS feel comes from: `env(safe-area-inset-*)` for notch/home-bar, translucent tab bar with `backdrop-filter`, large-title scroll-collapse, 44px touch targets
- Lucide icons (ISC license) substitute for SF Symbols (which can't ship on web)
- Desktop reverts to standard USWDS nav, the iOS feel is mobile-only

---

## Recipe 3: USWDS web with Android-native mobile feel

**When to use**: USWDS-primary government portal that must feel like an Android app on phones (user chose Android feel, or "cross-platform / unsure" defaulted to Material 3).

**Primary**: USWDS 3 (color, type, content tone, focus, accessibility posture)
**Borrowed from**: Material 3 (M3 navigation bar, FAB, bottom sheet)

```html
<main class="pp-android-main">
  <!-- page content -->
</main>
<nav class="pp-m3-navbar" aria-label="Primary">
  <a class="pp-m3-navbar__item" href="/home" aria-current="page">
    <span class="pp-m3-navbar__icon-wrap">
      <svg aria-hidden="true" class="pp-m3-navbar__icon"><!-- Material Symbols: home --></svg>
    </span>
    <span class="pp-m3-navbar__label">Home</span>
  </a>
  <a class="pp-m3-navbar__item" href="/applications">
    <span class="pp-m3-navbar__icon-wrap">
      <svg aria-hidden="true" class="pp-m3-navbar__icon"><!-- description --></svg>
    </span>
    <span class="pp-m3-navbar__label">Applications</span>
  </a>
  <a class="pp-m3-navbar__item" href="/messages">
    <span class="pp-m3-navbar__icon-wrap">
      <svg aria-hidden="true" class="pp-m3-navbar__icon"><!-- chat --></svg>
    </span>
    <span class="pp-m3-navbar__label">Messages</span>
  </a>
  <a class="pp-m3-navbar__item" href="/account">
    <span class="pp-m3-navbar__icon-wrap">
      <svg aria-hidden="true" class="pp-m3-navbar__icon"><!-- person --></svg>
    </span>
    <span class="pp-m3-navbar__label">Account</span>
  </a>
</nav>
<!-- M3 FAB for primary action (e.g., "New application") -->
<button type="button" class="pp-m3-fab" aria-label="Start new application">
  <svg aria-hidden="true"><!-- Material Symbols: add --></svg>
</button>
```

```css
/* Android feel: M3 navigation bar with active-indicator pill, FAB at bottom-right */
.pp-m3-navbar {
  position: fixed; bottom: 0; left: 0; right: 0;
  display: flex; height: 80px;  /* M3 navigation bar height */
  background: var(--pp-uswds-bg, #fff);
  border-top: 1px solid var(--pp-uswds-base-light, #dfe1e2);
}
.pp-m3-navbar__item {
  flex: 1; display: flex; flex-direction: column; align-items: center;
  justify-content: center; gap: 4px;
  color: var(--pp-uswds-base-dark, #565c65);
  text-decoration: none; font-size: 0.75rem;
  min-height: 44px;
}
.pp-m3-navbar__icon-wrap {
  display: inline-flex; align-items: center; justify-content: center;
  width: 64px; height: 32px; border-radius: 16px;  /* M3 active-indicator pill shape */
  transition: background 200ms;
}
.pp-m3-navbar__item[aria-current="page"] .pp-m3-navbar__icon-wrap {
  background: var(--pp-uswds-primary-lighter, #d9e8f6);  /* USWDS color, M3 indicator anatomy */
}
.pp-m3-navbar__item[aria-current="page"] {
  color: var(--pp-uswds-primary-darker, #1a4480);
}

.pp-m3-fab {
  position: fixed; right: 1rem; bottom: calc(80px + 1rem);
  width: 56px; height: 56px; border-radius: 16px;
  background: var(--pp-uswds-primary, #005ea2);  /* USWDS color */
  color: white; border: none;
  box-shadow: 0 3px 5px rgba(0,0,0,0.2);
  display: flex; align-items: center; justify-content: center;
}

@media (min-width: 64em) {
  .pp-m3-navbar, .pp-m3-fab { display: none; }
}

@media (prefers-reduced-motion: reduce) {
  .pp-m3-navbar__icon-wrap { transition: none; }
}
```

**Why this works**:
- USWDS color tokens preserved everywhere, the FAB is *USWDS primary blue*, not M3's source-color generated tone
- Android feel comes from: M3 navigation bar height (80px, not iOS 49pt), active-indicator pill anatomy, FAB shape and position, Material Symbols icons
- Material Symbols (Apache 2.0) bundle locally; safer than fonts.googleapis.com under CSP
- Desktop reverts to USWDS standard nav

---

## Recipe 4: Fluent 2 enterprise card with shadcn polish

**When to use**: Fluent 2-primary partner/vendor portal where the stock Fluent card pattern feels too utilitarian for a customer-facing surface. shadcn's card composition is more polished without breaking enterprise tone.

**Primary**: Fluent 2 (tokens, type, density, enterprise feel)
**Borrowed from**: shadcn/ui (card composition: `CardHeader` / `CardTitle` / `CardDescription` / `CardContent` / `CardFooter`)

```html
<article class="pp-fluent-card">
  <header class="pp-fluent-card__header">
    <h3 class="pp-fluent-card__title">Q3 Procurement Summary</h3>
    <p class="pp-fluent-card__description">Open POs across active vendor accounts</p>
  </header>
  <div class="pp-fluent-card__content">
    <dl class="pp-fluent-card__metrics">
      <div><dt>Total POs</dt><dd>247</dd></div>
      <div><dt>Pending review</dt><dd>14</dd></div>
      <div><dt>Overdue</dt><dd>3</dd></div>
    </dl>
  </div>
  <footer class="pp-fluent-card__footer">
    <button type="button" class="pp-fluent-button pp-fluent-button--primary">View all</button>
    <button type="button" class="pp-fluent-button pp-fluent-button--subtle">Export</button>
  </footer>
</article>
```

```css
.pp-fluent-card {
  background: var(--colorNeutralBackground1, #fff);
  border: 1px solid var(--colorNeutralStroke2, #e0e0e0);
  border-radius: var(--borderRadiusMedium, 4px);  /* Fluent's restrained corners */
  display: flex; flex-direction: column;
  gap: var(--spacingVerticalM, 12px);
  padding: var(--spacingHorizontalL, 16px);
}
.pp-fluent-card__header { display: flex; flex-direction: column; gap: var(--spacingVerticalXS, 4px); }
.pp-fluent-card__title {
  font-size: var(--fontSizeBase500, 1rem); font-weight: var(--fontWeightSemibold, 600);
  margin: 0; color: var(--colorNeutralForeground1, #242424);
}
.pp-fluent-card__description {
  font-size: var(--fontSizeBase200, 0.75rem);
  color: var(--colorNeutralForeground2, #424242); margin: 0;
}
.pp-fluent-card__metrics {
  display: grid; grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
  gap: var(--spacingHorizontalM, 12px);
  margin: 0;
}
.pp-fluent-card__metrics div { display: flex; flex-direction: column; gap: 2px; }
.pp-fluent-card__metrics dt {
  font-size: var(--fontSizeBase200, 0.75rem); color: var(--colorNeutralForeground2, #424242);
}
.pp-fluent-card__metrics dd {
  font-size: var(--fontSizeHero700, 1.5rem); font-weight: var(--fontWeightSemibold, 600);
  margin: 0; color: var(--colorNeutralForeground1, #242424);
}
.pp-fluent-card__footer {
  display: flex; gap: var(--spacingHorizontalS, 8px);
  border-top: 1px solid var(--colorNeutralStroke3, #f0f0f0);
  padding-top: var(--spacingVerticalM, 12px);
}
```

**Why this works**:
- All tokens are Fluent (alias names, restrained 4px radius, enterprise spacing)
- shadcn's compound-component thinking (Header / Title / Description / Content / Footer) gives a more polished composition than ad-hoc Fluent markup
- No React, no Radix, no Tailwind, just semantic HTML + Fluent CSS variables
- The `<dl>` for metrics is a small accessibility upgrade shadcn's marketing examples sometimes skip

---

## Recipe 5: shadcn/ui product portal with USWDS form rigor

**When to use**: shadcn-primary modern web portal where citizen-facing forms (registration, eligibility intake) need stronger labeling, validation summaries, and plain-language error messages than shadcn's default `<Form>` examples provide.

**Primary**: shadcn/ui (visual surfaces, layout, modern feel)
**Borrowed from**: USWDS 3 (form rhythm, helper text + error summary, required indication, plain-language tone)

```html
<form class="pp-shadcn-form" novalidate>
  <!-- USWDS-style validation summary at top -->
  <div class="pp-form-summary" role="alert" data-pp-form-summary hidden>
    <h2 class="pp-form-summary__heading">There is a problem</h2>
    <ul class="pp-form-summary__list"></ul>
  </div>

  <fieldset class="pp-fieldset">
    <legend class="pp-legend">Your contact information</legend>

    <div class="pp-field">
      <label for="email" class="pp-label">
        Email address <span class="pp-required-text">(required)</span>
      </label>
      <p class="pp-helper-text" id="email-hint">We use this for grant status updates only.</p>
      <input type="email" id="email" name="email" class="pp-input" required
             aria-describedby="email-hint" aria-invalid="false" />
      <p class="pp-error-text" id="email-error" hidden></p>
    </div>

    <!-- additional fields -->
  </fieldset>

  <button type="submit" class="pp-button pp-button--primary">Submit application</button>
</form>
```

```css
/* shadcn surfaces (radii, surface tokens) + USWDS form rhythm and required-indication */
.pp-shadcn-form { max-width: 40rem; }

.pp-fieldset {
  border: 1px solid hsl(var(--border, 214 32% 91%));
  border-radius: var(--radius, 0.5rem);
  padding: 1.5rem;
  display: flex; flex-direction: column; gap: 1.25rem;
}
.pp-legend {
  font-size: 1.125rem; font-weight: 600;
  padding: 0 0.5rem;
}

.pp-field { display: flex; flex-direction: column; gap: 0.375rem; }
.pp-label { font-weight: 500; font-size: 0.875rem; }
.pp-required-text {
  font-weight: 400; font-size: 0.75rem;
  color: hsl(var(--muted-foreground, 215 16% 47%));
}
.pp-helper-text {  /* USWDS: helper text BEFORE the input, not in placeholder */
  font-size: 0.8125rem;
  color: hsl(var(--muted-foreground, 215 16% 47%));
  margin: 0;
}
.pp-input {
  border: 1px solid hsl(var(--input, 214 32% 91%));
  border-radius: var(--radius, 0.5rem);
  padding: 0.5rem 0.75rem; font-size: 0.875rem;
  min-height: 44px;  /* WCAG 2.2 AA touch target */
}
.pp-input:focus-visible {
  outline: 2px solid hsl(var(--ring, 215 20% 65%));  /* shadcn focus ring */
  outline-offset: 2px;
}
.pp-input[aria-invalid="true"] {
  border-color: hsl(var(--destructive, 0 84% 60%));
}
.pp-error-text {
  color: hsl(var(--destructive, 0 84% 60%));
  font-size: 0.8125rem; margin: 0;
}

.pp-form-summary {
  border-left: 4px solid hsl(var(--destructive, 0 84% 60%));
  background: hsl(var(--destructive, 0 84% 60%) / 0.06);
  padding: 1rem 1.25rem;
  border-radius: var(--radius, 0.5rem);
  margin-block-end: 1.5rem;
}
.pp-form-summary__heading { font-size: 1rem; font-weight: 600; margin: 0 0 0.5rem; }
.pp-form-summary__list { margin: 0; padding-left: 1.25rem; }

.pp-button {
  border-radius: var(--radius, 0.5rem);
  padding: 0.5rem 1rem; font-weight: 500;
  min-height: 44px;
  border: 1px solid transparent;
}
.pp-button--primary {
  background: hsl(var(--primary, 222 47% 11%));
  color: hsl(var(--primary-foreground, 210 40% 98%));
}
```

```javascript
// /web-files/pp-form-validation.js
// USWDS-style: validate on submit, show inline errors AND populate summary at top.
// Uses textContent + DOM construction (no innerHTML) for XSS safety.
(function () {
  document.querySelectorAll('.pp-shadcn-form').forEach(function (form) {
    form.addEventListener('submit', function (e) {
      var errors = [];
      form.querySelectorAll('input, select, textarea').forEach(function (field) {
        var errorEl = document.getElementById(field.id + '-error');
        if (!field.checkValidity()) {
          var msg = customMessage(field) || field.validationMessage;
          field.setAttribute('aria-invalid', 'true');
          if (errorEl) { errorEl.textContent = msg; errorEl.hidden = false; }
          errors.push({ id: field.id, label: labelFor(field), message: msg });
        } else {
          field.setAttribute('aria-invalid', 'false');
          if (errorEl) { errorEl.textContent = ''; errorEl.hidden = true; }
        }
      });
      var summary = form.querySelector('[data-pp-form-summary]');
      if (errors.length) {
        e.preventDefault();
        var ul = summary.querySelector('.pp-form-summary__list');
        ul.replaceChildren();  // safer than innerHTML = '', explicit DOM clear
        errors.forEach(function (err) {
          var li = document.createElement('li');
          var a = document.createElement('a');
          a.href = '#' + err.id;
          a.textContent = err.label + ': ' + err.message;  // textContent, not innerHTML
          li.appendChild(a);
          ul.appendChild(li);
        });
        summary.hidden = false;
        summary.focus();
      } else {
        summary.hidden = true;
      }
    });
    function labelFor(field) {
      var lbl = form.querySelector('label[for="' + field.id + '"]');
      return lbl ? lbl.textContent.replace(/\s*\(required\).*/i, '').trim() : field.name;
    }
    function customMessage(field) {
      // Plain-language replacements per USWDS guidance.
      if (field.type === 'email' && field.validity.typeMismatch) return 'Enter your email in the format name@example.com.';
      if (field.validity.valueMissing) return 'This field is required.';
      return null;
    }
  });
})();
```

**Why this works**:
- shadcn token language preserved (`hsl(var(--primary))`, `var(--radius)`), visual identity stays modern web product
- USWDS form patterns layered on top:
  - Required indicated by **asterisk text**, not just an asterisk symbol (USWDS A11y rule)
  - Helper text **before** the input, not in placeholder (USWDS rule)
  - Plain-language error messages, not browser defaults
  - Validation summary at top with anchor links to fields (USWDS pattern; shadcn's default `<Form>` does inline-only)
- 44px touch targets across all controls
- DOM construction with `textContent` + `replaceChildren`, no innerHTML, no XSS surface
- All vanilla JS, CSP-safe, no React or zod required

---

## Recipe 6: Apple HIG calm + USWDS civic seriousness

**When to use**: Premium government / quasi-government portal (state-level economic development, museum membership, library systems) that wants Apple HIG calm + spacing + readability with USWDS rigor on forms and content tone.

**Primary**: USWDS 3 (content tone, accessibility, focus, plain-language messaging)
**Borrowed from**: Apple HIG (spacing rhythm, type calm, dark-mode parity, restrained motion)

This recipe is mostly **token translation**, no new components needed, just a calmer expression of USWDS via HIG-style spacing and dark-mode treatment.

```css
/* USWDS tokens, HIG-flavored spacing rhythm and dark mode */
:root {
  /* USWDS color tokens */
  --pp-primary: #005ea2;
  --pp-primary-darker: #1a4480;
  --pp-primary-lighter: #d9e8f6;
  --pp-base: #565c65;
  --pp-base-light: #dfe1e2;
  --pp-base-lighter: #f0f0f0;
  --pp-bg: #ffffff;
  --pp-fg: #1b1b1b;

  /* HIG-flavored spacing (8pt grid, generous on the high end) */
  --pp-space-1: 4px;
  --pp-space-2: 8px;
  --pp-space-3: 12px;
  --pp-space-4: 16px;
  --pp-space-5: 24px;
  --pp-space-6: 32px;
  --pp-space-7: 48px;
  --pp-space-8: 64px;

  /* HIG-flavored type rhythm (semantic styles, scale via rem) */
  --pp-type-large-title: 2.125rem;
  --pp-type-title-1: 1.75rem;
  --pp-type-title-2: 1.375rem;
  --pp-type-title-3: 1.25rem;
  --pp-type-headline: 1.0625rem;
  --pp-type-body: 1.0625rem;
  --pp-type-callout: 1rem;
  --pp-type-footnote: 0.8125rem;

  /* HIG continuous-corner approximation */
  --pp-radius-sm: 6px;
  --pp-radius-md: 10px;
  --pp-radius-lg: 16px;
}

@media (prefers-color-scheme: dark) {
  :root {
    --pp-primary: #4f97d4;       /* USWDS-derived but lifted for dark */
    --pp-primary-darker: #73b3e7;
    --pp-base: #a9aeb1;
    --pp-base-light: #565c65;
    --pp-base-lighter: #2d3033;
    --pp-bg: #1c1c1e;             /* HIG systemBackground equivalent */
    --pp-fg: #f2f2f7;
  }
}

body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI Variable", "Public Sans",
               "Segoe UI", Roboto, sans-serif;
  font-size: var(--pp-type-body);
  line-height: 1.5;
  background: var(--pp-bg); color: var(--pp-fg);
}

h1 { font-size: var(--pp-type-large-title); margin-block: var(--pp-space-7) var(--pp-space-4); }
h2 { font-size: var(--pp-type-title-1); margin-block: var(--pp-space-6) var(--pp-space-3); }
h3 { font-size: var(--pp-type-title-2); margin-block: var(--pp-space-5) var(--pp-space-3); }

.pp-section { padding-block: var(--pp-space-8); }
.pp-prose { max-width: 38rem; }  /* HIG line-length restraint, USWDS prose width */
```

**Why this works**:
- All semantic colors are USWDS-derived; HIG contributes the **calm spacing rhythm** and **dark-mode posture**
- `-apple-system` first in the font stack gives Apple users actual SF (no licensing issue), then falls back to Segoe / Public Sans / web stack
- Continuous-corner approximation via `border-radius` is acceptable for web (HIG's actual squircle math isn't reproducible in CSS without an SVG mask)
- Dark mode is first-class, light is the **secondary**, not the only mode

---

## What's not in these recipes

- **Tailwind configurations**, these recipes use plain CSS variables so they work in classic Power Pages portals without a build pipeline
- **React component code**, every recipe is HTML + CSS + vanilla JS
- **CDN dependencies**, every asset (fonts, icons, JS) is meant to be vendored locally per [strict-csp.md](strict-csp.md)
- **Auto-installing CLI commands**, no `npx shadcn add card` or `dotnet tool install`; recipes can be implemented by hand by reading the source

When a stakeholder asks for something not covered here, follow the rule in [system-selection.md](system-selection.md): identify the primary system, identify what's missing, borrow only the anatomy needed, re-express in the primary tokens, verify accessibility and responsive behavior.
