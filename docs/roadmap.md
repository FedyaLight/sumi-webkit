# Roadmap

`v0.0.1` is Sumi's first public release. This document records its boundaries and likely next areas of work; it is not a promise of dates or blanket compatibility.

## 0.0.1 Scope

- Native macOS browsing with tabs, windows, profiles, spaces, pinned items, Essentials, nested folders, Glance, and durable split groups.
- Session and closed-tab restoration, downloads, Reader presentation, command palette, bookmarks, history, themes, keyboard shortcuts, and media controls.
- Memory and Energy Saver behavior with inactive-page unloading.
- Profile-specific website-data partitions and ephemeral private browsing.
- Permission and site-settings UI, Global Privacy Control, prepared content-blocking bundles, and data cleanup.
- Browser import, Zen export, and Sumi backup/restore through Data & Recovery.
- Experimental Safari Web Extension workflows verified for Bitwarden, Proton Pass, Raindrop.io, and Userscripts.
- Optional, off-by-default Live Folders and Boosts.
- Sparkle update infrastructure using GitHub Releases and a static signed appcast.

## Current Boundaries

- Apple-silicon and Intel artifacts are independently compiled and package-verified. Intel hardware behavior still needs a pass on a physical Intel Mac.
- The DMGs are distributed outside the Mac App Store and are not yet Developer ID signed or notarized.
- Safari Web Extension compatibility remains extension- and workflow-specific.
- 1Password 8 native-core integration is blocked by a macOS host-entitlement boundary outside Safari.
- Apple Passwords/iCloud Keychain has no Sumi-specific integration, and system AutoFill has not completed release E2E validation.
- Backup v1 is a logical Sumi-model backup, not a copy of passwords, cookies, WebKit data, history, extensions, downloads, or preferences.
- Sumi is not yet recommended as a primary browser.

## Next Priorities

- Crash, data-safety, restoration, and update-path hardening.
- A physical Intel Mac verification pass.
- Developer ID signing, hardened runtime, notarization, and stapling.
- Broader extension compatibility where public WebKit and macOS APIs permit a generic solution.
- Accessibility and interaction-quality passes for sidebar, drag-and-drop, focus, and native window behavior.
- End-to-end encrypted sync without collecting browsing data.

No built-in AI panel is currently planned. AI tools can arrive through extensions after the extension runtime is mature enough.
