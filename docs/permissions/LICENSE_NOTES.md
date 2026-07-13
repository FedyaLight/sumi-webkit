# Permission Implementation License Notes

## Summary

Sumi is GPL-3.0. The DuckDuckGo Apple browser reference checkout under `../references/apple-browsers` is Apache 2.0. Apache 2.0 is GPL-3.0 compatible, but copied or closely adapted DDG source must retain the required Apache notice and be tracked here with source and destination paths.

The final DDG reference audit conservatively classified only one file as copied or closely adapted/API-derived: the private geolocation ABI header. That header carries the Apache 2.0 notice in Sumi source. All other DDG-inspected permission areas were used as design/API reference only. No DuckDuckGo SwiftUI/AppKit view source, implementation source, tests, strings, icons, fonts, media, or other assets were copied or closely adapted.

Manual permission pages use Sumi-owned HTML/CSS/JavaScript and do not include third-party snippets or external assets.

## Final DDG Reference Audit Matrix

| Area | DDG files inspected | Copied or adapted? | Source/destination and notices |
| --- | --- | --- | --- |
| Geolocation | `macOS/DuckDuckGo/Geolocation/*`; `macOS/DuckDuckGo/Tab/Model/Tab+UIDelegate.swift`; `macOS/LocalPackages/CommonObjCExtensions/Sources/CommonObjCExtensions/include/WKGeolocationProvider.h`; WebKit C geolocation manager symbols referenced from that header | Yes, for ABI surface only. Sumi implementation code is Sumi-owned. | Closely adapted/API-derived source: `../references/apple-browsers/macOS/LocalPackages/CommonObjCExtensions/Sources/CommonObjCExtensions/include/WKGeolocationProvider.h`. Destination: `Sumi/Supporting Files/SumiWebKitGeolocationProviderABI.h`. The destination header preserves the Apache License, Version 2.0 notice and identifies the DDG source. |
| Notifications | `macOS/DuckDuckGo/Tab/UserScripts/WebNotificationsHandler.swift`; `macOS/DuckDuckGo/Tab/TabExtensions/WebNotificationsTabExtension.swift`; `macOS/DuckDuckGo/UserNotifications/UserNotificationAuthorizationService.swift`; `macOS/DuckDuckGo/UserNotifications/WebNotificationClickHandler.swift`; `macOS/DuckDuckGo/UserNotifications/NotificationIconFetcher.swift`; `macOS/DuckDuckGo/Permissions/Model/*`; related DDG notification tests | No. Design-reference-only. | No DDG notification implementation source copied. Sumi's website notification bridge and delivery service are Sumi-owned. |
| Popups | `macOS/DuckDuckGo/Tab/TabExtensions/PopupHandlingTabExtension.swift`; `macOS/DuckDuckGo/Tab/Model/Tab+UIDelegate.swift`; `macOS/DuckDuckGo/Permissions/Model/*`; `macOS/DuckDuckGo/Permissions/View/PopupBlockedPopover.swift`; `SharedPackages/BrowserServicesKit/Sources/Navigation/*`; popup/window-open tests | No. Design-reference-only. | No DDG popup implementation source copied. Sumi popup bridge/session store/source regression tests are Sumi-owned. |
| External schemes | `macOS/DuckDuckGo/Tab/Navigation/ExternalAppSchemeHandler.swift`; `macOS/DuckDuckGo/Tab/Model/Tab+Navigation.swift`; `macOS/DuckDuckGo/Tab/TabExtensions/TabExtensions.swift`; `macOS/DuckDuckGo/Permissions/Model/*`; `SharedPackages/BrowserServicesKit/Sources/Navigation/*`; DDG tab-permission tests | No. Design-reference-only. | No DDG external app scheme implementation source copied. `SumiExternalAppResolver` and bridge/session-state code are Sumi-owned. |
| Autoplay | `macOS/DuckDuckGo/Tab/Navigation/AutoplayPolicyTabExtension.swift`; `macOS/DuckDuckGo/AutoplayPermissionSeeder.swift`; `macOS/DuckDuckGo/Preferences/Model/AutoplayPreferences.swift`; `macOS/DuckDuckGo/Permissions/Model/*`; `macOS/DuckDuckGo/Permissions/ViewModel/PermissionCenterViewModel.swift`; DDG autoplay tests; matching vendor navigation abstractions | No. Design-reference-only. | No DDG autoplay implementation source copied. Canonical `.autoplay` store adapter, Sumi navigation responder, and fallback WebKit configuration wiring are Sumi-owned. |
| File picker | `macOS/DuckDuckGo/Tab/Model/Tab+UIDelegate.swift`; `macOS/DuckDuckGo/Tab/View/BrowserTabViewController.swift`; `macOS/DuckDuckGo/Tab/Model/Tab+Dialogs.swift`; `macOS/DuckDuckGo/Common/Extensions/NSOpenPanelExtensions.swift` | No. Design-reference-only. | No DDG file picker/open-panel source copied. Normal-tab bridge/presenter code is Sumi-owned; MiniWindow/Glance auxiliary paths remain separate. |
| Storage access | `macOS/DuckDuckGo/Tab/Model/Tab+UIDelegate.swift`; `macOS/DuckDuckGo/Tab/Model/NSAlert+Tab.swift`; `macOS/DuckDuckGo/Common/Localizables/UserText.swift`; `macOS/DuckDuckGo/Permissions/Model/*` | No. Design/API-reference-only. | No DDG storage-access alert, string, or permission source copied. Sumi uses the observed private selector names and Sumi-owned coordinator/UI flow. |
| Screen sharing/display capture | `macOS/DuckDuckGo/Permissions/Model/*`; `macOS/DuckDuckGo/Common/Extensions/WKWebViewExtension.swift`; `macOS/DuckDuckGo/Tab/Model/Tab+UIDelegate.swift`; DDG permission/web-view tests | No. Design/API-reference-only. | No DDG display-capture implementation source copied. Sumi-owned code maps private display callbacks to canonical `.screenCapture`. |
| URL-bar indicator | `macOS/DuckDuckGo/NavigationBar/View/AddressBarButtonsViewController.swift`; `macOS/DuckDuckGo/VisualRefresh/AddressBarPermissionButtonsIconsProviding.swift`; `macOS/DuckDuckGo/Permissions/View/PermissionButton.swift`; `macOS/DuckDuckGo/Permissions/View/PopupBlockedPopover.swift`; permission model/view-model files | No. Design-reference-only. | No DDG UI source or assets copied. Sumi uses existing Sumi icons and SF Symbol fallbacks. |
| Prompt UI | `macOS/DuckDuckGo/Permissions/View/PermissionAuthorizationPopover.swift`; `macOS/DuckDuckGo/Permissions/View/PermissionAuthorizationSwiftUIView.swift`; `macOS/DuckDuckGo/Permissions/View/PermissionAuthorizationViewController.swift`; `macOS/DuckDuckGo/Permissions/ViewModel/PermissionCenterViewModel.swift`; permission authorization query/model files | No. Design-reference-only. | No DDG prompt/popover source copied. `SumiPermissionPromptView`, presenter, and view model are Sumi-owned. |
| URL hub submenu | DDG Permission Center and address-bar permission UI/model files listed above | No. Design-reference-only. | No DDG menu or Permission Center implementation copied. Sumi URL hub rows and current-site view model are Sumi-owned. |
| Privacy Site Settings | `macOS/DuckDuckGo/Permissions/View/PermissionCenterView.swift`; `macOS/DuckDuckGo/Permissions/ViewModel/PermissionCenterViewModel.swift`; DDG permission model/store files | No. Design-reference-only. | No DDG settings UI, strings, or store code copied. Sumi Site Settings repository/read models/views are Sumi-owned. |
| Runtime controls | DDG `WKWebViewExtension.swift`; DDG permission type/state/model files; DDG media/web-view tests | No. Design/API-reference-only. | No DDG runtime-control code copied. Sumi's runtime controller and control view models are Sumi-owned. |
| One-time lifecycle | DDG permission model/state/store tests and tab lifecycle reference files | No. Design-reference-only. | No DDG lifecycle implementation copied. Sumi lifecycle controller and store invariants are Sumi-owned. |
| Anti-abuse/cleanup | DDG permission model/store/UI reference files used for comparison only | No. Design-reference-only. | No DDG anti-abuse or cleanup implementation copied. Sumi prompt cooldown/embargo and stale-allow cleanup are Sumi-owned. |
| Automated tests | DDG unit/UI/integration tests listed in the relevant rows were inspected for behavior categories only. | No. Design-reference-only. | No DDG test source copied. Sumi tests under `SumiTests/` and `SumiUITests/` are Sumi-owned. |

## Copied/Adapted Code Inventory

| Sumi destination | Reference source | Classification | Required notice |
| --- | --- | --- | --- |
| `Sumi/Supporting Files/SumiWebKitGeolocationProviderABI.h` | `../references/apple-browsers/macOS/LocalPackages/CommonObjCExtensions/Sources/CommonObjCExtensions/include/WKGeolocationProvider.h` | Closely adapted/API-derived private WebKit geolocation ABI header. Sumi implementation code around it is Sumi-owned. | Preserve the Apache License, Version 2.0 notice and identify the DDG source in the destination header. |

No other permission implementation files, UI files, tests, strings, icons, fonts, images, media, or manual pages are copied or closely adapted from DDG.

## Private WebKit Symbols Documented

Geolocation private WebKit symbols are isolated to `Sumi/Geolocation/SumiGeolocationProvider.swift` and the adapted ABI header:

- `WKContextGetGeolocationManager`
- `WKGeolocationManagerSetProvider`
- `WKGeolocationManagerProviderDidChangePosition`
- `WKGeolocationManagerProviderDidFailToDeterminePosition`
- `WKGeolocationManagerProviderDidFailToDeterminePositionWithErrorMessage`
- `WKGeolocationPositionCreate_c`
- `WKRelease`

Geolocation private delegate selectors are isolated to `Sumi/Models/Tab/Tab+UIDelegate.swift` and routed into `SumiWebKitGeolocationBridge`:

- `_webView:requestGeolocationPermissionForFrame:decisionHandler:`
- `_webView:requestGeolocationPermissionForOrigin:initiatedByFrame:decisionHandler:`

Storage access private selector names are isolated to `Sumi/Models/Tab/Tab+UIDelegate.swift` and routed into `SumiStorageAccessPermissionBridge`:

- `_webView:requestStorageAccessPanelForDomain:underCurrentDomain:completionHandler:`
- `_webView:requestStorageAccessPanelForDomain:underCurrentDomain:forQuirkDomains:completionHandler:`

Display capture private selector usage is isolated to `Sumi/Models/Tab/Tab+UIDelegate.swift` and routed into `SumiWebKitPermissionBridge`:

- `_webView:requestDisplayCapturePermissionForOrigin:initiatedByFrame:withSystemAudio:decisionHandler:`

No private WebKit permission selectors are used from SwiftUI settings, URL hub views, prompt views, or manual test pages.

## Asset/Manual/Test Code Notes

No new fonts, icon packs, images, media files, CDNs, or license-incompatible assets were added for the permission project. Permission UI uses existing Sumi assets and SF Symbol fallbacks.

Manual pages use generated DOM/media primitives only and do not embed third-party source snippets. Automated permission tests under `SumiTests/` and `SumiUITests/` are Sumi-owned.

## Vendored DDG Code Ported Into Sumi Source (2026-07)

When the vendored `Vendor/DDG` snapshot was reduced to the `Navigation` and
`Common` targets, the bookmark storage code Sumi depends on was ported from
BrowserServicesKit into the app target. These files are copied or closely
adapted Apache 2.0 DDG source and carry the required notice in their headers:

| Source (duckduckgo/apple-browsers, BrowserServicesKit) | Destination |
| --- | --- |
| `Sources/Bookmarks/BookmarkEntity.swift` | `Sumi/Bookmarks/Store/BookmarkEntity.swift` |
| `Sources/Bookmarks/BookmarkUtils.swift` | `Sumi/Bookmarks/Store/BookmarkUtils.swift` |
| `Sources/Bookmarks/BookmarksModel.xcdatamodeld` | `Sumi/Bookmarks/Store/BookmarksModel.xcdatamodeld` |
| `Sources/Bookmarks/ImportExport/*` (importer, HTML exporter, import sources, node/summary/error types) | `Sumi/Bookmarks/Store/*` |
| `Sources/Persistence/CoreDataDatabase.swift` | `Sumi/Common/Database/SumiPersistentContainerDatabase.swift` (adapted) |

The URLPredictor Rust binary and its Swift wrapper were removed entirely; the
replacement classifier (`SumiAddressBarClassifier`), Punycode encoder, and
Public Suffix List matcher are Sumi-owned implementations. The bundled
`Sumi/Resources/public_suffix_list.dat` comes from https://publicsuffix.org
(Mozilla Public License 2.0; comments and blank lines are stripped for bundle size, rules unmodified, MPL notice retained in the file header).
