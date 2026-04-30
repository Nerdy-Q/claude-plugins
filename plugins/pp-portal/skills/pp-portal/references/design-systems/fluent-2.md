# Fluent 2 for Power Pages

Microsoft's Fluent design system, second major version. The natural primary system for Power Pages portals because Power Pages itself is a Microsoft product, Fluent 2 gives the portal **visual affinity with Microsoft 365, Teams, and the broader Microsoft business ecosystem**. Strongest fit for enterprise self-service, partner/vendor portals, internal-facing workflows exposed externally, and dense data/filter-heavy experiences.

## Canonical sources

| Resource | URL |
|---|---|
| Design system docs | https://fluent2.microsoft.design/ |
| Web component library docs | https://react.fluentui.dev/ |
| Tokens reference | https://react.fluentui.dev/?path=/docs/theme-colors--docs |
| GitHub | https://github.com/microsoft/fluentui |
| npm packages | `@fluentui/react-components` (v9, current), `@fluentui/web-components` (Web Components variant) |
| Fluent UI System Icons | https://github.com/microsoft/fluentui-system-icons |
| Figma kit | https://aka.ms/fluent2figma |
| License | MIT (code), specific font/icon licenses below |

## Component catalog

Fluent 2 React v9 ships ~50 components. The Power Pages relevance varies, many Fluent components assume an SPA shell, but their **visual language and token system** are highly portable.

| Component | In Fluent 2? | Power Pages note |
|---|---|---|
| Accordion | ✓ | One- or multi-open variant |
| Avatar / AvatarGroup | ✓ | Initials, image, or icon |
| Badge | ✓ | Numeric / dot / icon variants; counter color tokens |
| Breadcrumb | ✓ | With overflow menu |
| Button | ✓ | Primary / Secondary / Outline / Subtle / Transparent, five emphasis tiers (similar to Material 3 in count) |
| Card | ✓ | Filled / FilledAlternative / Outline / Subtle |
| Carousel | ✓ | **Added in recent Fluent 2 (v9)**, was not in v8 |
| Checkbox | ✓ | With error state |
| Combobox | ✓ | Free-form + listbox |
| Dialog | ✓ | Modal + non-modal |
| Divider | ✓ | Horizontal + vertical, with text label option |
| Drawer | ✓ | Inline + overlay; left / right / top / bottom |
| Dropdown | ✓ | Native-feeling but custom rendering |
| Field | ✓ | Composable wrapper for label + control + validation message |
| InfoButton / InfoLabel | ✓ | Inline help affordance, Fluent-distinctive |
| Input | ✓ | Outline / Filled / FilledLighter |
| Label | ✓ | Required asterisk + weight variants |
| Link | ✓ | Subtle + Default; visited treatment |
| Menu / MenuList | ✓ | Cascading + checkable items |
| MessageBar | ✓ | Info / Warning / Error / Success / Severe |
| Persona | ✓ | Avatar + name + secondary text, Microsoft-iconic |
| Popover | ✓ | With arrow; positioned |
| ProgressBar | ✓ | Determinate + indeterminate |
| Radio | ✓ | With error state |
| RatingDisplay / Rating | ✓ | Star rating |
| SearchBox | ✓ | With clear button |
| Select | ✓ | Native `<select>` styled |
| Skeleton | ✓ | Loading placeholder shapes |
| Slider | ✓ | Continuous + discrete |
| SpinButton | ✓ | Increment / decrement number input |
| Spinner | ✓ | Circular indeterminate |
| Switch | ✓ | With label position options |
| Tab / TabList | ✓ | Subtle + transparent appearance |
| Table | ✓ | Sortable, selectable, with selection cells |
| Tag / TagPicker / InteractionTag | ✓ | Static + interactive variants |
| Textarea | ✓ | Outline / Filled |
| Toast | ✓ | With actions |
| Toolbar | ✓ | With overflow menu |
| Tooltip | ✓ | Plain + with anchor positioning |
| Tree | ✓ | Expandable hierarchy |
| Virtualizer | ✓ | Large-list rendering helper |

Notable holes:
- **No native data-grid component**, Table is the closest; for richer enterprise grid (column resize, filter row, group-by), look at react-data-grid + Fluent token theming, or borrow grid pattern from shadcn/ui's data-table
- **No carousel before v9.x**, older Fluent code may need refactoring
- **No native stepper/wizard**, use Tabs with controlled state, or borrow from Material 3

## Token theory

Fluent 2 has the most **enterprise-realistic** token system among the five, built around themes (Web Light, Web Dark, Teams Light, Teams Dark, Teams High Contrast) with semantic role tokens.

### Color tokens

Token naming: `colorNeutral*`, `colorBrand*`, `colorPalette*Background*`, etc. Examples:
- `colorNeutralBackground1`, `colorNeutralBackground2`, `colorNeutralBackground3`, increasing emphasis
- `colorNeutralForeground1`, `colorNeutralForeground2`, `colorNeutralForeground3`, decreasing emphasis
- `colorNeutralStroke1`, `colorNeutralStroke2`, `colorNeutralStrokeAccessible`, subtle to AA-compliant
- `colorBrandBackground`, `colorBrandForeground1`, `colorBrandForeground2`
- `colorPaletteRedBackground1` … `colorPaletteRedForeground1` (same for green / yellow / blue / purple / etc.)

CSS custom-property convention: `--colorNeutralBackground1`, etc.

The system uses **alias tokens** layered over **global tokens**, alias tokens have semantic meaning ("colorBrandBackground"), global tokens have raw values ("#0F6CBD"). Always use alias tokens; only override globals during theme creation.

### Typography

Default font is **Segoe UI Variable** on Windows (system); Web fallback uses **Segoe UI** if licensed or a generic web stack. Token names use a domain-prefixed pattern:
- `fontSizeBase200`, `fontSizeBase300`, `fontSizeBase400`, `fontSizeBase500`, `fontSizeBase600`
- `fontSizeHero700`, `fontSizeHero800`, `fontSizeHero900`, `fontSizeHero1000`
- `fontWeightRegular` (400), `fontWeightMedium` (500), `fontWeightSemibold` (600), `fontWeightBold` (700)
- `lineHeightBase*`, `lineHeightHero*` matching the size tokens

### Spacing

Fluent uses an **8-point grid** with horizontal/vertical naming:
- `spacingHorizontalNone` (0), `spacingHorizontalXXS` (2), `spacingHorizontalXS` (4), `spacingHorizontalS` (8), `spacingHorizontalM` (12), `spacingHorizontalL` (16), `spacingHorizontalXL` (20), `spacingHorizontalXXL` (24), `spacingHorizontalXXXL` (32)
- Same scale for `spacingVertical*`

### Border radius

`borderRadiusNone` (0), `borderRadiusSmall` (2), `borderRadiusMedium` (4), `borderRadiusLarge` (6), `borderRadiusXLarge` (8), `borderRadiusCircular` (50%)

Notice Fluent's radii are **smaller than Material 3's**, that's a deliberate enterprise restraint signal.

### Shadows

Eight elevation tokens: `shadow2`, `shadow4`, `shadow8`, `shadow16`, `shadow28`, `shadow64`, plus brand-shadow variants for selected/active states.

### Motion

Duration tokens: `durationUltraFast` (50ms), `durationFaster` (100ms), `durationFast` (150ms), `durationNormal` (200ms), `durationGentle` (250ms), `durationSlow` (300ms), `durationSlower` (400ms), `durationUltraSlow` (500ms). Curves: `curveAccelerateMid`, `curveDecelerateMid`, `curveEasyEaseMax`, etc.

## Power Pages implementation bias

- Fluent 2 is **the closest fit to Power Pages out of the box**, Power Pages Studio, the maker portal, and the platform admin center all use Fluent 2 visually. A Fluent 2 portal feels native to Microsoft customers.
- **Do not pull in `@fluentui/react-components`**, it's an SPA-oriented React component library that conflicts with Power Pages' server-rendered Liquid + Bootstrap + jQuery foundation. Re-implement the components you need with HTML + Fluent tokens.
- Power Pages already includes Bootstrap; layer Fluent **tokens** on top, keeping Bootstrap layout primitives.
- Web Components variant (`@fluentui/web-components`) is more amenable to non-React contexts but still adds bundle weight; preferred only for greenfield SPA-style code sites, not classic portals.
- For typography: use the system font stack with Segoe UI first, since most users are on Windows already:
  ```css
  font-family: "Segoe UI Variable", "Segoe UI", -apple-system, BlinkMacSystemFont, system-ui, Roboto, sans-serif;
  ```

## License + foot-guns

- **Code: MIT**, safe commercial use.
- **Segoe UI is licensed for Microsoft Windows**, do not host the Segoe UI font files yourself for non-Windows users. Use the system font stack pattern above; non-Windows users get a graceful fallback.
- **Fluent UI System Icons: MIT**, bundle them locally; they have ~3000 icons in 20px and 24px sizes, regular and filled variants.
- **Don't confuse Fluent v8 (Office UI Fabric era) with Fluent 2 v9.** v8 used `@fluentui/react`; v9 uses `@fluentui/react-components`. Token names changed substantially, `theme.palette.themePrimary` (v8) is roughly `colorBrandBackground` (v9), but mapping is not 1:1.
- **Don't skin Power Pages Studio chrome.** The maker portal already uses Fluent; users moving between Studio and the rendered portal benefit from visual consistency, not from a custom-rebranded Fluent variant that looks "almost like" Studio but subtly different.

## Component-level guidance

### Persona

Fluent's signature component, avatar + name + secondary line. Use for any "user identity" surface (record owners, comment authors, contact cards). Prefer `Persona` over a generic avatar+text combination because the spacing/alignment is tuned.

### MessageBar (alerts)

Five severities: Info / Warning / Error / Success / Severe. Severe is Fluent's "this needs immediate attention" tier, distinct from Error (which means "the operation failed"). Use Severe sparingly.

### Field (form composition)

Field wraps a control with label + required marker + hint + validation message in a single tuned vertical rhythm. Always use Field instead of a hand-composed `<label>` + `<input>` + `<span class="error">` block, the spacing is non-trivial.

### Tables

Fluent Table is presentational; for sortable + filterable + selectable enterprise grids, the v9 Table primitive composes with `useTableFeatures` hooks (React-only). On a classic Power Pages portal, use the visual tokens of Fluent Table but build the interactivity in vanilla JS or borrow from shadcn/ui's data-table anatomy.

## Responsive bias

Fluent 2 is **strongest on desktop and tablet**, weakest on mobile out of the box. On mobile:
- Collapse complex command bars into overflow menus
- Simplify filter panels into a Drawer
- Reduce visible columns; promote the rest into a "details" view per row
- Convert dense forms into stacked Field stacks
- Replace tabs with accordions if labels wrap

For a Fluent-primary portal that needs strong mobile, pair with **Material 3** for mobile navigation and bottom-sheet behavior (Fluent has Drawer but lacks Material's mobile-nav language).

See [responsive-defaults.md](responsive-defaults.md) for cross-system responsive rules.

## Pairing with other systems

- **Material 3**, for mobile nav, stepper, richer responsive transitions; see [material-3.md](material-3.md)
- **USWDS 3**, for public-service clarity and form seriousness when the audience includes citizens; see [uswds-3.md](uswds-3.md)
- **shadcn/ui**, for simplified card/dialog patterns in lighter-weight portals; see [shadcn-ui.md](shadcn-ui.md)
- **Apple HIG**, for touch ergonomics and calmer spacing on mobile; see [apple-hig.md](apple-hig.md)

See [system-selection.md](system-selection.md) for selection logic and [crossover-recipes.md](crossover-recipes.md) for concrete patterns.
