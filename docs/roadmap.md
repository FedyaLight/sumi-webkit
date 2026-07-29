# Roadmap

Sumi Browser is an Alpha project. This roadmap is a planning snapshot, not a release promise.

## Current Status

- Sumi builds and runs locally as a working native macOS browser shell.
- It is not recommended as a primary browser yet.
- Alpha hardening is focused on Safari password-manager compatibility and update-path validation.

## Current Milestone

Safari password-manager extension compatibility.

The near-term target is that a user can install an unpacked or zipped password-manager extension and use it from the browser UI. Sumi does not currently claim that Bitwarden, Proton Pass, or 1Password already work.

## Completed Milestone: Browser Import And Backup/Restore

Sumi now has multi-browser migration and Sumi backup/restore surfaces in Settings > Data & Recovery.

- Arc and Zen imports preserve Sumi's own model: essentials remain profile-scoped launchers, pinned items remain space launchers, regular tabs remain regular tabs, and nested sidebar folder hierarchy is preserved instead of flattened.
- Arc, Chrome/Chromium, Edge, Brave, Firefox, Safari, Zen, Vivaldi, Opera/Opera GX, and Yandex imports include the source data each browser exposes: profiles/workspaces, tabs, bookmarks, history, favicons where available, and cookies when the source encryption permits them to be moved.
- Export for Zen writes a browser2zen v1-compatible `.zenbackup` with workspaces, tabs, folders, bookmarks, history, containers, and cookies.
- Sumi backup/restore uses `.sumibackup` logical JSON archives. Backup v1 includes profiles, spaces and themes, bookmarks, essentials, pinned launchers, folders, and regular tabs. It excludes history, permission decisions, extension metadata and payloads, cookies, passwords, WebKit website data, caches, downloads, preferences, and session settings.
- Restore supports explicit Merge and Replace modes. Replace writes an automatic pre-restore backup and prunes old automatic pre-restore files so the feature does not accumulate unbounded app-support data.

## Done In Alpha

- Working native macOS browser shell.
- Tabs, sidebar, spaces, and profiles.
- Glance.
- Split view up to four views.
- Incognito windows backed by an ephemeral profile and ephemeral tabs.
- Command palette.
- Bookmarks and history.
- Sidebar drag-and-drop organization.
- Pinned items, essentials, nested folders, and folder ungroup/delete actions.
- Custom themes.
- Session restore setting.
- Mini Player jump-to-media / pause / mute.
- Memory modes and inactive tab unloading.
- Automatic cleanup settings.
- Extension manager UI.
- Safari extension compatibility report UI.
- Real password-manager package trials.
- Data & Recovery import/export/backup/restore.
- Sparkle Alpha updates through GitHub Releases and a static HTTPS appcast.

## Experimental Or In Validation

- Safari extension scripting API.
- Safari extension service-worker lifecycle.
- Native messaging.
- Automatic history and site-data cleanup.
- Extension compatibility reporting.

Additional details:
- Automatic cleanup intervals include 1, 7, 30, and 90 days. Cleanup is intended to remove browser leftovers and site data where possible, not only history.
- The Mini Player does not currently include next/previous track controls or a timeline.

## Remaining Safari Extension Blockers

- Service-worker lifecycle on real extension events.
- MAIN world bridge.
- Multi-frame, `about_blank`, and `match_origin_as_fallback` behavior.
- Native messaging fixture exchange and trusted host configuration.
- Offscreen, webRequest, and DNR product behavior.
- Arbitrary `scripting.executeScript` and `insertCSS`.

## Remaining Alpha Hardening

- Safari password-manager compatibility.
- End-to-end published update validation for each Alpha release.

## Near-Term

- Safari password-manager support.
- Alpha release validation and documentation hardening.

## Later

- Live folders.
- Site customization/boosts.
- Fully encrypted sync without data collection.
- Multi-window workflows.
- Improved profile isolation redesign.
- Broader migration of browser-specific data that platform APIs or source encryption do not currently make portable.
