import AppKit
import XCTest

@testable import Sumi

@MainActor
final class ShortcutActionDispatcherTests: XCTestCase {
    func testFindInPageRoutesSynchronouslyAndPostsNotification() {
        let router = RecordingShortcutActionRouter()
        let dispatcher = ShortcutActionDispatcher()
        dispatcher.actionRouter = router
        let notification = expectation(
            forNotification: .shortcutExecuted,
            object: nil
        ) { note in
            note.userInfo?["action"] as? ShortcutAction == .findInPage
        }

        dispatcher.execute(.findInPage)

        wait(for: [notification], timeout: 1)
        XCTAssertEqual(router.events, [.findInPage])
    }

    func testGoBackRoutesThroughNarrowShortcutRouter() async {
        let router = RecordingShortcutActionRouter()
        let dispatcher = ShortcutActionDispatcher()
        dispatcher.actionRouter = router
        let notification = expectation(
            forNotification: .shortcutExecuted,
            object: nil
        ) { note in
            note.userInfo?["action"] as? ShortcutAction == .goBack
        }

        dispatcher.execute(.goBack)

        await fulfillment(of: [notification], timeout: 1)
        XCTAssertEqual(router.events, [.goBack])
    }

    func testCloseTabRoutesSynchronously() {
        let router = RecordingShortcutActionRouter()
        let dispatcher = ShortcutActionDispatcher()
        dispatcher.actionRouter = router

        dispatcher.execute(.closeTab)

        XCTAssertEqual(router.events, [.closeTab])
    }

    func testFocusAddressBarUsesActiveURLPrefill() async {
        let router = RecordingShortcutActionRouter()
        router.activePageURL = URL(string: "https://example.com/path")!
        let dispatcher = ShortcutActionDispatcher()
        dispatcher.actionRouter = router
        let notification = expectation(
            forNotification: .shortcutExecuted,
            object: nil
        ) { note in
            note.userInfo?["action"] as? ShortcutAction == .focusAddressBar
        }

        dispatcher.execute(.focusAddressBar)

        await fulfillment(of: [notification], timeout: 1)
        XCTAssertEqual(
            router.focusRequests,
            [RecordingShortcutActionRouter.FocusRequest(
                prefill: "https://example.com/path",
                navigateCurrentTab: true
            ),
            ]
        )
    }
}

@MainActor
private final class RecordingShortcutActionRouter: ShortcutActionRouting {
    struct FocusRequest: Equatable {
        let prefill: String
        let navigateCurrentTab: Bool
    }

    var activePageURL: URL?
    private(set) var events: [ShortcutAction] = []
    private(set) var focusRequests: [FocusRequest] = []

    func showFindBar() { events.append(.findInPage) }
    func goBackInActiveWindow() { events.append(.goBack) }
    func goForwardInActiveWindow() { events.append(.goForward) }
    func refreshCurrentTabInActiveWindow() { events.append(.refresh) }
    func clearCurrentPageCookies() { events.append(.clearCookiesAndRefresh) }
    func openNewTabSurfaceInActiveWindow() { events.append(.newTab) }
    func closeCurrentTab() { events.append(.closeTab) }
    func undoCloseTab() { events.append(.undoCloseTab) }
    func selectNextTabInActiveWindow() { events.append(.nextTab) }
    func selectPreviousTabInActiveWindow() { events.append(.previousTab) }
    func selectTabByIndexInActiveWindow(_ index: Int) {
        let tabIndexActions: [ShortcutAction] = [
            .goToTab1,
            .goToTab2,
            .goToTab3,
            .goToTab4,
            .goToTab5,
            .goToTab6,
            .goToTab7,
            .goToTab8,
        ]
        guard tabIndexActions.indices.contains(index) else { return }
        events.append(tabIndexActions[index])
    }
    func selectLastTabInActiveWindow() { events.append(.goToLastTab) }
    func duplicateCurrentTab() { events.append(.duplicateTab) }
    func setActiveSplitLayout(_ layoutKind: SplitLayoutKind) {
        switch layoutKind {
        case .grid:
            events.append(.splitGrid)
        case .vertical:
            events.append(.splitVertical)
        case .horizontal:
            events.append(.splitHorizontal)
        }
    }
    func unsplitActiveWindow() { events.append(.unsplit) }
    func createEmptySplitInActiveWindow() { events.append(.newEmptySplit) }
    func selectNextSpaceInActiveWindow() { events.append(.nextSpace) }
    func selectPreviousSpaceInActiveWindow() { events.append(.previousSpace) }
    func createNewWindow() { events.append(.newWindow) }
    func closeActiveWindow() { events.append(.closeWindow) }
    func showQuitDialog() { events.append(.closeBrowser) }
    func toggleFullScreenForActiveWindow() { events.append(.toggleFullScreen) }
    func openWebInspector() { events.append(.openDevTools) }
    func showDownloads() { events.append(.viewDownloads) }
    func showHistory() { events.append(.viewHistory) }
    func expandAllFoldersInSidebar() { events.append(.expandAllFolders) }
    func activePageURLForActiveWindow() -> URL? { activePageURL }
    func focusFloatingBarForActiveWindow(prefill: String, navigateCurrentTab: Bool) {
        events.append(.focusAddressBar)
        focusRequests.append(FocusRequest(prefill: prefill, navigateCurrentTab: navigateCurrentTab))
    }
    func zoomInCurrentTab() { events.append(.zoomIn) }
    func zoomOutCurrentTab() { events.append(.zoomOut) }
    func resetZoomCurrentTab() { events.append(.actualSize) }
    func toggleSidebar() { events.append(.toggleSidebar) }
    func copyCurrentURL() { events.append(.copyCurrentURL) }
    func hardReloadCurrentPage() { events.append(.hardReload) }
    func toggleReaderModeInActiveWindow() { events.append(.toggleReaderMode) }
    func toggleMuteCurrentTabInActiveWindow() { events.append(.muteUnmuteAudio) }
    func showGradientEditor() { events.append(.customizeSpaceGradient) }
}
