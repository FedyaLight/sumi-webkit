import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SafariExtensionAutofillFillDiagnosticsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SafariExtensionAutofillFillDiagnostics.resetForTesting()
    }

    func testAllBucketsExist() {
        XCTAssertEqual(
            SafariExtensionAutofillFillDiagnosticBucket.allCases.count,
            25
        )
        XCTAssertTrue(
            SafariExtensionAutofillFillDiagnosticBucket.allCases.contains(.popupSeesCurrentTab)
        )
        XCTAssertTrue(
            SafariExtensionAutofillFillDiagnosticBucket.allCases.contains(.pageWorldBridgeMissing)
        )
    }

    func testRecordIsNoOpWhenVerboseDisabled() {
        SafariExtensionAutofillFillDiagnostics.record(.fillActionStarted)
        let snapshot = SafariExtensionAutofillFillDiagnostics.snapshot()
        XCTAssertTrue(snapshot.bucketCounts.isEmpty)
    }

    func testFillSessionDefersTeardownAfterPopupCloseWithNativeMessaging() {
        SafariExtensionAutofillFillDiagnostics.beginFillSession(extensionId: "ext-a")
        SafariExtensionAutofillFillDiagnostics.recordNativeMessagingActivity(extensionId: "ext-a")
        SafariExtensionAutofillFillDiagnostics.setPopupActive(false, extensionId: "ext-a")

        XCTAssertTrue(SafariExtensionAutofillFillDiagnostics.isFillSessionActive)
        XCTAssertTrue(
            SafariExtensionAutofillFillDiagnostics.shouldDeferNativeMessagingTeardownOnPopupClose()
        )

        SafariExtensionAutofillFillDiagnostics.endFillSession(extensionId: "ext-a")
        XCTAssertFalse(SafariExtensionAutofillFillDiagnostics.isFillSessionActive)
        XCTAssertFalse(
            SafariExtensionAutofillFillDiagnostics.shouldDeferNativeMessagingTeardownOnPopupClose()
        )
    }

    func testIntentionalDeferredTeardownSuppressesRelayCancellationDiagnostics() {
        SafariExtensionAutofillFillDiagnostics.beginFillSession(extensionId: "ext-b")
        SafariExtensionAutofillFillDiagnostics.beginIntentionalDeferredTeardown()
        XCTAssertFalse(SafariExtensionAutofillFillDiagnostics.shouldRecordRelayCancellation())
        SafariExtensionAutofillFillDiagnostics.endIntentionalDeferredTeardown()
        XCTAssertTrue(SafariExtensionAutofillFillDiagnostics.shouldRecordRelayCancellation())
    }

    func testPasswordManagerFixtureProbeFindsAutofillPages() {
        let probe = SafariExtensionPasswordManagerFormFixtureProbe.evaluate()
        XCTAssertTrue(probe.passed, probe.detail)
        XCTAssertTrue(probe.detail.contains("login-basic.html"))
    }

    func testFillProbeScriptExistsInAutofillFixtures() {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let probeURL = repoRoot.appendingPathComponent(
            "SumiTests/Fixtures/AutofillPages/shared/fill-probe.js"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: probeURL.path))
        let contents = try? String(contentsOf: probeURL, encoding: .utf8)
        XCTAssertTrue(contents?.contains("__sumiAutofillFillProbe") == true)
    }
}
