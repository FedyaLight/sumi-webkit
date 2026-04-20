# First native Aura pass

This note describes the first useful integration pass after the baseline
Helium build launches successfully.

## Goal

Reach the first real Aura window inside Helium's native desktop view tree,
without inventing a second runtime or duplicating browser ownership.

This pass assumes the frozen core-shell spec pack is already complete and is
treated as the source of truth for drag, split, glance, menus, restore, and
selection behavior.

## Order

1. Flip the local development build from `Helium.app` to `Aura.app`.
2. Mount Aura chrome ownership in `BrowserView`.
3. Rewrite the left shell in `VerticalTabStripRegionView`.
4. Rewrite the toolbar/address bar path in `ToolbarView` and
   `LocationBarView`.
5. Remap Helium global media runtime into Aura sidebar cards.
6. Bind Aura state loaders and services to live Helium runtime data.

## First visible deliverable

The first visible deliverable is not the whole product. It is a real Helium
window where these surfaces are already Aura-owned:

- branded app bundle and placeholder Aura icon
- sidebar shell host
- address bar shell host
- site-controls hub anchor
- media card host

At that point the app is no longer "plain Helium", even if folders, spaces,
theme, and essentials are still being wired progressively.

## Hard constraints

- Do not fork large Chromium UI classes wholesale.
- Do not create a second sidebar, toolbar, or media runtime beside Helium.
- Keep tabs, profiles, navigation, and media sessions owned by Helium/Chromium.
- Aura may replace visible chrome, but must not duplicate runtime ownership.
