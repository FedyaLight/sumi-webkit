import SwiftData
import XCTest

@testable import Sumi

final class SumiPermissionSourceRegressionTests: XCTestCase {
    func testNormalTabMediaCaptureRoutesThroughWebKitPermissionBridge() throws {
        let source = try sourceFile("Sumi/Models/Tab/Tab+UIDelegate.swift")
        let publicMedia = try source.slice(
            from: "requestMediaCaptureAuthorization type",
            to: "@objc(_webView:requestDisplayCapturePermissionForOrigin"
        )
        let legacyMedia = try source.slice(
            from: "requestUserMediaAuthorizationForDevices devicesRawValue",
            to: "@available(macOS 10.14, *)"
        )

        XCTAssertTrue(publicMedia.contains("webKitPermissionBridge.handleMediaCaptureAuthorization("))
        XCTAssertTrue(legacyMedia.contains("webKitPermissionBridge.handleLegacyMediaCaptureAuthorization("))
        XCTAssertTrue(legacyMedia.contains("webKitPermissionBridge.handleDisplayCaptureAuthorization("))
        XCTAssertFalse(publicMedia.contains("decisionHandler(.grant)"))
        XCTAssertFalse(legacyMedia.contains("decisionHandler(true)"))
    }

    func testNormalTabGeolocationRoutesThroughGeolocationBridge() throws {
        let source = try sourceFile("Sumi/Models/Tab/Tab+UIDelegate.swift")
        let geolocation = try source.slice(
            from: "_webView:requestGeolocationPermissionForFrame:decisionHandler:",
            to: "private func geolocationTabContext"
        )

        XCTAssertTrue(geolocation.contains("webKitGeolocationBridge.handleLegacyGeolocationAuthorization("))
        XCTAssertTrue(geolocation.contains("webKitGeolocationBridge.handleGeolocationAuthorization("))
        XCTAssertFalse(geolocation.contains("decisionHandler(true)"))
        XCTAssertFalse(geolocation.contains("decisionHandler(.grant)"))
    }

    func testNormalTabPermissionSurfaceContextStaysOutOfMainTabBody() throws {
        let tab = try sourceFile("Sumi/Models/Tab/Tab.swift")
        let surface = try sourceFile("Sumi/Models/Tab/Tab+PermissionSurface.swift")

        XCTAssertFalse(tab.contains("func popupPermissionTabContext"))
        XCTAssertFalse(tab.contains("func externalSchemePermissionTabContext"))
        XCTAssertFalse(tab.contains("func permissionRequestSurfaceState"))
        XCTAssertTrue(surface.contains("func popupPermissionTabContext"))
        XCTAssertTrue(surface.contains("func externalSchemePermissionTabContext"))
        XCTAssertTrue(surface.contains("func permissionRequestSurfaceState"))
    }

    func testNormalTabFilePickerRoutesThroughBridgeAndOpenPanelsStayOutOfNormalTabDelegate() throws {
        let tabDelegate = try sourceFile("Sumi/Models/Tab/Tab+UIDelegate.swift")
        let normalOpenPanel = try tabDelegate.slice(
            from: "runOpenPanelWith parameters",
            to: "/// WebKit private save-data hook"
        )
        let webOpenPanelSources = try [
            "Sumi/Models/Tab/Tab+UIDelegate.swift",
            "Sumi/Permissions/SumiFilePickerPanelPresenter.swift",
        ].map(sourceFile).joined(separator: "\n")

        XCTAssertTrue(normalOpenPanel.contains("filePickerPermissionBridge.handleOpenPanel("))
        XCTAssertFalse(normalOpenPanel.contains("NSOpenPanel"))
        XCTAssertTrue(webOpenPanelSources.contains("SumiFilePickerPanelPresenter"))
        XCTAssertFalse(tabDelegate.contains("let openPanel = NSOpenPanel()"))
    }

    func testExternalSchemeResponderDoesNotOpenWorkspaceDirectlyBeforePermission() throws {
        let responder = try sourceFile("Sumi/Models/Tab/Navigation/SumiExternalSchemeNavigationResponder.swift")
        let bridge = try sourceFile("Sumi/Permissions/SumiExternalSchemePermissionBridge.swift")
        let resolver = try sourceFile("Sumi/Permissions/SumiExternalAppResolver.swift")

        XCTAssertTrue(responder.contains("bridge.evaluate("))
        XCTAssertFalse(responder.contains("NSWorkspace.shared.open"))
        XCTAssertFalse(responder.contains(".open(externalURL)"))
        XCTAssertFalse(bridge.contains("NSWorkspace.shared.open"))
        XCTAssertTrue(resolver.contains("workspace.open(url)"))
    }

    func testNotificationAuthorizationIsIsolatedFromBridgeAndGMNotification() throws {
        let system = try sourceFile("Sumi/Permissions/SumiSystemPermissionService.swift")
        let bridge = try sourceFile("Sumi/Permissions/SumiNotificationPermissionBridge.swift")
        let gmBridge = try sourceFile("Sumi/Managers/SumiScripts/UserScriptGMBridge.swift")
        let gmSubfeatures = try sourceFile("Sumi/Managers/SumiScripts/SumiUserScriptGMSubfeatures.swift")
        let prompt = try sourceFile("Sumi/Permissions/UI/SumiPermissionPromptViewModel.swift")

        XCTAssertTrue(system.contains("UNUserNotificationCenter.current().requestAuthorization"))
        XCTAssertTrue(prompt.contains("systemPermissionService.requestAuthorization(for: kind)"))
        XCTAssertFalse(bridge.contains("UNUserNotificationCenter.current().requestAuthorization"))
        XCTAssertFalse(bridge.contains("requestAuthorization(options:"))
        XCTAssertFalse(gmBridge.contains("UNUserNotificationCenter.current().requestAuthorization"))
        XCTAssertFalse(gmSubfeatures.contains("UNUserNotificationCenter.current().requestAuthorization"))
    }

    func testAutoplayUsesCanonicalStoreInsteadOfOldUserDefaultsOverride() throws {
        let sources = try [
            "Sumi/Models/BrowserConfig/BrowserConfig.swift",
            "Sumi/Models/Tab/Tab+WebViewRuntime.swift",
            "Sumi/Permissions/SumiAutoplayPolicyStoreAdapter.swift",
            "Sumi/Components/Sidebar/URLBarHubPopover.swift",
        ].map(sourceFile).joined(separator: "\n")

        XCTAssertTrue(sources.contains("SumiAutoplayPolicyStoreAdapter"))
        XCTAssertTrue(sources.contains("resolvedAutoplayPolicy"))
        XCTAssertFalse(sources.contains("settings.sitePermissionOverrides.autoplay"))
        XCTAssertFalse(sources.contains("SitePermissionOverridesStore"))
        XCTAssertFalse(sources.contains("AutoplayOverrideState"))
    }

    func testPromptPresenterUnavailableFallbacksAreNotNormalTabPromptDefaults() throws {
        let mediaBridge = try sourceFile("Sumi/Permissions/SumiWebKitPermissionBridge.swift")
        let geolocationBridge = try sourceFile("Sumi/Permissions/SumiWebKitGeolocationBridge.swift")
        let notificationBridge = try sourceFile("Sumi/Permissions/SumiNotificationPermissionBridge.swift")
        let storageBridge = try sourceFile("Sumi/Permissions/SumiStorageAccessPermissionBridge.swift")
        let externalBridge = try sourceFile("Sumi/Permissions/SumiExternalSchemePermissionBridge.swift")
        let browserManager = try sourceFile("Sumi/Managers/BrowserManager/BrowserManager.swift")

        XCTAssertTrue(mediaBridge.contains("pendingStrategy: SumiWebKitPermissionBridgePendingStrategy = .waitForPromptUI"))
        XCTAssertTrue(mediaBridge.contains("screenCapturePendingStrategy: SumiWebKitScreenCapturePendingStrategy = .waitForPromptUI"))
        XCTAssertTrue(geolocationBridge.contains("pendingStrategy: SumiWebKitGeolocationPendingStrategy = .waitForPromptUI"))
        XCTAssertTrue(notificationBridge.contains("pendingStrategy: SumiNotificationPendingStrategy = .waitForPromptUI"))
        XCTAssertTrue(storageBridge.contains("pendingStrategy: SumiStorageAccessPendingStrategy = .waitForPromptUI"))
        XCTAssertTrue(externalBridge.contains("pendingStrategy: SumiExternalSchemePendingStrategy = .waitForPromptUI"))

        XCTAssertFalse(browserManager.contains("promptPresenterUnavailableDeny"))
        XCTAssertFalse(browserManager.contains("promptPresenterUnavailableBlock"))
        XCTAssertFalse(browserManager.contains("prompt-presenter-unavailable-deny"))
        XCTAssertFalse(browserManager.contains("prompt-presenter-unavailable-block"))
    }

    func testSettingsAndRuntimeControlsDoNotWriteSwiftDataOrStoredDecisionsDirectly() throws {
        let settingsSources = try [
            "Sumi/Permissions/UI/SumiSiteSettingsView.swift",
            "Sumi/Permissions/UI/SumiSiteSettingsCategoryView.swift",
            "Sumi/Permissions/UI/SumiSiteSettingsSiteDetailView.swift",
            "Sumi/Permissions/UI/SumiSiteSettingsRows.swift",
            "Sumi/Permissions/UI/SumiCurrentSitePermissionsViewModel.swift",
        ].map(sourceFile).joined(separator: "\n")
        let runtimeSources = try [
            "Sumi/Permissions/UI/SumiPermissionRuntimeControlsViewModel.swift",
            "Sumi/Permissions/UI/SumiPermissionRuntimeControlsView.swift",
        ].map(sourceFile).joined(separator: "\n")

        XCTAssertFalse(settingsSources.contains("import SwiftData"))
        XCTAssertFalse(settingsSources.contains("ModelContext("))
        XCTAssertFalse(settingsSources.contains("requestAuthorization("))
        XCTAssertFalse(settingsSources.contains("UNUserNotificationCenter"))
        XCTAssertFalse(settingsSources.contains("AVCaptureDevice"))
        XCTAssertFalse(settingsSources.contains("CLLocationManager"))
        XCTAssertFalse(settingsSources.contains("CGRequestScreenCaptureAccess"))
        XCTAssertTrue(settingsSources.contains("setSiteDecision("))
        XCTAssertTrue(settingsSources.contains("resetSiteDecision"))
        XCTAssertFalse(runtimeSources.contains("setSiteDecision("))
        XCTAssertFalse(runtimeSources.contains("resetSiteDecision"))
        XCTAssertFalse(runtimeSources.contains("SwiftData"))
        XCTAssertFalse(runtimeSources.contains("SumiPermissionStore"))

        let repository = try sourceFile("Sumi/Permissions/SumiPermissionSettingsRepository.swift")
        let resetSitePermissions = try repository.slice(
            from: "func resetSitePermissions(",
            to: "func deleteSiteData("
        )
        XCTAssertFalse(resetSitePermissions.contains("removeWebsiteData"))
        XCTAssertFalse(resetSitePermissions.contains("deleteSiteData"))
    }

    func testCoordinatorContractStaysOutOfWebKitBridgePolicy() throws {
        let coordinatorContract = try sourceFile("Sumi/Permissions/SumiPermissionCoordinating.swift")
        let webKitBridge = try sourceFile("Sumi/Permissions/SumiWebKitPermissionBridge.swift")

        XCTAssertTrue(coordinatorContract.contains("protocol SumiPermissionCoordinating"))
        XCTAssertTrue(coordinatorContract.contains("extension SumiPermissionCoordinator: SumiPermissionCoordinating"))
        XCTAssertTrue(coordinatorContract.contains("enum SumiPermissionSiteDecisionError"))
        XCTAssertFalse(webKitBridge.contains("protocol SumiPermissionCoordinating"))
        XCTAssertFalse(webKitBridge.contains("enum SumiPermissionSiteDecisionError"))
    }

    func testAntiAbuseSuppressionAndCleanupDoNotPersistUnsafeSideEffects() throws {
        let coordinator = try sourceFile("Sumi/Permissions/SumiPermissionCoordinator.swift")
        let cleanup = try sourceFile("Sumi/Permissions/SumiPermissionCleanupService.swift")
        let suppressionBody = try coordinator.slice(
            from: "private func promptSuppressedDecision",
            to: "private func enqueueAuthorizationQuery"
        )

        XCTAssertTrue(suppressionBody.contains("outcome: .suppressed"))
        XCTAssertFalse(suppressionBody.contains("persistentStore.setDecision"))
        XCTAssertFalse(suppressionBody.contains("SumiPermissionDecision(\n            state: .deny"))

        XCTAssertTrue(cleanup.contains("store.resetDecision(for: record.key)"))
        XCTAssertFalse(cleanup.contains("removeWebsiteData"))
        XCTAssertFalse(cleanup.contains("clearAllProfileWebsiteData"))
        XCTAssertFalse(cleanup.contains("tracking"))
        XCTAssertFalse(cleanup.contains("cookie"))
    }

    @MainActor
    func testBrowserManagerPermissionRuntimeRecordsPermissionEvents() async throws {
        let recentActivityStore = SumiPermissionRecentActivityStore()
        let siteActivityStore = SumiPermissionSiteActivityStore(
            userDefaults: try XCTUnwrap(
                UserDefaults(suiteName: "SumiPermissionSourceRegressionTests-\(UUID().uuidString)")
            )
        )
        let systemPermissionService = FakeSumiSystemPermissionService(
            states: sumiPermissionIntegrationAuthorizedSystemStates()
        )
        let permissionCoordinator = SumiPermissionCoordinator(
            policyResolver: DefaultSumiPermissionPolicyResolver(
                systemPermissionService: systemPermissionService
            ),
            persistentStore: nil,
            antiAbuseStore: nil,
            sessionOwnerId: "browser-permission-source-regression"
        )
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupContainer()
            ),
            systemPermissionService: systemPermissionService,
            permissionCoordinator: permissionCoordinator,
            permissionRecentActivityStore: recentActivityStore,
            permissionSiteActivityStore: siteActivityStore
        )
        await Task.yield()

        let requestTask = Task {
            await browserManager.permissionCoordinator.requestPermission(
                sumiPermissionIntegrationContext([.camera])
            )
        }
        let query = await sumiPermissionIntegrationWaitForActiveQuery(
            browserManager.permissionCoordinator
        )

        await waitUntil {
            recentActivityStore.records.contains {
                $0.permissionType == .camera && $0.action == .asked
            } && siteActivityStore.records(
                forSiteOf: query.topOrigin,
                profilePartitionId: query.profilePartitionId,
                isEphemeralProfile: query.isEphemeralProfile
            ).contains {
                $0.permissionType == .camera && $0.hasRequested
            }
        }

        await browserManager.permissionCoordinator.dismiss(query.id)
        _ = await requestTask.value
    }

    @MainActor
    private func makeInMemoryStartupContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    @MainActor
    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<100 {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for condition", file: file, line: line)
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}

private extension String {
    func slice(from start: String, to end: String) throws -> String {
        guard let startRange = range(of: start) else {
            throw XCTSkip("Missing source marker: \(start)")
        }
        guard let endRange = self[startRange.lowerBound...].range(of: end) else {
            throw XCTSkip("Missing source marker: \(end)")
        }
        return String(self[startRange.lowerBound..<endRange.lowerBound])
    }
}
