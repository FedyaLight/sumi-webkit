# Architecture

Sumi Browser is a native macOS app built around system WebKit, SwiftUI, and
AppKit where platform integration requires it. The repository name emphasizes
the WebKit direction, but the public product name is Sumi Browser.

The current target is macOS 15.7+.

## Browser Shell

The main browser shell is organized around:

- Tabs for ordinary page navigation.
- Spaces for separating groups of tabs within a profile.
- Profiles for separating larger browsing contexts.
- Sidebar-first organization for tabs, spaces, pinned items, essentials, and
  folders.
- Glance for opening a page over the current tab without taking layout space.
- Split view for viewing up to four pages together.
- Floating bar for search, address entry, suggestions, site search, history,
  bookmarks, and split-aware actions.

Glance can close quickly, expand into a normal tab, or move into split view.
Pinned and essential items can also open through Glance-style launcher flows.

Essentials are global across spaces that belong to the same profile. Pinned
items live in one space and look like normal tabs. Essentials appear as tiles.

## Launcher Semantics

Sumi separates visible organization from live page runtime where possible.
Pinned and essential items can preserve their visible identity while the live
WebView/runtime instance is unloaded to free memory. This is a design and
implementation behavior, not a benchmark claim.

## Performance Principles

Sumi is performance-first in the sense that browser features should have clear
lifecycle ownership and should avoid hidden work.

Current principles:

- Use system WebKit for page rendering.
- Prefer native SwiftUI/AppKit browser chrome over heavy web UI.
- Keep optional modules lazy.
- Disabled modules should not create background runtime work.
- Avoid background services and timers unless they are necessary.
- Preserve visible tab, pinned, essential, and folder organization when
  inactive live page runtimes are unloaded.
- Keep extension service-worker behavior aligned with Safari's event-driven model.

Memory modes exist in the UI, and inactive tab unloading exists. The goal is to
preserve user organization while reducing unnecessary live runtime state.

## Optional Modules

Extensions, userscripts, and privacy cleanup are feature areas that should
remain optional. When disabled, they should avoid background runtime cost.

## Extensions

Safari extension support is built around `WKWebExtensions`. The active milestone
is real-world password-manager extension compatibility.

Normal browsing views are the default extension participation surface. Helper
surfaces such as favicon downloads, previews, and mini windows should not
participate unless a future design explicitly opts them in.

## AI Policy

Sumi does not include a built-in AI panel. AI tools can be added later through
extensions once extension compatibility matures, for example through official
Safari extensions.
