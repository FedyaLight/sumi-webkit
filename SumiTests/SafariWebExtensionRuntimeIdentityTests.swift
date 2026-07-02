import XCTest

@testable import Sumi

final class SafariWebExtensionRuntimeIdentityTests: XCTestCase {
    func testComposedIdentifierUsesSafariBundleTeamFormat() {
        XCTAssertEqual(
            SafariWebExtensionRuntimeIdentity.composedIdentifier(
                bundleIdentifier: "me.proton.pass.catalyst.safari-extension",
                teamIdentifier: "2SB5Z68H26"
            ),
            "me.proton.pass.catalyst.safari-extension (2SB5Z68H26)"
        )
    }

    func testComposedIdentifierIsNilForNonSafariSource() {
        XCTAssertNil(
            SafariWebExtensionRuntimeIdentity.composedIdentifier(
                sourceKind: .directory,
                sourceBundlePath: "/tmp/does-not-matter"
            )
        )
    }

    func testComposedIdentifierIsNilWhenBundleIdentityUnavailable() {
        // An arbitrary path is not a signed Safari .appex, so no composed
        // identifier can be derived and callers fall back to the internal id.
        XCTAssertNil(
            SafariWebExtensionRuntimeIdentity.composedIdentifier(
                sourceKind: .safariAppExtension,
                sourceBundlePath: "/nonexistent/Extension.appex"
            )
        )
    }

    func testInstalledProtonPassComposedIdentifierMatchesWebClientContract() throws {
        let appexPath =
            "/Applications/Proton Pass for Safari.app/Contents/PlugIns/Safari Extension.appex"
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: appexPath),
            "Proton Pass for Safari is not installed on this machine"
        )
        let composed = SafariWebExtensionRuntimeIdentity.composedIdentifier(
            sourceKind: .safariAppExtension,
            sourceBundlePath: appexPath
        )
        // The Proton account web app hardcodes this identifier for
        // externally_connectable messaging (packages/shared/lib/constants.ts).
        XCTAssertEqual(
            composed,
            "me.proton.pass.catalyst.safari-extension (2SB5Z68H26)"
        )
    }
}
