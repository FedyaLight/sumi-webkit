import Foundation
import XCTest

@testable import Sumi

final class ChromeMV3ExtensionManagerDeveloperPreviewTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_720_000_000)
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    @MainActor
    func testDeveloperPreviewManagerGateIsInternalOnly() throws {
        let module = try makeModule(enabled: true)
        let gate = module.chromeMV3ExtensionManagerGate()

        #if DEBUG
            XCTAssertTrue(gate.managerAvailableInDeveloperPreview)
            XCTAssertTrue(gate.installActionsAvailable)
        #else
            XCTAssertFalse(gate.managerAvailableInDeveloperPreview)
            XCTAssertFalse(gate.installActionsAvailable)
        #endif
        XCTAssertTrue(gate.developerPreviewOnly)
        XCTAssertFalse(gate.managerAvailableInPublicProduct)
        XCTAssertFalse(gate.runtimeActionsAvailable)
        XCTAssertFalse(gate.webStoreInstallAvailable)
        #if DEBUG
            XCTAssertTrue(gate.localArchiveImportAvailable)
        #else
            XCTAssertFalse(gate.localArchiveImportAvailable)
        #endif
        XCTAssertTrue(gate.diagnostics.contains {
            $0.code == .runtimeActionsUnavailable
        })
        XCTAssertTrue(gate.diagnostics.contains {
            $0.code == .chromeWebStoreInstallDeferred
        })
        XCTAssertTrue(gate.diagnostics.contains {
            $0.code == .crxImportDeferred
        })
    }

    @MainActor
    func testDisabledModuleBlocksManagerViewModelsAndActionsWithoutArtifacts()
        throws
    {
        let root = try makeTemporaryDirectory()
        let source = try makeFixture(
            named: "disabled-manager",
            manifest: minimalManifest(version: "1.0.0"),
            files: ["background.js": ""]
        )
        let module = try makeModule(enabled: false)

        XCTAssertNil(
            module.chromeMV3ExtensionManagerListViewModelIfEnabled(
                rootURL: root
            )
        )
        XCTAssertNil(
            module.chromeMV3ExtensionManagerDetailViewModelIfEnabled(
                rootURL: root,
                profileID: "profile-disabled",
                extensionID: "extension-disabled"
            )
        )

        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: source,
            profileID: "profile-disabled"
        )
        let archive = module.chromeMV3ImportLocalArchiveThroughManager(
            sourceURL: root.appendingPathComponent("fixture.zip")
        )
        let webStore = module
            .chromeMV3ChromeWebStoreInstallDiagnosticThroughManager()

        XCTAssertEqual(install.status, .blocked)
        XCTAssertEqual(archive.status, .blocked)
        XCTAssertEqual(webStore.status, .blocked)
        XCTAssertTrue(install.blockedDiagnostics.contains {
            $0.code == .moduleDisabled
        })
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
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    @MainActor
    func testInstallUnpackedListsDetailAndCompatibilityPreflight()
        throws
    {
        let root = try makeTemporaryDirectory()
        let source = try makeFixture(
            named: "manager-install",
            manifest: blockerHeavyManifest(),
            files: [
                "background.js": "",
                "content.js": "",
                "panel.html": "<!doctype html><title>Panel</title>\n",
                "rules.json": "[]",
            ]
        )
        let module = try makeModule(enabled: true)

        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: source,
            profileID: "profile-manager",
            enableInternal: false
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)
        let list = try XCTUnwrap(
            module.chromeMV3ExtensionManagerListViewModelIfEnabled(
                rootURL: root,
                now: fixedDate
            )
        )
        let detail = try XCTUnwrap(
            module.chromeMV3ExtensionManagerDetailViewModelIfEnabled(
                rootURL: root,
                profileID: record.profileID,
                extensionID: record.extensionID
            )
        )

        XCTAssertTrue(install.succeeded)
        XCTAssertEqual(install.action, .installUnpacked)
        assertNoRuntimeSideEffects(install, module: module)
        XCTAssertEqual(list.items.count, 1)
        XCTAssertEqual(list.items.first?.extensionID, record.extensionID)
        XCTAssertEqual(list.items.first?.name, "Manager Blocker Heavy")
        XCTAssertEqual(list.items.first?.internalEnabled, false)
        XCTAssertEqual(
            list.items.first?.generatedBundleSummary.runtimeLoadable,
            false
        )
        XCTAssertNotNil(list.items.first?.lastDiagnosticsGeneratedAt)

        XCTAssertEqual(detail.manifestSummary.manifestVersion, 3)
        XCTAssertEqual(detail.manifestSummary.name, "Manager Blocker Heavy")
        XCTAssertTrue(
            detail.permissionStatePanel.requiredPermissions
                .contains("storage")
        )
        XCTAssertTrue(
            detail.permissionStatePanel.hostPermissions
                .contains("https://example.com/*")
        )
        XCTAssertFalse(detail.permissionStatePanel.promptGate.silentGrantAllowed)
        XCTAssertFalse(
            detail.permissionStatePanel.promptGate
                .permissionPromptAvailableInPublicProduct
        )
        XCTAssertEqual(detail.lifecycleRecord.lifecycleState, .diagnosticsReady)
        XCTAssertTrue(detail.generatedBundleState.generatedBundleAvailable)
        XCTAssertFalse(
            detail.productEnablementPreflight.normalTabPreflight
                .canAttachToNormalTabNow
        )
        XCTAssertFalse(
            detail.productEnablementPreflight.normalTabPreflight
                .canExposeRuntimeBridgeNow
        )
        XCTAssertTrue(detail.apiSupportMatrix.contains {
            $0.apiNamespace == ChromeMV3API.webRequest.rawValue
                && $0.productBlocked
        })
        XCTAssertTrue(detail.blockersBySeverity.contains {
            $0.blockers.contains { $0.severity == .productBlocked }
        })
        XCTAssertTrue(detail.exactCompatibilityBlockers.contains {
            $0.apiNamespace == ChromeMV3API.nativeMessaging.rawValue
        })
        XCTAssertFalse(detail.exactProductPreflightBlockers.isEmpty)
        XCTAssertTrue(detail.diagnosticsJSONAvailable)
        XCTAssertTrue(detail.actions.contains {
            $0.action == .enableInternal && $0.available
        })
        XCTAssertTrue(detail.actions.contains {
            $0.action == .chromeWebStoreInstall && !$0.available
                && $0.unavailableDiagnostics.contains {
                    $0.code == .chromeWebStoreInstallDeferred
                }
        })
        XCTAssertTrue(detail.actions.contains {
            $0.action == .importZipArchive && $0.available
        })
    }

    @MainActor
    func testTrustedNativeHostPanelApproveAndRevokeControls()
        throws
    {
        let root = try makeTemporaryDirectory()
        let source = try makeFixture(
            named: "trusted-native-host-manager",
            manifest: blockerHeavyManifest(),
            files: [
                "background.js": "",
                "content.js": "",
                "panel.html": "<!doctype html><title>Panel</title>\n",
                "rules.json": "[]",
            ]
        )
        let module = try makeModule(enabled: true)
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: source,
            profileID: "profile-trusted-native-host",
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)
        let hostName = ChromeMV3NativeMessagingFixtureHostBuilder
            .passwordManagerFixtureHostName
        let fixtureRoot = root.appendingPathComponent(
            "NativeMessagingFixtureHosts",
            isDirectory: true
        )
        _ = try ChromeMV3NativeMessagingFixtureHostBuilder.writeFixtureHost(
            kind: .echo,
            rootURL: fixtureRoot,
            hostName: hostName,
            extensionID: record.extensionID
        )
        let detailBefore = try XCTUnwrap(
            module.chromeMV3ExtensionManagerDetailViewModelIfEnabled(
                rootURL: root,
                profileID: record.profileID,
                extensionID: record.extensionID
            )
        )
        let before = try XCTUnwrap(
            detailBefore.trustedNativeHostPanel.hostRequirements.first
        )

        XCTAssertTrue(
            detailBefore.trustedNativeHostPanel
                .nativeMessagingPermissionDeclared
        )
        XCTAssertTrue(
            detailBefore.trustedNativeHostPanel
                .nativeMessagingPermissionGranted
        )
        XCTAssertFalse(
            detailBefore.trustedNativeHostPanel.arbitraryHostLaunchAllowed
        )
        XCTAssertFalse(detailBefore.trustedNativeHostPanel.nativeHostScanningAllowed)
        XCTAssertEqual(before.manifestStatus, .found)
        XCTAssertEqual(before.trustedHostState, .unknown)
        XCTAssertFalse(before.trustedForDeveloperPreview)
        XCTAssertTrue(before.controls.contains {
            $0.kind == .approveForDeveloperPreview && $0.available
        })

        let approve = module.chromeMV3RunTrustedNativeHostControlThroughManager(
            .approveForDeveloperPreview,
            rootURL: root,
            profileID: record.profileID,
            extensionID: record.extensionID,
            hostName: hostName
        )
        let detailApproved = try XCTUnwrap(
            module.chromeMV3ExtensionManagerDetailViewModelIfEnabled(
                rootURL: root,
                profileID: record.profileID,
                extensionID: record.extensionID
            )
        )
        let approved = try XCTUnwrap(
            detailApproved.trustedNativeHostPanel.hostRequirements.first
        )

        XCTAssertTrue(approve.succeeded, approve.diagnostics.joined(separator: "\n"))
        XCTAssertEqual(
            approve.record?.trustState,
            .trustedForDeveloperPreview
        )
        XCTAssertEqual(approve.record?.userConsentGranted, true)
        XCTAssertTrue(approve.preflight?.canConnectNativeNow == true)
        XCTAssertFalse(approve.serviceWorkerWakeAttempted)
        XCTAssertFalse(approve.nativeHostLaunchAttempted)
        XCTAssertEqual(
            approved.trustedHostState,
            .trustedForDeveloperPreview
        )
        XCTAssertTrue(approved.trustedForDeveloperPreview)
        XCTAssertTrue(approved.processLaunchAllowedNow)
        XCTAssertTrue(approved.controls.contains {
            $0.kind == .revoke && $0.available
        })

        let revoke = module.chromeMV3RunTrustedNativeHostControlThroughManager(
            .revoke,
            rootURL: root,
            profileID: record.profileID,
            extensionID: record.extensionID,
            hostName: hostName
        )
        let detailRevoked = try XCTUnwrap(
            module.chromeMV3ExtensionManagerDetailViewModelIfEnabled(
                rootURL: root,
                profileID: record.profileID,
                extensionID: record.extensionID
            )
        )
        let revoked = try XCTUnwrap(
            detailRevoked.trustedNativeHostPanel.hostRequirements.first
        )

        XCTAssertTrue(revoke.succeeded, revoke.diagnostics.joined(separator: "\n"))
        XCTAssertEqual(revoke.record?.trustState, .revoked)
        XCTAssertFalse(revoke.preflight?.canConnectNativeNow == true)
        XCTAssertFalse(revoke.serviceWorkerWakeAttempted)
        XCTAssertFalse(revoke.nativeHostLaunchAttempted)
        XCTAssertEqual(revoked.trustedHostState, .revoked)
        XCTAssertFalse(revoked.trustedForDeveloperPreview)
        XCTAssertFalse(revoked.processLaunchAllowedNow)
    }

    @MainActor
    func testInstallRejectsMV2AndSafariPackagesThroughManager() throws {
        let root = try makeTemporaryDirectory()
        let module = try makeModule(enabled: true)
        let mv2 = try makeFixture(
            named: "legacy-mv2",
            manifest: [
                "manifest_version": 2,
                "name": "Legacy MV2",
                "version": "1.0",
            ],
            files: [:]
        )
        let appURL = try makeTemporaryDirectory()
            .appendingPathComponent("Legacy.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: appURL,
            withIntermediateDirectories: true
        )
        let appexURL = try makeTemporaryDirectory()
            .appendingPathComponent("Legacy.appex", isDirectory: true)
        try FileManager.default.createDirectory(
            at: appexURL,
            withIntermediateDirectories: true
        )

        let mv2Result = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: mv2,
            profileID: "profile-reject"
        )
        let appResult = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: appURL,
            profileID: "profile-reject"
        )
        let appexResult = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: appexURL,
            profileID: "profile-reject"
        )

        XCTAssertFalse(mv2Result.succeeded)
        XCTAssertEqual(
            mv2Result.lifecycleOperationResult?.failureCode,
            .manifestInvalid
        )
        XCTAssertFalse(appResult.succeeded)
        XCTAssertEqual(
            appResult.lifecycleOperationResult?.failureCode,
            .manifestInvalid
        )
        XCTAssertTrue(appResult.report?.blockerTaxonomy.contains {
            $0.message.contains(".app/.appex")
        } == true)
        XCTAssertFalse(appexResult.succeeded)
        XCTAssertEqual(
            appexResult.lifecycleOperationResult?.failureCode,
            .manifestInvalid
        )
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    @MainActor
    func testArchiveAndChromeWebStoreFlowsReturnDeterministicDeferredDiagnostics()
        throws
    {
        let root = try makeTemporaryDirectory()
        let module = try makeModule(enabled: true)

        let zip = module.chromeMV3ImportLocalArchiveThroughManager(
            rootURL: root,
            sourceURL: root.appendingPathComponent("local.zip")
        )
        let crx = module.chromeMV3ImportLocalArchiveThroughManager(
            rootURL: root,
            sourceURL: root.appendingPathComponent("local.crx")
        )
        let webStore = module
            .chromeMV3ChromeWebStoreInstallDiagnosticThroughManager(rootURL: root)

        XCTAssertEqual(zip.status, .failed)
        XCTAssertEqual(zip.action, .importZipArchive)
        XCTAssertEqual(zip.packageIntakeReport?.sourceKind, .localZip)
        XCTAssertEqual(zip.packageIntakeReport?.preflightResult.status, .failed)

        XCTAssertEqual(crx.status, .blocked)
        XCTAssertEqual(crx.action, .importCRXArchive)
        XCTAssertEqual(crx.packageIntakeReport?.sourceKind, .localCrx)
        XCTAssertTrue(crx.packageIntakeReport?.trustResult.importAllowed == false)

        XCTAssertEqual(webStore.status, .deferred)
        XCTAssertEqual(webStore.action, .chromeWebStoreInstall)
        XCTAssertTrue(webStore.blockedDiagnostics.contains {
            $0.code == .chromeWebStoreInstallNotSupportedInThisBuild
        })
        XCTAssertTrue(webStore.blockedDiagnostics.contains {
            $0.code == .chromeWebStoreInterceptionForbidden
        })
        XCTAssertTrue(webStore.blockedDiagnostics.contains {
            $0.code == .remoteCRXDownloadForbidden
        })
        XCTAssertTrue(webStore.blockedDiagnostics.contains {
            $0.code == .webStorePageInjectionForbidden
        })
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    @MainActor
    func testEnableDisableOnlyTogglesInternalRegistryState() throws {
        let fixture = try installMinimalFixture(
            named: "enable-disable",
            profileID: "profile-toggle",
            enableInternal: false
        )
        let module = fixture.module

        let enable = module.chromeMV3SetInternalExtensionEnabledThroughManager(
            true,
            rootURL: fixture.root,
            profileID: fixture.record.profileID,
            extensionID: fixture.record.extensionID
        )
        let enabledRecord = try XCTUnwrap(
            enable.lifecycleOperationResult?.record
        )
        let disable = module.chromeMV3SetInternalExtensionEnabledThroughManager(
            false,
            rootURL: fixture.root,
            profileID: fixture.record.profileID,
            extensionID: fixture.record.extensionID
        )
        let disabledRecord = try XCTUnwrap(
            disable.lifecycleOperationResult?.record
        )

        XCTAssertTrue(enable.succeeded)
        XCTAssertEqual(enabledRecord.lifecycleState, .enabledInternal)
        XCTAssertTrue(enabledRecord.runtimeState.internalRuntimeEnabled)
        assertNoRuntimeSideEffects(enable, module: module)

        XCTAssertTrue(disable.succeeded)
        XCTAssertEqual(disabledRecord.lifecycleState, .disabledInternal)
        XCTAssertFalse(disabledRecord.runtimeState.internalRuntimeEnabled)
        XCTAssertFalse(disabledRecord.runtimeState.sharedLifecycleSessionActive)
        XCTAssertFalse(disabledRecord.runtimeState.nativeFixturePortOpen)
        assertNoRuntimeSideEffects(disable, module: module)
    }

    @MainActor
    func testDisabledModuleBlocksPermissionControlsWithoutPresenterOrState()
        throws
    {
        let root = try makeTemporaryDirectory()
        let module = try makeModule(enabled: false)
        let presenter = ChromeMV3TestPermissionPromptPresenter(
            disposition: .accepted
        )

        let result = module.chromeMV3RunPermissionControlThroughManager(
            .requestOptionalAPIPermission,
            rootURL: root,
            profileID: "profile-disabled-permission",
            extensionID: "extension-disabled-permission",
            value: "history",
            permissionPromptPresenter: presenter
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(presenter.presentedRequests.count, 0)
        XCTAssertFalse(result.serviceWorkerWakeAttempted)
        XCTAssertFalse(result.hiddenExtensionPageCreated)
        XCTAssertFalse(module.hasLoadedRuntime)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath:
                    root
                    .appendingPathComponent("lifecycle", isDirectory: true)
                    .appendingPathComponent("permission-state", isDirectory: true)
                    .path
            )
        )
    }

    @MainActor
    func testDisabledExtensionBlocksPermissionControlPromptPresentation()
        throws
    {
        let root = try makeTemporaryDirectory()
        let source = try makeFixture(
            named: "disabled-permission-control",
            manifest: optionalPermissionManifest(),
            files: ["background.js": ""]
        )
        let module = try makeModule(enabled: true)
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: source,
            profileID: "profile-disabled-extension",
            enableInternal: false
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)
        let presenter = ChromeMV3TestPermissionPromptPresenter(
            disposition: .accepted
        )

        let result = module.chromeMV3RunPermissionControlThroughManager(
            .requestOptionalAPIPermission,
            rootURL: root,
            profileID: record.profileID,
            extensionID: record.extensionID,
            value: "history",
            permissionPromptPresenter: presenter
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(presenter.presentedRequests.count, 0)
        XCTAssertNil(result.promptRequest)
        XCTAssertNil(result.promptResult)
        XCTAssertFalse(result.serviceWorkerWakeAttempted)
        XCTAssertFalse(result.hiddenExtensionPageCreated)
    }

    @MainActor
    func testManagerPermissionControlsRequestAndRevokeOptionalAccess()
        throws
    {
        let fixture = try installOptionalPermissionFixture(
            named: "permission-controls",
            profileID: "profile-permission-controls"
        )
        let module = fixture.module
        module.chromeMV3RegisterPermissionEventPageForTesting(
            surfaceID: "profile-permission-controls:\(fixture.record.extensionID):options",
            profileID: fixture.record.profileID,
            extensionID: fixture.record.extensionID,
            surface: .optionsPage,
            onAddedListenerCount: 1,
            onRemovedListenerCount: 1
        )
        let detail = try XCTUnwrap(
            module.chromeMV3ExtensionManagerDetailViewModelIfEnabled(
                rootURL: fixture.root,
                profileID: fixture.record.profileID,
                extensionID: fixture.record.extensionID
            )
        )
        XCTAssertTrue(detail.permissionStatePanel.controls.contains {
            $0.kind == .requestOptionalAPIPermission
                && $0.value == "history"
                && $0.available
        })
        XCTAssertTrue(detail.permissionStatePanel.controls.contains {
            $0.kind == .requestOptionalHostPermission
                && $0.value == "https://example.com/*"
                && $0.available
        })

        let presenter = ChromeMV3TestPermissionPromptPresenter(
            disposition: .accepted
        )
        let requestAPI = module.chromeMV3RunPermissionControlThroughManager(
            .requestOptionalAPIPermission,
            rootURL: fixture.root,
            profileID: fixture.record.profileID,
            extensionID: fixture.record.extensionID,
            value: "history",
            permissionPromptPresenter: presenter
        )
        let requestHost = module.chromeMV3RunPermissionControlThroughManager(
            .requestOptionalHostPermission,
            rootURL: fixture.root,
            profileID: fixture.record.profileID,
            extensionID: fixture.record.extensionID,
            value: "https://example.com/*",
            permissionPromptPresenter: presenter
        )
        let store = ChromeMV3DeveloperPreviewPermissionStateStore(
            rootURL: fixture.root
        )
        let grantedRecord = try XCTUnwrap(store.loadRecord(
            profileID: fixture.record.profileID,
            extensionID: fixture.record.extensionID
        ))

        XCTAssertTrue(requestAPI.succeeded)
        XCTAssertTrue(requestHost.succeeded)
        XCTAssertEqual(presenter.presentedRequests.count, 2)
        XCTAssertEqual(requestAPI.promptResult?.disposition, .accepted)
        XCTAssertEqual(requestAPI.eventDispatchRecord?.outcome, .delivered)
        XCTAssertEqual(requestAPI.eventDispatchRecord?.eventPayload.eventKind, .onAdded)
        XCTAssertEqual(requestAPI.serviceWorkerWakeAttempted, false)
        XCTAssertEqual(requestAPI.hiddenExtensionPageCreated, false)
        XCTAssertTrue(
            grantedRecord.permissionRuntimeSnapshot.permissionStore.summary
                .grantedOptionalAPIPermissions.contains("history")
        )
        XCTAssertTrue(
            grantedRecord.permissionRuntimeSnapshot.permissionStore.summary
                .grantedOptionalHostPermissions
                .contains("https://example.com/*")
        )
        let bridgeAfterGrant = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: popupOptionsConfiguration(for: fixture)
        )
        let containsAfterGrant = bridgeAfterGrant.handle(runtimeRequest(
            namespace: "permissions",
            methodName: "contains",
            arguments: [.object([
                "permissions": .array([.string("history")]),
                "origins": .array([.string("https://example.com/*")]),
            ])]
        ))
        let getAllAfterGrant = bridgeAfterGrant.handle(runtimeRequest(
            namespace: "permissions",
            methodName: "getAll"
        ))
        XCTAssertEqual(boolValue(containsAfterGrant.resultPayload), true)
        XCTAssertTrue(
            stringArrayValue(objectValue(getAllAfterGrant.resultPayload)?["permissions"])
                .contains("history")
        )
        XCTAssertTrue(
            stringArrayValue(objectValue(getAllAfterGrant.resultPayload)?["origins"])
                .contains { $0.contains("example.com") }
        )

        let revokeAPI = module.chromeMV3RunPermissionControlThroughManager(
            .revokeOptionalAPIPermission,
            rootURL: fixture.root,
            profileID: fixture.record.profileID,
            extensionID: fixture.record.extensionID,
            value: "history"
        )
        let revokeHost = module.chromeMV3RunPermissionControlThroughManager(
            .revokeOptionalHostPermission,
            rootURL: fixture.root,
            profileID: fixture.record.profileID,
            extensionID: fixture.record.extensionID,
            value: "https://example.com/*"
        )
        let revokedRecord = try XCTUnwrap(store.loadRecord(
            profileID: fixture.record.profileID,
            extensionID: fixture.record.extensionID
        ))

        XCTAssertTrue(revokeAPI.succeeded)
        XCTAssertTrue(revokeHost.succeeded)
        XCTAssertEqual(revokeAPI.eventDispatchRecord?.outcome, .delivered)
        XCTAssertEqual(revokeAPI.eventDispatchRecord?.eventPayload.eventKind, .onRemoved)
        XCTAssertFalse(
            revokedRecord.permissionRuntimeSnapshot.permissionStore.summary
                .grantedOptionalAPIPermissions.contains("history")
        )
        XCTAssertFalse(
            revokedRecord.permissionRuntimeSnapshot.permissionStore.summary
                .grantedOptionalHostPermissions
                .contains("https://example.com/*")
        )
        let bridgeAfterRevoke = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: popupOptionsConfiguration(for: fixture)
        )
        let containsAfterRevoke = bridgeAfterRevoke.handle(runtimeRequest(
            namespace: "permissions",
            methodName: "contains",
            arguments: [.object([
                "permissions": .array([.string("history")]),
                "origins": .array([.string("https://example.com/*")]),
            ])]
        ))
        XCTAssertEqual(boolValue(containsAfterRevoke.resultPayload), false)
        XCTAssertTrue(module.chromeMV3PermissionEventDispatchRecordsForTesting
            .allSatisfy {
                $0.serviceWorkerWakeAttempted == false
                    && $0.hiddenExtensionPageCreated == false
            })
    }

    @MainActor
    func testManagerRequiredPermissionRemoveIsRejected() throws {
        let fixture = try installOptionalPermissionFixture(
            named: "permission-required-remove",
            profileID: "profile-required-remove"
        )

        let result = fixture.module.chromeMV3RunPermissionControlThroughManager(
            .revokeOptionalAPIPermission,
            rootURL: fixture.root,
            profileID: fixture.record.profileID,
            extensionID: fixture.record.extensionID,
            value: "tabs"
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertFalse(result.returnedBoolean)
        XCTAssertNil(result.eventDispatchRecord)
        XCTAssertTrue(result.diagnostics.contains {
            $0.contains("required")
        })
        XCTAssertFalse(result.serviceWorkerWakeAttempted)
        XCTAssertFalse(result.hiddenExtensionPageCreated)
    }

    @MainActor
    func testRebuildRetryDiagnosticsRecoveryAndExportUseLifecycleOnly()
        throws
    {
        let fixture = try installMinimalFixture(
            named: "rebuild-retry",
            profileID: "profile-retry"
        )
        let module = fixture.module
        let retry = module.chromeMV3RetryDiagnosticsThroughManager(
            rootURL: fixture.root,
            profileID: fixture.record.profileID,
            extensionID: fixture.record.extensionID
        )
        let diagnostics = module.chromeMV3RunDiagnosticsThroughManager(
            rootURL: fixture.root,
            profileID: fixture.record.profileID,
            extensionID: fixture.record.extensionID
        )
        let crash = ChromeMV3ExtensionLifecycleRegistry(rootURL: fixture.root)
            .writeCrashMarker(
                profileID: fixture.record.profileID,
                extensionID: fixture.record.extensionID,
                reason: "manager recovery test",
                lifecycleSessionLeftActive: true,
                nativeFixturePortLeftOpen: true
            )
        let recover = module.chromeMV3RecoverThroughManager(
            rootURL: fixture.root,
            profileID: fixture.record.profileID,
            extensionID: fixture.record.extensionID
        )
        let exported = module.chromeMV3ExportDiagnosticsJSONThroughManager(
            rootURL: fixture.root,
            profileID: fixture.record.profileID,
            extensionID: fixture.record.extensionID
        )

        XCTAssertTrue(retry.succeeded)
        XCTAssertEqual(retry.action, .retryDiagnostics)
        XCTAssertEqual(retry.lifecycleOperationResult?.operation, .rebuild)
        assertNoRuntimeSideEffects(retry, module: module)

        XCTAssertTrue(diagnostics.succeeded)
        XCTAssertEqual(diagnostics.action, .runDiagnostics)
        XCTAssertNotNil(diagnostics.report)
        assertNoRuntimeSideEffects(diagnostics, module: module)

        XCTAssertTrue(crash.succeeded)
        XCTAssertTrue(recover.succeeded)
        XCTAssertEqual(recover.action, .recover)
        XCTAssertEqual(
            recover.lifecycleOperationResult?.record?.lifecycleState,
            .recoveryRequired
        )
        XCTAssertFalse(
            recover.lifecycleOperationResult?.record?.runtimeState
                .internalRuntimeEnabled ?? true
        )
        assertNoRuntimeSideEffects(recover, module: module)

        XCTAssertTrue(exported.succeeded)
        XCTAssertNotNil(exported.diagnosticsJSON)
        assertNoRuntimeSideEffects(exported, module: module)
    }

    @MainActor
    func testRebuildFailurePreservesPreviousWorkingGeneratedVersion()
        throws
    {
        let fixture = try installMinimalFixture(
            named: "rebuild-failure",
            profileID: "profile-rebuild-failure"
        )
        let active = try XCTUnwrap(fixture.record.activeGeneratedVersionID)
        try FileManager.default.removeItem(
            at: URL(fileURLWithPath: fixture.record.originalBundleRootPath)
                .appendingPathComponent("background.js")
        )

        let rebuild = fixture.module.chromeMV3RebuildThroughManager(
            rootURL: fixture.root,
            profileID: fixture.record.profileID,
            extensionID: fixture.record.extensionID
        )
        let failed = try XCTUnwrap(rebuild.lifecycleOperationResult?.record)

        XCTAssertFalse(rebuild.succeeded)
        XCTAssertEqual(
            rebuild.lifecycleOperationResult?.failureCode,
            .resourceMissing
        )
        XCTAssertEqual(failed.lifecycleState, .updateFailed)
        XCTAssertEqual(failed.activeGeneratedVersionID, active)
        XCTAssertFalse(failed.runtimeState.internalRuntimeEnabled)
        assertNoRuntimeSideEffects(rebuild, module: fixture.module)
    }

    @MainActor
    func testUninstallAndResetClearInternalStateWithoutRuntimeObjects()
        throws
    {
        let uninstallFixture = try installMinimalFixture(
            named: "uninstall-manager",
            profileID: "profile-uninstall",
            enableInternal: true
        )
        let installedVersionRoots = uninstallFixture.record
            .generatedBundleVersions.map(\.versionRootPath)
        let uninstall = uninstallFixture.module.chromeMV3UninstallThroughManager(
            rootURL: uninstallFixture.root,
            profileID: uninstallFixture.record.profileID,
            extensionID: uninstallFixture.record.extensionID
        )
        let uninstalled = try XCTUnwrap(
            uninstall.lifecycleOperationResult?.record
        )

        XCTAssertTrue(uninstall.succeeded)
        XCTAssertEqual(uninstalled.lifecycleState, .uninstalled)
        XCTAssertNil(uninstalled.activeGeneratedVersionID)
        XCTAssertFalse(uninstalled.runtimeState.internalRuntimeEnabled)
        XCTAssertTrue(uninstalled.generatedBundleVersions.allSatisfy {
            $0.state == .removed
        })
        XCTAssertTrue(installedVersionRoots.allSatisfy {
            FileManager.default.fileExists(atPath: $0) == false
        })
        assertNoRuntimeSideEffects(uninstall, module: uninstallFixture.module)

        let resetFixture = try installMinimalFixture(
            named: "reset-manager",
            profileID: "profile-reset",
            enableInternal: true
        )
        let reset = resetFixture.module.chromeMV3ResetThroughManager(
            rootURL: resetFixture.root,
            profileID: resetFixture.record.profileID,
            extensionID: resetFixture.record.extensionID
        )
        let resetRecord = try XCTUnwrap(reset.lifecycleOperationResult?.record)

        XCTAssertTrue(reset.succeeded)
        XCTAssertEqual(resetRecord.lifecycleState, .disabledInternal)
        XCTAssertFalse(resetRecord.runtimeState.internalRuntimeEnabled)
        XCTAssertFalse(resetRecord.runtimeState.syntheticHarnessStatePresent)
        XCTAssertFalse(resetRecord.runtimeState.sharedLifecycleSessionActive)
        XCTAssertFalse(resetRecord.runtimeState.nativeFixturePortOpen)
        XCTAssertFalse(resetRecord.runtimeState.storageStatePresent)
        XCTAssertFalse(resetRecord.runtimeState.permissionsStatePresent)
        assertNoRuntimeSideEffects(reset, module: resetFixture.module)
    }

    @MainActor
    func testViewingManagerDoesNotCreateWebKitContextControllerOrBridge()
        throws
    {
        let fixture = try installMinimalFixture(
            named: "view-only",
            profileID: "profile-view"
        )

        _ = fixture.module.chromeMV3ExtensionManagerListViewModelIfEnabled(
            rootURL: fixture.root
        )
        _ = fixture.module.chromeMV3ExtensionManagerDetailViewModelIfEnabled(
            rootURL: fixture.root,
            profileID: fixture.record.profileID,
            extensionID: fixture.record.extensionID
        )

        XCTAssertFalse(fixture.module.hasLoadedRuntime)
        XCTAssertFalse(
            fixture.record.productFlags.productRuntimeAvailable
        )
        XCTAssertFalse(
            fixture.record.productFlags.normalTabRuntimeBridgeAvailable
        )
        XCTAssertFalse(fixture.record.productFlags.runtimeLoadable)
        XCTAssertFalse(
            fixture.record.productFlags.productNetworkEnforcementAvailable
        )
        XCTAssertFalse(fixture.record.productFlags.productRuntimeExposed)
    }

    func testManagerSourceGuardsRemainControlSurfaceOnly() throws {
        let managerSource = try source(
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3ExtensionManagerDeveloperPreview.swift"
        )
        let settingsSource = try source(
            "Sumi/Components/Settings/SettingsView.swift"
        )
        let managerAndSettings = managerSource + "\n" + settingsSource
        let positiveBoolean = "tr" + "ue"

        for token in ["Ti" + "mer", "DispatchSource" + "Ti" + "mer"] {
            XCTAssertFalse(managerAndSettings.contains(token))
        }
        XCTAssertFalse(managerAndSettings.contains("Process" + "("))
        XCTAssertFalse(managerAndSettings.contains("addUser" + "Script"))
        XCTAssertFalse(
            managerAndSettings.contains("addScript" + "MessageHandler")
        )
        XCTAssertFalse(managerAndSettings.contains("WKContent" + "RuleList"))
        XCTAssertFalse(managerAndSettings.contains("chrome" + ".google"))
        XCTAssertFalse(
            managerAndSettings.contains(
                "productRuntimeAvailable: " + positiveBoolean
            )
        )
        XCTAssertFalse(
            managerAndSettings.contains(
                "normalTabRuntimeBridgeAvailable: " + positiveBoolean
            )
        )
        XCTAssertFalse(
            managerAndSettings.contains(
                "runtimeLoadable: " + positiveBoolean
            )
        )
        XCTAssertFalse(
            managerAndSettings.contains(
                "productNetworkEnforcementAvailable: " + positiveBoolean
            )
        )
        XCTAssertFalse(
            managerAndSettings.contains(
                "productRuntimeExposed: " + positiveBoolean
            )
        )
        XCTAssertTrue(managerSource.contains("developerPreviewOnly"))
        XCTAssertTrue(managerSource.contains("managerAvailableInPublicProduct"))
        XCTAssertTrue(managerSource.contains("webStorePageInjectionForbidden"))
        XCTAssertTrue(managerSource.contains("crxSignatureVerificationRequired"))
    }

    @MainActor
    private func installMinimalFixture(
        named name: String,
        profileID: String,
        enableInternal: Bool = false
    ) throws -> InstalledManagerFixture {
        let root = try makeTemporaryDirectory()
        let source = try makeFixture(
            named: name,
            manifest: minimalManifest(version: "1.0.0"),
            files: ["background.js": ""]
        )
        let module = try makeModule(enabled: true)
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: source,
            profileID: profileID,
            enableInternal: enableInternal
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)
        return InstalledManagerFixture(
            root: root,
            module: module,
            record: record
        )
    }

    @MainActor
    private func installOptionalPermissionFixture(
        named name: String,
        profileID: String
    ) throws -> InstalledManagerFixture {
        let root = try makeTemporaryDirectory()
        let source = try makeFixture(
            named: name,
            manifest: optionalPermissionManifest(),
            files: ["background.js": ""]
        )
        let module = try makeModule(enabled: true)
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: source,
            profileID: profileID,
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)
        return InstalledManagerFixture(
            root: root,
            module: module,
            record: record
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
            "name": "Manager Minimal",
            "version": version,
            "background": [
                "service_worker": "background.js",
            ],
        ]
    }

    private func blockerHeavyManifest() -> [String: Any] {
        [
            "manifest_version": 3,
            "name": "Manager Blocker Heavy",
            "version": "1.0.0",
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

    private func optionalPermissionManifest() -> [String: Any] {
        [
            "manifest_version": 3,
            "name": "Manager Optional Permissions",
            "version": "1.0.0",
            "permissions": ["tabs", "activeTab"],
            "optional_permissions": ["history"],
            "optional_host_permissions": ["https://example.com/*"],
            "background": [
                "service_worker": "background.js",
            ],
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

    private func popupOptionsConfiguration(
        for fixture: InstalledManagerFixture
    ) -> ChromeMV3PopupOptionsJSBridgeConfiguration {
        ChromeMV3PopupOptionsJSBridgeConfiguration(
            extensionID: fixture.record.extensionID,
            profileID: fixture.record.profileID,
            surfaceID:
                "\(fixture.record.profileID):\(fixture.record.extensionID):actionPopup",
            surface: .actionPopup,
            extensionBaseURLString:
                "chrome-extension://\(fixture.record.extensionID)/",
            permissionStateRootPath: fixture.root.path,
            moduleState: .enabled,
            bridgeAvailable: true,
            popupOptionsJSBridgeAvailableInDeveloperPreview: true,
            popupOptionsJSBridgeAvailableInPublicProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            contentScriptAttachmentAvailableInProduct: false,
            runtimeLoadable: false,
            manifestPermissions: ["tabs", "activeTab"],
            manifestOptionalPermissions: ["history"],
            manifestHostPermissions: [],
            manifestOptionalHostPermissions: ["https://example.com/*"],
            activeTabGrants: [],
            allowlist: .defaultPolicy,
            diagnostics: [
                "Manager permission control popup/options reflection test configuration.",
            ]
        )
    }

    private func runtimeRequest(
        namespace: String,
        methodName: String,
        arguments: [ChromeMV3StorageValue] = []
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        ChromeMV3RuntimeJSBridgeHostRequest(
            bridgeCallID: UUID().uuidString,
            namespace: namespace,
            methodName: methodName,
            invocationMode: .promise,
            arguments: arguments,
            listenerID: nil,
            eventName: nil,
            portID: nil,
            diagnostics: []
        )
    }

    private func objectValue(
        _ value: ChromeMV3StorageValue?
    ) -> [String: ChromeMV3StorageValue]? {
        guard case .object(let object)? = value else { return nil }
        return object
    }

    private func stringArrayValue(
        _ value: ChromeMV3StorageValue?
    ) -> [String] {
        guard case .array(let values)? = value else { return [] }
        return values.compactMap { value in
            guard case .string(let string) = value else { return nil }
            return string
        }
    }

    private func boolValue(_ value: ChromeMV3StorageValue?) -> Bool? {
        guard case .bool(let bool)? = value else { return nil }
        return bool
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
private struct InstalledManagerFixture {
    var root: URL
    var module: SumiExtensionsModule
    var record: ChromeMV3ExtensionLifecycleRecord
}
