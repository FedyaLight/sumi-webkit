import AppKit
import Foundation
import SwiftData
import XCTest

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
    func testControlledCompatibilityPopupGateOpensGeneratedActionPopupWithoutNativeRuntime()
        async throws
    {
        UserDefaults.standard.removeObject(
            forKey: ExtensionManager
                .controlledCompatibilityActionPopupDefaultsKey
        )
        XCTAssertFalse(
            RuntimeDiagnostics.debugDefaultBool(
                forKey: ExtensionManager
                    .controlledCompatibilityActionPopupDefaultsKey
            )
        )
        UserDefaults.standard.set(
            true,
            forKey: ExtensionManager
                .controlledCompatibilityActionPopupDefaultsKey
        )
        defer {
            UserDefaults.standard.removeObject(
                forKey: ExtensionManager
                    .controlledCompatibilityActionPopupDefaultsKey
            )
        }

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
        defer {
            UserDefaults.standard.removeObject(
                forKey: ExtensionManager
                    .nativeActionPopupBoundaryObservationDefaultsKey
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
        defer {
            UserDefaults.standard.removeObject(
                forKey: ExtensionManager
                    .nativeActionPopupBoundaryObservationDefaultsKey
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
        UserDefaults.standard.set(
            true,
            forKey: ExtensionManager
                .controlledCompatibilityActionPopupDefaultsKey
        )
        defer {
            UserDefaults.standard.removeObject(
                forKey: ExtensionManager
                    .controlledCompatibilityActionPopupDefaultsKey
            )
        }
        XCTAssertTrue(
            RuntimeDiagnostics.debugDefaultBool(
                forKey: ExtensionManager
                    .controlledCompatibilityActionPopupDefaultsKey
            )
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
            bitwardenNativeHostRunningApplicationIdentifiers(),
            nativeHostWasRunning,
            "The controlled Bitwarden popup diagnostics must not launch com.bitwarden.desktop."
        )

        recordControlledBitwardenPopupSanitizedDiagnostics(
            prefix: "SumiControlledBitwardenPopup",
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
        UserDefaults.standard.set(
            true,
            forKey: ExtensionManager
                .controlledCompatibilityActionPopupDefaultsKey
        )
        defer {
            UserDefaults.standard.removeObject(
                forKey: ExtensionManager
                    .controlledCompatibilityActionPopupDefaultsKey
            )
        }
        XCTAssertTrue(
            RuntimeDiagnostics.debugDefaultBool(
                forKey: ExtensionManager
                    .controlledCompatibilityActionPopupDefaultsKey
            )
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
    func testURLHubActionClickReportsSelectedPackageContextLoadFailurePrecisely()
        async throws
    {
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
                "controlledCompatibilityActionPopupDefaultsKey"
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
            "remoteResources=\((launchRecord.resourceResolution?.remoteResourceReferences ?? []).joined(separator: ","))",
            "linkedResourceKinds=\(linkedKinds)",
        ].joined(separator: " ")
    }

    @MainActor
    private func waitForControlledBitwardenPopupBridgeSnapshot(
        module: SumiExtensionsModule,
        profileID: String,
        extensionID: String
    ) async throws -> ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot {
        var latest:
            ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot?
        for _ in 0..<200 {
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
                if manifestReturned
                    && (finalCheckpointReached || hasPostManifestBlocker) {
                    return snapshot
                }
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
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
          const hasBusyIndicator = !!document.querySelector(
            '[role="progressbar"],[aria-busy="true"],.spinner,.loading,.loader,[data-loading="true"]'
          );
          const hasLoadingText =
            /\\b(loading|please wait|initializing|syncing)\\b/i.test(text);
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
          } else if (hasBusyIndicator || hasLoadingText) {
            coarseClassification = 'spinner/loading';
          }
          return JSON.stringify({
            readyState: document.readyState,
            hasLoadingText,
            hasBusyIndicator,
            inputCount,
            buttonCount,
            linkCount,
            controlCount,
            elementCount,
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

    private func recordControlledBitwardenPopupSanitizedDiagnostics(
        prefix: String,
        snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot,
        domState: String,
        firstBlocker: String,
        tabsConnectFatal: Bool,
        extraLines: [String] = []
    ) {
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
            ]
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
        let eventLines = snapshot.jsDebugRouteEvents.prefix(80).map {
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
        let routeLines = snapshot.sanitizedBridgeRouteRecords.prefix(40).map {
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
        return pendingLines + eventLines + routeLines
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
