# Chrome MV3 Extensions

Chrome Manifest V3 support is the current active engineering milestone for
Sumi Browser.

Sumi chose Chrome MV3 because it is the modern extension architecture and
better matches the project's performance and energy direction than older
background-page models. Safari extensions are not currently a product target.
A Safari-extension test path existed earlier in the project, but the current
direction is Chrome MV3 compatibility.

## Architecture Direction

Sumi's MV3 support is built around `WKWebExtensions` plus a compatibility layer
where needed.

The extension subsystem should remain optional:

- Disabled extensions should not create a `WKWebExtensionController`.
- Disabled extensions should not load extension contexts.
- Disabled extensions should not inject extension JavaScript.
- Disabled extensions should not wake service workers.
- Disabled extensions should not start native messaging.

## Installation

Current developer-preview installation paths:

- Unpacked extension directory.
- Zip archive.

Future goal:

- Chrome Web Store installation support.

## Current Status

Done and working in the local experimental/developer-preview contour:

- Extension manager UI.
- Runtime messaging.
- `runtime.sendMessage`.
- `runtime.connect` and ports.
- `tabs.query`.
- `tabs.sendMessage`.
- Permissions and `activeTab`.
- `storage.local`.
- `contextMenus`.
- `alarms`.
- `webNavigation`.
- DNR/webRequest design.
- Compatibility report UI.
- Real password-manager package trials.

Partial:

- Scripting API.
- Service-worker lifecycle.
- Native messaging.

Main remaining blockers:

- Service-worker lifecycle on real extension events.
- MAIN world bridge.
- Multi-frame, `about_blank`, and `match_origin_as_fallback` behavior.
- Native messaging fixture exchange and trusted host configuration.
- Offscreen, webRequest, and DNR product behavior.
- Arbitrary `scripting.executeScript` and `insertCSS`.

## Password-Manager Validation

The near-term target is real-world password-manager extension compatibility.
Validation targets include Bitwarden, Proton Pass, and 1Password-style MV3
packages, but Sumi does not currently claim that those extensions work.

The user-facing goal is that a user can install an unpacked or zipped
password-manager extension, unlock it from the browser UI, and use it on normal
tabs without enabling extension runtime behavior in helper web views.

## Compatibility Reporting

The extension UI should report supported, partial, deferred, and unsupported
APIs clearly. Unsupported APIs should be visible to developers before they
mistake a missing feature for a silent runtime failure.
