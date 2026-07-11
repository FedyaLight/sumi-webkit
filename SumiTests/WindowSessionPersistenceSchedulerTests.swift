import Foundation
import SwiftData
import XCTest

@testable import Sumi

/// Ownership coverage for window-session persistence teardown: a bare
/// scheduler cancels its work on deinit, while BrowserManager explicitly
/// flushes requests already accepted by its process-lifetime scheduler.
@MainActor
final class WindowSessionPersistenceSchedulerTests: XCTestCase {
    func testSchedulerDeinitCancelsPendingPersistence() async throws {
        var scheduler: WindowSessionPersistenceScheduler? =
            WindowSessionPersistenceScheduler()
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
        try await Task.sleep(nanoseconds: 200_000_000)

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
        XCTAssertEqual(harness.observation.catalogReadCount, 1)
        XCTAssertEqual(harness.observation.archiveWriteCount, 1)
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
        XCTAssertEqual(harness.observation.catalogReadCount, 0)
        XCTAssertEqual(harness.observation.archiveWriteCount, 0)
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
        XCTAssertEqual(harness.observation.catalogReadCount, 0)
        XCTAssertEqual(harness.observation.archiveWriteCount, 0)
    }

    func testTimedScheduledCommitInvokesLiveArchiveRefreshOnce() async throws {
        let harness = makeCoordinatorHarness()

        harness.coordinator.schedule(
            harness.persistedWindow,
            delayNanoseconds: 10_000_000
        )
        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertEqual(
            harness.snapshotStore.loadSnapshot()?.snapshot.currentProfileId,
            harness.persistedWindow.currentProfileId
        )
        XCTAssertEqual(harness.observation.catalogReadCount, 1)
        XCTAssertEqual(harness.observation.archiveWriteCount, 1)
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
        XCTAssertEqual(harness.observation.catalogReadCount, 1)
        XCTAssertEqual(harness.observation.archiveWriteCount, 1)
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
        harness.observation.windows = [harness.persistedWindow]
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
        XCTAssertEqual(harness.observation.catalogReadCount, 0)
        XCTAssertEqual(harness.observation.archiveWriteCount, 0)
    }

    func testDelayedCommitWithEmptyLiveProjectionPreservesArchive() async throws {
        let harness = makeCoordinatorHarness()
        harness.observation.windows = [harness.persistedWindow]
        harness.coordinator.persist(harness.persistedWindow)
        let archivedSnapshots = harness.historyStore.snapshots
        harness.coordinator.schedule(
            harness.persistedWindow,
            delayNanoseconds: 10_000_000
        )
        harness.observation.windows = []

        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertEqual(harness.historyStore.snapshots, archivedSnapshots)
        XCTAssertEqual(harness.observation.archiveWriteCount, 1)
    }

    func testBrowserTeardownFlushesScheduledWindowPersistenceEndToEnd() throws {
        let defaults = makeUserDefaults()
        let snapshotStore = WindowSessionSnapshotStore(
            key: "window-session",
            userDefaults: defaults,
            environment: { [:] }
        )
        var browserManager: BrowserManager? = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupContainer()
            ),
            windowSessionSnapshotStore: snapshotStore
        )
        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager?.tabManager
        let persistedProfileID = UUID()
        windowState.currentProfileId = persistedProfileID
        browserManager?.windowSessionBundle.persistence.schedule(
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

    private struct CoordinatorHarness {
        let coordinator: WindowSessionPersistenceCoordinator
        let snapshotStore: WindowSessionSnapshotStore
        let historyStore: LastSessionWindowsStore
        let persistedWindow: BrowserWindowState
        let otherOpenWindow: BrowserWindowState
        let observation: PersistenceObservation
    }

    private final class PersistenceObservation {
        var catalogReadCount = 0
        var archiveWriteCount = 0
        var windows: [BrowserWindowState] = []
    }

    private func makeCoordinatorHarness() -> CoordinatorHarness {
        let defaults = makeUserDefaults()
        let snapshotStore = WindowSessionSnapshotStore(
            key: "window-session",
            userDefaults: defaults,
            environment: { [:] }
        )
        let scheduler = WindowSessionPersistenceScheduler()
        let snapshotFactory = WindowSessionSnapshotFactory(
            splitManager: SplitViewManager(),
            glanceManager: GlanceManager()
        )
        let historyStore = LastSessionWindowsStore(userDefaults: defaults)
        let startupRestore = BrowserStartupSessionRestoreOwner(
            lastSessionWindowsStore: historyStore
        )
        startupRestore.markRestoreOfferConsumed()
        let persistedWindow = BrowserWindowState()
        persistedWindow.currentProfileId = UUID()
        let otherOpenWindow = BrowserWindowState()
        otherOpenWindow.currentProfileId = UUID()
        let observation = PersistenceObservation()
        observation.windows = [persistedWindow, otherOpenWindow]
        let catalog = OpenWindowSessionCatalog(
            allWindows: {
                observation.catalogReadCount += 1
                return observation.windows
            },
            makeWindowSessionSnapshot: snapshotFactory.make
        )
        let archive = LastSessionWindowArchive(
            openWindows: catalog,
            lastSessionWindowsStore: {
                observation.archiveWriteCount += 1
                return historyStore
            },
            startupRestore: startupRestore
        )
        return CoordinatorHarness(
            coordinator: WindowSessionPersistenceCoordinator(
                persistence: WindowSessionPersistenceService(
                    store: snapshotStore,
                    snapshotFactory: snapshotFactory
                ),
                scheduler: scheduler,
                openWindows: catalog,
                archive: archive
            ),
            snapshotStore: snapshotStore,
            historyStore: historyStore,
            persistedWindow: persistedWindow,
            otherOpenWindow: otherOpenWindow,
            observation: observation
        )
    }

    private struct DurableWriteHarness {
        let write: WindowSessionDurableWrite
        let snapshotStore: WindowSessionSnapshotStore
    }

    private func makeDurableWrite(
        windowState: BrowserWindowState
    ) -> DurableWriteHarness {
        let defaults = makeUserDefaults()
        let snapshotStore = WindowSessionSnapshotStore(
            key: "window-session",
            userDefaults: defaults,
            environment: { [:] }
        )
        let snapshotFactory = WindowSessionSnapshotFactory(
            splitManager: SplitViewManager(),
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

    private func makeInMemoryStartupContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }
}
