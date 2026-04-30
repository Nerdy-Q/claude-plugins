# Power Pages Design-System Selection and Crossover

This reference teaches the model how to work with a **primary design system** and, when needed, borrow a **secondary component pattern** without turning a Power Pages site into a mismatched collage.

## Default operating model

Treat every portal as having one of these states:

1. **Existing house style**, preserve it unless the user explicitly wants a redesign.
2. **Named primary system**, e.g. USWDS 3, Material Design 3, Fluent 2, Apple Human Interface Guidelines, or shadcn/ui-inspired styling.
3. **No explicit system**, default to a restrained, accessible Bootstrap-friendly system that can later be aligned to one of the references below.

Always choose **one primary system**. Borrow from another only when the primary system lacks a pattern the user explicitly needs.

## Hard Power Pages constraints

- Keep **Bootstrap present**. Power Pages internals, entity tags, validation, and some Studio surfaces assume Bootstrap selectors still exist.
- Borrow **interaction patterns and component anatomy**, not a foreign framework's whole CSS stack.
- Prefer **HTML + Bootstrap utility/layout classes + custom CSS variables** over dropping in a second framework.
- Keep Liquid output simple and semantic; let CSS and lightweight JS handle design-system expression.
- Respect the existing theme tokens in `theme.css` and the portal's current contrast requirements.
- Assume **strict CSP** and prefer portal-local JS/CSS over CDN or runtime-injected dependencies. See [strict-csp.md](strict-csp.md).

## Crossover decision rule

When the user asks for a pattern not native to the primary system:

1. Preserve the **primary system's** color, type, spacing, corner-radius, and motion language.
2. Borrow only the **missing component behavior or information architecture** from the secondary system.
3. Re-express the borrowed pattern in the primary system's visual language.
4. Verify accessibility and responsive behavior before shipping.

Example:

- **USWDS 3 primary, carousel needed**:
  - Borrow the **pattern structure** from Material Design 3 or shadcn/ui.
  - Keep USWDS typography, color tokens, button styling, focus ring treatment, and plain-language content tone.
  - Add pause/play controls, keyboard support, visible labels, and reduced-motion behavior.

## Special rule: web-only primary system + mobile-app feel needed

Some design systems are **explicitly web-scoped** and have no native-app navigation patterns. USWDS 3 is the clearest case, it does not define bottom tab bars, Android-style navigation drawers, large-title-collapse navigation, or FAB. When a portal that uses a web-only primary system needs to feel **like a mobile app** (PWA, mobile-first kiosk, "feels like an app" stakeholder request), the borrow must come from a system that does cover that surface.

The model **must ask the user** before assuming:

1. Should the mobile experience feel **iOS-native** (Apple HIG flavor) or **Android-native** (Material 3 flavor)?
2. **Cross-platform / unsure** → default to Material 3 (its content-first posture is closer to USWDS than HIG's premium-calm posture, and it works for both iOS and Android audiences without feeling foreign on either).

After the choice is made, apply the standard crossover rule:

- **iOS variant**: borrow nav anatomy from [apple-hig.md](apple-hig.md) (bottom tab bar, large title with scroll-collapse, sheet presentations, popovers); preserve USWDS color, type, focus, and content tone.
- **Android variant**: borrow nav anatomy from [material-3.md](material-3.md) (M3 navigation bar, navigation drawer, FAB, bottom sheets); preserve USWDS color, type, focus, and content tone.

In both variants, **only the navigation chrome changes**, forms, alerts, tables, content typography, button treatment, focus states, and color all stay USWDS.

This rule generalizes:

- **Fluent 2 primary + mobile-app feel**: same iOS-or-Android question; preserve Fluent tokens, borrow mobile nav anatomy.
- **shadcn/ui primary + mobile-app feel**: shadcn has Drawer + Sheet + Sidebar but no opinionated bottom-tab-bar; same iOS-or-Android borrow.
- **Material 3 primary**: already covers mobile app patterns natively; rarely needs this borrow.
- **Apple HIG primary**: already iOS-flavored; rarely needs this borrow except when an Android variant is also required.

See [crossover-recipes.md](crossover-recipes.md) → "USWDS web with mobile-app feel" for both variants implemented in HTML/CSS.

## What can be borrowed safely

Usually safe to borrow:

- Missing component patterns such as carousel, drawer, stepper, command palette, empty-state card, or richer filter panel
- Content hierarchy ideas
- Interaction states
- Responsiveness patterns
- Motion principles, if reduced-motion fallbacks exist

Usually unsafe to borrow directly:

- Whole CSS frameworks
- Entire foreign token systems pasted in unchanged
- Framework-specific JSX/React abstractions
- Visual signatures that overpower the primary system
- Components that require replacing Bootstrap globally

## Priority order when mixing systems

Keep these from the **primary** system unless the user explicitly says otherwise:

1. Accessibility posture
2. Color palette and contrast behavior
3. Typography scale
4. Spacing rhythm
5. Form-field styling
6. Button styling
7. Navigation conventions

The **secondary** system should contribute:

- component anatomy
- interaction detail
- missing responsive behavior
- advanced states if the primary guidance is thin

## Recommended pairing guidance

### USWDS 3 as primary

- Best for: government, civic, grants, compliance-heavy service portals
- Safe borrow sources:
  - **Material 3** for carousel, stepper, bottom-sheet-like mobile patterns
  - **shadcn/ui** for cards, filter panels, dialogs, empty states
  - **Fluent 2** for dense enterprise table/filter behavior
- Preserve:
  - plain language
  - strong contrast
  - restrained visual tone
  - obvious focus states

### Fluent 2 as primary

- Best for: Microsoft-adjacent enterprise portals, internal/external business workflows
- Safe borrow sources:
  - **Material 3** for mobile navigation and richer assistive patterns
  - **shadcn/ui** for modern card/command/menu patterns
  - **USWDS 3** for stronger form guidance and public-service clarity
- Preserve:
  - productivity-first density
  - predictable enterprise controls
  - Microsoft-like corner/spacing restraint

### Material Design 3 as primary

- Best for: mobile-first self-service portals, modern account/task flows
- Safe borrow sources:
  - **USWDS 3** for form seriousness, public-sector readability, and content clarity
  - **Fluent 2** for dense tables and enterprise filter surfaces
  - **shadcn/ui** for lightweight web card/dialog patterns
- Preserve:
  - clear hierarchy
  - purposeful color roles
  - strong state feedback

### Apple HIG as primary

- Best for: premium, calm, content-light experiences and touch-heavy flows
- Safe borrow sources:
  - **Material 3** for more explicit components when HIG is too abstract
  - **shadcn/ui** for practical web primitives
  - **USWDS 3** for stronger compliance-oriented content structure
- Preserve:
  - clarity and deference
  - spacious layout
  - strong touch ergonomics

### shadcn/ui as primary

- Best for: modern product-style web portals where the team wants composable, open-code patterns
- Safe borrow sources:
  - **USWDS 3** for public-service form and accessibility rigor
  - **Fluent 2** for enterprise grid/filter behavior
  - **Material 3** for motion, stepper, FAB-adjacent, and richer navigation ideas
- Preserve:
  - minimalist component surfaces
  - token-driven customization
  - composable anatomy

## Accessibility gate for mixed systems

Before approving a mixed-system solution, make sure all of these remain true:

- The visual hierarchy still reads like one product, not two
- Focus indicators are consistent across native and borrowed components
- Keyboard interaction is complete
- Motion is optional under `prefers-reduced-motion`
- Touch targets remain at least `44x44` CSS pixels on mobile
- Color contrast still meets the project's bar, usually WCAG 2.2 AA
- Carousel, tabs, dialogs, drawers, and accordions follow established ARIA patterns

## Power Pages-specific implementation bias

In Power Pages, prefer this order:

1. semantic HTML
2. Bootstrap layout/utilities
3. local CSS variables for tokens
4. small custom JS for behavior
5. only then an additional lightweight library, if the user explicitly wants one

If a user asks for a design system but the site is already live, do **not** recommend replacing the portal shell or undoing Studio/theme assumptions. Layer the system in incrementally.
