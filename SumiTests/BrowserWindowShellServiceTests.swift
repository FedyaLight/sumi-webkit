import AppKit
import SwiftData
import XCTest

@testable import Sumi
import SumiDomain

@MainActor
final class BrowserWindowShellServiceTests: XCTestCase {
    func testPresentRegisteredWindowActivatesAndPresentsExactShell() {
        let service = BrowserWindowShellService()
        let registry = WindowRegistry()
        let windowState = BrowserWindowState()
        let window = makePresentationRecordingWindow()
        registry.bindAppKitWindow(window, to: windowState)
        XCTAssertEqual(registry.register(windowState), .registered)
        defer {
            window.close()
            registry.unregister(windowState.id)
        }

        XCTAssertTrue(
            service.presentRegisteredWindow(
                windowState,
                in: registry,
                activate: true
            )
        )
        XCTAssertEqual(registry.activeWindowId, windowState.id)
        XCTAssertEqual(window.makeKeyAndOrderFrontCallCount, 1)
        XCTAssertEqual(window.orderFrontCallCount, 0)
    }

    func testPresentRegisteredWindowDoesNotPresentShellClosedByActivationObserver() {
        let service = BrowserWindowShellService()
        let registry = WindowRegistry()
        let windowState = BrowserWindowState()
        let window = makePresentationRecordingWindow()
        registry.keyAppKitWindowProvider = { nil }
        registry.mainAppKitWindowProvider = { nil }
        registry.bindAppKitWindow(window, to: windowState)
        XCTAssertEqual(registry.register(windowState), .registered)
        installWindowRegistryTestEventSink(
            on: registry,
            activateWindow: { activatedWindow in
                registry.unregister(activatedWindow.id)
            }
        )
        defer { window.close() }

        XCTAssertFalse(
            service.presentRegisteredWindow(
                windowState,
                in: registry,
                activate: true
            )
        )
        XCTAssertNil(registry.windows[windowState.id])
        XCTAssertNil(registry.activeWindowId)
        XCTAssertEqual(window.makeKeyAndOrderFrontCallCount, 0)
        XCTAssertEqual(window.orderFrontCallCount, 0)
    }

    func testCreateIncognitoWindowShowsCommandPaletteEmptyStateWithoutCreatingEmptyTab() throws {
        let harness = try makeHarness()
        let service = BrowserWindowShellService()
        var emptyStateRequests: [(windowId: UUID, presentNewTabCommandPalette: Bool)] = []

        let context = makeContext(harness: harness) { windowState, presentNewTabCommandPalette in
            emptyStateRequests.append((windowState.id, presentNewTabCommandPalette))
            windowState.currentTabId = nil
            windowState.removeAllEphemeralTabs()
            windowState.isShowingEmptyState = true
            if presentNewTabCommandPalette {
                windowState.commandPaletteDraftText = ""
                windowState.commandPaletteDraftNavigatesCurrentTab = false
                windowState.commandPalettePresentationReason = .emptySpace
                windowState.presentationState.isCommandPaletteVisible = true
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
        XCTAssertEqual(emptyStateRequests.first?.presentNewTabCommandPalette, true)
        XCTAssertTrue(windowState.ephemeralTabs.isEmpty)
        XCTAssertNil(windowState.currentTabId)
        XCTAssertTrue(windowState.isShowingEmptyState)
        XCTAssertTrue(windowState.presentationState.isCommandPaletteVisible)
        XCTAssertEqual(windowState.commandPalettePresentationReason, .emptySpace)
        XCTAssertEqual(windowState.commandPaletteDraftText, "")
        XCTAssertFalse(windowState.commandPaletteDraftNavigatesCurrentTab)

        let ephemeralProfile = try XCTUnwrap(windowState.ephemeralProfile)
        XCTAssertTrue(ephemeralProfile.isEphemeral)
        XCTAssertFalse(ephemeralProfile.dataStore.isPersistent)
        XCTAssertFalse(
            harness.browserManager.profileManager.profiles.contains {
                $0.id == ephemeralProfile.id
            }
        )
    }

    func testCreateNewWindowUsesContentFactoryAndRegistersWindowWithAssociatedNSWindow() throws {
        let harness = try makeHarness()
        let service = BrowserWindowShellService()
        var factoryWindowStates: [BrowserWindowState] = []
        var registeredWindowHadNSWindow: Bool?
        installWindowRegistryTestEventSink(
            on: harness.windowRegistry,
            prepareWindowRegistration: { windowState in
                registeredWindowHadNSWindow = harness.windowRegistry
                    .appKitWindow(for: windowState) != nil
            }
        )

        let context = BrowserWindowShellService.Context(
            windowRegistry: harness.windowRegistry,
            permissionLifecycleController: harness.permissionLifecycleController,
            profileManager: harness.browserManager.profileManager,
            tabResidences: harness.browserManager.tabResidenceAuthority,
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
        XCTAssertTrue(
            harness.browserManager.tabResidenceAuthority.owns(windowState)
        )
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
        installWindowRegistryTestEventSink(
            on: harness.windowRegistry,
            prepareWindowRegistration: { windowState in
                events.append("register")
                registeredState = windowState
                XCTAssertEqual(windowState.restorationState.restoredSessionWindowID, archiveID)
                XCTAssertEqual(windowState.currentProfileId, profileID)
                XCTAssertTrue(windowState.restorationState.isAwaitingInitialResolution)
                XCTAssertNotNil(
                    harness.windowRegistry.appKitWindow(for: windowState),
                    "The AppKit shell must be bound before registry publication"
                )
                windowState.restorationState.isAwaitingInitialResolution = false
            },
            publishWindowRegistration: { windowState in
                events.append("publish")
                XCTAssertIdentical(registeredState, windowState)
                XCTAssertIdentical(
                    harness.windowRegistry.windows[windowState.id],
                    windowState
                )
            },
            activateWindow: { windowState in
                events.append("active")
                activeState = windowState
                XCTAssertFalse(windowState.restorationState.isAwaitingInitialResolution)
            }
        )
        let context = BrowserWindowShellService.Context(
            windowRegistry: harness.windowRegistry,
            permissionLifecycleController: harness
                .permissionLifecycleController,
            profileManager: harness.browserManager.profileManager,
            tabResidences: harness.browserManager.tabResidenceAuthority,
            makeContentView: { registry, windowState in
                events.append("content")
                XCTAssertEqual(windowState.restorationState.restoredSessionWindowID, archiveID)
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
                windowState.restorationState.restoredSessionWindowID = archiveID
                windowState.currentProfileId = profileID
                windowState.restorationState.isAwaitingInitialResolution = true
            },
            validateRestoredStateBeforePublication: {
                $0.restorationState.isAwaitingInitialResolution == false
            },
            compensateRejectedRegistration: { _ in
                XCTFail("Accepted registration must not be compensated")
            }
        ))
        defer {
            harness.windowRegistry.appKitWindow(for: windowState)?.close()
            harness.windowRegistry.unregister(windowState.id)
        }

        XCTAssertEqual(
            events,
            ["prepare", "content", "register", "publish", "active"]
        )
        XCTAssertIdentical(registeredState, windowState)
        XCTAssertIdentical(activeState, windowState)
    }

    func testRejectedRegistrationRollsBackBeforeExternalCompensation() throws {
        let harness = try makeHarness()
        let service = BrowserWindowShellService()
        var events: [String] = []
        var preparedWindow: BrowserWindowState?
        installWindowRegistryTestEventSink(
            on: harness.windowRegistry,
            prepareWindowRegistration: { _ in
                events.append("register")
            },
            publishWindowRegistration: { _ in
                XCTFail("Rejected provisional state must never be published")
            },
            closeWindow: { _ in
                XCTFail("Rejected publication is not a user-visible window close")
            }
        )
        let context = makeContext(harness: harness) { _, _ in /* No-op. */ }

        let result = service.createNewWindow(
            using: context,
            initializeBeforePublication: { windowState in
                events.append("prepare")
                preparedWindow = windowState
                windowState.restorationState.isAwaitingInitialResolution = true
            },
            validateRestoredStateBeforePublication: { _ in false },
            compensateRejectedRegistration: { windowState in
                events.append("compensate")
                XCTAssertNil(harness.windowRegistry.windows[windowState.id])
                XCTAssertNil(
                    harness.windowRegistry.appKitWindow(for: windowState)
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

    func testCommittedValidationRejectionCompensatesWithoutActivationOrVisibleShell()
        throws {
        let harness = try makeHarness()
        let service = BrowserWindowShellService()
        var events: [String] = []
        var rejectedWindow: BrowserWindowState?
        installWindowRegistryTestEventSink(
            on: harness.windowRegistry,
            prepareWindowRegistration: { _ in
                events.append("registry-prepare")
            },
            publishWindowRegistration: { _ in
                events.append("registry-publish")
            },
            closeWindow: { _ in
                XCTFail("A validator-rejected registration is not a user-visible close")
            },
            activateWindow: { _ in
                XCTFail("A validator-rejected registration must never activate")
            }
        )
        let context = BrowserWindowShellService.Context(
            windowRegistry: harness.windowRegistry,
            permissionLifecycleController: harness
                .permissionLifecycleController,
            profileManager: harness.browserManager.profileManager,
            tabResidences: harness.browserManager.tabResidenceAuthority,
            makeContentView: { _, _ in
                events.append("content")
                return NSView()
            },
            showEmptyState: { _, _ in /* No-op. */ },
            sidebarHostRecoveryCoordinator: SidebarHostRecoveryCoordinator()
        )

        let result = service.createNewWindow(
            using: context,
            initializeBeforePublication: { window in
                events.append("initialize")
                rejectedWindow = window
            },
            validateRestoredStateBeforePublication: { _ in
                events.append("restored-validation")
                return true
            },
            validateCommittedRegistration: { window in
                events.append("committed-validation")
                XCTAssertIdentical(
                    harness.windowRegistry.windows[window.id],
                    window
                )
                XCTAssertNotNil(
                    harness.windowRegistry.appKitWindow(for: window)
                )
                return false
            },
            compensateRejectedRegistration: { window in
                events.append("compensate")
                XCTAssertIdentical(window, rejectedWindow)
                XCTAssertNil(harness.windowRegistry.windows[window.id])
                XCTAssertNil(harness.windowRegistry.appKitWindow(for: window))
            }
        )

        XCTAssertNil(result)
        XCTAssertEqual(
            events,
            [
                "initialize",
                "content",
                "registry-prepare",
                "restored-validation",
                "registry-publish",
                "committed-validation",
                "compensate",
            ]
        )
        XCTAssertTrue(harness.windowRegistry.windows.isEmpty)
        XCTAssertNil(harness.windowRegistry.activeWindowId)
    }

    func testRejectedPrepublicationPreparationNeverBuildsOrRegistersShell()
        throws {
        let harness = try makeHarness()
        let service = BrowserWindowShellService()
        var events: [String] = []
        installWindowRegistryTestEventSink(
            on: harness.windowRegistry,
            prepareWindowRegistration: { _ in
                XCTFail("A rejected preparation must never enter WindowRegistry")
            }
        )
        let context = BrowserWindowShellService.Context(
            windowRegistry: harness.windowRegistry,
            permissionLifecycleController: harness
                .permissionLifecycleController,
            profileManager: harness.browserManager.profileManager,
            tabResidences: harness.browserManager.tabResidenceAuthority,
            makeContentView: { _, _ in
                XCTFail("A rejected preparation must not construct content")
                return NSView()
            },
            showEmptyState: { _, _ in /* No-op. */ },
            sidebarHostRecoveryCoordinator: SidebarHostRecoveryCoordinator()
        )

        let result = service.createNewWindow(
            using: context,
            initializeBeforePublication: { _ in events.append("prepare") },
            validateBeforeShellPublication: { _ in false },
            validateRestoredStateBeforePublication: { _ in
                XCTFail("A rejected preparation cannot be post-validated")
                return false
            },
            compensateRejectedRegistration: { windowState in
                events.append("compensate")
                XCTAssertNil(harness.windowRegistry.windows[windowState.id])
                XCTAssertNil(
                    harness.windowRegistry.appKitWindow(for: windowState)
                )
            }
        )

        XCTAssertNil(result)
        XCTAssertEqual(events, ["prepare", "compensate"])
        XCTAssertTrue(harness.windowRegistry.windows.isEmpty)
    }

    func testEphemeralTabsUseMonotonicIndexesAndIncognitoCleanupIsIdempotent() async throws {
        let harness = try makeHarness()
        let service = BrowserWindowShellService()
        let context = makeContext(harness: harness) { windowState, presentNewTabCommandPalette in
            windowState.currentTabId = nil
            windowState.isShowingEmptyState = true
            if presentNewTabCommandPalette {
                windowState.commandPalettePresentationReason = .emptySpace
                windowState.presentationState.isCommandPaletteVisible = true
            }
        }

        service.createIncognitoWindow(using: context)

        let windowState = try XCTUnwrap(harness.windowRegistry.allWindows.first)
        defer {
            harness.windowRegistry.appKitWindow(for: windowState)?.close()
            harness.windowRegistry.unregister(windowState.id)
        }

        let profile = try XCTUnwrap(windowState.ephemeralProfile)
        let firstTab = harness.browserManager.ephemeralLifecycleOwner.createEphemeralTab(
            url: try XCTUnwrap(URL(string: "https://example.com/one")),
            in: windowState,
            profile: profile
        )
        let secondTab = harness.browserManager.ephemeralLifecycleOwner.createEphemeralTab(
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
        harness.browserManager.tabResidenceAuthority
            .establishResidenceSession(on: windowState)

        let ephemeralProfile = harness.browserManager.profileManager
            .createEphemeralProfile(for: windowState.id)
        windowState.ephemeralProfile = ephemeralProfile
        windowState.currentProfileId = ephemeralProfile.id

        let ephemeralSpace = Space(name: "Incognito", profileId: ephemeralProfile.id)
        ephemeralSpace.isEphemeral = true
        windowState.appendEphemeralSpace(ephemeralSpace)
        windowState.currentSpaceId = ephemeralSpace.id

        _ = harness.browserManager.ephemeralLifecycleOwner.createEphemeralTab(
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

        let profileCloseCall = await harness.permissionCoordinator.firstProfileCloseCall()
        XCTAssertEqual(
            profileCloseCall,
            ProfileCloseCall(
                profilePartitionId: ephemeralProfile.id.uuidString,
                reason: "incognito-profile-close"
            )
        )
    }

    private struct Harness {
        let windowRegistry: WindowRegistry
        let permissionCoordinator: RecordingPermissionCoordinator
        let permissionLifecycleController: SumiPermissionGrantLifecycleController
        let browserManager: BrowserManager
    }

    private func makeHarness() throws -> Harness {
        let startupContainer = try makeInMemoryStartupContainer()
        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(
            windowRegistry: windowRegistry,
            startupPersistence: BrowserManagerStartupPersistence(
                container: startupContainer
            )
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
            windowRegistry: windowRegistry,
            permissionCoordinator: permissionCoordinator,
            permissionLifecycleController: permissionLifecycleController,
            browserManager: browserManager
        )
    }

    private func makeInMemoryStartupContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func makePresentationRecordingWindow()
        -> WindowPresentationRecordingWindow {
        let window = WindowPresentationRecordingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }

    private func makeContext(
        harness: Harness,
        showEmptyState: @escaping @MainActor (BrowserWindowState, Bool) -> Void
    ) -> BrowserWindowShellService.Context {
        BrowserWindowShellService.Context(
            windowRegistry: harness.windowRegistry,
            permissionLifecycleController: harness.permissionLifecycleController,
            profileManager: harness.browserManager.profileManager,
            tabResidences: harness.browserManager.tabResidenceAuthority,
            makeContentView: { _, _ in NSView() },
            showEmptyState: showEmptyState,
            sidebarHostRecoveryCoordinator: SidebarHostRecoveryCoordinator()
        )
    }
}

private final class WindowPresentationRecordingWindow: NSWindow {
    private(set) var makeKeyAndOrderFrontCallCount = 0
    private(set) var orderFrontCallCount = 0

    override func makeKeyAndOrderFront(_ sender: Any?) {
        makeKeyAndOrderFrontCallCount += 1
        _ = sender
    }

    override func orderFront(_ sender: Any?) {
        orderFrontCallCount += 1
        _ = sender
    }
}

private struct ProfileCloseCall: Equatable, Sendable {
    let profilePartitionId: String
    let reason: String
}

private actor RecordingPermissionCoordinator: SumiPermissionCoordinating {
    private(set) var profileCloseCalls: [ProfileCloseCall] = []
    private var profileCloseWaiters: [CheckedContinuation<ProfileCloseCall, Never>] = []

    func firstProfileCloseCall() async -> ProfileCloseCall {
        if let call = profileCloseCalls.first { return call }
        return await withCheckedContinuation { continuation in
            profileCloseWaiters.append(continuation)
        }
    }

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
        let call = ProfileCloseCall(
            profilePartitionId: profilePartitionId,
            reason: reason
        )
        profileCloseCalls.append(call)

        let waiters = profileCloseWaiters
        profileCloseWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: call)
        }

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
