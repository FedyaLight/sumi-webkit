# Browser Chrome Pipeline

## Goal

Keep address bar and site chrome predictable by giving each responsibility one owner.

## Owners

- `URLBarView.swift`
Canonical address bar surface for both sidebar and top-bar presentations.
- `SiteControlsSnapshot`
Value snapshot for current-site chrome state. It should stay URL-derived and not depend on tab internals beyond the current URL.

## Rules

- There is one canonical URL bar implementation.
- Trailing actions are ordered as:
  1. page actions such as copy link
  2. site controls
- Browser-owned site security rows belong to the hub, not to random extra chrome buttons.

## Anti-patterns to avoid

- Re-introducing a second URL bar implementation in `TopBarView`.
- Storing site chrome state directly on `Tab` when a URL-derived snapshot is sufficient.