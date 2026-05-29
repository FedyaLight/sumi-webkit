# Status

Sumi Browser is in developer preview. It builds and runs locally as a working
browser shell, but it is not recommended as a primary browser yet.

## Working Today

Current developer-preview builds include:

- Native macOS browser shell using WebKit and SwiftUI.
- Tabs, sidebar, profiles, and spaces.
- Glance over the current tab, with quick close, expand-to-tab, and move-to-split
  behavior.
- Split view with up to four views.
- Floating bar with search/address input, suggestions, site search, history and
  bookmark suggestions, compact/top links behavior, and split-aware actions.
- Bookmarks and history.
- Search inside bookmarks, history, and settings.
- Custom themes.
- Drag-and-drop organization in the sidebar.
- Folders for organizing pinned items.
- Essentials and pinned items.
- Session restore setting for either previous-session restore or clean start.
- Mini Player at the bottom of the sidebar for jumping to playing media,
  pausing media, and muting media.
- Memory modes and inactive tab unloading.
- Optional tracking protection, adblock, and automatic cleanup modules.

## Experimental Or In Validation

- Chrome MV3 extension compatibility.
- Real-world password-manager extension compatibility.
- Tracking protection behavior and protection-bundle workflow.
- Adblock behavior and validation.
- Automatic history and site-data cleanup.
- Extension compatibility reporting.

Automatic cleanup intervals include 1, 7, 30, and 90 days. Cleanup is intended
to remove browser leftovers and site data where possible, not only history.

The Mini Player does not currently include next/previous track controls or a
timeline.

## Public Preview Blockers

The first public preview is planned after:

- MV3 password-manager compatibility.
- Backup and restore for user data.
- Update mechanism or update notification.

Backup and restore is a blocker because Sumi's target users may build complex
tab, space, profile, pinned item, essential, folder, and theme organization.
