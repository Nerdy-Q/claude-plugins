# Design Systems for Power Pages

Reference layer for working with named design systems inside classic Power Pages portals. Five primary systems are covered, with crossover guidance for the cases where one system needs a pattern from another.

## Layout

| File | What it's for |
|---|---|
| [system-selection.md](system-selection.md) | **Read first.** Primary/secondary selection rules, crossover decision rule, when to ask the user iOS vs Android, recommended pairings per primary |
| [responsive-defaults.md](responsive-defaults.md) | **Always applies.** Mobile-first layout, touch/spacing minimums, navigation/forms/tables/modals/carousels, per-system responsive bias |
| [strict-csp.md](strict-csp.md) | **Always applies.** Power-Pages-specific rule: prefer local JS/CSS, no inline scripts, no runtime injection, no CDN dependencies for component assets |
| [crossover-recipes.md](crossover-recipes.md) | **Concrete combined patterns.** HTML/CSS recipes for the most-asked crossovers (USWDS hero+carousel, USWDS+iOS/Android mobile feel, Fluent enterprise card with shadcn polish, etc.) |
| [uswds-3.md](uswds-3.md) | U.S. Web Design System 3, sources, full component catalog, tokens, license/foot-guns. Web-only. |
| [material-3.md](material-3.md) | Google Material Design 3, sources, catalog (carousel was added in M3), tonal palette, type scale, motion. Mobile-strong. |
| [apple-hig.md](apple-hig.md) | Apple Human Interface Guidelines, values + components reference. **Critical: SF font and SF Symbols are not licensed for web.** |
| [fluent-2.md](fluent-2.md) | Microsoft Fluent 2, sources, React v9 catalog, alias tokens, Segoe fallback. Closest to Power Pages out of the box. |
| [shadcn-ui.md](shadcn-ui.md) | shadcn/ui, registry of copy-paste patterns built on Radix + Tailwind. Treat as a **pattern source**, not an install target. |

## Routing logic

When a user asks about UI / styling / layout:

1. **Is responsive design implied?** Always yes for portal work, apply [responsive-defaults.md](responsive-defaults.md) regardless of system choice.
2. **Is a system named?** Go to that system's file for the catalog, tokens, and foot-guns.
3. **Is the requested pattern in that system?** Check the component catalog. If yes, implement using that system's tokens. If no, follow the crossover rule.
4. **Crossover needed?** Go to [system-selection.md](system-selection.md) for the rule, then [crossover-recipes.md](crossover-recipes.md) for concrete code.
5. **Mobile-app feel needed on a web-only system (USWDS)?** **Ask the user iOS or Android first**, then borrow nav anatomy from Apple HIG or Material 3 accordingly.
6. **Strict CSP applies**, verify with [strict-csp.md](strict-csp.md) before recommending any external script, CDN, or runtime injection.

## What this layer does NOT cover

- **Site shell / theme.css mechanics**, see [`../pages/styling-and-design.md`](../pages/styling-and-design.md)
- **Liquid template patterns**, see [`../language/`](../language/) and [`../pages/hybrid-page-idiom.md`](../pages/hybrid-page-idiom.md)
- **Web API + FetchXML**, see [`../data/webapi-patterns.md`](../data/webapi-patterns.md)
- **Accessibility commitments + gaps**, see [`../quality/accessibility.md`](../quality/accessibility.md). Design-system files note where their accessibility differs from the baseline.

## Update cadence

Each system has a canonical sources table at the top of its file with the official docs URL. The component catalogs and token theory in these files reflect a snapshot, for current spec, link the user to the canonical source. The **principles, foot-guns, and Power Pages implementation bias** sections are stable; the **catalogs** drift slowly and should be refreshed when adopting a new portal.
