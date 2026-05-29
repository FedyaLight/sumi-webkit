# Roadmap

Sumi Browser is a developer-preview project. This roadmap is a planning
snapshot, not a release promise.

## Current Milestone

The active milestone is Chrome MV3 password-manager extension compatibility.

The near-term target is that a user can install an unpacked or zipped
password-manager extension and use it from the browser UI.

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
- Mini Player controls for jump-to-media, pause, and mute.
- Memory modes and inactive tab unloading.
- Optional tracking protection module.
- Optional adblock module.
- Automatic cleanup settings.
- Extension manager UI.
- MV3 compatibility report UI.
- Real password-manager package trials.

## Partial

- Chrome MV3 scripting API.
- MV3 service-worker lifecycle.
- Native messaging.
- Adblock product behavior validation.
- Tracking/privacy module validation.

## Remaining MV3 Blockers

- Service-worker lifecycle on real extension events.
- MAIN world bridge.
- Multi-frame, `about_blank`, and `match_origin_as_fallback` behavior.
- Native messaging fixture exchange and trusted host configuration.
- Offscreen, webRequest, and DNR product behavior.
- Arbitrary `scripting.executeScript` and `insertCSS`.

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
