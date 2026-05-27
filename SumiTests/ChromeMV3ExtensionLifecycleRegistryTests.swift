import Foundation
import XCTest

@testable import Sumi

final class ChromeMV3ExtensionLifecycleRegistryTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    @MainActor
    func testDisabledModuleBlocksInternalInstallLifecycleWithoutArtifacts() throws {
        let root = try makeTemporaryDirectory()
        let source = try makeFixture(
            named: "disabled-module",
            manifest: minimalManifest(version: "1.0.0"),
            files: ["background.js": ""]
        )
        let module = try makeModule(enabled: false)

        let result = module.chromeMV3ImportInternalExtensionIfEnabled(
            rootURL: root,
            sourceURL: source,
            profileID: "profile-disabled"
        )

        XCTAssertNil(result)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("lifecycle").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("originals").path
            )
        )
    }

    func testRejectsMV2AndSafariPackagesWithoutActiveRegistryRecord() throws {
        let root = try makeTemporaryDirectory()
        let mv2 = try makeFixture(
            named: "mv2",
            manifest: [
                "manifest_version": 2,
                "name": "Legacy MV2",
                "version": "1.0",
            ],
            files: [:]
        )
        let registry = makeRegistry(rootURL: root)
        let mv2Result = registry.installUnpackedExtension(
            at: mv2,
            profileID: "profile-reject"
        )

        XCTAssertFalse(mv2Result.succeeded)
        XCTAssertEqual(mv2Result.failureCode, .manifestInvalid)
        XCTAssertNil(mv2Result.record)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("lifecycle/records").path
            )
        )

        let appURL = try makeTemporaryDirectory()
            .appendingPathComponent("Legacy.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: appURL,
            withIntermediateDirectories: true
        )
        let appResult = registry.installUnpackedExtension(
            at: appURL,
            profileID: "profile-reject"
        )

        XCTAssertFalse(appResult.succeeded)
        XCTAssertEqual(appResult.failureCode, .manifestInvalid)
        XCTAssertTrue(
            appResult.report?.blockerTaxonomy.contains {
                $0.message.contains(".app/.appex")
            } == true
        )
    }

    func testValidMV3InstallCreatesRegistryStagingGeneratedVersionAndReport()
        throws
    {
        let root = try makeTemporaryDirectory()
        let source = try makeFixture(
            named: "valid-install",
            manifest: passwordManagerManifest(version: "2.3.4"),
            files: passwordManagerFiles()
        )
        let result = makeRegistry(rootURL: root).installUnpackedExtension(
            at: source,
            profileID: "profile-install"
        )
        let record = try XCTUnwrap(result.record)
        let generated = try XCTUnwrap(result.generatedVersion)
        let report = try XCTUnwrap(result.report)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(record.lifecycleState, .diagnosticsReady)
        XCTAssertEqual(record.displayName, "Password Manager Fixture")
        XCTAssertEqual(record.displayVersion, "2.3.4")
        XCTAssertEqual(record.activeGeneratedVersionID, generated.id)
        XCTAssertNil(record.previousWorkingGeneratedVersionID)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: record.originalBundleRootPath)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: generated.generatedBundleRootPath
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: try XCTUnwrap(generated.rewrittenVariantRootPath)
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: try XCTUnwrap(generated.runtimeLoadabilityReportPath)
            )
        )
        XCTAssertFalse(generated.runtimeLoadable)
        XCTAssertFalse(report.productFlags.productRuntimeAvailable)
        XCTAssertFalse(report.productFlags.normalTabRuntimeBridgeAvailable)
        XCTAssertFalse(report.productFlags.runtimeLoadable)
        XCTAssertFalse(report.productFlags.productUIAvailable)
        XCTAssertFalse(report.productFlags.productNetworkEnforcementAvailable)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: record.reportPaths.compatibilityReportPath ?? ""
            )
        )
        XCTAssertTrue(
            report.lifecycleAvailability.extensionInstalledInInternalRegistry
        )
        XCTAssertTrue(report.lifecycleAvailability.generatedBundleAvailable)
        XCTAssertTrue(report.lifecycleAvailability.compatibilityReportAvailable)
        XCTAssertNotNil(report.passwordManagerReadinessSummary)
    }

    func testAggregatesConcreteAPIBlockersForNetworkPanelIdentityNativeAndWorker()
        throws
    {
        let root = try makeTemporaryDirectory()
        let source = try makeFixture(
            named: "api-blockers",
            manifest: blockerHeavyManifest(),
            files: [
                "background.js": "",
                "panel.html": "<!doctype html><title>Panel</title>\n",
                "rules.json": "[]",
            ]
        )
        let result = makeRegistry(rootURL: root).installUnpackedExtension(
            at: source,
            profileID: "profile-blockers"
        )
        let compatibility = try XCTUnwrap(result.report)
            .aggregateAPICompatibility
        let blockers = compatibility.allBlockers

        XCTAssertTrue(compatibility.productBlockedAPIs.contains(.webRequest))
        XCTAssertTrue(
            compatibility.productBlockedAPIs.contains(.declarativeNetRequest)
        )
        XCTAssertTrue(compatibility.productBlockedAPIs.contains(.sidePanel))
        XCTAssertTrue(compatibility.productBlockedAPIs.contains(.offscreen))
        XCTAssertTrue(compatibility.productBlockedAPIs.contains(.identity))
        XCTAssertTrue(compatibility.productBlockedAPIs.contains(.nativeMessaging))
        XCTAssertTrue(
            blockers.contains {
                $0.source == .network
                    && $0.apiNamespace == ChromeMV3API.webRequest.rawValue
                    && $0.severity == .productBlocked
            }
        )
        XCTAssertTrue(
            blockers.contains {
                $0.source == .sidePanel
                    && $0.severity == .productBlocked
                    && $0.filePath == "panel.html"
            }
        )
        XCTAssertTrue(
            blockers.contains {
                $0.source == .identity
                    && $0.apiMethod == "launchWebAuthFlow"
            }
        )
        XCTAssertTrue(
            blockers.contains {
                $0.source == .nativeMessaging
                    && $0.message.contains("fixture hosts")
            }
        )
        XCTAssertTrue(
            blockers.contains {
                $0.source == .serviceWorker
                    && $0.manifestKey == "background.service_worker"
            }
        )
        XCTAssertEqual(
            compatibility.nextRecommendedAction,
            "Use internal diagnostics only; product runtime remains unavailable."
        )
    }

    func testUpdateSuccessPromotesCandidateAndPreservesPreviousWorkingVersion()
        throws
    {
        let root = try makeTemporaryDirectory()
        let registry = makeRegistry(rootURL: root)
        let firstSource = try makeFixture(
            named: "update-v1",
            manifest: minimalManifest(version: "1.0.0"),
            files: ["background.js": "const version = 1;\n"]
        )
        let install = registry.installUnpackedExtension(
            at: firstSource,
            profileID: "profile-update"
        )
        let firstRecord = try XCTUnwrap(install.record)
        let firstActive = try XCTUnwrap(firstRecord.activeGeneratedVersionID)
        let secondSource = try makeFixture(
            named: "update-v2",
            manifest: minimalManifest(version: "2.0.0"),
            files: ["background.js": "const version = 2;\n"]
        )

        let update = registry.updateExtension(
            profileID: firstRecord.profileID,
            extensionID: firstRecord.extensionID,
            from: secondSource
        )
        let updated = try XCTUnwrap(update.record)

        XCTAssertTrue(update.succeeded)
        XCTAssertNotEqual(updated.activeGeneratedVersionID, firstActive)
        XCTAssertEqual(updated.previousWorkingGeneratedVersionID, firstActive)
        XCTAssertEqual(updated.displayVersion, "2.0.0")
        XCTAssertEqual(updated.generatedBundleVersions.count, 2)
        XCTAssertTrue(
            try XCTUnwrap(
                updated.generatedBundleVersions.first { $0.id == firstActive }
            ).state == .previousWorking
        )
    }

    func testUpdateFailureKeepsPreviousWorkingGeneratedVersionIntact()
        throws
    {
        let root = try makeTemporaryDirectory()
        let registry = makeRegistry(rootURL: root)
        let source = try makeFixture(
            named: "update-failure-v1",
            manifest: minimalManifest(version: "1.0.0"),
            files: ["background.js": ""]
        )
        let install = registry.installUnpackedExtension(
            at: source,
            profileID: "profile-update-fail"
        )
        let installed = try XCTUnwrap(install.record)
        let active = try XCTUnwrap(installed.activeGeneratedVersionID)
        let activeRoot = try XCTUnwrap(install.generatedVersion)
            .generatedBundleRootPath
        let broken = try makeFixture(
            named: "update-failure-v2",
            manifest: minimalManifest(version: "2.0.0"),
            files: [:]
        )

        let update = registry.updateExtension(
            profileID: installed.profileID,
            extensionID: installed.extensionID,
            from: broken
        )
        let failed = try XCTUnwrap(update.record)

        XCTAssertFalse(update.succeeded)
        XCTAssertEqual(update.failureCode, .resourceMissing)
        XCTAssertEqual(failed.lifecycleState, .updateFailed)
        XCTAssertEqual(failed.activeGeneratedVersionID, active)
        XCTAssertTrue(FileManager.default.fileExists(atPath: activeRoot))
        XCTAssertFalse(failed.runtimeState.internalRuntimeEnabled)
    }

    func testRebuildFailureKeepsPreviousWorkingGeneratedVersionIntact()
        throws
    {
        let root = try makeTemporaryDirectory()
        let registry = makeRegistry(rootURL: root)
        let source = try makeFixture(
            named: "rebuild-failure",
            manifest: minimalManifest(version: "1.0.0"),
            files: ["background.js": ""]
        )
        let install = registry.installUnpackedExtension(
            at: source,
            profileID: "profile-rebuild-fail"
        )
        let installed = try XCTUnwrap(install.record)
        let active = try XCTUnwrap(installed.activeGeneratedVersionID)
        try FileManager.default.removeItem(
            at: URL(fileURLWithPath: installed.originalBundleRootPath)
                .appendingPathComponent("background.js")
        )

        let rebuild = registry.rebuildExtension(
            profileID: installed.profileID,
            extensionID: installed.extensionID
        )
        let failed = try XCTUnwrap(rebuild.record)

        XCTAssertFalse(rebuild.succeeded)
        XCTAssertEqual(rebuild.failureCode, .resourceMissing)
        XCTAssertEqual(failed.activeGeneratedVersionID, active)
        XCTAssertEqual(failed.lifecycleState, .updateFailed)
    }

    func testRollbackRestoresPreviousWorkingGeneratedVersion() throws {
        let root = try makeTemporaryDirectory()
        let registry = makeRegistry(rootURL: root)
        let first = try makeFixture(
            named: "rollback-v1",
            manifest: minimalManifest(version: "1.0.0"),
            files: ["background.js": "const version = 1;\n"]
        )
        let install = registry.installUnpackedExtension(
            at: first,
            profileID: "profile-rollback"
        )
        let installed = try XCTUnwrap(install.record)
        let firstActive = try XCTUnwrap(installed.activeGeneratedVersionID)
        let second = try makeFixture(
            named: "rollback-v2",
            manifest: minimalManifest(version: "2.0.0"),
            files: ["background.js": "const version = 2;\n"]
        )
        let update = registry.updateExtension(
            profileID: installed.profileID,
            extensionID: installed.extensionID,
            from: second
        )
        let secondRecord = try XCTUnwrap(update.record)
        let secondActive = try XCTUnwrap(secondRecord.activeGeneratedVersionID)

        let rollback = registry.rollbackExtension(
            profileID: installed.profileID,
            extensionID: installed.extensionID
        )
        let rolledBack = try XCTUnwrap(rollback.record)

        XCTAssertTrue(rollback.succeeded)
        XCTAssertEqual(rolledBack.activeGeneratedVersionID, firstActive)
        XCTAssertEqual(rolledBack.previousWorkingGeneratedVersionID, secondActive)
        XCTAssertFalse(rolledBack.runtimeState.internalRuntimeEnabled)
    }

    func testUninstallClearsGeneratedArtifactsAndInternalRuntimeState() throws {
        let root = try makeTemporaryDirectory()
        let registry = makeRegistry(rootURL: root)
        let source = try makeFixture(
            named: "uninstall",
            manifest: minimalManifest(version: "1.0.0"),
            files: ["background.js": ""]
        )
        let install = registry.installUnpackedExtension(
            at: source,
            profileID: "profile-uninstall",
            enableInternal: true
        )
        let installed = try XCTUnwrap(install.record)
        _ = registry.writeCrashMarker(
            profileID: installed.profileID,
            extensionID: installed.extensionID,
            reason: "test crash",
            lifecycleSessionLeftActive: true,
            nativeFixturePortLeftOpen: true
        )
        let beforeUninstall = try XCTUnwrap(
            registry.loadLifecycleRecord(
                profileID: installed.profileID,
                extensionID: installed.extensionID
            )
        )
        let versionRoots = beforeUninstall.generatedBundleVersions
            .map(\.versionRootPath)

        let uninstall = registry.uninstallExtension(
            profileID: installed.profileID,
            extensionID: installed.extensionID
        )
        let record = try XCTUnwrap(uninstall.record)

        XCTAssertTrue(uninstall.succeeded)
        XCTAssertEqual(record.lifecycleState, .uninstalled)
        XCTAssertNil(record.activeGeneratedVersionID)
        XCTAssertFalse(record.runtimeState.internalRuntimeEnabled)
        XCTAssertFalse(record.runtimeState.sharedLifecycleSessionActive)
        XCTAssertFalse(record.runtimeState.nativeFixturePortOpen)
        XCTAssertFalse(record.runtimeState.storageStatePresent)
        XCTAssertFalse(record.runtimeState.permissionsStatePresent)
        XCTAssertTrue(
            record.generatedBundleVersions.allSatisfy {
                $0.state == .removed
            }
        )
        XCTAssertTrue(
            versionRoots.allSatisfy {
                FileManager.default.fileExists(atPath: $0) == false
            }
        )
    }

    func testResetClearsStoragePermissionsAndSessionStateAccordingToPolicy()
        throws
    {
        let root = try makeTemporaryDirectory()
        let registry = makeRegistry(rootURL: root)
        let source = try makeFixture(
            named: "reset",
            manifest: minimalManifest(version: "1.0.0"),
            files: ["background.js": ""]
        )
        let install = registry.installUnpackedExtension(
            at: source,
            profileID: "profile-reset",
            enableInternal: true
        )
        var record = try XCTUnwrap(install.record)
        record.runtimeState.syntheticHarnessStatePresent = true
        record.runtimeState.sharedLifecycleSessionActive = true
        record.runtimeState.nativeFixturePortOpen = true
        record.runtimeState.storageStatePresent = true
        record.runtimeState.permissionsStatePresent = true
        try writeRecord(record)

        let reset = registry.resetExtensionState(
            profileID: record.profileID,
            extensionID: record.extensionID
        )
        let resetRecord = try XCTUnwrap(reset.record)

        XCTAssertTrue(reset.succeeded)
        XCTAssertEqual(resetRecord.lifecycleState, .disabledInternal)
        XCTAssertFalse(resetRecord.runtimeState.internalRuntimeEnabled)
        XCTAssertFalse(resetRecord.runtimeState.syntheticHarnessStatePresent)
        XCTAssertFalse(resetRecord.runtimeState.sharedLifecycleSessionActive)
        XCTAssertFalse(resetRecord.runtimeState.nativeFixturePortOpen)
        XCTAssertFalse(resetRecord.runtimeState.storageStatePresent)
        XCTAssertFalse(resetRecord.runtimeState.permissionsStatePresent)
        XCTAssertEqual(resetRecord.runtimeState.resetSequence, 1)
    }

    func testRecoveryDetectsCrashMarkerAndRollsBackToPreviousWorkingVersion()
        throws
    {
        let root = try makeTemporaryDirectory()
        let registry = makeRegistry(rootURL: root)
        let first = try makeFixture(
            named: "recover-v1",
            manifest: minimalManifest(version: "1.0.0"),
            files: ["background.js": "const version = 1;\n"]
        )
        let install = registry.installUnpackedExtension(
            at: first,
            profileID: "profile-recover"
        )
        let installed = try XCTUnwrap(install.record)
        let firstActive = try XCTUnwrap(installed.activeGeneratedVersionID)
        let second = try makeFixture(
            named: "recover-v2",
            manifest: minimalManifest(version: "2.0.0"),
            files: ["background.js": "const version = 2;\n"]
        )
        let update = registry.updateExtension(
            profileID: installed.profileID,
            extensionID: installed.extensionID,
            from: second
        )
        let updated = try XCTUnwrap(update.record)
        let secondActiveRoot = try XCTUnwrap(
            updated.generatedBundleVersions.first {
                $0.id == updated.activeGeneratedVersionID
            }
        ).generatedBundleRootPath
        try FileManager.default.removeItem(
            at: URL(fileURLWithPath: secondActiveRoot, isDirectory: true)
        )
        _ = registry.writeCrashMarker(
            profileID: updated.profileID,
            extensionID: updated.extensionID,
            reason: "simulated crash",
            lifecycleSessionLeftActive: true,
            nativeFixturePortLeftOpen: true
        )

        let recovery = registry.runRecoveryScan(
            profileID: updated.profileID,
            extensionID: updated.extensionID
        )
        let recovered = try XCTUnwrap(recovery.record)
        let status = try XCTUnwrap(recovery.report?.crashRecoveryStatus)

        XCTAssertTrue(recovery.succeeded)
        XCTAssertEqual(recovered.lifecycleState, .recoveryRequired)
        XCTAssertEqual(recovered.activeGeneratedVersionID, firstActive)
        XCTAssertEqual(status.rolledBackToPreviousWorkingVersionID, firstActive)
        XCTAssertTrue(status.crashMarkerDetected)
        XCTAssertTrue(status.activeGeneratedBundleMissing)
        XCTAssertTrue(status.lifecycleSessionLeftActive)
        XCTAssertTrue(status.nativeFixturePortLeftOpen)
        XCTAssertFalse(recovered.runtimeState.internalRuntimeEnabled)
    }

    func testRecoveryDisablesInternalRuntimeAndRequiresRebuildWithoutValidVersion()
        throws
    {
        let root = try makeTemporaryDirectory()
        let registry = makeRegistry(rootURL: root)
        let source = try makeFixture(
            named: "recover-no-version",
            manifest: minimalManifest(version: "1.0.0"),
            files: ["background.js": ""]
        )
        let install = registry.installUnpackedExtension(
            at: source,
            profileID: "profile-recover-none",
            enableInternal: true
        )
        let installed = try XCTUnwrap(install.record)
        let activeRoot = try XCTUnwrap(install.generatedVersion)
            .generatedBundleRootPath
        try FileManager.default.removeItem(
            at: URL(fileURLWithPath: activeRoot, isDirectory: true)
        )
        try "{}".write(
            to: URL(fileURLWithPath: installed.manifestSnapshotPath),
            atomically: true,
            encoding: .utf8
        )
        try "{".write(
            to: URL(
                fileURLWithPath:
                    try XCTUnwrap(installed.reportPaths.compatibilityReportPath)
            ),
            atomically: true,
            encoding: .utf8
        )

        let recovery = registry.runRecoveryScan(
            profileID: installed.profileID,
            extensionID: installed.extensionID
        )
        let recovered = try XCTUnwrap(recovery.record)
        let status = try XCTUnwrap(recovery.report?.crashRecoveryStatus)

        XCTAssertEqual(recovered.lifecycleState, .recoveryRequired)
        XCTAssertNil(recovered.activeGeneratedVersionID)
        XCTAssertTrue(status.manifestSnapshotMissingOrCorrupt)
        XCTAssertTrue(status.generatedMetadataMissingOrCorrupt)
        XCTAssertTrue(status.reportMissingOrCorrupt)
        XCTAssertTrue(status.rebuildRequired)
        XCTAssertFalse(recovered.runtimeState.internalRuntimeEnabled)
    }

    @MainActor
    func testSumiExtensionsModuleWritesAndFetchesEndToEndDiagnosticsWhenEnabled()
        throws
    {
        let root = try makeTemporaryDirectory()
        let source = try makeFixture(
            named: "module-e2e",
            manifest: minimalManifest(version: "1.0.0"),
            files: ["background.js": ""]
        )
        let module = try makeModule(enabled: true)
        let install = try XCTUnwrap(
            module.chromeMV3ImportInternalExtensionIfEnabled(
                rootURL: root,
                sourceURL: source,
                profileID: "profile-module"
            )
        )
        let record = try XCTUnwrap(install.record)

        let report = module.chromeMV3RunEndToEndDiagnosticsIfEnabled(
            rootURL: root,
            profileID: record.profileID,
            extensionID: record.extensionID
        )
        let latest = module.chromeMV3LatestEndToEndDiagnosticsReportIfEnabled(
            rootURL: root,
            profileID: record.profileID,
            extensionID: record.extensionID
        )

        XCTAssertNotNil(report)
        XCTAssertEqual(report?.id, latest?.id)
        XCTAssertEqual(report?.reportFileName, latest?.reportFileName)
        XCTAssertEqual(report?.productFlags, latest?.productFlags)
        XCTAssertEqual(report?.productFlags.productRuntimeAvailable, false)
        XCTAssertEqual(
            report?.productFlags.normalTabRuntimeBridgeAvailable,
            false
        )
        XCTAssertEqual(report?.productFlags.runtimeLoadable, false)
    }

    func testLifecycleSourceGuardsStayInternalOnly() throws {
        let lifecycleSource = try source(
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3ExtensionLifecycleRegistry.swift"
        )
        let moduleSource = try source(
            "Sumi/Managers/ExtensionManager/SumiExtensionsModule.swift"
        )
        let forbiddenScheduling = ["Ti" + "mer", "DispatchSource" + "Ti" + "mer"]
        for token in forbiddenScheduling {
            XCTAssertFalse(lifecycleSource.contains(token))
        }
        XCTAssertFalse(lifecycleSource.contains("Process" + "("))
        let enabledLiteral = "tr" + "ue"
        XCTAssertFalse(
            moduleSource.contains("runtimeLoadable = " + enabledLiteral)
        )
        XCTAssertFalse(
            moduleSource.contains(
                "productRuntime" + "Available = " + enabledLiteral
            )
        )
        XCTAssertFalse(lifecycleSource.contains("Browser" + "Config"))
        XCTAssertFalse(lifecycleSource.contains("webExtension" + "Controller"))
        XCTAssertFalse(lifecycleSource.contains("addUser" + "Script"))
        XCTAssertFalse(lifecycleSource.contains("addScript" + "MessageHandler"))
        XCTAssertFalse(lifecycleSource.contains("NS" + "Window"))
        XCTAssertFalse(lifecycleSource.contains("NS" + "Panel"))
        XCTAssertFalse(lifecycleSource.contains("NS" + "Menu"))
        XCTAssertFalse(lifecycleSource.contains("URL" + "Session"))
        XCTAssertFalse(lifecycleSource.contains("ASWeb" + "AuthenticationSession"))
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

    private func passwordManagerManifest(version: String) -> [String: Any] {
        [
            "manifest_version": 3,
            "name": "Password Manager Fixture",
            "version": version,
            "permissions": [
                "storage",
                "nativeMessaging",
            ],
            "host_permissions": ["https://example.com/*"],
            "background": [
                "service_worker": "background.js",
            ],
            "content_scripts": [
                [
                    "matches": ["https://example.com/*"],
                    "js": ["content.js"],
                    "all_frames": true,
                    "match_about_blank": true,
                ],
            ],
            "action": [
                "default_popup": "popup.html",
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
            ],
            "background": [
                "service_worker": "background.js",
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

    private func writeRecord(
        _ record: ChromeMV3ExtensionLifecycleRecord
    ) throws {
        try ChromeMV3DeterministicJSON.write(
            record,
            to: URL(fileURLWithPath: record.reportPaths.registryRecordPath)
        )
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

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: projectRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
