import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class WindowSessionRegistrationTests: XCTestCase {
    func testIncognitoRegistrationPreservesEphemeralIdentityAndSkipsDurableRestore()
        throws {
        let fixture = try makeFixture(
            snapshot: makeSnapshot(
                currentSpaceID: UUID(),
                currentProfileID: UUID()
            )
        )
        let windowState = BrowserWindowState()
        let ephemeralProfile = Profile.createEphemeral()
        let ephemeralSpace = Space(
            name: "Private",
            profileId: ephemeralProfile.id
        )
        ephemeralSpace.isEphemeral = true
        let ephemeralTabID = UUID()
        windowState.isIncognito = true
        windowState.tabManager = fixture.tabManager
        windowState.ephemeralProfile = ephemeralProfile
        windowState.ephemeralSpaces = [ephemeralSpace]
        windowState.currentProfileId = ephemeralProfile.id
        windowState.currentSpaceId = ephemeralSpace.id
        windowState.currentTabId = ephemeralTabID
        fixture.extensions.onOpen = { publishedWindow in
            XCTAssertIdentical(publishedWindow.ephemeralProfile, ephemeralProfile)
            XCTAssertEqual(publishedWindow.currentProfileId, ephemeralProfile.id)
            XCTAssertEqual(publishedWindow.currentSpaceId, ephemeralSpace.id)
            XCTAssertEqual(publishedWindow.currentTabId, ephemeralTabID)
        }

        fixture.registration.restore(windowState)
        fixture.restoreService.handleTabManagerDataLoaded(
            windows: [windowState]
        )

        XCTAssertIdentical(windowState.ephemeralProfile, ephemeralProfile)
        XCTAssertEqual(windowState.ephemeralSpaces.map(\.id), [ephemeralSpace.id])
        XCTAssertEqual(windowState.currentProfileId, ephemeralProfile.id)
        XCTAssertEqual(windowState.currentSpaceId, ephemeralSpace.id)
        XCTAssertEqual(windowState.currentTabId, ephemeralTabID)
        XCTAssertFalse(windowState.isAwaitingInitialSessionResolution)
        XCTAssertEqual(fixture.extensions.openedWindowIDs, [windowState.id])
        XCTAssertEqual(fixture.startup.reconcileCallCount, 0)
    }

    func testBatchHydratesEveryWindowBeforePublishingAndReconcilesStartupOnce()
        throws {
        let profile = Profile(name: "Regular")
        let space = Space(name: "Workspace", profileId: profile.id)
        let fixture = try makeFixture(currentProfile: profile)
        fixture.tabManager.spaceStateOwner.replaceSpaces([space])
        let firstWindow = BrowserWindowState()
        let secondWindow = BrowserWindowState()
        let tabManager = fixture.tabManager
        fixture.extensions.onOpen = { openedWindow in
            XCTAssertIdentical(openedWindow.tabManager, tabManager)
            XCTAssertIdentical(firstWindow.tabManager, tabManager)
            XCTAssertIdentical(secondWindow.tabManager, tabManager)
            XCTAssertEqual(firstWindow.currentProfileId, profile.id)
            XCTAssertEqual(secondWindow.currentProfileId, profile.id)
            XCTAssertEqual(firstWindow.currentSpaceId, space.id)
            XCTAssertEqual(secondWindow.currentSpaceId, space.id)
        }

        fixture.registration.restoreRegisteredWindows(
            [firstWindow, secondWindow]
        )

        XCTAssertEqual(
            fixture.extensions.openedWindowIDs,
            [firstWindow.id, secondWindow.id]
        )
        XCTAssertEqual(fixture.startup.reconcileCallCount, 1)
    }

    func testAwaitingRegistrationPublishesExactlyOnceAfterInitialResolution()
        throws {
        let profile = Profile(name: "Regular")
        let space = Space(name: "Workspace", profileId: profile.id)
        let fixture = try makeFixture(
            currentProfile: profile,
            snapshot: makeSnapshot(
                currentSpaceID: space.id,
                currentProfileID: profile.id
            )
        )
        fixture.tabManager.spaceStateOwner.replaceSpaces([space])
        let windowState = BrowserWindowState()

        fixture.registration.restore(windowState)

        XCTAssertTrue(windowState.isAwaitingInitialSessionResolution)
        XCTAssertTrue(fixture.extensions.openedWindowIDs.isEmpty)
        XCTAssertEqual(fixture.startup.reconcileCallCount, 0)

        fixture.tabManager.startupRestoreLifecycle.markLoadFinished()
        fixture.restoreService.handleTabManagerDataLoaded(
            windows: [windowState]
        )
        fixture.registration.completePendingRegistrations(
            registeredWindows: [windowState]
        )
        fixture.registration.completePendingRegistrations(
            registeredWindows: [windowState]
        )

        XCTAssertFalse(windowState.isAwaitingInitialSessionResolution)
        XCTAssertEqual(fixture.extensions.openedWindowIDs, [windowState.id])
    }

    func testPendingRegistrationCannotPublishReplacementWithSameUUID()
        throws {
        let profile = Profile(name: "Regular")
        let space = Space(name: "Workspace", profileId: profile.id)
        let fixture = try makeFixture(
            currentProfile: profile,
            snapshot: makeSnapshot(
                currentSpaceID: space.id,
                currentProfileID: profile.id
            )
        )
        fixture.tabManager.spaceStateOwner.replaceSpaces([space])
        let originalWindow = BrowserWindowState()
        fixture.registration.restore(originalWindow)
        XCTAssertTrue(originalWindow.isAwaitingInitialSessionResolution)

        let replacement = BrowserWindowState(id: originalWindow.id)
        fixture.registration.completePendingRegistrations(
            registeredWindows: [replacement]
        )

        XCTAssertTrue(fixture.extensions.openedWindowIDs.isEmpty)
    }

    func testDiscardedPendingRegistrationCannotPublishLater() throws {
        let profile = Profile(name: "Regular")
        let space = Space(name: "Workspace", profileId: profile.id)
        let fixture = try makeFixture(
            currentProfile: profile,
            snapshot: makeSnapshot(
                currentSpaceID: space.id,
                currentProfileID: profile.id
            )
        )
        fixture.tabManager.spaceStateOwner.replaceSpaces([space])
        let windowState = BrowserWindowState()
        fixture.registration.restore(windowState)
        XCTAssertTrue(windowState.isAwaitingInitialSessionResolution)

        fixture.registration.discardRegistration(windowState)
        windowState.isAwaitingInitialSessionResolution = false
        fixture.registration.completePendingRegistrations(
            registeredWindows: [windowState]
        )

        XCTAssertTrue(fixture.extensions.openedWindowIDs.isEmpty)
    }

    func testActivationHasNoEffectsUntilExactDeferredWindowIsResolved() {
        let sessionKey = "SumiTests.activation.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: sessionKey) }
        let snapshotStore = WindowSessionSnapshotStore(key: sessionKey)
        let browserManager = BrowserManager(
            windowSessionSnapshotStore: snapshotStore
        )
        let extensions = RecordingWindowExtensionLifecycle()
        let activation = BrowserWindowActivationService(
            splitManager: browserManager.splitManager,
            sidebarPresentation: browserManager.chromeBundle
                .sidebarPresentationOwner,
            persistence: browserManager.windowSessionBundle.persistence,
            activePageResolver: browserManager.shellRuntime.activePageResolver,
            findManager: browserManager.findManager,
            extensions: extensions,
            synchronizeFocusedContext: { _ in
                // Focus-context behavior is covered independently.
            },
            nowPlaying: browserManager.nativeNowPlayingController,
            backgroundMedia: browserManager
                .backgroundMediaOptimizationService
        )
        let windowState = BrowserWindowState(
            awaitsInitialSessionResolution: true
        )

        activation.activate(windowState)
        activation.activate(windowState)

        XCTAssertTrue(extensions.focusedWindowIDs.isEmpty)
        XCTAssertNil(snapshotStore.loadSnapshot())

        windowState.isAwaitingInitialSessionResolution = false
        activation.completeDeferredActivation(for: windowState)
        activation.completeDeferredActivation(for: windowState)

        XCTAssertEqual(extensions.focusedWindowIDs, [windowState.id])
        XCTAssertNotNil(snapshotStore.loadSnapshot())
    }

    private func makeFixture(
        currentProfile: Profile? = nil,
        snapshot: WindowSessionSnapshot? = nil
    ) throws -> RegistrationFixture {
        let tabManager = try makeInMemoryTabManager(loadPersistedState: false)
        let sessionKey = "SumiTests.registration.\(UUID().uuidString)"
        if let snapshot {
            XCTAssertTrue(
                WindowSessionSnapshotStore(key: sessionKey).persist(snapshot)
            )
        }
        addTeardownBlock {
            UserDefaults.standard.removeObject(forKey: sessionKey)
        }
        let restoreDelegate = TestWindowSessionDelegate(tabManager: tabManager)
        let restoreService = restoreDelegate.makeRestoreService(
            lastWindowSessionKey: sessionKey
        )
        let profileSupport = try RegistrationProfileSupport(
            currentProfile: currentProfile
        )
        let extensions = RecordingWindowExtensionLifecycle()
        let startup = RecordingStartupSessionReconciler()
        let registration = BrowserWindowSessionRestorationService(
            restoration: restoreService,
            extensions: extensions,
            profileSupport: profileSupport,
            startupSessions: startup
        )
        return RegistrationFixture(
            tabManager: tabManager,
            restoreDelegate: restoreDelegate,
            restoreService: restoreService,
            profileSupport: profileSupport,
            extensions: extensions,
            startup: startup,
            registration: registration
        )
    }

    private func makeSnapshot(
        currentSpaceID: UUID,
        currentProfileID: UUID
    ) -> WindowSessionSnapshot {
        WindowSessionSnapshot(
            currentTabId: nil,
            currentSpaceId: currentSpaceID,
            currentProfileId: currentProfileID,
            activeShortcutPinId: nil,
            activeShortcutPinRole: nil,
            isShowingEmptyState: true,
            floatingBarReason: nil,
            activeTabsBySpace: [],
            activeShortcutsBySpace: [],
            sidebarWidth: Double(BrowserWindowState.sidebarDefaultWidth),
            savedSidebarWidth: Double(
                BrowserWindowState.sidebarDefaultWidth
            ),
            sidebarContentWidth: Double(
                BrowserWindowState.sidebarContentWidth(
                    for: BrowserWindowState.sidebarDefaultWidth
                )
            ),
            isSidebarVisible: true,
            floatingBarDraft: FloatingBarDraftState(
                text: "",
                navigateCurrentTab: false
            )
        )
    }
}

@MainActor
private struct RegistrationFixture {
    let tabManager: TabManager
    let restoreDelegate: TestWindowSessionDelegate
    let restoreService: WindowSessionRestoreService
    let profileSupport: RegistrationProfileSupport
    let extensions: RecordingWindowExtensionLifecycle
    let startup: RecordingStartupSessionReconciler
    let registration: BrowserWindowSessionRestorationService
}

@MainActor
private final class RecordingWindowExtensionLifecycle:
    BrowserWindowExtensionLifecycleNotifying {
    private(set) var openedWindowIDs: [UUID] = []
    private(set) var focusedWindowIDs: [UUID] = []
    var onOpen: ((BrowserWindowState) -> Void)?

    func notifyWindowOpenedIfLoaded(_ windowState: BrowserWindowState) {
        onOpen?(windowState)
        openedWindowIDs.append(windowState.id)
    }

    func notifyWindowFocusedIfLoaded(_ windowState: BrowserWindowState) {
        focusedWindowIDs.append(windowState.id)
    }
}

@MainActor
private final class RecordingStartupSessionReconciler:
    BrowserStartupSessionReconciling {
    private(set) var reconcileCallCount = 0

    func reconcileStartupSessionIfPossible() {
        reconcileCallCount += 1
    }
}

@MainActor
private final class RegistrationProfileSupport: SumiProfileRoutingSupport {
    let currentProfile: Profile?
    let profileManager: ProfileManager
    let windowRegistry: WindowRegistry? = nil
    private let container: ModelContainer

    init(currentProfile: Profile?) throws {
        self.currentProfile = currentProfile
        container = try makeInMemoryStartupModelContainer()
        profileManager = ProfileManager(context: container.mainContext)
        profileManager.profiles = currentProfile.map { [$0] } ?? []
    }

    func switchToProfile(
        _: Profile,
        context _: BrowserManager.ProfileSwitchContext,
        in _: BrowserWindowState?
    ) async {
        // Registration tests never perform a process-wide profile switch.
    }
}
