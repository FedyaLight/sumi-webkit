# Aura Native Chrome

Aura's primary interface lives here.

This layer owns the rewritten Helium browser chrome:

- sidebar
- address bar
- site controls
- theme editor surface
- media cards
- shell menus

Implementation must build directly on Helium's existing Chromium Views/macOS
bridge surfaces such as `BrowserView`, `VerticalTabStripRegionView`,
`ToolbarView`, `LocationBarView`, and global media controls.

This layer must never introduce a second browser runtime or a parallel
always-live shell beside Helium.
