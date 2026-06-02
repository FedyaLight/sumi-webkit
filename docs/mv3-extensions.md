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

## Product Normal-Tab Readiness Slice

The first product-normal-tab slice is readiness-only and default-off. It does
not enable general extension support in product tabs.

The local experimental readiness policy requires:

- Explicit local experimental MV3 product gate.
- Extension module, extension, profile, tab, document, permission, and runtime
  route preflight.
- Normal tab surface only.
- Host permission or `activeTab`.
- Reviewed generated-bundle file planning only.
- Isolated world only.
- Top frame only.
- No `file://`, `about:blank`, `match_about_blank`, or
  `match_origin_as_fallback`.
- No auxiliary, favicon, helper, mini, peek, glance, download, popup, or
  options WebView surface.
- Teardown on navigation, tab close, extension disable, module disable, profile
  close, permission revoke, reset/uninstall, and smoke completion.

The manager can show readiness, gate state, blockers, reviewed-file status,
permission/activeTab status, auxiliary-surface exclusion, object lifetime, and
manual smoke prerequisites. Viewing that readout must not attach a normal tab,
register scripts, wake a service worker, launch native hosts, or create a
permanent background runtime.

Manual smoke readiness, when all gates pass, is limited to a synthetic HTTPS
login fixture on a non-credential test origin. It may only execute the reviewed
generated-bundle file in an isolated top-frame world and must verify teardown
immediately afterward.

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

Prepared generated bundles preserve every safe regular file below the staged
extension root, while writing `manifest.json` separately from the validated
canonical snapshot. This is safer and more compatible than inferring a copy
allowlist from manifest entries: extension-owned popup, options, and side-panel
pages can load package-local CSS, JavaScript, fonts, images, and localization
catalogs without declaring those files as web-accessible resources. Intake
rejects unsafe paths, root escapes, symbolic links, non-regular files, and
nested Safari `.app` or `.appex` packages. Sumi-generated metadata and runtime
template namespaces are reserved and cannot be pre-seeded by a source package.
Preserving a local file does not expand its exposure to web origins because the
source manifest is unchanged, and no package scripts execute during intake.

## Compatibility Reporting

The extension UI should report supported, partial, deferred, and unsupported
APIs clearly. Unsupported APIs should be visible to developers before they
mistake a missing feature for a silent runtime failure.
