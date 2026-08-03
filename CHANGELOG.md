# Changelog

Sumi follows semantic product versions. This changelog records public release scope, not every internal refactor.

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
