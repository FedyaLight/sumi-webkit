import AppKit
import XCTest

@testable import Sumi
import SumiDomain

@MainActor
final class BrowserWindowShellServiceTests: XCTestCase {
    func testNewWindowPlacementCascadesFromSourceWindow() {
        let source = makeWindow(frame: NSRect(x: 120, y: 220, width: 600, height: 400))
        let newWindow = makeWindow(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        defer {
            source.close()
            newWindow.close()
        }

        BrowserWindowGeometryPolicy.placeNewWindow(
            newWindow,
            relativeTo: source
        )

        XCTAssertNotEqual(newWindow.frame.origin, source.frame.origin)
        XCTAssertEqual(newWindow.frame.size, source.frame.size)
    }

    func testArchivedWindowGeometryRestoresInsideVisibleScreen() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let expectedFrame = NSRect(
            x: screen.visibleFrame.minX + 80,
            y: screen.visibleFrame.minY + 80,
            width: min(700, screen.visibleFrame.width - 160),
            height: min(500, screen.visibleFrame.height - 160)
        )
        let window = makeWindow(
            frame: NSRect(x: 0, y: 0, width: 320, height: 240)
        )
        defer { window.close() }
        let geometry = BrowserWindowGeometrySnapshot(
            frame: BrowserWindowFrameSnapshot(expectedFrame),
            displayMode: .normal
        )

        BrowserWindowGeometryPolicy.restoreFrame(geometry, to: window)

        XCTAssertEqual(window.frame, expectedFrame)
    }

    func testPendingGeometryFrameIsAppliedOnlyOncePerNativeShell() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let restoredFrame = NSRect(
            x: screen.visibleFrame.minX + 40,
            y: screen.visibleFrame.minY + 40,
            width: min(640, screen.visibleFrame.width - 80),
            height: min(480, screen.visibleFrame.height - 80)
        )
        let userMovedFrame = restoredFrame.offsetBy(dx: 30, dy: 30)
        let window = makeWindow(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        defer { window.close() }
        let windowState = BrowserWindowState()
        windowState.restorationState.stageWindowGeometry(
            BrowserWindowGeometrySnapshot(
                frame: BrowserWindowFrameSnapshot(restoredFrame),
                displayMode: .normal
            )
        )

        XCTAssertTrue(
            BrowserWindowGeometryPolicy.restorePendingFrame(
                of: windowState,
                to: window
            )
        )
        XCTAssertEqual(window.frame, restoredFrame)

        window.setFrame(userMovedFrame, display: false)

        XCTAssertFalse(
            BrowserWindowGeometryPolicy.restorePendingFrame(
                of: windowState,
                to: window
            )
        )
        XCTAssertEqual(
            window.frame,
            userMovedFrame,
            "A later bridge update must not overwrite a user's move."
        )
        XCTAssertNotNil(windowState.restorationState.pendingWindowGeometry)
    }

    func testPendingGeometryCanMoveToAReplacementNativeShellBeforeConsumption()
        throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let restoredFrame = NSRect(
            x: screen.visibleFrame.minX + 60,
            y: screen.visibleFrame.minY + 60,
            width: min(600, screen.visibleFrame.width - 120),
            height: min(440, screen.visibleFrame.height - 120)
        )
        let firstWindow = makeWindow(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let replacementWindow = makeWindow(
            frame: NSRect(x: 20, y: 20, width: 320, height: 240)
        )
        defer {
            firstWindow.close()
            replacementWindow.close()
        }
        let windowState = BrowserWindowState()
        let geometry = BrowserWindowGeometrySnapshot(
            frame: BrowserWindowFrameSnapshot(restoredFrame),
            displayMode: .normal
        )
        windowState.restorationState.stageWindowGeometry(geometry)

        XCTAssertTrue(
            BrowserWindowGeometryPolicy.restorePendingFrame(
                of: windowState,
                to: firstWindow
            )
        )
        XCTAssertTrue(
            BrowserWindowGeometryPolicy.restorePendingFrame(
                of: windowState,
                to: replacementWindow
            )
        )
        XCTAssertEqual(replacementWindow.frame, restoredFrame)
        XCTAssertEqual(
            windowState.restorationState.consumePendingWindowGeometry(),
            geometry
        )
        XCTAssertNil(windowState.restorationState.pendingWindowGeometry)
    }

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
        let ephemeralSpace = try XCTUnwrap(windowState.ephemeralSpaces.first)
        let nativeWindow = try XCTUnwrap(
            harness.windowRegistry.appKitWindow(for: windowState)
        )
        XCTAssertEqual(nativeWindow.title, "Private Window - Sumi")
        XCTAssertEqual(ephemeralSpace.name, "Private")
        XCTAssertEqual(ephemeralProfile.name, "Private")
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
        let residueCleanup = RecordingPrivatePartitionResidueCleanup()
        harness.browserManager.profileManager.privatePartitionResidueCleanup =
            residueCleanup
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
        XCTAssertEqual(residueCleanup.profileIDs, [ephemeralProfile.id])
    }

    func testSharedPrivatePartitionIsSweptOnlyAfterFinalWindowCloses()
        async throws {
        let harness = try makeHarness()
        let service = BrowserWindowShellService()
        let context = makeContext(harness: harness) { _, _ in /* No-op. */ }
        let residueCleanup = RecordingPrivatePartitionResidueCleanup()
        harness.browserManager.profileManager.privatePartitionResidueCleanup =
            residueCleanup
        let firstWindow = BrowserWindowState()
        firstWindow.isIncognito = true
        let secondWindow = BrowserWindowState()
        secondWindow.isIncognito = true

        let profile = harness.browserManager.profileManager
            .createEphemeralProfile(for: firstWindow.id)
        firstWindow.ephemeralProfile = profile
        secondWindow.ephemeralProfile = try XCTUnwrap(
            harness.browserManager.profileManager.shareEphemeralProfile(
                from: firstWindow.id,
                with: secondWindow.id
            )
        )

        await service.closeIncognitoWindow(firstWindow, using: context)

        XCTAssertTrue(residueCleanup.profileIDs.isEmpty)

        await service.closeIncognitoWindow(secondWindow, using: context)

        XCTAssertEqual(residueCleanup.profileIDs, [profile.id])
    }

    func testCancelledPrivatePartitionCreationSweepsResidue() throws {
        let harness = try makeHarness()
        let residueCleanup = RecordingPrivatePartitionResidueCleanup()
        harness.browserManager.profileManager.privatePartitionResidueCleanup =
            residueCleanup
        let windowID = UUID()
        let profile = harness.browserManager.profileManager
            .createEphemeralProfile(for: windowID)

        XCTAssertTrue(
            harness.browserManager.profileManager
                .cancelEphemeralProfileCreation(
                    for: windowID,
                    expected: profile
                )
        )
        XCTAssertEqual(residueCleanup.profileIDs, [profile.id])
    }

    func testDisplayReflowKeepsPartiallyVisibleWindowInPlace() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let window = makeWindow(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        defer { window.close() }
        let hangingOff = NSRect(
            x: screen.visibleFrame.maxX - 40,
            y: screen.visibleFrame.midY - 120,
            width: 320,
            height: 240
        )
        window.setFrame(hangingOff, display: false)

        BrowserWindowGeometryPolicy.reflowOntoVisibleScreen(window)

        XCTAssertEqual(window.frame, hangingOff)
    }

    func testDisplayReflowReturnsInvisibleWindowToFirstScreen() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let maxX = NSScreen.screens.map(\.visibleFrame.maxX).max() ?? 0
        let maxY = NSScreen.screens.map(\.visibleFrame.maxY).max() ?? 0
        let window = makeWindow(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        defer { window.close() }
        window.setFrame(
            NSRect(
                x: maxX + 1000,
                y: maxY + 1000,
                width: 320,
                height: 240
            ),
            display: false
        )

        BrowserWindowGeometryPolicy.reflowOntoVisibleScreen(window)

        XCTAssertTrue(screen.visibleFrame.contains(window.frame))
    }

    func testDisplayReflowKeepsOversizedWindowControlsReachable() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let maxX = NSScreen.screens.map(\.visibleFrame.maxX).max() ?? 0
        let maxY = NSScreen.screens.map(\.visibleFrame.maxY).max() ?? 0
        let window = makeWindow(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        defer { window.close() }
        window.setFrame(
            NSRect(
                x: maxX + 1000,
                y: maxY + 1000,
                width: screen.visibleFrame.width + 600,
                height: screen.visibleFrame.height + 400
            ),
            display: false
        )

        BrowserWindowGeometryPolicy.reflowOntoVisibleScreen(window)

        XCTAssertTrue(screen.visibleFrame.contains(window.frame))
        XCTAssertEqual(window.frame.maxY, screen.visibleFrame.maxY, accuracy: 1)
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
            startupPersistence: BrowserManagerStartupPersistence(database: startupContainer
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

    private func makeInMemoryStartupContainer() throws -> SumiDatabase {
        try SumiDatabase.inMemory()
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

    private func makeWindow(frame: NSRect) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable],
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

@MainActor
private final class RecordingPrivatePartitionResidueCleanup:
    PrivatePartitionResidueCleaning {
    private(set) var profileIDs: [UUID] = []

    func cleanup(profileID: UUID) {
        profileIDs.append(profileID)
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
