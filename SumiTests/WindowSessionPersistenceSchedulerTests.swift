import Foundation
import XCTest

@testable import Sumi

/// Ownership coverage for window-session persistence teardown: a bare
/// scheduler cancels its work on deinit, while BrowserManager explicitly
/// flushes requests already accepted by its process-lifetime scheduler.
@MainActor
final class WindowSessionPersistenceSchedulerTests: XCTestCase {
    func testSchedulerDeinitCancelsPendingPersistence() async throws {
        let delayedActions = ManualMainActorDelayedActionScheduler()
        var scheduler: WindowSessionPersistenceScheduler? =
            WindowSessionPersistenceScheduler(
                delayedActions: delayedActions.scheduler
            )
        let windowState = BrowserWindowState()
        let pending = makeDurableWrite(windowState: windowState)

        scheduler?.schedule(
            pending.write,
            delayNanoseconds: 50_000_000,
            afterDurableCommit: {
                XCTFail("Cancelled scheduler must not project live history")
            }
        )

        scheduler = nil
        XCTAssertEqual(delayedActions.pendingActionCount, 0)
        delayedActions.runAll()

        XCTAssertNil(pending.snapshotStore.loadSnapshot())
    }

    func testCancelAllDropsPendingStateSoFlushPersistsNothing() {
        let scheduler = WindowSessionPersistenceScheduler()
        let windowState = BrowserWindowState()
        let pending = makeDurableWrite(windowState: windowState)

        scheduler.schedule(
            pending.write,
            delayNanoseconds: 60_000_000_000,
            afterDurableCommit: {
                XCTFail("Cancelled write must not project live history")
            }
        )
        scheduler.cancelAll()
        XCTAssertEqual(scheduler.flush(), 0)

        XCTAssertNil(pending.snapshotStore.loadSnapshot())
    }

    func testRuntimeTeardownFlushCommitsSnapshotWithoutLiveHistoryProjection() {
        let scheduler = WindowSessionPersistenceScheduler()
        let windowState = BrowserWindowState()
        let persistedProfileID = UUID()
        windowState.currentProfileId = persistedProfileID
        let pending = makeDurableWrite(windowState: windowState)
        var liveArchiveRefreshCount = 0

        scheduler.schedule(
            pending.write,
            delayNanoseconds: 60_000_000_000,
            afterDurableCommit: {
                liveArchiveRefreshCount += 1
            }
        )

        XCTAssertEqual(scheduler.flushDurableStateForRuntimeTeardown(), 1)

        XCTAssertEqual(
            pending.snapshotStore.loadSnapshot()?.snapshot.currentProfileId,
            persistedProfileID
        )
        XCTAssertEqual(liveArchiveRefreshCount, 0)
    }

    func testImmediateCoordinatorPersistCommitsSnapshotAndRefreshesLiveArchive() {
        let harness = makeCoordinatorHarness()

        harness.coordinator.persist(harness.persistedWindow)

        XCTAssertEqual(
            harness.snapshotStore.loadSnapshot()?.snapshot.currentProfileId,
            harness.persistedWindow.currentProfileId
        )
        XCTAssertEqual(
            harness.historyStore.snapshots.map(\.id),
            [harness.persistedWindow.id, harness.otherOpenWindow.id]
        )
    }

    func testIncognitoOnlyImmediatePersistPreservesRegularArchive() {
        let harness = makeCoordinatorHarness()
        let archivedSnapshot = LastSessionWindowSnapshot(
            id: UUID(),
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )
        harness.historyStore.updateSnapshots([archivedSnapshot])
        let incognitoWindow = BrowserWindowState()
        incognitoWindow.isIncognito = true

        harness.coordinator.persist(incognitoWindow)

        XCTAssertNil(harness.snapshotStore.loadSnapshot())
        XCTAssertEqual(harness.historyStore.snapshots, [archivedSnapshot])
    }

    func testIncognitoOnlyScheduledPersistDoesNotCreateLiveArchiveWork() {
        let harness = makeCoordinatorHarness()
        let archivedSnapshot = LastSessionWindowSnapshot(
            id: UUID(),
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )
        harness.historyStore.updateSnapshots([archivedSnapshot])
        let incognitoWindow = BrowserWindowState()
        incognitoWindow.isIncognito = true

        harness.coordinator.schedule(
            incognitoWindow,
            delayNanoseconds: 0
        )

        XCTAssertEqual(harness.coordinator.flush(), 0)
        XCTAssertNil(harness.snapshotStore.loadSnapshot())
        XCTAssertEqual(harness.historyStore.snapshots, [archivedSnapshot])
    }

    func testTimedScheduledCommitRefreshesLiveArchive() async throws {
        let delayedActions = ManualMainActorDelayedActionScheduler()
        let harness = makeCoordinatorHarness(
            delayedActions: delayedActions.scheduler
        )

        harness.coordinator.schedule(
            harness.persistedWindow,
            delayNanoseconds: 10_000_000
        )
        XCTAssertEqual(delayedActions.scheduledDelays, [0.01])
        delayedActions.runNext()

        XCTAssertEqual(
            harness.snapshotStore.loadSnapshot()?.snapshot.currentProfileId,
            harness.persistedWindow.currentProfileId
        )
        XCTAssertEqual(
            harness.historyStore.snapshots.map(\.id),
            [harness.persistedWindow.id, harness.otherOpenWindow.id]
        )
    }

    func testScheduledCoordinatorBatchFlushRefreshesLiveArchiveOnce() {
        let harness = makeCoordinatorHarness()

        harness.coordinator.schedule(
            harness.persistedWindow,
            delayNanoseconds: 60_000_000_000
        )
        harness.coordinator.schedule(
            harness.otherOpenWindow,
            delayNanoseconds: 60_000_000_000
        )
        XCTAssertTrue(harness.historyStore.snapshots.isEmpty)

        XCTAssertEqual(harness.coordinator.flush(), 2)

        XCTAssertTrue(
            [
                harness.persistedWindow.currentProfileId,
                harness.otherOpenWindow.currentProfileId,
            ].contains(
                harness.snapshotStore.loadSnapshot()?.snapshot.currentProfileId
            )
        )
        XCTAssertEqual(
            harness.historyStore.snapshots.map(\.id),
            [harness.persistedWindow.id, harness.otherOpenWindow.id]
        )
    }

    func testImmediatePersistSupersedesEntireScheduledBatch() {
        let harness = makeCoordinatorHarness()

        harness.coordinator.schedule(
            harness.persistedWindow,
            delayNanoseconds: 60_000_000_000
        )
        harness.coordinator.schedule(
            harness.otherOpenWindow,
            delayNanoseconds: 60_000_000_000
        )

        harness.coordinator.persist(harness.persistedWindow)

        XCTAssertEqual(harness.coordinator.flush(), 0)
        XCTAssertEqual(
            harness.snapshotStore.loadSnapshot()?.snapshot.currentProfileId,
            harness.persistedWindow.currentProfileId
        )
        XCTAssertEqual(
            harness.historyStore.snapshots.map(\.id),
            [harness.persistedWindow.id, harness.otherOpenWindow.id]
        )
    }

    func testClosingScheduledWindowCancelsItsWriteAndPersistsSurvivor() {
        let harness = makeCoordinatorHarness()
        let closingProfileID = UUID()
        let survivingProfileID = UUID()
        harness.persistedWindow.currentProfileId = closingProfileID
        harness.otherOpenWindow.currentProfileId = survivingProfileID

        harness.coordinator.schedule(
            harness.persistedWindow,
            delayNanoseconds: 60_000_000_000
        )
        harness.coordinator.persistBeforeClosing(harness.persistedWindow)

        XCTAssertEqual(harness.coordinator.flush(), 0)
        XCTAssertEqual(
            harness.snapshotStore.loadSnapshot()?.snapshot.currentProfileId,
            survivingProfileID
        )
        XCTAssertEqual(
            harness.historyStore.snapshots.map(\.id),
            [harness.otherOpenWindow.id]
        )
    }

    func testClosingSoleRegularWindowPersistsFinalStateBeforeNextCycleClaim() {
        let harness = makeCoordinatorHarness()
        XCTAssertTrue(harness.windows.discardRejectedRegistration(harness.otherOpenWindow))
        harness.persistedWindow.currentProfileId = UUID()
        harness.coordinator.schedule(
            harness.persistedWindow,
            delayNanoseconds: 60_000_000_000
        )
        let finalProfileID = UUID()
        harness.persistedWindow.currentProfileId = finalProfileID

        harness.coordinator.persistBeforeClosing(harness.persistedWindow)
        let cycle = WindowSessionRestoreCycle()
        cycle.reset(store: harness.snapshotStore)
        let restored = cycle.claimSnapshot(
            from: harness.snapshotStore,
            for: BrowserWindowState()
        )

        XCTAssertEqual(restored?.currentProfileId, finalProfileID)
        XCTAssertEqual(harness.coordinator.flush(), 0)
    }

    func testIncognitoCloseCancelsPendingWriteWithoutProjectingArchive() {
        let harness = makeCoordinatorHarness()
        let archivedSnapshot = LastSessionWindowSnapshot(
            id: UUID(),
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )
        harness.historyStore.updateSnapshots([archivedSnapshot])
        harness.coordinator.schedule(
            harness.persistedWindow,
            delayNanoseconds: 60_000_000_000
        )
        harness.persistedWindow.isIncognito = true

        harness.coordinator.persistBeforeClosing(harness.persistedWindow)

        XCTAssertEqual(harness.coordinator.flush(), 0)
        XCTAssertNil(harness.snapshotStore.loadSnapshot())
        XCTAssertEqual(harness.historyStore.snapshots, [archivedSnapshot])
    }

    func testDelayedCommitWithEmptyLiveProjectionPreservesArchive() async throws {
        let delayedActions = ManualMainActorDelayedActionScheduler()
        let harness = makeCoordinatorHarness(
            delayedActions: delayedActions.scheduler
        )
        XCTAssertTrue(harness.windows.discardRejectedRegistration(harness.otherOpenWindow))
        harness.coordinator.persist(harness.persistedWindow)
        let archivedSnapshots = harness.historyStore.snapshots
        harness.coordinator.schedule(
            harness.persistedWindow,
            delayNanoseconds: 10_000_000
        )
        XCTAssertTrue(harness.windows.discardRejectedRegistration(harness.persistedWindow))

        XCTAssertEqual(delayedActions.scheduledDelays, [0.01])
        delayedActions.runNext()

        XCTAssertEqual(harness.historyStore.snapshots, archivedSnapshots)
    }

    func testBrowserTeardownFlushesScheduledWindowPersistenceEndToEnd() throws {
        let snapshotStore = WindowSessionSnapshotStore(
            key: "window-session.\(UUID().uuidString)",
            environment: { [:] }
        )
        var browserManager: BrowserManager? = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupContainer()
            ),
            windowSessionSnapshotStore: snapshotStore
        )
        let windowState = BrowserWindowState()
        browserManager?.tabResidenceAuthority.establishResidenceSession(
            on: windowState
        )
        let persistedProfileID = UUID()
        windowState.currentProfileId = persistedProfileID
        browserManager?.windowSessionPersistenceCoordinator.schedule(
            windowState,
            delayNanoseconds: 60_000_000_000
        )

        weak let releasedBrowserManager = browserManager
        browserManager = nil
        XCTAssertNil(releasedBrowserManager)

        XCTAssertEqual(
            snapshotStore.loadSnapshot()?.snapshot.currentProfileId,
            persistedProfileID
        )
    }

    func testLiveShortcutNavigationSchedulesPerWindowResumeSnapshot() throws {
        let snapshotStore = WindowSessionSnapshotStore(
            key: "window-session-live-shortcut",
            environment: { [:] }
        )
        let browser = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupContainer()
            ),
            windowSessionSnapshotStore: snapshotStore
        )
        let windowState = BrowserWindowState()
        browser.tabResidenceAuthority.establishResidenceSession(
            on: windowState
        )
        browser.windowRegistry.register(windowState)
        let space = try XCTUnwrap(
            browser.sidebarSpaceLifecycle.createSpace(
                name: "Space",
                icon: "square",
                profileID: nil
            )
        )
        windowState.currentSpaceId = space.id
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 0,
            launchURL: try XCTUnwrap(
                URL(string: "https://launcher.example")
            ),
            title: "Launcher"
        )
        browser.structuralCollectionMutationOwner.setSpacePinnedShortcuts(
            [pin],
            for: space.id
        )
        windowState.currentShortcutPinId = pin.id
        XCTAssertTrue(
            WindowSessionShortcutRestorer(
                pins: browser.shortcutPinCollectionStateOwner,
                activation: browser.shortcutPresentationActivation
            ).materializeSelectionIfNeeded(in: windowState)
        )
        let liveTab = try XCTUnwrap(
            browser.liveShortcutTabs.tab(
                for: pin.id,
                in: windowState.id
            )
        )
        let currentURL = try XCTUnwrap(
            URL(string: "https://launcher.example/continued")
        )
        liveTab.url = currentURL

        XCTAssertTrue(
            liveTab.acceptResolvedDisplayTitle("Continued Work")
        )
        XCTAssertEqual(
            browser.windowSessionPersistenceCoordinator.flush(),
            1
        )

        XCTAssertEqual(
            snapshotStore.loadSnapshot()?.snapshot.liveShortcuts,
            [
                ShortcutLiveSessionSnapshot(
                    shortcutPinId: pin.id,
                    presentationSpaceId: space.id,
                    currentURL: currentURL,
                    title: "Continued Work"
                ),
            ]
        )
    }

    private struct CoordinatorHarness {
        let coordinator: WindowSessionPersistenceCoordinator
        let snapshotStore: WindowSessionSnapshotStore
        let historyStore: LastSessionWindowsStore
        let persistedWindow: BrowserWindowState
        let otherOpenWindow: BrowserWindowState
        let windows: WindowRegistry
    }

    private func makeCoordinatorHarness(
        delayedActions: MainActorDelayedActionScheduler = .live
    ) -> CoordinatorHarness {
        let database = try! SumiDatabase.inMemory()
        let snapshotStore = WindowSessionSnapshotStore(
            database: database,
            key: "window-session",
            environment: { [:] }
        )
        let scheduler = WindowSessionPersistenceScheduler(
            delayedActions: delayedActions
        )
        let snapshotFactory = WindowSessionSnapshotFactory(
            glanceManager: GlanceManager()
        )
        let historyStore = LastSessionWindowsStore(database: database)
        let startupRestore = BrowserStartupSessionRestoreOwner(
            lastSessionWindowsStore: historyStore
        )
        startupRestore.markRestoreOfferConsumed()
        let persistedWindow = BrowserWindowState()
        persistedWindow.currentProfileId = UUID()
        let otherOpenWindow = BrowserWindowState()
        otherOpenWindow.currentProfileId = UUID()
        let windows = WindowRegistry()
        windows.register(persistedWindow)
        windows.register(otherOpenWindow)
        let catalog = OpenWindowSessionCatalog(
            windows: windows,
            snapshots: snapshotFactory
        )
        let archive = LastSessionWindowArchive(
            openWindows: catalog,
            lastSessionWindowsStore: historyStore,
            startupRestore: startupRestore
        )
        return CoordinatorHarness(
            coordinator: WindowSessionPersistenceCoordinator(
                snapshotStore: snapshotStore,
                snapshotFactory: snapshotFactory,
                scheduler: scheduler,
                openWindows: catalog,
                archive: archive
            ),
            snapshotStore: snapshotStore,
            historyStore: historyStore,
            persistedWindow: persistedWindow,
            otherOpenWindow: otherOpenWindow,
            windows: windows
        )
    }

    private struct DurableWriteHarness {
        let write: WindowSessionDurableWrite
        let snapshotStore: WindowSessionSnapshotStore
    }

    private func makeDurableWrite(
        windowState: BrowserWindowState
    ) -> DurableWriteHarness {
        let snapshotStore = WindowSessionSnapshotStore(
            key: "window-session.\(UUID().uuidString)",
            environment: { [:] }
        )
        let snapshotFactory = WindowSessionSnapshotFactory(
            glanceManager: GlanceManager()
        )
        return DurableWriteHarness(
            write: WindowSessionDurableWrite(
                windowState: windowState,
                store: snapshotStore,
                snapshotFactory: snapshotFactory
            ),
            snapshotStore: snapshotStore
        )
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "WindowSessionPersistenceSchedulerTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Failed to create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeInMemoryStartupContainer() throws -> SumiDatabase {
        try SumiDatabase.inMemory()
    }
}
