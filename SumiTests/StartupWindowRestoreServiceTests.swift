import XCTest

@testable import Sumi

@MainActor
final class StartupWindowRestoreServiceTests: XCTestCase {
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
        let browser = BrowserManager()
        let windows = browser.windowRegistry
        let launchWindow = BrowserWindowState()
        windows.register(launchWindow)
        let catalog = makeCatalog(windows: windows)
        let archive = makeArchive(
            catalog: catalog,
            store: store,
            startupRestore: startupRestore
        )
        let windowReopen = WindowSessionReopenerFake()
        windowReopen.reopenResults = [true, false]
        windowReopen.onReopen = {
            guard windowReopen.reopenedSnapshots.count == 1,
                  let restored = windowReopen.reopenedSnapshots.last else { return }
            let window = BrowserWindowState()
            WindowSessionSnapshotApplier(glanceManager: GlanceManager())
                .prepareForRegistration(restored.session, to: window)
            window.restorationState.restoredSessionWindowID = restored.id
            windows.register(window)
        }
        let service = StartupWindowRestoreService(
            startupRestore: startupRestore,
            archive: archive,
            openWindows: catalog,
            restoration: browser.windowSessionBundle.restoreService,
            windowReopen: windowReopen
        )

        service.restoreIfNeeded()
        archive.refresh(excludingWindowID: nil)
        await service.pendingRestoreTask?.value

        XCTAssertFalse(startupRestore.didConsumeRestoreOffer)
        XCTAssertEqual(store.snapshots, sourceSnapshots)
        archive.refresh(excludingWindowID: nil)
        XCTAssertEqual(store.snapshots, sourceSnapshots)
        XCTAssertEqual(
            windowReopen.reopenedSnapshots.map(\.id),
            [sourceSnapshots[1].id, sourceSnapshots[2].id]
        )

        windowReopen.reopenResults = [true]
        windowReopen.onReopen = {
            guard let restored = windowReopen.reopenedSnapshots.last else { return }
            let window = BrowserWindowState()
            WindowSessionSnapshotApplier(glanceManager: GlanceManager())
                .prepareForRegistration(restored.session, to: window)
            window.restorationState.restoredSessionWindowID = restored.id
            windows.register(window)
        }
        service.restoreIfNeeded()
        await service.pendingRestoreTask?.value

        XCTAssertTrue(startupRestore.didConsumeRestoreOffer)
        XCTAssertEqual(windowReopen.reopenedSnapshots.last?.id, sourceSnapshots[2].id)
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
        let browser = BrowserManager()
        let windows = browser.windowRegistry
        let launchWindow = BrowserWindowState()
        windows.register(launchWindow)
        let catalog = makeCatalog(windows: windows)
        let archive = makeArchive(
            catalog: catalog,
            store: store,
            startupRestore: startupRestore
        )
        let blockingAttempt = try XCTUnwrap(archive.beginRestoreAttempt())
        let windowReopen = WindowSessionReopenerFake(reopenResult: false)
        let service = StartupWindowRestoreService(
            startupRestore: startupRestore,
            archive: archive,
            openWindows: catalog,
            restoration: browser.windowSessionBundle.restoreService,
            windowReopen: windowReopen
        )

        service.restoreIfNeeded()
        await Task.yield()
        XCTAssertNil(launchWindow.restorationState.restoredSessionWindowID)
        XCTAssertFalse(startupRestore.didConsumeRestoreOffer)

        archive.finishRestoreAttempt(blockingAttempt, outcome: .interrupted)
        await service.pendingRestoreTask?.value

        XCTAssertEqual(
            launchWindow.restorationState.restoredSessionWindowID,
            sourceSnapshot.id
        )
        XCTAssertTrue(windowReopen.reopenedSnapshots.isEmpty)
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
        let browser = BrowserManager()
        let windows = browser.windowRegistry
        let catalog = makeCatalog(windows: windows)
        let archive = makeArchive(
            catalog: catalog,
            store: store,
            startupRestore: startupRestore
        )
        var didEnterReopen = false
        let windowReopen = WindowSessionReopenerFake(reopenResult: false)
        windowReopen.onReopen = {
            didEnterReopen = true
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(2))
            while Task.isCancelled == false, clock.now < deadline {
                await Task.yield()
            }
        }
        var service: StartupWindowRestoreService? = StartupWindowRestoreService(
            startupRestore: startupRestore,
            archive: archive,
            openWindows: catalog,
            restoration: browser.windowSessionBundle.restoreService,
            windowReopen: windowReopen
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
        let browser = BrowserManager()
        let windows = browser.windowRegistry
        let launchWindow = BrowserWindowState()
        windows.register(launchWindow)
        let catalog = makeCatalog(windows: windows)
        let archive = makeArchive(
            catalog: catalog,
            store: store,
            startupRestore: startupRestore
        )
        let blockingAttempt = try XCTUnwrap(archive.beginRestoreAttempt())
        let windowReopen = WindowSessionReopenerFake()
        windowReopen.onReopen = {
            guard let snapshot = windowReopen.reopenedSnapshots.last else { return }
            let restoredWindow = BrowserWindowState()
            WindowSessionSnapshotApplier(glanceManager: GlanceManager())
                .prepareForRegistration(
                    snapshot.session,
                    to: restoredWindow
                )
            restoredWindow.restorationState.restoredSessionWindowID = snapshot.id
            windows.register(restoredWindow)
        }
        let service = StartupWindowRestoreService(
            startupRestore: startupRestore,
            archive: archive,
            openWindows: catalog,
            restoration: browser.windowSessionBundle.restoreService,
            windowReopen: windowReopen
        )

        service.restoreIfNeeded()
        XCTAssertTrue(windows.discardRejectedRegistration(launchWindow))
        archive.finishRestoreAttempt(blockingAttempt, outcome: .interrupted)
        await service.pendingRestoreTask?.value

        XCTAssertNil(launchWindow.restorationState.restoredSessionWindowID)
        XCTAssertEqual(windowReopen.reopenedSnapshots.map(\.id), [sourceSnapshot.id])
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
        let browser = BrowserManager()
        let windows = browser.windowRegistry
        let catalog = makeCatalog(windows: windows)
        let archive = makeArchive(
            catalog: catalog,
            store: store,
            startupRestore: startupRestore
        )
        let blockingAttempt = try XCTUnwrap(archive.beginRestoreAttempt())
        let windowReopen = WindowSessionReopenerFake()
        var service: StartupWindowRestoreService? = StartupWindowRestoreService(
            startupRestore: startupRestore,
            archive: archive,
            openWindows: catalog,
            restoration: browser.windowSessionBundle.restoreService,
            windowReopen: windowReopen
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
        XCTAssertTrue(windowReopen.reopenedSnapshots.isEmpty)
    }

    private func makeCatalog(windows: WindowRegistry) -> OpenWindowSessionCatalog {
        OpenWindowSessionCatalog(
            windows: windows,
            snapshots: WindowSessionSnapshotFactory(
                glanceManager: GlanceManager()
            )
        )
    }

    private func makeArchive(
        catalog: OpenWindowSessionCatalog,
        store: LastSessionWindowsStore,
        startupRestore: StartupSessionRestoreProviderFake
    ) -> LastSessionWindowArchive {
        LastSessionWindowArchive(
            openWindows: catalog,
            lastSessionWindowsStore: store,
            startupRestore: startupRestore
        )
    }
}
