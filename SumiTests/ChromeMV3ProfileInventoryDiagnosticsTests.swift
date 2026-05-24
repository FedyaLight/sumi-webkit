import CryptoKit
import Foundation
import SwiftData
import XCTest

@testable import Sumi

final class ChromeMV3ProfileInventoryDiagnosticsTests: XCTestCase {
    private let fixedInstallDate = Date(timeIntervalSince1970: 1_700_000_000)
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testInventoryReaderDiscoversGeneratedRewrittenCandidateAndLoadabilityReport() throws {
        let fixture = try writeBundle(
            named: "inventory-password-manager",
            manifest: passwordManagerManifest(),
            files: passwordManagerFiles()
        )
        let variant = try writeVariant(for: fixture)
        let report = try readReport(from: variant.variantRootURL)

        let inventory = ChromeMV3CandidateInventoryReader()
            .readInventory(rootURL: fixture.storeRootURL)
        let candidate = try XCTUnwrap(inventory.candidates.first)

        XCTAssertEqual(inventory.stagedOriginalRecords.count, 1)
        XCTAssertEqual(inventory.generatedBundleRecords.count, 1)
        XCTAssertEqual(inventory.generatedRewriteApplicationReports.count, 1)
        XCTAssertEqual(inventory.runtimeLoadabilityReports.count, 1)
        XCTAssertEqual(candidate.generatedRootPath, fixture.result.generatedBundleRootURL.path)
        XCTAssertEqual(candidate.rewrittenRootPath, variant.variantRootURL.path)
        XCTAssertEqual(candidate.manifestHash, report.rewrittenManifestHash?.sha256)
        XCTAssertEqual(candidate.reportHash?.count, 64)
        XCTAssertEqual(candidate.runtimeLoadable, false)
        XCTAssertEqual(candidate.manifestVersion, 3)
        XCTAssertTrue(candidate.blockers.contains("WebKit runtime loading is not yet wired."))
        XCTAssertTrue(candidate.deferredAPIs.contains(.nativeMessaging))
        XCTAssertTrue(candidate.passwordManagerReadinessSummary?.contentScriptsPresent == true)
        XCTAssertTrue(candidate.missingArtifactWarnings.isEmpty)
        XCTAssertNotNil(candidate.runtimeLoadabilityReport)
    }

    func testInventoryReaderReportsMissingRuntimeLoadabilityReport() throws {
        let fixture = try writeBundle(
            named: "inventory-missing-loadability",
            manifest: serviceWorkerManifest(),
            files: [
                "background.js": "chrome.runtime.onInstalled.addListener(() => {});\n",
            ]
        )
        let variant = try writeVariant(for: fixture)
        try FileManager.default.removeItem(
            at: variant.variantRootURL.appendingPathComponent(
                ChromeMV3RuntimeLoadabilityVerifier.reportFileName
            )
        )

        let inventory = ChromeMV3CandidateInventoryReader()
            .readInventory(rootURL: fixture.storeRootURL)
        let candidate = try XCTUnwrap(inventory.candidates.first)

        XCTAssertNil(candidate.runtimeLoadabilityReport)
        XCTAssertEqual(candidate.runtimeLoadable, false)
        XCTAssertNil(candidate.reportHash)
        XCTAssertTrue(
            candidate.missingArtifactWarnings.contains {
                $0.contains("Missing runtime-loadability report")
            }
        )
    }

    func testInventoryReaderReportsRuntimeLoadableFalseAndBlockers() throws {
        let fixture = try writeBundle(
            named: "inventory-blockers",
            manifest: serviceWorkerManifest(),
            files: [
                "background.js": "chrome.runtime.onInstalled.addListener(() => {});\n",
            ]
        )
        _ = try writeVariant(for: fixture)

        let inventory = ChromeMV3CandidateInventoryReader()
            .readInventory(rootURL: fixture.storeRootURL)
        let candidate = try XCTUnwrap(inventory.candidates.first)

        XCTAssertEqual(candidate.runtimeLoadable, false)
        XCTAssertTrue(candidate.blockers.contains("Runtime messaging is not implemented."))
        XCTAssertTrue(candidate.blockers.contains("WebKit runtime loading is not yet wired."))
    }

    func testInventoryReaderDoesNotMutateFiles() throws {
        let fixture = try writeBundle(
            named: "inventory-readonly",
            manifest: serviceWorkerManifest(),
            files: [
                "background.js": "chrome.runtime.onInstalled.addListener(() => {});\n",
            ]
        )
        _ = try writeVariant(for: fixture)
        let before = try fileHashes(rootURL: fixture.storeRootURL)

        _ = ChromeMV3CandidateInventoryReader()
            .readInventory(rootURL: fixture.storeRootURL)

        let after = try fileHashes(rootURL: fixture.storeRootURL)
        XCTAssertEqual(after, before)
    }

    func testProfileHostDiagnosticsCombineCandidatePreflightAndSurfaceMapping() throws {
        let fixture = try writeBundle(
            named: "inventory-diagnostics",
            manifest: serviceWorkerManifest(),
            files: [
                "background.js": "chrome.runtime.onInstalled.addListener(() => {});\n",
            ]
        )
        _ = try writeVariant(for: fixture)
        let inventory = ChromeMV3CandidateInventoryReader()
            .readInventory(rootURL: fixture.storeRootURL)
        let host = ChromeMV3ProfileHost(
            profileIdentifier: "profile-inventory",
            extensionsEnabled: true,
            profileDataStoreIdentity: .profileIdentifier("profile-inventory"),
            candidateRewrittenVariants: inventory.candidates
                .map(\.profileHostCandidate)
        )

        let diagnostics = host.diagnostics(candidateInventory: inventory)

        XCTAssertEqual(diagnostics.preflightResults.count, 1)
        XCTAssertFalse(diagnostics.canCreateControllerNow)
        XCTAssertFalse(diagnostics.canLoadContextNow)
        XCTAssertFalse(diagnostics.canAttachToNormalTabsNow)
        XCTAssertTrue(diagnostics.attachableSurfacesNow.isEmpty)
        XCTAssertTrue(diagnostics.futureEligibleSurfaces.contains(.normalTab))
        XCTAssertTrue(
            diagnostics.futureEligibleSurfaces
                .contains(.pinnedEssentialsLiveNormalBrowsing)
        )
        XCTAssertTrue(
            diagnostics.futureExtensionUIHostOnlySurfaces
                .contains(.extensionOwnedPopup)
        )
        XCTAssertTrue(diagnostics.ineligibleSurfaces.contains(.faviconDownload))
        XCTAssertTrue(
            diagnostics.blockingReasons.contains(
                "Normal-tab attachment is intentionally blocked by the non-loading host skeleton."
            )
        )
        XCTAssertTrue(
            diagnostics.disabledRuntimeInvariantStatus
                .noControllerAttachedToConfigurations
        )
    }

    @MainActor
    func testDisabledModuleInventoryDiagnosticsReturnNilAndDoNotCreateManager() throws {
        let rootURL = try makeTemporaryDirectory()
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = InventoryDiagnosticsRuntimeProbe()
        let module = try makeExtensionsModule(registry: registry, probe: probe)

        let diagnostics = module.chromeMV3InventoryDiagnosticsIfEnabled(
            rootURL: rootURL
        )

        XCTAssertNil(diagnostics)
        XCTAssertEqual(probe.managerCount, 0)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testNormalTabAndPinnedLiveMappingsAreFutureEligibleButNotAttachableNow() throws {
        let diagnostics = surfaceDiagnostics()
        let normal = try mapping("tab.normal.primary", in: diagnostics)
        let clone = try mapping("tab.normal.clone", in: diagnostics)
        let pinnedLive = try mapping(
            "shortcut.live.normalBrowsing",
            in: diagnostics
        )

        for item in [normal, clone, pinnedLive] {
            XCTAssertEqual(item.futureEligibility, .futureEligible)
            XCTAssertEqual(item.currentEligibility.status, .futureEligible)
            XCTAssertFalse(item.controllerAttachmentAllowedNow)
            XCTAssertTrue(item.futureAttachmentRequiresEnabledModule)
            XCTAssertFalse(item.futureAttachmentRequiresNormalBrowsingPromotion)
        }
    }

    func testLauncherPreviewMiniAndHelperSurfaceMappingsAreIneligible() throws {
        let diagnostics = surfaceDiagnostics()
        let launcher = try mapping("shortcut.launcher.metadata", in: diagnostics)
        let glance = try mapping("glance.preview.tab", in: diagnostics)
        let mini = try mapping("miniWindow.oauth.webView", in: diagnostics)
        let favicon = try mapping("favicon.temporaryDownload", in: diagnostics)
        let download = try mapping("download.retry.currentTab", in: diagnostics)
        let helper = try mapping("miniWindow.popup.inlineLoad", in: diagnostics)

        XCTAssertEqual(launcher.futureEligibility, .neverEligible)
        XCTAssertEqual(glance.futureEligibility, .notEligible)
        XCTAssertTrue(glance.futureAttachmentRequiresNormalBrowsingPromotion)
        XCTAssertEqual(mini.futureEligibility, .notEligible)
        XCTAssertTrue(mini.futureAttachmentRequiresNormalBrowsingPromotion)
        XCTAssertEqual(favicon.futureEligibility, .neverEligible)
        XCTAssertEqual(download.futureEligibility, .neverEligible)
        XCTAssertEqual(helper.futureEligibility, .neverEligible)
        XCTAssertFalse(
            [launcher, glance, mini, favicon, download, helper].contains {
                $0.controllerAttachmentAllowedNow
            }
        )
    }

    func testExtensionOwnedAndWebKitPopupMappingsRequireFutureHostsOrPromotion() throws {
        let diagnostics = surfaceDiagnostics()
        let options = try mapping("extension.options.window", in: diagnostics)
        let actionPopup = try mapping("extension.action.popup", in: diagnostics)
        let webKitPopup = try mapping("tab.webKitPopup.delegate", in: diagnostics)

        XCTAssertEqual(
            options.futureEligibility,
            .futureEligibleThroughExtensionUIHostOnly
        )
        XCTAssertTrue(options.futureAttachmentRequiresExtensionUIHost)
        XCTAssertEqual(
            actionPopup.futureEligibility,
            .futureEligibleThroughExtensionUIHostOnly
        )
        XCTAssertTrue(actionPopup.futureAttachmentRequiresExtensionUIHost)
        XCTAssertEqual(
            webKitPopup.futureEligibility,
            .eligibleAfterPromotionAndReevaluation
        )
        XCTAssertTrue(webKitPopup.futureAttachmentRequiresNormalBrowsingPromotion)
        XCTAssertFalse(webKitPopup.controllerAttachmentAllowedNow)
    }

    func testSurfaceDiagnosticsKeepAttachableSurfacesAndControllerGatesClosed() {
        let host = ChromeMV3ProfileHost(
            profileIdentifier: "surface-gates",
            extensionsEnabled: true
        )
        let diagnostics = host.diagnostics()

        XCTAssertTrue(diagnostics.attachableSurfacesNow.isEmpty)
        XCTAssertFalse(diagnostics.canCreateControllerNow)
        XCTAssertFalse(diagnostics.canLoadContextNow)
        XCTAssertFalse(diagnostics.canAttachToNormalTabsNow)
        XCTAssertTrue(
            diagnostics.webViewSurfaceMappings.allSatisfy {
                $0.controllerAttachmentAllowedNow == false
            }
        )
    }

    func testSourceGuardsForInventoryAndSurfaceMappingFiles() throws {
        let source = try [
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3CandidateInventory.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3WebViewSurfaceInventory.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3ProfileHost.swift",
        ]
            .map { try Self.source(named: $0) }
            .joined(separator: "\n")

        for forbidden in [
            "import " + "WebKit",
            "WKWebExtension" + "(",
            "WKWebExtension" + "Controller(",
            "WKWebExtension" + "Context(",
            "load" + "ExtensionContext",
            "webExtensionController" + " =",
            "add" + "UserScript",
            "connect" + "Native",
            "DispatchSource" + "Ti" + "mer",
            "Ti" + "mer",
        ] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }
    }

    private func surfaceDiagnostics()
        -> [ChromeMV3WebViewSurfaceMappingDiagnostic]
    {
        ChromeMV3WebViewSurfaceInventory.diagnostics(
            extensionModuleEnabled: true,
            profileHostActive: true
        )
    }

    private func mapping(
        _ siteID: String,
        in diagnostics: [ChromeMV3WebViewSurfaceMappingDiagnostic]
    ) throws -> ChromeMV3WebViewSurfaceMappingDiagnostic {
        try XCTUnwrap(diagnostics.first { $0.siteID == siteID }, siteID)
    }

    private struct InventoryFixture {
        var storeRootURL: URL
        var stage: ChromeMV3OriginalBundleStageResult
        var result: ChromeMV3GeneratedBundleWriteResult
        var runtimeResourcePlan: ChromeMV3RuntimeResourcePlan
        var preview: ChromeMV3ManifestRewritePreview
        var dryRunReport: ChromeMV3ManifestRewriteDryRunVerificationReport
    }

    private func writeBundle(
        named name: String,
        manifest: [String: Any],
        files: [String: String]
    ) throws -> InventoryFixture {
        let sourceURL = try makeFixture(
            named: name,
            manifest: manifest,
            files: files
        )
        let storeRootURL = try makeTemporaryDirectory()
        let stage = try ChromeMV3OriginalBundleStore(
            rootURL: storeRootURL,
            now: { self.fixedInstallDate }
        ).stageUnpackedDirectory(at: sourceURL)
        let result = try ChromeMV3GeneratedBundleWriter(rootURL: storeRootURL)
            .writeGeneratedBundle(
                originalBundleRecord: stage.originalBundleRecord,
                manifestSnapshot: stage.manifestSnapshot,
                planningRecord: stage.generatedBundlePlan
            )
        let decoder = JSONDecoder()
        let runtimeResourcePlan = try decoder.decode(
            ChromeMV3RuntimeResourcePlan.self,
            from: Data(
                contentsOf: result.generatedBundleRootURL
                    .appendingPathComponent("runtime-resource-plan.json")
            )
        )
        let preview = try decoder.decode(
            ChromeMV3ManifestRewritePreview.self,
            from: Data(contentsOf: result.manifestRewritePreviewURL)
        )
        let dryRunReport = try decoder.decode(
            ChromeMV3ManifestRewriteDryRunVerificationReport.self,
            from: Data(contentsOf: result.manifestRewriteDryRunReportURL)
        )
        return InventoryFixture(
            storeRootURL: storeRootURL,
            stage: stage,
            result: result,
            runtimeResourcePlan: runtimeResourcePlan,
            preview: preview,
            dryRunReport: dryRunReport
        )
    }

    private func writeVariant(
        for fixture: InventoryFixture
    ) throws -> ChromeMV3GeneratedRewriteVariantWriteResult {
        try ChromeMV3GeneratedRewriteVariantWriter().writeRewrittenVariant(
            generatedBundleRecord: fixture.result.record,
            generatedBundleRootURL: fixture.result.generatedBundleRootURL,
            runtimeResourcePlan: fixture.runtimeResourcePlan,
            manifestRewritePreview: fixture.preview,
            dryRunReport: fixture.dryRunReport
        )
    }

    private func serviceWorkerManifest() -> [String: Any] {
        [
            "manifest_version": 3,
            "name": "Minimal MV3",
            "version": "1.0.0",
            "background": [
                "service_worker": "background.js",
            ],
        ]
    }

    private func passwordManagerManifest() -> [String: Any] {
        [
            "manifest_version": 3,
            "name": "Password Manager Fixture",
            "version": "2.3.4",
            "background": [
                "service_worker": "background.js",
            ],
            "permissions": [
                "nativeMessaging",
                "storage",
            ],
            "host_permissions": [
                "https://*/*",
            ],
            "content_scripts": [
                [
                    "matches": ["https://*/*"],
                    "js": ["content.js"],
                    "all_frames": true,
                    "match_about_blank": true,
                    "match_origin_as_fallback": true,
                    "run_at": "document_start",
                    "world": "ISOLATED",
                ],
            ],
            "action": [
                "default_popup": "popup.html",
            ],
        ]
    }

    private func passwordManagerFiles() -> [String: String] {
        [
            "background.js": "chrome.runtime.onMessage.addListener(() => {});\n",
            "content.js": "document.documentElement.dataset.sumiFixture = 'password';\n",
            "popup.html": "<!doctype html><title>Password Manager</title>\n",
        ]
    }

    private func makeFixture(
        named name: String,
        manifest: [String: Any],
        files: [String: String]
    ) throws -> URL {
        let directory = try makeTemporaryDirectory()
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try manifestData.write(
            to: directory.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )

        for (relativePath, contents) in files {
            let fileURL = directory.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        return directory
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(directory)
        return directory
    }

    private func readReport(
        from variantRootURL: URL
    ) throws -> ChromeMV3RuntimeLoadabilityReport {
        try JSONDecoder().decode(
            ChromeMV3RuntimeLoadabilityReport.self,
            from: Data(
                contentsOf: variantRootURL.appendingPathComponent(
                    ChromeMV3RuntimeLoadabilityVerifier.reportFileName
                )
            )
        )
    }

    private func fileHashes(rootURL: URL) throws -> [String: String] {
        let root = rootURL.standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                ]
            )
        )
        var hashes: [String: String] = [:]

        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                continue
            }
            let data = try Data(contentsOf: url)
            let relativePath = String(
                url.standardizedFileURL.path.dropFirst(rootPath.count)
            )
            hashes[relativePath] = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
        }
        return hashes
    }

    @MainActor
    private func makeExtensionsModule(
        registry: SumiModuleRegistry,
        probe: InventoryDiagnosticsRuntimeProbe
    ) throws -> SumiExtensionsModule {
        let container = try ModelContainer(
            for: Schema([ExtensionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let initialProfile = Profile(name: "Chrome MV3 Inventory Test")
        return SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: BrowserConfiguration(),
            initialProfileProvider: { initialProfile },
            managerFactory: { context, initialProfile, browserConfiguration in
                probe.managerCount += 1
                return ExtensionManager(
                    context: context,
                    initialProfile: initialProfile,
                    browserConfiguration: browserConfiguration
                )
            }
        )
    }

    private static func source(named relativePath: String) throws -> String {
        let sourceURL = repoRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private final class InventoryDiagnosticsRuntimeProbe {
    var managerCount = 0
}
