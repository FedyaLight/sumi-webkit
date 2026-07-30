# Safari Extension Release Checklist

Run these checks on the packaged release build with the Extensions module enabled. Use test accounts and fixtures; never capture real passwords, tokens, cookies, form values, or vault contents in logs or screenshots.

## Common Checks

For every target:

1. Install the target's current macOS containing app.
2. Import its `.appex` from Settings → Extensions → Safari imports.
3. Enable it and confirm the action appears on a normal HTTPS page.
4. Close and reopen Sumi; confirm the extension remains installed and enabled.
5. Repeat the core workflow in two Sumi profiles and confirm sessions do not cross profiles.
6. Disable the module and confirm no extension controller, popup, worker, polling, or repeated companion-app launch remains active.

## Target Workflows

| Target | Release-candidate baseline | Recheck before publishing |
| --- | --- | --- |
| Bitwarden | Import, popup, sign-in, inline autofill, and local biometric/native messaging work. | Autofill a login fixture, validate profile isolation, and confirm repeated unlock does not create a launch loop. |
| Proton Pass | Import, popup sign-in, permission flow, dynamic scripting, and inline autofill work. | Complete a fresh popup login, focus a login fixture for inline UI, and validate profile isolation. |
| Raindrop.io | Import, popup sign-in, save page, persistence, and profile isolation work. | Save an HTTPS article and confirm the saved state after reopening the popup and app. |
| Userscripts | The Safari extension and Sumi companion-library bridge work. | Run one local script, update it through the companion flow, reload the page, and confirm the update applies only to the intended match. |
| 1Password for Safari | Partial only; native-core unlock is not supported outside Safari. | Confirm failures are bounded and honestly surfaced; do not treat extension-page loading as end-to-end support. |
| Apple Passwords/iCloud Keychain | Not yet release-verified. | On a clean account with Password AutoFill enabled, test password suggestion/fill, passkey authentication, and save/update behavior through a normal Sumi `WKWebView`. Record the exact macOS build and whether UI is system-provided. |

## Fixture

Serve the repository login forms with:

```sh
scripts/serve_autofill_fixtures.sh
```

Then open `http://127.0.0.1:8765/login-basic.html`. The loopback fixture is for UI and routing checks only; never populate it with a real account.

Detailed native-messaging diagnostics are documented in [SafariExtensionNativeMessagingAdapterAcceptance.md](SafariExtensionNativeMessagingAdapterAcceptance.md).
