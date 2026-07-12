import Combine
import SumiWebRuntime
import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class TabClosureServiceCompositionTests: XCTestCase {
    func testLiveCompositionUsesRealTabManagerService() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let active = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://active.example",
            in: space,
            activate: true
        )
        let closed = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://closed.example",
            in: space,
            activate: false
        )

        let service = tabManager.tabClosureService
        service.removeTab(closed.id)

        XCTAssertNil(tabManager.regularTabCollectionOwner.tab(for: closed.id))
        XCTAssertEqual(tabManager.selectionStateOwner.currentTab?.id, active.id)
        XCTAssertTrue(service === tabManager.tabClosureService)
    }

    func testRetainedClosureServiceDoesNotRetainTabManager() throws {
        var tabManager: TabManager? = try makeInMemoryTabManager()
        let service = try XCTUnwrap(tabManager).tabClosureService
        weak let releasedTabManager = tabManager

        tabManager = nil

        XCTAssertNil(releasedTabManager)
        withExtendedLifetime(service) {}
    }

    func testConfirmedRegularRemovalCapturesRecentlyClosedAndNotifiesOnce() throws {
        var captured: [(UUID, UUID?)] = []
        let notifications = NotificationPresentingSpy()
        let container = try makeInMemoryStartupModelContainer()
        let tabManager = TabManager(
            runtimePorts: TestRuntimePorts.make(
                captureClosedTab: { tab, spaceId in
                    captured.append((tab.id, spaceId))
                },
                notifications: { notifications }
            ),
            context: container.mainContext,
            webViewSessions: WebViewSessionRepository(),
            loadPersistedState: false
        )
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let first = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://first.example",
            in: space,
            activate: true
        )
        let second = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://second.example",
            in: space,
            activate: false
        )

        tabManager.tabClosureService.removeTabs([first.id, second.id])

        XCTAssertEqual(Set(captured.map(\.0)), [first.id, second.id])
        XCTAssertEqual(captured.map(\.1), [space.id, space.id])
        XCTAssertEqual(notifications.presentTabClosureNotificationCalls, [2])
    }

    func testNonexistentRegularCandidatesSkipPersistenceNotificationAndCapture() throws {
        var captured: [UUID] = []
        var structuralPublishCount = 0
        let notifications = NotificationPresentingSpy()
        let container = try makeInMemoryStartupModelContainer()
        let tabManager = TabManager(
            runtimePorts: TestRuntimePorts.make(
                captureClosedTab: { tab, _ in
                    captured.append(tab.id)
                },
                notifications: { notifications }
            ),
            context: container.mainContext,
            webViewSessions: WebViewSessionRepository(),
            loadPersistedState: false
        )
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink {
                structuralPublishCount += 1
            }

        let persistence = TabClosurePersistenceSpy()
        let service = TabClosureService.compose(
            tabManager: tabManager,
            persistence: persistence
        )
        service.removeTabs([UUID(), UUID()])

        XCTAssertTrue(captured.isEmpty)
        XCTAssertTrue(notifications.presentTabClosureNotificationCalls.isEmpty)
        XCTAssertEqual(structuralPublishCount, 0)
        XCTAssertEqual(persistence.scheduleCount, 0)
        withExtendedLifetime(cancellable) {}
    }

    func testSuccessfulBatchUsesOneStructuralTransaction() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let first = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://first.example",
            in: space,
            activate: true
        )
        let second = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://second.example",
            in: space,
            activate: false
        )
        var structuralPublishCount = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink {
                structuralPublishCount += 1
            }

        let persistence = TabClosurePersistenceSpy()
        let service = TabClosureService.compose(
            tabManager: tabManager,
            persistence: persistence
        )
        service.removeTabs([first.id, second.id])

        XCTAssertEqual(structuralPublishCount, 1)
        XCTAssertEqual(persistence.scheduleCount, 1)
        withExtendedLifetime(cancellable) {}
    }

    func testSelectionAfterClosingActiveRegularUsesPostRemovalNeighbor() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let first = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://first.example",
            in: space,
            activate: false
        )
        let active = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://active.example",
            in: space,
            activate: true
        )
        let third = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://third.example",
            in: space,
            activate: false
        )
        XCTAssertEqual(tabManager.selectionStateOwner.currentTab?.id, active.id)

        tabManager.tabClosureService.removeTab(active.id)

        XCTAssertEqual(tabManager.selectionStateOwner.currentTab?.id, third.id)
        XCTAssertEqual(
            tabManager.regularTabCollectionOwner.tabs(in: space.id).map(\.id),
            [first.id, third.id]
        )
    }

    func testConfirmedRemovalUsesOneRuntimeLeaseAcrossSynchronousDetach() throws {
        var tabManager: TabManager!
        var events: [String] = []
        let container = try makeInMemoryStartupModelContainer()
        let runtime = TestRuntimePorts.make(
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                unloadTab: { _ in events.append("unload") },
                requireRemoveAllWebViews: { _, _ in events.append("remove") }
            ),
            handleTabClosures: { _ in
                events.append("closures")
                tabManager.detachBrowserRuntime()
            },
            captureClosedTab: { _, _ in events.append("capture") },
            validateWindowStates: {
                events.append("validate")
                return []
            }
        )
        tabManager = TabManager(
            runtimePorts: runtime,
            context: container.mainContext,
            webViewSessions: WebViewSessionRepository(),
            loadPersistedState: false
        )
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://lease.example",
            in: space,
            activate: false
        )

        tabManager.tabClosureService.removeTab(tab.id)

        XCTAssertNil(tabManager.runtimePorts)
        XCTAssertEqual(
            events,
            ["closures", "unload", "remove", "capture", "validate"]
        )
    }
}
