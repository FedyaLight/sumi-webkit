Type: grilling
Status: resolved
Blocked by: 03

# How should Page Media Sessions be owned across windows and WebView residences?

## Question

When one Durable Page Identity has zero, one, or multiple WebView Residences across windows, which exact identity owns each Page Media Session and which window may present and command its card? Decide behavior for the source tab selected in its own or another window, duplicate residences, split groups, window closure, tab movement, suspension, private windows, and residence replacement without falling back to a global current tab or callback arrival order.

## Comments

- Current Sumi uses a global controller with window-qualified owner state; the replacement must not merge distinct residence generations.
- Incognito is currently excluded and remains an explicit decision rather than an accidental filter.

## Answer

Each card is owned by one exact `(window, tab, WebView session generation, WebView object identity)`. Candidate discovery preserves separate window residences, drops pairs without a live window-owned WebView, and samples each remaining WebView independently. Only the residence whose page snapshot reports playing becomes a card; a selected source residence is hidden only in its own window. Incognito and ephemeral tabs remain excluded.

Every async result and command re-resolves the same tab object, window object, session generation, and WebView identity. Replacement, movement, unload, or window teardown therefore invalidates the old retained/dismissed owner instead of transferring state to a new document or residence.
