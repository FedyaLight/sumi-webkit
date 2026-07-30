import Combine
import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabClosureServiceCompositionTests: XCTestCase {
    func testExactCompositionMutatesOnlyInjectedGraph() throws {
        let selectedGraph = BrowserManager()
        let otherGraph = BrowserManager()
        let selectedSpace = makeSpace(in: selectedGraph, name: "Selected")
        let otherSpace = makeSpace(in: otherGraph, name: "Other")
        let active = selectedGraph.regularTabLifecycleOwner.createNewTab(
            url: "https://active.example",
            in: selectedSpace,
            activate: true
        )
        let closed = selectedGraph.regularTabLifecycleOwner.createNewTab(
            url: "https://closed.example",
            in: selectedSpace,
            activate: false
        )
        let untouched = otherGraph.regularTabLifecycleOwner.createNewTab(
            url: "https://untouched.example",
            in: otherSpace,
            activate: true
        )

        let service = makeClosureService(for: selectedGraph)
        service.removeTab(closed.id)

        XCTAssertNil(selectedGraph.regularTabCollectionOwner.tab(for: closed.id))
        XCTAssertEqual(selectedGraph.tabStateStore.selection.currentTab?.id, active.id)
        XCTAssertEqual(
            otherGraph.regularTabCollectionOwner.tab(for: untouched.id)?.id,
            untouched.id
        )
    }

    func testExactCompositionDoesNotRetainAssemblyManager() throws {
        var tabManager: BrowserManager? = BrowserManager()
        let space = makeSpace(
            in: try XCTUnwrap(tabManager),
            name: "Space"
        )
        _ = try XCTUnwrap(tabManager).regularTabLifecycleOwner.createNewTab(
            url: "https://active.example",
            in: space,
            activate: true
        )
        let closed = try XCTUnwrap(tabManager).regularTabLifecycleOwner.createNewTab(
            url: "https://closed.example",
            in: space,
            activate: false
        )
        let regularTabs = try XCTUnwrap(tabManager).regularTabCollectionOwner
        let selection = try XCTUnwrap(tabManager).tabStateStore.selection
        let service = makeClosureService(for: try XCTUnwrap(tabManager))
        weak let releasedTabManager = tabManager

        tabManager = nil

        XCTAssertNil(releasedTabManager)
        service.removeTab(closed.id)
        XCTAssertNil(regularTabs.tab(for: closed.id))
        XCTAssertNil(selection.currentTab)
    }

    func testConfirmedRegularRemovalCapturesRecentlyClosedAndNotifiesOnce() throws {
        var captured: [(UUID, UUID?)] = []
        let notifications = NotificationPresentingSpy()
        let profile = Profile(name: "Closure")
        let tabManager = BrowserManager(
            runtimePorts: TestRuntimePorts.make(
                currentProfileId: { profile.id },
                defaultProfileId: { profile.id },
                profile: { $0 == profile.id ? profile : nil },
                captureClosedTab: { tab, spaceId in
                    captured.append((tab.id, spaceId))
                },
                notifications: { notifications }
            )
        )
        let space = makeSpace(
            in: tabManager,
            name: "Space",
            profileID: profile.id
        )
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

        makeClosureService(for: tabManager).removeTabs([first.id, second.id])

        XCTAssertEqual(Set(captured.map(\.0)), [first.id, second.id])
        XCTAssertEqual(captured.map(\.1), [space.id, space.id])
        XCTAssertEqual(notifications.presentTabClosureNotificationCalls, [2])
    }

    func testConfirmedRegularRemovalReleasesRegisteredWebView() {
        let tabManager = BrowserManager()
        let space = makeSpace(in: tabManager, name: "WebView retirement")
        weak var releasedWebView: WKWebView?
        var closedTabID: UUID?

        autoreleasepool {
            let tab = tabManager.regularTabLifecycleOwner.createNewTab(
                url: "https://memory.example",
                in: space,
                activate: true
            )
            let webView = WKWebView()
            tab.replaceUntrackedWebView(webView)
            tab.bindAudioState(to: webView)
            releasedWebView = webView
            closedTabID = tab.id

            tabManager.tabClosureService.removeTab(tab.id)

            XCTAssertNil(tabManager.regularTabCollectionOwner.tab(for: tab.id))
            XCTAssertNil(tabManager.webViewSessions.residence(of: webView))
        }

        XCTAssertNotNil(closedTabID)
        XCTAssertNil(
            releasedWebView,
            "Closing a regular tab must release Sumi's final strong WKWebView ownership"
        )
    }

    func testNonexistentRegularCandidatesSkipPersistenceNotificationAndCapture() throws {
        var captured: [UUID] = []
        var structuralPublishCount = 0
        let notifications = NotificationPresentingSpy()
        let tabManager = BrowserManager(
            runtimePorts: TestRuntimePorts.make(
                captureClosedTab: { tab, _ in
                    captured.append(tab.id)
                },
                notifications: { notifications }
            )
        )
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink {
                structuralPublishCount += 1
            }

        let persistence = TabClosurePersistenceSpy()
        let service = makeClosureService(
            for: tabManager,
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
        let tabManager = BrowserManager()
        let space = makeSpace(in: tabManager, name: "Space")
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
        let service = makeClosureService(
            for: tabManager,
            persistence: persistence
        )
        service.removeTabs([first.id, second.id])

        XCTAssertEqual(structuralPublishCount, 1)
        XCTAssertEqual(persistence.scheduleCount, 1)
        withExtendedLifetime(cancellable) {}
    }

    func testSelectionAfterClosingActiveRegularUsesPostRemovalNeighbor() throws {
        let tabManager = BrowserManager()
        let space = makeSpace(in: tabManager, name: "Space")
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
        XCTAssertEqual(tabManager.tabStateStore.selection.currentTab?.id, active.id)

        makeClosureService(for: tabManager).removeTab(active.id)

        XCTAssertEqual(tabManager.tabStateStore.selection.currentTab?.id, third.id)
        XCTAssertEqual(
            tabManager.regularTabCollectionOwner.tabs(in: space.id).map(\.id),
            [first.id, third.id]
        )
    }

    func testConfirmedRemovalUsesOneRuntimeLeaseAcrossSynchronousDetach() throws {
        var tabManager: BrowserManager!
        var events: [String] = []
        let profile = Profile(name: "Closure")
        let runtime = TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                unloadTab: { _ in events.append("unload") },
                requireRemoveAllWebViews: { _, _ in events.append("remove") }
            ),
            handleTabClosures: { _ in
                events.append("closures")
                tabManager.tabRuntimeLifecycle.shutdown()
            },
            captureClosedTab: { _, _ in events.append("capture") },
            validateWindowStates: {
                events.append("validate")
                return []
            }
        )
        tabManager = BrowserManager(runtimePorts: runtime)
        let space = makeSpace(
            in: tabManager,
            name: "Space",
            profileID: profile.id
        )
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://lease.example",
            in: space,
            activate: false
        )

        makeClosureService(for: tabManager).removeTab(tab.id)

        XCTAssertNil(tabManager.runtimePortConnection.current)
        XCTAssertEqual(
            events,
            ["unload", "remove", "closures", "capture", "validate"]
        )
    }

    private func makeClosureService(
        for tabManager: BrowserManager,
        persistence: (any TabClosurePersistence)? = nil
    ) -> TabClosureService {
        let persistence = persistence ?? tabManager.structuralPersistence
        let candidateRetirement = TabClosureCandidateRetirement(
            shortcutRetirement: tabManager.shortcutLiveTabRetirement,
            persistence: persistence,
            transientExtensionTabs: TransientExtensionTabRetirementTransaction(
                runtimeConnection: tabManager.runtimePortConnection,
                membership: tabManager.tabCollectionMembershipOwner
            ),
            auxiliaryMiniWindowTabs: tabManager.auxiliaryMiniWindowTabs
        )
        let runtimeCleanup = RegularTabClosureRuntimeCleanup(
            membership: tabManager.tabCollectionMembershipOwner
        )
        return TabClosureService(
            transactions: tabManager.structuralLookupCoordinator,
            candidateRetirement: candidateRetirement,
            regularCommit: RegularTabClosureCommitTransaction(
                regularTabs: tabManager.regularTabCollectionOwner,
                spaces: tabManager.spaceStateOwner,
                runtimeCleanup: runtimeCleanup,
                persistence: persistence,
                runtimePorts: tabManager.runtimePortConnection
            ),
            selectionRepair: RegularTabClosureSelectionRepair(
                selection: tabManager.tabStateStore.selection,
                spaces: tabManager.spaceStateOwner,
                regularTabs: tabManager.regularTabCollectionOwner,
                shortcutPresentation: tabManager.shortcutPresentationOwner
            ),
            targets: RegularTabClosureTargetQuery(
                regularTabs: tabManager.regularTabCollectionOwner,
                selection: tabManager.tabStateStore.selection
            )
        )
    }

    private func makeSpace(
        in browser: BrowserManager,
        name: String,
        profileID: UUID? = nil
    ) -> Space {
        let space = Space(name: name, profileId: profileID)
        browser.spaceStateOwner.append(space)
        browser.spaceStateOwner.replaceCurrentSpace(space)
        return space
    }
}
