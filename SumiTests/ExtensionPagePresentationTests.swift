import XCTest

@testable import Sumi

@MainActor
final class ExtensionPagePresentationTests: XCTestCase {
    func testExtensionOwnedURLResolvesInstalledExtensionDisplayName() {
        let installed = makeInstalledExtension(id: "ext-bitwarden", name: "Bitwarden")
        let url = URL(string: "safari-web-extension://ext-bitwarden/popup.html")!

        XCTAssertEqual(
            ExtensionUtils.displayName(
                forExtensionOwnedURL: url,
                installedExtensions: [installed]
            ),
            "Bitwarden"
        )
    }

    func testExtensionOwnedURLDoesNotExposeTechnicalHostWhenExtensionIsUnknown() {
        let url = URL(string: "webkit-extension://ext-384345433143334442/page.html")!

        XCTAssertNil(
            ExtensionUtils.displayName(
                forExtensionOwnedURL: url,
                installedExtensions: []
            )
        )
        XCTAssertEqual(
            AuxiliaryWindowManager.windowTitle(
                for: url,
                ownerExtensionID: nil,
                installedExtensions: []
            ),
            "Extension"
        )
    }

    func testAuxiliaryWindowTitleKeepsExternalPopupHost() {
        let url = URL(string: "https://auth.example/login")!

        XCTAssertEqual(
            AuxiliaryWindowManager.windowTitle(
                for: url,
                ownerExtensionID: "ext-bitwarden",
                installedExtensions: [makeInstalledExtension(id: "ext-bitwarden", name: "Bitwarden")]
            ),
            "auth.example"
        )
    }

    func testAuxiliaryWindowTitleUsesOwnerExtensionFallbackForExtensionPage() {
        let installed = makeInstalledExtension(id: "ext-bitwarden", name: "Bitwarden")
        let url = URL(string: "safari-web-extension://unknown-extension/popup.html")!

        XCTAssertEqual(
            AuxiliaryWindowManager.windowTitle(
                for: url,
                ownerExtensionID: installed.id,
                installedExtensions: [installed]
            ),
            "Bitwarden"
        )
    }

    private func makeInstalledExtension(id: String, name: String) -> InstalledExtension {
        InstalledExtension(
            id: id,
            name: name,
            version: "1.0.0",
            manifestVersion: 3,
            description: nil,
            isEnabled: true,
            installDate: Date(),
            lastUpdateDate: Date(),
            packagePath: "/tmp/\(id)",
            iconPath: nil,
            sourceKind: .directory,
            backgroundModel: .none,
            incognitoMode: .spanning,
            sourcePathFingerprint: id,
            manifestRootFingerprint: id,
            sourceBundlePath: "/tmp/\(id)",
            optionsPagePath: nil,
            defaultPopupPath: nil,
            hasBackground: false,
            hasAction: false,
            hasOptionsPage: false,
            hasContentScripts: false,
            hasExtensionPages: true,
            activationSummary: ExtensionActivationSummary(
                matchPatternStrings: [],
                broadScope: false,
                hasContentScripts: false,
                hasAction: false,
                hasOptionsPage: false,
                hasExtensionPages: true
            ),
            manifest: [
                "manifest_version": 3,
                "name": name,
                "version": "1.0.0",
            ]
        )
    }
}
