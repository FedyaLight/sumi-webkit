import Foundation
import XCTest

@testable import Sumi

final class ChromeMV3CompatibilityDiagnosticsTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_710_000_000)
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testViewModelRendersLifecycleBundleMatrixAndProductFlags() throws {
        let root = try temporaryDirectory()
        let source = try makeFixture(
            named: "view-model",
            manifest: blockerHeavyManifest(),
            files: [
                "background.js": "",
                "content.js": "",
                "panel.html": "<!doctype html><title>Panel</title>\n",
                "rules.json": "[]",
            ]
        )
        let registry = makeRegistry(rootURL: root)
        let install = registry.installUnpackedExtension(
            at: source,
            profileID: "profile-view",
            runtimeDiagnostics: fullRuntimeDiagnostics()
        )
        let record = try XCTUnwrap(install.record)

        let viewModel = try XCTUnwrap(
            registry.compatibilityReportViewModel(
                profileID: record.profileID,
                extensionID: record.extensionID
            )
        )

        XCTAssertEqual(viewModel.extensionIdentity.displayName, "Blocker Heavy")
        XCTAssertEqual(viewModel.lifecycleState, .diagnosticsReady)
        XCTAssertEqual(viewModel.generatedBundleState.activeVersionID, record.activeGeneratedVersionID)
        XCTAssertEqual(viewModel.generatedBundleState.versions.count, 1)
        XCTAssertFalse(viewModel.productFlags.productRuntimeAvailable)
        XCTAssertFalse(viewModel.productFlags.normalTabRuntimeBridgeAvailable)
        XCTAssertFalse(viewModel.productFlags.runtimeLoadable)
        XCTAssertFalse(viewModel.productFlags.productExtensionUIAvailable)
        XCTAssertFalse(viewModel.productFlags.productNetworkEnforcementAvailable)
        XCTAssertTrue(viewModel.productFlags.internalDiagnosticsUIAvailable)
        XCTAssertTrue(viewModel.productFlags.developerPreviewLifecycleAvailable)
        XCTAssertTrue(viewModel.productFlags.internalSyntheticRuntimeDiagnosticsAvailable)

        let matrix = Dictionary(uniqueKeysWithValues: viewModel.apiSupportMatrix.map {
            ($0.id, $0)
        })
        XCTAssertTrue(Set(matrix.keys).isSuperset(of: expectedMatrixIDs()))
        XCTAssertTrue(matrix["runtime"]?.statuses.contains(.internalSyntheticReady) == true)
        XCTAssertTrue(matrix["runtime"]?.statuses.contains(.productBlocked) == true)
        let storageLocal = try XCTUnwrap(matrix["storage.local"])
        XCTAssertTrue(
            storageLocal.statuses.contains(.internalSyntheticReady),
            "storage.local statuses: \(storageLocal.statuses)"
        )
        XCTAssertTrue(matrix["storage.sync"]?.statuses.contains(.deferred) == true)
        XCTAssertTrue(matrix["nativeMessaging"]?.statuses.contains(.fixtureOnly) == true)
        XCTAssertTrue(matrix["declarativeNetRequest"]?.statuses.contains(.fixtureOnly) == true)
        XCTAssertTrue(matrix["webRequest"]?.statuses.contains(.productBlocked) == true)
        XCTAssertTrue(matrix["sidePanel"]?.statuses.contains(.webKitSyntheticExecuted) == true)
        XCTAssertTrue(matrix["offscreen"]?.statuses.contains(.webKitSyntheticExecuted) == true)
        XCTAssertTrue(matrix["identity"]?.statuses.contains(.webKitSyntheticExecuted) == true)
        XCTAssertTrue(matrix["activeTab"]?.statuses.contains(.notRequired) == true)
    }

    func testViewModelGroupsBlockersBySeveritySourceAPIManifestAndResource()
        throws
    {
        let root = try temporaryDirectory()
        let source = try makeFixture(
            named: "blockers",
            manifest: blockerHeavyManifest(),
            files: [
                "background.js": "",
                "content.js": "",
                "panel.html": "<!doctype html><title>Panel</title>\n",
                "rules.json": "[]",
            ]
        )
        let registry = makeRegistry(rootURL: root)
        let install = registry.installUnpackedExtension(
            at: source,
            profileID: "profile-blockers",
            runtimeDiagnostics: fullRuntimeDiagnostics()
        )
        let record = try XCTUnwrap(install.record)
        let viewModel = try XCTUnwrap(
            registry.compatibilityReportViewModel(
                profileID: record.profileID,
                extensionID: record.extensionID
            )
        )

        XCTAssertTrue(viewModel.blockersBySeverity.contains {
            $0.key == ChromeMV3APIBlockerSeverity.productBlocked.rawValue
        })
        let sourceKeys = Set(viewModel.blockersBySource.map(\.key))
        XCTAssertTrue(sourceKeys.isSuperset(of: [
            ChromeMV3APIBlockerSource.network.rawValue,
            ChromeMV3APIBlockerSource.sidePanel.rawValue,
            ChromeMV3APIBlockerSource.offscreen.rawValue,
            ChromeMV3APIBlockerSource.identity.rawValue,
            ChromeMV3APIBlockerSource.nativeMessaging.rawValue,
            ChromeMV3APIBlockerSource.serviceWorker.rawValue,
            ChromeMV3APIBlockerSource.runtimeGate.rawValue,
        ]))
        XCTAssertTrue(viewModel.blockersByAPI.contains {
            $0.key.contains(ChromeMV3API.webRequest.rawValue)
        })
        XCTAssertTrue(viewModel.blockersByManifestKey.contains {
            $0.key == "background.service_worker"
        })
        XCTAssertTrue(viewModel.blockersByResourcePath.contains {
            $0.key == "panel.html"
        })
    }

    func testInternalActionsAndDiagnosticsSurfaceStayInternalOnly() throws {
        let root = try temporaryDirectory()
        let source = try makeFixture(
            named: "actions",
            manifest: minimalManifest(version: "1.0.0"),
            files: ["background.js": ""]
        )
        let registry = makeRegistry(rootURL: root)
        let install = registry.installUnpackedExtension(
            at: source,
            profileID: "profile-actions",
            runtimeDiagnostics: fullRuntimeDiagnostics()
        )
        let record = try XCTUnwrap(install.record)
        let viewModel = try XCTUnwrap(
            registry.compatibilityReportViewModel(
                profileID: record.profileID,
                extensionID: record.extensionID
            )
        )

        XCTAssertTrue(viewModel.internalLifecycleActions.allSatisfy(\.internalOnly))
        XCTAssertTrue(viewModel.internalLifecycleActions.allSatisfy(\.requiresEnabledModule))
        XCTAssertTrue(viewModel.internalLifecycleActions.contains {
            $0.action == .updateFromSource && $0.mutatesLifecycle
        })
        XCTAssertTrue(viewModel.internalLifecycleActions.contains {
            $0.action == .exportReportJSON && $0.mutatesLifecycle == false
        })
        #if DEBUG
            XCTAssertTrue(ChromeMV3InternalDiagnosticsGate.uiAvailable)
        #endif
        XCTAssertEqual(
            Set(SumiExtensionsSettingsSubPane.allCases),
            Set([.extensions, .userScripts])
        )
    }

    @MainActor
    func testDisabledModuleBlocksDiagnosticsAndWritesNoArtifacts() throws {
        let root = try temporaryDirectory()
        let module = try makeModule(enabled: false)

        XCTAssertNil(
            module.chromeMV3ListInternalCompatibilityDiagnosticsIfEnabled(
                rootURL: root
            )
        )
        XCTAssertNil(
            module.chromeMV3CompatibilityReportViewModelIfEnabled(
                rootURL: root,
                profileID: "profile-disabled",
                extensionID: "extension-disabled"
            )
        )
        XCTAssertNil(
            module.chromeMV3RunArtifactCleanupIfEnabled(
                rootURL: root,
                profileID: "profile-disabled",
                extensionID: "extension-disabled"
            )
        )
        XCTAssertNil(
            module.chromeMV3RunFinalFoundationReadinessReportIfEnabled(
                rootURL: root,
                profileID: "profile-disabled",
                extensionID: "extension-disabled"
            )
        )
        XCTAssertNil(
            module.chromeMV3ExportCompatibilityReportJSONIfEnabled(
                rootURL: root,
                profileID: "profile-disabled",
                extensionID: "extension-disabled"
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("lifecycle").path
            )
        )
    }

    func testFinalReadinessRequiresInternalSubsystemReports() throws {
        let root = try temporaryDirectory()
        let source = try makeFixture(
            named: "readiness",
            manifest: blockerHeavyManifest(),
            files: [
                "background.js": "",
                "content.js": "",
                "panel.html": "<!doctype html><title>Panel</title>\n",
                "rules.json": "[]",
            ]
        )
        let registry = makeRegistry(rootURL: root)
        let install = registry.installUnpackedExtension(
            at: source,
            profileID: "profile-readiness"
        )
        let record = try XCTUnwrap(install.record)

        let partial = try XCTUnwrap(
            registry.writeFoundationReadinessReport(
                profileID: record.profileID,
                extensionID: record.extensionID
            )
        )
        XCTAssertFalse(partial.finalPhaseStatus.internalDeveloperPreviewReady)
        XCTAssertEqual(partial.finalPhaseStatus.readinessLevel, .partial)
        XCTAssertFalse(partial.missingRequiredInternalReports.isEmpty)
        XCTAssertFalse(partial.finalPhaseStatus.productRuntimeAvailable)
        XCTAssertFalse(partial.finalPhaseStatus.normalTabRuntimeBridgeAvailable)
        XCTAssertFalse(partial.finalPhaseStatus.runtimeLoadable)
        XCTAssertFalse(partial.finalPhaseStatus.productExtensionUIAvailable)
        XCTAssertFalse(partial.finalPhaseStatus.productNetworkEnforcementAvailable)

        _ = registry.writeEndToEndDiagnostics(
            profileID: record.profileID,
            extensionID: record.extensionID,
            runtimeDiagnostics: fullRuntimeDiagnostics()
        )
        let ready = try XCTUnwrap(
            registry.writeFoundationReadinessReport(
                profileID: record.profileID,
                extensionID: record.extensionID
            )
        )
        XCTAssertTrue(ready.finalPhaseStatus.internalDeveloperPreviewReady)
        XCTAssertEqual(ready.finalPhaseStatus.readinessLevel, .ready)
        XCTAssertTrue(ready.missingRequiredInternalReports.isEmpty)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: reportPath(
                    root: root,
                    profileID: record.profileID,
                    extensionID: record.extensionID,
                    fileName: ChromeMV3FoundationReadinessReport.fileName
                )
            )
        )
    }

    func testArtifactCleanupRemovesFailedCandidatesPreservesWorkingVersionsAndDiagnosesCorruptReport()
        throws
    {
        let root = try temporaryDirectory()
        let registry = makeRegistry(rootURL: root)
        let first = try makeFixture(
            named: "cleanup-v1",
            manifest: minimalManifest(version: "1.0.0"),
            files: ["background.js": "const version = 1;\n"]
        )
        let install = registry.installUnpackedExtension(
            at: first,
            profileID: "profile-cleanup"
        )
        let installed = try XCTUnwrap(install.record)
        let second = try makeFixture(
            named: "cleanup-v2",
            manifest: minimalManifest(version: "2.0.0"),
            files: ["background.js": "const version = 2;\n"]
        )
        let update = registry.updateExtension(
            profileID: installed.profileID,
            extensionID: installed.extensionID,
            from: second
        )
        var record = try XCTUnwrap(update.record)
        let activeID = try XCTUnwrap(record.activeGeneratedVersionID)
        let previousID = try XCTUnwrap(record.previousWorkingGeneratedVersionID)
        let templateVersion = try XCTUnwrap(record.generatedBundleVersions.first)
        let failedRoot = root.appendingPathComponent("failed-candidate", isDirectory: true)
        let candidateRoot = root.appendingPathComponent("stale-candidate", isDirectory: true)
        try FileManager.default.createDirectory(at: failedRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: candidateRoot, withIntermediateDirectories: true)
        var failed = templateVersion
        failed.id = "generated-version-failed"
        failed.sequence = 900
        failed.state = .failed
        failed.versionRootPath = failedRoot.path
        var candidate = templateVersion
        candidate.id = "generated-version-candidate"
        candidate.sequence = 901
        candidate.state = .candidate
        candidate.versionRootPath = candidateRoot.path
        record.generatedBundleVersions.append(contentsOf: [failed, candidate])
        record.candidateGeneratedVersionID = candidate.id
        record.runtimeState.internalRuntimeEnabled = true
        record.runtimeState.syntheticHarnessStatePresent = true
        record.runtimeState.sharedLifecycleSessionActive = true
        record.runtimeState.nativeFixturePortOpen = true
        record.runtimeState.storageStatePresent = true
        record.runtimeState.permissionsStatePresent = true
        try writeRecord(record)
        _ = registry.writeCrashMarker(
            profileID: record.profileID,
            extensionID: record.extensionID,
            reason: "cleanup test",
            lifecycleSessionLeftActive: true,
            nativeFixturePortLeftOpen: true
        )
        try "{".write(
            to: URL(
                fileURLWithPath: reportPath(
                    root: root,
                    profileID: record.profileID,
                    extensionID: record.extensionID,
                    fileName: ChromeMV3ExtensionLifecycleRegistry
                        .diagnosticsReportFileName
                )
            ),
            atomically: true,
            encoding: .utf8
        )

        let cleanup = try XCTUnwrap(
            registry.runArtifactCleanup(
                profileID: record.profileID,
                extensionID: record.extensionID
            )
        )
        let cleaned = try XCTUnwrap(
            registry.loadLifecycleRecord(
                profileID: record.profileID,
                extensionID: record.extensionID
            )
        )

        XCTAssertEqual(
            Set(cleanup.removedGeneratedVersionIDs),
            Set([failed.id, candidate.id])
        )
        XCTAssertEqual(
            Set(cleanup.preservedGeneratedVersionIDs),
            Set([activeID, previousID])
        )
        XCTAssertTrue(cleanup.corruptReportRemoved)
        XCTAssertTrue(cleanup.crashMarkerRemoved)
        XCTAssertTrue(cleanup.internalRuntimeStateReset)
        XCTAssertFalse(cleanup.productProfileDataDeleted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: failedRoot.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: candidateRoot.path))
        XCTAssertEqual(cleaned.activeGeneratedVersionID, activeID)
        XCTAssertEqual(cleaned.previousWorkingGeneratedVersionID, previousID)
        XCTAssertNil(cleaned.candidateGeneratedVersionID)
        XCTAssertFalse(cleaned.runtimeState.internalRuntimeEnabled)
        XCTAssertFalse(cleaned.runtimeState.sharedLifecycleSessionActive)
        XCTAssertFalse(cleaned.runtimeState.nativeFixturePortOpen)
    }

    func testThreatModelPerformanceBudgetAndRuntimeGuardAreDeterministic()
        throws
    {
        let firstThreat = ChromeMV3ThreatModelChecklistReport
            .currentInternalDeveloperPreview()
        let secondThreat = ChromeMV3ThreatModelChecklistReport
            .currentInternalDeveloperPreview()
        let firstBudget = ChromeMV3PerformanceBudgetReport
            .currentInternalDeveloperPreview()
        let secondBudget = ChromeMV3PerformanceBudgetReport
            .currentInternalDeveloperPreview()

        XCTAssertEqual(
            try ChromeMV3DeterministicJSON.encodedString(firstThreat),
            try ChromeMV3DeterministicJSON.encodedString(secondThreat)
        )
        XCTAssertEqual(
            try ChromeMV3DeterministicJSON.encodedString(firstBudget),
            try ChromeMV3DeterministicJSON.encodedString(secondBudget)
        )
        XCTAssertFalse(firstThreat.passed)
        XCTAssertTrue(firstThreat.trustBoundaries.contains {
            $0.id == "identity-token-boundary" && $0.status == .blocked
        })
        XCTAssertTrue(firstBudget.passed)
        XCTAssertTrue(firstBudget.items.contains {
            $0.id == "normal-tabs-zero-overhead" && $0.status == .pass
        })
        XCTAssertTrue(ChromeMV3ProductRuntimeHardeningGuardReport.blocked.passes)
        XCTAssertFalse(ChromeMV3ProductRuntimeHardeningGuardReport.blocked.runtimeLoadable)
        XCTAssertFalse(ChromeMV3ProductRuntimeHardeningGuardReport.blocked.productRuntimeAvailable)
        XCTAssertFalse(ChromeMV3ProductRuntimeHardeningGuardReport.blocked.productRuntimeExposed)
    }

    func testDiagnosticsHardeningSourceGuardsStayProductBlocked() throws {
        let diagnosticsSource = try source(
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3CompatibilityDiagnostics.swift"
        )
        let moduleSource = try source(
            "Sumi/Managers/ExtensionManager/SumiExtensionsModule.swift"
        )
        let forbiddenScheduling = ["Ti" + "mer", "DispatchSource" + "Ti" + "mer"]
        for token in forbiddenScheduling {
            XCTAssertFalse(diagnosticsSource.contains(token), token)
        }
        XCTAssertFalse(diagnosticsSource.contains("Process" + "("))
        XCTAssertFalse(diagnosticsSource.contains("Browser" + "Config"))
        XCTAssertFalse(diagnosticsSource.contains("webExtension" + "Controller"))
        XCTAssertFalse(diagnosticsSource.contains("addUser" + "Script"))
        XCTAssertFalse(diagnosticsSource.contains("addScript" + "MessageHandler"))
        XCTAssertFalse(diagnosticsSource.contains("NS" + "Window"))
        XCTAssertFalse(diagnosticsSource.contains("NS" + "Panel"))
        XCTAssertFalse(diagnosticsSource.contains("NS" + "Menu"))
        XCTAssertFalse(diagnosticsSource.contains("WK" + "ContentRuleList"))
        XCTAssertFalse(diagnosticsSource.contains("URL" + "Session"))
        XCTAssertFalse(diagnosticsSource.contains("ASWeb" + "AuthenticationSession"))
        XCTAssertFalse(diagnosticsSource.contains("Chrome " + "Web " + "Store"))
        XCTAssertFalse(diagnosticsSource.lowercased().contains("web" + "store"))
        XCTAssertFalse(moduleSource.contains("runtimeLoadable = " + "tr" + "ue"))
        XCTAssertFalse(moduleSource.contains("productRuntimeAvailable = " + "tr" + "ue"))
        try assertProductFlagsNeverEnabled(
            sources: [diagnosticsSource, moduleSource]
        )
        try assertProcessUseRemainsConfined()
    }

    private func makeRegistry(
        rootURL: URL
    ) -> ChromeMV3ExtensionLifecycleRegistry {
        ChromeMV3ExtensionLifecycleRegistry(
            rootURL: rootURL,
            now: { self.fixedDate }
        )
    }

    @MainActor
    private func makeModule(enabled: Bool) throws -> SumiExtensionsModule {
        let harness = TestDefaultsHarness()
        let registry = SumiModuleRegistry(
            settingsStore:
                SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.setEnabled(enabled, for: .extensions)
        return SumiExtensionsModule(moduleRegistry: registry)
    }

    private func fullRuntimeDiagnostics()
        -> ChromeMV3LifecycleRuntimeDiagnosticsSnapshot
    {
        ChromeMV3LifecycleRuntimeDiagnosticsSnapshot(
            WebKitObjectDiagnosticsAvailable: true,
            contextCreationGateDiagnosticsAvailable: true,
            controllerLoadGateDiagnosticsAvailable: true,
            runtimeBridgeReadinessDiagnosticsAvailable: true,
            runtimeJSMessagingDiagnosticsAvailable: true,
            tabsScriptingDiagnosticsAvailable: true,
            permissionsDiagnosticsAvailable: true,
            storageDiagnosticsAvailable: true,
            nativeMessagingDiagnosticsAvailable: true,
            serviceWorkerDiagnosticsAvailable: true,
            eventAPIDiagnosticsAvailable: true,
            networkDiagnosticsAvailable: true,
            sidePanelOffscreenIdentityDiagnosticsAvailable: true,
            passwordManagerDiagnosticsAvailable: true,
            diagnostics: [
                "All internal synthetic diagnostic reports were supplied by the focused test.",
            ]
        )
    }

    private func expectedMatrixIDs() -> Set<String> {
        [
            "runtime",
            "tabs",
            "scripting",
            "permissions",
            "activeTab",
            "storage.local",
            "storage.sync",
            "nativeMessaging",
            "serviceWorkerLifecycle",
            "contextMenus",
            "alarms",
            "webNavigation",
            "declarativeNetRequest",
            "webRequest",
            "sidePanel",
            "offscreen",
            "identity",
            "action popup/options",
            "content scripts",
            "extension pages",
        ]
    }

    private func minimalManifest(version: String) -> [String: Any] {
        [
            "manifest_version": 3,
            "name": "Minimal MV3",
            "version": version,
            "background": [
                "service_worker": "background.js",
            ],
        ]
    }

    private func blockerHeavyManifest() -> [String: Any] {
        [
            "manifest_version": 3,
            "name": "Blocker Heavy",
            "version": "1.0",
            "permissions": [
                "declarativeNetRequest",
                "webRequest",
                "webRequestBlocking",
                "sidePanel",
                "offscreen",
                "identity",
                "nativeMessaging",
                "storage",
            ],
            "host_permissions": ["https://example.com/*"],
            "background": [
                "service_worker": "background.js",
            ],
            "content_scripts": [
                [
                    "matches": ["https://example.com/*"],
                    "js": ["content.js"],
                ],
            ],
            "declarative_net_request": [
                "rule_resources": [
                    [
                        "id": "rules_1",
                        "enabled": true,
                        "path": "rules.json",
                    ],
                ],
            ],
            "side_panel": [
                "default_path": "panel.html",
            ],
            "oauth2": [
                "client_id": "fixture",
                "scopes": ["email"],
            ],
            "action": [
                "default_popup": "panel.html",
            ],
        ]
    }

    private func makeFixture(
        named name: String,
        manifest: [String: Any],
        files: [String: String]
    ) throws -> URL {
        let directory = try temporaryDirectory()
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

    private func reportPath(
        root: URL,
        profileID: String,
        extensionID: String,
        fileName: String
    ) -> String {
        root
            .appendingPathComponent("lifecycle", isDirectory: true)
            .appendingPathComponent("reports", isDirectory: true)
            .appendingPathComponent(profileID, isDirectory: true)
            .appendingPathComponent(extensionID, isDirectory: true)
            .appendingPathComponent(fileName)
            .path
    }

    private func writeRecord(
        _ record: ChromeMV3ExtensionLifecycleRecord
    ) throws {
        try ChromeMV3DeterministicJSON.write(
            record,
            to: URL(fileURLWithPath: record.reportPaths.registryRecordPath)
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(directory)
        return directory
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: projectRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func assertProductFlagsNeverEnabled(sources: [String]) throws {
        let enabledWord = "tr" + "ue"
        let patterns = [
            "productRuntimeAvailable.*\(enabledWord)",
            "normalTabRuntimeBridgeAvailable.*\(enabledWord)",
            "runtimeLoadable.*\(enabledWord)",
            "productExtensionUIAvailable.*\(enabledWord)",
            "productNetworkEnforcementAvailable.*\(enabledWord)",
            "productRuntimeExposed.*\(enabledWord)",
        ]
        for source in sources {
            for pattern in patterns {
                let regex = try NSRegularExpression(pattern: pattern)
                let range = NSRange(source.startIndex..., in: source)
                XCTAssertEqual(regex.numberOfMatches(in: source, range: range), 0, pattern)
            }
        }
    }

    private func assertProcessUseRemainsConfined() throws {
        let token = "Process" + "("
        let allowed = Set([
            "Sumi/Managers/SumiScripts/UserScriptZipUtil.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3NativeMessagingInternalRuntime.swift",
        ])
        let matches = try swiftSourcesUnderProjectRoot().filter { fileURL in
            (try? String(contentsOf: fileURL, encoding: .utf8).contains(token))
                == true
        }
        let relativeMatches = Set(matches.map { relativePath(for: $0) })
        XCTAssertEqual(relativeMatches, allowed)
    }

    private func swiftSourcesUnderProjectRoot() throws -> [URL] {
        let root = projectRoot()
        let roots = ["Sumi", "SumiTests"].map {
            root.appendingPathComponent($0, isDirectory: true)
        }
        return roots.flatMap { sourceRoot -> [URL] in
            guard
                let enumerator = FileManager.default.enumerator(
                    at: sourceRoot,
                    includingPropertiesForKeys: [.isRegularFileKey]
                )
            else {
                return []
            }
            return enumerator.compactMap { item in
                guard let url = item as? URL else { return nil }
                return url.pathExtension == "swift" ? url : nil
            }
        }
    }

    private func relativePath(for url: URL) -> String {
        let rootPath = projectRoot().path
        let path = url.path
        guard path.hasPrefix(rootPath + "/") else { return path }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
