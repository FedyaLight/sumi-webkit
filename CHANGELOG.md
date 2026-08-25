# Changelog

Sumi follows semantic product versions. This changelog records public release scope, not every internal refactor.

## 0.0.7 Alpha, 2026-08-25

### Extensions and Permissions

- Extension content scripts now run on the first page loaded in a newly opened tab instead of requiring a reload.
- Dismissing a site permission prompt settles the request and releases the sidebar. When a page queues another prompt, Sumi presents it after the current decision.

### Browser Interaction

- Command-W closes Settings when Settings is focused instead of closing a browser tab behind it.
- The Command Palette no longer repeats the typed search query as a suggestion. Pressing Return searches the entered text unless another result is selected.
- Certificate trust approval now stays with the tab for its related page resources, while the URL Hub continues to mark the page as not secure.

### Favicons

- Initial favicon selection and later page updates now use the same source ordering. High-quality raster resampling improves diagonal edges, and repeated sidebar reads no longer repeat the same repository lookup.

## 0.0.6 Alpha, 2026-08-24

### Downloads and Webpage Actions

- Gmail attachments served from directory-style URLs now download instead of opening as a page.
- Webpage context menus now route linked-file downloads, image saving, and image copying through working browser commands. Copy Link to Selected Text also produces a correctly encoded text-fragment URL.

### Sidebar, Glance, and Window Interaction

- Selected sidebar items reliably scroll into view with the smallest necessary movement. Items already visible stay in place, and background opens do not steal the viewport.
- Promoting a Glance preview into a tab preserves webpage hover state and the correct pointing-hand cursor.
- Collapsed-sidebar hover no longer leaves stale webpage hover underneath transient browser chrome.
- Dragging from the top of a web page no longer moves the browser window, so page interactions such as text selection work there. Browser windows move from the sidebar control strip instead. Windows that end up fully off-screen after a display change return to a visible screen.
- Terminal WebKit key events no longer produce a system beep after the browser has handled them.

### Adblock and Rendering

- Domain-scoped cosmetic Adblock rules now run only on matching hosts through the advanced pipeline. Existing compiled generations migrate locally; generic and exclusion-based cosmetic rules remain in WebKit for first-paint blocking.
- Favicons prefer appropriately sized sources, avoid uneven fractional raster scaling, and reuse the canonical favicon cache across sidebar surfaces. Favorite backdrop rendering no longer performs its blur work on the main thread.
- Browser-owned loading and certificate-warning surfaces follow the active Space and effective light or dark appearance.

## 0.0.5 Alpha — 2026-08-18

This release moves Sumi to one signed immutable DMG for direct installs and Sparkle updates, replaces prepared blocking bundles with locally built Adblock generations, and makes browser-owned storage cleanup safer and more bounded.

### Adblock

- Selected filter lists now download and compile locally into one atomic native WebKit and advanced-blocking generation. Existing site-specific exceptions remain intact.
- Inactive generations are reclaimed without disturbing the current selection or user site exceptions.

### Browser Storage and Permissions

- Regular-profile HTTP caches have a bounded disk budget, and stale persistent website-data and extension-controller namespaces are reclaimed in bounded batches without touching live profile state.
- Older per-profile regular favicon caches migrate to one shared regular-profile store while private favicon state remains isolated.
- Site permission decisions migrate to regular install-wide scope so a browser-level decision stays consistent across regular profiles.

### Browser Polish

- Settings reliably comes to the front, and certificate warnings route through the active browser surface.
- Sidebar hover actions respond immediately, unloaded regular tabs no longer show an extra indicator dot, Space title chevrons no longer overshoot, and URL Hub popovers use the corrected presentation surface.

### Distribution

- Direct installs and Sparkle updates use the same signed Arm64 DMG. Native Intel Macs are not offered the incompatible update, and historic Intel and Universal assets remain available.

## 0.0.4 Alpha 4 — 2026-08-15

Alpha 4 improves redirect and external-app handoffs, keeps navigation feedback continuous, makes Sidebar Mini Player sessions more predictable, and prevents automatic history retention from signing users out of websites.

### Navigation and External Apps

- Fixed OAuth and other external-app callbacks so an active main-frame redirect can ask for permission and complete even when WebKit no longer reports the original click.
- Limited automatic external-app attempts to one per page while keeping iframe, background, Glance, and other non-normal surfaces blocked.
- Preserved the committed page across redirect settlement and presentation-URL changes so popup and page ownership remain attached to the document actually on screen.
- Recovered the exact current document when WebKit finishes a rewritten navigation without delivering its commit callback, preventing an older page lease from hiding the new page.
- Kept the loading indicator continuous across short redirect and successor-navigation chains instead of briefly disappearing between loads.

### Sidebar Mini Player

- Reworked media-card state around the exact page session in its window, preventing controls from affecting another residence of the same tab.
- Kept cards stable after pausing or muting from the Mini Player, without resuming media when the page is activated.
- Made dismissed cards stay dismissed until a new audible playback session starts, and rolled back failed or stale media commands cleanly.

### Privacy and Reliability

- Changed automatic retention to delete only expired browsing history; website data and sign-ins are preserved. Manual website-data and cache clearing remain available.
- Fixed private-window pages loading in WebKit without being attached to the visible compositor.
- Hardened external-app admission so stored permissions cannot be reused by subframes or auxiliary surfaces, even after a user interaction.

## 0.0.3 Alpha 3 — 2026-08-11

Alpha 3 improves navigation and Glance behavior, media playback, fullscreen reliability, sidebar interactions, Settings, and WebKit page lifecycle management.

### Navigation and Glance

- Added automatic Glance presentation for eligible primary-click navigation from Favorites and pinned tabs.
- Preserved ordinary behavior for downloads, external schemes, extension popups, middle-clicks, modifier-clicks, new windows, and same-frame navigation.
- Fixed navigation inside Glance previews, teardown after closing a preview, and browser link-navigation fallbacks.
- Integrated page-loading presentation with Glance without conflating their runtime ownership.

### Media and Fullscreen

- Reduced energy consumption during fullscreen video playback.
- Fixed native fullscreen titlebar auto-hide and hardened WebKit fullscreen and page-presentation lifecycles.
- Reworked the sidebar mini-player around multiple media-session cards with focus, playback, mute, Picture in Picture, and dismissal controls.
- Fixed media downloads initiated from the WebKit context menu.

### Sidebar, Tabs, Folders, and Favorites

- Renamed Essentials to Favorites and fixed Favorite selection across profiles.
- Added configurable dimming and desaturation for unloaded tabs.
- Fixed tab-close visual handoff hangs and favicon update flicker.
- Improved collapsed-sidebar hover behavior, docked-sidebar collapse animation, and vertical spacing.
- Fixed folder transition snapshots, folder-preview appearance changes, custom folder-icon selection, and cancelled split-picker cleanup.

### Settings, Keyboard, and Extensions

- Expanded Search Engine settings with filtering, editing, removal, restoration, and Tab Search controls.
- Unified native menu and keyboard command routing and moved Keyboard settings search into the toolbar.
- Fixed duplicate extension context-menu items and prevented middle-clicks from opening the command palette.
- Renamed the About Sumi “What's new” destination to Changelog.

### Reliability and Polish

- Hardened page and WebKit runtime lifecycle management.
- Improved the page-loading indicator and long-loading presentation.
- Improved notification secondary-text contrast.

## 0.0.2 Alpha 2 — 2026-08-03

Alpha 2 focuses on native macOS interaction, sidebar reliability, extension workflows, media playback, and session restoration.

### Highlights

- Rebuilt Settings as a dedicated native macOS window.
- Reworked History and Bookmarks with native AppKit tables, editing, and improved import/export workflows.
- Added native Picture in Picture controls to the sidebar media player.
- Added a native certificate warning flow with per-navigation trust decisions.
- Added a dedicated Alpha update channel and improved the About Sumi update interface.

### Extensions

- Improved Safari Web Extension discovery, installation, activation, removal, profile initialization, and cleanup.
- Added Glance support for extension pages.
- Fixed extension pinning, unpinning, reordering, and popup presentation in expanded and collapsed sidebars.
- Fixed installation of extensions that contain popup content without an explicit script type.

### Sidebar and Navigation

- Improved collapsed-sidebar clicking, dragging, cursor handling, and extension actions.
- Reworked automatic scrolling, selected-tab visibility, hover restoration, space transitions, and favicon transitions.
- Fixed pinned external-link routing and Favorites placeholder dismissal.
- Added native tab-title tooltips and refined the sidebar toggle placement.
- Prevented a source-page flash when promoting a Glance preview into a regular tab.

### Browser, Media, and Reliability

- Moved background media and fullscreen behavior back to native WebKit handling.
- Improved Now Playing lifecycle and added Picture in Picture to the mini player.
- Fixed WebKit file-picker activation and an unwanted keyboard-event system beep.
- Fixed command-palette text editing and shortcut handling.
- Improved restored launcher navigation, browser-data import, deferred profile deletion, and extension runtime cleanup.
- Added a post-update sidebar notification and a clearer About Sumi update presentation.

## 0.0.1 — 2026-07-31

The first public release includes:

- Native macOS browsing with tabs, windows, profiles, spaces, saved launchers, folders, Glance, and two-to-four-page split groups.
- Command palette, bookmarks, history, downloads, Reader presentation, session restore, themes, media controls, and memory/energy modes.
- Browser import, Zen export, and Sumi backup/restore.
- Profile partitions, private browsing, permissions, cleanup, Global Privacy Control, and prepared content-blocking bundles.
- Experimental Safari Web Extension workflows verified for Bitwarden, Proton Pass, Raindrop.io, and Userscripts.
- Optional Live Folders and Boosts modules.
- Sparkle update infrastructure and a repository-owned release gate.
- Separate verified DMGs for Apple silicon (`arm64`) and Intel (`x86_64`).

Known release boundaries are maintained in the [roadmap](docs/roadmap.md) and [extension matrix](docs/extensions.md).
