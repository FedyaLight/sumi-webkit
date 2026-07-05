# Sumi Permissions

Sumi's permission system routes normal-tab website permission requests through browser-owned bridges, a central coordinator, profile-scoped storage, macOS system authorization boundaries, and UI surfaces that settle requests without directly touching WebKit callbacks or SwiftData.

Implemented normal-tab permission types:

- camera
- microphone
- camera + microphone grouping
- geolocation
- notifications
- screenCapture
- popups
- externalScheme
- autoplay
- filePicker
- storageAccess

## Main Documentation

- [Architecture](ARCHITECTURE.md)
- [Validation plan](TEST_PLAN.md)
- [License notes](LICENSE_NOTES.md)

## Validation Summary

Automated validation covers unit tests, bridge/integration tests, view-model tests, source-level regression guards, and documentation fixture tests.

Manual validation for real device, TCC, WebKit, app-handler, and app-level popover behavior is local-only and intentionally not versioned in this mirror repository.

## Deferred Work

- MiniWindow/Glance permission integration.
- Extension permission bridging/UI.
- Deterministic permission XCUITest injection harness.
- Optional future content settings for JavaScript, images, automatic downloads, ads, background sync, and sound.
- Optional ServiceWorker notification support if WebKit exposes a safe app-owned path.
