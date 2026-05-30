# Roadmap

Sumi Browser is a developer-preview project. This roadmap is a planning snapshot, not a release promise.

## Current Status

- Sumi builds and runs locally as a working native macOS browser shell.
- It is not recommended as a primary browser yet.
- The first public preview is planned after MV3 password-manager compatibility, backup/restore user data, and update mechanism/notification.

## Current Milestone

Chrome MV3 password-manager extension compatibility.

The near-term target is that a user can install an unpacked or zipped password-manager extension and use it from the browser UI. Sumi does not currently claim that Bitwarden, Proton Pass, or 1Password already work.

## Done In Developer Preview

- Working native macOS browser shell.
- Tabs, sidebar, spaces, and profiles.
- Glance.
- Split view up to four views.
- Floating bar.
- Bookmarks and history.
- Sidebar drag-and-drop organization.
- Pinned items, essentials, and folders.
- Custom themes.
- Session restore setting.
- Mini Player jump-to-media / pause / mute.
- Memory modes and inactive tab unloading.
- Optional tracking protection module.
- Optional adblock module.
- Automatic cleanup settings.
- Extension manager UI.
- MV3 compatibility report UI.
- Real password-manager package trials.

## Experimental Or In Validation

- Chrome MV3 scripting API.
- MV3 service-worker lifecycle.
- Native messaging.
- Tracking protection behavior and protection-bundle workflow.
- Adblock behavior and validation.
- Automatic history and site-data cleanup.
- Extension compatibility reporting.

Additional details:
- Automatic cleanup intervals include 1, 7, 30, and 90 days. Cleanup is intended to remove browser leftovers and site data where possible, not only history.
- The Mini Player does not currently include next/previous track controls or a timeline.

## Remaining MV3 Blockers

- Service-worker lifecycle on real extension events.
- MAIN world bridge.
- Multi-frame, `about_blank`, and `match_origin_as_fallback` behavior.
- Native messaging fixture exchange and trusted host configuration.
- Offscreen, webRequest, and DNR product behavior.
- Arbitrary `scripting.executeScript` and `insertCSS`.

## Public Preview Blockers

- MV3 password-manager compatibility.
- File/archive-based backup and restore for user data.
- Update mechanism or update notification.

Backup and restore is a blocker because Sumi's target users may build complex tab, space, profile, pinned item, essential, folder, and theme organization.

## Near-Term

- MV3 password-manager support.
- File/archive-based backup and restore for:
  - tabs
  - spaces
  - profiles
  - bookmarks
  - pinned items and essentials
  - folders
  - themes
  - extension settings
  - tracking/adblock settings
- Update mechanism or update notification.
- Import from Arc and Zen.

## Later

- Nested folders.
- Live folders.
- Site customization/boosts.
- Private or ephemeral profile/incognito mode.
- Fully encrypted sync without data collection.
- Multi-window workflows.
- Improved profile isolation redesign.
- Safari and Chrome import.
