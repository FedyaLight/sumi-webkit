# Performance budgets

Helium is the baseline.

## Acceptance budgets

- idle CPU delta vs Helium: target `<= +1 pp`, fail `> +2 pp`
- idle wakeups/energy delta vs Helium: target `<= +10%`, fail `> +15%`
- idle memory delta vs Helium: target `<= +10%`, fail `> +15%`
- cold startup delta vs Helium: target `<= +10%`
- shell overhead on tab/space switch: within one frame budget

## Runtime constraints

- one lightweight shell surface, not multiple always-live renderers
- no polling loops for sidebar, media, theme, or URL state
- no hidden helper tabs for shell features
- background work must be event-driven
- if Helium already does something efficiently in core runtime, Aura should
  integrate with it instead of mirroring it in shell logic

## Architectural preference

- prefer upstream Helium behavior over custom Aura logic when the upstream path
  is already fast, stable, and correct
- treat custom runtime workarounds as last resort, not default implementation

## Performance review triggers

Changes require explicit performance review when they introduce:

- repeated invalidation or render thrash in visible chrome
- expensive blur, animation, or paint effects in hot paths
- repeated or polling-based runtime queries
- duplicated state owners for tabs, extensions, media, theme, or restore
- new work on every navigation, tab switch, or space switch

If a change is measurably expensive, it must justify that cost and describe the
removal or optimization path.

## Bleed responsibly

- risky experiments belong in cheap shell layers
- critical runtime and persistence layers stay boring and stable
- do not move fragile experiments into data or browser-runtime ownership layers
