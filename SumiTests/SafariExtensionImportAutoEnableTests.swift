import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SafariExtensionImportAutoEnableTests:
    SafariExtensionWebViewControllerWiringTestCase {
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
    func testAddSafariWebExtensionCreatesDisabledRecord() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let importStore = RecordingSafariExtensionImportStore()
        let container = try makeTestContainer()
        let fixture = makeEnabledModule(
            context: container,
            importStore: importStore,
            defaults: harness.defaults
        )
        let module = fixture.module
        let scratchDirectory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchDirectory) }
        let candidate = try makeSafariWebExtensionCandidate(
            bundleIdentifier: "com.example.sync-disabled",
            in: scratchDirectory
        )

        let installed = try await module.addSafariAppExtension(from: candidate)

        XCTAssertFalse(installed.isEnabled)
        XCTAssertEqual(installed.id, candidate.extensionBundleIdentifier)
        XCTAssertEqual(installed.sourceKind, .safariAppExtension)
        XCTAssertEqual(installed.sourceBundlePath, candidate.appexURL.path)
        XCTAssertEqual(importStore.markedImports.map { $0.candidate.id }, [candidate.id])
    }

    @available(macOS 15.5, *)
    func testEnablingExtensionDoesNotRefreshFindings() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let importStore = RecordingSafariExtensionImportStore()
        let container = try makeTestContainer()
        let fixture = makeEnabledModule(
            context: container,
            importStore: importStore,
            defaults: harness.defaults
        )
        let scratchDirectory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchDirectory) }
        let installed = try await installUnpackedExtension(
            manager: fixture.manager,
            scratchDirectory: scratchDirectory,
            name: "ManualScanOnly"
        )

        _ = try await fixture.module.enableExtension(installed.id)

        XCTAssertTrue(importStore.refreshedCandidateBatches.isEmpty)
    }

    @available(macOS 15.5, *)
    func testUninstallSafariWebExtensionPreservesOriginalAppex() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let importStore = RecordingSafariExtensionImportStore()
        let container = try makeTestContainer()
        let fixture = makeEnabledModule(
            context: container,
            importStore: importStore,
            defaults: harness.defaults
        )
        let scratchDirectory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchDirectory) }
        let candidate = try makeSafariWebExtensionCandidate(
            bundleIdentifier: "com.example.preserved-source",
            in: scratchDirectory
        )
        let originalAppexPath = candidate.appexURL.path

        let installed = try await fixture.module.addSafariAppExtension(from: candidate)
        try await fixture.module.uninstallExtension(installed.id)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: originalAppexPath),
            "Uninstall must not delete the original Safari app extension"
        )
        XCTAssertTrue(
            fixture.inspection.actionSurfaces.installedExtensions.records.isEmpty
        )
        XCTAssertEqual(importStore.removedInstalledExtensionIds, [installed.id])
    }

    @available(macOS 15.5, *)
    func testAddSafariWebExtensionRejectsContentBlocker()
        async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let importStore = RecordingSafariExtensionImportStore()
        let container = try makeTestContainer()
        let fixture = makeEnabledModule(
            context: container,
            importStore: importStore,
            defaults: harness.defaults
        )
        let module = fixture.module
        let contentBlocker = makeCandidate(
            bundleIdentifier: "com.example.content-blocker",
            bundleKind: .contentBlocker,
            runtimeStatus: .contentBlockerImportable
        )

        do {
            _ = try await module.addSafariAppExtension(from: contentBlocker)
            XCTFail("Expected a non-WebExtension candidate to be rejected")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Only Safari Web Extensions"))
        }

        XCTAssertTrue(importStore.markedImports.isEmpty)
        XCTAssertTrue(
            fixture.inspection.actionSurfaces.installedExtensions.records.isEmpty
        )
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
        context: SumiDatabase,
        importStore: RecordingSafariExtensionImportStore,
        defaults: UserDefaults
    ) -> EnabledModuleFixture {
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: defaults)
        )
        registry.enable(.extensions)
        let profile = Profile(name: "Safari Sync Profile")
        let managerFixture = makeSafariExtensionManagerTestFixture(
            context: context,
            initialProfile: profile,
            moduleRegistry: registry
        )
        let browserManager = makeSafariExtensionTestBrowserManager(
            moduleRegistry: registry,
            profile: profile
        )
        let module = SumiExtensionsModule(
            moduleRegistry: registry,
            database: context,
            initialProfileProvider: { profile },
            safariExtensionImportStore: importStore,
            managerFactory: { _, _, _, _ in managerFixture.manager }
        )
        module.attach(
            runtime: BrowserExtensionsModuleRuntimeFactory.runtime(
                for: browserManager
            )
        )
        return EnabledModuleFixture(
            module: module,
            manager: managerFixture.manager,
            inspection: managerFixture.inspection,
            browserManager: browserManager
        )
    }

    private func makeSafariWebExtensionCandidate(
        bundleIdentifier: String,
        in scratchDirectory: URL
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

@available(macOS 15.5, *)
@MainActor
private struct EnabledModuleFixture {
    let module: SumiExtensionsModule
    let manager: ExtensionManager
    let inspection: ExtensionManagerTestInspection
    let browserManager: BrowserManager
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
