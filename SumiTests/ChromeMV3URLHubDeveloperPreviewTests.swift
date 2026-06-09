import AppKit
import Foundation
import SwiftData
import XCTest
#if canImport(WebKit)
import WebKit
#endif

@testable import Sumi

final class ChromeMV3URLHubDeveloperPreviewTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_720_100_000)
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    @MainActor
    func testURLHubSectionIsAbsentWhenExtensionsModuleDisabled()
        throws
    {
        let root = try makeTemporaryDirectory()
        let source = try makeFixture(
            named: "urlhub-disabled",
            manifest: bitwardenManualSmokeManifest(name: "urlhub-disabled"),
            files: bitwardenManualSmokeFiles()
        )
        let module = try makeModule(enabled: true)
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: source,
            profileID: "profile-urlhub-disabled",
            enableInternal: true
        )
        XCTAssertTrue(install.succeeded)
        module.setEnabled(false)

        let section = module.chromeMV3URLHubSectionViewModelIfEnabled(
            rootURL: root,
            currentPage: syntheticPageContext(
                profileID: "profile-urlhub-disabled"
            ),
            now: fixedDate
        )

        XCTAssertNil(section)
        XCTAssertFalse(module.hasLoadedRuntime)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(".diagnostics").path
            )
        )
    }

    @MainActor
    func testURLHubPassiveReadoutBlocksUnreviewedSyntheticFixture()
        throws
    {
        let fixture = try installBitwardenURLHubFixture(
            named: "urlhub-readout",
            profileID: "profile-urlhub-readout",
            enableInternal: true
        )
        let artifactURL =
            ChromeMV3ExtensionManagerReviewedResourceDiagnosticArtifactWriter.reportURL(
                rootURL: fixture.root,
                profileID: fixture.record.profileID,
                extensionID: fixture.record.extensionID
            )

        let section = try XCTUnwrap(
            fixture.module.chromeMV3URLHubSectionViewModelIfEnabled(
                rootURL: fixture.root,
                currentPage: syntheticPageContext(
                    profileID: fixture.record.profileID
                ),
                now: fixedDate
            )
        )
        let row = try XCTUnwrap(section.rows.first)

        XCTAssertEqual(section.rows.count, 1)
        XCTAssertEqual(row.extensionID, fixture.record.extensionID)
        XCTAssertEqual(row.profileID, fixture.record.profileID)
        XCTAssertEqual(row.displayName, fixture.record.displayName)
        XCTAssertEqual(row.sourceType, .localUnpacked)
        XCTAssertEqual(row.installIntakeStatus, .enabledInternal)
        XCTAssertTrue(row.installed)
        XCTAssertTrue(row.generatedBundleAvailable)
        XCTAssertNotNil(row.generatedBundleRecordID)
        XCTAssertNotNil(row.generatedBundleHash)
        XCTAssertNotNil(row.manifestHash)
        XCTAssertNotNil(row.originalBundleContentHash)
        XCTAssertFalse(row.productSupportClaim)
        XCTAssertEqual(row.developerPreviewLabel, "Local experimental developer preview")
        XCTAssertTrue(row.notProductSupportLabel.contains("not product support"))
        XCTAssertTrue(row.enabled)
        XCTAssertTrue(row.readiness.localExperimentalGateOpen)
        XCTAssertTrue(row.readiness.currentPageIsSyntheticDiagnosticPage)
        XCTAssertFalse(row.readiness.explicitDiagnosticActionCanRun)
        XCTAssertTrue(row.readiness.productRuntimeStayedOff)
        XCTAssertFalse(row.readiness.productDefaultRuntimeAvailable)
        XCTAssertEqual(row.readiness.blockers, [.blockedByRuntimeGate])
        XCTAssertFalse(row.diagnosticAction.available)
        let capability = try XCTUnwrap(row.diagnosticAction.capability)
        XCTAssertEqual(
            capability.capabilityID,
            ChromeMV3ReviewedResourceDiagnosticCapabilityCatalog
                .reviewedGeneratedResourceNormalTabDiagnosticID
        )
        XCTAssertEqual(
            capability.generatedResourceStatus,
            .reviewedHashMismatch
        )
        XCTAssertTrue(capability.sourceGeneratedByteEqual)
        XCTAssertFalse(capability.productSupportClaim)
        XCTAssertNil(row.diagnosticAction.lastArtifactPath)
        XCTAssertNil(row.diagnosticAction.lastRunStatus)
        XCTAssertFalse(section.lifetime.artifactWrittenByReadout)
        XCTAssertEqual(section.lifetime.runtimeObjectsCreated, [])
        XCTAssertFalse(section.lifetime.serviceWorkerWakeAttempted)
        XCTAssertFalse(section.lifetime.nativeHostLaunchAttempted)
        XCTAssertFalse(section.lifetime.timersOrPollingStarted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifactURL.path))
        XCTAssertFalse(fixture.module.hasLoadedRuntime)
    }

    @MainActor
    func testURLHubShowsGenericInstalledExtensionStateWithoutFixtureCapability()
        throws
    {
        let root = try makeTemporaryDirectory()
        let source = try makeFixture(
            named: "urlhub-generic-installed",
            manifest: genericMV3Manifest(name: "Generic Local MV3"),
            files: [:]
        )
        let module = try makeModule(enabled: true)
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: source,
            profileID: "profile-urlhub-generic",
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)

        let installedState = try XCTUnwrap(
            ChromeMV3ExtensionLifecycleRegistry(rootURL: root)
                .installedExtensionState(
                    profileID: record.profileID,
                    extensionID: record.extensionID
                )
        )
        XCTAssertEqual(installedState.sourceType, .localUnpacked)
        XCTAssertEqual(installedState.stableLocalExtensionID, record.extensionID)
        XCTAssertEqual(installedState.displayName, "Generic Local MV3")
        XCTAssertTrue(installedState.installed)
        XCTAssertTrue(installedState.enabled)
        XCTAssertTrue(installedState.generatedBundleState.generatedBundleAvailable)
        XCTAssertNotNil(installedState.generatedBundleHash)
        XCTAssertNotNil(installedState.manifestHash)
        XCTAssertNotNil(installedState.originalBundleContentHash)
        XCTAssertFalse(installedState.productSupportClaim)

        let section = try XCTUnwrap(
            module.chromeMV3URLHubSectionViewModelIfEnabled(
                rootURL: root,
                currentPage: syntheticPageContext(profileID: record.profileID),
                now: fixedDate
            )
        )
        let row = try XCTUnwrap(section.rows.first)

        XCTAssertEqual(section.rows.count, 1)
        XCTAssertEqual(row.extensionID, record.extensionID)
        XCTAssertEqual(row.displayName, "Generic Local MV3")
        XCTAssertEqual(row.sourceType, .localUnpacked)
        XCTAssertEqual(row.installIntakeStatus, .enabledInternal)
        XCTAssertTrue(row.installed)
        XCTAssertTrue(row.enabled)
        XCTAssertTrue(row.generatedBundleAvailable)
        XCTAssertFalse(row.productSupportClaim)
        XCTAssertEqual(
            row.diagnosticAction.capabilityID,
            ChromeMV3ReviewedResourceDiagnosticCapabilityCatalog
                .reviewedGeneratedResourceNormalTabDiagnosticID
        )
        XCTAssertFalse(row.diagnosticAction.capabilityAvailable)
        XCTAssertFalse(row.diagnosticAction.available)
        XCTAssertNil(row.diagnosticAction.capability)
        XCTAssertTrue(
            row.diagnosticAction.unavailableDiagnostics.contains {
                $0.code == .reviewedResourceDiagnosticReviewedFileMissing
            }
        )
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    @MainActor
    func testEnabledLocalMV3ActionSyncsIntoURLHubActionSurfaceWithoutRuntimeObjects()
        async throws
    {
        let root = try makeTemporaryDirectory()
        let source = try makeFixture(
            named: "urlhub-generic-action-popup",
            manifest: genericActionPopupManifest(
                name: "Generic Popup MV3",
                permissions: ["activeTab"]
            ),
            files: [
                "popup.html": "<!doctype html><title>Popup</title>",
            ]
        )
        let module = try makeModule(enabled: true, includesModelContext: true)

        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: source,
            profileID: "profile-urlhub-generic-action",
            enableInternal: true
        )
        let lifecycleRecord = try XCTUnwrap(
            install.lifecycleOperationResult?.record
        )

        let syncedAction = await waitForEnabledExtension(
            in: module,
            extensionId: lifecycleRecord.extensionID
        )
        let action = try XCTUnwrap(syncedAction)

        XCTAssertTrue(install.succeeded)
        XCTAssertEqual(module.surfaceStore.enabledExtensions.count, 1)
        XCTAssertEqual(action.id, lifecycleRecord.extensionID)
        XCTAssertEqual(action.name, "Generic Popup MV3")
        XCTAssertTrue(action.hasAction)
        XCTAssertEqual(action.defaultPopupPath, "popup.html")
        XCTAssertEqual(action.sourceKind, .directory)
        XCTAssertTrue(action.isEnabled)
        let activeGeneratedVersionID = try XCTUnwrap(
            lifecycleRecord.activeGeneratedVersionID
        )
        let activeGeneratedVersion = try XCTUnwrap(
            lifecycleRecord.generatedBundleVersions.first {
                $0.id == activeGeneratedVersionID
            }
        )
        XCTAssertEqual(
            action.packagePath,
            activeGeneratedVersion.generatedBundleRootPath
        )
        XCTAssertEqual(
            action.sourceBundlePath,
            lifecycleRecord.originalBundleRootPath
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(".diagnostics").path
            )
        )
        XCTAssertFalse(module.hasLoadedWebExtensionController)
    }

    @MainActor
    func testURLHubRestoresPersistedActionSurfaceOnColdStartWithoutReinstall()
        async throws
    {
        let root = try makeTemporaryDirectory()
        let source = try makeFixture(
            named: "urlhub-cold-start-action-popup",
            manifest: genericActionPopupManifest(
                name: "Cold Start Popup MV3",
                permissions: ["activeTab"]
            ),
            files: [
                "popup.html": "<!doctype html><title>Cold Start Popup</title>",
            ]
        )
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore:
                SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.setEnabled(true, for: .extensions)
        let container = try ModelContainer(
            for: Schema([ExtensionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let installingModule = SumiExtensionsModule(
            moduleRegistry: registry,
            context: ModelContext(container)
        )

        let install = installingModule.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: source,
            profileID: "profile-urlhub-cold-start-action",
            enableInternal: true
        )
        let lifecycleRecord = try XCTUnwrap(
            install.lifecycleOperationResult?.record
        )
        let installedAction = await waitForEnabledExtension(
            in: installingModule,
            extensionId: lifecycleRecord.extensionID
        )
        XCTAssertNotNil(installedAction)

        let restartedModule = SumiExtensionsModule(
            moduleRegistry: registry,
            context: ModelContext(container)
        )
        XCTAssertTrue(restartedModule.surfaceStore.enabledExtensions.isEmpty)
        XCTAssertFalse(restartedModule.hasLoadedRuntime)

        XCTAssertTrue(
            restartedModule.ensureActionSurfaceMetadataLoadedIfNeeded(
                rootURL: root
            )
        )
        let restoredActionCandidate = await waitForEnabledExtension(
            in: restartedModule,
            extensionId: lifecycleRecord.extensionID
        )
        let restoredAction = try XCTUnwrap(restoredActionCandidate)

        XCTAssertEqual(restoredAction.id, lifecycleRecord.extensionID)
        XCTAssertEqual(restoredAction.name, "Cold Start Popup MV3")
        XCTAssertTrue(restoredAction.hasAction)
        XCTAssertEqual(restoredAction.defaultPopupPath, "popup.html")
        XCTAssertFalse(restartedModule.hasLoadedWebExtensionController)
    }

    @MainActor
    func testControlledCompatibilityPopupDefaultOpensGeneratedActionPopupWithoutNativeRuntime()
        async throws
    {
        let root = try makeTemporaryDirectory()
        let source = try makeFixture(
            named: "urlhub-controlled-action-popup",
            manifest: genericActionPopupManifest(
                name: "Controlled URLHub Popup",
                permissions: ["activeTab"]
            ),
            files: [
                "popup.html": """
                    <!doctype html>
                    <html>
                    <head><meta charset="utf-8"><title>Controlled Popup</title></head>
                    <body data-api="chrome.runtime.sendMessage">
                    <script src="popup.js"></script>
                    </body>
                    </html>
                    """,
                "popup.js": "chrome.runtime.getURL('popup.html');",
            ]
        )
        let fakeFactory = FakeURLHubPopupOptionsWebViewFactory()
        let profileID = UUID()
        let module = try makeModule(
            enabled: true,
            includesModelContext: true,
            popupOptionsWebViewFactory: { fakeFactory }
        )
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: source,
            profileID: profileID.uuidString,
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)
        _ = await waitForEnabledExtension(
            in: module,
            extensionId: record.extensionID
        )
        let activeGeneratedVersionID = try XCTUnwrap(
            record.activeGeneratedVersionID
        )
        let activeGeneratedVersion = try XCTUnwrap(
            record.generatedBundleVersions.first {
                $0.id == activeGeneratedVersionID
            }
        )

        let currentTab = Tab(url: URL(string: "https://example.com/login")!)
        currentTab.profileId = profileID
        let result = await module.openActionPopupFromURLHub(
            extensionId: record.extensionID,
            currentTab: currentTab
        )

        XCTAssertTrue(result.opened)
        XCTAssertNil(result.blocker)
        XCTAssertNil(result.nativePopupBoundarySnapshot)
        XCTAssertEqual(
            result.message,
            "Extension action popup opened through Sumi's controlled MV3 compatibility host."
        )
        XCTAssertEqual(fakeFactory.createCount, 1)
        XCTAssertEqual(
            fakeFactory.loadedFileURLs.first?.lastPathComponent,
            "popup.html"
        )
        XCTAssertEqual(
            fakeFactory.readAccessURLs.first?.path,
            activeGeneratedVersion.generatedBundleRootPath
        )
        XCTAssertEqual(
            fakeFactory.lastBridgeInstallation?.allowlist,
            .controlledActionPopupPolicy
        )
        XCTAssertEqual(
            module.chromeMV3PopupOptionsActiveSessionCountForTesting,
            1
        )
        XCTAssertFalse(module.hasLoadedWebExtensionController)
        XCTAssertTrue(result.sanitizedBridgeSnapshotDiagnostics.contains {
            $0.contains("controlled MV3 compatibility host")
        })
        XCTAssertTrue(result.sanitizedBridgeSnapshotDiagnostics.contains {
            $0.contains(
                "selectedPopupPath=controlledCompatibilityActionPopup"
            )
        })
        XCTAssertTrue(result.sanitizedBridgeSnapshotDiagnostics.contains {
            $0.contains("compatibilityPolicy=allowed")
                && $0.contains(
                    "reason=enabledLocalUnpackedMV3DeveloperPreview"
                )
        })

        let close = module.chromeMV3ClosePopupOptionsThroughManager(
            profileID: record.profileID,
            extensionID: record.extensionID
        )

        XCTAssertEqual(close.status, .succeeded)
        XCTAssertEqual(fakeFactory.teardownCount, 1)
        XCTAssertEqual(
            module.chromeMV3PopupOptionsActiveSessionCountForTesting,
            0
        )
        XCTAssertFalse(module.hasLoadedWebExtensionController)
        XCTAssertEqual(
            close.popupOptionsRunResult?.nativeHostLaunchAttempted,
            false
        )
    }

    @MainActor
    func testControlledCompatibilityPopupPreservesManifestPageURLQuery()
        async throws
    {
        let root = try makeTemporaryDirectory()
        var manifest = genericActionPopupManifest(
            name: "Controlled Query Popup",
            permissions: ["activeTab"]
        )
        manifest["action"] = [
            "default_title": "Controlled Query Popup",
            "default_popup": "popup.html?action#extension",
        ]
        let source = try makeFixture(
            named: "urlhub-controlled-query-popup",
            manifest: manifest,
            files: [
                "popup.html": """
                    <!doctype html>
                    <html>
                    <head><meta charset="utf-8"><title>Controlled Popup</title></head>
                    <body data-api="chrome.runtime.sendMessage"></body>
                    </html>
                    """,
            ]
        )
        let fakeFactory = FakeURLHubPopupOptionsWebViewFactory()
        let profileID = UUID()
        let module = try makeModule(
            enabled: true,
            includesModelContext: true,
            popupOptionsWebViewFactory: { fakeFactory }
        )
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: source,
            profileID: profileID.uuidString,
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)
        _ = await waitForEnabledExtension(
            in: module,
            extensionId: record.extensionID
        )

        let currentTab = Tab(url: URL(string: "https://example.com/login")!)
        currentTab.profileId = profileID
        let result = await module.openActionPopupFromURLHub(
            extensionId: record.extensionID,
            currentTab: currentTab
        )

        XCTAssertTrue(result.opened)
        let loadedURL = try XCTUnwrap(fakeFactory.loadedFileURLs.first)
        XCTAssertEqual(loadedURL.lastPathComponent, "popup.html")
        let loadedComponents = try XCTUnwrap(
            URLComponents(url: loadedURL, resolvingAgainstBaseURL: false)
        )
        XCTAssertEqual(loadedComponents.percentEncodedQuery, "action")
        XCTAssertEqual(loadedComponents.percentEncodedFragment, "extension")
        XCTAssertEqual(fakeFactory.createCount, 1)
        XCTAssertFalse(module.hasLoadedWebExtensionController)

        _ = module.chromeMV3ClosePopupOptionsThroughManager(
            profileID: record.profileID,
            extensionID: record.extensionID
        )
    }

    @MainActor
    func testURLHubActionClickLoadsNewlySyncedRecordIntoReadyRuntime()
        async throws
    {
        let root = try makeTemporaryDirectory()
        let firstSource = try makeFixture(
            named: "urlhub-ready-runtime-first-popup",
            manifest: genericActionPopupManifest(
                name: "First Popup",
                permissions: ["activeTab"]
            ),
            files: [
                "popup.html": "<!doctype html><title>First Popup</title>",
            ]
        )
        let secondSource = try makeFixture(
            named: "urlhub-ready-runtime-second-popup",
            manifest: genericActionPopupManifest(
                name: "Second Popup",
                permissions: ["activeTab"]
            ),
            files: [
                "popup.html": "<!doctype html><title>Second Popup</title>",
            ]
        )
        UserDefaults.standard.set(
            true,
            forKey: ExtensionManager
                .nativeActionPopupBoundaryObservationDefaultsKey
        )
        UserDefaults.standard.set(
            true,
            forKey: ExtensionManager
                .forceNativeCompatibilityActionPopupDefaultsKey
        )
        defer {
            UserDefaults.standard.removeObject(
                forKey: ExtensionManager
                    .nativeActionPopupBoundaryObservationDefaultsKey
            )
            UserDefaults.standard.removeObject(
                forKey: ExtensionManager
                    .forceNativeCompatibilityActionPopupDefaultsKey
            )
        }
        let module = try makeModule(enabled: true, includesModelContext: true)
        let firstInstall = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: firstSource,
            profileID: "profile-urlhub-ready-runtime",
            enableInternal: true
        )
        let firstRecord = try XCTUnwrap(
            firstInstall.lifecycleOperationResult?.record
        )
        _ = await waitForEnabledExtension(
            in: module,
            extensionId: firstRecord.extensionID
        )
        let manager = try XCTUnwrap(module.managerIfEnabled())

        let runtimeReady = await manager.requestExtensionRuntimeAndWait(
            reason: .extensionAction
        )
        XCTAssertTrue(runtimeReady)
        XCTAssertNotNil(manager.getExtensionContext(for: firstRecord.extensionID))
        XCTAssertEqual(manager.runtimeState, .ready)

        let secondInstall = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: secondSource,
            profileID: "profile-urlhub-ready-runtime",
            enableInternal: true
        )
        let secondRecord = try XCTUnwrap(
            secondInstall.lifecycleOperationResult?.record
        )
        _ = await waitForEnabledExtension(
            in: module,
            extensionId: secondRecord.extensionID
        )

        XCTAssertNil(manager.getExtensionContext(for: secondRecord.extensionID))
        XCTAssertEqual(manager.runtimeState, .ready)

        let result = await module.openActionPopupFromURLHub(
            extensionId: secondRecord.extensionID,
            currentTab: Tab(url: URL(string: "https://example.com/login")!)
        )

        XCTAssertTrue(result.opened)
        XCTAssertNil(result.blocker)
        XCTAssertTrue(result.sanitizedBridgeSnapshotDiagnostics.contains {
            $0.contains("selectedPopupPath=nativeWebKitActionPopup")
                && $0.contains("reason=debugForceNativeActionPopup")
        })
        let nativeSnapshot = try XCTUnwrap(result.nativePopupBoundarySnapshot)
        XCTAssertEqual(nativeSnapshot.extensionID, secondRecord.extensionID)
        XCTAssertFalse(nativeSnapshot.popupWebViewAccessedBeforePerformAction)
        XCTAssertFalse(nativeSnapshot.nativePopupBridgeInstalled)
        XCTAssertTrue(
            nativeSnapshot.nativePopupPreludeConfiguredBeforePopupCreation
        )
        XCTAssertTrue(nativeSnapshot.lifecycleEvents.contains {
            $0.milestone == "performAction.aboutToRun"
        })
        let encodedNativeSnapshot = String(
            data: try JSONEncoder().encode(nativeSnapshot),
            encoding: .utf8
        ) ?? ""
        XCTAssertFalse(encodedNativeSnapshot.contains("https://example.com/login"))
        XCTAssertFalse(encodedNativeSnapshot.contains("password"))
        XCTAssertFalse(encodedNativeSnapshot.contains("token"))
        XCTAssertNotNil(manager.getExtensionContext(for: secondRecord.extensionID))
        XCTAssertEqual(manager.extensionController?.extensionContexts.count, 2)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(".diagnostics").path
            )
        )
    }

    @MainActor
    func testDebugNativeBitwardenURLHubActionPopupPreludeCaptureHarness()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("WKWebExtension native popup boundary requires macOS 15.5.")
        }

        let bitwardenRoot = URL(
            fileURLWithPath:
                "/Users/fedaefimov/Downloads/Aura/mv3-test-extensions/bitwarden",
            isDirectory: true
        )
        try XCTSkipUnless(
            FileManager.default.fileExists(
                atPath: bitwardenRoot.appendingPathComponent("manifest.json").path
            ),
            "Local Bitwarden package is not available."
        )

        let nativeHostWasRunning =
            bitwardenNativeHostRunningApplicationIdentifiers()
        UserDefaults.standard.set(
            true,
            forKey: ExtensionManager
                .nativeActionPopupBoundaryObservationDefaultsKey
        )
        UserDefaults.standard.set(
            true,
            forKey: ExtensionManager
                .forceNativeCompatibilityActionPopupDefaultsKey
        )
        defer {
            UserDefaults.standard.removeObject(
                forKey: ExtensionManager
                    .nativeActionPopupBoundaryObservationDefaultsKey
            )
            UserDefaults.standard.removeObject(
                forKey: ExtensionManager
                    .forceNativeCompatibilityActionPopupDefaultsKey
            )
        }
        XCTAssertTrue(
            ExtensionManager.isNativeActionPopupBoundaryObservationEnabled
        )

        let root = try makeTemporaryDirectory()
        let module = try makeModule(enabled: true, includesModelContext: true)
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: bitwardenRoot,
            profileID: "profile-urlhub-real-bitwarden-native-popup",
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)
        XCTAssertTrue(install.succeeded)

        let syncedAction = await waitForEnabledExtension(
            in: module,
            extensionId: record.extensionID
        )
        XCTAssertNotNil(syncedAction)
        let manager = try XCTUnwrap(module.managerIfEnabled())
        XCTAssertNil(manager.extensionController)

        let result = await module.openActionPopupFromURLHub(
            extensionId: record.extensionID,
            currentTab: Tab(url: URL(string: "https://example.com/login")!)
        )

        XCTAssertTrue(result.opened, result.message)
        XCTAssertNil(result.blocker)
        XCTAssertTrue(result.sanitizedBridgeSnapshotDiagnostics.contains {
            $0.contains("selectedPopupPath=nativeWebKitActionPopup")
                && $0.contains("reason=debugForceNativeActionPopup")
        })

        let snapshot = try await waitForNativeBitwardenPopupPreludeSnapshot(
            manager: manager,
            extensionID: record.extensionID,
            initialSnapshot: result.nativePopupBoundarySnapshot
        )
        let noCaptureReason = nativeBitwardenPopupNoCaptureReason(snapshot)
        let firstBlocker = nativeBitwardenPopupFirstBlocker(snapshot)
        let prototypeMethodDescriptor =
            "descriptor:data/owner:prototype/prototypeDepth:1/writable:false/configurable:true/enumerable:false/getter:false/setter:false/objectExtensible:true/descriptorOwnerExtensible:true/namespaceExtensible:true"
        let ownMethodDescriptor =
            "descriptor:data/owner:own/prototypeDepth:0/writable:false/configurable:true/enumerable:false/getter:false/setter:false/objectExtensible:true/descriptorOwnerExtensible:true/namespaceExtensible:true"
        for apiName in [
            "chrome.runtime.sendMessage",
            "chrome.runtime.connect",
            "chrome.tabs.query",
            "chrome.tabs.sendMessage",
            "browser.runtime.sendMessage",
            "browser.runtime.connect",
            "browser.tabs.query",
            "browser.tabs.sendMessage",
        ] {
            XCTAssertTrue(snapshot.routeObservations.contains {
                $0.apiName == apiName
                    && $0.resultClassifier == "descriptorObserved"
                    && $0.descriptorSummary == prototypeMethodDescriptor
            }, apiName)
            XCTAssertTrue(snapshot.routeObservations.contains {
                $0.apiName == apiName
                    && $0.resultClassifier == "notWritable"
                    && $0.firstMissingAPIOrError == "methodNotWritable"
            }, apiName)
        }
        for apiName in [
            "chrome.runtime.connectNative",
            "chrome.runtime.sendNativeMessage",
            "browser.runtime.connectNative",
            "browser.runtime.sendNativeMessage",
        ] {
            XCTAssertTrue(snapshot.routeObservations.contains {
                $0.apiName == apiName
                    && $0.resultClassifier == "descriptorObserved"
                    && $0.descriptorSummary == ownMethodDescriptor
            }, apiName)
            XCTAssertTrue(snapshot.routeObservations.contains {
                $0.apiName == apiName
                    && $0.resultClassifier == "notWritable"
                    && $0.firstMissingAPIOrError == "methodNotWritable"
            }, apiName)
        }

        XCTAssertTrue(
            snapshot.nativePopupPreludeConfiguredBeforePopupCreation,
            "Prelude was not configured before WebKit controller creation."
        )
        XCTAssertNotEqual(noCaptureReason, "preludeDidNotInstallBeforeExtensionManagerCreation")

        let encodedSnapshot = String(
            data: try JSONEncoder().encode(snapshot),
            encoding: .utf8
        ) ?? ""
        XCTAssertFalse(encodedSnapshot.contains("https://example.com/login"))
        XCTAssertFalse(encodedSnapshot.localizedCaseInsensitiveContains("password"))
        XCTAssertFalse(encodedSnapshot.localizedCaseInsensitiveContains("token"))
        XCTAssertFalse(encodedSnapshot.localizedCaseInsensitiveContains("vault"))
        XCTAssertEqual(
            bitwardenNativeHostRunningApplicationIdentifiers(),
            nativeHostWasRunning,
            "The DEBUG native popup capture harness must not launch com.bitwarden.desktop."
        )

        print("SumiNativeBitwardenPopupCapture preludeConfiguredBeforePopupCreation=\(snapshot.nativePopupPreludeConfiguredBeforePopupCreation)")
        print("SumiNativeBitwardenPopupCapture preludeAttachedAtDocumentStart=\(snapshot.nativePopupPreludeAttachedAtDocumentStart)")
        print("SumiNativeBitwardenPopupCapture routeRecords=\(snapshot.routeObservations.count)")
        print("SumiNativeBitwardenPopupCapture noCaptureReason=\(noCaptureReason)")
        print("SumiNativeBitwardenPopupCapture firstBlocker=\(firstBlocker)")
        for line in snapshot.sanitizedLogLines {
            print("SumiNativeBitwardenPopupCapture \(line)")
        }
    }

    @MainActor
    func testDebugControlledBitwardenURLHubActionPopupSpinnerDiagnostics()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Controlled popup WKWebView diagnostics require macOS 15.5.")
        }

        let bitwardenRoot = URL(
            fileURLWithPath:
                "/Users/fedaefimov/Downloads/Aura/mv3-test-extensions/bitwarden",
            isDirectory: true
        )
        try XCTSkipUnless(
            FileManager.default.fileExists(
                atPath: bitwardenRoot.appendingPathComponent("manifest.json").path
            ),
            "Local Bitwarden package is not available."
        )

        let nativeHostWasRunning =
            bitwardenNativeHostRunningApplicationIdentifiers()

        let root = try makeTemporaryDirectory()
        let profileID = UUID()
        let module = try makeModule(
            enabled: true,
            includesModelContext: true,
            popupOptionsWebViewFactory: {
                ChromeMV3ProductPopupOptionsWKWebViewFactory(
                    loadingMode: .fileBacked
                )
            }
        )
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: bitwardenRoot,
            profileID: profileID.uuidString,
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)
        XCTAssertTrue(install.succeeded)
        if let lifecycle =
            module.chromeMV3LocalLifecycleDispatchResultForTesting
        {
            print(
                "SumiControlledBitwardenPopupLifecycle event=\(lifecycle.event.rawValue) reason=\(lifecycle.reason) attempted=\(lifecycle.attempted) captured=\(lifecycle.captured) dispatched=\(lifecycle.dispatched) startStatus=\(lifecycle.startStatus.rawValue) dispatchResult=\(lifecycle.dispatchResultKind?.rawValue ?? "none") dispatchRecordCount=\(lifecycle.dispatchRecordCount) storageLocalLoaded=\(lifecycle.storageLocalLoadedExistingSnapshot) storageLocalSeeded=\(lifecycle.storageLocalSeededIntoWorker) storageLocalPersisted=\(lifecycle.storageLocalPersistedFromWorker) storageLocalInitialKeyCount=\(lifecycle.storageLocalInitialKeyCount) storageLocalFinalKeyCount=\(lifecycle.storageLocalFinalKeyCount) storageLocalWriteCount=\(lifecycle.storageLocalWriteCount) nativeHost=\(lifecycle.nativeHostLaunchAttempted) runtimeObjectsCreated=\(lifecycle.runtimeObjectsCreated)"
            )
        } else {
            print("SumiControlledBitwardenPopupLifecycle result=none")
        }
        _ = await waitForEnabledExtension(
            in: module,
            extensionId: record.extensionID
        )

        let currentTab = Tab(url: URL(string: "https://example.com/login")!)
        currentTab.profileId = profileID
        let installedAction = try XCTUnwrap(
            module.surfaceStore.enabledExtensions.first {
                $0.id == record.extensionID
            }
        )
        let preflightLaunchRecord =
            ChromeMV3ProductPopupOptionsLaunchPlanner
            .controlledActionPopupLaunchRecord(
                rootURL: ChromeMV3ExtensionManagerStoreLocation
                    .defaultRootURL(),
                profileID: profileID.uuidString,
                installedExtension: installedAction,
                managerGate: module.chromeMV3ExtensionManagerGate(),
                moduleEnabled: true
            )
        let preflightSummary =
            controlledBitwardenPopupPreflightSummary(
                preflightLaunchRecord
            )
        print("SumiControlledBitwardenPopup \(preflightSummary)")
        let result = await module.openActionPopupFromURLHub(
            extensionId: record.extensionID,
            currentTab: currentTab
        )

        guard result.opened else {
            XCTFail("\(result.message) \(preflightSummary)")
            XCTAssertEqual(
                bitwardenNativeHostRunningApplicationIdentifiers(),
                nativeHostWasRunning,
                "The controlled Bitwarden popup diagnostics must not launch com.bitwarden.desktop."
            )
            return
        }
        XCTAssertNil(result.blocker)
        XCTAssertNil(result.nativePopupBoundarySnapshot)
        XCTAssertTrue(result.sanitizedBridgeSnapshotDiagnostics.contains {
            $0.contains("controlled file-backed compatibility popup host")
        })
        XCTAssertTrue(result.sanitizedBridgeSnapshotDiagnostics.contains {
            $0.contains(
                "selectedPopupPath=controlledCompatibilityActionPopup"
            )
        })

        let snapshot = try await waitForControlledBitwardenPopupBridgeSnapshot(
            module: module,
            profileID: record.profileID,
            extensionID: record.extensionID
        )
        let domState = try await controlledBitwardenPopupDOMState(
            module: module,
            profileID: record.profileID,
            extensionID: record.extensionID
        )
        let firstBlocker =
            controlledBitwardenPopupFirstFatalBlocker(snapshot)
        let tabsConnectFatal =
            controlledBitwardenTabsConnectActuallyFatal(snapshot)

        XCTAssertFalse(snapshot.jsDebugRouteEvents.isEmpty)
        XCTAssertNotEqual(firstBlocker, "unknown")
        XCTAssertEqual(
            snapshot.appStateDependencyTrace.correlationSummary.classification,
            "appStateWaitWithNoWriter",
            "Bitwarden controlled popup app-state classification should remain stable."
        )
        XCTAssertEqual(
            bitwardenNativeHostRunningApplicationIdentifiers(),
            nativeHostWasRunning,
            "The controlled Bitwarden popup diagnostics must not launch com.bitwarden.desktop."
        )

        let boundaryDiagnostics =
            controlledBitwardenPopupAppStateBoundaryDiagnostics(
                snapshot: snapshot,
                domStateJSON: domState
            )
        XCTAssertEqual(
            boundaryDiagnostics.firstStableAppStateClassifier,
            "appStateWaitWithNoWriter"
        )
        XCTAssertEqual(
            boundaryDiagnostics.extensionBoundaryClassifier,
            "extensionLocalAppState"
        )
        XCTAssertEqual(boundaryDiagnostics.boundaryKind, "extension-local")
        XCTAssertEqual(
            boundaryDiagnostics.nativeMessagingRequestCategory,
            "none"
        )
        XCTAssertEqual(
            boundaryDiagnostics.nativeMessagingResultCategory,
            "notRequested"
        )
        XCTAssertNotEqual(
            boundaryDiagnostics.portRouteCategory,
            "failed"
        )
        XCTAssertEqual(boundaryDiagnostics.storageCategory, "readNoWriter")

        recordControlledBitwardenPopupSanitizedDiagnostics(
            prefix: "SumiControlledBitwardenPopup",
            snapshot: snapshot,
            domState: domState,
            firstBlocker: firstBlocker,
            tabsConnectFatal: tabsConnectFatal,
            boundaryDiagnostics: boundaryDiagnostics
        )

        _ = module.chromeMV3ClosePopupOptionsThroughManager(
            profileID: record.profileID,
            extensionID: record.extensionID
        )
    }

    @MainActor
    func testDebugBitwardenLivePopupProductPathTraceCapturesHarnessMismatch()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Live popup product-path trace requires macOS 15.5.")
        }

        let bitwardenRoot = URL(
            fileURLWithPath:
                "/Users/fedaefimov/Downloads/Aura/mv3-test-extensions/bitwarden",
            isDirectory: true
        )
        try XCTSkipUnless(
            FileManager.default.fileExists(
                atPath: bitwardenRoot.appendingPathComponent("manifest.json").path
            ),
            "Local Bitwarden package is not available."
        )

        let root = try makeTemporaryDirectory()
        let profileID = UUID()
        let module = try makeModule(enabled: true, includesModelContext: true)
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: bitwardenRoot,
            profileID: profileID.uuidString,
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)
        _ = await waitForEnabledExtension(
            in: module,
            extensionId: record.extensionID
        )

        let currentTab = Tab(url: URL(string: "https://example.com/login")!)
        currentTab.profileId = profileID
        let result = await module.openActionPopupFromURLHub(
            extensionId: record.extensionID,
            currentTab: currentTab
        )
        XCTAssertTrue(result.opened, result.message)

        let trace = await module.chromeMV3AwaitLivePopupProductPathTraceForTesting(
            timeoutSeconds: 12
        )
        let resolvedTrace = try XCTUnwrap(trace)
        for line in resolvedTrace.compactSanitizedLogLines {
            print("SumiLivePopupProductPathTrace \(line)")
        }

        XCTAssertEqual(
            resolvedTrace.actualPopupPath,
            ChromeMV3CompatibilityActionPopupPath
                .controlledCompatibilityActionPopup.rawValue
        )
        XCTAssertTrue(resolvedTrace.webViewCreated)
        XCTAssertTrue(resolvedTrace.bridgeInstalled)
        XCTAssertEqual(
            resolvedTrace.failureClassifier,
            .unknown,
            "Harness opens without a live URL-hub anchor; popover presentation is unavailable in tests."
        )
        XCTAssertFalse(resolvedTrace.popoverPresented)
        XCTAssertTrue(
            resolvedTrace.presentationSkipReason == "anchorViewMissing"
                || resolvedTrace.presentationSkipReason
                    == "anchorWindowUnavailable"
                || resolvedTrace.presentationSkipReason
                    == "anchorWindowRetryExhausted"
                || resolvedTrace.presentationSkipReason == "none"
        )
        XCTAssertFalse(resolvedTrace.nativeHostLaunched)

        _ = module.chromeMV3ClosePopupOptionsThroughManager(
            profileID: record.profileID,
            extensionID: record.extensionID
        )
    }

    @MainActor
    func testDebugLivePopupServiceWorkerOnConnectBucketsUseBridgeRoutesNotPopupRegistrations()
    {
        let popupOnMessageRegistration = [
            ChromeMV3PopupOptionsJSDebugRouteEventRecord(
                sequence: 1,
                eventKind: "extensionMethodCalled",
                apiName: "runtime.onMessage.addListener",
                sourceContext: "actionPopup",
                targetContext: "popup",
                safeMessageShapeClassification: "shape=unknown",
                safeCommandTypeActionFieldNames: [],
                diagnostics: []
            ),
        ]
        let bucketsWithoutRoutes =
            ChromeMV3LivePopupProductPathTraceBuilder.apiRouteCountBuckets(
                from: popupOnMessageRegistration
            )
        XCTAssertEqual(bucketsWithoutRoutes.serviceWorkerOnMessageListener, 0)
        XCTAssertEqual(bucketsWithoutRoutes.serviceWorkerOnConnectListener, 0)

        let connectRoute = ChromeMV3PopupOptionsSanitizedBridgeRouteRecord(
            extensionIDHash: "abc",
            profileID: "profile",
            sourceContext: "actionPopup",
            targetContext: "serviceWorker",
            apiName: "runtime.connect",
            safeMessageShapeClassification: "shape=unknown",
            safeCommandTypeActionFieldNames: [],
            listenerCount: 3,
            listenerInvoked: true,
            sendResponseCalled: false,
            listenerReturnedTrue: false,
            listenerThrew: false,
            portName: "callerProvided",
            portMessageCount: 0,
            resultClassifier: "delivered",
            firstMissingAPIOrPermissionOrLifecycleError: nil,
            diagnostics: [
                "runtime.connect delivered a named Port to captured service-worker runtime.onConnect JavaScript listener(s).",
            ]
        )
        let bucketsWithRoutes =
            ChromeMV3LivePopupProductPathTraceBuilder.apiRouteCountBuckets(
                from: popupOnMessageRegistration,
                routeRecords: [connectRoute],
                harnessOnConnectListenerCount: 6
            )
        XCTAssertEqual(bucketsWithRoutes.serviceWorkerOnConnectListener, 3)
        XCTAssertEqual(bucketsWithRoutes.serviceWorkerOnMessageListener, 0)

        var trace = makeLivePopupBootstrapGapTrace()
        trace.stagedSnapshots = [
            ChromeMV3LivePopupStagedSnapshot(
                stage: "after3000ms",
                readyState: "loading",
                navigationStarted: true,
                navigationFinished: true,
                urlLoaded: true,
                firstJSCheckpoint: true,
                bridgeInstalled: true,
                scriptsExecuted: true,
                runtimeErrorCategory: "none",
                consoleErrorCategory: "none",
                unhandledRejectionCategory: "none",
                appRootPresent: true,
                bodyChildCountBucket: "1-3",
                appRootChildCountBucket: "0",
                visibleTextBucket: "0",
                formControlCountBucket: "0",
                buttonCountBucket: "0",
                ariaBusyOrLoadingCategory: "none",
                storageReadCountBucket: "1-3",
                storageWriteCountBucket: "0",
                runtimeSendMessageCountBucket: "0",
                runtimeConnectCountBucket: "1-3",
                portMessageCountBucket: "0",
                tabsQueryCountBucket: "0",
                tabsSendMessageCountBucket: "0",
                scriptingExecuteScriptCountBucket: "0",
                pendingBridgeRoutesBucket: "0",
                serviceWorkerOnMessageListenerCountBucket: "0",
                serviceWorkerOnConnectListenerCountBucket: "1-3",
                nativeMessagingRequestCountBucket: "0",
                nativeMessagingResultCategory: "notRequested",
                swOutboxCapturedCountBucket: "0",
                swOutboxDeliveredToPopupCountBucket: "0",
                popupPortOnMessageListenerCategory: "listenerRegistered",
                pendingInboundPortMessagesBucket: "0",
                portDisconnectCategory: "notObserved"
            ),
        ]
        XCTAssertNotEqual(
            ChromeMV3LivePopupProductPathTraceBuilder.classifyBootstrapFailure(
                trace: trace,
                routeEvents: popupOnMessageRegistration,
                routeRecords: [connectRoute],
                harnessOnConnectCount: 6
            ),
            .popupWaitingOnServiceWorkerListener
        )

        let missingListenerRoute = ChromeMV3PopupOptionsSanitizedBridgeRouteRecord(
            extensionIDHash: "abc",
            profileID: "profile",
            sourceContext: "actionPopup",
            targetContext: "serviceWorker",
            apiName: "runtime.connect",
            safeMessageShapeClassification: "shape=unknown",
            safeCommandTypeActionFieldNames: [],
            listenerCount: 0,
            listenerInvoked: false,
            sendResponseCalled: false,
            listenerReturnedTrue: false,
            listenerThrew: false,
            portName: "callerProvided",
            portMessageCount: 0,
            resultClassifier: "noReceivingEnd",
            firstMissingAPIOrPermissionOrLifecycleError: nil,
            diagnostics: [
                "listenerCount=0",
                "listenerInvoked=false",
                "runtime.connect returned a popup/options-scoped synthetic Port object.",
            ]
        )
        // When the staged snapshots captured live service-worker onConnect
        // listeners (bucket 1-3), a connect route that reported no receiving end
        // is a connect/startup ordering issue, not a permanently missing
        // listener. The classifier must reconcile the staged listener evidence
        // and must not return .serviceWorkerOnConnectListenerMissing using a
        // stale top-level harness count of zero.
        XCTAssertEqual(
            ChromeMV3LivePopupProductPathTraceBuilder.classifyServiceWorkerConnectBlocker(
                trace: trace,
                routeEvents: popupOnMessageRegistration,
                routeRecords: [missingListenerRoute]
            ),
            .serviceWorkerConnectDispatchedBeforeStartup
        )

        // A genuinely missing listener (staged onConnect bucket 0 and a connect
        // route with no receiving end) is still classified as missing.
        var genuinelyMissingTrace = trace
        genuinelyMissingTrace.stagedSnapshots = trace.stagedSnapshots.map {
            var snapshot = $0
            snapshot.serviceWorkerOnConnectListenerCountBucket = "0"
            return snapshot
        }
        XCTAssertEqual(
            ChromeMV3LivePopupProductPathTraceBuilder.classifyServiceWorkerConnectBlocker(
                trace: genuinelyMissingTrace,
                routeEvents: popupOnMessageRegistration,
                routeRecords: [missingListenerRoute]
            ),
            .serviceWorkerOnConnectListenerMissing
        )
    }

    @MainActor
    func testDebugLivePopupProductPathClassifierDetectsPresentationMismatch()
    {
        let domVisible = ChromeMV3LivePopupDOMCheckpoint(
            readyState: "complete",
            visibleTextLengthBucket: "21-100",
            controlCountBucket: "4-10",
            bodyChildCount: 3,
            appRootPresent: true,
            navigationCommitted: true,
            visibilityCategory: "visible",
            backgroundCategory: "white"
        )
        let trace = ChromeMV3LivePopupProductPathTrace(
            productPath: .urlHubActionClick,
            expectedPopupPath: "controlledCompatibilityActionPopup",
            actualPopupPath: "controlledCompatibilityActionPopup",
            extensionIDHash: "abc",
            profileIDHash: "def",
            loadingMode: "fileBacked",
            forceNativeActionPopup: false,
            forceControlledCompatibilityActionPopupOff: false,
            compatibilityPolicyState: "allowed",
            compatibilityPolicyReason: "test",
            selectedTabBound: true,
            anchorKind: "urlHubActionTile",
            anchorViewAvailable: true,
            anchorInWindow: true,
            anchorBoundsSizeBucket: "medium",
            popupHostCreated: true,
            popoverPresented: true,
            popoverShown: true,
            presentationAttempts: 1,
            presentationSkipReason: nil,
            contentViewAttachedToWindow: true,
            contentViewSizeBucket: "large",
            popoverContentSizeBucket: "large",
            webViewCreated: true,
            webViewAttachedToHost: true,
            webViewFrameSizeBucket: "zero",
            webViewHidden: false,
            webViewAlphaBucket: "opaque",
            webViewInWindowHierarchy: true,
            webViewDeallocated: false,
            loadedURLCategory: "file",
            navigationStarted: true,
            navigationFinished: true,
            navigationFailed: false,
            urlLoadCommitted: true,
            generatedRootHandlerActive: false,
            bridgeInstalled: true,
            scriptsExecuted: true,
            firstJSCheckpointReached: true,
            runtimeErrorCategory: nil,
            firstDOMCheckpoint: domVisible,
            finalDOMCheckpoint: domVisible,
            dismissReason: nil,
            nativeHostLaunched: false,
            selectedPopupPath: "controlledCompatibilityActionPopup",
            requiredResourceLoadFailure: false,
            resourceFailureCategory: nil,
            resourceLoadBlockerCategory: nil,
            extensionClassifier: nil,
            extensionBlankedDOM: false,
            popupHostSessionIdentityHash: "session",
            webViewIdentityHash: "webview",
            bridgeHandlerIdentityHash: "bridge",
            popoverDisplaysSameWebViewAsLoaded: true,
            contentViewReplacedWebView: false,
            failureClassifier: .unknown,
            stagedSnapshots: [],
            lifecycleEventCategories: [],
            diagnostics: []
        )

        XCTAssertEqual(
            ChromeMV3LivePopupProductPathTraceBuilder.classify(trace),
            .popoverPresentedButWebViewZeroSize
        )

        var domProbeMismatch = trace
        domProbeMismatch.webViewFrameSizeBucket = "large"
        domProbeMismatch.contentViewAttachedToWindow = false
        XCTAssertEqual(
            ChromeMV3LivePopupProductPathTraceBuilder.classify(domProbeMismatch),
            .popoverPresentedButDOMVisibleInProbeButNotOnScreen
        )
    }

    @MainActor
    func testDebugLivePopupProductPathClassifierDetectsEmptyAppRootBootstrapGap()
    {
        let emptyDOM = ChromeMV3LivePopupDOMCheckpoint(
            readyState: "complete",
            visibleTextLengthBucket: "0",
            controlCountBucket: "0",
            bodyChildCount: 1,
            appRootPresent: true,
            navigationCommitted: true,
            visibilityCategory: "unknown",
            backgroundCategory: "white"
        )
        let staged = ChromeMV3LivePopupStagedSnapshot(
            stage: "after3000ms",
            readyState: "complete",
            navigationStarted: true,
            navigationFinished: true,
            urlLoaded: true,
            firstJSCheckpoint: false,
            bridgeInstalled: true,
            scriptsExecuted: true,
            runtimeErrorCategory: "none",
            consoleErrorCategory: "none",
            unhandledRejectionCategory: "none",
            appRootPresent: true,
            bodyChildCountBucket: "1-3",
            appRootChildCountBucket: "0",
            visibleTextBucket: "0",
            formControlCountBucket: "0",
            buttonCountBucket: "0",
            ariaBusyOrLoadingCategory: "none",
            storageReadCountBucket: "0",
            storageWriteCountBucket: "0",
            runtimeSendMessageCountBucket: "0",
            runtimeConnectCountBucket: "0",
            portMessageCountBucket: "0",
            tabsQueryCountBucket: "0",
            tabsSendMessageCountBucket: "0",
            scriptingExecuteScriptCountBucket: "0",
            pendingBridgeRoutesBucket: "0",
            serviceWorkerOnMessageListenerCountBucket: "0",
            serviceWorkerOnConnectListenerCountBucket: "0",
            nativeMessagingRequestCountBucket: "0",
            nativeMessagingResultCategory: "notRequested",
            swOutboxCapturedCountBucket: "0",
            swOutboxDeliveredToPopupCountBucket: "0",
            popupPortOnMessageListenerCategory: "notObserved",
            pendingInboundPortMessagesBucket: "0",
            portDisconnectCategory: "notObserved"
        )
        let trace = ChromeMV3LivePopupProductPathTrace(
            productPath: .urlHubActionClick,
            expectedPopupPath: "controlledCompatibilityActionPopup",
            actualPopupPath: "controlledCompatibilityActionPopup",
            extensionIDHash: "abc",
            profileIDHash: "def",
            loadingMode: "fileBacked",
            forceNativeActionPopup: false,
            forceControlledCompatibilityActionPopupOff: false,
            compatibilityPolicyState: "allowed",
            compatibilityPolicyReason: "test",
            selectedTabBound: true,
            anchorKind: "urlHubActionTile",
            anchorViewAvailable: true,
            anchorInWindow: true,
            anchorBoundsSizeBucket: "large",
            popupHostCreated: true,
            popoverPresented: true,
            popoverShown: true,
            presentationAttempts: 1,
            presentationSkipReason: nil,
            contentViewAttachedToWindow: true,
            contentViewSizeBucket: "large",
            popoverContentSizeBucket: "large",
            webViewCreated: true,
            webViewAttachedToHost: true,
            webViewFrameSizeBucket: "large",
            webViewHidden: false,
            webViewAlphaBucket: "opaque",
            webViewInWindowHierarchy: true,
            webViewDeallocated: false,
            loadedURLCategory: "file",
            navigationStarted: true,
            navigationFinished: true,
            navigationFailed: false,
            urlLoadCommitted: true,
            generatedRootHandlerActive: false,
            bridgeInstalled: true,
            scriptsExecuted: true,
            firstJSCheckpointReached: false,
            runtimeErrorCategory: nil,
            firstDOMCheckpoint: emptyDOM,
            finalDOMCheckpoint: emptyDOM,
            dismissReason: nil,
            nativeHostLaunched: false,
            selectedPopupPath: "controlledCompatibilityActionPopup",
            requiredResourceLoadFailure: false,
            resourceFailureCategory: nil,
            resourceLoadBlockerCategory: nil,
            extensionClassifier: nil,
            extensionBlankedDOM: false,
            popupHostSessionIdentityHash: "session",
            webViewIdentityHash: "webview",
            bridgeHandlerIdentityHash: "bridge",
            popoverDisplaysSameWebViewAsLoaded: true,
            contentViewReplacedWebView: false,
            failureClassifier: .unknown,
            stagedSnapshots: [staged],
            lifecycleEventCategories: [],
            diagnostics: []
        )

        XCTAssertEqual(
            ChromeMV3LivePopupProductPathTraceBuilder.classify(trace),
            .popupBootstrapCheckpointMissing
        )
    }

    @MainActor
    func testDebugLiveUsablePopupFixtureLocationResolvesRepositoryFixture() {
        XCTAssertNotNil(ChromeMV3LiveUsablePopupFixtureLocation.packageRoot())
        XCTAssertTrue(
            ChromeMV3LiveUsablePopupFixtureLocation.resolvedPathDescription()
                .contains("mv3-sumi-usable-popup")
        )
    }

    @MainActor
    func testDebugLivePopupStagedSummaryGroupsOrderedStages() {
        let trace = makeLivePopupBootstrapGapTrace()
        let lines =
            ChromeMV3LivePopupProductPathTraceBuilder.stagedSummaryLogLines(
                trace: trace,
                extensionLabel: "bitwarden-extension-id"
            )
        XCTAssertEqual(lines.first, lines.first(where: {
            $0.hasPrefix(
                "BEGIN live-popup-staged-summary extension=bitwarden-extension-id"
            )
        }))
        XCTAssertEqual(lines.last, "END live-popup-staged-summary")
        XCTAssertTrue(
            lines.contains(where: { $0.hasPrefix("stage=after3000ms") })
        )
    }

    @MainActor
    func testDebugLivePopupProductPathClassifierReconcilesLatestStagedSnapshot()
    {
        let staged = ChromeMV3LivePopupStagedSnapshot(
            stage: "after3000ms",
            readyState: "complete",
            navigationStarted: true,
            navigationFinished: true,
            urlLoaded: true,
            firstJSCheckpoint: true,
            bridgeInstalled: true,
            scriptsExecuted: true,
            runtimeErrorCategory: "none",
            consoleErrorCategory: "none",
            unhandledRejectionCategory: "none",
            appRootPresent: true,
            bodyChildCountBucket: "4-10",
            appRootChildCountBucket: "1-3",
            visibleTextBucket: "21-100",
            formControlCountBucket: "1-3",
            buttonCountBucket: "1-3",
            ariaBusyOrLoadingCategory: "none",
            storageReadCountBucket: "0",
            storageWriteCountBucket: "0",
            runtimeSendMessageCountBucket: "1-3",
            runtimeConnectCountBucket: "0",
            portMessageCountBucket: "0",
            tabsQueryCountBucket: "0",
            tabsSendMessageCountBucket: "0",
            scriptingExecuteScriptCountBucket: "0",
            pendingBridgeRoutesBucket: "0",
            serviceWorkerOnMessageListenerCountBucket: "0",
            serviceWorkerOnConnectListenerCountBucket: "0",
            nativeMessagingRequestCountBucket: "0",
            nativeMessagingResultCategory: "notRequested",
            swOutboxCapturedCountBucket: "0",
            swOutboxDeliveredToPopupCountBucket: "0",
            popupPortOnMessageListenerCategory: "notObserved",
            pendingInboundPortMessagesBucket: "0",
            portDisconnectCategory: "notObserved"
        )
        var trace = makeLivePopupBootstrapGapTrace()
        trace.loadingMode = "fileBacked"
        trace.scriptsExecuted = false
        trace.firstJSCheckpointReached = false
        trace.requiredResourceLoadFailure = false
        trace.stagedSnapshots = [staged]
        trace.failureClassifier = .unknown

        let reconciled =
            ChromeMV3LivePopupProductPathTraceBuilder
            .reconcileTraceWithStagedSnapshots(trace)
        XCTAssertTrue(reconciled.scriptsExecuted)
        XCTAssertTrue(reconciled.firstJSCheckpointReached)
        XCTAssertEqual(
            ChromeMV3LivePopupProductPathTraceBuilder.classify(reconciled),
            .livePopupVisible
        )
        XCTAssertNotEqual(
            ChromeMV3LivePopupProductPathTraceBuilder.classify(reconciled),
            .popoverPresentedButScriptsNotExecuted
        )
    }

    @MainActor
    func testDebugLivePopupProductPathClassifierDetectsBridgeJSNotInjected() {
        var trace = makeLivePopupBootstrapGapTrace()
        trace.stagedSnapshots = []
        trace.scriptsExecuted = false
        trace.firstJSCheckpointReached = false
        let routeEvents = [
            ChromeMV3PopupOptionsJSDebugRouteEventRecord(
                sequence: 1,
                eventKind: "extensionMethodCalled",
                apiName: "runtime.sendMessage",
                sourceContext: "actionPopup",
                targetContext: "serviceWorker",
                safeMessageShapeClassification: "shape=unknown",
                safeCommandTypeActionFieldNames: [],
                diagnostics: []
            ),
        ]
        XCTAssertEqual(
            ChromeMV3LivePopupProductPathTraceBuilder.classify(
                trace,
                routeEvents: routeEvents
            ),
            .popoverPresentedButScriptsNotExecuted
        )
        XCTAssertEqual(
            ChromeMV3LivePopupProductPathTraceBuilder.classifyBootstrapFailure(
                trace: trace,
                routeEvents: routeEvents
            ),
            .popupBridgeJSNotInjected
        )

        trace.scriptsExecuted = true
        XCTAssertNotEqual(
            ChromeMV3LivePopupProductPathTraceBuilder.classify(
                trace,
                routeEvents: routeEvents
            ),
            .popupBridgeJSNotInjected,
            "Executed popup scripts must not be classified as bridge-not-injected when the bootstrap probe is missing."
        )

        trace.bridgeInstalled = false
        XCTAssertEqual(
            ChromeMV3LivePopupProductPathTraceBuilder.classify(
                trace,
                routeEvents: routeEvents
            ),
            .popoverPresentedButBridgeMissing
        )
    }

    @MainActor
    func testDebugLivePopupProductPathClassifierDetectsBridgeInjectedTooLate() {
        let trace = makeLivePopupBootstrapGapTrace()
        let routeEvents = [
            ChromeMV3PopupOptionsJSDebugRouteEventRecord(
                sequence: 1,
                eventKind: "bridgeBootstrapProbe",
                apiName: "popup.bootstrapProbe",
                sourceContext: "actionPopup",
                targetContext: "platform",
                safeMessageShapeClassification: "shape=unknown",
                safeCommandTypeActionFieldNames: [],
                diagnostics: [
                    "phase=atDocumentStartBridgeInjection",
                    "bridgeInjectedTooLateCandidate=true",
                ]
            ),
            ChromeMV3PopupOptionsJSDebugRouteEventRecord(
                sequence: 2,
                eventKind: "bridgeBootstrapProbe",
                apiName: "popup.bootstrapProbe",
                sourceContext: "actionPopup",
                targetContext: "platform",
                safeMessageShapeClassification: "shape=unknown",
                safeCommandTypeActionFieldNames: [],
                diagnostics: [
                    "phase=beforeFirstExtensionScript",
                    "firstMissingAPI=none",
                ]
            ),
        ]
        XCTAssertEqual(
            ChromeMV3LivePopupProductPathTraceBuilder.classify(
                trace,
                routeEvents: routeEvents
            ),
            .popupBridgeInjectedTooLate
        )
    }

    @MainActor
    func testDebugLivePopupProductPathClassifierDetectsChromeAPIMissingBeforeBundle() {
        let trace = makeLivePopupBootstrapGapTrace()
        let routeEvents = [
            ChromeMV3PopupOptionsJSDebugRouteEventRecord(
                sequence: 1,
                eventKind: "bridgeBootstrapProbe",
                apiName: "popup.bootstrapProbe",
                sourceContext: "actionPopup",
                targetContext: "platform",
                safeMessageShapeClassification: "shape=unknown",
                safeCommandTypeActionFieldNames: [],
                diagnostics: [
                    "phase=atDocumentStartBridgeInjection",
                    "bridgeInjectedTooLateCandidate=false",
                ]
            ),
            ChromeMV3PopupOptionsJSDebugRouteEventRecord(
                sequence: 2,
                eventKind: "bridgeBootstrapProbe",
                apiName: "popup.bootstrapProbe",
                sourceContext: "actionPopup",
                targetContext: "platform",
                safeMessageShapeClassification: "shape=unknown",
                safeCommandTypeActionFieldNames: [],
                firstMissingAPIOrPermissionOrLifecycleError: "chrome.runtime",
                diagnostics: [
                    "phase=beforeFirstExtensionScript",
                    "firstMissingAPI=chrome.runtime",
                ]
            ),
        ]
        XCTAssertEqual(
            ChromeMV3LivePopupProductPathTraceBuilder.classify(
                trace,
                routeEvents: routeEvents
            ),
            .popupChromeAPIMissingBeforeBundle
        )
    }

    private func makeLivePopupBootstrapGapTrace()
        -> ChromeMV3LivePopupProductPathTrace
    {
        let emptyDOM = ChromeMV3LivePopupDOMCheckpoint(
            readyState: "complete",
            visibleTextLengthBucket: "0",
            controlCountBucket: "0",
            bodyChildCount: 1,
            appRootPresent: true,
            navigationCommitted: true,
            visibilityCategory: "unknown",
            backgroundCategory: "white"
        )
        let staged = ChromeMV3LivePopupStagedSnapshot(
            stage: "after3000ms",
            readyState: "complete",
            navigationStarted: true,
            navigationFinished: true,
            urlLoaded: true,
            firstJSCheckpoint: false,
            bridgeInstalled: true,
            scriptsExecuted: true,
            runtimeErrorCategory: "none",
            consoleErrorCategory: "none",
            unhandledRejectionCategory: "none",
            appRootPresent: true,
            bodyChildCountBucket: "1-3",
            appRootChildCountBucket: "0",
            visibleTextBucket: "0",
            formControlCountBucket: "0",
            buttonCountBucket: "0",
            ariaBusyOrLoadingCategory: "none",
            storageReadCountBucket: "0",
            storageWriteCountBucket: "0",
            runtimeSendMessageCountBucket: "0",
            runtimeConnectCountBucket: "0",
            portMessageCountBucket: "0",
            tabsQueryCountBucket: "0",
            tabsSendMessageCountBucket: "0",
            scriptingExecuteScriptCountBucket: "0",
            pendingBridgeRoutesBucket: "0",
            serviceWorkerOnMessageListenerCountBucket: "0",
            serviceWorkerOnConnectListenerCountBucket: "0",
            nativeMessagingRequestCountBucket: "0",
            nativeMessagingResultCategory: "notRequested",
            swOutboxCapturedCountBucket: "0",
            swOutboxDeliveredToPopupCountBucket: "0",
            popupPortOnMessageListenerCategory: "notObserved",
            pendingInboundPortMessagesBucket: "0",
            portDisconnectCategory: "notObserved"
        )
        return ChromeMV3LivePopupProductPathTrace(
            productPath: .urlHubActionClick,
            expectedPopupPath: "controlledCompatibilityActionPopup",
            actualPopupPath: "controlledCompatibilityActionPopup",
            extensionIDHash: "abc",
            profileIDHash: "def",
            loadingMode: "fileBacked",
            forceNativeActionPopup: false,
            forceControlledCompatibilityActionPopupOff: false,
            compatibilityPolicyState: "allowed",
            compatibilityPolicyReason: "test",
            selectedTabBound: true,
            anchorKind: "urlHubActionTile",
            anchorViewAvailable: true,
            anchorInWindow: true,
            anchorBoundsSizeBucket: "large",
            popupHostCreated: true,
            popoverPresented: true,
            popoverShown: true,
            presentationAttempts: 1,
            presentationSkipReason: nil,
            contentViewAttachedToWindow: true,
            contentViewSizeBucket: "large",
            popoverContentSizeBucket: "large",
            webViewCreated: true,
            webViewAttachedToHost: true,
            webViewFrameSizeBucket: "large",
            webViewHidden: false,
            webViewAlphaBucket: "opaque",
            webViewInWindowHierarchy: true,
            webViewDeallocated: false,
            loadedURLCategory: "file",
            navigationStarted: true,
            navigationFinished: true,
            navigationFailed: false,
            urlLoadCommitted: true,
            generatedRootHandlerActive: false,
            bridgeInstalled: true,
            scriptsExecuted: true,
            firstJSCheckpointReached: false,
            runtimeErrorCategory: nil,
            firstDOMCheckpoint: emptyDOM,
            finalDOMCheckpoint: emptyDOM,
            dismissReason: nil,
            nativeHostLaunched: false,
            selectedPopupPath: "controlledCompatibilityActionPopup",
            requiredResourceLoadFailure: false,
            resourceFailureCategory: nil,
            resourceLoadBlockerCategory: nil,
            extensionClassifier: nil,
            extensionBlankedDOM: false,
            popupHostSessionIdentityHash: "session",
            webViewIdentityHash: "webview",
            bridgeHandlerIdentityHash: "bridge",
            popoverDisplaysSameWebViewAsLoaded: true,
            contentViewReplacedWebView: false,
            failureClassifier: .unknown,
            stagedSnapshots: [staged],
            lifecycleEventCategories: [],
            diagnostics: []
        )
    }

    @MainActor
    func testDebugLivePopupProductPathClassifierDoesNotMisclassifyBitwardenLiveTraceShape()
    {
        let emptyDOM = ChromeMV3LivePopupDOMCheckpoint(
            readyState: "complete",
            visibleTextLengthBucket: "0",
            controlCountBucket: "0",
            bodyChildCount: 1,
            appRootPresent: true,
            navigationCommitted: true,
            visibilityCategory: "unknown",
            backgroundCategory: "white"
        )
        let staged = ChromeMV3LivePopupStagedSnapshot(
            stage: "after3000ms",
            readyState: "complete",
            navigationStarted: true,
            navigationFinished: true,
            urlLoaded: true,
            firstJSCheckpoint: true,
            bridgeInstalled: true,
            scriptsExecuted: true,
            runtimeErrorCategory: "none",
            consoleErrorCategory: "none",
            unhandledRejectionCategory: "none",
            appRootPresent: true,
            bodyChildCountBucket: "1-3",
            appRootChildCountBucket: "0",
            visibleTextBucket: "0",
            formControlCountBucket: "0",
            buttonCountBucket: "0",
            ariaBusyOrLoadingCategory: "none",
            storageReadCountBucket: "1-3",
            storageWriteCountBucket: "0",
            runtimeSendMessageCountBucket: "0",
            runtimeConnectCountBucket: "1-3",
            portMessageCountBucket: "0",
            tabsQueryCountBucket: "0",
            tabsSendMessageCountBucket: "0",
            scriptingExecuteScriptCountBucket: "0",
            pendingBridgeRoutesBucket: "0",
            serviceWorkerOnMessageListenerCountBucket: "0",
            serviceWorkerOnConnectListenerCountBucket: "0",
            nativeMessagingRequestCountBucket: "0",
            nativeMessagingResultCategory: "notRequested",
            swOutboxCapturedCountBucket: "1-3",
            swOutboxDeliveredToPopupCountBucket: "1-3",
            popupPortOnMessageListenerCategory: "listenerRegistered",
            pendingInboundPortMessagesBucket: "0",
            portDisconnectCategory: "none"
        )
        var trace = makeLivePopupBootstrapGapTrace()
        trace.scriptsExecuted = true
        trace.firstJSCheckpointReached = true
        trace.extensionClassifier = "extensionLocalAppState"
        trace.stagedSnapshots = [staged]
        trace.finalDOMCheckpoint = emptyDOM
        trace.firstDOMCheckpoint = emptyDOM
        let routeEvents = [
            ChromeMV3PopupOptionsJSDebugRouteEventRecord(
                sequence: 1,
                eventKind: "extensionMethodCalled",
                apiName: "runtime.connect",
                sourceContext: "actionPopup",
                targetContext: "serviceWorker",
                safeMessageShapeClassification: "shape=unknown",
                safeCommandTypeActionFieldNames: [],
                diagnostics: []
            ),
            ChromeMV3PopupOptionsJSDebugRouteEventRecord(
                sequence: 2,
                eventKind: "portSwOutboxReceived",
                apiName: "Port.onMessage",
                sourceContext: "serviceWorker",
                targetContext: "actionPopup",
                safeMessageShapeClassification: "shape=unknown",
                safeCommandTypeActionFieldNames: [],
                diagnostics: [
                    "queuedSwOutboxCountBucket=1",
                    "listenerRegistrationCategory=listenerRegistered",
                ]
            ),
            ChromeMV3PopupOptionsJSDebugRouteEventRecord(
                sequence: 3,
                eventKind: "portSwOutboxDelivered",
                apiName: "Port.onMessage",
                sourceContext: "serviceWorker",
                targetContext: "actionPopup",
                safeMessageShapeClassification: "shape=unknown",
                safeCommandTypeActionFieldNames: [],
                diagnostics: [
                    "deliveredSwToPopupCountBucket=1",
                    "listenerRegistrationCategory=listenerRegistered",
                ]
            ),
        ]

        let classifier = ChromeMV3LivePopupProductPathTraceBuilder.classify(
            trace,
            routeEvents: routeEvents
        )
        XCTAssertNotEqual(classifier, .popupBridgeJSNotInjected)
        XCTAssertEqual(classifier, .extensionLocalAppState)
        XCTAssertTrue(
            staged.compactSanitizedLogLine.contains(
                "swOutboxCapturedCountBucket=1-3"
            )
        )
        XCTAssertTrue(
            staged.compactSanitizedLogLine.contains(
                "swOutboxDeliveredToPopupCountBucket=1-3"
            )
        )
        XCTAssertTrue(
            staged.compactSanitizedLogLine.contains(
                "popupPortOnMessageListenerCategory=listenerRegistered"
            )
        )
    }

    @MainActor
    func testDebugLivePopupProductPathClassifierDetectsPortConnectedWithoutSwOutbox()
    {
        var trace = makeLivePopupBootstrapGapTrace()
        trace.scriptsExecuted = true
        trace.firstJSCheckpointReached = true
        trace.stagedSnapshots = [
            ChromeMV3LivePopupStagedSnapshot(
                stage: "after3000ms",
                readyState: "complete",
                navigationStarted: true,
                navigationFinished: true,
                urlLoaded: true,
                firstJSCheckpoint: true,
                bridgeInstalled: true,
                scriptsExecuted: true,
                runtimeErrorCategory: "none",
                consoleErrorCategory: "none",
                unhandledRejectionCategory: "none",
                appRootPresent: true,
                bodyChildCountBucket: "1-3",
                appRootChildCountBucket: "0",
                visibleTextBucket: "0",
                formControlCountBucket: "0",
                buttonCountBucket: "0",
                ariaBusyOrLoadingCategory: "none",
                storageReadCountBucket: "1-3",
                storageWriteCountBucket: "0",
                runtimeSendMessageCountBucket: "0",
                runtimeConnectCountBucket: "1-3",
                portMessageCountBucket: "0",
                tabsQueryCountBucket: "0",
                tabsSendMessageCountBucket: "0",
                scriptingExecuteScriptCountBucket: "0",
                pendingBridgeRoutesBucket: "0",
                serviceWorkerOnMessageListenerCountBucket: "0",
                serviceWorkerOnConnectListenerCountBucket: "0",
                nativeMessagingRequestCountBucket: "0",
                nativeMessagingResultCategory: "notRequested",
                swOutboxCapturedCountBucket: "0",
                swOutboxDeliveredToPopupCountBucket: "0",
                popupPortOnMessageListenerCategory: "listenerAbsent",
                pendingInboundPortMessagesBucket: "0",
                portDisconnectCategory: "none"
            ),
        ]
        let classifier = ChromeMV3LivePopupProductPathTraceBuilder.classify(trace)
        XCTAssertEqual(classifier, .portConnectedNoSwOutbox)
    }

    @MainActor
    func testDebugBitwardenRepeatedURLHubPopupOpensDoNotDuplicateHandlers()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Repeated popup handler regression requires macOS 15.5.")
        }

        let bitwardenRoot = URL(
            fileURLWithPath:
                "/Users/fedaefimov/Downloads/Aura/mv3-test-extensions/bitwarden",
            isDirectory: true
        )
        try XCTSkipUnless(
            FileManager.default.fileExists(
                atPath: bitwardenRoot.appendingPathComponent("manifest.json").path
            ),
            "Local Bitwarden package is not available."
        )

        ChromeMV3WKScriptMessageHandlerRegistration.resetDiagnosticsForTesting()
        let root = try makeTemporaryDirectory()
        let profileID = UUID()
        let module = try makeModule(enabled: true, includesModelContext: true)
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: bitwardenRoot,
            profileID: profileID.uuidString,
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)
        _ = await waitForEnabledExtension(
            in: module,
            extensionId: record.extensionID
        )

        let currentTab = Tab(url: URL(string: "https://example.com/login")!)
        currentTab.profileId = profileID
        for attempt in 1 ... 3 {
            let result = await module.openActionPopupFromURLHub(
                extensionId: record.extensionID,
                currentTab: currentTab
            )
            XCTAssertTrue(
                result.opened,
                "Bitwarden popup open attempt \(attempt) failed: \(result.message)"
            )
            _ = module.chromeMV3ClosePopupOptionsThroughManager(
                profileID: record.profileID,
                extensionID: record.extensionID
            )
        }

        XCTAssertGreaterThanOrEqual(
            ChromeMV3WKScriptMessageHandlerRegistration
                .diagnosticsSnapshot.count,
            0,
            "Repeated Bitwarden popup opens completed without duplicate-handler crash."
        )
    }

    @MainActor
    func testDebugControlledBitwardenURLHubActionPopupDiagnosticSchemeDiagnostics()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Controlled popup WKWebView diagnostics require macOS 15.5.")
        }

        let bitwardenRoot = URL(
            fileURLWithPath:
                "/Users/fedaefimov/Downloads/Aura/mv3-test-extensions/bitwarden",
            isDirectory: true
        )
        try XCTSkipUnless(
            FileManager.default.fileExists(
                atPath: bitwardenRoot.appendingPathComponent("manifest.json").path
            ),
            "Local Bitwarden package is not available."
        )

        let nativeHostWasRunning =
            bitwardenNativeHostRunningApplicationIdentifiers()

        let root = try makeTemporaryDirectory()
        let profileID = UUID()
        // This DEBUG diagnostic test specifically exercises the
        // `diagnosticCustomScheme` popup host. The live controlled-popup default
        // is now `.fileBacked` (see
        // ChromeMV3ProductPopupOptionsLoadingMode.controlledCompatibilityDefault),
        // so the diagnostic custom-scheme path must be requested explicitly.
        let module = try makeModule(
            enabled: true,
            includesModelContext: true,
            popupOptionsWebViewFactory: {
                ChromeMV3ProductPopupOptionsWKWebViewFactory(
                    loadingMode: .diagnosticCustomScheme
                )
            }
        )
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: bitwardenRoot,
            profileID: profileID.uuidString,
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)
        XCTAssertTrue(install.succeeded)
        _ = await waitForEnabledExtension(
            in: module,
            extensionId: record.extensionID
        )

        let currentTab = Tab(url: URL(string: "https://example.com/login")!)
        currentTab.profileId = profileID
        let installedAction = try XCTUnwrap(
            module.surfaceStore.enabledExtensions.first {
                $0.id == record.extensionID
            }
        )
        let preflightLaunchRecord =
            ChromeMV3ProductPopupOptionsLaunchPlanner
            .controlledActionPopupLaunchRecord(
                rootURL: ChromeMV3ExtensionManagerStoreLocation
                    .defaultRootURL(),
                profileID: profileID.uuidString,
                installedExtension: installedAction,
                managerGate: module.chromeMV3ExtensionManagerGate(),
                moduleEnabled: true
            )
        let preflightSummary =
            controlledBitwardenPopupPreflightSummary(
                preflightLaunchRecord
            )
        print("SumiControlledBitwardenPopupDiagnosticScheme \(preflightSummary)")
        let result = await module.openActionPopupFromURLHub(
            extensionId: record.extensionID,
            currentTab: currentTab
        )

        guard result.opened else {
            XCTFail("\(result.message) \(preflightSummary)")
            XCTAssertEqual(
                bitwardenNativeHostRunningApplicationIdentifiers(),
                nativeHostWasRunning,
                "The controlled Bitwarden diagnostic scheme must not launch com.bitwarden.desktop."
            )
            return
        }
        XCTAssertNil(result.blocker)
        XCTAssertNil(result.nativePopupBoundarySnapshot)
        XCTAssertTrue(result.sanitizedBridgeSnapshotDiagnostics.contains {
            $0.contains("DEBUG-only controlled custom-scheme diagnostic popup host")
        })
        XCTAssertTrue(result.sanitizedBridgeSnapshotDiagnostics.contains {
            $0.contains(
                "selectedPopupPath=controlledCompatibilityActionPopup"
            )
        })

        let snapshot = try await waitForControlledBitwardenPopupBridgeSnapshot(
            module: module,
            profileID: record.profileID,
            extensionID: record.extensionID
        )
        let domState = try await controlledBitwardenPopupDOMState(
            module: module,
            profileID: record.profileID,
            extensionID: record.extensionID
        )
        let firstBlocker =
            controlledBitwardenPopupFirstFatalBlocker(snapshot)
        let tabsConnectFatal =
            controlledBitwardenTabsConnectActuallyFatal(snapshot)
        let customSchemeResourceEvents = snapshot.jsDebugRouteEvents.filter {
            $0.apiName == "customScheme.resource"
        }
        let activeGeneratedVersion = record.generatedBundleVersions.first {
            $0.id == record.activeGeneratedVersionID
        }

        XCTAssertFalse(customSchemeResourceEvents.isEmpty)
        XCTAssertTrue(customSchemeResourceEvents.contains {
            $0.diagnostics.contains(
                "loadScheme=sumi-extension-page-diagnostic"
            )
        })
        XCTAssertNotEqual(firstBlocker, "unknown")
        XCTAssertEqual(
            bitwardenNativeHostRunningApplicationIdentifiers(),
            nativeHostWasRunning,
            "The controlled Bitwarden diagnostic scheme must not launch com.bitwarden.desktop."
        )

        recordControlledBitwardenPopupSanitizedDiagnostics(
            prefix: "SumiControlledBitwardenPopupDiagnosticScheme",
            snapshot: snapshot,
            domState: domState,
            firstBlocker: firstBlocker,
            tabsConnectFatal: tabsConnectFatal,
            extraLines: [
                "extensionID=\(record.extensionID)",
                "profileID=\(record.profileID)",
                "generatedBundleVersionID=\(record.activeGeneratedVersionID ?? "none")",
                "generatedPackageID=\(activeGeneratedVersion?.generatedBundleRecordID ?? "none")",
                "customSchemeResourceEvents=\(customSchemeResourceEvents.count)"
            ]
        )

        _ = module.chromeMV3ClosePopupOptionsThroughManager(
            profileID: record.profileID,
            extensionID: record.extensionID
        )
    }

    @MainActor
    func testDebugControlledRaindropURLHubActionPopupDefaultDiagnostics()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Controlled popup WKWebView diagnostics require macOS 15.5.")
        }

        let raindropRoot = URL(
            fileURLWithPath:
                "/Users/fedaefimov/Downloads/Aura/mv3-test-extensions/raindrop",
            isDirectory: true
        )
        try XCTSkipUnless(
            FileManager.default.fileExists(
                atPath: raindropRoot.appendingPathComponent("manifest.json").path
            ),
            "Local Raindrop package is not available."
        )

        let root = try makeTemporaryDirectory()
        let profileID = UUID()
        let module = try makeModule(
            enabled: true,
            includesModelContext: true,
            popupOptionsWebViewFactory: {
                ChromeMV3ProductPopupOptionsWKWebViewFactory(
                    loadingMode: .fileBacked
                )
            }
        )
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: raindropRoot,
            profileID: profileID.uuidString,
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)
        XCTAssertTrue(install.succeeded)
        _ = await waitForEnabledExtension(
            in: module,
            extensionId: record.extensionID
        )

        let currentTab = Tab(url: URL(string: "https://example.com/article")!)
        currentTab.profileId = profileID
        let installedAction = try XCTUnwrap(
            module.surfaceStore.enabledExtensions.first {
                $0.id == record.extensionID
            }
        )
        let preflightLaunchRecord =
            ChromeMV3ProductPopupOptionsLaunchPlanner
            .controlledActionPopupLaunchRecord(
                rootURL: ChromeMV3ExtensionManagerStoreLocation
                    .defaultRootURL(),
                profileID: profileID.uuidString,
                installedExtension: installedAction,
                managerGate: module.chromeMV3ExtensionManagerGate(),
                moduleEnabled: true
            )
        let preflightSummary =
            controlledBitwardenPopupPreflightSummary(
                preflightLaunchRecord
            )
        print("SumiControlledRaindropPopup \(preflightSummary)")
        let result = await module.openActionPopupFromURLHub(
            extensionId: record.extensionID,
            currentTab: currentTab
        )

        guard result.opened else {
            XCTAssertEqual(result.blocker, .contextUnavailable)
            XCTAssertFalse(preflightSummary.contains("validation=unsafeHTML"))
            XCTAssertTrue(preflightSummary.contains("assets/app.js"))
            XCTAssertTrue(
                preflightSummary.contains("https://api.raindrop.io/")
            )
            XCTAssertTrue(preflightSummary.contains("https://rdl.ink/"))
            XCTAssertTrue(
                preflightSummary.contains("remoteExecutableResources=")
            )
            XCTAssertTrue(result.sanitizedBridgeSnapshotDiagnostics.contains {
                $0.contains(
                    "selectedPopupPath=controlledCompatibilityActionPopup"
                )
            })
            print(
                "SumiControlledRaindropPopup reachesUsableUI=false firstBlocker=\(result.blocker?.rawValue ?? "unknown") message=\(result.message)"
            )
            return
        }
        XCTAssertNil(result.blocker)
        XCTAssertNil(result.nativePopupBoundarySnapshot)
        XCTAssertTrue(result.sanitizedBridgeSnapshotDiagnostics.contains {
            $0.contains("controlled file-backed compatibility popup host")
        })
        XCTAssertTrue(result.sanitizedBridgeSnapshotDiagnostics.contains {
            $0.contains(
                "selectedPopupPath=controlledCompatibilityActionPopup"
            )
        })

        let snapshot = try await waitForControlledBitwardenPopupBridgeSnapshot(
            module: module,
            profileID: record.profileID,
            extensionID: record.extensionID
        )
        let domState = try await controlledBitwardenPopupDOMState(
            module: module,
            profileID: record.profileID,
            extensionID: record.extensionID
        )
        let firstBlocker =
            controlledBitwardenPopupFirstFatalBlocker(snapshot)
        let tabsConnectFatal =
            controlledBitwardenTabsConnectActuallyFatal(snapshot)

        XCTAssertFalse(snapshot.jsDebugRouteEvents.isEmpty)
        recordControlledBitwardenPopupSanitizedDiagnostics(
            prefix: "SumiControlledRaindropPopup",
            snapshot: snapshot,
            domState: domState,
            firstBlocker: firstBlocker,
            tabsConnectFatal: tabsConnectFatal
        )

        _ = module.chromeMV3ClosePopupOptionsThroughManager(
            profileID: record.profileID,
            extensionID: record.extensionID
        )
    }

    @MainActor
    func testControlledRaindropURLHubActionClickExecutesParseJSWithMaterializedWebView()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Controlled popup WKWebView diagnostics require macOS 15.5.")
        }

        let raindropRoot = URL(
            fileURLWithPath:
                "/Users/fedaefimov/Downloads/Aura/mv3-test-extensions/raindrop",
            isDirectory: true
        )
        try XCTSkipUnless(
            FileManager.default.fileExists(
                atPath: raindropRoot.appendingPathComponent("manifest.json").path
            ),
            "Local Raindrop package is not available."
        )

        let context = try makeURLHubLiveTabModuleFixture(
            profileName: "URL Hub Raindrop Materialized Tab",
            useFileBackedPopupHost: true
        )
        defer { context.tearDown() }
        context.module.chromeMV3InternalNormalTabConfigurationAttachmentAllowed = true
        _ = try XCTUnwrap(
            context.module.createChromeMV3EmptyControllerOwnerIfEnabled(
                explicitControllerCreationAllowed: true
            )
        )

        let windowState = BrowserWindowState()
        let windowRegistry = WindowRegistry()
        windowRegistry.register(windowState)
        context.browserManager.windowRegistry = windowRegistry
        context.browserManager.webViewCoordinator = WebViewCoordinator()

        let manager = try XCTUnwrap(context.module.managerIfEnabled())
        let tab = context.makeTab(
            url: URL(string: "https://example.com/article")!
        )
        tab.primaryWindowId = windowState.id
        let webView = try XCTUnwrap(
            tab.makeNormalTabWebView(
                reason: "test.urlHubRaindrop.materializedNormalTab"
            )
        )
        tab._webView = webView
        guard webView.configuration.sumiIsNormalTabWebViewConfiguration else {
            throw XCTSkip(
                "Materialized WebView did not receive the normal-tab configuration marker."
            )
        }
        try XCTUnwrap(context.browserManager.webViewCoordinator).setWebView(
            webView,
            for: tab.id,
            in: windowState.id
        )
        let navigationObserver =
            ChromeMV3URLHubMaterializedTabNavigationObserver()
        webView.navigationDelegate = navigationObserver
        let navigation = webView.loadHTMLString(
            """
            <!doctype html>
            <html>
              <head><title>Raindrop Materialized Tab Fixture</title></head>
              <body><main><h1>Example article</h1><p>fixture</p></main></body>
            </html>
            """,
            baseURL: tab.url
        )
        try await navigationObserver.wait(navigation: navigation)

        let root = try makeTemporaryDirectory()
        let install = context.module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: raindropRoot,
            profileID: context.profile.id.uuidString,
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)
        XCTAssertTrue(install.succeeded)
        _ = await waitForEnabledExtension(
            in: context.module,
            extensionId: record.extensionID
        )

        let result = await context.module.openActionPopupFromURLHub(
            extensionId: record.extensionID,
            currentTab: tab
        )

        XCTAssertTrue(
            result.sanitizedBridgeSnapshotDiagnostics.contains {
                $0.contains(
                    "selectedPopupPath=controlledCompatibilityActionPopup"
                )
            },
            "Expected controlled URL-hub action popup path diagnostics: \(result.sanitizedBridgeSnapshotDiagnostics.joined(separator: " | "))"
        )

        let boundLocalTabID = try XCTUnwrap(
            manager.chromeMV3ScriptingExecuteScriptLocalTabIDIfLoaded(
                for: tab.id
            ),
            "URL-hub action click should bind the materialized normal-tab WebView."
        )
        XCTAssertGreaterThan(boundLocalTabID, 0)
        let boundTarget = try XCTUnwrap(
            manager.chromeMV3ScriptingExecuteScriptTargetIfLoaded(
                extensionID: record.extensionID,
                profileID: record.profileID,
                tabID: boundLocalTabID
            ),
            "Bound scripting target should be discoverable by the real local tab ID."
        )
        XCTAssertTrue(
            boundTarget.webView === webView,
            "Scripting target WebView should match the materialized normal-tab WebView."
        )

        guard result.opened else {
            return XCTFail(
                "Controlled Raindrop popup should open with a materialized tab: \(result.message)"
            )
        }

        let snapshot = try await waitForRaindropPostParseBridgeSnapshot(
            module: context.module,
            profileID: record.profileID,
            extensionID: record.extensionID
        )
        let executeScriptCall = try XCTUnwrap(
            raindropParseJSExecuteScriptCallRecord(in: snapshot),
            """
            Expected Raindrop popup to reach scripting.executeScript for assets/parse.js. \
            executeScriptCalls=\(raindropExecuteScriptCallSummary(in: snapshot))
            """
        )
        XCTAssertTrue(executeScriptCall.succeeded)
        XCTAssertNil(executeScriptCall.lastErrorCode)
        XCTAssertNotEqual(executeScriptCall.lastErrorCode, "contextNotLoaded")
        XCTAssertTrue(
            executeScriptCall.diagnostics.contains {
                $0.contains("executionClassifier=filesExecuted")
            },
            "executeScript diagnostics: \(executeScriptCall.diagnostics.joined(separator: " | "))"
        )
        XCTAssertTrue(
            executeScriptCall.diagnostics.contains {
                $0.contains("fileShapes=assets/parse.js")
                    || $0.contains("assets/parse.js")
            }
        )
        XCTAssertTrue(
            executeScriptCall.diagnostics.contains {
                $0.contains(
                    "scripting.executeScript target.tabId=\(boundLocalTabID)."
                )
            },
            "executeScript should target the bound local tab ID, not a hardcoded tab."
        )
        XCTAssertTrue(
            executeScriptCall.diagnostics.contains {
                $0.contains("No fake executeScript success")
                    || $0.contains(
                        "modeled no-op success is blocked"
                    )
            }
        )

        let domState = try await controlledBitwardenPopupDOMState(
            module: context.module,
            profileID: record.profileID,
            extensionID: record.extensionID
        )
        let postParseDiagnostics =
            raindropPostParseSanitizedDiagnostics(
                snapshot: snapshot,
                domStateJSON: domState
            )
        let firstPostParseBlocker = postParseDiagnostics.firstBlocker
        let firstContinuationBlocker =
            postParseDiagnostics.firstContinuationBlocker
        let firstUIDisappearanceBlocker =
            postParseDiagnostics.firstUIDisappearanceBlocker
        let bindingLogs = [
            "urlHubAction click scripting target bound tab=\(tab.id.uuidString) localTabID=\(boundLocalTabID) url=\(tab.url.absoluteString)",
            "entrypoint=urlHubActionClickScriptingTarget tab=\(boundLocalTabID) frame=0 url=\(tab.url.absoluteString)",
        ]
        let scriptingLogs = executeScriptCall.diagnostics.filter {
            $0.contains("scripting.executeScript")
                || $0.contains("executionClassifier=")
                || $0.contains("permissionClassifier=")
        }
        let resultDeliveryClassifier =
            postParseDiagnostics.resultDeliveryClassifier
        let closingDecision = postParseDiagnostics.closingDecision
        print(
            "SumiControlledRaindropMaterializedTab actionClickPath=urlHubActionClick selectedPopupPath=controlledCompatibilityActionPopup boundLocalTabID=\(boundLocalTabID) executionClassifier=filesExecuted firstPostParseBlocker=\(firstPostParseBlocker) firstContinuationBlocker=\(firstContinuationBlocker) firstUIDisappearanceBlocker=\(firstUIDisappearanceBlocker) executeScriptResultDeliveryClassifier=\(resultDeliveryClassifier) raindropClosingDecision=\(closingDecision)"
        )
        for line in bindingLogs + scriptingLogs + postParseDiagnostics.lines {
            print("SumiControlledRaindropMaterializedTab \(line)")
        }
        XCTAssertTrue(
            chromeMV3PostParseBlockerCatalog.contains(firstPostParseBlocker),
            "Unexpected post-parse blocker classification: \(firstPostParseBlocker)"
        )
        XCTAssertNotEqual(
            firstPostParseBlocker,
            "unknown",
            "Post-parse diagnostics did not classify the first blocker after assets/parse.js filesExecuted."
        )
        XCTAssertTrue(
            chromeMV3ExecuteScriptContinuationBlockerCatalog.contains(
                firstContinuationBlocker
            ),
            "Unexpected executeScript continuation blocker: \(firstContinuationBlocker)"
        )
        XCTAssertNotEqual(
            firstContinuationBlocker,
            "unknown",
            "ExecuteScript continuation diagnostics did not classify the first popup-side blocker after assets/parse.js filesExecuted."
        )
        XCTAssertNotEqual(
            firstContinuationBlocker,
            "noPopupContinuationObserved",
            "Expected popup bundled JS to observe scripting.executeScript continuation after assets/parse.js filesExecuted."
        )
        XCTAssertTrue(
            chromeMV3TransientUIDisappearanceBlockerCatalog.contains(
                firstUIDisappearanceBlocker
            ),
            "Unexpected UI disappearance blocker classification: \(firstUIDisappearanceBlocker)"
        )
        XCTAssertNotEqual(
            firstUIDisappearanceBlocker,
            "unknown",
            "Popup render timeline diagnostics did not classify the first UI disappearance blocker."
        )
        XCTAssertTrue(
            chromeMV3ExecuteScriptResultDeliveryClassifierCatalog.contains(
                resultDeliveryClassifier
            ),
            "Unexpected executeScript result-delivery classifier: \(resultDeliveryClassifier)"
        )
        XCTAssertNotEqual(
            resultDeliveryClassifier,
            "unknown",
            "ExecuteScript result-delivery diagnostics did not classify popup object-result delivery after assets/parse.js filesExecuted."
        )
        XCTAssertTrue(
            chromeMV3RaindropClosingDecisionCatalog.contains(closingDecision),
            "Unexpected Raindrop closing decision: \(closingDecision)"
        )
        XCTAssertEqual(
            closingDecision,
            "closeRaindropAsExtensionLocalRenderState",
            """
            Raindrop closing pass expected extension-local render-state blanking after confirmed object-result delivery. \
            firstPostParseBlocker=\(firstPostParseBlocker) firstContinuationBlocker=\(firstContinuationBlocker) \
            firstUIDisappearanceBlocker=\(firstUIDisappearanceBlocker) resultDeliveryClassifier=\(resultDeliveryClassifier)
            """
        )
        recordControlledBitwardenPopupSanitizedDiagnostics(
            prefix: "SumiControlledRaindropMaterializedTab",
            snapshot: snapshot,
            domState: domState,
            firstBlocker: firstPostParseBlocker,
            tabsConnectFatal: controlledBitwardenTabsConnectActuallyFatal(snapshot),
            extraLines: postParseDiagnostics.lines
                + [
                    "firstContinuationBlocker=\(firstContinuationBlocker)",
                    "firstUIDisappearanceBlocker=\(firstUIDisappearanceBlocker)",
                    "executeScriptResultDeliveryClassifier=\(resultDeliveryClassifier)",
                    "raindropClosingDecision=\(closingDecision)",
                ]
        )

        _ = context.module.chromeMV3ClosePopupOptionsThroughManager(
            profileID: record.profileID,
            extensionID: record.extensionID
        )
    }

    @MainActor
    func testURLHubActionClickReportsSelectedPackageContextLoadFailurePrecisely()
        async throws
    {
        UserDefaults.standard.set(
            true,
            forKey: ExtensionManager
                .forceNativeCompatibilityActionPopupDefaultsKey
        )
        defer {
            UserDefaults.standard.removeObject(
                forKey: ExtensionManager
                    .forceNativeCompatibilityActionPopupDefaultsKey
            )
        }
        let root = try makeTemporaryDirectory()
        let firstSource = try makeFixture(
            named: "urlhub-ready-runtime-valid-popup",
            manifest: genericActionPopupManifest(
                name: "Valid Popup",
                permissions: ["activeTab"]
            ),
            files: [
                "popup.html": "<!doctype html><title>Valid Popup</title>",
            ]
        )
        let brokenSource = try makeFixture(
            named: "urlhub-ready-runtime-broken-popup",
            manifest: genericActionPopupManifest(
                name: "Broken Popup",
                permissions: ["activeTab"]
            ),
            files: [
                "popup.html": "<!doctype html><title>Broken Popup</title>",
            ]
        )
        let module = try makeModule(enabled: true, includesModelContext: true)
        let firstInstall = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: firstSource,
            profileID: "profile-urlhub-load-failure",
            enableInternal: true
        )
        let firstRecord = try XCTUnwrap(
            firstInstall.lifecycleOperationResult?.record
        )
        _ = await waitForEnabledExtension(
            in: module,
            extensionId: firstRecord.extensionID
        )
        let manager = try XCTUnwrap(module.managerIfEnabled())
        let runtimeReady = await manager.requestExtensionRuntimeAndWait(
            reason: .extensionAction
        )
        XCTAssertTrue(runtimeReady)

        let brokenInstall = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: brokenSource,
            profileID: "profile-urlhub-load-failure",
            enableInternal: true
        )
        let brokenRecord = try XCTUnwrap(
            brokenInstall.lifecycleOperationResult?.record
        )
        let waitedBrokenAction = await waitForEnabledExtension(
            in: module,
            extensionId: brokenRecord.extensionID
        )
        let brokenAction = try XCTUnwrap(waitedBrokenAction)
        try FileManager.default.removeItem(
            at: URL(fileURLWithPath: brokenAction.packagePath)
                .appendingPathComponent("manifest.json")
        )

        let result = await module.openActionPopupFromURLHub(
            extensionId: brokenRecord.extensionID,
            currentTab: Tab(url: URL(string: "https://example.com/login")!)
        )

        XCTAssertFalse(result.opened)
        XCTAssertEqual(result.blocker, .runtimeLoadFailed)
        XCTAssertTrue(
            result.message.contains(
                "WebKit context load failed for the selected local package"
            )
        )
        XCTAssertFalse(
            result.message.contains(
                "did not produce a loaded WebKit extension context"
            )
        )
        XCTAssertNil(manager.getExtensionContext(for: brokenRecord.extensionID))
    }

    @MainActor
    func testURLHubActionClickPreflightBlocksNoPopupWithoutRuntime()
        async throws
    {
        let root = try makeTemporaryDirectory()
        let source = try makeFixture(
            named: "urlhub-action-no-popup",
            manifest: genericMV3Manifest(name: "Generic Action No Popup"),
            files: [:]
        )
        let module = try makeModule(enabled: true, includesModelContext: true)
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: source,
            profileID: "profile-urlhub-action-no-popup",
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)

        _ = await waitForEnabledExtension(
            in: module,
            extensionId: record.extensionID
        )
        let result = await module.openActionPopupFromURLHub(
            extensionId: record.extensionID,
            currentTab: Tab(url: URL(string: "https://example.com/login")!)
        )

        XCTAssertFalse(result.opened)
        XCTAssertEqual(result.blocker, .noActionPopup)
        XCTAssertFalse(result.message.isEmpty)
        XCTAssertFalse(module.hasLoadedWebExtensionController)
    }

    @MainActor
    func testURLHubActionClickPreflightBlocksMissingCurrentPagePermission()
        async throws
    {
        let root = try makeTemporaryDirectory()
        let source = try makeFixture(
            named: "urlhub-action-missing-permission",
            manifest: genericActionPopupManifest(
                name: "Generic Popup No Host Permission"
            ),
            files: [
                "popup.html": "<!doctype html><title>Popup</title>",
            ]
        )
        let module = try makeModule(enabled: true, includesModelContext: true)
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: source,
            profileID: "profile-urlhub-action-missing-permission",
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)

        _ = await waitForEnabledExtension(
            in: module,
            extensionId: record.extensionID
        )
        let result = await module.openActionPopupFromURLHub(
            extensionId: record.extensionID,
            currentTab: Tab(url: URL(string: "https://example.com/login")!)
        )

        XCTAssertFalse(result.opened)
        XCTAssertEqual(result.blocker, .currentPagePermissionMissing)
        XCTAssertFalse(result.message.isEmpty)
        XCTAssertFalse(module.hasLoadedWebExtensionController)
    }

    @MainActor
    func testURLHubActionClickPreflightBlocksDisabledExtensionWithoutRuntime()
        async throws
    {
        let root = try makeTemporaryDirectory()
        let source = try makeFixture(
            named: "urlhub-action-disabled-extension",
            manifest: genericActionPopupManifest(
                name: "Generic Popup Disabled",
                permissions: ["activeTab"]
            ),
            files: [
                "popup.html": "<!doctype html><title>Popup</title>",
            ]
        )
        let module = try makeModule(enabled: true, includesModelContext: true)
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: source,
            profileID: "profile-urlhub-action-disabled-extension",
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)

        _ = await waitForEnabledExtension(
            in: module,
            extensionId: record.extensionID
        )
        let disabled = module
            .chromeMV3SetInternalExtensionEnabledThroughManager(
                false,
                rootURL: root,
                profileID: record.profileID,
                extensionID: record.extensionID
            )
        XCTAssertTrue(disabled.succeeded)
        _ = module.managerIfEnabled()?.loadInstalledExtensionMetadata()

        let result = await module.openActionPopupFromURLHub(
            extensionId: record.extensionID,
            currentTab: Tab(url: URL(string: "https://example.com/login")!)
        )

        XCTAssertFalse(result.opened)
        XCTAssertEqual(result.blocker, .extensionDisabled)
        XCTAssertFalse(result.message.isEmpty)
        XCTAssertFalse(module.hasLoadedWebExtensionController)
    }

    @MainActor
    func testURLHubActionClickPreflightBlocksMissingEligibleTabWithoutRuntime()
        async throws
    {
        let root = try makeTemporaryDirectory()
        let source = try makeFixture(
            named: "urlhub-action-no-tab",
            manifest: genericActionPopupManifest(
                name: "Generic Popup Missing Tab",
                permissions: ["activeTab"]
            ),
            files: [
                "popup.html": "<!doctype html><title>Popup</title>",
            ]
        )
        let module = try makeModule(enabled: true, includesModelContext: true)
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: source,
            profileID: "profile-urlhub-action-no-tab",
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)

        _ = await waitForEnabledExtension(
            in: module,
            extensionId: record.extensionID
        )
        let result = await module.openActionPopupFromURLHub(
            extensionId: record.extensionID,
            currentTab: nil
        )

        XCTAssertFalse(result.opened)
        XCTAssertEqual(result.blocker, .noEligibleTab)
        XCTAssertFalse(result.message.isEmpty)
        XCTAssertFalse(module.hasLoadedWebExtensionController)
    }

    @MainActor
    func testURLHubActionClickPreflightBlocksModuleWorkerWithoutRuntime()
        async throws
    {
        let root = try makeTemporaryDirectory()
        var manifest = genericActionPopupManifest(
            name: "Generic Popup Module Worker",
            permissions: ["activeTab"]
        )
        manifest["background"] = [
            "service_worker": "background.js",
            "type": "module",
        ]
        let source = try makeFixture(
            named: "urlhub-action-module-worker",
            manifest: manifest,
            files: [
                "background.js": "export {};",
                "popup.html": "<!doctype html><title>Popup</title>",
            ]
        )
        let module = try makeModule(enabled: true, includesModelContext: true)
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: source,
            profileID: "profile-urlhub-action-module-worker",
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)

        _ = await waitForEnabledExtension(
            in: module,
            extensionId: record.extensionID
        )
        let result = await module.openActionPopupFromURLHub(
            extensionId: record.extensionID,
            currentTab: Tab(url: URL(string: "https://example.com/login")!)
        )

        XCTAssertFalse(result.opened)
        XCTAssertEqual(result.blocker, .moduleWorkerUnsupported)
        XCTAssertFalse(result.message.isEmpty)
        XCTAssertFalse(module.hasLoadedWebExtensionController)
    }

    @MainActor
    func testURLHubActionClickPreflightBlocksOffRecordExtensionWithoutRuntime()
        async throws
    {
        let root = try makeTemporaryDirectory()
        let source = try makeFixture(
            named: "urlhub-action-off-record",
            manifest: genericActionPopupManifest(
                name: "Generic Popup Off Record",
                permissions: ["activeTab"]
            ),
            files: [
                "popup.html": "<!doctype html><title>Popup</title>",
            ]
        )
        let module = try makeModule(enabled: true, includesModelContext: true)
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: source,
            profileID: "profile-urlhub-action-off-record",
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)

        _ = await waitForEnabledExtension(
            in: module,
            extensionId: record.extensionID
        )
        let privateProfile = Profile.createEphemeral()
        let browserManager = BrowserManager(extensionsModule: module)
        browserManager.profileManager.profiles = [privateProfile]
        browserManager.currentProfile = privateProfile
        let privateTab = Tab(
            url: URL(string: "https://example.com/login")!,
            browserManager: browserManager
        )
        privateTab.profileId = privateProfile.id
        XCTAssertTrue(privateTab.isEphemeral)

        let result = await module.openActionPopupFromURLHub(
            extensionId: record.extensionID,
            currentTab: privateTab
        )

        XCTAssertFalse(result.opened)
        XCTAssertEqual(result.blocker, .noEligibleTab)
        XCTAssertFalse(result.message.isEmpty)
        XCTAssertFalse(module.hasLoadedWebExtensionController)
    }

    @MainActor
    func testURLHubReflectsGenericEnableDisableState() throws {
        let root = try makeTemporaryDirectory()
        let source = try makeFixture(
            named: "urlhub-generic-disabled",
            manifest: genericMV3Manifest(name: "Generic Disabled MV3"),
            files: [:]
        )
        let module = try makeModule(enabled: true)
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: source,
            profileID: "profile-urlhub-generic-disabled",
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)

        let disabled = module
            .chromeMV3SetInternalExtensionEnabledThroughManager(
                false,
                rootURL: root,
                profileID: record.profileID,
                extensionID: record.extensionID
            )
        XCTAssertTrue(disabled.succeeded)

        let section = try XCTUnwrap(
            module.chromeMV3URLHubSectionViewModelIfEnabled(
                rootURL: root,
                currentPage: syntheticPageContext(profileID: record.profileID),
                now: fixedDate
            )
        )
        let row = try XCTUnwrap(section.rows.first)

        XCTAssertEqual(row.installIntakeStatus, .disabledInternal)
        XCTAssertFalse(row.enabled)
        XCTAssertTrue(row.installed)
        XCTAssertTrue(row.generatedBundleAvailable)
        XCTAssertTrue(row.readiness.blockedByExtension)
        XCTAssertFalse(row.readiness.explicitDiagnosticActionCanRun)
        XCTAssertFalse(row.diagnosticAction.available)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    @MainActor
    func testURLHubReadinessBlocksNonSyntheticCurrentPage()
        throws
    {
        let fixture = try installBitwardenURLHubFixture(
            named: "urlhub-real-page-blocked",
            profileID: "profile-urlhub-real-page",
            enableInternal: true
        )

        let section = try XCTUnwrap(
            fixture.module.chromeMV3URLHubSectionViewModelIfEnabled(
                rootURL: fixture.root,
                currentPage: currentPageContext(
                    profileID: fixture.record.profileID,
                    urlString: "https://example.com/login",
                    surface: .normalTab
                ),
                now: fixedDate
            )
        )
        let row = try XCTUnwrap(section.rows.first)

        XCTAssertFalse(row.readiness.currentPageIsSyntheticDiagnosticPage)
        XCTAssertTrue(
            row.readiness.blockers.contains(.blockedByNonSyntheticOrigin)
        )
        XCTAssertTrue(row.readiness.blockedByNonSyntheticOrigin)
        XCTAssertFalse(row.readiness.explicitDiagnosticActionCanRun)
        XCTAssertFalse(row.diagnosticAction.available)
        XCTAssertTrue(
            row.diagnosticAction.disabledReason?
                .contains("blockedByNonSyntheticOrigin") == true
        )
        XCTAssertFalse(fixture.module.hasLoadedRuntime)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath:
                    ChromeMV3ExtensionManagerReviewedResourceDiagnosticArtifactWriter
                    .reportURL(
                        rootURL: fixture.root,
                        profileID: fixture.record.profileID,
                        extensionID: fixture.record.extensionID
                    )
                    .path
            )
        )
    }

    @MainActor
    func testURLHubReadinessBlocksAuxiliaryAndFileSurfaces()
        throws
    {
        let fixture = try installBitwardenURLHubFixture(
            named: "urlhub-auxiliary-blocked",
            profileID: "profile-urlhub-auxiliary",
            enableInternal: true
        )

        let section = try XCTUnwrap(
            fixture.module.chromeMV3URLHubSectionViewModelIfEnabled(
                rootURL: fixture.root,
                currentPage: currentPageContext(
                    profileID: fixture.record.profileID,
                    urlString: "file:///tmp/login.html",
                    surface: .peekGlancePreview
                ),
                now: fixedDate
            )
        )
        let row = try XCTUnwrap(section.rows.first)

        XCTAssertTrue(row.readiness.blockers.contains(.blockedBySurface))
        XCTAssertTrue(
            row.readiness.blockers.contains(.blockedByAuxiliarySurface)
        )
        XCTAssertTrue(row.readiness.blockers.contains(.blockedByScheme))
        XCTAssertFalse(row.diagnosticAction.available)
        XCTAssertFalse(fixture.module.hasLoadedRuntime)
    }

    @MainActor
    func testURLHubStateMatchesManagerSourceOfTruth() throws {
        let fixture = try installBitwardenURLHubFixture(
            named: "urlhub-manager-consistency",
            profileID: "profile-urlhub-consistency",
            enableInternal: true
        )
        let detail = try XCTUnwrap(
            fixture.module.chromeMV3ExtensionManagerDetailViewModelIfEnabled(
                rootURL: fixture.root,
                profileID: fixture.record.profileID,
                extensionID: fixture.record.extensionID
            )
        )
        let section = try XCTUnwrap(
            fixture.module.chromeMV3URLHubSectionViewModelIfEnabled(
                rootURL: fixture.root,
                currentPage: syntheticPageContext(
                    profileID: fixture.record.profileID
                ),
                now: fixedDate
            )
        )
        let row = try XCTUnwrap(section.rows.first)

        XCTAssertEqual(row.extensionID, detail.listItem.extensionID)
        XCTAssertEqual(row.profileID, detail.listItem.profileID)
        XCTAssertEqual(row.displayName, detail.listItem.name)
        XCTAssertEqual(row.enabled, detail.listItem.internalEnabled)
        XCTAssertEqual(
            row.diagnosticAction.actionID,
            detail.reviewedResourceDiagnosticAction.actionID
        )
        XCTAssertEqual(
            row.diagnosticAction.lastArtifactPath,
            detail.reviewedResourceDiagnosticAction.lastArtifactPath
        )
        XCTAssertFalse(fixture.module.hasLoadedRuntime)
    }

    @MainActor
    func testURLHubListsMultipleReviewedResourceCapabilitiesGenerically()
        throws
    {
        let root = try makeTemporaryDirectory()
        let module = try makeModule(enabled: true)
        let bitwardenSource = try makeFixture(
            named: "urlhub-additive-bitwarden",
            manifest:
                bitwardenManualSmokeManifest(name: "urlhub-additive-bitwarden"),
            files: bitwardenManualSmokeFiles()
        )
        let syntheticSource = try makeFixture(
            named: "urlhub-additive-synthetic",
            manifest:
                syntheticReviewedResourceManifest(
                    name: "urlhub-additive-synthetic"
                ),
            files: syntheticReviewedResourceFiles()
        )
        let bitwardenInstall = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: bitwardenSource,
            profileID: "profile-urlhub-additive",
            enableInternal: true
        )
        let syntheticInstall = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: syntheticSource,
            profileID: "profile-urlhub-additive",
            enableInternal: true
        )
        let bitwardenRecord = try XCTUnwrap(
            bitwardenInstall.lifecycleOperationResult?.record
        )
        let syntheticRecord = try XCTUnwrap(
            syntheticInstall.lifecycleOperationResult?.record
        )

        let section = try XCTUnwrap(
            module.chromeMV3URLHubSectionViewModelIfEnabled(
                rootURL: root,
                currentPage:
                    syntheticPageContext(profileID: "profile-urlhub-additive"),
                now: fixedDate
            )
        )

        XCTAssertEqual(section.rows.count, 2)
        let rowsByExtension = Dictionary(
            uniqueKeysWithValues: section.rows.map { ($0.extensionID, $0) }
        )
        let bitwardenRow = try XCTUnwrap(
            rowsByExtension[bitwardenRecord.extensionID]
        )
        let syntheticRow = try XCTUnwrap(
            rowsByExtension[syntheticRecord.extensionID]
        )

        XCTAssertEqual(
            bitwardenRow.diagnosticAction.capabilityID,
            ChromeMV3ReviewedResourceDiagnosticCapabilityCatalog
                .reviewedGeneratedResourceNormalTabDiagnosticID
        )
        XCTAssertEqual(
            bitwardenRow.diagnosticAction.capability?.fixtureProvenance,
            "bitwardenCompatibilityFixture"
        )
        XCTAssertEqual(
            syntheticRow.diagnosticAction.capabilityID,
            ChromeMV3ReviewedResourceDiagnosticCapabilityCatalog
                .syntheticReviewedResourceNormalTabDiagnosticID
        )
        XCTAssertEqual(
            syntheticRow.diagnosticAction.capability?.fixtureProvenance,
            "syntheticNonVendorReviewedResourceFixture"
        )
        XCTAssertEqual(
            syntheticRow.diagnosticAction.capability?.reviewedResourcePath,
            "content/sumi-reviewed-resource-marker.js"
        )
        XCTAssertTrue(syntheticRow.diagnosticAction.capabilityAvailable)
        XCTAssertTrue(syntheticRow.diagnosticAction.available)
        XCTAssertFalse(section.lifetime.artifactWrittenByReadout)
        XCTAssertFalse(module.hasLoadedRuntime)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath:
                    ChromeMV3ExtensionManagerReviewedResourceDiagnosticArtifactWriter
                    .reportURL(
                        rootURL: root,
                        profileID: syntheticRecord.profileID,
                        extensionID: syntheticRecord.extensionID
                    )
                    .path
            )
        )
    }

    @MainActor
    func testURLHubExplicitActionRejectsUnreviewedSyntheticFixture()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Named WKContentWorld execution requires macOS 15.5.")
        }
        let fixture = try installBitwardenURLHubFixture(
            named: "urlhub-action-run",
            profileID: "profile-urlhub-action",
            enableInternal: true
        )
        let context = syntheticPageContext(profileID: fixture.record.profileID)
        let artifactURL =
            ChromeMV3ExtensionManagerReviewedResourceDiagnosticArtifactWriter.reportURL(
                rootURL: fixture.root,
                profileID: fixture.record.profileID,
                extensionID: fixture.record.extensionID
            )

        XCTAssertFalse(FileManager.default.fileExists(atPath: artifactURL.path))
        let before = try XCTUnwrap(
            fixture.module.chromeMV3URLHubSectionViewModelIfEnabled(
                rootURL: fixture.root,
                currentPage: context,
                now: fixedDate
            )?.rows.first
        )
        XCTAssertFalse(before.diagnosticAction.available)

        let result = await fixture.module
            .chromeMV3RunReviewedResourceDiagnosticActionThroughURLHub(
                rootURL: fixture.root,
                profileID: fixture.record.profileID,
                extensionID: fixture.record.extensionID,
                currentPage: context,
                now: { self.fixedDate }
            )

        XCTAssertEqual(result.status, .blocked)
        XCTAssertNil(result.reviewedResourceDiagnosticResult)
        XCTAssertNil(result.reviewedResourceDiagnosticArtifact)
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifactURL.path))
        let after = try XCTUnwrap(
            fixture.module.chromeMV3URLHubSectionViewModelIfEnabled(
                rootURL: fixture.root,
                currentPage: context,
                now: fixedDate
            )?.rows.first
        )
        XCTAssertNil(after.diagnosticAction.lastRunStatus)
        XCTAssertNil(after.diagnosticAction.lastArtifactPath)
        XCTAssertNil(after.diagnosticAction.lastRetainedObjectCount)
        XCTAssertNil(after.diagnosticAction.lastTeardownCompleted)
        XCTAssertNil(after.diagnosticAction.lastDOMFillSucceeded)
        assertNoRuntimeSideEffects(result, module: fixture.module)
    }

    func testURLHubMV3SourceGuardsStayPassiveAndURLHubScoped()
        throws
    {
        let modelSource = try source(
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3URLHubDeveloperPreview.swift"
        )
        let hubSource = try source(
            "Sumi/Components/Sidebar/URLBarHubPopover.swift"
        )
        let actionViewSource = try source(
            "Sumi/Components/Extensions/ExtensionActionView.swift"
        )
        let managerUISource = try source(
            "Sumi/Managers/ExtensionManager/ExtensionManager+UI.swift"
        )
        let controllerDelegateSource = try source(
            "Sumi/Managers/ExtensionManager/ExtensionManager+ControllerDelegate.swift"
        )
        let managerProfilesSource = try source(
            "Sumi/Managers/ExtensionManager/ExtensionManager+Profiles.swift"
        )
        let nativePreludeSource = try source(
            "Sumi/Managers/ExtensionManager/ExtensionManager+NativeActionPopupPrelude.swift"
        )
        let extensionBridgeSource = try source(
            "Sumi/Managers/ExtensionManager/ExtensionBridge.swift"
        )
        let sidebarHeaderSource = try source(
            "Navigation/Sidebar/SidebarHeader.swift"
        )
        let moduleSource = try source(
            "Sumi/Managers/ExtensionManager/SumiExtensionsModule.swift"
        )
        let popupOptionsSource = try source(
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3ProductPopupOptionsUI.swift"
        )
        let popupOptionsBridgeSource = try source(
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3PopupOptionsJSBridge.swift"
        )
        let runtimeGateSource = try source(
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3ProductRuntimeGate.swift"
        )
        let combined = modelSource + "\n" + hubSource + "\n" + actionViewSource
        let nativePopupBoundarySources =
            managerUISource + "\n" + controllerDelegateSource + "\n"
            + extensionBridgeSource
        let manualSmokeRunnerCall =
            ".run" + "Manual" + "Normal" + "Tab" + "Smoke(request)"
        let artifactWriterCall =
            ".write(artifact, rootURL: rootURL)"

        XCTAssertTrue(modelSource.contains("URL-hub developer-preview"))
        XCTAssertTrue(hubSource.contains("Local MV3 Preview"))
        XCTAssertTrue(hubSource.contains("urlhub-mv3-row-"))
        XCTAssertTrue(modelSource.contains("listInstalledExtensionStates"))
        XCTAssertTrue(modelSource.contains("productSupportClaim"))
        XCTAssertTrue(modelSource.contains("not product support"))
        XCTAssertTrue(
            modelSource.contains("ChromeMV3ReviewedResourceDiagnosticCapability")
        )
        XCTAssertTrue(
            modelSource.contains("runReviewedResourceDiagnosticAction")
        )
        XCTAssertTrue(modelSource.contains("chromeMV3URLHubSectionViewModelIfEnabled"))
        XCTAssertFalse(modelSource.contains("runBitwarden"))
        XCTAssertFalse(modelSource.contains("Bitwarden"))
        XCTAssertFalse(modelSource.contains("bitwarden"))
        XCTAssertFalse(modelSource.contains("managerIfEnabled()"))
        XCTAssertFalse(modelSource.contains("WKWebView"))
        XCTAssertFalse(modelSource.contains("WKWebExtensionController"))
        XCTAssertFalse(modelSource.contains("WKWebExtensionContext"))
        XCTAssertFalse(modelSource.contains("addUser" + "Script"))
        XCTAssertFalse(modelSource.contains("addScript" + "MessageHandler"))
        XCTAssertFalse(modelSource.contains("Process" + "("))
        XCTAssertFalse(modelSource.contains("DispatchSource" + "Timer"))
        XCTAssertFalse(modelSource.contains("Timer.publish"))
        XCTAssertFalse(modelSource.contains("ExtensionToolbar"))
        XCTAssertFalse(modelSource.contains("toolbar action"))
        XCTAssertFalse(sidebarHeaderSource.contains("ExtensionActionView("))
        XCTAssertFalse(actionViewSource.contains("Pin to Toolbar"))
        XCTAssertFalse(actionViewSource.contains("Unpin from Toolbar"))
        XCTAssertFalse(hubSource.contains(manualSmokeRunnerCall))
        XCTAssertFalse(hubSource.contains(artifactWriterCall))
        XCTAssertFalse(
            [
                modelSource,
                hubSource,
                actionViewSource,
                moduleSource,
                popupOptionsSource,
            ].joined(separator: "\n")
                .contains("ChromeMV3PopupOptionsI18nCatalogSnapshot")
        )
        XCTAssertTrue(actionViewSource.contains("openActionPopupFromURLHub"))
        XCTAssertTrue(
            moduleSource.contains(
                "forceNativeCompatibilityActionPopupDefaultsKey"
            )
        )
        XCTAssertTrue(
            moduleSource.contains(
                "forceControlledCompatibilityActionPopupOffDefaultsKey"
            )
        )
        XCTAssertFalse(
            moduleSource.contains(
                "controlledCompatibility" + "ActionPopupDefaultsKey"
            )
        )
        XCTAssertTrue(
            runtimeGateSource.contains(
                "ChromeMV3LocalMV3CompatibilityPolicy"
            )
        )
        XCTAssertTrue(
            runtimeGateSource.contains(
                "enabledLocalUnpackedMV3DeveloperPreview"
            )
        )
        XCTAssertTrue(
            runtimeGateSource.contains(
                "selectedPopupPath=\\(selectedPopupPath)"
            )
                || runtimeGateSource.contains("selectedPopupPath=")
        )
        XCTAssertTrue(
            runtimeGateSource.contains(
                "case controlledCompatibilityActionPopup"
            )
        )
        XCTAssertTrue(
            popupOptionsSource.contains(
                "controlledCompatibilityDefault"
            )
        )
        XCTAssertTrue(popupOptionsSource.contains("case diagnosticCustomScheme"))
        XCTAssertTrue(
            popupOptionsSource.contains(
                "sumi-extension-page-diagnostic"
            )
        )
        XCTAssertTrue(
            moduleSource.contains(
                "openControlledCompatibilityActionPopupFromURLHub"
            )
        )
        XCTAssertTrue(
            moduleSource.contains(
                "controlledActionPopupServiceWorkerLifecycleSession"
            )
        )
        XCTAssertTrue(
            moduleSource.contains(
                "ChromeMV3ControlledActionPopupServiceWorkerLifecycleStore"
            )
        )
        XCTAssertTrue(
            moduleSource.contains(
                "ChromeMV3ServiceWorkerJSExecutionHarness"
            )
        )
        XCTAssertTrue(
            moduleSource.contains(
                "nativePortKeepaliveAvailableInFixture: false"
            )
        )
        XCTAssertTrue(
            moduleSource.contains("manager.openActionPopupFromURLHub")
        )
        XCTAssertTrue(
            popupOptionsSource.contains(
                "sharedLifecycleSessionReleaseHandler"
            )
        )
        XCTAssertTrue(
            popupOptionsSource.contains(
                "controlledActionPopupLaunchRecord"
            )
        )
        XCTAssertTrue(
            popupOptionsSource.contains(
                "Package-local popup JavaScript, CSS, image, locale, frame, and asset resources are preserved"
            )
        )
        XCTAssertTrue(
            popupOptionsSource.contains(
                "Remote non-executable popup references such as preconnect"
            )
        )
        XCTAssertTrue(
            popupOptionsSource.contains(
                "chrome-extension:// origin semantics are approximated"
            )
        )
        XCTAssertTrue(
            popupOptionsBridgeSource.contains("controlledActionPopupPolicy")
        )
        XCTAssertTrue(
            popupOptionsBridgeSource.contains("\"runtime.sendMessage\"")
        )
        XCTAssertTrue(
            popupOptionsBridgeSource.contains("\"runtime.connect\"")
        )
        XCTAssertTrue(
            popupOptionsBridgeSource.contains(
                "runtime.connect delivered a named Port to captured service-worker runtime.onConnect JavaScript listener(s)."
            )
        )
        XCTAssertTrue(
            popupOptionsBridgeSource.contains("\"tabs.sendMessage\"")
        )
        XCTAssertTrue(
            popupOptionsBridgeSource.contains("\"storage.session.get\"")
        )
        XCTAssertTrue(
            popupOptionsBridgeSource.contains("\"i18n.getMessage\"")
        )
        XCTAssertTrue(
            popupOptionsBridgeSource.contains("\"i18n.getUILanguage\"")
        )
        XCTAssertTrue(
            popupOptionsBridgeSource.contains("i18nExposed")
        )
        XCTAssertTrue(
            popupOptionsBridgeSource.contains(
                "No raw localized message values are recorded."
            )
        )
        XCTAssertTrue(
            popupOptionsBridgeSource.contains("storageSessionExposed")
        )
        XCTAssertTrue(popupOptionsBridgeSource.contains("\"tabs.getCurrent\""))
        XCTAssertTrue(
            popupOptionsBridgeSource.contains(
                "Object.defineProperty(tabs, \"getCurrent\""
            )
        )
        XCTAssertTrue(
            popupOptionsBridgeSource.contains(
                "\"extension.getBackgroundPage\""
            )
        )
        XCTAssertTrue(
            popupOptionsBridgeSource.contains(
                "controlledExtensionGetBackgroundPageCompatibilitySurface"
            )
        )
        XCTAssertTrue(
            popupOptionsBridgeSource.contains(
                "Object.defineProperty(target, \"extension\""
            )
        )
        XCTAssertTrue(
            popupOptionsBridgeSource.contains(
                "Object.defineProperty(namespace, \"getBackgroundPage\""
            )
        )
        XCTAssertTrue(
            popupOptionsBridgeSource.contains(
                "No fake background page/window or service-worker internals were returned."
            )
        )
        XCTAssertTrue(
            popupOptionsBridgeSource.contains(
                "No broad legacy chrome.extension APIs are exposed."
            )
        )
        XCTAssertTrue(
            popupOptionsBridgeSource.contains(
                "controlledTabsGetCurrentCompatibilitySurface"
            )
        )
        XCTAssertFalse(
            popupOptionsBridgeSource.contains(
                "controlledActionPopupPolicy" + ".allowedMethods.append"
            )
        )
        XCTAssertTrue(managerUISource.contains("performAction(for: adapter)"))
        XCTAssertTrue(managerUISource.contains("nativePopupBoundarySnapshot"))
        XCTAssertTrue(
            managerUISource.contains(
                "popupWebView intentionally not touched before performAction"
            )
        )
        XCTAssertTrue(
            controllerDelegateSource.contains(
                "recordNativeActionPopupPresentationBoundary"
            )
        )
        XCTAssertTrue(
            controllerDelegateSource.contains("runtime.sendNativeMessage")
        )
        XCTAssertTrue(
            controllerDelegateSource.contains("runtime.connectNative")
        )
        XCTAssertTrue(extensionBridgeSource.contains("metadataAvailable: false"))
        XCTAssertTrue(
            managerProfilesSource.contains(
                "makeExtensionPageBaseWebViewConfiguration"
            )
        )
        XCTAssertTrue(nativePreludeSource.contains("#if DEBUG"))
        XCTAssertTrue(nativePreludeSource.contains("WKUserScript("))
        XCTAssertTrue(nativePreludeSource.contains("in: .page"))
        XCTAssertTrue(nativePreludeSource.contains("safeTopLevelFieldNames"))
        XCTAssertTrue(nativePreludeSource.contains("keyCount"))
        XCTAssertTrue(nativePreludeSource.contains("portName"))
        XCTAssertTrue(nativePreludeSource.contains("descriptorSummary"))
        XCTAssertTrue(nativePreludeSource.contains("descriptorObserved"))
        XCTAssertTrue(nativePreludeSource.contains("Reflect.apply"))
        XCTAssertTrue(
            nativePreludeSource.contains("runtime.sendMessage")
        )
        XCTAssertTrue(nativePreludeSource.contains("tabs.sendMessage"))
        XCTAssertTrue(nativePreludeSource.contains("connectNative"))
        XCTAssertFalse(
            nativePreludeSource.contains(
                "ChromeMV3PopupOptionsJSBridgeHandler("
            )
        )
        XCTAssertFalse(nativePreludeSource.contains("Process" + "("))
        XCTAssertFalse(nativePreludeSource.contains("DispatchSource" + "Timer"))
        XCTAssertFalse(nativePreludeSource.contains("sumiIsNormalTabWebViewConfiguration = true"))
        XCTAssertFalse(nativePopupBoundarySources.contains("addUser" + "Script"))
        XCTAssertFalse(
            nativePopupBoundarySources.contains("addScript" + "MessageHandler")
        )
        XCTAssertFalse(nativePopupBoundarySources.contains("Process" + "("))
        XCTAssertFalse(moduleSource.contains("com.bitwarden.desktop"))
        XCTAssertFalse(nativePopupBoundarySources.contains("navigationDelegate ="))
        XCTAssertFalse(
            nativePopupBoundarySources.contains(
                "ChromeMV3PopupOptionsJSBridgeHandler("
            )
        )
        XCTAssertTrue(managerUISource.contains("extensionContext.action(for: adapter)"))
        XCTAssertTrue(managerUISource.contains("presentsPopup"))
        XCTAssertTrue(managerUISource.contains("guard action.isEnabled"))
        XCTAssertTrue(managerUISource.contains("extensionContext.performAction(for: adapter)"))
        XCTAssertTrue(managerUISource.contains("requestExtensionRuntimeAndWait(reason: .extensionAction)"))
        XCTAssertTrue(
            managerUISource.contains("currentPagePermissionMissing")
        )
        XCTAssertTrue(managerUISource.contains("noEligibleTab"))
        XCTAssertTrue(managerUISource.contains("extensionDisabled"))
        XCTAssertTrue(managerUISource.contains("moduleWorkerUnsupported"))
        XCTAssertFalse(managerUISource.contains("runReviewedResourceDiagnosticAction"))
        XCTAssertFalse(
            actionViewSource.contains("chromeMV3OpenActionPopupThroughManager")
        )
        XCTAssertFalse(
            actionViewSource.contains("runReviewedResourceDiagnosticAction")
        )
        XCTAssertTrue(moduleSource.contains("managerIfNeededForNormalTabRuntime"))
        XCTAssertTrue(
            moduleSource.contains("cachedManager.extensionController != nil")
        )
        XCTAssertFalse(modelSource.contains(manualSmokeRunnerCall))
        XCTAssertFalse(modelSource.contains(artifactWriterCall))
        XCTAssertFalse(combined.contains("masterPassword"))
        XCTAssertFalse(combined.contains("accessToken"))
        XCTAssertFalse(combined.contains("connectNative"))
        XCTAssertFalse(combined.contains("sendNativeMessage"))
    }

    @MainActor
    private func installBitwardenURLHubFixture(
        named name: String,
        profileID: String,
        enableInternal: Bool
    ) throws -> InstalledURLHubFixture {
        let root = try makeTemporaryDirectory()
        let source = try makeFixture(
            named: name,
            manifest: bitwardenManualSmokeManifest(name: name),
            files: bitwardenManualSmokeFiles()
        )
        let module = try makeModule(enabled: true)
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: source,
            profileID: profileID,
            enableInternal: enableInternal
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)
        return InstalledURLHubFixture(
            root: root,
            module: module,
            record: record
        )
    }

    @MainActor
    private func makeModule(
        enabled: Bool,
        includesModelContext: Bool = false,
        popupOptionsWebViewFactory:
            (@MainActor () -> ChromeMV3PopupOptionsWebViewFactory)? = nil
    ) throws -> SumiExtensionsModule {
        let harness = TestDefaultsHarness()
        let registry = SumiModuleRegistry(
            settingsStore:
                SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.setEnabled(enabled, for: .extensions)
        guard includesModelContext else {
            return SumiExtensionsModule(
                moduleRegistry: registry,
                chromeMV3PopupOptionsWebViewFactory:
                    popupOptionsWebViewFactory
                    ?? { ChromeMV3ProductPopupOptionsWKWebViewFactory() }
            )
        }
        let container = try ModelContainer(
            for: Schema([ExtensionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return SumiExtensionsModule(
            moduleRegistry: registry,
            context: ModelContext(container),
            chromeMV3PopupOptionsWebViewFactory:
                popupOptionsWebViewFactory
                ?? { ChromeMV3ProductPopupOptionsWKWebViewFactory() }
        )
    }

    private func syntheticPageContext(
        profileID: String
    ) -> ChromeMV3URLHubCurrentPageContext {
        currentPageContext(
            profileID: profileID,
            urlString:
                ChromeMV3URLHubDeveloperPreviewModelBuilder
                .syntheticDiagnosticURLString,
            surface: .normalTab
        )
    }

    private func currentPageContext(
        profileID: String,
        urlString: String,
        surface: ChromeMV3WebViewSurface
    ) -> ChromeMV3URLHubCurrentPageContext {
        ChromeMV3URLHubCurrentPageContext(
            profileID: profileID,
            tabID: "urlhub-test-tab",
            permissionBrokerTabID: 42,
            documentID: "urlhub-test-document",
            urlString: urlString,
            tabSurface: surface
        )
    }

    private func bitwardenManualSmokeManifest(name: String) -> [String: Any] {
        [
            "manifest_version": 3,
            "name": "Manager \(name)",
            "version": "1.0.0",
            "permissions": ["scripting", "activeTab"],
            "background": [
                "service_worker": "background.js",
            ],
            "content_scripts": [
                [
                    "matches": ["https://sumi.local.test/*"],
                    "js": [
                        "content/trigger-autofill-script-injection.js",
                        "content/trigger-autofill-script-injection.js",
                    ],
                ],
            ],
        ]
    }

    private func syntheticReviewedResourceManifest(name: String) -> [String: Any] {
        [
            "manifest_version": 3,
            "name": "Synthetic \(name)",
            "version": "1.0.0",
            "permissions": ["scripting", "activeTab"],
            "background": [
                "service_worker": "background.js",
            ],
        ]
    }

    private func genericMV3Manifest(name: String) -> [String: Any] {
        [
            "manifest_version": 3,
            "name": name,
            "version": "1.0.0",
            "action": [
                "default_title": name,
            ],
        ]
    }

    private func genericActionPopupManifest(
        name: String,
        permissions: [String] = [],
        hostPermissions: [String] = []
    ) -> [String: Any] {
        var manifest: [String: Any] = [
            "manifest_version": 3,
            "name": name,
            "version": "1.0.0",
            "action": [
                "default_title": name,
                "default_popup": "popup.html",
            ],
        ]
        if permissions.isEmpty == false {
            manifest["permissions"] = permissions
        }
        if hostPermissions.isEmpty == false {
            manifest["host_permissions"] = hostPermissions
        }
        return manifest
    }

    private func bitwardenManualSmokeFiles() -> [String: String] {
        [
            "background.js": """
            function triggerAutofillScriptInjection(tabId) {
              return chrome.scripting.executeScript({
                target: { tabId, frameIds: [0] },
                files: ["content/bootstrap-autofill.js"],
                world: "ISOLATED",
                injectImmediately: true
              });
            }
            """,
            "content/trigger-autofill-script-injection.js": """
            chrome.runtime.sendMessage({ command: "triggerAutofillScriptInjection" });
            """,
            "content/bootstrap-autofill.js": bitwardenReviewedBootstrapScript(),
        ]
    }

    private func syntheticReviewedResourceFiles() -> [String: String] {
        [
            "background.js": """
            function runSyntheticReviewedResourceMarker(tabId) {
              return chrome.scripting.executeScript({
                target: { tabId, frameIds: [0] },
                files: ["content/sumi-reviewed-resource-marker.js"],
                world: "ISOLATED",
                injectImmediately: true
              });
            }
            """,
            "content/sumi-reviewed-resource-marker.js":
                syntheticReviewedResourceMarkerScript(),
        ]
    }

    private func bitwardenReviewedBootstrapScript() -> String {
        """
        (() => {
          let listener;
          listener = (message, sender, sendResponse) => {
            if (message.command === "collectPageDetailsImmediately") {
              document.getElementById("sumi-login-email").opid = "__0";
              document.getElementById("sumi-login-password").opid = "__1";
              sendResponse({ fields: ["__0", "__1"] });
              return true;
            }
            if (message.command === "fillForm") {
              for (const [action, opid, value] of message.fillScript.script) {
                if (action !== "fill_by_opid") continue;
                const field = Array.from(document.querySelectorAll("input"))
                  .find((item) => item.opid === opid);
                if (field) field.value = value;
              }
              sendResponse(null);
              return true;
            }
            return null;
          };
          chrome.runtime.onMessage.addListener(listener);
          chrome.runtime.connect({ name: "autofill-injected-script-port" });
          window.bitwardenAutofillInit = {
            destroy() { chrome.runtime.onMessage.removeListener(listener); }
          };
        })();
        """
    }

    private func syntheticReviewedResourceMarkerScript() -> String {
        """
        (() => {
          const marker = globalThis.__sumiSyntheticReviewedResourceMarker || {};
          const username = document.getElementById("sumi-login-email");
          const password = document.getElementById("sumi-login-password");
          if (username && typeof marker.username === "string") {
            username.value = marker.username;
            username.dataset.sumiReviewedResourceMarker = "username";
          }
          if (password && typeof marker.password === "string") {
            password.value = marker.password;
            password.dataset.sumiReviewedResourceMarker = "password";
          }
          globalThis.__sumiSyntheticReviewedResourceDiagnostic = {
            fixture: "sumiSyntheticReviewedResource",
            touched: [
              username ? username.id : "missing-username",
              password ? password.id : "missing-password"
            ],
            destroy() {
              delete globalThis.__sumiSyntheticReviewedResourceDiagnostic;
              delete globalThis.__sumiSyntheticReviewedResourceMarker;
            }
          };
        })();
        """
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

    @MainActor
    private func waitForEnabledExtension(
        in module: SumiExtensionsModule,
        extensionId: String
    ) async -> InstalledExtension? {
        for _ in 0..<20 {
            if let installedExtension = module.surfaceStore.enabledExtensions.first(
                where: { $0.id == extensionId }
            ) {
                return installedExtension
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return module.surfaceStore.enabledExtensions.first {
            $0.id == extensionId
        }
    }

    private func controlledBitwardenPopupPreflightSummary(
        _ launchRecord: ChromeMV3ProductPopupOptionsLaunchRecord?
    ) -> String {
        guard let launchRecord else {
            return "preflightLaunchRecord=none"
        }
        let linkedKinds =
            Dictionary(
                grouping:
                    launchRecord.resourceResolution?.linkedResources
                        .map(\.kind.rawValue) ?? [],
                by: { $0 }
            )
            .map { "\($0.key):\($0.value.count)" }
            .sorted()
            .joined(separator: ",")
        return [
            "preflightCanOpen=\(launchRecord.canOpen)",
            "declaredPath=\(launchRecord.declaredPath ?? "none")",
            "validation=\(launchRecord.resourceValidationState.rawValue)",
            "blockers=\(launchRecord.blockers.map(\.rawValue).joined(separator: ","))",
            "resourceBlockers=\((launchRecord.resourceResolution?.blockingReasons ?? []).joined(separator: "|"))",
            "missingResources=\((launchRecord.resourceResolution?.missingResourcePaths ?? []).joined(separator: ","))",
            "unsafeResources=\((launchRecord.resourceResolution?.unsafeResourcePaths ?? []).joined(separator: ","))",
            "remoteResources=\((launchRecord.resourceResolution?.remoteResourceShapes ?? []).joined(separator: ","))",
            "remoteExecutableResources=\((launchRecord.resourceResolution?.remoteExecutableResourceShapes ?? []).joined(separator: ","))",
            "remoteNonExecutableResources=\((launchRecord.resourceResolution?.remoteNonExecutableResourceShapes ?? []).joined(separator: ","))",
            "linkedResourceKinds=\(linkedKinds)",
        ].joined(separator: " ")
    }

    @MainActor
    private func makeURLHubLiveTabModuleFixture(
        profileName: String,
        useFileBackedPopupHost: Bool = false
    ) throws -> ChromeMV3URLHubLiveTabModuleFixture {
        let harness = TestDefaultsHarness()
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.extensions)
        let container = try ModelContainer(
            for: Schema([ExtensionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let browserConfiguration = BrowserConfiguration()
        let profile = Profile(name: profileName)
        let popupOptionsWebViewFactory:
            @MainActor @Sendable () -> ChromeMV3PopupOptionsWebViewFactory
        if useFileBackedPopupHost {
            popupOptionsWebViewFactory = {
                ChromeMV3ProductPopupOptionsWKWebViewFactory(
                    loadingMode: .fileBacked
                )
            }
        } else {
            popupOptionsWebViewFactory = {
                ChromeMV3ProductPopupOptionsWKWebViewFactory()
            }
        }
        let module = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: browserConfiguration,
            initialProfileProvider: { profile },
            managerFactory: { context, initialProfile, browserConfiguration in
                ExtensionManager(
                    context: context,
                    initialProfile: initialProfile,
                    browserConfiguration: browserConfiguration
                )
            },
            chromeMV3EmptyControllerOwnerFactory: { decision, dataStore, identifier in
                ChromeMV3EmptyControllerFactory.makeOwner(
                    gateDecision: decision,
                    defaultWebsiteDataStore: dataStore,
                    controllerIdentifier: identifier
                )
            },
            chromeMV3PopupOptionsWebViewFactory: popupOptionsWebViewFactory
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            extensionsModule: module
        )
        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile

        return ChromeMV3URLHubLiveTabModuleFixture(
            defaultsHarness: harness,
            container: container,
            browserConfiguration: browserConfiguration,
            module: module,
            browserManager: browserManager,
            profile: profile
        )
    }

    @MainActor
    private func waitForRaindropExecuteScriptBridgeSnapshot(
        module: SumiExtensionsModule,
        profileID: String,
        extensionID: String
    ) async throws -> ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot {
        for _ in 0..<280 {
            if let snapshot =
                module
                .chromeMV3PopupOptionsBridgeDiagnosticsSnapshotForTesting(
                    profileID: profileID,
                    extensionID: extensionID
                ),
                raindropParseJSExecuteScriptCallRecord(in: snapshot) != nil
            {
                return snapshot
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return try await waitForControlledBitwardenPopupBridgeSnapshot(
            module: module,
            profileID: profileID,
            extensionID: extensionID
        )
    }

    private func raindropParseJSExecuteScriptCallRecord(
        in snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot
    ) -> ChromeMV3PopupOptionsJSBridgeCallRecord? {
        snapshot.callRecords.last { record in
            guard record.namespace == "scripting",
                  record.methodName == "executeScript"
            else { return false }
            return record.diagnostics.contains {
                $0.contains("assets/parse.js")
                    || $0.contains("fileShapes=parse.js")
            }
        }
    }

    private func raindropExecuteScriptCallSummary(
        in snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot
    ) -> String {
        snapshot.callRecords
            .filter {
                $0.namespace == "scripting" && $0.methodName == "executeScript"
            }
            .map { record in
                [
                    "succeeded=\(record.succeeded)",
                    "lastError=\(record.lastErrorCode ?? "none")",
                    "diagnostics=\(record.diagnostics.joined(separator: " | "))",
                ].joined(separator: " ")
            }
            .joined(separator: " || ")
    }

    private func raindropParseJSExecuteScriptSucceeded(
        in snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot
    ) -> Bool {
        guard let record = raindropParseJSExecuteScriptCallRecord(in: snapshot)
        else { return false }
        return record.succeeded
            && record.diagnostics.contains {
                $0.contains("executionClassifier=filesExecuted")
            }
    }

    private let chromeMV3PostParseBlockerCatalog: Set<String> = [
        "contentScriptListenerMissing",
        "messageBeforeContentScriptReady",
        "serviceWorkerOnMessageMissing",
        "serviceWorkerOnConnectMissing",
        "popupToServiceWorkerRouteDropped",
        "popupToContentScriptRouteDropped",
        "contentScriptToServiceWorkerRouteDropped",
        "tabsTargetMappingWrong",
        "storageAppStateReadNoWriter",
        "storageWriteNotVisibleToPopup",
        "storageOnChangedMissed",
        "permissionOrActiveTabDenied",
        "missingNarrowChromeAPI",
        "networkOrAuthWait",
        "appStateWaitWithNoObservableBrowserDependency",
        "unknown",
    ]

    private let chromeMV3ExecuteScriptContinuationBlockerCatalog: Set<String> = [
        "executeScriptPromiseNotResolvedToPopup",
        "executeScriptPromiseRejectedInPopup",
        "executeScriptResultShapeUnexpected",
        "popupContinuationException",
        "popupContinuationUnhandledRejection",
        "popupAwaitNeverResolved",
        "popupTimerOrSchedulerGate",
        "popupRenderGateNoStateTransition",
        "popupLocalAuthOrNetworkBranch",
        "popupLocalAppStateBranch",
        "sourceMapUnavailable",
        "noPopupContinuationObserved",
        "unknown",
    ]

    private let chromeMV3TransientUIDisappearanceBlockerCatalog: Set<String> = [
        "transientUIThenRootEmptied",
        "transientUIThenRootHidden",
        "transientUIThenBodyEmptied",
        "transientUIThenAppRootReplaced",
        "transientUIThenNavigationReset",
        "transientUIThenCSSHidden",
        "transientUIThenRenderStateBlank",
        "transientUIThenAwaitingLocalState",
        "transientUIThenUnhandledException",
        "transientUIThenUnhandledRejection",
        "transientUIThenMissingGenericBrowserSignal",
        "noTransientUIObservedInTest",
        "unknown",
    ]

    private struct ChromeMV3PostParseSanitizedDiagnostics {
        var firstBlocker: String
        var firstContinuationBlocker: String
        var firstUIDisappearanceBlocker: String
        var resultDeliveryClassifier: String
        var closingDecision: String
        var lines: [String]
    }

    @MainActor
    private func waitForRaindropPostParseBridgeSnapshot(
        module: SumiExtensionsModule,
        profileID: String,
        extensionID: String
    ) async throws -> ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot {
        var snapshot = try await waitForRaindropExecuteScriptBridgeSnapshot(
            module: module,
            profileID: profileID,
            extensionID: extensionID
        )
        for _ in 0..<200 {
            if let current =
                module
                .chromeMV3PopupOptionsBridgeDiagnosticsSnapshotForTesting(
                    profileID: profileID,
                    extensionID: extensionID
                )
            {
                snapshot = current
                let postParseEvents = raindropPostParseEvents(in: current)
                let continuationEvents =
                    raindropExecuteScriptContinuationEvents(in: current)
                let renderTimelineEvents =
                    raindropPopupRenderTimelineEvents(in: current)
                if continuationEvents.contains(where: { event in
                    event.resultClassifier == "finalDOMCheckpoint"
                        || event.resultClassifier == "hostForcedFinalDOMCheckpoint"
                }),
                    renderTimelineEvents.contains(where: { event in
                        event.resultClassifier == "popupRenderTimelineFinal"
                            || event.resultClassifier == "hostForcedFinalDOM"
                    })
                {
                    return current
                }
                if postParseEvents.contains(where: { event in
                    event.eventKind == "postBootstrapCheckpoint"
                        && event.diagnostics.contains("phase=final")
                }) {
                    return current
                }
                if postParseEvents.contains(where: {
                    controlledBitwardenPopupIsBlockerEvent($0)
                }) {
                    return current
                }
                if continuationEvents.contains(where: {
                    $0.resultClassifier == "popupContinuationException"
                        || $0.resultClassifier == "popupContinuationUnhandledRejection"
                        || $0.resultClassifier == "popupPromiseRejected"
                }) {
                    return current
                }
                if current.pendingUnresolvedJSDebugRoutes.isEmpty == false {
                    return current
                }
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        _ = try? await module
            .chromeMV3PopupOptionsEvaluateJavaScriptForTesting(
                profileID: profileID,
                extensionID: extensionID,
                script: """
                (() => {
                  const forceCheckpoint =
                    globalThis.__sumiChromeMV3PopupOptionsDebugForceCheckpoint;
                  if (typeof forceCheckpoint !== 'function') {
                    return false;
                  }
                  forceCheckpoint('host-forced-final');
                  return true;
                })();
                """
            )
        try? await Task.sleep(nanoseconds: 50_000_000)
        if let current =
            module
            .chromeMV3PopupOptionsBridgeDiagnosticsSnapshotForTesting(
                profileID: profileID,
                extensionID: extensionID
            )
        {
            snapshot = current
        }
        return snapshot
    }

    private func raindropPostParseExecuteScriptRouteIndex(
        in snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot
    ) -> Int? {
        if let parseRouteIndex =
            snapshot.sanitizedBridgeRouteRecords.lastIndex(where: { route in
                guard route.apiName == "scripting.executeScript" else {
                    return false
                }
                let executedFiles = route.diagnostics.contains {
                    $0.contains("executionClassifier=filesExecuted")
                }
                let referencedParseJS = route.diagnostics.contains {
                    $0.contains("assets/parse.js")
                        || $0.contains("fileShapes=parse.js")
                }
                return executedFiles && referencedParseJS
            })
        {
            return parseRouteIndex
        }
        return snapshot.sanitizedBridgeRouteRecords.lastIndex { route in
            guard route.apiName == "scripting.executeScript" else {
                return false
            }
            return route.diagnostics.contains {
                $0.contains("executionClassifier=filesExecuted")
            } || route.resultClassifier.contains("executeScriptSucceeded")
        }
    }

    private func raindropPostParseExecuteScriptEventSequence(
        in snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot
    ) -> Int? {
        if let executeScriptEvent = snapshot.jsDebugRouteEvents.last(where: {
            event in
            event.apiName == "scripting.executeScript"
                && (
                    event.resultClassifier?
                        .contains("executeScriptSucceeded") == true
                        || event.diagnostics.contains {
                            $0.contains("executionClassifier=filesExecuted")
                        }
                )
        }) {
            return executeScriptEvent.sequence
        }
        if let bridgeResolved = snapshot.jsDebugRouteEvents.last(where: {
            $0.apiName == "scripting.executeScript"
                && $0.eventKind == "bridgeCallResolved"
        }) {
            return bridgeResolved.sequence
        }
        return snapshot.jsDebugRouteEvents.last { event in
            event.diagnostics.contains { $0.contains("assets/parse.js") }
                || event.diagnostics.contains {
                    $0.contains("executionClassifier=filesExecuted")
                }
        }?.sequence
    }

    private func raindropPostParseRoutes(
        in snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot
    ) -> [ChromeMV3PopupOptionsSanitizedBridgeRouteRecord] {
        guard let index = raindropPostParseExecuteScriptRouteIndex(in: snapshot)
        else { return [] }
        return Array(snapshot.sanitizedBridgeRouteRecords[(index + 1)...])
    }

    private func raindropPostParseEvents(
        in snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot
    ) -> [ChromeMV3PopupOptionsJSDebugRouteEventRecord] {
        guard let sequence =
            raindropPostParseExecuteScriptEventSequence(in: snapshot)
        else { return [] }
        return snapshot.jsDebugRouteEvents.filter { $0.sequence > sequence }
    }

    private func continuationDiagnosticValue(
        _ key: String,
        in diagnostics: [String]
    ) -> String? {
        for diagnostic in diagnostics {
            guard let range = diagnostic.range(of: "\(key)=") else { continue }
            let suffix = diagnostic[range.upperBound...]
            let value = suffix.prefix { character in
                character != ";"
                    && character != "|"
                    && character != ","
            }
            if value.isEmpty == false { return String(value) }
        }
        return nil
    }

    private func continuationShapeSummaryValue(
        _ key: String,
        in diagnostics: [String]
    ) -> String? {
        for diagnostic in diagnostics {
            guard diagnostic.hasPrefix("\(key)=") else { continue }
            let value = String(diagnostic.dropFirst("\(key)=".count))
            if value.isEmpty == false { return value }
        }
        return nil
    }

    private func raindropExecuteScriptContinuationEvents(
        in snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot
    ) -> [ChromeMV3PopupOptionsJSDebugRouteEventRecord] {
        snapshot.jsDebugRouteEvents.filter {
            $0.eventKind == "executeScriptContinuationCheckpoint"
        }
    }

    private func raindropPopupRenderTimelineEvents(
        in snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot
    ) -> [ChromeMV3PopupOptionsJSDebugRouteEventRecord] {
        snapshot.jsDebugRouteEvents.filter {
            $0.eventKind == "popupRenderTimelineCheckpoint"
        }
    }

    private func renderTimelineTransientUIObserved(
        in events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    ) -> Bool {
        events.contains { event in
            continuationDiagnosticValue("transientUIObserved", in: event.diagnostics)
                == "true"
                || (
                    continuationDiagnosticValue(
                        "visibleTextLengthBucket",
                        in: event.diagnostics
                    ) ?? "0"
                ) != "0"
                || continuationDiagnosticValue(
                    "usableFormCandidate",
                    in: event.diagnostics
                ) == "true"
                || (postParseDiagnosticInt(
                    "formControlCandidateCount",
                    in: event.diagnostics
                ) ?? 0) > 0
                || event.resultClassifier == "firstNonEmptyVisibleDOM"
        }
    }

    private func classifyFirstUIDisappearanceBlocker(
        snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot,
        continuationEvents: [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    ) -> String {
        let timelineEvents = raindropPopupRenderTimelineEvents(in: snapshot)
        guard timelineEvents.isEmpty == false else {
            return "unknown"
        }

        if continuationEvents.contains(where: {
            $0.resultClassifier == "popupContinuationException"
        }) {
            return renderTimelineTransientUIObserved(in: timelineEvents)
                ? "transientUIThenUnhandledException"
                : "noTransientUIObservedInTest"
        }
        if continuationEvents.contains(where: {
            $0.resultClassifier == "popupContinuationUnhandledRejection"
        }) {
            return renderTimelineTransientUIObserved(in: timelineEvents)
                ? "transientUIThenUnhandledRejection"
                : "noTransientUIObservedInTest"
        }

        guard renderTimelineTransientUIObserved(in: timelineEvents) else {
            return "noTransientUIObservedInTest"
        }

        let transientSequence = timelineEvents.first { event in
            event.resultClassifier == "firstNonEmptyVisibleDOM"
                || continuationDiagnosticValue(
                    "transientUIObserved",
                    in: event.diagnostics
                ) == "true"
        }?.sequence
        let blankingEvent = timelineEvents.first { event in
            continuationDiagnosticValue("blankingDetected", in: event.diagnostics)
                == "true"
                && (
                    transientSequence == nil
                        || event.sequence > transientSequence!
                )
        }
        let mechanism =
            blankingEvent.flatMap {
                continuationDiagnosticValue(
                    "dominantBlankingMechanism",
                    in: $0.diagnostics
                )
            }
            ?? timelineEvents.compactMap {
                continuationDiagnosticValue(
                    "dominantBlankingMechanism",
                    in: $0.diagnostics
                )
            }.last

        switch mechanism {
        case "rootEmptied":
            return "transientUIThenRootEmptied"
        case "rootHidden":
            return "transientUIThenRootHidden"
        case "bodyEmptied":
            return "transientUIThenBodyEmptied"
        case "appRootReplaced":
            return "transientUIThenAppRootReplaced"
        case "navigationDocumentReset":
            return "transientUIThenNavigationReset"
        case "cssHidden":
            return "transientUIThenCSSHidden"
        case "renderStateBlank", "loadingContainerRemoved":
            return "transientUIThenRenderStateBlank"
        default:
            break
        }

        let localBranch = continuationEvents.compactMap {
            continuationDiagnosticValue("localBranchClassifier", in: $0.diagnostics)
        }.last
        if localBranch == "appState" {
            return "transientUIThenAwaitingLocalState"
        }

        let trace = snapshot.appStateDependencyTrace.correlationSummary
        if trace.classification == "appStateWaitWithNoObservableDependency"
            || trace.classification == "appStateWaitWithNoObservableBrowserDependency"
            || trace.popupReadKeyHashesNeverWritten.isEmpty == false
        {
            return "transientUIThenAwaitingLocalState"
        }

        if blankingEvent != nil {
            return "transientUIThenMissingGenericBrowserSignal"
        }

        let finalBlank = timelineEvents.last.flatMap { event in
            continuationDiagnosticValue("blankCandidate", in: event.diagnostics)
        } == "true"
        if finalBlank {
            return "transientUIThenRenderStateBlank"
        }

        return "unknown"
    }

    private func raindropExecuteScriptContinuationPhaseObserved(
        _ phase: String,
        in events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    ) -> Bool {
        events.contains { event in
            event.resultClassifier == phase
                || event.diagnostics.contains("phase=\(phase)")
        }
    }

    private func executeScriptShapeResultTypeCategory(
        _ shapeSummary: String?
    ) -> String? {
        guard let shapeSummary else { return nil }
        for part in shapeSummary.split(separator: ";") {
            if part.hasPrefix("resultTypeCategory=") {
                return String(part.dropFirst("resultTypeCategory=".count))
            }
        }
        return nil
    }

    private func raindropExecuteScriptNativeExecutorResultShape(
        in snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot
    ) -> String? {
        guard let record = raindropParseJSExecuteScriptCallRecord(in: snapshot)
        else { return nil }
        for diagnostic in record.diagnostics {
            guard let range = diagnostic.range(of: "resultShape=") else {
                continue
            }
            let suffix = diagnostic[range.upperBound...]
            let value = suffix.prefix { character in
                character != "." && character != " " && character != ";"
            }
            if value.isEmpty == false { return String(value) }
        }
        return nil
    }

    private func raindropExecuteScriptBridgeResultShape(
        in events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    ) -> String? {
        for event in events.reversed() {
            if let shape = continuationShapeSummaryValue(
                "executeScriptBridgeResultShape",
                in: event.diagnostics
            ) {
                return shape
            }
        }
        return nil
    }

    private func raindropExecuteScriptPopupObservedResultShape(
        in events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    ) -> String? {
        for event in events.reversed() {
            if let shape = continuationShapeSummaryValue(
                "executeScriptResultShape",
                in: event.diagnostics
            ) {
                return shape
            }
        }
        return nil
    }

    private func raindropExecuteScriptContinuationResultShape(
        in events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    ) -> String? {
        raindropExecuteScriptPopupObservedResultShape(in: events)
            ?? raindropExecuteScriptBridgeResultShape(in: events)
    }

    private func raindropExecuteScriptInvocationMode(
        in events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    ) -> String? {
        for event in events {
            if let mode = continuationDiagnosticValue(
                "invocationMode",
                in: event.diagnostics
            ) {
                return mode
            }
        }
        return nil
    }

    private func raindropExecuteScriptLastErrorSemantics(
        in snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot,
        continuationEvents: [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    ) -> String {
        guard let record = raindropParseJSExecuteScriptCallRecord(in: snapshot)
        else { return "notObserved" }
        if record.succeeded && record.lastErrorCode != nil {
            return "lastErrorSetOnSuccess"
        }
        if record.succeeded == false && record.lastErrorCode == nil {
            return "lastErrorClearOnFailure"
        }
        if continuationEvents.contains(where: {
            $0.resultClassifier == "popupPromiseRejected"
                || $0.diagnostics.contains(
                    "executeScriptContinuationPhase=popupCallbackRejected"
                )
        }), record.succeeded {
            return "lastErrorSetOnSuccess"
        }
        if record.succeeded {
            return "lastErrorClearOnSuccess"
        }
        return "lastErrorSetOnFailure"
    }

    private let chromeMV3ExecuteScriptResultDeliveryClassifierCatalog: Set<
        String
    > = [
        "objectResultNotDeliveredToPopup",
        "objectResultDeliveredThenRenderStateBlank",
        "objectResultDeliveredThenLocalAppStateWait",
        "objectResultDeliveredThenUnhandledException",
        "objectResultDeliveredThenUnhandledRejection",
        "callbackResultShapeStillWrong",
        "lastErrorSemanticsWrong",
        "raindropReachesUsableUI",
        "unknown",
    ]

    private func classifyExecuteScriptResultDelivery(
        snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot,
        domStateJSON: String,
        continuationEvents: [ChromeMV3PopupOptionsJSDebugRouteEventRecord],
        firstContinuationBlocker: String,
        firstUIDisappearanceBlocker: String,
        firstPostParseBlocker: String
    ) -> String {
        guard raindropParseJSExecuteScriptSucceeded(in: snapshot) else {
            return "unknown"
        }

        let lastErrorSemantics = raindropExecuteScriptLastErrorSemantics(
            in: snapshot,
            continuationEvents: continuationEvents
        )
        if lastErrorSemantics == "lastErrorSetOnSuccess"
            || lastErrorSemantics == "lastErrorClearOnFailure"
        {
            return "lastErrorSemanticsWrong"
        }

        let nativeShape = raindropExecuteScriptNativeExecutorResultShape(
            in: snapshot
        )
        let bridgeShape = raindropExecuteScriptBridgeResultShape(
            in: continuationEvents
        )
        let popupShape = raindropExecuteScriptPopupObservedResultShape(
            in: continuationEvents
        )
        let bridgeCategory = executeScriptShapeResultTypeCategory(bridgeShape)
        let popupCategory = executeScriptShapeResultTypeCategory(popupShape)
        let invocationMode =
            raindropExecuteScriptInvocationMode(in: continuationEvents)
            ?? "promise"
        let popupResolved =
            raindropExecuteScriptContinuationPhaseObserved(
                "popupPromiseResolved",
                in: continuationEvents
            )
            || raindropExecuteScriptContinuationPhaseObserved(
                "popupCallbackInvoked",
                in: continuationEvents
            )

        if invocationMode == "callback",
           firstContinuationBlocker == "executeScriptResultShapeUnexpected"
            || (
                bridgeCategory == "object"
                    && popupCategory != "object"
                    && popupResolved
            )
        {
            return "callbackResultShapeStillWrong"
        }

        let nativeObject =
            nativeShape == "object"
            || bridgeCategory == "object"
        if nativeObject == false || popupCategory != "object" || popupResolved == false
        {
            if firstContinuationBlocker == "executeScriptResultShapeUnexpected" {
                return invocationMode == "callback"
                    ? "callbackResultShapeStillWrong"
                    : "objectResultNotDeliveredToPopup"
            }
            if popupCategory != "object" || popupResolved == false {
                return "objectResultNotDeliveredToPopup"
            }
        }

        let domObject =
            domStateJSON.data(using: .utf8).flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            } ?? [:]
        let coarse = domObject["coarseClassification"] as? String ?? ""
        let usableForm = domObject["usableFormCandidate"] as? Bool ?? false
        if coarse == "usable onboarding/login UI reached" || usableForm {
            return "raindropReachesUsableUI"
        }

        if continuationEvents.contains(where: {
            $0.resultClassifier == "popupContinuationException"
        }) {
            return "objectResultDeliveredThenUnhandledException"
        }
        if continuationEvents.contains(where: {
            $0.resultClassifier == "popupContinuationUnhandledRejection"
        }) {
            return "objectResultDeliveredThenUnhandledRejection"
        }

        let postParseEvents = raindropPostParseEvents(in: snapshot)
        if postParseEvents.contains(where: {
            $0.eventKind == "unhandledRejection"
        }) {
            return "objectResultDeliveredThenUnhandledRejection"
        }
        if postParseEvents.contains(where: {
            $0.eventKind == "scriptError"
        }) {
            return "objectResultDeliveredThenUnhandledException"
        }

        if firstUIDisappearanceBlocker == "transientUIThenRenderStateBlank"
            || firstUIDisappearanceBlocker == "transientUIThenRootEmptied"
            || firstUIDisappearanceBlocker == "transientUIThenBodyEmptied"
            || coarse == "blank"
        {
            return "objectResultDeliveredThenRenderStateBlank"
        }

        if firstContinuationBlocker == "popupLocalAppStateBranch"
            || firstPostParseBlocker.contains("appState")
            || coarse == "waits on app state"
            || firstUIDisappearanceBlocker == "transientUIThenAwaitingLocalState"
        {
            return "objectResultDeliveredThenLocalAppStateWait"
        }

        return "unknown"
    }

    private let chromeMV3RaindropClosingDecisionCatalog: Set<String> = [
        "fixGenericExecuteScriptDeliveryBug",
        "fixGenericCallbackOrLastErrorBug",
        "fixGenericRuntimeRouteBug",
        "fixGenericTabsRouteBug",
        "fixGenericStorageConsistencyBug",
        "fixGenericStorageOnChangedBug",
        "fixGenericPopupLifecycleBug",
        "reportMissingNarrowChromeAPI",
        "closeRaindropAsExtensionLocalRenderState",
        "closeRaindropAsExtensionLocalAuthOrNetworkState",
        "closeRaindropAsInsufficientSignalMoveOn",
        "unknownButStopDiagnostics",
    ]

    private func classifyRaindropClosingDecision(
        snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot,
        domStateJSON: String,
        firstPostParseBlocker: String,
        firstContinuationBlocker: String,
        firstUIDisappearanceBlocker: String,
        resultDeliveryClassifier: String
    ) -> String {
        let trace = snapshot.appStateDependencyTrace.correlationSummary
        let domObject =
            domStateJSON.data(using: .utf8).flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            } ?? [:]
        let coarse = domObject["coarseClassification"] as? String ?? ""
        let renderTimelineEvents =
            raindropPopupRenderTimelineEvents(in: snapshot)
        let dominantBlankingMechanism =
            renderTimelineEvents.compactMap {
                continuationDiagnosticValue(
                    "dominantBlankingMechanism",
                    in: $0.diagnostics
                )
            }.last ?? "none"
        let objectDelivered =
            resultDeliveryClassifier == "objectResultDeliveredThenRenderStateBlank"
            || resultDeliveryClassifier
                == "objectResultDeliveredThenLocalAppStateWait"
            || resultDeliveryClassifier == "raindropReachesUsableUI"
            || resultDeliveryClassifier
                == "objectResultDeliveredThenUnhandledException"
            || resultDeliveryClassifier
                == "objectResultDeliveredThenUnhandledRejection"

        if resultDeliveryClassifier == "lastErrorSemanticsWrong" {
            return "fixGenericCallbackOrLastErrorBug"
        }
        if resultDeliveryClassifier == "objectResultNotDeliveredToPopup"
            || resultDeliveryClassifier == "callbackResultShapeStillWrong"
        {
            return "fixGenericExecuteScriptDeliveryBug"
        }
        if firstContinuationBlocker == "executeScriptPromiseNotResolvedToPopup"
            || firstContinuationBlocker == "executeScriptResultShapeUnexpected"
            || firstContinuationBlocker == "executeScriptPromiseRejectedInPopup"
        {
            return "fixGenericExecuteScriptDeliveryBug"
        }
        if firstContinuationBlocker == "popupAwaitNeverResolved" {
            return "fixGenericCallbackOrLastErrorBug"
        }

        if objectDelivered == false {
            if resultDeliveryClassifier == "unknown" {
                return "closeRaindropAsInsufficientSignalMoveOn"
            }
            return "unknownButStopDiagnostics"
        }

        switch firstPostParseBlocker {
        case "popupToServiceWorkerRouteDropped",
            "serviceWorkerOnMessageMissing",
            "serviceWorkerOnConnectMissing",
            "contentScriptToServiceWorkerRouteDropped":
            return "fixGenericRuntimeRouteBug"
        case "popupToContentScriptRouteDropped",
            "contentScriptListenerMissing",
            "messageBeforeContentScriptReady",
            "tabsTargetMappingWrong":
            return "fixGenericTabsRouteBug"
        case "storageWriteNotVisibleToPopup", "storageAppStateReadNoWriter":
            return "fixGenericStorageConsistencyBug"
        case "storageOnChangedMissed":
            return "fixGenericStorageOnChangedBug"
        case "missingNarrowChromeAPI":
            return "reportMissingNarrowChromeAPI"
        case "networkOrAuthWait":
            return "closeRaindropAsExtensionLocalAuthOrNetworkState"
        default:
            break
        }

        if firstUIDisappearanceBlocker == "transientUIThenNavigationReset"
            || dominantBlankingMechanism == "navigationDocumentReset"
        {
            return "fixGenericPopupLifecycleBug"
        }

        if resultDeliveryClassifier == "objectResultDeliveredThenUnhandledException"
            || resultDeliveryClassifier == "objectResultDeliveredThenUnhandledRejection"
            || firstContinuationBlocker == "popupContinuationException"
            || firstContinuationBlocker == "popupContinuationUnhandledRejection"
        {
            return "closeRaindropAsExtensionLocalRenderState"
        }

        if resultDeliveryClassifier == "raindropReachesUsableUI" {
            return "closeRaindropAsInsufficientSignalMoveOn"
        }

        let renderStateBlankObserved =
            resultDeliveryClassifier
                == "objectResultDeliveredThenRenderStateBlank"
            || firstUIDisappearanceBlocker == "transientUIThenRenderStateBlank"
            || dominantBlankingMechanism == "renderStateBlank"
            || dominantBlankingMechanism == "loadingContainerRemoved"
        let appStateWaitObserved =
            resultDeliveryClassifier
                == "objectResultDeliveredThenLocalAppStateWait"
            || firstContinuationBlocker == "popupLocalAppStateBranch"
            || firstContinuationBlocker == "popupRenderGateNoStateTransition"
            || firstPostParseBlocker
                == "appStateWaitWithNoObservableBrowserDependency"
            || coarse == "waits on app state"
        if renderStateBlankObserved || appStateWaitObserved {
            if trace.networkOrAuthDependencyObserved {
                return "closeRaindropAsExtensionLocalAuthOrNetworkState"
            }
            if trace.missingAPIsObserved.isEmpty == false {
                return "reportMissingNarrowChromeAPI"
            }
            return "closeRaindropAsExtensionLocalRenderState"
        }

        if firstUIDisappearanceBlocker == "transientUIThenMissingGenericBrowserSignal" {
            return "closeRaindropAsInsufficientSignalMoveOn"
        }

        return "unknownButStopDiagnostics"
    }

    private func raindropExecuteScriptContinuationSourceMapAvailability(
        in events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    ) -> String {
        for event in events.reversed() {
            if let availability = continuationDiagnosticValue(
                "sourceMapAvailability",
                in: event.diagnostics
            ) {
                return availability
            }
        }
        return "notObserved"
    }

    private func raindropExecuteScriptContinuationStackDiagnostics(
        in events: [ChromeMV3PopupOptionsJSDebugRouteEventRecord]
    ) -> [String] {
        var lines: [String] = []
        for event in events.suffix(24) {
            for diagnostic in event.diagnostics {
                if diagnostic.hasPrefix("stackFrame")
                    || diagnostic.hasPrefix("sourceMapOriginalFiles=")
                {
                    lines.append(diagnostic)
                }
            }
        }
        return Array(lines.suffix(12))
    }

    private func classifyFirstExecuteScriptContinuationBlocker(
        snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot,
        domStateJSON: String
    ) -> String {
        guard raindropParseJSExecuteScriptSucceeded(in: snapshot) else {
            return "unknown"
        }

        let continuationEvents =
            raindropExecuteScriptContinuationEvents(in: snapshot)
        guard continuationEvents.isEmpty == false else {
            return "noPopupContinuationObserved"
        }

        if continuationEvents.contains(where: {
            $0.resultClassifier == "popupContinuationException"
        }) {
            return "popupContinuationException"
        }
        if continuationEvents.contains(where: {
            $0.resultClassifier == "popupContinuationUnhandledRejection"
        }) {
            return "popupContinuationUnhandledRejection"
        }
        if raindropExecuteScriptContinuationPhaseObserved(
            "popupPromiseRejected",
            in: continuationEvents
        ) {
            return "executeScriptPromiseRejectedInPopup"
        }

        let nativeResolved = raindropExecuteScriptContinuationPhaseObserved(
            "nativeBridgeResolved",
            in: continuationEvents
        )
        let popupResolved =
            raindropExecuteScriptContinuationPhaseObserved(
                "popupPromiseResolved",
                in: continuationEvents
            )
            || raindropExecuteScriptContinuationPhaseObserved(
                "popupCallbackInvoked",
                in: continuationEvents
            )
        if nativeResolved && popupResolved == false {
            if snapshot.pendingUnresolvedJSDebugRoutes.contains(where: {
                $0.apiName == "scripting.executeScript"
            }) {
                return "executeScriptPromiseNotResolvedToPopup"
            }
            if raindropExecuteScriptContinuationPhaseObserved(
                "nativeBridgeReceive",
                in: continuationEvents
            ) {
                return "executeScriptPromiseNotResolvedToPopup"
            }
        }

        if let shape = raindropExecuteScriptContinuationResultShape(
            in: continuationEvents
        ) {
            if shape.contains("success=false")
                || shape.contains("frameResultPresent=false")
                || shape.contains("arrayLength=0")
            {
                return "executeScriptResultShapeUnexpected"
            }
        }

        if snapshot.pendingUnresolvedJSDebugRoutes.isEmpty == false,
           popupResolved
        {
            return "popupAwaitNeverResolved"
        }

        let localBranch = continuationEvents.compactMap {
            continuationDiagnosticValue("localBranchClassifier", in: $0.diagnostics)
        }.last
        if localBranch == "networkOrAuth" {
            return "popupLocalAuthOrNetworkBranch"
        }
        if localBranch == "appState" {
            return "popupLocalAppStateBranch"
        }

        let domObject =
            domStateJSON.data(using: .utf8).flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            } ?? [:]
        let visibleTextLength = domObject["visibleTextLength"] as? Int ?? 0
        let usableFormCandidate = domObject["usableFormCandidate"] as? Bool ?? false
        let renderTransitionObserved = continuationEvents.contains {
            $0.diagnostics.contains("renderTransitionObserved=true")
        }
        let finalCheckpointReached = continuationEvents.contains {
            $0.resultClassifier == "finalDOMCheckpoint"
                || $0.resultClassifier == "hostForcedFinalDOMCheckpoint"
        }
        let microtaskObserved = raindropExecuteScriptContinuationPhaseObserved(
            "firstMicrotaskAfterResolve",
            in: continuationEvents
        )
        let timerObserved = raindropExecuteScriptContinuationPhaseObserved(
            "firstTimerAfterResolve",
            in: continuationEvents
        )

        if popupResolved,
           microtaskObserved,
           timerObserved,
           finalCheckpointReached,
           renderTransitionObserved == false,
           visibleTextLength == 0,
           usableFormCandidate == false
        {
            if raindropExecuteScriptContinuationSourceMapAvailability(
                in: continuationEvents
            ) == "unavailable" {
                return "popupRenderGateNoStateTransition"
            }
            return "popupRenderGateNoStateTransition"
        }

        if popupResolved,
           microtaskObserved == false
        {
            return "popupTimerOrSchedulerGate"
        }

        if popupResolved,
           microtaskObserved,
           timerObserved == false,
           finalCheckpointReached == false
        {
            return "popupTimerOrSchedulerGate"
        }

        let trace = snapshot.appStateDependencyTrace.correlationSummary
        if popupResolved,
           trace.networkOrAuthDependencyObserved
        {
            return "popupLocalAuthOrNetworkBranch"
        }
        if popupResolved,
           trace.classification == "appStateWaitWithNoObservableDependency"
            || trace.classification
                == "appStateWaitWithNoObservableBrowserDependency"
            || trace.popupReadKeyHashesNeverWritten.isEmpty == false
        {
            return "popupLocalAppStateBranch"
        }

        if raindropExecuteScriptContinuationSourceMapAvailability(
            in: continuationEvents
        ) == "unavailable",
           popupResolved,
           finalCheckpointReached
        {
            return "popupRenderGateNoStateTransition"
        }

        return "unknown"
    }

    private func postParseDiagnosticInt(
        _ key: String,
        in diagnostics: [String]
    ) -> Int? {
        for diagnostic in diagnostics {
            guard let range = diagnostic.range(of: "\(key)=") else { continue }
            let suffix = diagnostic[range.upperBound...]
            let value = suffix.prefix { character in
                character != ";"
                    && character != "|"
                    && character != ","
                    && character != " "
            }
            if let intValue = Int(value) { return intValue }
        }
        return nil
    }

    private func postParseServiceWorkerListenerCounts(
        in snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot
    ) -> (onMessage: Int, onConnect: Int) {
        var onMessage = 0
        var onConnect = 0
        for route in snapshot.sanitizedBridgeRouteRecords {
            if route.apiName == "runtime.sendMessage" {
                onMessage = max(
                    onMessage,
                    route.listenerCount,
                    postParseDiagnosticInt(
                        "onMessageListenerCount",
                        in: route.diagnostics
                    ) ?? 0
                )
            }
            if route.apiName == "runtime.connect" {
                onConnect = max(onConnect, route.listenerCount)
                onMessage = max(
                    onMessage,
                    postParseDiagnosticInt(
                        "onMessageListenerCount",
                        in: route.diagnostics
                    ) ?? 0
                )
            }
        }
        for event in snapshot.jsDebugRouteEvents {
            if event.apiName.contains("runtime.onMessage") {
                onMessage = max(
                    onMessage,
                    postParseDiagnosticInt("listenerCount", in: event.diagnostics)
                        ?? 0
                )
            }
            if event.apiName.contains("runtime.onConnect") {
                onConnect = max(
                    onConnect,
                    postParseDiagnosticInt("listenerCount", in: event.diagnostics)
                        ?? 0
                )
            }
        }
        for record in snapshot.appStateDependencyTrace.portLifecycle {
            if record.apiName.contains("runtime.connect")
                || record.eventKind.contains("runtime.connect")
            {
                onConnect = max(onConnect, record.listenerCount)
            }
        }
        return (onMessage, onConnect)
    }

    private func postParseContentScriptListenerRegistered(
        in snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot
    ) -> Bool {
        if let summary = snapshot.contentScriptEndpointSummary,
           summary.messageListenerEndpointCount > 0
        {
            return true
        }
        return snapshot.sanitizedBridgeRouteRecords.contains { route in
            route.targetContext == "contentScript"
                && (
                    route.listenerCount > 0
                        || route.listenerInvoked
                        || route.diagnostics.contains {
                            $0.localizedCaseInsensitiveContains(
                                "runtime.onMessage listener registration observed"
                            )
                        }
                )
        }
    }

    private func postParseContentScriptListenerRegistrationObserved(
        in snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot
    ) -> Bool {
        if postParseContentScriptListenerRegistered(in: snapshot) {
            return true
        }
        return raindropPostParseEvents(in: snapshot).contains { event in
            event.targetContext == "contentScript"
                && event.diagnostics.contains {
                    $0.localizedCaseInsensitiveContains(
                        "runtime.onMessage listener registration observed"
                    )
                }
        }
    }

    private func postParseRouteFailed(
        _ route: ChromeMV3PopupOptionsSanitizedBridgeRouteRecord
    ) -> Bool {
        if route.firstMissingAPIOrPermissionOrLifecycleError != nil {
            return true
        }
        if route.resultClassifier == "permissionDenied" { return true }
        if route.resultClassifier == "noReceivingEnd" { return true }
        if route.resultClassifier == "noListener" { return true }
        if route.resultClassifier == "blocked" { return true }
        if route.resultClassifier == "listenerThrew" { return true }
        if route.resultClassifier == "listenerPresentButNoResponse" {
            return true
        }
        return false
    }

    private func classifyPostParseRouteBlocker(
        _ route: ChromeMV3PopupOptionsSanitizedBridgeRouteRecord,
        contentScriptListenerRegistered: Bool,
        serviceWorkerOnMessageCount: Int,
        serviceWorkerOnConnectCount: Int
    ) -> String? {
        guard postParseRouteFailed(route) else { return nil }
        if route.resultClassifier == "permissionDenied"
            || route.diagnostics.contains(where: {
                $0.localizedCaseInsensitiveContains("permission denied")
            })
        {
            return "permissionOrActiveTabDenied"
        }
        switch route.apiName {
        case "runtime.sendMessage":
            if route.sourceContext == "contentScript" {
                return "contentScriptToServiceWorkerRouteDropped"
            }
            if serviceWorkerOnMessageCount == 0
                && route.listenerCount == 0
                && route.listenerInvoked == false
            {
                return "serviceWorkerOnMessageMissing"
            }
            return "popupToServiceWorkerRouteDropped"
        case "runtime.connect":
            if serviceWorkerOnConnectCount == 0
                && route.listenerCount == 0
                && route.listenerInvoked == false
            {
                return "serviceWorkerOnConnectMissing"
            }
            return "popupToServiceWorkerRouteDropped"
        case "tabs.sendMessage":
            if contentScriptListenerRegistered == false {
                return "contentScriptListenerMissing"
            }
            return "popupToContentScriptRouteDropped"
        case "tabs.query", "tabs.getCurrent":
            return "tabsTargetMappingWrong"
        default:
            if route.targetContext == "contentScript" {
                return "popupToContentScriptRouteDropped"
            }
            if route.targetContext == "serviceWorker" {
                return "popupToServiceWorkerRouteDropped"
            }
            return nil
        }
    }

    private func classifyPostParseEventBlocker(
        _ event: ChromeMV3PopupOptionsJSDebugRouteEventRecord
    ) -> String? {
        if event.eventKind == "missingAPIAccess" {
            return "missingNarrowChromeAPI"
        }
        if event.eventKind == "resourceLoadError"
            || event.resultClassifier?
                .localizedCaseInsensitiveContains("network") == true
            || event.resultClassifier?
                .localizedCaseInsensitiveContains("auth") == true
        {
            return "networkOrAuthWait"
        }
        if controlledBitwardenPopupIsBlockerEvent(event) {
            let label = controlledBitwardenPopupBlockerLabel(event)
            if label.localizedCaseInsensitiveContains("permission") {
                return "permissionOrActiveTabDenied"
            }
            if label.localizedCaseInsensitiveContains("storage.session")
                || label.localizedCaseInsensitiveContains("storage.sync")
            {
                return "missingNarrowChromeAPI"
            }
            if label == "Port message not delivered"
                || label == "Port response not delivered"
            {
                return "popupToServiceWorkerRouteDropped"
            }
            if label == "unknown pending promise" {
                return "popupToServiceWorkerRouteDropped"
            }
        }
        return nil
    }

    private func classifyFirstPostParseBlocker(
        snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot,
        domStateJSON: String
    ) -> String {
        guard raindropParseJSExecuteScriptSucceeded(in: snapshot) else {
            return "unknown"
        }

        let subsequentRoutes = raindropPostParseRoutes(in: snapshot)
        let subsequentEvents = raindropPostParseEvents(in: snapshot)
        let serviceWorkerListeners =
            postParseServiceWorkerListenerCounts(in: snapshot)
        let contentScriptListenerRegistered =
            postParseContentScriptListenerRegistered(in: snapshot)
        let contentScriptListenerObserved =
            postParseContentScriptListenerRegistrationObserved(in: snapshot)
        let trace = snapshot.appStateDependencyTrace.correlationSummary

        if subsequentRoutes.contains(where: { $0.apiName == "tabs.sendMessage" }),
           contentScriptListenerObserved == false
        {
            return "contentScriptListenerMissing"
        }

        let tabsSendMessageRoute = subsequentRoutes.first {
            $0.apiName == "tabs.sendMessage"
        }
        if let tabsSendMessageRoute,
           contentScriptListenerObserved,
           tabsSendMessageRoute.listenerInvoked == false,
           postParseRouteFailed(tabsSendMessageRoute)
        {
            return "messageBeforeContentScriptReady"
        }

        for route in subsequentRoutes {
            if let blocker = classifyPostParseRouteBlocker(
                route,
                contentScriptListenerRegistered:
                    contentScriptListenerRegistered,
                serviceWorkerOnMessageCount: serviceWorkerListeners.onMessage,
                serviceWorkerOnConnectCount: serviceWorkerListeners.onConnect
            ) {
                return blocker
            }
        }

        for event in subsequentEvents {
            if let blocker = classifyPostParseEventBlocker(event) {
                return blocker
            }
        }

        if snapshot.pendingUnresolvedJSDebugRoutes.isEmpty == false {
            if subsequentRoutes.contains(where: {
                $0.apiName == "tabs.sendMessage"
            }) {
                return "popupToContentScriptRouteDropped"
            }
            return "popupToServiceWorkerRouteDropped"
        }

        if trace.classification == "appStateWaitWithNoWriter"
            || (
                trace.repeatedEmptyReadKeyHashes.isEmpty == false
                    && trace.popupReadKeyHashesNeverWritten.isEmpty == false
            )
        {
            return "storageAppStateReadNoWriter"
        }
        if trace.writtenKeyHashesWithoutObservedOnChangedDelivery.isEmpty
            == false
        {
            return "storageOnChangedMissed"
        }
        if trace.popupReadKeyHashesWrittenByServiceWorker.isEmpty == false
            && trace.popupReadKeyHashesNeverWritten.isEmpty == false
        {
            return "storageWriteNotVisibleToPopup"
        }
        if trace.missingAPIsObserved.isEmpty == false {
            return "missingNarrowChromeAPI"
        }
        if trace.networkOrAuthDependencyObserved {
            return "networkOrAuthWait"
        }
        if trace.classification == "appStateWaitWithNoObservableDependency"
            || trace.classification
                == "appStateWaitWithUnresolvedBridgeRoute"
        {
            return "appStateWaitWithNoObservableBrowserDependency"
        }

        if let domData = domStateJSON.data(using: .utf8),
           let domObject = try? JSONSerialization.jsonObject(with: domData)
            as? [String: Any]
        {
            let coarse =
                domObject["coarseClassification"] as? String ?? ""
            if coarse == "waits on app state"
                || coarse == "blank"
                || coarse == "spinner/loading"
            {
                if trace.popupReadKeyHashesNeverWritten.isEmpty == false {
                    return "storageAppStateReadNoWriter"
                }
                return "appStateWaitWithNoObservableBrowserDependency"
            }
        }

        return "unknown"
    }

    private func raindropPostParseSanitizedDiagnostics(
        snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot,
        domStateJSON: String
    ) -> ChromeMV3PostParseSanitizedDiagnostics {
        let firstBlocker = classifyFirstPostParseBlocker(
            snapshot: snapshot,
            domStateJSON: domStateJSON
        )
        let firstContinuationBlocker =
            classifyFirstExecuteScriptContinuationBlocker(
                snapshot: snapshot,
                domStateJSON: domStateJSON
            )
        let continuationEvents =
            raindropExecuteScriptContinuationEvents(in: snapshot)
        let renderTimelineEvents =
            raindropPopupRenderTimelineEvents(in: snapshot)
        let firstUIDisappearanceBlocker = classifyFirstUIDisappearanceBlocker(
            snapshot: snapshot,
            continuationEvents: continuationEvents
        )
        let resultDeliveryClassifier = classifyExecuteScriptResultDelivery(
            snapshot: snapshot,
            domStateJSON: domStateJSON,
            continuationEvents: continuationEvents,
            firstContinuationBlocker: firstContinuationBlocker,
            firstUIDisappearanceBlocker: firstUIDisappearanceBlocker,
            firstPostParseBlocker: firstBlocker
        )
        let nativeExecutorShape = raindropExecuteScriptNativeExecutorResultShape(
            in: snapshot
        )
        let bridgeResultShape = raindropExecuteScriptBridgeResultShape(
            in: continuationEvents
        )
        let popupObservedShape = raindropExecuteScriptPopupObservedResultShape(
            in: continuationEvents
        )
        let invocationMode =
            raindropExecuteScriptInvocationMode(in: continuationEvents)
            ?? "notObserved"
        let lastErrorSemantics = raindropExecuteScriptLastErrorSemantics(
            in: snapshot,
            continuationEvents: continuationEvents
        )
        let subsequentRoutes = raindropPostParseRoutes(in: snapshot)
        let subsequentEvents = raindropPostParseEvents(in: snapshot)
        let serviceWorkerListeners =
            postParseServiceWorkerListenerCounts(in: snapshot)
        let contentScriptSummary = snapshot.contentScriptEndpointSummary
        let trace = snapshot.appStateDependencyTrace
        let domObject =
            domStateJSON.data(using: .utf8).flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            } ?? [:]

        var lines: [String] = [
            "postParseClassifier=\(firstBlocker)",
            "executeScriptContinuationClassifier=\(firstContinuationBlocker)",
            "executeScriptContinuationEventCount=\(continuationEvents.count)",
            "executeScriptPopupObservedResolution=\(raindropExecuteScriptContinuationPhaseObserved("popupPromiseResolved", in: continuationEvents) || raindropExecuteScriptContinuationPhaseObserved("popupCallbackInvoked", in: continuationEvents))",
            "executeScriptNativeExecutorResultShape=\(nativeExecutorShape ?? "none")",
            "executeScriptBridgeResultShape=\(bridgeResultShape ?? "none")",
            "executeScriptBridgeResultTypeCategory=\(executeScriptShapeResultTypeCategory(bridgeResultShape) ?? "none")",
            "executeScriptPopupObservedResultShape=\(popupObservedShape ?? "none")",
            "executeScriptPopupObservedResultTypeCategory=\(executeScriptShapeResultTypeCategory(popupObservedShape) ?? "none")",
            "executeScriptResultShape=\(raindropExecuteScriptContinuationResultShape(in: continuationEvents) ?? "none")",
            "executeScriptInvocationMode=\(invocationMode)",
            "executeScriptLastErrorSemantics=\(lastErrorSemantics)",
            "executeScriptResultDeliveryClassifier=\(resultDeliveryClassifier)",
            "executeScriptSourceMapAvailability=\(raindropExecuteScriptContinuationSourceMapAvailability(in: continuationEvents))",
            "postParseRouteCount=\(subsequentRoutes.count)",
            "postParseEventCount=\(subsequentEvents.count)",
            "postParsePendingCount=\(snapshot.pendingUnresolvedJSDebugRoutes.count)",
            "postParseServiceWorkerOnMessageListeners=\(serviceWorkerListeners.onMessage)",
            "postParseServiceWorkerOnConnectListeners=\(serviceWorkerListeners.onConnect)",
            "postParseServiceWorkerCapturedListeners=\(trace.serviceWorkerCapturedListenerCount)",
            "postParseContentScriptListenerEndpoints=\(contentScriptSummary?.messageListenerEndpointCount ?? 0)",
            "postParseContentScriptConnectEndpoints=\(contentScriptSummary?.connectListenerEndpointCount ?? 0)",
            "postParseContentScriptListenerRegistered=\(postParseContentScriptListenerRegistrationObserved(in: snapshot))",
            "postParseAppStateClassification=\(trace.correlationSummary.classification)",
            "postParseStorageOnChangedReachedListeners=\(trace.correlationSummary.storageOnChangedReachedRegisteredListeners)",
            "postParsePopupReadsNeverWritten=\(trace.correlationSummary.popupReadKeyHashesNeverWritten.count)",
            "postParsePopupReadsWrittenByServiceWorker=\(trace.correlationSummary.popupReadKeyHashesWrittenByServiceWorker.count)",
            "postParseRepeatedEmptyReads=\(trace.correlationSummary.repeatedEmptyReadKeyHashes.count)",
            "postParseMissingAPIs=\(trace.correlationSummary.missingAPIsObserved.joined(separator: ","))",
            "postParseNetworkOrAuthDependency=\(trace.correlationSummary.networkOrAuthDependencyObserved)",
            "postParseVisibleTextLength=\(domObject["visibleTextLength"] ?? "na")",
            "postParseUsableFormCandidate=\(domObject["usableFormCandidate"] ?? "na")",
            "postParseCoarseClassification=\(domObject["coarseClassification"] ?? "na")",
            "postParseNativeHostLaunched=false",
            "popupRenderTimelineEventCount=\(renderTimelineEvents.count)",
            "popupRenderTimelineTransientUIObserved=\(renderTimelineTransientUIObserved(in: renderTimelineEvents))",
            "firstUIDisappearanceBlocker=\(firstUIDisappearanceBlocker)",
            "popupRenderTimelineBlankingRelativeToExecuteScript=\(renderTimelineEvents.compactMap { continuationDiagnosticValue("blankingRelativeToExecuteScript", in: $0.diagnostics) }.first ?? "none")",
            "popupRenderTimelineDominantBlankingMechanism=\(renderTimelineEvents.compactMap { continuationDiagnosticValue("dominantBlankingMechanism", in: $0.diagnostics) }.first ?? "none")",
        ]

        let popupMessagingRoutes = subsequentRoutes.filter {
            ["runtime.sendMessage", "runtime.connect"].contains($0.apiName)
                && $0.sourceContext != "contentScript"
        }
        for route in popupMessagingRoutes.prefix(24) {
            lines.append(
                [
                    "postParsePopupMessaging",
                    "api=\(route.apiName)",
                    "target=\(route.targetContext)",
                    "classifier=\(route.resultClassifier)",
                    "listeners=\(route.listenerCount)",
                    "invoked=\(route.listenerInvoked)",
                    "sendResponse=\(route.sendResponseCalled)",
                    "shape=\(route.safeMessageShapeClassification)",
                    "fields=\(route.safeCommandTypeActionFieldNames.joined(separator: ","))",
                    "firstError=\(route.firstMissingAPIOrPermissionOrLifecycleError ?? "none")",
                ].joined(separator: " ")
            )
        }

        let tabsRoutes = subsequentRoutes.filter {
            ["tabs.query", "tabs.sendMessage", "tabs.getCurrent", "tabs.connect"]
                .contains($0.apiName)
        }
        for route in tabsRoutes.prefix(24) {
            lines.append(
                [
                    "postParseTabsRoute",
                    "api=\(route.apiName)",
                    "target=\(route.targetContext)",
                    "classifier=\(route.resultClassifier)",
                    "listeners=\(route.listenerCount)",
                    "invoked=\(route.listenerInvoked)",
                    "shape=\(route.safeMessageShapeClassification)",
                    "firstError=\(route.firstMissingAPIOrPermissionOrLifecycleError ?? "none")",
                ].joined(separator: " ")
            )
        }

        let contentScriptRoutes = subsequentRoutes.filter {
            $0.sourceContext == "contentScript"
                || $0.targetContext == "contentScript"
        }
        for route in contentScriptRoutes.prefix(16) {
            lines.append(
                [
                    "postParseContentScriptRoute",
                    "api=\(route.apiName)",
                    "source=\(route.sourceContext)",
                    "target=\(route.targetContext)",
                    "classifier=\(route.resultClassifier)",
                    "listeners=\(route.listenerCount)",
                    "invoked=\(route.listenerInvoked)",
                ].joined(separator: " ")
            )
        }

        for record in trace.storageOperations.suffix(40) {
            lines.append(
                [
                    "postParseStorage",
                    "context=\(record.context)",
                    "area=\(record.area)",
                    "op=\(record.operation)",
                    "keyShape=\(record.keyShape)",
                    "keyCount=\(record.keyCount)",
                    "empty=\(record.emptyResult)",
                    "populated=\(record.populatedResult)",
                    "classifier=\(record.resultClassifier)",
                ].joined(separator: " ")
            )
        }
        for record in trace.storageChangeDispatches.suffix(16) {
            lines.append(
                [
                    "postParseStorageChange",
                    "area=\(record.area)",
                    "changedKeyCount=\(record.changedKeyCount)",
                    "dispatched=\(record.dispatched)",
                    "listenerCounts=\(record.listenerCountByContext.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ","))",
                    "listenerReceived=\(record.listenerReceivedByContext.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ","))",
                ].joined(separator: " ")
            )
        }

        for event in subsequentEvents.filter({
            [
                "consoleError",
                "consoleWarn",
                "unhandledRejection",
                "scriptError",
                "cspViolation",
                "resourceLoadError",
                "missingAPIAccess",
            ].contains($0.eventKind)
        }).prefix(24) {
            lines.append(
                [
                    "postParseConsole",
                    "seq=\(event.sequence)",
                    "event=\(event.eventKind)",
                    "api=\(event.apiName)",
                    "classifier=\(event.resultClassifier ?? "none")",
                    "firstError=\(event.firstMissingAPIOrPermissionOrLifecycleError ?? "none")",
                ].joined(separator: " ")
            )
        }

        for event in subsequentEvents.prefix(40) {
            lines.append(
                [
                    "postParseRouteEvent",
                    "seq=\(event.sequence)",
                    "event=\(event.eventKind)",
                    "api=\(event.apiName)",
                    "target=\(event.targetContext ?? "unknown")",
                    "classifier=\(event.resultClassifier ?? "none")",
                    "shape=\(event.safeMessageShapeClassification)",
                    "firstError=\(event.firstMissingAPIOrPermissionOrLifecycleError ?? "none")",
                ].joined(separator: " ")
            )
        }

        for event in subsequentEvents.filter({
            $0.eventKind == "postBootstrapCheckpoint"
        }).suffix(6) {
            lines.append(
                [
                    "postParseDOMCheckpoint",
                    "seq=\(event.sequence)",
                    "classifier=\(event.resultClassifier ?? "none")",
                    "diagnostics=\(event.diagnostics.joined(separator: "|"))",
                ].joined(separator: " ")
            )
        }

        for pending in snapshot.pendingUnresolvedJSDebugRoutes.prefix(12) {
            lines.append(
                "postParsePending api=\(pending.apiName) classifier=\(pending.resultClassifier ?? "pending") ageMs=\(pending.ageMilliseconds.map(String.init) ?? "na")"
            )
        }

        for event in continuationEvents.prefix(40) {
            lines.append(
                [
                    "executeScriptContinuation",
                    "seq=\(event.sequence)",
                    "phase=\(event.resultClassifier ?? "none")",
                    "classifier=\(event.resultClassifier ?? "none")",
                    "firstError=\(event.firstMissingAPIOrPermissionOrLifecycleError ?? "none")",
                    "diagnostics=\(event.diagnostics.joined(separator: "|"))",
                ].joined(separator: " ")
            )
        }
        for stackLine in raindropExecuteScriptContinuationStackDiagnostics(
            in: continuationEvents
        ) {
            lines.append("executeScriptContinuationStack \(stackLine)")
        }

        for event in renderTimelineEvents.prefix(48) {
            lines.append(
                [
                    "popupRenderTimeline",
                    "seq=\(event.sequence)",
                    "phase=\(event.resultClassifier ?? "none")",
                    "diagnostics=\(event.diagnostics.joined(separator: "|"))",
                ].joined(separator: " ")
            )
        }

        let closingDecision = classifyRaindropClosingDecision(
            snapshot: snapshot,
            domStateJSON: domStateJSON,
            firstPostParseBlocker: firstBlocker,
            firstContinuationBlocker: firstContinuationBlocker,
            firstUIDisappearanceBlocker: firstUIDisappearanceBlocker,
            resultDeliveryClassifier: resultDeliveryClassifier
        )
        lines.append("raindropClosingDecision=\(closingDecision)")

        return ChromeMV3PostParseSanitizedDiagnostics(
            firstBlocker: firstBlocker,
            firstContinuationBlocker: firstContinuationBlocker,
            firstUIDisappearanceBlocker: firstUIDisappearanceBlocker,
            resultDeliveryClassifier: resultDeliveryClassifier,
            closingDecision: closingDecision,
            lines: lines
        )
    }

    @MainActor
    private func waitForControlledBitwardenPopupBridgeSnapshot(
        module: SumiExtensionsModule,
        profileID: String,
        extensionID: String
    ) async throws -> ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot {
        var latest:
            ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot?
        for _ in 0..<280 {
            if let snapshot =
                module
                .chromeMV3PopupOptionsBridgeDiagnosticsSnapshotForTesting(
                    profileID: profileID,
                    extensionID: extensionID
                )
            {
                latest = snapshot
                let manifestReturned =
                    controlledBitwardenPopupManifestReturnedSequence(snapshot)
                        != nil
                let postManifestEvents =
                    controlledBitwardenPopupPostGetManifestEvents(snapshot)
                let hasPostManifestBlocker =
                    postManifestEvents.contains { event in
                        event.firstMissingAPIOrPermissionOrLifecycleError != nil
                            || [
                                "consoleError",
                                "cspViolation",
                                "hostNavigationFailure",
                                "resourceLoadError",
                                "scriptError",
                                "unhandledRejection",
                                "webContentProcessTerminated",
                            ].contains(event.eventKind)
                    }
                let finalCheckpointReached =
                    postManifestEvents.contains { event in
                        event.eventKind == "postBootstrapCheckpoint"
                            && event.diagnostics.contains("phase=final")
                    }
                let bootstrapResourceClasses = Set(
                    postManifestEvents
                        .filter { $0.eventKind == "bootstrapResourceObserved" }
                        .flatMap(\.diagnostics)
                        .compactMap { diagnostic -> String? in
                            guard diagnostic.hasPrefix("resourceClass=")
                            else { return nil }
                            return String(
                                diagnostic.dropFirst(
                                    "resourceClass=".count
                                )
                            )
                        }
                )
                let resourceFinalClasses = Set(
                    postManifestEvents
                        .filter { $0.eventKind == "postBootstrapCheckpoint" }
                        .flatMap(\.diagnostics)
                        .compactMap { diagnostic -> String? in
                            guard diagnostic.hasPrefix(
                                "phase=resource-final-"
                            ) else { return nil }
                            return String(
                                diagnostic.dropFirst(
                                    "phase=resource-final-".count
                                )
                            )
                        }
                )
                let resourceFinalCheckpointReached =
                    bootstrapResourceClasses.isEmpty
                        || bootstrapResourceClasses.isSubset(
                            of: resourceFinalClasses
                        )
                if manifestReturned
                    && (
                        hasPostManifestBlocker
                            || (
                                finalCheckpointReached
                                    && resourceFinalCheckpointReached
                            )
                    ) {
                    return snapshot
                }
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        _ = try? await module
            .chromeMV3PopupOptionsEvaluateJavaScriptForTesting(
                profileID: profileID,
                extensionID: extensionID,
                script: """
                (() => {
                  const forceCheckpoint =
                    globalThis.__sumiChromeMV3PopupOptionsDebugForceCheckpoint;
                  if (typeof forceCheckpoint !== 'function') {
                    return false;
                  }
                  forceCheckpoint('host-forced-final');
                  return true;
                })();
                """
            )
        try? await Task.sleep(nanoseconds: 50_000_000)
        if let snapshot =
            module
            .chromeMV3PopupOptionsBridgeDiagnosticsSnapshotForTesting(
                profileID: profileID,
                extensionID: extensionID
            )
        {
            latest = snapshot
        }
        return try XCTUnwrap(
            latest,
            "No controlled popup bridge diagnostics snapshot was captured."
        )
    }

    @MainActor
    private func controlledBitwardenPopupDOMState(
        module: SumiExtensionsModule,
        profileID: String,
        extensionID: String
    ) async throws -> String {
        let script = """
        (() => {
          const text = document.body && document.body.innerText
            ? document.body.innerText
            : "";
          const title = typeof document.title === 'string'
            ? document.title
            : "";
          const debugSnapshot =
            globalThis.__sumiChromeMV3PopupOptionsDebugSnapshot
              ? globalThis.__sumiChromeMV3PopupOptionsDebugSnapshot()
              : { events: [], pending: [] };
          const inputCount =
            document.querySelectorAll('input,textarea,select').length;
          const buttonCount =
            document.querySelectorAll(
              'button,[role="button"],input[type="button"],input[type="submit"]'
            ).length;
          const linkCount = document.querySelectorAll('a[href]').length;
          const controlCount = inputCount + buttonCount + linkCount;
          const elementCount = document.body
            ? document.body.querySelectorAll('*').length
            : 0;
          const appRoot = document.querySelector(
            'app-root,[data-app-root],main,#app,#root,#react'
          );
          const appRootCount = document.querySelectorAll(
            'app-root,[data-app-root],main,#app,#root,#react'
          ).length;
          const appRootChildCount = appRoot
            ? appRoot.children.length
            : 0;
          const appRootElementCount = appRoot
            ? appRoot.querySelectorAll('*').length
            : 0;
          const appRootTextLength = appRoot && appRoot.innerText
            ? appRoot.innerText.trim().length
            : 0;
          const safeToken = (value) => {
            const text = String(value || '').trim();
            if (!text || text.length > 80) return null;
            if (!/^[A-Za-z0-9_-]+$/.test(text)) return null;
            if (/(auth|cookie|jwt|oauth|passwd|password|secret|session|token)/i
                .test(text)) {
              return 'redacted';
            }
            return text;
          };
          const classTokens = (node) => {
            if (!node || !node.classList) return [];
            return Array.from(node.classList)
              .map(safeToken)
              .filter(Boolean)
              .slice(0, 12)
              .sort();
          };
          const bodyChildTags = Array.from(
            document.body ? document.body.children : []
          ).slice(0, 8).map((node) => {
            const id = node.id ? '#id' : '';
            const klass = node.classList && node.classList.length
              ? '.class'
              : '';
            return String(node.tagName || 'node').toLowerCase() + id + klass;
          });
          const appRootChildTags = Array.from(appRoot ? appRoot.children : [])
            .slice(0, 8)
            .map((node) => {
              const id = node.id ? '#id' : '';
              const klass = node.classList && node.classList.length
                ? '.class'
                : '';
              return String(node.tagName || 'node').toLowerCase() + id + klass;
            });
          const appRootChildClassTokens =
            Array.from(appRoot ? appRoot.children : [])
              .slice(0, 4)
              .map(classTokens);
          const storageShape = (() => {
            const shape = {
              localStorageAvailable: false,
              sessionStorageAvailable: false,
              indexedDBAvailable: typeof indexedDB !== 'undefined',
              localStorageKeyCount: -1,
              sessionStorageKeyCount: -1,
              hasPersistPrimary: false,
              hasExtensionModeCache: false,
              hasExtensionHeightCache: false
            };
            try {
              shape.localStorageKeyCount = localStorage.length;
              shape.localStorageAvailable = true;
              shape.hasPersistPrimary =
                localStorage.getItem('persist:primary') !== null;
              shape.hasExtensionModeCache =
                localStorage.getItem('_extension_mode_cached') !== null;
              shape.hasExtensionHeightCache =
                localStorage.getItem('_extension_height_cached') !== null;
            } catch (_) {}
            try {
              shape.sessionStorageKeyCount = sessionStorage.length;
              shape.sessionStorageAvailable = true;
            } catch (_) {}
            return shape;
          })();
          const locationShape = {
            protocol: location.protocol,
            pathnameDepth: location.pathname
              ? location.pathname.split('/').filter(Boolean).length
              : 0,
            searchKeys: location.search
              ? location.search.slice(1).split('&').filter(Boolean)
                  .map((part) => part.split('=')[0]).sort().slice(0, 12)
              : [],
            hasHash: location.hash.length > 0
          };
          const hasBusyIndicator = !!document.querySelector(
            '[role="progressbar"],[aria-busy="true"],.spinner,.loading,.loader,[data-loading="true"]'
          );
          const hasLoadingText =
            /\\b(loading|please wait|initializing|syncing)\\b/i.test(text);
          const titleHasLoadingText =
            /\\b(loading|please wait|initializing|syncing)\\b/i.test(title);
          const blankCandidate =
            text.trim().length === 0 && controlCount === 0 && elementCount <= 1;
          const usableFormCandidate =
            (inputCount > 0 && buttonCount > 0)
              || (controlCount >= 2 && text.trim().length > 0);
          const sentinels = Array.isArray(debugSnapshot.events)
            ? debugSnapshot.events.filter((event) => {
                return event && event.eventKind === 'postBootstrapCheckpoint';
              })
            : [];
          const finalSentinel =
            sentinels.find((event) => {
              return Array.isArray(event.diagnostics)
                && event.diagnostics.includes('phase=final');
            }) || sentinels[sentinels.length - 1] || null;
          let coarseClassification = 'waits on app state';
          if (usableFormCandidate && !hasBusyIndicator) {
            coarseClassification = 'usable onboarding/login UI reached';
          } else if (blankCandidate) {
            coarseClassification = 'blank';
          } else if (hasBusyIndicator || hasLoadingText || titleHasLoadingText) {
            coarseClassification = 'spinner/loading';
          }
          return JSON.stringify({
            readyState: document.readyState,
            hasLoadingText,
            titleHasLoadingText,
            hasBusyIndicator,
            inputCount,
            buttonCount,
            linkCount,
            controlCount,
            elementCount,
            appRootCount,
            appRootChildCount,
            appRootElementCount,
            appRootTextLength,
            bodyChildTags,
            appRootChildTags,
            htmlClassTokens: classTokens(document.documentElement),
            bodyClassTokens: classTokens(document.body),
            appRootClassTokens: classTokens(appRoot),
            appRootChildClassTokens,
            locationShape,
            storageShape,
            blankCandidate,
            usableFormCandidate,
            coarseClassification,
            postBootstrapClassifier:
              finalSentinel && finalSentinel.resultClassifier
                ? finalSentinel.resultClassifier
                : null,
            visibleTextLength: text.trim().length,
            debugEventCount: Array.isArray(debugSnapshot.events)
              ? debugSnapshot.events.length
              : 0,
            pendingCount: Array.isArray(debugSnapshot.pending)
              ? debugSnapshot.pending.length
              : 0
          });
        })();
        """
        let value = try await module
            .chromeMV3PopupOptionsEvaluateJavaScriptForTesting(
                profileID: profileID,
                extensionID: extensionID,
                script: script
            )
        return value as? String ?? "{}"
    }

    private func controlledBitwardenPopupFirstFatalBlocker(
        _ snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot
    ) -> String {
        let events = controlledBitwardenPopupPostGetManifestEvents(snapshot)
        if let firstBlocker = events.first(where: {
            controlledBitwardenPopupIsBlockerEvent($0)
        }) {
            return controlledBitwardenPopupBlockerLabel(firstBlocker)
        }
        if let hostPreflightFailure = events.first(where: {
            $0.eventKind == "hostPreloadResource"
                && $0.firstMissingAPIOrPermissionOrLifecycleError != nil
        }) {
            return hostPreflightFailure.resultClassifier
                ?? hostPreflightFailure.firstMissingAPIOrPermissionOrLifecycleError
                ?? "host resource preflight failed"
        }
        if events.contains(where: {
            $0.eventKind == "resourceLoadError"
        }) {
            return "resource load error"
        }
        if events.contains(where: {
            $0.eventKind == "cspViolation"
        }) {
            return "CSP violation"
        }
        if events.contains(where: {
            $0.eventKind == "scriptError"
        }) {
            return "script error"
        }
        if events.contains(where: {
            $0.eventKind == "unhandledRejection"
        }) {
            return "Promise rejection"
        }
        if events.contains(where: {
            $0.eventKind == "consoleError"
        }) {
            return "console error"
        }
        if events.contains(where: {
            $0.eventKind == "hostNavigationFailure"
        }) {
            return "navigation failed"
        }
        if events.contains(where: {
            $0.eventKind == "webContentProcessTerminated"
        }) {
            return "web content process terminated"
        }
        if events.contains(where: {
            $0.resultClassifier == "missing storage.session"
        }) {
            return "missing storage.session"
        }
        if events.contains(where: {
            $0.resultClassifier == "missing storage.sync"
        }) {
            return "missing storage.sync"
        }
        if events.contains(where: {
            $0.resultClassifier == "missing storage.managed"
        }) {
            return "missing storage.managed"
        }
        if events.contains(where: {
            $0.resultClassifier == "service worker not waking"
        }) {
            return "service worker not waking"
        }
        if events.contains(where: {
            $0.resultClassifier == "Port message not delivered"
        }) {
            return "Port message not delivered"
        }
        if events.contains(where: {
            $0.resultClassifier == "Port response not delivered"
        }) {
            return "Port response not delivered"
        }
        if events.contains(where: {
            $0.resultClassifier == "missing tabs.connect"
        }) {
            return "missing tabs.connect"
        }
        if let pending = snapshot.pendingUnresolvedJSDebugRoutes.first(
            where: { pending in
                events.contains { $0.sequence == pending.sequence }
            }
        ) {
            return pending.resultClassifier ?? "unknown pending promise"
        }
        if let lastError = events.first(where: {
            $0.firstMissingAPIOrPermissionOrLifecycleError != nil
        }) {
            return lastError.resultClassifier ?? "unknown"
        }
        if let finalCheckpoint = events.last(where: {
            $0.eventKind == "postBootstrapCheckpoint"
                && $0.diagnostics.contains("phase=final")
        }) {
            return finalCheckpoint.resultClassifier
                ?? "post-getManifest sentinel completed"
        }
        if let checkpoint = events.last(where: {
            $0.eventKind == "postBootstrapCheckpoint"
        }) {
            return checkpoint.resultClassifier
                ?? "post-getManifest sentinel observed"
        }
        return "unknown"
    }

    private func controlledBitwardenPopupIsBlockerEvent(
        _ event: ChromeMV3PopupOptionsJSDebugRouteEventRecord
    ) -> Bool {
        if event.firstMissingAPIOrPermissionOrLifecycleError != nil {
            return true
        }
        if [
            "consoleError",
            "cspViolation",
            "hostNavigationFailure",
            "resourceLoadError",
            "scriptError",
            "unhandledRejection",
            "webContentProcessTerminated",
        ].contains(event.eventKind) {
            return true
        }
        return [
            "missing storage.session",
            "missing storage.sync",
            "missing storage.managed",
            "service worker not waking",
            "Port message not delivered",
            "Port response not delivered",
            "missing tabs.connect",
            "unknown pending promise",
        ].contains(event.resultClassifier ?? "")
    }

    private func controlledBitwardenPopupBlockerLabel(
        _ event: ChromeMV3PopupOptionsJSDebugRouteEventRecord
    ) -> String {
        if let classifier = event.resultClassifier,
           classifier != "pending"
        {
            return classifier
        }
        return event.firstMissingAPIOrPermissionOrLifecycleError
            ?? event.eventKind
    }

    private func controlledBitwardenTabsConnectActuallyFatal(
        _ snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot
    ) -> Bool {
        guard let firstFatal =
            controlledBitwardenPopupPostGetManifestEvents(snapshot)
            .first(where: { event in
                [
                    "missing storage.session",
                    "missing storage.sync",
                    "missing storage.managed",
                    "service worker not waking",
                    "Port message not delivered",
                    "Port response not delivered",
                    "missing tabs.connect",
                    "unknown pending promise",
                ].contains(event.resultClassifier ?? "")
            }) else {
            return false
        }
        return firstFatal.apiName == "tabs.connect"
    }

    private func controlledBitwardenPopupAppStateBoundaryDiagnostics(
        snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot,
        domStateJSON: String
    ) -> ChromeMV3ControlledPopupAppStateBoundaryDiagnostics {
        let domObject =
            (try? JSONSerialization.jsonObject(
                with: Data(domStateJSON.utf8)
            ) as? [String: Any]) ?? [:]
        let finalDOM = ChromeMV3LivePopupDOMCheckpoint(
            readyState: domObject["readyState"] as? String ?? "unknown",
            visibleTextLengthBucket:
                ChromeMV3LivePopupProductPathTraceBuilder.textLengthBucket(
                    domObject["visibleTextLength"] as? Int ?? 0
                ),
            controlCountBucket:
                ChromeMV3LivePopupProductPathTraceBuilder.countBucket(
                    domObject["controlCount"] as? Int ?? 0
                ),
            bodyChildCount: domObject["elementCount"] as? Int ?? 0,
            appRootPresent: (domObject["appRootCount"] as? Int ?? 0) > 0,
            navigationCommitted: true,
            visibilityCategory: "unknown",
            backgroundCategory: "white"
        )
        let stagedSnapshots =
            ChromeMV3LivePopupProductPathTraceBuilder.synthesizeStagedSnapshots(
                from: snapshot.jsDebugRouteEvents,
                observedMethods: snapshot.observedMethods,
                bridgeInstalled: true,
                finalDOM: finalDOM
            )
        return ChromeMV3LivePopupProductPathTraceBuilder
            .controlledPopupAppStateBoundaryDiagnostics(
                bridgeSnapshot: snapshot,
                finalDOM: finalDOM,
                stagedSnapshots: stagedSnapshots
            )
            ?? ChromeMV3ControlledPopupAppStateBoundaryDiagnostics(
                firstStableAppStateClassifier: "notClassified",
                extensionBoundaryClassifier: "unknown",
                boundaryKind: "unknown",
                nativeMessagingRequestCategory: "none",
                nativeMessagingResultCategory: "notRequested",
                pendingRouteBucket: "0",
                serviceWorkerListenerCategory: "onMessage=0,onConnect=0",
                popupMessagingCategory: "none",
                portRouteCategory: "notObserved",
                storageCategory: "unknown",
                after3000msSnapshotLine: nil
            )
    }

    private func recordControlledBitwardenPopupSanitizedDiagnostics(
        prefix: String,
        snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot,
        domState: String,
        firstBlocker: String,
        tabsConnectFatal: Bool,
        boundaryDiagnostics:
            ChromeMV3ControlledPopupAppStateBoundaryDiagnostics? = nil,
        extraLines: [String] = []
    ) {
        let resolvedBoundary =
            boundaryDiagnostics
            ?? controlledBitwardenPopupAppStateBoundaryDiagnostics(
                snapshot: snapshot,
                domStateJSON: domState
            )
        let lines =
            [
                "reproducedControlledHost=true",
                "domState=\(domState)",
                "firstFatalBlocker=\(firstBlocker)",
                "pendingCount=\(snapshot.pendingUnresolvedJSDebugRoutes.count)",
                "routeEvents=\(snapshot.jsDebugRouteEvents.count)",
                "callRecords=\(snapshot.callRecords.count)",
                "tabsConnectActuallyFatal=\(tabsConnectFatal)",
                "nativeHostLaunched=false",
                "appStateClassification=\(snapshot.appStateDependencyTrace.correlationSummary.classification)",
                "appStateServiceWorkerState=\(snapshot.appStateDependencyTrace.correlationSummary.serviceWorkerState)",
                "appStatePopupReadsNeverWritten=\(snapshot.appStateDependencyTrace.correlationSummary.popupReadKeyHashesNeverWritten.count)",
                "appStatePopupReadsWrittenByServiceWorker=\(snapshot.appStateDependencyTrace.correlationSummary.popupReadKeyHashesWrittenByServiceWorker.count)",
                "appStateRepeatedEmptyReads=\(snapshot.appStateDependencyTrace.correlationSummary.repeatedEmptyReadKeyHashes.count)",
                "appStateServiceWorkerStorageWritesAfterConnect=\(snapshot.appStateDependencyTrace.correlationSummary.serviceWorkerStorageWritesAfterConnect)",
                "appStateStorageOnChangedReachedRegisteredListeners=\(snapshot.appStateDependencyTrace.correlationSummary.storageOnChangedReachedRegisteredListeners)",
                "appStateUsableOnboardingLoginUI=\(snapshot.appStateDependencyTrace.correlationSummary.popupReachedUsableOnboardingOrLoginUI)",
            ]
            + resolvedBoundary.logLines
            + extraLines
            + controlledBitwardenPopupSanitizedLogLines(snapshot)

        for line in lines {
            print("\(prefix) \(line)")
        }

        let attachment = XCTAttachment(
            string: lines
                .map { "\(prefix) \($0)" }
                .joined(separator: "\n")
        )
        attachment.name = "\(prefix)-sanitized-diagnostics"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func controlledBitwardenPopupManifestReturnedSequence(
        _ snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot
    ) -> Int? {
        snapshot.jsDebugRouteEvents
            .filter {
                $0.apiName == "runtime.getManifest"
                    && $0.resultClassifier == "manifestReturned"
            }
            .map(\.sequence)
            .min()
    }

    private func controlledBitwardenPopupPostGetManifestEvents(
        _ snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot
    ) -> [ChromeMV3PopupOptionsJSDebugRouteEventRecord] {
        guard let manifestSequence =
            controlledBitwardenPopupManifestReturnedSequence(snapshot)
        else {
            return snapshot.jsDebugRouteEvents
        }
        return snapshot.jsDebugRouteEvents.filter {
            $0.sequence > manifestSequence
        }
    }

    private func controlledBitwardenPopupSanitizedLogLines(
        _ snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot
    ) -> [String] {
        let eventLines = snapshot.jsDebugRouteEvents.prefix(180).map {
            event in
            [
                "seq=\(event.sequence)",
                "event=\(event.eventKind)",
                "api=\(event.apiName)",
                "target=\(event.targetContext ?? "unknown")",
                "classifier=\(event.resultClassifier ?? "none")",
                "ageMs=\(event.ageMilliseconds.map(String.init) ?? "na")",
                "shape=\(event.safeMessageShapeClassification)",
                "fields=\(event.safeCommandTypeActionFieldNames.joined(separator: ","))",
                "port=\(event.portName ?? "none")",
                "firstError=\(event.firstMissingAPIOrPermissionOrLifecycleError ?? "none")",
                "diagnostics=\(event.diagnostics.joined(separator: "|"))",
            ].joined(separator: " ")
        }
        let pendingLines = snapshot.pendingUnresolvedJSDebugRoutes.map {
            event in
            "pending api=\(event.apiName) ageMs=\(event.ageMilliseconds.map(String.init) ?? "na") classifier=\(event.resultClassifier ?? "unknown pending promise")"
        }
        let routeLines = snapshot.sanitizedBridgeRouteRecords.prefix(80).map {
            route in
            [
                "swiftRoute",
                "api=\(route.apiName)",
                "target=\(route.targetContext)",
                "classifier=\(route.resultClassifier)",
                "listeners=\(route.listenerCount)",
                "invoked=\(route.listenerInvoked)",
                "sendResponse=\(route.sendResponseCalled)",
                "port=\(route.portName ?? "none")",
                "messageCount=\(route.portMessageCount)",
                "firstError=\(route.firstMissingAPIOrPermissionOrLifecycleError ?? "none")",
                "diagnostics=\(route.diagnostics.joined(separator: "|"))",
            ].joined(separator: " ")
        }
        let appStateStorageLines =
            snapshot.appStateDependencyTrace.storageOperations.prefix(160).map {
                record in
                [
                    "appStateStorage",
                    "seq=\(record.sequence)",
                    "context=\(record.context)",
                    "area=\(record.area)",
                    "op=\(record.operation)",
                    "keyShape=\(record.keyShape)",
                    "keyCount=\(record.keyCount)",
                    "keyHashes=\(record.keyHashes.joined(separator: ","))",
                    "valueShape=\(record.valueShape)",
                    "resultShape=\(record.resultShape)",
                    "classifier=\(record.resultClassifier)",
                    "empty=\(record.emptyResult)",
                    "populated=\(record.populatedResult)",
                    "elapsedMs=\(record.elapsedMilliseconds)",
                ].joined(separator: " ")
            }
        let appStateChangeLines =
            snapshot.appStateDependencyTrace.storageChangeDispatches
            .prefix(80).map { record in
                [
                    "appStateStorageChange",
                    "seq=\(record.sequence)",
                    "area=\(record.area)",
                    "changedKeyCount=\(record.changedKeyCount)",
                    "changedKeyHashes=\(record.changedKeyHashes.joined(separator: ","))",
                    "listenerCounts=\(record.listenerCountByContext.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ","))",
                    "listenerReceived=\(record.listenerReceivedByContext.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ","))",
                    "dispatched=\(record.dispatched)",
                    "elapsedMs=\(record.elapsedMilliseconds)",
                ].joined(separator: " ")
            }
        let appStatePortLines =
            snapshot.appStateDependencyTrace.portLifecycle.prefix(120).map {
                record in
                [
                    "appStatePort",
                    "seq=\(record.sequence)",
                    "event=\(record.eventKind)",
                    "api=\(record.apiName)",
                    "source=\(record.sourceContext)",
                    "target=\(record.targetContext)",
                    "direction=\(record.direction)",
                    "listenerCount=\(record.listenerCount)",
                    "postMessageCount=\(record.postMessageCount)",
                    "messageShape=\(record.messageShape)",
                    "classifier=\(record.responseClassifier)",
                    "ageMs=\(record.ageMilliseconds.map(String.init) ?? "na")",
                ].joined(separator: " ")
            }
        let appStateDOMLines =
            snapshot.appStateDependencyTrace.domCheckpoints.prefix(20).map {
                record in
                [
                    "appStateDOM",
                    "seq=\(record.sequence)",
                    "phase=\(record.phase)",
                    "readyState=\(record.readyState)",
                    "controls=\(record.controlsCount)",
                    "visibleTextLength=\(record.visibleTextLength)",
                    "rootApp=\(record.rootAppElementExists)",
                    "coarse=\(record.coarseStatus)",
                    "pending=\(record.pendingRouteCount)",
                ].joined(separator: " ")
            }
        return pendingLines + eventLines + routeLines
            + appStateStorageLines + appStateChangeLines
            + appStatePortLines + appStateDOMLines
    }

    @available(macOS 15.5, *)
    @MainActor
    private func waitForNativeBitwardenPopupPreludeSnapshot(
        manager: ExtensionManager,
        extensionID: String,
        initialSnapshot: ChromeMV3NativeActionPopupBoundarySnapshot?
    ) async throws -> ChromeMV3NativeActionPopupBoundarySnapshot {
        var latest = try XCTUnwrap(initialSnapshot)
        for _ in 0..<80 {
            if let current = manager.nativeActionPopupBoundarySnapshot(
                for: extensionID
            ) {
                latest = current
            }
            if latest.routeObservations.contains(where: {
                $0.nativeBoundary == "WKUserScript.pageWorld"
                    && $0.apiName != "nativeActionPopupPrelude"
            }) {
                return latest
            }
            if latest.nativePopupPreludeAttachedAtDocumentStart,
               latest.routeObservations.contains(where: {
                   $0.apiName == "nativeActionPopupPrelude"
               })
            {
                return latest
            }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        return latest
    }

    @available(macOS 15.5, *)
    private func nativeBitwardenPopupNoCaptureReason(
        _ snapshot: ChromeMV3NativeActionPopupBoundarySnapshot
    ) -> String {
        if snapshot.nativePopupPreludeConfiguredBeforePopupCreation == false {
            return "preludeDidNotInstallBeforeExtensionManagerCreation"
        }
        if snapshot.routeObservations.contains(where: {
            $0.nativeBoundary == "WKUserScript.pageWorld"
                && $0.apiName != "nativeActionPopupPrelude"
        }) {
            return "captured"
        }
        if snapshot.nativePopupPreludeAttachedAtDocumentStart == false {
            if let firstMissing =
                snapshot.nativePopupPreludeFirstMissingAPIOrError
            {
                switch firstMissing {
                case "chromeMissing":
                    return "webkitPageWorldDidNotExposeChromeObjectToPrelude"
                case "browserMissing":
                    return "webkitPageWorldDidNotExposeBrowserObjectToPrelude"
                case "runtimeMissing":
                    return "webkitPageWorldDidNotExposeRuntimeOrTabsToPrelude"
                default:
                    return "preludeInstalledButReported\(firstMissing)"
                }
            }
            return "preludeDidNotAttachBeforePopupJSExecution"
        }
        if snapshot.popupWebViewAvailableAtPresentation == false {
            return "realWebKitNativePopupWebViewUnavailableAtPresentation"
        }
        return "bitwardenPopupEmittedNoObservablePreludeAPICalls"
    }

    @available(macOS 15.5, *)
    private func nativeBitwardenPopupFirstBlocker(
        _ snapshot: ChromeMV3NativeActionPopupBoundarySnapshot
    ) -> String {
        if let route = snapshot.routeObservations.first(where: {
            $0.resultClassifier == "threw"
                || $0.resultClassifier == "apiMissing"
                || $0.resultClassifier == "ownerMissing"
                || $0.resultClassifier == "namespaceMissing"
                || $0.resultClassifier == "notFunction"
                || $0.firstMissingAPIOrError != nil
        }) {
            if let missingOrError = route.firstMissingAPIOrError {
                return "\(route.apiName):\(missingOrError)"
            }
            if let result = route.resultClassifier {
                return "\(route.apiName):\(result)"
            }
            return route.apiName
        }
        if snapshot.routeObservations.contains(where: {
            $0.apiName == "chrome.tabs.query"
                || $0.apiName == "browser.tabs.query"
                || $0.apiName == "chrome.tabs.sendMessage"
                || $0.apiName == "browser.tabs.sendMessage"
        }) {
            return "tabsMessagingOrTabMetadata"
        }
        if snapshot.routeObservations.contains(where: {
            $0.apiName == "chrome.runtime.connect"
                || $0.apiName == "browser.runtime.connect"
                || $0.apiName == "chrome.Port.postMessage"
                || $0.apiName == "browser.Port.postMessage"
        }) {
            return "PortSemantics"
        }
        return nativeBitwardenPopupNoCaptureReason(snapshot)
    }

    private func bitwardenNativeHostRunningApplicationIdentifiers() -> [String] {
        NSWorkspace.shared.runningApplications
            .compactMap(\.bundleIdentifier)
            .filter { $0 == "com.bitwarden.desktop" }
            .sorted()
    }

    @MainActor
    private func assertNoRuntimeSideEffects(
        _ result: ChromeMV3ExtensionManagerActionResult,
        module: SumiExtensionsModule,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(result.runtimeAttachmentAttempted, file: file, line: line)
        XCTAssertFalse(result.runtimeObjectsCreated, file: file, line: line)
        XCTAssertFalse(result.serviceWorkerWakeAttempted, file: file, line: line)
        XCTAssertFalse(result.nativeHostLaunchAttempted, file: file, line: line)
        XCTAssertFalse(module.hasLoadedRuntime, file: file, line: line)
        XCTAssertFalse(result.productFlags.runtimeLoadable, file: file, line: line)
        XCTAssertFalse(
            result.productFlags.productRuntimeAvailable,
            file: file,
            line: line
        )
        XCTAssertFalse(
            result.productFlags.normalTabRuntimeBridgeAvailable,
            file: file,
            line: line
        )
        XCTAssertFalse(
            result.productFlags.productNetworkEnforcementAvailable,
            file: file,
            line: line
        )
        XCTAssertFalse(
            result.productFlags.productRuntimeExposed,
            file: file,
            line: line
        )
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

@MainActor
private struct InstalledURLHubFixture {
    var root: URL
    var module: SumiExtensionsModule
    var record: ChromeMV3ExtensionLifecycleRecord
}

#if canImport(WebKit)
@MainActor
private final class ChromeMV3URLHubMaterializedTabNavigationObserver:
    NSObject,
    WKNavigationDelegate
{
    private var continuation: CheckedContinuation<Void, Error>?

    func wait(navigation: WKNavigation?) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            if navigation == nil {
                continuation.resume()
                self.continuation = nil
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        continuation?.resume()
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
#endif

@MainActor
private struct ChromeMV3URLHubLiveTabModuleFixture {
    let defaultsHarness: TestDefaultsHarness
    let container: ModelContainer
    let browserConfiguration: BrowserConfiguration
    let module: SumiExtensionsModule
    let browserManager: BrowserManager
    let profile: Profile

    func makeTab(
        url: URL = URL(string: "https://example.com/article")!
    ) -> Tab {
        let tab = Tab(
            url: url,
            name: url.host ?? "URL Hub Materialized Tab",
            favicon: "globe",
            index: 0,
            browserManager: browserManager
        )
        tab.profileId = profile.id
        return tab
    }

    func tearDown() {
        _ = module.tearDownChromeMV3EmptyControllerOwnerIfEnabled(
            trigger: .explicitReset
        )
        module.setEnabled(false)
        defaultsHarness.reset()
    }
}

@MainActor
private final class FakeURLHubPopupOptionsWebViewFactory:
    ChromeMV3PopupOptionsWebViewFactory
{
    var createCount = 0
    var teardownCount = 0
    var loadedFileURLs: [URL] = []
    var readAccessURLs: [URL] = []
    var lastBridgeInstallation:
        ChromeMV3PopupOptionsJSBridgeInstallation?

    func createWebView(
        loadFileURL: URL,
        allowingReadAccessTo readAccessURL: URL
    ) throws -> ChromeMV3PopupOptionsWebViewHandle {
        createCount += 1
        loadedFileURLs.append(loadFileURL)
        readAccessURLs.append(readAccessURL)
        return FakeURLHubPopupOptionsWebViewHandle { [weak self] in
            self?.teardownCount += 1
        }
    }

    func createWebView(
        loadFileURL: URL,
        allowingReadAccessTo readAccessURL: URL,
        bridgeInstallation:
            ChromeMV3PopupOptionsJSBridgeInstallation,
        permissionPromptPresenter:
            ChromeMV3PermissionPromptPresenting?,
        permissionEventDispatcher:
            ChromeMV3PermissionEventDispatching?
    ) throws -> ChromeMV3PopupOptionsWebViewHandle {
        lastBridgeInstallation = bridgeInstallation
        _ = permissionPromptPresenter
        _ = permissionEventDispatcher
        return try createWebView(
            loadFileURL: loadFileURL,
            allowingReadAccessTo: readAccessURL
        )
    }
}

@MainActor
private final class FakeURLHubPopupOptionsWebViewHandle:
    ChromeMV3PopupOptionsWebViewHandle
{
    private let onTearDown: () -> Void
    private var didTearDown = false

    init(onTearDown: @escaping () -> Void) {
        self.onTearDown = onTearDown
    }

    func tearDown() {
        guard didTearDown == false else { return }
        didTearDown = true
        onTearDown()
    }
}
