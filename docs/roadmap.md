# Roadmap

`v0.1.0-alpha.1` is Sumi's first public alpha. This document records its boundaries and the direction after release; it is not a promise of dates or blanket compatibility.

## First Alpha Scope

The first alpha includes:

- A native macOS browser shell with tabs, multiple windows, profiles, spaces, pinned items, Essentials, nested folders, Glance, and durable split groups.
- Session and closed-tab restoration, downloads, Reader presentation, command palette, bookmarks, history, themes, keyboard shortcuts, and media controls.
- Memory and Energy Saver behavior with inactive-page unloading.
- Profile-specific website-data partitions and ephemeral private browsing.
- Permission/site-settings UI, Global Privacy Control, prepared tracking-protection/ad-block bundles, and data cleanup.
- Browser import, Zen export, and Sumi backup/restore through Data & Recovery.
- Experimental Safari Web Extension support with maintainer-verified Bitwarden, Proton Pass, Raindrop.io, and Userscripts workflows.
- Optional, off-by-default Live Folders and Boosts modules.
- Sparkle-based alpha update infrastructure using GitHub Releases and a static signed appcast.

The detailed feature and compatibility boundaries are in the [README](../README.md) and [extension matrix](extensions.md).

## Release Gates for `v0.1.0-alpha.1`

- Run the complete release gate suite with the repository-owned Xcode 27 toolchain.
- Repeat the documented manual extension checks on the packaged build.
- Validate first install on a clean macOS user account.
- Publish separate Apple-silicon and Intel DMGs with release notes.
- Prove an update from the published first alpha to a newer controlled alpha artifact.
- Verify and document Apple Passwords/iCloud Keychain behavior in Sumi; do not claim full AutoFill support before the E2E result exists.

## Known Alpha Boundaries

- The Apple-silicon and Intel artifacts are independently compiled and package-verified. Intel hardware behavior still needs a pass on a physical Intel Mac.
- The initial DMGs are distributed outside the Mac App Store and are not yet Developer ID signed or notarized.
- Safari Web Extension compatibility remains extension- and workflow-specific.
- 1Password 8 native-core integration is blocked by a macOS host-entitlement boundary outside Safari.
- Backup v1 is a logical Sumi-model backup, not a copy of passwords, cookies, WebKit data, history, extensions, downloads, or preferences.
- Sumi is not yet recommended as a primary browser.

## After the First Alpha

Priorities will be driven by reproducible alpha feedback rather than speculative feature breadth:

- Crash, data-safety, restoration, and update-path hardening.
- Broader extension compatibility only where public WebKit and macOS APIs permit a generic solution.
- Improved multi-window workflows and profile isolation diagnostics.
- Accessibility and interaction-quality passes for sidebar, drag-and-drop, focus, and native window behavior.
- Developer ID signing, hardened runtime, notarization, and stapling for a wider distribution path.

## Later Exploration

- End-to-end encrypted sync without collecting browsing data.
- Broader migration of browser data that source APIs and encryption currently make non-portable.
- Additional optional browser tools when they can remain zero-cost while disabled.

No built-in AI panel is planned for the first alpha. AI tools can arrive through extensions after the extension runtime is mature enough.
