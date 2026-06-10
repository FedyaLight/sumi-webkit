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
        XCTAssertEqual(row.autofill, .fixed)
        XCTAssertEqual(row.popupAnchoring, .fixed)
    }

    func testManualVerificationCatalogOnePasswordPending() {
        let row = SafariExtensionManualVerificationCatalog.row(forTargetKey: "1password")
        XCTAssertEqual(row.importEnable, .notVerified)
        XCTAssertEqual(row.autofill, .pending)
        XCTAssertEqual(row.nativeMessagingProtocol, .unknown)
        XCTAssertTrue(row.notes.contains("inject-content-scripts"))
    }

    func testManualVerificationCatalogProtonPassScriptingBlocked() {
        let row = SafariExtensionManualVerificationCatalog.row(forTargetKey: "proton-pass")
        XCTAssertEqual(row.importEnable, .notVerified)
        XCTAssertEqual(row.autofill, .classified)
        XCTAssertEqual(row.nativeMessagingProtocol, .unknown)
        XCTAssertTrue(row.notes.contains("scripting denied"))
    }

    func testInlineUIClassificationCatalogPasswordManagers() {
        let bitwarden = SafariExtensionInlineUIClassificationCatalog
            .classification(forTargetKey: "bitwarden")
        XCTAssertEqual(bitwarden.verificationStatus, .fixed)
        XCTAssertEqual(bitwarden.primaryBlocker, .none)
        XCTAssertEqual(bitwarden.fixtures.localBasic, .expected)
        XCTAssertEqual(bitwarden.fixtures.iframe, .expected)
        XCTAssertEqual(bitwarden.fixtures.realSite, .classifiedOnly)

        let onePassword = SafariExtensionInlineUIClassificationCatalog
            .classification(forTargetKey: "1password")
        XCTAssertEqual(onePassword.verificationStatus, .pending)
        XCTAssertEqual(onePassword.primaryBlocker, .manualVerificationRequired)
        XCTAssertEqual(onePassword.fixtures.localBasic, .pending)
        XCTAssertTrue(onePassword.notes.contains("shouldDenyAutoGrantForWebKitRuntime"))

        let protonPass = SafariExtensionInlineUIClassificationCatalog
            .classification(forTargetKey: "proton-pass")
        XCTAssertEqual(protonPass.verificationStatus, .blockedByPlatform)
        XCTAssertEqual(protonPass.primaryBlocker, .scriptingPermissionDenied)
        XCTAssertTrue(protonPass.notes.contains("browser_specific_settings.safari"))
    }

    func testCompatibilityReportIncludesInlineUIClassification() {
        let report = SafariExtensionCompatibilityReportBuilder.build(
            targets: [SafariExtensionCompatibilityTargets.all[0]],
            discovered: [],
            importStore: importStore
        )

        XCTAssertEqual(report.entries[0].inlineUIClassification.verificationStatus, .fixed)
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
        XCTAssertEqual(report.supportedRelayProtocolHostCount, 1)
        XCTAssertTrue(report.note.contains("coalesced ext="))
        XCTAssertTrue(report.note.contains("WebKit extension console"))
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
        XCTAssertEqual(report.adapterCompatibility.count, SafariExtensionCompatibilityTargets.all.count)
        XCTAssertEqual(
            report.registeredAdapterIdentifiers,
            [BitwardenNativeMessagingIdentifiers.protocolIdentifier]
        )
        let bitwarden = report.entries.first { $0.targetKey == "bitwarden" }
        XCTAssertEqual(bitwarden?.launchSuppressionExpected, true)
        XCTAssertEqual(bitwarden?.expectedSessionState, .unknownProtocolInitial)
        XCTAssertEqual(bitwarden?.adapterSelected, true)
        XCTAssertEqual(bitwarden?.adapterIdentifier, BitwardenNativeMessagingIdentifiers.protocolIdentifier)
        XCTAssertEqual(bitwarden?.protocolStatus, .notApplicable)
        XCTAssertEqual(bitwarden?.failureBucket, .extensionNotImported)
        XCTAssertTrue(
            bitwarden?.classifications.contains(.companionAppProtocolUnknown) ?? false
        )
        let adapterRow = report.adapterCompatibility.first { $0.targetKey == "bitwarden" }
        XCTAssertEqual(adapterRow?.desktopResolved, true)
        XCTAssertEqual(adapterRow?.realTransportAttempted, false)
        XCTAssertEqual(adapterRow?.biometricsStatusProbe, .notAttempted)
        XCTAssertEqual(
            adapterRow?.repeatedCallCountBucket,
            SumiNativeMessagingRetryCountBucket.none
        )
        let raindropRow = report.adapterCompatibility.first { $0.targetKey == "raindrop" }
        XCTAssertEqual(raindropRow?.protocolStatus, .notApplicable)
        XCTAssertEqual(raindropRow?.biometricsStatusProbe, .notApplicable)
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
