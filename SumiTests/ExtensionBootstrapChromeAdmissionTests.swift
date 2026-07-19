import XCTest

@testable import Sumi

@MainActor
final class ExtensionBootstrapChromeAdmissionTests: XCTestCase {
    func testLedgerAdmitsOneProfilePerIdentityAndVersion() {
        let defaults = makeDefaults()
        let ledger = ExtensionGlobalInstallLedger(userDefaults: defaults)
        let firstProfile = UUID()
        let secondProfile = UUID()

        XCTAssertTrue(
            ledger.claim(
                identity: "extension",
                version: "1.0",
                profileID: firstProfile
            ).admitsBootstrapChrome
        )
        XCTAssertFalse(
            ledger.claim(
                identity: "extension",
                version: "1.0",
                profileID: secondProfile
            ).admitsBootstrapChrome
        )
        XCTAssertFalse(
            ledger.claim(
                identity: "extension",
                version: "1.0",
                profileID: firstProfile,
                cause: .profileAttachment
            ).admitsBootstrapChrome,
            "Reloading the owner profile must not reclaim install chrome"
        )
        XCTAssertTrue(
            ledger.claim(
                identity: "extension",
                version: "2.0",
                profileID: secondProfile
            ).admitsBootstrapChrome
        )
        XCTAssertFalse(
            ledger.claim(
                identity: "extension",
                version: "2.0",
                profileID: firstProfile
            ).admitsBootstrapChrome
        )
    }

    func testExistingInstallMigrationDoesNotCreateFreshOnboardingOwner() {
        let ledger = ExtensionGlobalInstallLedger(userDefaults: makeDefaults())
        let firstRestoredProfile = UUID()
        let otherProfile = UUID()

        XCTAssertFalse(
            ledger.claim(
                identity: "existing-extension",
                version: "1.0",
                profileID: firstRestoredProfile,
                cause: .profileAttachment
            ).admitsBootstrapChrome
        )
        XCTAssertFalse(
            ledger.claim(
                identity: "existing-extension",
                version: "1.0",
                profileID: otherProfile,
                cause: .profileAttachment
            ).admitsBootstrapChrome
        )
        XCTAssertTrue(
            ledger.claim(
                identity: "existing-extension",
                version: "2.0",
                profileID: otherProfile,
                cause: .update
            ).admitsBootstrapChrome
        )
    }

    func testAdmissionSuppressesOnlyBootstrapWithoutUserGesture() {
        let ledger = ExtensionGlobalInstallLedger(userDefaults: makeDefaults())
        let admission = ExtensionBootstrapChromeAdmission(ledger: ledger)
        let firstProfile = UUID()
        let secondProfile = UUID()
        let first = admission.begin(
            extensionIdentity: "extension",
            version: "1",
            profileID: firstProfile,
            cause: .installation
        )
        let second = admission.begin(
            extensionIdentity: "extension",
            version: "1",
            profileID: secondProfile,
            cause: .profileAttachment
        )

        XCTAssertTrue(
            admission.admitsChrome(
                extensionIdentity: "extension",
                profileID: firstProfile,
                hasUserGesture: false
            )
        )
        XCTAssertFalse(
            admission.admitsChrome(
                extensionIdentity: "extension",
                profileID: secondProfile,
                hasUserGesture: false
            )
        )
        XCTAssertTrue(
            admission.admitsChrome(
                extensionIdentity: "extension",
                profileID: secondProfile,
                hasUserGesture: true
            )
        )
        XCTAssertTrue(
            admission.admitsChrome(
                extensionIdentity: "extension",
                profileID: secondProfile,
                hasUserGesture: false
            ),
            "A real user gesture must end the secondary-profile bootstrap gate"
        )

        admission.finish(second)
        XCTAssertTrue(
            admission.admitsChrome(
                extensionIdentity: "extension",
                profileID: secondProfile,
                hasUserGesture: false
            )
        )
        admission.finish(first)
    }

    func testUninstallClearsLedger() {
        let ledger = ExtensionGlobalInstallLedger(userDefaults: makeDefaults())
        let admission = ExtensionBootstrapChromeAdmission(ledger: ledger)
        let firstProfile = UUID()
        let secondProfile = UUID()
        let first = admission.begin(
            extensionIdentity: "extension",
            version: "1",
            profileID: firstProfile,
            cause: .installation
        )
        admission.finish(first)
        admission.removeFromLedger(extensionIdentity: "extension")
        let reinstalled = admission.begin(
            extensionIdentity: "extension",
            version: "1",
            profileID: secondProfile,
            cause: .installation
        )

        XCTAssertTrue(
            admission.admitsChrome(
                extensionIdentity: "extension",
                profileID: secondProfile,
                hasUserGesture: false
            )
        )
        admission.finish(reinstalled)
    }

    func testContextRetirementClearsCausalBootstrapGate() {
        let admission = ExtensionBootstrapChromeAdmission(
            ledger: ExtensionGlobalInstallLedger(userDefaults: makeDefaults())
        )
        let ownerProfile = UUID()
        let secondaryProfile = UUID()
        _ = admission.begin(
            extensionIdentity: "extension",
            version: "1",
            profileID: ownerProfile,
            cause: .installation
        )
        _ = admission.begin(
            extensionIdentity: "extension",
            version: "1",
            profileID: secondaryProfile,
            cause: .profileAttachment
        )

        XCTAssertFalse(
            admission.admitsChrome(
                extensionIdentity: "extension",
                profileID: secondaryProfile,
                hasUserGesture: false
            )
        )
        admission.retire(
            extensionIdentity: "extension",
            profileID: secondaryProfile
        )
        XCTAssertTrue(
            admission.admitsChrome(
                extensionIdentity: "extension",
                profileID: secondaryProfile,
                hasUserGesture: false
            )
        )
    }

    func testSettlementEndsBootstrapGateForTheLoadedContext() {
        let admission = ExtensionBootstrapChromeAdmission(
            ledger: ExtensionGlobalInstallLedger(userDefaults: makeDefaults())
        )
        let profileID = UUID()
        let scope = admission.begin(
            extensionIdentity: "extension",
            version: "1",
            profileID: profileID,
            cause: .installation
        )
        XCTAssertTrue(scope.admitsBootstrapChrome)
        XCTAssertTrue(
            admission.admitsChrome(
                extensionIdentity: "extension",
                profileID: profileID,
                hasUserGesture: false
            )
        )

        admission.finishBootstrap(
            extensionIdentity: "extension",
            profileID: profileID
        )
        XCTAssertTrue(
            admission.admitsChrome(
                extensionIdentity: "extension",
                profileID: profileID,
                hasUserGesture: false
            )
        )
    }

    func testBootstrapPermissionTargetsCausalSiteScopedManifestOrigins() {
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "host_permissions": ["*://*/*"],
            "externally_connectable": [
                "matches": [
                    "https://account.example.com/*",
                    "https://*.broad.example/*",
                ],
            ],
            "content_scripts": [
                ["matches": ["https://content.example/*"]],
            ],
        ]

        XCTAssertTrue(
            ExtensionBootstrapPermissionTargetPolicy.requiresEarlyPrompt(
                for: URL(string: "https://account.example.com/onboarding")!,
                manifest: manifest
            )
        )
        XCTAssertTrue(
            ExtensionBootstrapPermissionTargetPolicy.requiresEarlyPrompt(
                for: URL(string: "https://login.broad.example/onboarding")!,
                manifest: manifest
            )
        )
        XCTAssertTrue(
            ExtensionBootstrapPermissionTargetPolicy.requiresEarlyPrompt(
                for: URL(string: "https://content.example/onboarding")!,
                manifest: manifest
            )
        )
        XCTAssertFalse(
            ExtensionBootstrapPermissionTargetPolicy.requiresEarlyPrompt(
                for: URL(string: "https://unrelated.example/login")!,
                manifest: manifest
            )
        )
        XCTAssertEqual(
            ExtensionBootstrapPermissionTargetPolicy.earlyPromptTargets(
                in: [
                    URL(string: "https://account.example.com/first")!,
                    URL(string: "https://account.example.com/second")!,
                    URL(string: "https://unrelated.example/login")!,
                ],
                manifest: manifest
            ),
            [
                URL(string: "https://account.example.com/")!,
            ]
        )
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(
            suiteName: "ExtensionBootstrapChromeAdmissionTests.\(UUID().uuidString)"
        )!
    }
}
