# Material Design 3 for Power Pages

Google's design system, third major version. Strongest primary system when a Power Pages portal needs **modern mobile-first navigation, vivid systematic state communication, richer interaction states, and clear hierarchy**, particularly for self-service account flows, dashboards, and citizen-facing customer experiences.

## Canonical sources

| Resource | URL |
|---|---|
| Design system docs | https://m3.material.io/ |
| Components catalog | https://m3.material.io/components |
| Foundations (theory) | https://m3.material.io/foundations |
| Color system + tonal palette | https://m3.material.io/styles/color/system/overview |
| Type scale | https://m3.material.io/styles/typography/type-scale-tokens |
| Material Theme Builder | https://material-foundation.github.io/material-theme-builder/ |
| Web component library | https://github.com/material-components/material-web (`@material/web`) |
| Material Symbols (icons) | https://fonts.google.com/icons |
| License | Apache 2.0 (specs + code) |
| Figma kit | https://www.figma.com/community/file/1035203688168086460 |

## Component catalog

Material 3 has a richer component set than USWDS, and **carousel was added in M3** (Material 2 did not have one, this is a common knowledge trap).

| Component | In Material 3? | Notes |
|---|---|---|
| App bars: Top app bar | ✓ | Center-aligned / small / medium / large variants |
| App bars: Bottom app bar | ✓ | With FAB; mobile-first |
| Search | ✓ | Search bar + search view |
| Badges | ✓ | Numeric + dot |
| Bottom sheet | ✓ | Standard + modal |
| Side sheet | ✓ | Standard + modal; tablet/desktop |
| Buttons: Common | ✓ | Filled / Tonal / Elevated / Outlined / Text, five emphasis levels |
| Buttons: FAB | ✓ | Small / Regular / Large / Extended |
| Buttons: Icon button | ✓ | With/without container; toggle state |
| Buttons: Segmented button | ✓ | Single + multi select |
| Cards | ✓ | Elevated / Filled / Outlined |
| **Carousel** | ✓ | **Added in M3.** Hero / Multi-browse / Full-screen / Uncontained variants |
| Checkbox | ✓ | With error state |
| Chips | ✓ | Assist / Filter / Input / Suggestion (four distinct semantic types) |
| Date pickers | ✓ | Modal docked + modal calendar + input |
| Dialog | ✓ | Basic + full-screen |
| Divider | ✓ | Full-width + inset |
| Lists | ✓ | One/two/three-line; with icons / avatars / images |
| Menus | ✓ | Dropdown + cascading |
| Navigation bar | ✓ | Mobile bottom nav (3-5 destinations) |
| Navigation drawer | ✓ | Standard + modal; can be permanent on desktop |
| Navigation rail | ✓ | Tablet/desktop alternative to bottom nav |
| Progress indicators | ✓ | Linear (determinate / indeterminate) + Circular |
| Radio button | ✓ | With error state |
| Sliders | ✓ | Continuous / Discrete / Range |
| Snackbar | ✓ | With action; auto-dismiss |
| Switch | ✓ | With icon-on-thumb option |
| Tabs | ✓ | Primary + Secondary |
| Text fields | ✓ | Filled + Outlined |
| Time pickers | ✓ | Dial + input |
| Toolbar | ✓ | Floating action toolbar pattern |
| Tooltip | ✓ | Plain + rich |
| **Banner** | ✗ | Removed from M3 (was in M2), use Snackbar or in-page Card |
| **Step indicator / Stepper** | partial | Not a first-class M3 component; M3 uses linear progress + content sectioning |
| **Hero (USWDS-style)** | partial | M3 does not name a "hero" component; build from large display type + image + button |
| **Data table (sortable / filterable)** | partial | M3 doesn't ship a heavy data-table component; borrow from Fluent 2 for enterprise tables |

## Token theory

M3 introduced **dynamic color via tonal palettes**, a major shift from M2's primary/secondary/etc. with manual tints.

### Color: tonal palette + semantic roles

A **tonal palette** is a single hue rendered at 13 tones (0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99, 100). The **scheme** maps tonal palette tones into semantic roles for light + dark mode.

Core semantic role pairs (each has `<role>` and `on-<role>` for foreground):
- `primary` / `on-primary` / `primary-container` / `on-primary-container`
- `secondary` / `on-secondary` / `secondary-container` / `on-secondary-container`
- `tertiary` / `on-tertiary` / `tertiary-container` / `on-tertiary-container`
- `error` / `on-error` / `error-container` / `on-error-container`
- `surface` / `on-surface` / `surface-variant` / `on-surface-variant`
- `surface-container-lowest` / `surface-container-low` / `surface-container` / `surface-container-high` / `surface-container-highest`
- `outline` / `outline-variant`
- `inverse-surface` / `inverse-on-surface` / `inverse-primary`
- `scrim` / `shadow`

CSS custom property convention: `--md-sys-color-<role>` (e.g., `--md-sys-color-primary`, `--md-sys-color-on-surface`).

**Generate a scheme from a single source color** via the Material Theme Builder; the result is a complete light + dark palette with WCAG-compliant pairings.

### Type scale

M3 defines five role groups, each with three sizes:
- `display-large`, `display-medium`, `display-small`
- `headline-large`, `headline-medium`, `headline-small`
- `title-large`, `title-medium`, `title-small`
- `body-large`, `body-medium`, `body-small`
- `label-large`, `label-medium`, `label-small`

Default font is **Roboto** (Apache 2.0). Each role has weight, size, line-height, letter-spacing pre-baked. CSS convention: `--md-sys-typescale-<role>-<property>`.

### Shape

Five corner-radius tiers: `none` (0), `extra-small` (4), `small` (8), `medium` (12), `large` (16), `extra-large` (28), `full` (50%). CSS: `--md-sys-shape-corner-<size>`.

### Elevation

Six levels (0-5), expressed as **surface tint overlays** rather than only shadows in M3, this is a deliberate change from M2. Shadow values still exist but pair with tonal elevation.

### Motion

- Duration tokens: `short1` (50ms) through `extra-long4` (1000ms)
- Easing tokens: `emphasized`, `emphasized-decelerate`, `emphasized-accelerate`, `standard`, `standard-decelerate`, `standard-accelerate`, `legacy`
- M3 strongly recommends `emphasized` curves over linear

## Power Pages implementation bias

- Use Material Theme Builder once, export the CSS variables, and ship them in the portal CSS file.
- **Do not pull in `@material/web`**, it's a Web Components library that may collide with Power Pages Studio rendering and assumes a build pipeline. Re-implement the components you need with HTML + tokens.
- Material Symbols can ship as a self-hosted variable font (Apache 2.0); don't depend on `fonts.googleapis.com` if strict CSP is in play.
- Surface tint elevation is a CSS-only effect, feasible to recreate without JS.

## License + foot-guns

- **Specs and code: Apache 2.0**, safe to use commercially. Attribution recommended (NOTICE file).
- **Roboto: Apache 2.0**, bundle locally.
- **Material Symbols: Apache 2.0**, bundle the variable font; no attribution required, but a NOTICE entry is courteous.
- **`@material/web` Web Components**, do not import directly into Power Pages; they can fight Studio's rendering pipeline and require build tooling.
- **Don't confuse M2 and M3**, M2 `theme.palette.primary.main` ≠ M3 `--md-sys-color-primary`. Models trained on older Material content may emit M2 token names.
- **Tonal palette source-color expansion** is non-trivial math; use Material Theme Builder rather than guessing tones.

## Component-level guidance

### Cards

M3 distinguishes Elevated / Filled / Outlined, these have semantic meaning, not just visual variation:
- Elevated: highest emphasis, hover lift
- Filled: medium emphasis, surface-container-highest background
- Outlined: lowest emphasis, content-first

### Buttons (five emphasis levels)

- Filled: primary action only (one per surface ideally)
- Tonal (filled-tonal): secondary actions with more emphasis than outlined
- Elevated: secondary action when surface is busy
- Outlined: secondary actions
- Text: lowest emphasis (cancel / dismiss / inline)

### Carousel (M3-native)

Four variants, pick by content:
- **Hero**: one large item, peek of next
- **Multi-browse**: 2-4 items visible, browsable
- **Full-screen**: vertical full-width, e.g., onboarding
- **Uncontained**: scrolling without container chrome

Always include keyboard nav, pause control if auto-advancing, and `prefers-reduced-motion` disable. M3 carousels do **not** auto-advance by default, that's a deliberate accessibility choice.

## Responsive bias

Material 3 is one of the strongest sources for mobile patterns:
- **Mobile**: bottom nav for 3-5 top destinations; bottom sheets for menus; FAB for primary action
- **Tablet**: navigation rail (60-80px wide) replaces bottom nav; drawer for richer nav
- **Desktop**: permanent navigation drawer; rail still viable

Density reduction on mobile is built into the type scale (use `body-medium` not `body-large` for dense lists).

See [responsive-defaults.md](responsive-defaults.md) for cross-system responsive rules.

## Pairing with other systems

- **USWDS 3**, when civic seriousness is needed; borrow USWDS form rigor + plain language; see [uswds-3.md](uswds-3.md)
- **Fluent 2**, when enterprise data density is needed (Material is not strong here); see [fluent-2.md](fluent-2.md)
- **shadcn/ui**, when the team wants restrained web-product feel without M3's heavy color system; see [shadcn-ui.md](shadcn-ui.md)
- **Apple HIG**, Material and HIG conflict on motion language; do not mix both equally, pick one motion system and let the other contribute spacing/clarity only

See [system-selection.md](system-selection.md) for selection logic and [crossover-recipes.md](crossover-recipes.md) for concrete combined patterns.
