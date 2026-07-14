import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class SafariExtensionImportAutoEnableTests: XCTestCase {
    private var scratchDirectory: URL!

    override func setUpWithError() throws {
        scratchDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: scratchDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let scratchDirectory, FileManager.default.fileExists(atPath: scratchDirectory.path) {
            try FileManager.default.removeItem(at: scratchDirectory)
        }
        scratchDirectory = nil
    }

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

    @available(macOS 15.5, *)
    func testSyncDiscoveredSafariWebExtensionAddsDisabledRecord() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let importStore = RecordingSafariExtensionImportStore()
        let container = try makeTestContainer()
        let module = makeEnabledModule(
            context: container.mainContext,
            importStore: importStore,
            defaults: harness.defaults
        )
        let candidate = try makeSafariWebExtensionCandidate(
            bundleIdentifier: "com.example.sync-disabled"
        )

        let result = await module.syncDiscoveredSafariWebExtensions([candidate])

        let installed = try XCTUnwrap(result.addedExtensions.first)
        XCTAssertEqual(result.addedExtensions.count, 1)
        XCTAssertFalse(installed.isEnabled)
        XCTAssertEqual(installed.id, candidate.extensionBundleIdentifier)
        XCTAssertEqual(installed.sourceKind, .safariAppExtension)
        XCTAssertEqual(installed.sourceBundlePath, candidate.appexURL.path)
        XCTAssertEqual(importStore.markedImports.map { $0.candidate.id }, [candidate.id])
    }

    @available(macOS 15.5, *)
    func testSyncDiscoveredSafariWebExtensionSkipsExistingEnabledRecord() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let importStore = RecordingSafariExtensionImportStore()
        let container = try makeTestContainer()
        let module = makeEnabledModule(
            context: container.mainContext,
            importStore: importStore,
            defaults: harness.defaults
        )
        let candidate = try makeSafariWebExtensionCandidate(
            bundleIdentifier: "com.example.sync-existing-enabled"
        )
        let firstResult = await module.syncDiscoveredSafariWebExtensions([candidate])
        let installed = try XCTUnwrap(firstResult.addedExtensions.first)
        let manager = try XCTUnwrap(module.managerForTesting(materializeIfNeeded: false))
        let entity = try XCTUnwrap(try manager.extensionEntity(for: installed.id))
        try manager.installationMetadataStore.setEnabled(true, for: entity)
        let enabledRecord = manager.installationMetadataStore.record(
            installed,
            withEnabledState: true
        )
        manager.installedExtensionCollection.setAll([enabledRecord])

        let secondResult = await module.syncDiscoveredSafariWebExtensions([candidate])

        XCTAssertTrue(secondResult.addedExtensions.isEmpty)
        XCTAssertEqual(manager.installedExtensionCollection.records.first?.isEnabled, true)
        XCTAssertEqual(importStore.markedImports.map { $0.candidate.id }, [candidate.id])
    }

    @available(macOS 15.5, *)
    func testSyncDiscoveredSafariWebExtensionsDoesNotMaterializeContentBlockers()
        async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let importStore = RecordingSafariExtensionImportStore()
        let container = try makeTestContainer()
        let module = makeEnabledModule(
            context: container.mainContext,
            importStore: importStore,
            defaults: harness.defaults
        )
        let contentBlocker = makeCandidate(
            bundleIdentifier: "com.example.content-blocker",
            bundleKind: .contentBlocker,
            runtimeStatus: .contentBlockerImportable
        )

        let result = await module.syncDiscoveredSafariWebExtensions([contentBlocker])

        XCTAssertTrue(result.addedExtensions.isEmpty)
        XCTAssertTrue(importStore.markedImports.isEmpty)
        XCTAssertTrue(module.managerForTesting(materializeIfNeeded: false)?.installedExtensionCollection.records.isEmpty ?? false)
    }

    private func makeCandidate(
        bundleIdentifier: String,
        bundleKind: SafariExtensionBundleKind,
        runtimeStatus: SafariExtensionRuntimeStatus,
        appexURL: URL? = nil
    ) -> DiscoveredSafariExtensionCandidate {
        let appexURL = appexURL
            ?? URL(fileURLWithPath: "/Applications/Example.app/Contents/PlugIns/Example.appex")
        return DiscoveredSafariExtensionCandidate(
            extensionBundleIdentifier: bundleIdentifier,
            displayName: "Example",
            version: "1.0",
            extensionPointIdentifier: SafariExtensionScanner.safariWebExtensionPointIdentifier,
            bundleKind: bundleKind,
            runtimeStatus: runtimeStatus,
            containingAppName: "Example App",
            containingAppBundleIdentifier: "com.example.app",
            containingAppURL: URL(fileURLWithPath: "/Applications/Example.app"),
            appexURL: appexURL,
            manifestURL: nil,
            isReadable: true
        )
    }

    @available(macOS 15.5, *)
    private func makeEnabledModule(
        context: ModelContext,
        importStore: RecordingSafariExtensionImportStore,
        defaults: UserDefaults
    ) -> SumiExtensionsModule {
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: defaults)
        )
        registry.enable(.extensions)
        let profile = Profile(name: "Safari Sync Profile")
        return SumiExtensionsModule(
            moduleRegistry: registry,
            context: context,
            initialProfileProvider: { profile },
            safariExtensionImportStore: importStore
        )
    }

    private func makeTestContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func makeSafariWebExtensionCandidate(
        bundleIdentifier: String
    ) throws -> DiscoveredSafariExtensionCandidate {
        let appexURL = try SafariExtensionScannerTestSupport.makeStandaloneAppex(
            in: scratchDirectory,
            specification: .init(
                name: bundleIdentifier,
                bundleIdentifier: bundleIdentifier,
                displayName: "Example"
            )
        )
        return makeCandidate(
            bundleIdentifier: bundleIdentifier,
            bundleKind: .webExtension,
            runtimeStatus: .webExtensionImportable,
            appexURL: appexURL
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
