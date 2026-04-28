import WebKit
import XCTest

@testable import Sumi

@available(macOS 13.0, *)
@MainActor
final class SumiPermissionURLHubIntegrationTests: XCTestCase {
    func testRowsReflectStoredDecisionsRuntimeEventsAndWriteThroughCoordinator() async throws {
        let harness = makeHarness()
        let context = currentSiteContext()
        let profile = sumiPermissionIntegrationProfile()
        let blockedStore = SumiBlockedPopupStore()
        let externalStore = SumiExternalSchemeSessionStore()
        let indicatorStore = SumiPermissionIndicatorEventStore()
        let runtime = FakeSumiRuntimePermissionController(
            cameraRuntimeState: .active,
            microphoneRuntimeState: .none,
            geolocationRuntimeState: .active
        )

        try await harness.coordinator.setSiteDecision(
            for: context.key(for: .microphone),
            state: .deny,
            source: .user,
            reason: "seed"
        )
        blockedStore.record(blockedPopup(context: context))
        externalStore.record(externalAttempt(context: context))

        let viewModel = SumiCurrentSitePermissionsViewModel()
        let dependencies = dependencies(
            coordinator: harness.coordinator,
            runtime: runtime,
            autoplay: harness.autoplayStore,
            blockedPopupStore: blockedStore,
            externalStore: externalStore,
            indicatorStore: indicatorStore
        )

        await viewModel.load(
            context: context,
            webView: WKWebView(),
            profile: profile,
            reloadRequired: true,
            dependencies: dependencies
        )

        let microphone = try XCTUnwrap(viewModel.rows.first { $0.id == "microphone" })
        let camera = try XCTUnwrap(viewModel.rows.first { $0.id == "camera" })
        let popups = try XCTUnwrap(viewModel.rows.first { $0.id == "popups" })
        let external = try XCTUnwrap(viewModel.rows.first { $0.id == "external-scheme-mailto" })
        let autoplay = try XCTUnwrap(viewModel.rows.first { $0.id == "autoplay" })

        XCTAssertEqual(microphone.currentOption, .block)
        XCTAssertEqual(camera.runtimeStatus, "Active")
        XCTAssertEqual(popups.recentEventCount, 1)
        XCTAssertEqual(external.recentEventCount, 1)
        XCTAssertEqual(autoplay.subtitle, "Reload required")

        await viewModel.select(.allow, for: camera, profile: profile, dependencies: dependencies)
        await viewModel.select(.block, for: external, profile: profile, dependencies: dependencies)
        await viewModel.select(.blockAudible, for: autoplay, profile: profile, dependencies: dependencies)

        let cameraState = await harness.store.record(for: context.key(for: .camera))?.decision.state
        let externalState = await harness.store.record(for: context.key(for: .externalScheme("mailto")))?.decision.state
        XCTAssertEqual(cameraState, .allow)
        XCTAssertEqual(externalState, .deny)
        XCTAssertEqual(harness.autoplayStore.explicitPolicy(for: profileURL, profile: profile), .blockAudible)
    }

    func testResetCurrentSiteClearsOnlyPermissionAndSessionEvents() async throws {
        let harness = makeHarness()
        let context = currentSiteContext()
        let profile = sumiPermissionIntegrationProfile()
        let blockedStore = SumiBlockedPopupStore()
        let externalStore = SumiExternalSchemeSessionStore()
        let indicatorStore = SumiPermissionIndicatorEventStore()
        let dependencies = dependencies(
            coordinator: harness.coordinator,
            runtime: nil,
            autoplay: harness.autoplayStore,
            blockedPopupStore: blockedStore,
            externalStore: externalStore,
            indicatorStore: indicatorStore
        )

        try await harness.coordinator.setSiteDecision(
            for: context.key(for: .camera),
            state: .allow,
            source: .user,
            reason: "seed"
        )
        try await harness.coordinator.setSiteDecision(
            for: context.key(for: .popups),
            state: .deny,
            source: .user,
            reason: "seed"
        )
        try await harness.autoplayStore.setPolicy(
            .blockAll,
            for: profileURL,
            profile: profile,
            source: .user,
            now: sumiPermissionIntegrationNow
        )
        blockedStore.record(blockedPopup(context: context))
        externalStore.record(externalAttempt(context: context))
        indicatorStore.record(indicatorEvent(context: context))

        let viewModel = SumiCurrentSitePermissionsViewModel()
        await viewModel.load(
            context: context,
            webView: nil,
            profile: profile,
            reloadRequired: false,
            dependencies: dependencies
        )

        await viewModel.resetCurrentSite(profile: profile, dependencies: dependencies)

        let cameraRecord = await harness.store.record(for: context.key(for: .camera))
        let popupRecord = await harness.store.record(for: context.key(for: .popups))
        XCTAssertNil(cameraRecord)
        XCTAssertNil(popupRecord)
        XCTAssertNil(harness.autoplayStore.explicitPolicy(for: profileURL, profile: profile))
        XCTAssertTrue(blockedStore.records(forPageId: context.pageId!).isEmpty)
        XCTAssertTrue(externalStore.records(forPageId: context.pageId!).isEmpty)
        XCTAssertTrue(indicatorStore.records(forPageId: context.pageId!).isEmpty)

        let settingsSource = try sourceFile("Sumi/Permissions/UI/SumiCurrentSitePermissionsViewModel.swift")
        XCTAssertFalse(settingsSource.contains("removeWebsiteData"))
        XCTAssertFalse(settingsSource.contains("tracking"))
        XCTAssertFalse(settingsSource.contains("cookies"))
    }

    func testUnsupportedContentSettingsRemainAbsentFromURLHubSource() throws {
        let source = try sourceFile("Sumi/Permissions/UI/SumiCurrentSitePermissionsViewModel.swift")

        XCTAssertTrue(source.contains("sitePermissionRow(\n                permissionType: .camera"))
        XCTAssertTrue(source.contains("sitePermissionRow(\n                permissionType: .storageAccess"))
        XCTAssertFalse(source.contains("javascript"))
        XCTAssertFalse(source.contains("background-sync"))
        XCTAssertFalse(source.contains("automatic downloads"))
        XCTAssertFalse(source.contains("sound"))
    }

    private func makeHarness() -> (
        store: SumiPermissionIntegrationStore,
        coordinator: SumiPermissionCoordinator,
        autoplayStore: SumiPermissionIntegrationAutoplayStore
    ) {
        let store = SumiPermissionIntegrationStore()
        let coordinator = SumiPermissionCoordinator(
            policyResolver: DefaultSumiPermissionPolicyResolver(
                systemPermissionService: FakeSumiSystemPermissionService(
                    states: sumiPermissionIntegrationAuthorizedSystemStates()
                )
            ),
            memoryStore: InMemoryPermissionStore(),
            persistentStore: store,
            sessionOwnerId: "window-a",
            now: sumiPermissionIntegrationDate
        )
        return (store, coordinator, SumiPermissionIntegrationAutoplayStore())
    }

    private var profileURL: URL {
        URL(string: "https://example.com/page")!
    }

    private func currentSiteContext() -> SumiCurrentSitePermissionsViewModel.Context {
        SumiCurrentSitePermissionsViewModel.Context(
            tabId: "tab-a",
            pageId: "tab-a:1",
            committedURL: profileURL,
            visibleURL: profileURL,
            mainFrameURL: profileURL,
            origin: sumiPermissionIntegrationOrigin(),
            profilePartitionId: "profile-a",
            isEphemeralProfile: false,
            displayDomain: "example.com",
            navigationOrPageGeneration: "1"
        )
    }

    private func dependencies(
        coordinator: any SumiPermissionCoordinating,
        runtime: (any SumiRuntimePermissionControlling)?,
        autoplay: SumiPermissionIntegrationAutoplayStore,
        blockedPopupStore: SumiBlockedPopupStore,
        externalStore: SumiExternalSchemeSessionStore,
        indicatorStore: SumiPermissionIndicatorEventStore
    ) -> SumiCurrentSitePermissionsViewModel.LoadDependencies {
        SumiCurrentSitePermissionsViewModel.LoadDependencies(
            coordinator: coordinator,
            systemPermissionService: FakeSumiSystemPermissionService(
                states: sumiPermissionIntegrationAuthorizedSystemStates()
            ),
            runtimeController: runtime,
            autoplayStore: autoplay,
            blockedPopupStore: blockedPopupStore,
            externalSchemeSessionStore: externalStore,
            indicatorEventStore: indicatorStore
        )
    }

    private func blockedPopup(
        context: SumiCurrentSitePermissionsViewModel.Context
    ) -> SumiBlockedPopupRecord {
        SumiBlockedPopupRecord(
            id: "popup-a",
            tabId: context.tabId!,
            pageId: context.pageId!,
            requestingOrigin: context.origin,
            topOrigin: context.origin,
            targetURL: URL(string: "https://example.com/popup"),
            sourceURL: context.mainFrameURL,
            createdAt: sumiPermissionIntegrationNow,
            lastBlockedAt: sumiPermissionIntegrationNow,
            userActivation: .none,
            reason: .blockedByDefault,
            canOpenLater: true,
            navigationActionMetadata: [:],
            profilePartitionId: context.profilePartitionId,
            isEphemeralProfile: context.isEphemeralProfile,
            attemptCount: 1
        )
    }

    private func externalAttempt(
        context: SumiCurrentSitePermissionsViewModel.Context
    ) -> SumiExternalSchemeAttemptRecord {
        SumiExternalSchemeAttemptRecord(
            id: "external-a",
            tabId: context.tabId!,
            pageId: context.pageId!,
            requestingOrigin: context.origin,
            topOrigin: context.origin,
            scheme: "mailto",
            redactedTargetURLString: "mailto:test@example.com",
            appDisplayName: "Mail",
            createdAt: sumiPermissionIntegrationNow,
            lastAttemptAt: sumiPermissionIntegrationNow,
            userActivation: .none,
            result: .blockedByDefault,
            reason: "test",
            navigationActionMetadata: [:],
            profilePartitionId: context.profilePartitionId,
            isEphemeralProfile: context.isEphemeralProfile,
            attemptCount: 1
        )
    }

    private func indicatorEvent(
        context: SumiCurrentSitePermissionsViewModel.Context
    ) -> SumiPermissionIndicatorEventRecord {
        SumiPermissionIndicatorEventRecord(
            tabId: context.tabId!,
            pageId: context.pageId!,
            displayDomain: context.displayDomain,
            permissionTypes: [.notifications],
            category: .blockedEvent,
            visualStyle: .blocked,
            priority: .blockedNotification,
            reason: "test",
            requestingOrigin: context.origin,
            topOrigin: context.origin,
            profilePartitionId: context.profilePartitionId,
            isEphemeralProfile: context.isEphemeralProfile,
            createdAt: sumiPermissionIntegrationNow
        )
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
