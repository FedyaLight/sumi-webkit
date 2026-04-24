import BrowserServicesKit
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabSuspensionServiceTests: XCTestCase {
    private var now: Date!

    override func setUp() {
        super.setUp()
        now = Date()
    }

    override func tearDown() {
        now = nil
        super.tearDown()
    }

    func testActiveSelectedTabIsNeverSuspended() {
        let harness = makeHarness()
        let selected = makeTab("https://example.com/selected", harness: harness)
        let hidden = makeTab("https://example.com/hidden", harness: harness)

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        attachWebView(to: hidden, harness: harness)
        selected.lastSelectedAt = now.addingTimeInterval(-600)
        hidden.lastSelectedAt = now.addingTimeInterval(-1200)

        let result = harness.service.handleMemoryPressure(.critical)

        XCTAssertEqual(result.suspendedTabIDs, [hidden.id])
        XCTAssertFalse(selected.isSuspended)
        XCTAssertNotNil(harness.coordinator.getWebView(for: selected.id, in: harness.windowState.id))
    }

    func testVisibleSplitPanesAreNeverSuspended() {
        let harness = makeHarness()
        let left = makeTab("https://example.com/left", harness: harness)
        let right = makeTab("https://example.com/right", harness: harness)
        let hidden = makeTab("https://example.com/split-hidden", harness: harness)

        setCurrentTab(left, in: harness.windowState)
        var splitState = harness.browserManager.splitManager.getSplitState(for: harness.windowState.id)
        splitState.isSplit = true
        splitState.leftTabId = left.id
        splitState.rightTabId = right.id
        harness.browserManager.splitManager.setSplitState(splitState, for: harness.windowState.id)

        attachWebView(to: left, harness: harness)
        attachWebView(to: right, harness: harness)
        attachWebView(to: hidden, harness: harness)
        left.lastSelectedAt = now.addingTimeInterval(-1800)
        right.lastSelectedAt = now.addingTimeInterval(-1700)
        hidden.lastSelectedAt = now.addingTimeInterval(-1600)

        let result = harness.service.handleMemoryPressure(.critical)

        XCTAssertEqual(result.suspendedTabIDs, [hidden.id])
        XCTAssertFalse(left.isSuspended)
        XCTAssertFalse(right.isSuspended)
        XCTAssertNotNil(harness.coordinator.getWebView(for: left.id, in: harness.windowState.id))
        XCTAssertNotNil(harness.coordinator.getWebView(for: right.id, in: harness.windowState.id))
    }

    func testWarningPressureSuspendsOldestHiddenLRUTabOnly() {
        let harness = makeHarness()
        let selected = makeTab("https://example.com/current", harness: harness)
        let oldest = makeTab("https://example.com/oldest", harness: harness)
        let recent = makeTab("https://example.com/recent", harness: harness)

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        attachWebView(to: oldest, harness: harness)
        attachWebView(to: recent, harness: harness)
        oldest.lastSelectedAt = now.addingTimeInterval(-2400)
        recent.lastSelectedAt = now.addingTimeInterval(-60)

        let result = harness.service.handleMemoryPressure(.warning)

        XCTAssertEqual(result.candidateCount, 1)
        XCTAssertEqual(result.suspendedTabIDs, [oldest.id])
        XCTAssertTrue(oldest.isSuspended)
        XCTAssertFalse(recent.isSuspended)
    }

    func testRecentlySelectedHiddenTabIsNotSuspendedByMemoryPressure() {
        let harness = makeHarness()
        let selected = makeTab("https://example.com/current", harness: harness)
        let recent = makeTab("https://example.com/recent", harness: harness)
        let old = makeTab("https://example.com/old", harness: harness)

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        attachWebView(to: recent, harness: harness)
        attachWebView(to: old, harness: harness)
        recent.lastSelectedAt = now.addingTimeInterval(-120)
        old.lastSelectedAt = now.addingTimeInterval(-1200)

        let result = harness.service.handleMemoryPressure(.critical)

        XCTAssertEqual(result.candidateCount, 1)
        XCTAssertEqual(result.suspendedTabIDs, [old.id])
        XCTAssertFalse(recent.isSuspended)
        XCTAssertTrue(old.isSuspended)
    }

    func testHiddenTabWithoutLastSelectedAtIsSuspendedByMemoryPressure() {
        let harness = makeHarness()
        let selected = makeTab("https://example.com/current", harness: harness)
        let neverSelected = makeTab("https://example.com/never-selected", harness: harness)

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        attachWebView(to: neverSelected, harness: harness)

        let result = harness.service.handleMemoryPressure(.critical)

        XCTAssertEqual(result.candidateCount, 1)
        XCTAssertEqual(result.suspendedTabIDs, [neverSelected.id])
        XCTAssertTrue(neverSelected.isSuspended)
    }

    func testCriticalPressureSuspendsAllEligibleHiddenTabsInLRUOrder() {
        let harness = makeHarness()
        let selected = makeTab("https://example.com/current", harness: harness)
        let oldest = makeTab("https://example.com/oldest", harness: harness)
        let middle = makeTab("https://example.com/middle", harness: harness)
        let newest = makeTab("https://example.com/newest", harness: harness)

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        attachWebView(to: newest, harness: harness)
        attachWebView(to: oldest, harness: harness)
        attachWebView(to: middle, harness: harness)
        oldest.lastSelectedAt = now.addingTimeInterval(-3000)
        middle.lastSelectedAt = now.addingTimeInterval(-2000)
        newest.lastSelectedAt = now.addingTimeInterval(-1000)

        let result = harness.service.handleMemoryPressure(.critical)

        XCTAssertEqual(result.candidateCount, 3)
        XCTAssertEqual(result.suspendedTabIDs, [oldest.id, middle.id, newest.id])
        XCTAssertTrue(oldest.isSuspended)
        XCTAssertTrue(middle.isSuspended)
        XCTAssertTrue(newest.isSuspended)
    }

    func testPinnedHiddenTabsAreNeverSuspended() {
        let harness = makeHarness()
        let selected = makeTab("https://example.com/current", harness: harness)
        let pinned = makeTab("https://example.com/pinned", harness: harness)
        let eligible = makeTab("https://example.com/eligible", harness: harness)

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        attachWebView(to: pinned, harness: harness)
        attachWebView(to: eligible, harness: harness)
        pinned.isPinned = true
        pinned.lastSelectedAt = now.addingTimeInterval(-3600)
        eligible.lastSelectedAt = now.addingTimeInterval(-1800)

        let result = harness.service.handleMemoryPressure(.critical)

        XCTAssertEqual(result.candidateCount, 1)
        XCTAssertEqual(result.suspendedTabIDs, [eligible.id])
        XCTAssertFalse(pinned.isSuspended)
    }

    func testNonHTTPHiddenTabsAreNeverSuspended() {
        let harness = makeHarness()
        let selected = makeTab("https://example.com/current", harness: harness)
        let fileTab = makeTab("file:///tmp/suspension.html", harness: harness)
        let eligible = makeTab("https://example.com/eligible", harness: harness)

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        attachWebView(to: fileTab, harness: harness)
        attachWebView(to: eligible, harness: harness)
        fileTab.lastSelectedAt = now.addingTimeInterval(-3600)
        eligible.lastSelectedAt = now.addingTimeInterval(-1800)

        let result = harness.service.handleMemoryPressure(.critical)

        XCTAssertEqual(fileTab.url.scheme, "file")
        XCTAssertEqual(result.candidateCount, 1)
        XCTAssertEqual(result.suspendedTabIDs, [eligible.id])
        XCTAssertFalse(fileTab.isSuspended)
    }

    func testAlreadySuspendedAndUnloadedTabsAreSkipped() {
        let harness = makeHarness()
        let selected = makeTab("https://example.com/current", harness: harness)
        let alreadySuspended = makeTab("https://example.com/already", harness: harness)
        let unloaded = makeTab("https://example.com/unloaded", harness: harness)
        let eligible = makeTab("https://example.com/eligible", harness: harness)

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        attachWebView(to: alreadySuspended, harness: harness)
        attachWebView(to: eligible, harness: harness)
        alreadySuspended.isSuspended = true

        let result = harness.service.handleMemoryPressure(.critical)

        XCTAssertEqual(result.candidateCount, 1)
        XCTAssertEqual(result.suspendedTabIDs, [eligible.id])
        XCTAssertFalse(unloaded.isSuspended)
    }

    func testSuspendingTabReleasesCoordinatorStateAndWebViewDelegates() {
        let harness = makeHarness()
        let selected = makeTab("https://example.com/current", harness: harness)
        let hidden = makeTab("https://example.com/release", harness: harness)

        setCurrentTab(selected, in: harness.windowState)
        attachWebView(to: selected, harness: harness)
        let releasedWebView = attachWebView(to: hidden, harness: harness)
        releasedWebView.navigationDelegate = hidden
        releasedWebView.uiDelegate = hidden

        XCTAssertTrue(harness.service.suspend(hidden, reason: "test-release"))

        XCTAssertTrue(hidden.isSuspended)
        XCTAssertNil(hidden.existingWebView)
        XCTAssertNil(hidden.primaryWindowId)
        XCTAssertNil(harness.coordinator.getWebView(for: hidden.id, in: harness.windowState.id))
        XCTAssertNil(harness.coordinator.getWebViewHost(for: hidden.id, in: harness.windowState.id))
        XCTAssertNil(harness.coordinator.windowID(containing: releasedWebView))
        XCTAssertNil(releasedWebView.navigationDelegate)
        XCTAssertNil(releasedWebView.uiDelegate)
        XCTAssertNil(releasedWebView.superview)
    }

    func testSelectingSuspendedTabRestoresOnlyThatTab() throws {
        let harness = makeHarness()
        let current = makeTab("https://example.com/current", harness: harness)
        let firstSuspended = makeTab("https://example.com/first", harness: harness)
        let secondSuspended = makeTab("https://example.com/second", harness: harness)

        setCurrentTab(current, in: harness.windowState)
        attachWebView(to: current, harness: harness)
        attachWebView(to: firstSuspended, harness: harness)
        attachWebView(to: secondSuspended, harness: harness)

        XCTAssertTrue(harness.service.suspend(firstSuspended, reason: "test-roundtrip"))
        XCTAssertTrue(harness.service.suspend(secondSuspended, reason: "test-roundtrip"))

        harness.browserManager.selectTab(
            firstSuspended,
            in: harness.windowState,
            loadPolicy: .immediate
        )

        let restoredWebView = try XCTUnwrap(firstSuspended.existingWebView)
        XCTAssertFalse(firstSuspended.isSuspended)
        XCTAssertTrue(secondSuspended.isSuspended)
        XCTAssertNil(secondSuspended.existingWebView)
        XCTAssertTrue(
            restoredWebView.configuration.userContentController
                .sumiUsesNormalTabBrowserServicesKitUserContentController
        )
        XCTAssertTrue(restoredWebView.configuration.userContentController is UserContentController)
    }

    func testMemoryPressureMonitorMapsWarningAndCriticalEvents() {
        let monitor = SumiMemoryPressureMonitor()
        var received: [String] = []
        monitor.eventHandler = { level in
            received.append(level.rawValue)
        }

        monitor.processMemoryPressureEventForTesting(.warning)
        monitor.processMemoryPressureEventForTesting([.warning, .critical])
        monitor.stop()

        XCTAssertEqual(received, ["warning", "critical"])
    }

    private struct Harness {
        let browserManager: BrowserManager
        let coordinator: WebViewCoordinator
        let windowRegistry: WindowRegistry
        let windowState: BrowserWindowState
        let service: TabSuspensionService
    }

    private func makeHarness() -> Harness {
        let browserManager = BrowserManager()
        let coordinator = WebViewCoordinator()
        let windowRegistry = WindowRegistry()
        browserManager.webViewCoordinator = coordinator
        browserManager.windowRegistry = windowRegistry

        let space = Space(name: "Suspension")
        browserManager.tabManager.spaces = [space]
        browserManager.tabManager.currentSpace = space

        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        let service = TabSuspensionService(
            memoryMonitor: nil,
            dateProvider: { [unowned self] in self.now }
        )
        service.attach(browserManager: browserManager)

        return Harness(
            browserManager: browserManager,
            coordinator: coordinator,
            windowRegistry: windowRegistry,
            windowState: windowState,
            service: service
        )
    }

    private func makeTab(_ url: String, harness: Harness) -> Tab {
        harness.browserManager.tabManager.createNewTab(
            url: url,
            in: harness.browserManager.tabManager.currentSpace,
            activate: false
        )
    }

    @discardableResult
    private func attachWebView(to tab: Tab, harness: Harness) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        harness.coordinator.setWebView(webView, for: tab.id, in: harness.windowState.id)
        tab.assignWebViewToWindow(webView, windowId: harness.windowState.id)
        return webView
    }

    private func setCurrentTab(_ tab: Tab, in windowState: BrowserWindowState) {
        windowState.currentTabId = tab.id
        windowState.currentSpaceId = tab.spaceId
        windowState.isShowingEmptyState = false
    }
}
