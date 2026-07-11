import AppKit
import SwiftData
import XCTest

@testable import Sumi
import SumiDomain
import SumiWebRuntime

@MainActor
final class BrowserWindowShellServiceTests: XCTestCase {
    func testCreateIncognitoWindowShowsFloatingBarEmptyStateWithoutCreatingEmptyTab() throws {
        let harness = try makeHarness()
        let service = BrowserWindowShellService()
        var emptyStateRequests: [(windowId: UUID, presentNewTabFloatingBar: Bool)] = []

        let context = makeContext(harness: harness) { windowState, presentNewTabFloatingBar in
            emptyStateRequests.append((windowState.id, presentNewTabFloatingBar))
            windowState.currentTabId = nil
            windowState.ephemeralTabs.removeAll()
            windowState.isShowingEmptyState = true
            if presentNewTabFloatingBar {
                windowState.floatingBarDraftText = ""
                windowState.floatingBarDraftNavigatesCurrentTab = false
                windowState.floatingBarPresentationReason = .emptySpace
                windowState.isFloatingBarVisible = true
            }
        }

        service.createIncognitoWindow(using: context)

        guard let windowState = harness.windowRegistry.allWindows.first else {
            return XCTFail("Expected an incognito window to be registered.")
        }
        defer {
            harness.windowRegistry.appKitWindow(for: windowState)?.close()
            harness.windowRegistry.unregister(windowState.id)
        }

        XCTAssertTrue(windowState.isIncognito)
        XCTAssertEqual(emptyStateRequests.count, 1)
        XCTAssertEqual(emptyStateRequests.first?.windowId, windowState.id)
        XCTAssertEqual(emptyStateRequests.first?.presentNewTabFloatingBar, true)
        XCTAssertTrue(windowState.ephemeralTabs.isEmpty)
        XCTAssertNil(windowState.currentTabId)
        XCTAssertTrue(windowState.isShowingEmptyState)
        XCTAssertTrue(windowState.isFloatingBarVisible)
        XCTAssertEqual(windowState.floatingBarPresentationReason, .emptySpace)
        XCTAssertEqual(windowState.floatingBarDraftText, "")
        XCTAssertFalse(windowState.floatingBarDraftNavigatesCurrentTab)

        let ephemeralProfile = try XCTUnwrap(windowState.ephemeralProfile)
        XCTAssertTrue(ephemeralProfile.isEphemeral)
        XCTAssertFalse(ephemeralProfile.dataStore.isPersistent)
        XCTAssertFalse(harness.profileManager.profiles.contains { $0.id == ephemeralProfile.id })
    }

    func testCreateNewWindowUsesContentFactoryAndRegistersWindowWithAssociatedNSWindow() throws {
        let harness = try makeHarness()
        let service = BrowserWindowShellService()
        var factoryWindowStates: [BrowserWindowState] = []
        var registeredWindowHadNSWindow: Bool?
        harness.windowRegistry.onWindowRegister = { windowState in
            registeredWindowHadNSWindow = harness.windowRegistry.appKitWindow(for: windowState) != nil
        }

        let context = BrowserWindowShellService.Context(
            windowRegistry: harness.windowRegistry,
            webViewLifecycle: harness.webViewRuntime.lifecycleService,
            permissionLifecycleController: harness.permissionLifecycleController,
            profileManager: harness.profileManager,
            tabManager: harness.tabManager,
            makeContentView: { windowRegistry, windowState in
                XCTAssertIdentical(windowRegistry, harness.windowRegistry)
                factoryWindowStates.append(windowState)
                return NSView()
            },
            showEmptyState: { _, _ in /* no-op */ },
            sidebarHostRecoveryCoordinator: SidebarHostRecoveryCoordinator()
        )

        service.createNewWindow(using: context)

        let windowState = try XCTUnwrap(harness.windowRegistry.allWindows.first)
        defer {
            harness.windowRegistry.appKitWindow(for: windowState)?.close()
            harness.windowRegistry.unregister(windowState.id)
        }

        XCTAssertEqual(factoryWindowStates.map(\.id), [windowState.id])
        XCTAssertTrue(harness.windowRegistry.appKitWindow(for: windowState) is SumiBrowserWindow)
        XCTAssertIdentical(windowState.tabManager, harness.tabManager)
        XCTAssertEqual(harness.windowRegistry.activeWindowId, windowState.id)
        XCTAssertTrue(try XCTUnwrap(registeredWindowHadNSWindow))
    }

    func testPrepublicationInitializationCompletesBeforeRegistrationAndActivation() throws {
        let harness = try makeHarness()
        let service = BrowserWindowShellService()
        let archiveID = UUID()
        let profileID = UUID()
        var events: [String] = []
        var registeredState: BrowserWindowState?
        var activeState: BrowserWindowState?
        harness.windowRegistry.onWindowRegister = { windowState in
            events.append("register")
            registeredState = windowState
            XCTAssertEqual(windowState.restoredSessionWindowId, archiveID)
            XCTAssertEqual(windowState.currentProfileId, profileID)
            XCTAssertTrue(windowState.isAwaitingInitialSessionResolution)
            XCTAssertNotNil(
                harness.windowRegistry.appKitWindow(for: windowState),
                "The AppKit shell must be bound before registry publication"
            )
            windowState.isAwaitingInitialSessionResolution = false
        }
        harness.windowRegistry.onActiveWindowChange = { windowState in
            events.append("active")
            activeState = windowState
            XCTAssertFalse(windowState.isAwaitingInitialSessionResolution)
        }
        let context = BrowserWindowShellService.Context(
            windowRegistry: harness.windowRegistry,
            webViewLifecycle: harness.webViewRuntime.lifecycleService,
            permissionLifecycleController: harness
                .permissionLifecycleController,
            profileManager: harness.profileManager,
            tabManager: harness.tabManager,
            makeContentView: { registry, windowState in
                events.append("content")
                XCTAssertEqual(windowState.restoredSessionWindowId, archiveID)
                XCTAssertEqual(windowState.currentProfileId, profileID)
                XCTAssertNil(registry.windows[windowState.id])
                return NSView()
            },
            showEmptyState: { _, _ in /* No-op. */ },
            sidebarHostRecoveryCoordinator: SidebarHostRecoveryCoordinator()
        )

        let windowState = try XCTUnwrap(service.createNewWindow(
            using: context,
            initializeBeforePublication: { windowState in
                events.append("prepare")
                windowState.restoredSessionWindowId = archiveID
                windowState.currentProfileId = profileID
                windowState.isAwaitingInitialSessionResolution = true
            },
            validateAfterRegistration: {
                $0.isAwaitingInitialSessionResolution == false
            },
            compensateRejectedRegistration: { _ in
                XCTFail("Accepted registration must not be compensated")
            }
        ))
        defer {
            harness.windowRegistry.appKitWindow(for: windowState)?.close()
            harness.windowRegistry.unregister(windowState.id)
        }

        XCTAssertEqual(events, ["prepare", "content", "register", "active"])
        XCTAssertIdentical(registeredState, windowState)
        XCTAssertIdentical(activeState, windowState)
    }

    func testRejectedRegistrationRunsCompensationBeforeRegistryRollback() throws {
        let harness = try makeHarness()
        let service = BrowserWindowShellService()
        var events: [String] = []
        var preparedWindow: BrowserWindowState?
        harness.windowRegistry.onWindowRegister = { _ in
            events.append("register")
        }
        harness.windowRegistry.onWindowClose = { _ in
            XCTFail("Rejected publication is not a user-visible window close")
        }
        let context = makeContext(harness: harness) { _, _ in /* No-op. */ }

        let result = service.createNewWindow(
            using: context,
            initializeBeforePublication: { windowState in
                events.append("prepare")
                preparedWindow = windowState
                windowState.isAwaitingInitialSessionResolution = true
            },
            validateAfterRegistration: { _ in false },
            compensateRejectedRegistration: { windowState in
                events.append("compensate")
                XCTAssertIdentical(
                    harness.windowRegistry.windows[windowState.id],
                    windowState
                )
            }
        )

        XCTAssertNil(result)
        XCTAssertEqual(events, ["prepare", "register", "compensate"])
        XCTAssertTrue(harness.windowRegistry.windows.isEmpty)
        XCTAssertNil(
            preparedWindow.flatMap {
                harness.windowRegistry.appKitWindow(for: $0)
            }
        )
    }

    func testEphemeralTabsUseMonotonicIndexesAndIncognitoCleanupIsIdempotent() async throws {
        let harness = try makeHarness()
        let service = BrowserWindowShellService()
        let context = makeContext(harness: harness) { windowState, presentNewTabFloatingBar in
            windowState.currentTabId = nil
            windowState.isShowingEmptyState = true
            if presentNewTabFloatingBar {
                windowState.floatingBarPresentationReason = .emptySpace
                windowState.isFloatingBarVisible = true
            }
        }

        service.createIncognitoWindow(using: context)

        let windowState = try XCTUnwrap(harness.windowRegistry.allWindows.first)
        defer {
            harness.windowRegistry.appKitWindow(for: windowState)?.close()
            harness.windowRegistry.unregister(windowState.id)
        }

        let profile = try XCTUnwrap(windowState.ephemeralProfile)
        let firstTab = harness.tabManager.ephemeralLifecycleOwner.createEphemeralTab(
            url: try XCTUnwrap(URL(string: "https://example.com/one")),
            in: windowState,
            profile: profile
        )
        let secondTab = harness.tabManager.ephemeralLifecycleOwner.createEphemeralTab(
            url: try XCTUnwrap(URL(string: "https://example.com/two")),
            in: windowState,
            profile: profile
        )

        XCTAssertEqual(firstTab.index, 0)
        XCTAssertEqual(secondTab.index, 1)
        XCTAssertEqual(windowState.currentTabId, secondTab.id)
        XCTAssertFalse(profile.dataStore.isPersistent)

        await service.closeIncognitoWindow(windowState, using: context)
        await service.closeIncognitoWindow(windowState, using: context)

        XCTAssertTrue(windowState.ephemeralTabs.isEmpty)
        XCTAssertTrue(windowState.ephemeralSpaces.isEmpty)
        XCTAssertNil(windowState.currentTabId)
        XCTAssertNil(windowState.currentSpaceId)
        XCTAssertNil(windowState.ephemeralProfile)
    }

    func testCloseIncognitoWindowUsesWindowStateOwnershipAndCancelsProfilePermissions() async throws {
        let harness = try makeHarness()
        let service = BrowserWindowShellService()
        let context = makeContext(harness: harness) { _, _ in /* No-op. */ }
        let windowState = BrowserWindowState()
        windowState.isIncognito = true
        windowState.tabManager = harness.tabManager

        let ephemeralProfile = harness.profileManager.createEphemeralProfile(for: windowState.id)
        windowState.ephemeralProfile = ephemeralProfile
        windowState.currentProfileId = ephemeralProfile.id

        let ephemeralSpace = Space(name: "Incognito", profileId: ephemeralProfile.id)
        ephemeralSpace.isEphemeral = true
        windowState.ephemeralSpaces.append(ephemeralSpace)
        windowState.currentSpaceId = ephemeralSpace.id

        _ = harness.tabManager.ephemeralLifecycleOwner.createEphemeralTab(
            url: try XCTUnwrap(URL(string: "https://private.example")),
            in: windowState,
            profile: ephemeralProfile
        )

        await service.closeIncognitoWindow(windowState, using: context)

        XCTAssertTrue(windowState.ephemeralTabs.isEmpty)
        XCTAssertTrue(windowState.ephemeralSpaces.isEmpty)
        XCTAssertNil(windowState.currentTabId)
        XCTAssertNil(windowState.currentSpaceId)
        XCTAssertNil(windowState.ephemeralProfile)

        await waitForPermissionProfileClose(
            coordinator: harness.permissionCoordinator,
            profilePartitionId: ephemeralProfile.id.uuidString
        )
    }

    private struct Harness {
        let startupContainer: ModelContainer
        let windowRegistry: WindowRegistry
        let webViewRuntime: WebViewRuntimeGraph
        let permissionCoordinator: RecordingPermissionCoordinator
        let permissionLifecycleController: SumiPermissionGrantLifecycleController
        let profileManager: ProfileManager
        let tabManager: TabManager
    }

    private func makeHarness() throws -> Harness {
        let startupContainer = try makeInMemoryStartupContainer()
        let context = startupContainer.mainContext
        let webViewSessions = WebViewSessionRepository()
        let profileManager = ProfileManager(context: context)
        let tabManager = TabManager(
            context: context,
            webViewSessions: webViewSessions
        )
        let permissionCoordinator = RecordingPermissionCoordinator()
        let permissionLifecycleController = SumiPermissionGrantLifecycleController(
            coordinator: permissionCoordinator,
            geolocationProvider: nil,
            filePickerBridge: nil,
            indicatorEventStore: SumiPermissionIndicatorEventStore(),
            blockedPopupStore: SumiBlockedPopupStore(),
            externalSchemeSessionStore: SumiExternalSchemeSessionStore()
        )
        return Harness(
            startupContainer: startupContainer,
            windowRegistry: WindowRegistry(),
            webViewRuntime: makeTestWebViewRuntimeGraph(webViewSessions: webViewSessions),
            permissionCoordinator: permissionCoordinator,
            permissionLifecycleController: permissionLifecycleController,
            profileManager: profileManager,
            tabManager: tabManager
        )
    }

    private func makeInMemoryStartupContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func makeContext(
        harness: Harness,
        showEmptyState: @escaping @MainActor (BrowserWindowState, Bool) -> Void
    ) -> BrowserWindowShellService.Context {
        BrowserWindowShellService.Context(
            windowRegistry: harness.windowRegistry,
            webViewLifecycle: harness.webViewRuntime.lifecycleService,
            permissionLifecycleController: harness.permissionLifecycleController,
            profileManager: harness.profileManager,
            tabManager: harness.tabManager,
            makeContentView: { _, _ in NSView() },
            showEmptyState: showEmptyState,
            sidebarHostRecoveryCoordinator: SidebarHostRecoveryCoordinator()
        )
    }

    private func waitForPermissionProfileClose(
        coordinator: RecordingPermissionCoordinator,
        profilePartitionId: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<50 {
            let calls = await coordinator.profileCloseCalls
            if calls.contains(
                ProfileCloseCall(
                    profilePartitionId: profilePartitionId,
                    reason: "incognito-profile-close"
                )
            ) {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        let calls = await coordinator.profileCloseCalls
        XCTFail("Missing profile close event in \(calls)", file: file, line: line)
    }
}

private struct ProfileCloseCall: Equatable {
    let profilePartitionId: String
    let reason: String
}

private actor RecordingPermissionCoordinator: SumiPermissionCoordinating {
    private(set) var profileCloseCalls: [ProfileCloseCall] = []

    func requestPermission(
        _ context: SumiPermissionSecurityContext
    ) async -> SumiPermissionCoordinatorDecision {
        SumiPermissionCoordinatorDecision(
            outcome: .ignored,
            state: nil,
            persistence: nil,
            source: .runtime,
            reason: "test-permission-coordinator",
            permissionTypes: context.request.permissionTypes
        )
    }

    func queryPermissionState(
        _ context: SumiPermissionSecurityContext
    ) async -> SumiPermissionCoordinatorDecision {
        await requestPermission(context)
    }

    func activeQuery(forPageId pageId: String) async -> SumiPermissionAuthorizationQuery? {
        _ = pageId
        return nil
    }

    func stateSnapshot() async -> SumiPermissionCoordinatorState {
        SumiPermissionCoordinatorState()
    }

    func events() async -> AsyncStream<SumiPermissionCoordinatorEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func cancelProfile(
        profilePartitionId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision {
        profileCloseCalls.append(
            ProfileCloseCall(
                profilePartitionId: profilePartitionId,
                reason: reason
            )
        )
        return SumiPermissionCoordinatorDecision(
            outcome: .ignored,
            state: nil,
            persistence: nil,
            source: .runtime,
            reason: reason,
            permissionTypes: []
        )
    }
}
