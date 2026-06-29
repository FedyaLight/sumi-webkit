import XCTest

@testable import Sumi

@MainActor
final class SafariExtensionImportAutoEnableTests: XCTestCase {
    func testImportSucceededEnableFailedErrorDescription() {
        let error = ExtensionError.importSucceededEnableFailed(
            "Raindrop was imported but could not be enabled: runtime unavailable"
        )
        XCTAssertEqual(
            error.errorDescription,
            "Raindrop was imported but could not be enabled: runtime unavailable"
        )
    }

    func testExtensionsModuleRefreshesInjectedImportStore() {
        let importStore = RecordingSafariExtensionImportStore()
        let module = SumiExtensionsModule(safariExtensionImportStore: importStore)
        let webExtension = makeCandidate(
            bundleIdentifier: "com.example.web-extension",
            bundleKind: .webExtension,
            runtimeStatus: .webExtensionImportable
        )
        let contentBlocker = makeCandidate(
            bundleIdentifier: "com.example.content-blocker",
            bundleKind: .contentBlocker,
            runtimeStatus: .contentBlockerImportable
        )

        module.refreshDiscoveredSafariWebExtensionCandidates([contentBlocker, webExtension])

        XCTAssertEqual(importStore.refreshedCandidateBatches, [[webExtension]])
    }

    func testExtensionsModuleDiagnosticsRefreshInjectedImportStore() {
        let importStore = RecordingSafariExtensionImportStore()
        let module = SumiExtensionsModule(safariExtensionImportStore: importStore)

        _ = module.safariExtensionCompatibilityReport()
        _ = module.safariExtensionAcceptanceMatrix()
        _ = module.safariExtensionRuntimeDiagnosticReport()

        XCTAssertEqual(importStore.refreshedCandidateBatches.count, 3)
    }

    private func makeCandidate(
        bundleIdentifier: String,
        bundleKind: SafariExtensionBundleKind,
        runtimeStatus: SafariExtensionRuntimeStatus
    ) -> DiscoveredSafariExtensionCandidate {
        DiscoveredSafariExtensionCandidate(
            extensionBundleIdentifier: bundleIdentifier,
            displayName: "Example",
            version: "1.0",
            extensionPointIdentifier: SafariExtensionScanner.safariWebExtensionPointIdentifier,
            bundleKind: bundleKind,
            runtimeStatus: runtimeStatus,
            containingAppName: "Example App",
            containingAppBundleIdentifier: "com.example.app",
            containingAppURL: URL(fileURLWithPath: "/Applications/Example.app"),
            appexURL: URL(fileURLWithPath: "/Applications/Example.app/Contents/PlugIns/Example.appex"),
            manifestURL: nil,
            isReadable: true
        )
    }
}

private final class RecordingSafariExtensionImportStore: SafariExtensionImportStoring,
    SafariExtensionImportRecordProviding {
    var refreshedCandidateBatches: [[DiscoveredSafariExtensionCandidate]] = []
    var removedInstalledExtensionIds: [String] = []
    var markedImports: [(candidate: DiscoveredSafariExtensionCandidate, installedExtensionId: String)] = []
    var importedRecordResults: [SafariExtensionImportedRecord] = []

    func refreshDiscoveredCandidates(_ candidates: [DiscoveredSafariExtensionCandidate]) {
        refreshedCandidateBatches.append(candidates)
    }

    func removeImportedRecord(forInstalledExtensionId installedExtensionId: String) {
        removedInstalledExtensionIds.append(installedExtensionId)
    }

    func markImported(
        candidate: DiscoveredSafariExtensionCandidate,
        installedExtensionId: String
    ) {
        markedImports.append((candidate, installedExtensionId))
    }

    func importedRecords() -> [SafariExtensionImportedRecord] {
        importedRecordResults
    }
}
