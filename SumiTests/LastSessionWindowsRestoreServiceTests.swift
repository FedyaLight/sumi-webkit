import XCTest

@testable import Sumi

@MainActor
final class LastSessionWindowsRestoreServiceTests: XCTestCase {
    private enum Event: Equatable {
        case mergeTabSnapshot
        case reopen
        case archiveRefresh
    }

    func testReopenAllUsesStartupArchiveMergesTabSnapshotOnceSkipsOpenSessionsAndRefreshesArchive() async throws {
        let store = try makeIsolatedLastSessionWindowsStore(suitePrefix: "LastSessionWindowsRestoreServiceTests")
        let existingSnapshot = LastSessionWindowSnapshot(
            id: UUID(),
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )
        let snapshotToRestore = LastSessionWindowSnapshot(
            id: UUID(),
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )
        let startupTabSnapshot = TabPersistenceSnapshot(
            spaces: [],
            tabs: [],
            folders: [],
            state: TabPersistenceSelection(currentTabID: nil, currentSpaceID: nil)
        )
        let startupRestore = StartupSessionRestoreProviderFake(
            canOfferRestoreShortcut: true,
            windowSnapshots: [existingSnapshot, snapshotToRestore],
            tabSnapshot: startupTabSnapshot
        )
        var events: [Event] = []
        let windowReopen = WindowSessionReopenerFake()
        windowReopen.onReopen = { events.append(.reopen) }
        let openWindows = makeOpenWindows { [existingSnapshot] }
        // In this scenario every archive *read* is satisfied by the startup
        // provider, so the store closure fires exactly once per refresh and
        // doubles as the refresh-ordering observation point.
        let archive = LastSessionWindowArchive(
            openWindows: openWindows,
            lastSessionWindowsStore: {
                events.append(.archiveRefresh)
                return store
            },
            startupRestore: startupRestore
        )
        let service = LastSessionWindowsRestoreService(
            startupRestore: startupRestore,
            archive: archive,
            openWindows: openWindows,
            mergeLastSessionTabSnapshot: { _ in events.append(.mergeTabSnapshot) },
            windowReopen: windowReopen
        )

        XCTAssertTrue(service.canOfferStartupSessionRestoreShortcut)
        XCTAssertTrue(service.canRestoreAnyLastSession)

        service.reopenAllWindowsFromLastSession()
        XCTAssertFalse(startupRestore.didConsumeRestoreOffer)

        await service.pendingRestoreTask?.value

        XCTAssertTrue(startupRestore.didConsumeRestoreOffer)
        XCTAssertEqual(events, [.mergeTabSnapshot, .reopen, .archiveRefresh])
        XCTAssertEqual(windowReopen.reopenedSessions, [snapshotToRestore.session])
        XCTAssertEqual(store.snapshots.map(\.session), [existingSnapshot.session])
        XCTAssertNil(service.pendingRestoreTask)
    }

    func testReopenAllFallsBackToPersistedArchiveWhenStartupArchiveCannotOffer() async throws {
        let store = try makeIsolatedLastSessionWindowsStore(suitePrefix: "LastSessionWindowsRestoreServiceTests")
        let storedSnapshot = LastSessionWindowSnapshot(
            id: UUID(),
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )
        store.updateSnapshots([storedSnapshot])
        let startupRestore = StartupSessionRestoreProviderFake(
            canOfferRestoreShortcut: false,
            windowSnapshots: [
                LastSessionWindowSnapshot(
                    id: UUID(),
                    session: makeSessionRecoveryWindowSession(currentTabId: UUID())
                ),
            ]
        )
        let windowReopen = WindowSessionReopenerFake()
        var didMergeTabSnapshot = false
        let openWindows = makeOpenWindows { [] }
        let service = LastSessionWindowsRestoreService(
            startupRestore: startupRestore,
            archive: makeArchive(openWindows: openWindows, store: store, startupRestore: startupRestore),
            openWindows: openWindows,
            mergeLastSessionTabSnapshot: { _ in didMergeTabSnapshot = true },
            windowReopen: windowReopen
        )

        XCTAssertFalse(service.canOfferStartupSessionRestoreShortcut)
        XCTAssertTrue(service.canRestoreAnyLastSession)

        service.reopenAllWindowsFromLastSession()
        await service.pendingRestoreTask?.value

        XCTAssertEqual(windowReopen.reopenedSessions, [storedSnapshot.session])
        XCTAssertFalse(didMergeTabSnapshot)
    }

    func testReopenAllFinalizesStartupOfferWhenEverySessionIsAlreadyOpen() async throws {
        let store = try makeIsolatedLastSessionWindowsStore(suitePrefix: "LastSessionWindowsRestoreServiceTests")
        let openSnapshot = LastSessionWindowSnapshot(
            id: UUID(),
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )
        let startupRestore = StartupSessionRestoreProviderFake(
            canOfferRestoreShortcut: true,
            windowSnapshots: [openSnapshot]
        )
        let windowReopen = WindowSessionReopenerFake()
        let openWindows = makeOpenWindows { [openSnapshot] }
        let service = LastSessionWindowsRestoreService(
            startupRestore: startupRestore,
            archive: makeArchive(openWindows: openWindows, store: store, startupRestore: startupRestore),
            openWindows: openWindows,
            mergeLastSessionTabSnapshot: { _ in
                XCTFail("Tab snapshot must not merge when nothing is restored")
            },
            windowReopen: windowReopen
        )

        XCTAssertFalse(service.canOfferStartupSessionRestoreShortcut)
        XCTAssertFalse(service.canRestoreAnyLastSession)

        service.reopenAllWindowsFromLastSession()
        await service.pendingRestoreTask?.value

        XCTAssertTrue(windowReopen.reopenedSessions.isEmpty)
        XCTAssertTrue(startupRestore.didConsumeRestoreOffer)
        XCTAssertEqual(store.snapshots.map(\.session), [openSnapshot.session])
        XCTAssertNil(service.pendingRestoreTask)
    }

    func testFailedReopenKeepsStartupOfferAndDoesNotOverwriteRetryArchive() async throws {
        let store = try makeIsolatedLastSessionWindowsStore(suitePrefix: "LastSessionWindowsRestoreServiceTests")
        let retrySentinel = LastSessionWindowSnapshot(
            id: UUID(),
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )
        store.updateSnapshots([retrySentinel])
        let snapshot = LastSessionWindowSnapshot(
            id: UUID(),
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )
        let startupRestore = StartupSessionRestoreProviderFake(
            canOfferRestoreShortcut: true,
            windowSnapshots: [snapshot]
        )
        let windowReopen = WindowSessionReopenerFake(reopenResult: false)
        let openWindows = makeOpenWindows { [] }
        let service = LastSessionWindowsRestoreService(
            startupRestore: startupRestore,
            archive: makeArchive(openWindows: openWindows, store: store, startupRestore: startupRestore),
            openWindows: openWindows,
            mergeLastSessionTabSnapshot: { _ in /* No-op. */ },
            windowReopen: windowReopen
        )

        service.reopenAllWindowsFromLastSession()
        await service.pendingRestoreTask?.value

        XCTAssertFalse(startupRestore.didConsumeRestoreOffer)
        XCTAssertEqual(store.snapshots, [retrySentinel])
        XCTAssertEqual(windowReopen.reopenedSessions, [snapshot.session])
    }

    func testPartialFailureKeepsArchiveAvailableForRetry() async throws {
        let store = try makeIsolatedLastSessionWindowsStore(suitePrefix: "LastSessionWindowsRestoreServiceTests")
        let retrySentinel = LastSessionWindowSnapshot(
            id: UUID(),
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )
        store.updateSnapshots([retrySentinel])
        let snapshots = [
            LastSessionWindowSnapshot(
                id: UUID(),
                session: makeSessionRecoveryWindowSession(currentTabId: UUID())
            ),
            LastSessionWindowSnapshot(
                id: UUID(),
                session: makeSessionRecoveryWindowSession(currentTabId: UUID())
            ),
        ]
        let startupRestore = StartupSessionRestoreProviderFake(
            canOfferRestoreShortcut: true,
            windowSnapshots: snapshots
        )
        let windowReopen = WindowSessionReopenerFake()
        windowReopen.reopenResults = [true, false]
        let openWindows = makeOpenWindows { [] }
        let service = LastSessionWindowsRestoreService(
            startupRestore: startupRestore,
            archive: makeArchive(openWindows: openWindows, store: store, startupRestore: startupRestore),
            openWindows: openWindows,
            mergeLastSessionTabSnapshot: { _ in /* No-op. */ },
            windowReopen: windowReopen
        )

        service.reopenAllWindowsFromLastSession()
        await service.pendingRestoreTask?.value

        XCTAssertFalse(startupRestore.didConsumeRestoreOffer)
        XCTAssertEqual(store.snapshots, [retrySentinel])
        XCTAssertEqual(windowReopen.reopenedSessions, snapshots.map(\.session))
    }

    func testMutatedRestoredWindowRemainsOpenByStableArchiveIdentity() async throws {
        let store = try makeIsolatedLastSessionWindowsStore(
            suitePrefix: "LastSessionWindowsRestoreServiceTests"
        )
        let archived = LastSessionWindowSnapshot(
            id: UUID(),
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )
        let mutatedOpenWindow = LastSessionWindowSnapshot(
            id: archived.id,
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )
        store.updateSnapshots([archived])
        let startupRestore = StartupSessionRestoreProviderFake()
        let openWindows = makeOpenWindows { [mutatedOpenWindow] }
        let windowReopen = WindowSessionReopenerFake()
        let service = LastSessionWindowsRestoreService(
            startupRestore: startupRestore,
            archive: makeArchive(
                openWindows: openWindows,
                store: store,
                startupRestore: startupRestore
            ),
            openWindows: openWindows,
            mergeLastSessionTabSnapshot: { _ in /* No-op. */ },
            windowReopen: windowReopen
        )

        XCTAssertFalse(service.canRestoreAnyLastSession)
        service.reopenAllWindowsFromLastSession()
        await service.pendingRestoreTask?.value

        XCTAssertTrue(windowReopen.reopenedSnapshots.isEmpty)
        XCTAssertEqual(store.snapshots, [mutatedOpenWindow])
    }

    func testDifferentWindowIdentitiesWithSameSessionBothRestore() async throws {
        let store = try makeIsolatedLastSessionWindowsStore(
            suitePrefix: "LastSessionWindowsRestoreServiceTests"
        )
        let sharedSession = makeSessionRecoveryWindowSession(currentTabId: UUID())
        let snapshots = [
            LastSessionWindowSnapshot(id: UUID(), session: sharedSession),
            LastSessionWindowSnapshot(id: UUID(), session: sharedSession),
        ]
        store.updateSnapshots(snapshots)
        let startupRestore = StartupSessionRestoreProviderFake()
        let openWindows = makeOpenWindows { [] }
        let windowReopen = WindowSessionReopenerFake()
        let service = LastSessionWindowsRestoreService(
            startupRestore: startupRestore,
            archive: makeArchive(
                openWindows: openWindows,
                store: store,
                startupRestore: startupRestore
            ),
            openWindows: openWindows,
            mergeLastSessionTabSnapshot: { _ in /* No-op. */ },
            windowReopen: windowReopen
        )

        service.reopenAllWindowsFromLastSession()
        await service.pendingRestoreTask?.value

        XCTAssertEqual(windowReopen.reopenedSnapshots, snapshots)
    }

    func testPersistedPartialFailurePreservesSourceAcrossLiveRefreshAndRetriesOnlyMissingWindow() async throws {
        let store = try makeIsolatedLastSessionWindowsStore(
            suitePrefix: "LastSessionWindowsRestoreServiceTests"
        )
        let snapshots = [
            LastSessionWindowSnapshot(
                id: UUID(),
                session: makeSessionRecoveryWindowSession(currentTabId: UUID())
            ),
            LastSessionWindowSnapshot(
                id: UUID(),
                session: makeSessionRecoveryWindowSession(currentTabId: UUID())
            ),
        ]
        let mutatedFirstWindow = LastSessionWindowSnapshot(
            id: snapshots[0].id,
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )
        store.updateSnapshots(snapshots)
        let startupRestore = StartupSessionRestoreProviderFake()
        var openSnapshots: [LastSessionWindowSnapshot] = []
        let openWindows = makeOpenWindows { openSnapshots }
        let archive = makeArchive(
            openWindows: openWindows,
            store: store,
            startupRestore: startupRestore
        )
        let windowReopen = WindowSessionReopenerFake()
        windowReopen.reopenResults = [true, false, true]
        var reopenCall = 0
        windowReopen.onReopen = {
            defer { reopenCall += 1 }
            if reopenCall == 0 {
                openSnapshots.append(mutatedFirstWindow)
            } else if reopenCall == 2 {
                openSnapshots.append(snapshots[1])
            }
            archive.refresh(excludingWindowID: nil)
        }
        let service = LastSessionWindowsRestoreService(
            startupRestore: startupRestore,
            archive: archive,
            openWindows: openWindows,
            mergeLastSessionTabSnapshot: { _ in /* No-op. */ },
            windowReopen: windowReopen
        )

        service.reopenAllWindowsFromLastSession()
        await service.pendingRestoreTask?.value

        XCTAssertEqual(store.snapshots.map(\.session), snapshots.map(\.session))
        XCTAssertEqual(windowReopen.reopenedSessions, snapshots.map(\.session))
        XCTAssertTrue(service.canRestoreAnyLastSession)

        service.reopenAllWindowsFromLastSession()
        await service.pendingRestoreTask?.value

        XCTAssertEqual(
            windowReopen.reopenedSnapshots,
            [snapshots[0], snapshots[1], snapshots[1]]
        )
        XCTAssertEqual(store.snapshots.map(\.id), snapshots.map(\.id))
        XCTAssertEqual(store.snapshots.first?.session, mutatedFirstWindow.session)
        XCTAssertFalse(service.canRestoreAnyLastSession)
    }

    func testSuccessfulBatchDefersLiveRefreshUntilEveryWindowReopens() async throws {
        let store = try makeIsolatedLastSessionWindowsStore(
            suitePrefix: "LastSessionWindowsRestoreServiceTests"
        )
        let snapshots = [
            LastSessionWindowSnapshot(
                id: UUID(),
                session: makeSessionRecoveryWindowSession(currentTabId: UUID())
            ),
            LastSessionWindowSnapshot(
                id: UUID(),
                session: makeSessionRecoveryWindowSession(currentTabId: UUID())
            ),
        ]
        store.updateSnapshots(snapshots)
        let startupRestore = StartupSessionRestoreProviderFake()
        var openSnapshots: [LastSessionWindowSnapshot] = []
        let openWindows = makeOpenWindows { openSnapshots }
        let archive = makeArchive(
            openWindows: openWindows,
            store: store,
            startupRestore: startupRestore
        )
        let windowReopen = WindowSessionReopenerFake()
        var archivedSessionsObservedDuringReopen: [[WindowSessionSnapshot]] = []
        var reopenIndex = 0
        windowReopen.onReopen = {
            openSnapshots.append(snapshots[reopenIndex])
            reopenIndex += 1
            archive.refresh(excludingWindowID: nil)
            archivedSessionsObservedDuringReopen.append(store.snapshots.map(\.session))
        }
        let service = LastSessionWindowsRestoreService(
            startupRestore: startupRestore,
            archive: archive,
            openWindows: openWindows,
            mergeLastSessionTabSnapshot: { _ in /* No-op. */ },
            windowReopen: windowReopen
        )

        service.reopenAllWindowsFromLastSession()
        await service.pendingRestoreTask?.value

        XCTAssertEqual(
            archivedSessionsObservedDuringReopen,
            [snapshots.map(\.session), snapshots.map(\.session)]
        )
        XCTAssertEqual(store.snapshots.map(\.session), snapshots.map(\.session))
        XCTAssertFalse(service.canRestoreAnyLastSession)
    }

    func testCancelledBatchKeepsRetryArchiveDespiteLiveRefresh() async throws {
        let store = try makeIsolatedLastSessionWindowsStore(
            suitePrefix: "LastSessionWindowsRestoreServiceTests"
        )
        let snapshots = [
            LastSessionWindowSnapshot(
                id: UUID(),
                session: makeSessionRecoveryWindowSession(currentTabId: UUID())
            ),
            LastSessionWindowSnapshot(
                id: UUID(),
                session: makeSessionRecoveryWindowSession(currentTabId: UUID())
            ),
        ]
        store.updateSnapshots(snapshots)
        let startupRestore = StartupSessionRestoreProviderFake()
        var openSnapshots: [LastSessionWindowSnapshot] = []
        let openWindows = makeOpenWindows { openSnapshots }
        let archive = makeArchive(
            openWindows: openWindows,
            store: store,
            startupRestore: startupRestore
        )
        let windowReopen = WindowSessionReopenerFake()
        var didReachReopenGate = false
        var releaseReopen: CheckedContinuation<Void, Never>?
        windowReopen.onReopen = {
            openSnapshots.append(snapshots[0])
            archive.refresh(excludingWindowID: nil)
            didReachReopenGate = true
            await withCheckedContinuation { continuation in
                releaseReopen = continuation
            }
        }
        let service = LastSessionWindowsRestoreService(
            startupRestore: startupRestore,
            archive: archive,
            openWindows: openWindows,
            mergeLastSessionTabSnapshot: { _ in /* No-op. */ },
            windowReopen: windowReopen
        )

        service.reopenAllWindowsFromLastSession()
        let restoreTask = try XCTUnwrap(service.pendingRestoreTask)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while didReachReopenGate == false, clock.now < deadline {
            await Task.yield()
        }
        guard didReachReopenGate else {
            restoreTask.cancel()
            return XCTFail("Restore never reached the gated window reopen")
        }
        XCTAssertEqual(store.snapshots.map(\.session), snapshots.map(\.session))

        restoreTask.cancel()
        releaseReopen?.resume()
        await restoreTask.value

        XCTAssertEqual(windowReopen.reopenedSessions, [snapshots[0].session])
        XCTAssertEqual(store.snapshots.map(\.session), snapshots.map(\.session))
        XCTAssertTrue(service.canRestoreAnyLastSession)
        XCTAssertNil(service.pendingRestoreTask)
    }

    func testRepeatedCommandDoesNotStartDuplicateRestoreBatch() async throws {
        let store = try makeIsolatedLastSessionWindowsStore(suitePrefix: "LastSessionWindowsRestoreServiceTests")
        let snapshot = LastSessionWindowSnapshot(
            id: UUID(),
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )
        let startupRestore = StartupSessionRestoreProviderFake(
            canOfferRestoreShortcut: true,
            windowSnapshots: [snapshot],
            tabSnapshot: TabPersistenceSnapshot(
                spaces: [],
                tabs: [],
                folders: [],
                state: TabPersistenceSelection(currentTabID: nil, currentSpaceID: nil)
            )
        )
        let windowReopen = WindowSessionReopenerFake()
        windowReopen.onReopen = { await Task.yield() }
        var mergeCount = 0
        let openWindows = makeOpenWindows { [] }
        let service = LastSessionWindowsRestoreService(
            startupRestore: startupRestore,
            archive: makeArchive(openWindows: openWindows, store: store, startupRestore: startupRestore),
            openWindows: openWindows,
            mergeLastSessionTabSnapshot: { _ in mergeCount += 1 },
            windowReopen: windowReopen
        )

        service.reopenAllWindowsFromLastSession()
        let pendingTask = service.pendingRestoreTask
        service.reopenAllWindowsFromLastSession()
        await pendingTask?.value

        XCTAssertEqual(mergeCount, 1)
        XCTAssertEqual(windowReopen.reopenedSessions, [snapshot.session])
    }

    /// Builds a catalog whose view of open windows is driven by the test.
    private func makeOpenWindows(
        _ openSessions: @escaping @MainActor () -> [LastSessionWindowSnapshot]
    ) -> OpenWindowSessionCatalog {
        var sessionsByWindowId: [UUID: WindowSessionSnapshot] = [:]
        return OpenWindowSessionCatalog(
            allWindows: {
                openSessions().map { snapshot in
                    let windowState = BrowserWindowState()
                    windowState.restoredSessionWindowId = snapshot.id
                    sessionsByWindowId[windowState.id] = snapshot.session
                    return windowState
                }
            },
            makeWindowSessionSnapshot: { sessionsByWindowId[$0.id] }
        )
    }

    private func makeArchive(
        openWindows: OpenWindowSessionCatalog,
        store: LastSessionWindowsStore,
        startupRestore: StartupSessionRestoreProviderFake
    ) -> LastSessionWindowArchive {
        LastSessionWindowArchive(
            openWindows: openWindows,
            lastSessionWindowsStore: { store },
            startupRestore: startupRestore
        )
    }
}
