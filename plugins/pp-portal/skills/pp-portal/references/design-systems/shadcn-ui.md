# shadcn/ui for Power Pages

`shadcn/ui` is **not a component library you install**, it's a **registry of copy-paste components** built on Radix UI primitives + Tailwind CSS. You own the source. For Power Pages, that ownership model is a strong fit because you can lift just the *anatomy* and *visual language* of a component without dragging in React, Radix, or a build pipeline.

## Canonical sources

| Resource | URL |
|---|---|
| Docs | https://ui.shadcn.com/ |
| Components | https://ui.shadcn.com/docs/components |
| Theming | https://ui.shadcn.com/docs/theming |
| Examples | https://ui.shadcn.com/examples |
| Charts | https://ui.shadcn.com/charts |
| GitHub | https://github.com/shadcn-ui/ui |
| CLI | `npx shadcn@latest` (modern; `shadcn-ui` is the older name) |
| Underlying primitives | Radix UI, https://www.radix-ui.com/ |
| License | MIT (components); Radix is MIT; Lucide icons (default) is ISC; Tailwind is MIT |

## Component catalog

shadcn/ui covers the modern web product surface comprehensively. Components below are in the v2 registry; older `@shadcn-ui/ui` references may differ.

| Component | In shadcn? | Notes |
|---|---|---|
| Accordion | ✓ | Radix Accordion under the hood |
| Alert | ✓ | Default + Destructive variants |
| Alert Dialog | ✓ | Modal blocking confirmation |
| Aspect Ratio | ✓ | CSS aspect-ratio wrapper |
| Avatar | ✓ | With image fallback |
| Badge | ✓ | Default / Secondary / Destructive / Outline |
| Breadcrumb | ✓ | With overflow ellipsis |
| Button | ✓ | Default / Destructive / Outline / Secondary / Ghost / Link, six variants |
| Calendar | ✓ | react-day-picker under the hood |
| Card | ✓ | CardHeader / CardTitle / CardDescription / CardContent / CardFooter sub-components |
| **Carousel** | ✓ | Embla Carousel under the hood; horizontal + vertical |
| Chart | ✓ | Recharts wrapper with shadcn theme tokens |
| Checkbox | ✓ | Radix Checkbox |
| Collapsible | ✓ | Radix Collapsible |
| Combobox | ✓ | Composed from Popover + Command |
| Command | ✓ | Command palette (cmdk under the hood); shadcn-distinctive |
| Context Menu | ✓ | Radix Context Menu; right-click + long-press |
| Data Table | ✓ | TanStack Table integration; sortable / filterable / paginated |
| Date Picker | ✓ | Calendar in a Popover |
| Dialog | ✓ | Radix Dialog |
| Drawer | ✓ | Vaul library; mobile-first sheet |
| Dropdown Menu | ✓ | Radix DropdownMenu |
| Form | ✓ | react-hook-form + zod integration; Field-style composition |
| Hover Card | ✓ | Radix HoverCard |
| Input | ✓ | Plain styled `<input>` |
| Input OTP | ✓ | One-time-password segmented input |
| Label | ✓ | Radix Label for accessibility-correct labeling |
| Menubar | ✓ | Application menu bar (e.g., for editor surfaces) |
| Navigation Menu | ✓ | Radix NavigationMenu; horizontal nav with mega-menu support |
| Pagination | ✓ | First / Prev / Page numbers / Next / Last |
| Popover | ✓ | Radix Popover |
| Progress | ✓ | Linear determinate |
| Radio Group | ✓ | Radix RadioGroup |
| Resizable | ✓ | Resizable panels (CodeMirror-style) |
| Scroll Area | ✓ | Custom scrollbars without breaking native scroll |
| Select | ✓ | Radix Select |
| Separator | ✓ | Horizontal / Vertical |
| Sheet | ✓ | Side / top / bottom slide-in (different semantics from Drawer) |
| Sidebar | ✓ | Composable sidebar layout, added recently |
| Skeleton | ✓ | Loading placeholder |
| Slider | ✓ | Radix Slider |
| Sonner | ✓ | Toast library (replaced the older Toast component) |
| Switch | ✓ | Radix Switch |
| Table | ✓ | Plain styled HTML table (lighter than Data Table) |
| Tabs | ✓ | Radix Tabs |
| Textarea | ✓ | Plain styled textarea |
| Toggle / Toggle Group | ✓ | Radix Toggle |
| Tooltip | ✓ | Radix Tooltip |
| Typography | ✓ | Utility classes for prose hierarchy |

## Token theory

shadcn/ui uses **CSS custom properties + Tailwind** for theming. The token system is intentionally **simpler than Material 3 or Fluent 2**, that's part of the appeal.

### Color tokens (HSL-based)

The default theme defines token pairs in HSL space, with a `<role>` and a `<role>-foreground`:
- `--background` / `--foreground`, page surface and primary text
- `--card` / `--card-foreground`
- `--popover` / `--popover-foreground`
- `--primary` / `--primary-foreground`, primary action
- `--secondary` / `--secondary-foreground`
- `--muted` / `--muted-foreground`, de-emphasized
- `--accent` / `--accent-foreground`, hover states, highlight
- `--destructive` / `--destructive-foreground`, destructive actions
- `--border`, `--input`, `--ring`, structural
- `--chart-1` through `--chart-5`, sequential chart colors

Light + dark mode each defines all tokens. Theme switching is via `class="dark"` on `<html>` (or via `prefers-color-scheme`).

### Typography

shadcn/ui uses **system font stacks by default** (no opinionated typeface ships with the registry). Common stack via Tailwind:
```css
font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont,
             "Segoe UI", Roboto, "Helvetica Neue", Arial, "Noto Sans", sans-serif;
```

Most public examples use **Inter** as the explicit choice. Inter is SIL OFL, safe to bundle.

Type scale comes from Tailwind's defaults: `text-xs` (12), `text-sm` (14), `text-base` (16), `text-lg` (18), `text-xl` (20), `text-2xl` (24), `text-3xl` (30), `text-4xl` (36), `text-5xl` (48), … Line-heights are paired automatically.

### Spacing

Tailwind spacing scale: `0` (0), `1` (4px), `2` (8px), `3` (12px), `4` (16px), `5` (20px), `6` (24px), `8` (32px), `10` (40px), `12` (48px), `16` (64px), `20` (80px), `24` (96px), … (4px base unit).

### Radius

Tailwind `--radius` custom property; default is `0.5rem`. shadcn components use `rounded-md` / `rounded-lg` / `rounded-xl` based on this.

### Motion

shadcn doesn't define a motion language, Radix primitives ship sensible defaults and components use Tailwind's transition utilities.

## Power Pages implementation bias

shadcn/ui is the **most Power-Pages-friendly system in spirit** but the **least direct in mechanism**. The team gives you components by writing files in your repo, that doesn't apply to a classic Power Pages portal that doesn't have a build pipeline. Treat shadcn as a **pattern source**, not an install target.

For a Power Pages portal:
- **Read the shadcn component source** to understand its anatomy (which Radix primitive, which Tailwind classes, which composition pattern)
- **Re-implement the pattern** with semantic HTML, CSS variables (matching shadcn token names), Bootstrap layout primitives, and small custom JS
- **Bundle Lucide or Phosphor icons locally** for the icon language
- **Skip Tailwind** unless the project intentionally added a Tailwind CDN (rare in classic portals); express the same utility decisions as portal CSS classes
- **Skip Radix**, translate the relevant ARIA pattern manually; Radix's job is to make the ARIA pattern easy in React, but the underlying ARIA spec is the actual contract

A typical pattern: study shadcn's `<DropdownMenu>` source to learn that it uses Radix's `DropdownMenu.Root` with a `DropdownMenu.Trigger` button + `DropdownMenu.Content` portaled to the body, with arrow-key navigation. Then implement that same ARIA pattern with `role="menu"` + `role="menuitem"` + keyboard handlers in vanilla JS.

## License + foot-guns

- **Components: MIT**, safe to vendor.
- **Radix UI: MIT**, but don't import it directly into a classic portal (it's React-only). Translate the ARIA pattern instead.
- **Tailwind: MIT**, same caveat: do not introduce Tailwind into a classic Power Pages portal that already has Bootstrap; the cascade conflicts and bundle bloat are real.
- **Lucide: ISC**, no attribution required, but a credit in the footer or a NOTICE file is courteous.
- **Embla Carousel: MIT**, small (3-4 KB), portable to vanilla JS; can be used in classic portals if a real carousel implementation is needed.
- **Don't try to install the shadcn CLI on a classic Power Pages portal**, it expects a Vite/Next.js project with TypeScript, Tailwind config, and a `components.json`. None of that exists in classic portal source.
- **Components in shadcn are versioned per-component**, there's no "shadcn 1.0.0" tag the way Fluent has v9. When referencing, link to the component page on `ui.shadcn.com`, which always shows the current source.
- **Many shadcn examples skew desktop-first**, verify mobile behavior before shipping. Drawer and Sheet are mobile-aware; Sidebar is mobile-aware; many older examples (Form, Data Table) require explicit mobile correction.

## Component-level guidance

### Command palette

shadcn's `<Command>` is one of its most distinctive contributions, a fuzzy-search palette pattern (Cmd+K / Ctrl+K). For Power Pages:
- Almost never appropriate in citizen-facing or civic portals (users don't expect it)
- Strong fit for power-user enterprise/admin portals (procurement, vendor onboarding)
- Implementable in vanilla JS with ~150 lines: keyboard shortcut + modal overlay + filterable list

### Data Table

shadcn's `<DataTable>` is a TanStack Table wrapper. For classic Power Pages, the right move is usually:
- Use shadcn's *visual styling* (header treatment, row hover, pagination strip)
- Implement filtering / sorting / selection in vanilla JS or with the platform's entity-list rendering
- Borrow Fluent 2's enterprise table density if the user expects "Microsoft business" feel; borrow Material 3's row spacing if mobile-first

### Form

shadcn's `<Form>` is built around `react-hook-form` + `zod`. For classic Power Pages, the platform handles validation via entityform/webform metadata; replicating shadcn's form composition manually is rarely worth the effort. **Borrow shadcn's Field visual layout** (label position, error message styling) without the React + zod plumbing.

## Responsive bias

shadcn is the **most variable** system on responsive, it ships sensible patterns (Drawer, Sheet, Sidebar) but many examples are desktop-tuned. Always verify at phone width.

Strong areas:
- Modern card patterns (composable, predictable)
- Filter panel composition (Sheet + Form + Button group)
- Empty / loading / error states (Skeleton + Alert + retry button pattern)

Weak areas to supplement:
- Mobile navigation (no opinionated bottom-nav primitive, borrow from Material 3)
- Touch ergonomics (Tailwind's defaults aren't tuned for 44pt touch by default; check pad/spacing)

See [responsive-defaults.md](responsive-defaults.md) for cross-system responsive rules.

## Pairing with other systems

- **USWDS 3**, use shadcn anatomy for cards/dialogs/filter drawers, keep USWDS tone, contrast, and accessibility seriousness; see [uswds-3.md](uswds-3.md)
- **Fluent 2**, use shadcn to lighten Fluent's enterprise heaviness for customer-facing portions; see [fluent-2.md](fluent-2.md)
- **Material 3**, use shadcn for restrained web surfaces when Material feels too app-like; see [material-3.md](material-3.md)
- **Apple HIG**, strong combination; both lean minimal and prioritize content over chrome; see [apple-hig.md](apple-hig.md)

See [system-selection.md](system-selection.md) for selection logic and [crossover-recipes.md](crossover-recipes.md) for concrete patterns.
