import XCTest

@testable import Sumi

@MainActor
final class StartupWindowRestoreServiceTests: XCTestCase {
    private final class WindowReference {
        var value: BrowserWindowState?

        init(_ value: BrowserWindowState?) {
            self.value = value
        }
    }

    func testPartialFailureKeepsSourceAndRetrySkipsRestoredWindowIDs() async throws {
        let store = try makeIsolatedLastSessionWindowsStore(
            suitePrefix: "StartupWindowRestoreServiceTests"
        )
        let sourceSnapshots = (0..<3).map { _ in
            LastSessionWindowSnapshot(
                id: UUID(),
                session: makeSessionRecoveryWindowSession(currentTabId: UUID())
            )
        }
        store.updateSnapshots(sourceSnapshots)
        let startupRestore = StartupSessionRestoreProviderFake(
            canOfferRestoreShortcut: true,
            windowSnapshots: sourceSnapshots
        )
        let launchWindow = BrowserWindowState()
        var windows = [launchWindow]
        var sessions = [
            launchWindow.id: makeSessionRecoveryWindowSession(currentTabId: UUID()),
        ]
        let catalog = makeCatalog(windows: { windows }, sessions: { sessions })
        let archive = makeArchive(
            catalog: catalog,
            store: store,
            startupRestore: startupRestore
        )
        var reopenResults = [true, false]
        var reopenRequests: [UUID] = []
        let service = StartupWindowRestoreService(
            startupRestore: startupRestore,
            archive: archive,
            openWindows: catalog,
            startupWindow: { launchWindow },
            applySnapshot: { snapshot, window in
                sessions[window.id] = snapshot.session
            },
            reopenWindow: { snapshot in
                reopenRequests.append(snapshot.id)
                let didReopen = reopenResults.removeFirst()
                if didReopen {
                    let window = BrowserWindowState()
                    window.restoredSessionWindowId = snapshot.id
                    windows.append(window)
                    sessions[window.id] = snapshot.session
                }
                return didReopen
            }
        )

        service.restoreIfNeeded()
        archive.refresh(excludingWindowID: nil)
        await service.pendingRestoreTask?.value

        XCTAssertFalse(startupRestore.didConsumeRestoreOffer)
        XCTAssertEqual(store.snapshots, sourceSnapshots)
        archive.refresh(excludingWindowID: nil)
        XCTAssertEqual(store.snapshots, sourceSnapshots)
        XCTAssertEqual(
            reopenRequests,
            [sourceSnapshots[1].id, sourceSnapshots[2].id]
        )

        reopenResults = [true]
        service.restoreIfNeeded()
        await service.pendingRestoreTask?.value

        XCTAssertTrue(startupRestore.didConsumeRestoreOffer)
        XCTAssertEqual(reopenRequests.last, sourceSnapshots[2].id)
        XCTAssertEqual(Set(store.snapshots.map(\.id)), Set(sourceSnapshots.map(\.id)))
    }

    func testBusyArchiveLeaseQueuesOneShotStartupRestoreWithoutPolling() async throws {
        let store = try makeIsolatedLastSessionWindowsStore(
            suitePrefix: "StartupWindowRestoreServiceTests"
        )
        let sourceSnapshot = LastSessionWindowSnapshot(
            id: UUID(),
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )
        store.updateSnapshots([sourceSnapshot])
        let startupRestore = StartupSessionRestoreProviderFake(
            canOfferRestoreShortcut: true,
            windowSnapshots: [sourceSnapshot]
        )
        let launchWindow = BrowserWindowState()
        var sessions = [
            launchWindow.id: makeSessionRecoveryWindowSession(currentTabId: UUID()),
        ]
        let catalog = makeCatalog(
            windows: { [launchWindow] },
            sessions: { sessions }
        )
        let archive = makeArchive(
            catalog: catalog,
            store: store,
            startupRestore: startupRestore
        )
        let blockingAttempt = try XCTUnwrap(archive.beginRestoreAttempt())
        var appliedSnapshotIDs: [UUID] = []
        var appliedWindow: BrowserWindowState?
        let startupWindow = WindowReference(launchWindow)
        let service = StartupWindowRestoreService(
            startupRestore: startupRestore,
            archive: archive,
            openWindows: catalog,
            startupWindow: { startupWindow.value },
            applySnapshot: { snapshot, window in
                appliedSnapshotIDs.append(snapshot.id)
                appliedWindow = window
                sessions[window.id] = snapshot.session
            },
            reopenWindow: { _ in
                XCTFail("Launch window should receive the only snapshot")
                return false
            }
        )

        service.restoreIfNeeded()
        startupWindow.value = BrowserWindowState()
        await Task.yield()
        XCTAssertTrue(appliedSnapshotIDs.isEmpty)
        XCTAssertFalse(startupRestore.didConsumeRestoreOffer)

        archive.finishRestoreAttempt(blockingAttempt, outcome: .interrupted)
        await service.pendingRestoreTask?.value

        XCTAssertEqual(appliedSnapshotIDs, [sourceSnapshot.id])
        XCTAssertIdentical(appliedWindow, launchWindow)
        XCTAssertTrue(startupRestore.didConsumeRestoreOffer)
        XCTAssertEqual(store.snapshots.map(\.id), [sourceSnapshot.id])
    }

    func testDeinitCancelsActiveRestoreAndReleasesArchiveLease() async throws {
        let store = try makeIsolatedLastSessionWindowsStore(
            suitePrefix: "StartupWindowRestoreServiceTests"
        )
        let sourceSnapshot = LastSessionWindowSnapshot(
            id: UUID(),
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )
        let startupRestore = StartupSessionRestoreProviderFake(
            canOfferRestoreShortcut: true,
            windowSnapshots: [sourceSnapshot]
        )
        let catalog = makeCatalog(windows: { [] }, sessions: { [:] })
        let archive = makeArchive(
            catalog: catalog,
            store: store,
            startupRestore: startupRestore
        )
        var didEnterReopen = false
        var service: StartupWindowRestoreService? = StartupWindowRestoreService(
            startupRestore: startupRestore,
            archive: archive,
            openWindows: catalog,
            startupWindow: { nil },
            applySnapshot: { _, _ in
                XCTFail("No launch window is available")
            },
            reopenWindow: { _ in
                didEnterReopen = true
                let clock = ContinuousClock()
                let deadline = clock.now.advanced(by: .seconds(2))
                while Task.isCancelled == false, clock.now < deadline {
                    await Task.yield()
                }
                return false
            }
        )
        weak let releasedService = service

        service?.restoreIfNeeded()
        let restoreTask = try XCTUnwrap(service?.pendingRestoreTask)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while didEnterReopen == false, clock.now < deadline {
            await Task.yield()
        }
        guard didEnterReopen else {
            service = nil
            await restoreTask.value
            return XCTFail("Startup restore never reached the reopen gate")
        }
        service = nil
        await restoreTask.value

        XCTAssertNil(releasedService)
        let nextAttempt = try XCTUnwrap(archive.beginRestoreAttempt())
        archive.finishRestoreAttempt(nextAttempt, outcome: .interrupted)
    }

    func testQueuedRestoreReopensSnapshotWhenCapturedLaunchWindowClosed() async throws {
        let store = try makeIsolatedLastSessionWindowsStore(
            suitePrefix: "StartupWindowRestoreServiceTests"
        )
        let sourceSnapshot = LastSessionWindowSnapshot(
            id: UUID(),
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )
        store.updateSnapshots([sourceSnapshot])
        let startupRestore = StartupSessionRestoreProviderFake(
            canOfferRestoreShortcut: true,
            windowSnapshots: [sourceSnapshot]
        )
        let launchWindow = BrowserWindowState()
        var windows = [launchWindow]
        var sessions = [
            launchWindow.id: makeSessionRecoveryWindowSession(currentTabId: UUID()),
        ]
        let catalog = makeCatalog(windows: { windows }, sessions: { sessions })
        let archive = makeArchive(
            catalog: catalog,
            store: store,
            startupRestore: startupRestore
        )
        let blockingAttempt = try XCTUnwrap(archive.beginRestoreAttempt())
        var didApplyToClosedLaunchWindow = false
        var reopenRequests: [UUID] = []
        let service = StartupWindowRestoreService(
            startupRestore: startupRestore,
            archive: archive,
            openWindows: catalog,
            startupWindow: { launchWindow },
            applySnapshot: { _, _ in
                didApplyToClosedLaunchWindow = true
            },
            reopenWindow: { snapshot in
                reopenRequests.append(snapshot.id)
                let restoredWindow = BrowserWindowState()
                restoredWindow.restoredSessionWindowId = snapshot.id
                windows.append(restoredWindow)
                sessions[restoredWindow.id] = snapshot.session
                return true
            }
        )

        service.restoreIfNeeded()
        windows.removeAll()
        sessions.removeAll()
        archive.finishRestoreAttempt(blockingAttempt, outcome: .interrupted)
        await service.pendingRestoreTask?.value

        XCTAssertFalse(didApplyToClosedLaunchWindow)
        XCTAssertEqual(reopenRequests, [sourceSnapshot.id])
        XCTAssertTrue(startupRestore.didConsumeRestoreOffer)
        XCTAssertEqual(store.snapshots, [sourceSnapshot])
    }

    func testDeinitCancelsQueuedRestoreAndPassesLeaseToNextAttempt() async throws {
        let store = try makeIsolatedLastSessionWindowsStore(
            suitePrefix: "StartupWindowRestoreServiceTests"
        )
        let sourceSnapshot = LastSessionWindowSnapshot(
            id: UUID(),
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )
        let startupRestore = StartupSessionRestoreProviderFake(
            canOfferRestoreShortcut: true,
            windowSnapshots: [sourceSnapshot]
        )
        let catalog = makeCatalog(windows: { [] }, sessions: { [:] })
        let archive = makeArchive(
            catalog: catalog,
            store: store,
            startupRestore: startupRestore
        )
        let blockingAttempt = try XCTUnwrap(archive.beginRestoreAttempt())
        var service: StartupWindowRestoreService? = StartupWindowRestoreService(
            startupRestore: startupRestore,
            archive: archive,
            openWindows: catalog,
            startupWindow: { nil },
            applySnapshot: { _, _ in
                XCTFail("Cancelled queued restore must not apply a snapshot")
            },
            reopenWindow: { _ in
                XCTFail("Cancelled queued restore must not create a window")
                return false
            }
        )

        service?.restoreIfNeeded()
        let restoreTask = try XCTUnwrap(service?.pendingRestoreTask)
        await Task.yield()
        service = nil
        archive.finishRestoreAttempt(blockingAttempt, outcome: .interrupted)
        await restoreTask.value

        let nextAttempt = try XCTUnwrap(archive.beginRestoreAttempt())
        archive.finishRestoreAttempt(nextAttempt, outcome: .interrupted)
        XCTAssertFalse(startupRestore.didConsumeRestoreOffer)
    }

    private func makeCatalog(
        windows: @escaping @MainActor () -> [BrowserWindowState],
        sessions: @escaping @MainActor () -> [UUID: WindowSessionSnapshot]
    ) -> OpenWindowSessionCatalog {
        OpenWindowSessionCatalog(
            allWindows: windows,
            makeWindowSessionSnapshot: { sessions()[$0.id] }
        )
    }

    private func makeArchive(
        catalog: OpenWindowSessionCatalog,
        store: LastSessionWindowsStore,
        startupRestore: StartupSessionRestoreProviderFake
    ) -> LastSessionWindowArchive {
        LastSessionWindowArchive(
            openWindows: catalog,
            lastSessionWindowsStore: { store },
            startupRestore: startupRestore
        )
    }
}
