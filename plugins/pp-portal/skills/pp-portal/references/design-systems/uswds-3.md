# USWDS 3 for Power Pages

The U.S. Web Design System version 3, the de-facto baseline for U.S. federal sites and the strongest primary system when a Power Pages portal must feel **official, plain-language, trustworthy, and accessible by default**. Especially appropriate for grants portals, eligibility flows, public-facing service delivery, and compliance-heavy workflows.

## Canonical sources

Always link the user to these for the *current* spec; the catalog below is for the model's own reference so it doesn't have to fetch on every question.

| Resource | URL |
|---|---|
| Design system docs | https://designsystem.digital.gov/ |
| Components catalog | https://designsystem.digital.gov/components/ |
| Design tokens | https://designsystem.digital.gov/design-tokens/ |
| Utilities (CSS reference) | https://designsystem.digital.gov/utilities/ |
| GitHub | https://github.com/uswds/uswds |
| npm package | `@uswds/uswds` |
| License | Public domain (CC0), no attribution required |
| Figma kit | https://designsystem.digital.gov/documentation/figma-libraries/ |

## Component catalog

USWDS 3 exposes a deliberately restrained set. **Components marked ✗ are not in this system on purpose**, borrow from another system per the [crossover recipes](crossover-recipes.md), keeping USWDS tokens and accessibility posture.

| Component | In USWDS 3? | Notes |
|---|---|---|
| Accordion | ✓ | Bordered + borderless variants |
| Alert | ✓ | info / warning / error / success / emergency |
| Banner (gov identification) | ✓ | The dotgov + HTTPS lock pattern |
| Breadcrumb | ✓ | Wrapping + non-wrapping |
| Button | ✓ | Default / secondary / accent-cool / accent-warm / outline / unstyled / big variants |
| Button group | ✓ | Default + segmented |
| Card | ✓ | Header / body / footer; flag layout for media beside content |
| Character count | ✓ | Live region for assistive tech |
| Checkbox | ✓ | Tile variant for richer choices |
| Collection | ✓ | Lists with metadata |
| Combo box | ✓ | Search + select hybrid |
| Date picker | ✓ | Keyboard-first |
| Date range picker | ✓ | Two linked date pickers |
| File input | ✓ | Multi-file + drag/drop |
| Footer | ✓ | Big / medium / slim variants |
| Form | ✓ | Layout patterns for civic forms |
| Header | ✓ | Basic + extended; with mega menu |
| Hero | ✓ | **No carousel by design** |
| Icon | ✓ | USWDS Icons (Material-derived, public domain bundled) |
| Icon list | ✓ | Vertical lists with leading icons |
| Identifier | ✓ | "Required Links" footer block |
| In-page navigation | ✓ | Auto-generated from headings |
| Input mask | ✓ | Phone, ZIP, etc. |
| Input prefix/suffix | ✓ | $ before, .gov after, etc. |
| Language selector | ✓ | Multi-language sites |
| Link | ✓ | External-link icon + visited treatment |
| List | ✓ | Unordered, ordered, plain |
| Memorable date | ✓ | MM / DD / YYYY split inputs |
| Modal | ✓ | Force-action + dismissible |
| Pagination | ✓ | Truncated + full |
| Process list | ✓ | Numbered vertical step pattern |
| Prose | ✓ | Long-form readable typography |
| Radio buttons | ✓ | Tile variant |
| Range slider | ✓ | Single-value continuous |
| Search | ✓ | Big / medium / small variants |
| Select | ✓ | Native `<select>` styled |
| Side navigation | ✓ | Multi-level, with current state |
| Site alert | ✓ | info / emergency banner across the top |
| Step indicator | ✓ | Counter + sequence variants |
| Summary box | ✓ | "Key information" callout |
| Table | ✓ | Borderless + striped + sortable + scrollable |
| Tag | ✓ | Static labels (not interactive chips) |
| Text input | ✓ | Many states + sizes |
| Time picker | ✓ | 15-min increments by default |
| Tooltip | ✓ | Keyboard-accessible |
| Validation | ✓ | Inline + summary patterns |
| **Carousel** | ✗ | **Removed for a11y reasons.** Borrow from Material 3 or shadcn/ui, keeping USWDS tone |
| **Stepper / wizard** | ✗ (use Step indicator) | Step indicator is presentational, not a multi-step form pattern; borrow from Material 3 if interactive multi-step is needed |
| **Drawer / sheet** | ✗ | Borrow from shadcn/ui or Material 3 (bottom sheet) |
| **Command palette** | ✗ | Borrow from shadcn/ui; usually not needed in civic portals |
| **FAB** | ✗ | Borrow from Material 3; almost never appropriate in USWDS context |
| **Data table (sortable + selectable + filter)** | partial | USWDS Table is presentational; borrow from Fluent 2 for richer enterprise behavior |

## Token theory

USWDS uses a **token-driven system** with three layers: theme tokens (project-customizable), system tokens (fixed semantic names), and primitive tokens (raw values). Reference: https://designsystem.digital.gov/design-tokens/

### Color

USWDS colors are organized by **family + grade** (a numeric darkness scale). Grades 5-90 in steps of 10. Use grade-pair contrast rules: text grade ≥ 50 against background grade ≤ 20 generally clears AA.

Theme color slots (project sets values per-site):
- `primary`, primary brand action color
- `primary-darker`, `primary-darkest`, `primary-lighter`, `primary-lightest`
- `secondary`, destructive / alert
- `accent-cool`, informational accent
- `accent-warm`, emphasis accent
- `base`, neutral grays
- `error`, `warning`, `success`, `info`, `emergency`, status

Built-in palettes: red, orange, gold, yellow, green, mint, cyan, blue, indigo, violet, magenta, gray, gray-cool, gray-warm, each with grades 5-90.

### Type scale

Type families: `theme-font-type-sans` (default Public Sans), `theme-font-type-serif`, `theme-font-type-mono`, `theme-font-type-cond`, `theme-font-type-icon`. **Public Sans** is the USWDS default and is open source (SIL OFL).

Sizes use a **numeric ramp** (`3xs` through `3xl`), not a t-shirt scale. Default body is `2`, headings ramp from `lg` to `3xl`.

### Spacing

Spacing units use a **base unit of 8px** (`1unit = 8px`), with named tokens `1px`, `2px`, `05` (4px), `1` (8px), `105` (12px), `2` (16px), `205` (20px), `3` (24px), …

### Other

- **Radii**: `sm`, `md`, `lg`, `pill`, generally restrained
- **Shadows**: `none`, `1`, `2`, `3`, `4`, `5`, minimal use; favor borders
- **Motion**: deliberate and minimal; respects `prefers-reduced-motion`

## Power Pages implementation bias

- Re-express USWDS as **CSS variables in your portal CSS file**, not by importing the full USWDS build pipeline.
- Keep Bootstrap layout primitives present (Power Pages assumes them) and apply USWDS *visual language* on top.
- Bring in Public Sans via local web-files (avoid CDN where strict CSP applies). See [strict-csp.md](strict-csp.md).
- Use semantic class names like `.usa-button`, `.usa-alert` if the portal benefits from name-recognition; otherwise bridge USWDS token values into the existing portal classes.

## License + foot-guns

- **Bundle is public-domain (CC0)**, safe to vendor and modify.
- **Public Sans is OFL**, bundle the font files locally; CDN links can be CSP-blocked.
- **USWDS Icons are public-domain Material Symbols derivatives**, safe to ship with the portal; do not need attribution.
- **The full build expects Sass + npm**, Power Pages doesn't run a build pipeline at request time. Either pre-build Sass once and ship the compiled CSS, or rewrite the slice you need as plain CSS variables.
- **No carousel exists**, if a stakeholder insists, do not invent a "USWDS carousel"; document the borrow in a code comment and follow [crossover-recipes.md](crossover-recipes.md).
- **USWDS is web-only.** It defines no native-app navigation patterns, no bottom tab bar, no large-title scroll-collapse navigation, no FAB. When a portal needs a **mobile-app feel** (PWA, mobile-first service kiosk, "feels like an app" stakeholder request), USWDS cannot answer alone:
  - **Ask the user**: should the mobile experience feel **iOS-native** or **Android-native**?
  - **iOS-native** → borrow nav from [apple-hig.md](apple-hig.md) (bottom tab bar with translucent treatment, large title scroll-collapse, sheet presentations)
  - **Android-native** → borrow nav from [material-3.md](material-3.md) (M3 navigation bar, navigation drawer, FAB)
  - **Cross-platform / unsure** → default to Material 3 (it's the closest to USWDS's content-first posture and works for both audiences without feeling foreign on either)
  - In all variants, **preserve USWDS color tokens, type, focus states, and content tone**, only the navigation chrome changes. See [crossover-recipes.md](crossover-recipes.md) → "USWDS web with mobile-app feel."

## Component-level guidance

### Hero sections

Allowed, but keep them sober:
- one strong heading
- one concise supporting paragraph
- one primary CTA
- optional secondary CTA
- supportive image only if it aids comprehension

If carousel is requested, see [crossover-recipes.md](crossover-recipes.md) → "USWDS hero with Material carousel."

### Forms

- Explicit labels; helper text below the field, not in placeholder
- Group long forms with `<fieldset>` + `<legend>`
- Required indication uses asterisk **and** "required" text (asterisk alone fails AA)
- Validation summary at top + inline error per field
- USWDS Memorable date for date entry beats native `<input type="date">` for civic accessibility

### Cards

- Keep informational; avoid decorative chrome
- Use the flag layout for record-card patterns (image left, content right)
- Don't put more than one primary action per card

## Responsive bias

- **Mobile**: linear, single-column, task-first; in-page nav at top
- **Tablet**: introduce side summaries; keep two-column max
- **Desktop**: denser summaries, but never at the cost of content clarity
- USWDS's grid is built on a 12-column system with `tablet`, `desktop`, and `widescreen` breakpoints

See [responsive-defaults.md](responsive-defaults.md) for the cross-system responsive baseline.

## Pairing with other systems

- **Material 3**, for carousel, stepper, bottom-sheet behavior; see [material-3.md](material-3.md)
- **shadcn/ui**, for cards, modern filter drawers, dialogs; see [shadcn-ui.md](shadcn-ui.md)
- **Fluent 2**, for denser business tables and enterprise filter behavior; see [fluent-2.md](fluent-2.md)
- **Apple HIG**, generally not needed; USWDS is already calm and clear

When borrowing, always preserve USWDS plain language, contrast, focus states, and restrained tone. See [system-selection.md](system-selection.md) for the full crossover rule.
