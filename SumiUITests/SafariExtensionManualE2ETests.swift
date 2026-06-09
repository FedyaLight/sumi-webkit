import XCTest

/// Skipped-by-default manual E2E checklist for Safari Web Extension targets.
/// Run individually in Xcode after importing and enabling each extension in Sumi.
@MainActor
final class SafariExtensionManualE2ETests: XCTestCase {
    func testBitwardenImportEnableURLHubPopup() throws {
        throw XCTSkip(
            """
            Manual E2E — Bitwarden:
            1. Settings → Extensions → Safari imports → Import Bitwarden
            2. Enable extension in Sumi settings
            3. Open https:// example.com (or any https page)
            4. URL-hub → Bitwarden action → confirm non-empty popup
            5. Login form page → confirm autofill icons (content scripts)
            """
        )
    }

    func test1PasswordImportEnableURLHubPopup() throws {
        throw XCTSkip(
            """
            Manual E2E — 1Password:
            1. Settings → Extensions → Safari imports → Import 1Password for Safari
            2. Enable extension
            3. Open https:// page → URL-hub action → non-empty popup
            4. Login form → autofill prompt
            """
        )
    }

    func testProtonPassImportEnableURLHubPopup() throws {
        throw XCTSkip(
            """
            Manual E2E — Proton Pass:
            1. Settings → Extensions → Safari imports → Import Proton Pass for Safari
            2. Enable extension
            3. Open https:// page → URL-hub action → non-empty popup
            4. Login form → autofill prompt
            """
        )
    }

    func testRaindropImportEnableSaveFlow() throws {
        throw XCTSkip(
            """
            Manual E2E — Raindrop:
            1. Settings → Extensions → Safari imports → Import Save to Raindrop.io
            2. Enable extension
            3. Open https:// article page
            4. URL-hub → Raindrop action → save UI shows page title/URL
            5. Confirm save completes without native host relay
            """
        )
    }
}
