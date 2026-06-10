import XCTest

@testable import Sumi

@MainActor
final class SafariExtensionRuntimeDiagnosticsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var importStore: SafariExtensionImportStore!

    override func setUp() {
        suiteName = "SafariExtensionRuntimeDiagnosticsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        importStore = SafariExtensionImportStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        suiteName = nil
        defaults = nil
        importStore = nil
    }

    func testManualVerificationCatalogRaindropVerified() {
        let row = SafariExtensionManualVerificationCatalog.row(forTargetKey: "raindrop")
        XCTAssertEqual(row.importEnable, .yes)
        XCTAssertEqual(row.popup, .yes)
        XCTAssertEqual(row.signInSession, .yes)
        XCTAssertEqual(row.saveFlow, .yes)
        XCTAssertEqual(row.profileIsolation, .yes)
    }

    func testManualVerificationCatalogBitwardenStatuses() {
        let row = SafariExtensionManualVerificationCatalog.row(forTargetKey: "bitwarden")
        XCTAssertEqual(row.importEnable, .yes)
        XCTAssertEqual(row.mv2WarningObserved, .yes)
        XCTAssertEqual(row.popup, .yes)
        XCTAssertEqual(row.signInSession, .yes)
        XCTAssertEqual(row.desktopLaunchLoop, .no)
        XCTAssertEqual(row.nativeMessagingProtocol, .unknown)
        XCTAssertEqual(row.autofill, .classified)
        XCTAssertEqual(row.popupAnchoring, .fixed)
    }

    func testManualVerificationCatalogPasswordManagersNotFullyVerified() {
        for key in ["1password", "proton-pass"] {
            let row = SafariExtensionManualVerificationCatalog.row(forTargetKey: key)
            XCTAssertEqual(row.importEnable, .notVerified)
            XCTAssertEqual(row.nativeMessagingProtocol, .unknown)
            XCTAssertTrue(row.notes.contains("companionAppProtocolUnknown"))
        }
    }

    func testPopupAnchorProbePasses() {
        let result = SafariExtensionPopupAnchorProbe.evaluate()
        XCTAssertTrue(result.passed, result.detail)
        XCTAssertEqual(result.status, .wired)
    }

    func testTabFrameMappingProbePasses() {
        let result = SafariExtensionTabFrameMappingProbe.evaluate()
        XCTAssertTrue(result.passed, result.detail)
        XCTAssertEqual(result.status, .wired)
    }

    func testNativeMessagingSuppressionProbePasses() {
        let report = SafariExtensionNativeMessagingSuppressionProbe.evaluate()
        XCTAssertTrue(report.repeatedCallSuppressionEnabled)
        XCTAssertTrue(report.coalescedLoggingEnabled)
        XCTAssertTrue(report.sessionStateTrackingEnabled)
        XCTAssertTrue(report.companionProtocolUnknownDeterministic)
        XCTAssertEqual(report.supportedRelayProtocolHostCount, 0)
    }

    func testPasswordManagerFormFixtureProbePasses() {
        let result = SafariExtensionPasswordManagerFormFixtureProbe.evaluate()
        XCTAssertTrue(result.passed, result.detail)
    }

    func testRuntimeDiagnosticReportIncludesManualVerification() {
        let report = SafariExtensionRuntimeDiagnosticsBuilder.build(
            targets: [SafariExtensionCompatibilityTargets.all[0]],
            discovered: [],
            importStore: importStore
        )

        XCTAssertEqual(report.entries.count, 1)
        XCTAssertEqual(report.entries[0].targetKey, "bitwarden")
        XCTAssertEqual(report.entries[0].manualVerification.importEnable, .yes)
        XCTAssertTrue(report.entries[0].runtimeStatus.launchSuppressionExpected)
        XCTAssertEqual(
            report.entries[0].runtimeStatus.nativeMessagingSessionState,
            .unknownProtocolInitial
        )
        XCTAssertTrue(report.globalSuppressionReport.repeatedCallSuppressionEnabled)
    }

    func testAcceptanceMatrixIncludesGlobalProbes() {
        let matrix = SafariExtensionAcceptanceMatrixBuilder.build(
            targets: [SafariExtensionCompatibilityTargets.all[0]],
            discovered: [],
            importStore: importStore
        )

        XCTAssertEqual(matrix.globalChecks.count, 3)
        XCTAssertTrue(
            matrix.globalChecks.contains {
                $0.check == .popupAnchorPresentationWired && $0.passed
            }
        )
        XCTAssertTrue(
            matrix.globalChecks.contains {
                $0.check == .nativeMessagingSuppressionReportWired && $0.passed
            }
        )
        XCTAssertTrue(
            matrix.globalChecks.contains {
                $0.check == .passwordManagerLocalFormFixtureAvailable && $0.passed
            }
        )
        XCTAssertTrue(matrix.globalSuppressionReport.repeatedCallSuppressionEnabled)
    }

    func testNativeMessagingProbeIncludesSuppressionReport() {
        let report = SafariExtensionNativeMessagingProbeBuilder.build(
            discovered: [],
            importStore: importStore
        )

        XCTAssertTrue(report.suppressionReport.coalescedLoggingEnabled)
        let bitwarden = report.entries.first { $0.targetKey == "bitwarden" }
        XCTAssertEqual(bitwarden?.launchSuppressionExpected, true)
        XCTAssertEqual(bitwarden?.expectedSessionState, .unknownProtocolInitial)
        XCTAssertTrue(
            bitwarden?.classifications.contains(.companionAppProtocolUnknown) ?? false
        )
    }

    func testCompatibilityReportIncludesManualVerification() {
        let report = SafariExtensionCompatibilityReportBuilder.build(
            targets: [SafariExtensionCompatibilityTargets.all[3]],
            discovered: [],
            importStore: importStore
        )

        XCTAssertEqual(report.entries[0].manualVerification.importEnable, .yes)
        XCTAssertEqual(report.entries[0].manualVerification.saveFlow, .yes)
    }
}
