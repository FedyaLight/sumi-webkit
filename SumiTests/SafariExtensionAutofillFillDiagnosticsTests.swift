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
            44
        )
        XCTAssertTrue(
            SafariExtensionAutofillFillDiagnosticBucket.allCases.contains(.popupSeesCurrentTab)
        )
        XCTAssertTrue(
            SafariExtensionAutofillFillDiagnosticBucket.allCases.contains(.pageWorldBridgeMissing)
        )
        XCTAssertTrue(
            SafariExtensionAutofillFillDiagnosticBucket.allCases.contains(.inlineUIRenderAttempted)
        )
        XCTAssertTrue(
            SafariExtensionAutofillFillDiagnosticBucket.allCases.contains(.overlayHeightCollapsed)
        )
    }

    func testInlineUIInfrastructureProbeDocumentsTabContainerChromeClipping() {
        let probe = SafariExtensionInlineUIInfrastructureProbe.evaluate()
        XCTAssertTrue(probe.clipsToBoundsOnTabContainer)
        XCTAssertFalse(probe.clipsToBoundsAffectsInPageExtensionOverlays)
        XCTAssertTrue(probe.inlineUINavigationResponderWired)
        XCTAssertTrue(probe.detail.contains("tabContainerClipsToBoundsChromeOnly"))
    }

    func testRecordIsNoOpWhenVerboseDisabled() {
        SafariExtensionAutofillFillDiagnostics.record(.fillActionStarted)
        let snapshot = SafariExtensionAutofillFillDiagnostics.snapshot()
        XCTAssertTrue(snapshot.bucketCounts.isEmpty)
    }

    func testPopupCloseAlwaysEndsDiagnosticFillSession() {
        SafariExtensionAutofillFillDiagnostics.beginFillSession(extensionId: "ext-a")
        SafariExtensionAutofillFillDiagnostics.recordNativeMessagingActivity(extensionId: "ext-a")
        SafariExtensionAutofillFillDiagnostics.setPopupActive(false, extensionId: "ext-a")

        XCTAssertFalse(SafariExtensionAutofillFillDiagnostics.isFillSessionActive)
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
        XCTAssertEqual(contents?.contains("__sumiAutofillFillProbe"), true)
    }
}
