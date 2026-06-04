# Roadmap

Sumi Browser is a developer-preview project. This roadmap is a planning snapshot, not a release promise.

## Current Status

- Sumi builds and runs locally as a working native macOS browser shell.
- It is not recommended as a primary browser yet.
- The first public preview is planned after MV3 password-manager compatibility and update mechanism/notification.

## Current Milestone

Chrome MV3 password-manager extension compatibility.

The near-term target is that a user can install an unpacked or zipped password-manager extension and use it from the browser UI. Sumi does not currently claim that Bitwarden, Proton Pass, or 1Password already work.

## Completed Milestone: Arc/Zen Import And Backup/Restore

Sumi now has first-class Arc/Zen migration and Sumi backup/restore surfaces in Settings > Data & Recovery.

- Arc and Zen imports preserve Sumi's own model: essentials remain profile-scoped launchers, pinned items remain space launchers, regular tabs remain regular tabs, and nested sidebar folder hierarchy is preserved instead of flattened.
- Browser export writes a browser2zen-compatible JSON shape with `source: "sumi"` plus a Sumi extension block for exact future round-trips.
- Sumi backup/restore uses `.sumibackup` logical JSON archives. Backup v1 excludes history, cookies, passwords, WebKit website data, caches, downloads, and extension payloads.
- Restore supports explicit Merge and Replace modes. Replace writes an automatic pre-restore backup and prunes old automatic pre-restore files so the feature does not accumulate unbounded app-support data.
- Chrome, Safari, and Firefox are supported through the existing bookmarks importer; deeper browser organization import requires Arc/Zen data or a portable browser2zen/Sumi transfer file.

## Done In Developer Preview

- Working native macOS browser shell.
- Tabs, sidebar, spaces, and profiles.
- Glance.
- Split view up to four views.
- Incognito windows backed by an ephemeral profile and ephemeral tabs.
- Floating bar.
- Bookmarks and history.
- Sidebar drag-and-drop organization.
- Pinned items, essentials, nested folders, and folder ungroup/delete actions.
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
- Data & Recovery import/export/backup/restore.

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
- Update mechanism or update notification.

## Near-Term

- MV3 password-manager support.
- Update mechanism or update notification.

## Later

- Live folders.
- Site customization/boosts.
- Fully encrypted sync without data collection.
- Multi-window workflows.
- Improved profile isolation redesign.
- Deeper direct Safari and Chrome import beyond bookmarks and portable transfer files.
