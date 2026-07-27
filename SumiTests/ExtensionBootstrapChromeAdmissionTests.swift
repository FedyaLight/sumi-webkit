import XCTest

@testable import Sumi

@MainActor
final class ExtensionBootstrapChromeAdmissionTests: XCTestCase {
    func testLedgerAdmitsOneProfilePerIdentityAndVersion() {
        let defaults = makeDatabase()
        let ledger = ExtensionGlobalInstallLedger(database: defaults)
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
        let ledger = ExtensionGlobalInstallLedger(database: makeDatabase())
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
        let ledger = ExtensionGlobalInstallLedger(database: makeDatabase())
        let admission = ExtensionBootstrapChromeAdmission(ledger: ledger)
        let firstProfile = UUID()
        let secondProfile = UUID()
        let gatedProfile = UUID()
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
        let gated = admission.begin(
            extensionIdentity: "extension",
            version: "1",
            profileID: gatedProfile,
            cause: .installation
        )

        XCTAssertTrue(
            admission.admitsChrome(
                extensionIdentity: "extension",
                profileID: firstProfile,
                hasUserGesture: false
            )
        )
        XCTAssertTrue(
            admission.admitsChrome(
                extensionIdentity: "extension",
                profileID: secondProfile,
                hasUserGesture: false
            ),
            "Profile attachment must not block ordinary extension tabs"
        )
        XCTAssertFalse(
            admission.admitsChrome(
                extensionIdentity: "extension",
                profileID: gatedProfile,
                hasUserGesture: false
            ),
            "A duplicate install must suppress automatic bootstrap chrome"
        )
        XCTAssertTrue(
            admission.admitsChrome(
                extensionIdentity: "extension",
                profileID: gatedProfile,
                hasUserGesture: true
            )
        )
        XCTAssertTrue(
            admission.admitsChrome(
                extensionIdentity: "extension",
                profileID: gatedProfile,
                hasUserGesture: false
            ),
            "A real user gesture must end the install bootstrap gate"
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
        admission.finish(gated)
    }

    func testUninstallClearsLedger() {
        let ledger = ExtensionGlobalInstallLedger(database: makeDatabase())
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

    func testProfileAttachmentNeverInheritsGlobalBootstrapGate() {
        let admission = ExtensionBootstrapChromeAdmission(
            ledger: ExtensionGlobalInstallLedger(database: makeDatabase())
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

        XCTAssertTrue(
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
            ledger: ExtensionGlobalInstallLedger(database: makeDatabase())
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

    private func makeDatabase() -> SumiDatabase {
        try! SumiDatabase.inMemory()
    }
}
