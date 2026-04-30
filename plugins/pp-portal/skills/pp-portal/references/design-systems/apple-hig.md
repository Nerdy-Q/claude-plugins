# Apple Human Interface Guidelines for Power Pages

Apple's Human Interface Guidelines describe a **values-driven** design philosophy rather than a downloadable component library. The guidelines apply across iOS, iPadOS, macOS, watchOS, tvOS, and visionOS, each with platform-specific deviations. For Power Pages, HIG is best used as a **principle source** for premium, calm, content-light, touch-first experiences.

## Canonical sources

| Resource | URL |
|---|---|
| HIG docs | https://developer.apple.com/design/human-interface-guidelines/ |
| Components reference | https://developer.apple.com/design/human-interface-guidelines/components |
| Foundations | https://developer.apple.com/design/human-interface-guidelines/foundations |
| Patterns | https://developer.apple.com/design/human-interface-guidelines/patterns |
| Layout | https://developer.apple.com/design/human-interface-guidelines/layout |
| Apple Design Resources (Sketch / Figma) | https://developer.apple.com/design/resources/ |
| License | Apple license (proprietary; **fonts and icons restricted to Apple platforms**) |

## Component catalog

HIG's components are platform-specific, many have no clean web equivalent. The list below is **iOS/iPadOS-flavored** since that's the closest match to a web portal context. Components marked ⚠ require a web translation, not a literal copy.

### Content presentation

| Component | Web translation |
|---|---|
| Charts | Use accessible chart libraries (Chart.js, Plotly) styled to HIG palette |
| Image views | `<img>` with HIG-style aspect ratio and corner radius |
| Lists and tables | HTML lists; HIG list "rows" become semantic list items with disclosure indicators |
| Lockups | Brand mark + supporting text composition |
| Scroll views | Native page scroll; avoid trapped inner-scroll regions |
| Split views | CSS Grid two-pane on tablet/desktop |
| Tab views ⚠ | Web tabs (ARIA tablist); HIG tab bars are typically bottom-anchored on iOS, adapt for web |
| Web views | Iframes (rare in portals; CSP-sensitive) |

### Menus and actions

| Component | Web translation |
|---|---|
| Action sheets ⚠ | Bottom sheet on mobile, popover on desktop |
| Activity views ⚠ | Web Share API on supported browsers, fallback to button group |
| Buttons | Plain / Tinted / Filled / Bordered / Bordered Prominent, five visual emphasis tiers |
| Context menus | Right-click + long-press; ARIA menu pattern |
| Edit menus ⚠ | Native browser text-selection menus; do not override |
| Menus | Dropdown menu with HIG type/spacing |
| Pop-up buttons | `<select>` styled, or custom combobox |
| Pull-down buttons | Button that opens a menu (action-oriented) |
| Toolbars | Top app bar with primary actions |

### Navigation and search

| Component | Web translation |
|---|---|
| Navigation bars | Top nav with title + back action (mobile) / breadcrumb (desktop) |
| Path controls | Breadcrumb |
| Search fields | Search input with magnifying-glass leading icon |
| Sidebars | Left rail / drawer |
| Tab bars ⚠ | iOS bottom tabs translate to bottom nav on mobile only |

### Presentation

| Component | Web translation |
|---|---|
| Alerts | Modal dialog (urgent only) |
| Page controls ⚠ | Carousel pagination dots |
| Panels (macOS) | Detached modal/dialog |
| Popovers | ARIA popover; positioned next to anchor |
| Sheets | Modal (centered) on desktop, full-height bottom sheet on mobile |
| Windows ⚠ | Native browser windows; do not simulate |

### Selection and input

| Component | Web translation |
|---|---|
| Color wells | `<input type="color">` |
| Combo boxes | Combobox (native or custom with ARIA) |
| Pickers | Date / time / list pickers |
| Segmented controls | Button group (toggle variant) |
| Sliders | `<input type="range">` styled |
| Steppers | Increment / decrement number input |
| Text fields | `<input>` / `<textarea>` styled |
| Toggles | Switch component |

### Status

| Component | Web translation |
|---|---|
| Activity rings ⚠ | Custom SVG; HIG visual is recognizable |
| Gauges | Progress component; semicircular variant |
| Progress indicators | Linear + circular |
| Rating indicators | Star rating |

## Token theory

HIG does not expose CSS tokens directly, it specifies **values for native platforms**. The web translation:

### Color (Dynamic Color)

HIG uses **semantic colors** that adapt automatically across light/dark mode and accessibility settings. Translate to CSS custom properties:
- `label`, `secondaryLabel`, `tertiaryLabel`, `quaternaryLabel`
- `systemBackground`, `secondarySystemBackground`, `tertiarySystemBackground`
- `systemGroupedBackground`, `secondarySystemGroupedBackground`, `tertiarySystemGroupedBackground`
- `separator`, `opaqueSeparator`
- `link`
- System tints: `systemBlue`, `systemGreen`, `systemRed`, etc., **do not use Apple's exact RGB values without a license review**; pick visually equivalent tokens.

Light + dark variants are mandatory; HIG considers dark mode first-class, not a feature.

### Typography (Dynamic Type)

iOS Dynamic Type defines **semantic text styles** that scale with the user's preferred reading size:
- `largeTitle`, `title1`, `title2`, `title3`
- `headline`, `subheadline`
- `body`, `callout`
- `footnote`, `caption1`, `caption2`

Each style has a default point size, weight, and leading. **The user can scale these globally**, your design must accommodate, especially at the largest accessibility sizes.

For web: implement as a CSS custom-property type ramp + scale via `clamp()` or media queries. Don't hardcode pixel values; use `rem` so user font-size preferences scale.

### Spacing

HIG uses an **8-point grid** (same as Material). Common spacing values: 4, 8, 12, 16, 20, 24, 32, 40, 48, 56, 64.

### Corner radius

iOS uses **continuous corners** (squircles) rather than circular arcs. CSS `border-radius` is circular, the visual approximation is acceptable for web. Common radii: 4, 8, 12, 16, 24.

### Touch targets

HIG specifies **44×44 pt minimum** for touch, same as WCAG 2.2 AA target. Apply this strictly on mobile; relax on pointer-only desktop.

## License + foot-guns ⚠ critical

These are the most common HIG-on-web mistakes:

- **San Francisco (SF) font is restricted to Apple software.** Apple's font license (https://developer.apple.com/fonts/) explicitly forbids using SF on non-Apple platforms, including web. **Do not download SF and serve it from a Power Pages portal.** Use **Inter** (SIL OFL) as a near-equivalent, or **system-ui** with a sensible web font stack:
  ```css
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Inter, "Helvetica Neue", Arial, sans-serif;
  ```
  The `-apple-system` keyword renders SF only when the *user's device* is an Apple platform, that's allowed. Hosting SF font files yourself is not.

- **SF Symbols is iOS/macOS only.** The SF Symbols app and library are licensed for use on Apple platforms only. **Do not rasterize SF Symbols and ship them on web.** Use **Lucide** (ISC license, ~1500 icons, similar visual register) or **Phosphor Icons** (MIT) for HIG-aesthetic web icons.

- **Apple Design Resources (Figma kits)** can be downloaded but are not licensed for redistribution as production assets. They're for your internal design work; the resulting visual decisions can be shipped as your own implementation.

- **HIG content itself is copyrighted.** Reference patterns and principles in your guidance docs, but do not paste large blocks of HIG text verbatim into client documentation.

- **Don't simulate native chrome.** Building a fake iOS-style status bar, home indicator, or navigation bar in a web portal is HIG-anti-pattern and creates a confusing dual-context for users.

## Power Pages implementation bias

- Use the system font stack with `-apple-system` first; this gives Apple users the actual SF without licensing issues.
- Bundle Inter or Phosphor/Lucide locally; do not depend on CDNs under strict CSP.
- HIG works best in Power Pages as a **principle layer**: spacing rhythm, calm density, dark-mode parity, and touch ergonomics. The literal components mostly require web translation.
- Dark mode: implement via `prefers-color-scheme` + a class toggle for explicit user choice.

## Responsive bias

HIG is exceptional for:
- Touch ergonomics (44pt minimum, generous spacing)
- Mobile spacing rhythm
- Sheet vs. dialog vs. popover decisions by viewport
- Modal/full-screen task transitions
- Reduced-motion respect (HIG strongly emphasizes this)

On desktop, keep HIG's restraint but add structure so enterprise/civic users can scan quickly. Pure HIG can feel sparse for data-heavy desktop work.

See [responsive-defaults.md](responsive-defaults.md) for cross-system responsive rules.

## Pairing with other systems

- **USWDS 3**, borrow Apple spacing calmness + touch discipline; preserve USWDS plain language and contrast. See [uswds-3.md](uswds-3.md).
- **Fluent 2**, borrow Apple mobile ergonomics; let Fluent handle desktop density. See [fluent-2.md](fluent-2.md).
- **shadcn/ui**, strong combination; both lean minimal. shadcn provides explicit web components, HIG provides values. See [shadcn-ui.md](shadcn-ui.md).
- **Material 3**, **conflicting motion languages**; pick one motion system and let the other contribute spacing/clarity. See [material-3.md](material-3.md).

See [system-selection.md](system-selection.md) for selection logic and [crossover-recipes.md](crossover-recipes.md) for concrete patterns.
