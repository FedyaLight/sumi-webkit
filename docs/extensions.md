# Extension Compatibility

Safari Web Extensions are an experimental, off-by-default module in the first Sumi release. Sumi imports an installed Safari extension from its containing `.app` / `.appex`, then runs it with WebKit's `WKWebExtension` APIs. It does not patch third-party manifests or inject compatibility shims into extension code.

## Release-Candidate Matrix

Status reflects maintainer manual testing on 2026-07-30 plus automated coverage in this repository. It is a statement about specific workflows, not a promise that every feature or future extension version works.

| Extension or provider | Current status | Verified workflow / boundary |
| --- | --- | --- |
| Bitwarden | Works for the tested release workflow | Import and enable, action popup, sign-in, inline autofill, and local biometric/native-messaging paths. Profile-isolation retest remains part of the release checklist. |
| Proton Pass | Works for the tested release workflow | Import and enable, popup sign-in, site permission flow, worker-driven scripting, and inline autofill. Profile-isolation retest remains part of the release checklist. |
| Raindrop.io | Works | Import and enable, popup sign-in, save current page, persistence, and profile isolation. |
| Userscripts | Works through the Userscripts Safari extension | The companion library bridge supports the tested Userscripts workflow. Sumi does not expose a separate built-in arbitrary-script installer. |
| 1Password for Safari | Partial; not a release-supported workflow | Web extension pages and WebKit APIs can load, but 1Password 8 depends on a native Safari App Extension handler that macOS does not allow Sumi to host with public entitlements. Native unlock and end-to-end vault use are therefore not claimed. |
| Apple Passwords / iCloud Keychain | System WebKit behavior; not release-verified | Sumi uses `WKWebView`, for which Apple documents system handling of web authentication and credential requests. The repo has no Sumi-specific Apple Passwords extension integration or completed manual E2E, so full AutoFill support is not claimed yet. |

Apple's platform boundary is documented in [Password use in web browsers](https://developer.apple.com/documentation/authenticationservices/password-use-in-web-browsers) and [Passkey use in web browsers](https://developer.apple.com/documentation/authenticationservices/passkey-use-in-web-browsers).

## What Sumi Implements

- Discovery and import of installed Safari Web Extension app-extension bundles.
- Per-profile `WKWebExtensionController`, context, website-data, action, popup, tab, and window routing.
- Site-access and private-browsing policy surfaces.
- Extension toolbar actions, keyboard commands, and page context menus.
- Native-messaging adapters where the companion protocol is understood and can be implemented through public APIs.
- Fail-closed diagnostics that avoid logging message bodies, credentials, cookies, form values, or tokens.

The module is lazy: disabled extensions do not create controllers, contexts, observers, polling, or background work at browser startup.

## Install and Verify

1. Install the extension's normal macOS containing app.
2. In Sumi, enable the experimental Extensions module.
3. Open Settings → Extensions → Safari imports.
4. Import and enable the extension.
5. Verify the action popup and its core workflow on a non-private HTTPS page.

The release checklist is in [SafariExtensionManualE2E.md](SafariExtensionManualE2E.md). The detailed investigation history and runtime evidence remain in [SumiSafariExtensionCompatibility.md](SumiSafariExtensionCompatibility.md).

## Known Boundaries

- Compatibility depends on both WebKit and the third-party extension version.
- A Safari extension that requires private Safari host entitlements may not work outside Safari even when its web-extension code loads.
- Native companion protocols are not inferred or emulated without a documented, testable contract.
- Private-window and cross-profile behavior must be verified separately from a normal-window popup test.
