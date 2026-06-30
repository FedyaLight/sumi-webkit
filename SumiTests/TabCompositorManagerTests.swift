import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabCompositorManagerTests: XCTestCase {
    func testUpdateTabVisibilityRefreshesRegisteredCompositorWindows() {
        let firstWindow = BrowserWindowState()
        let secondWindow = BrowserWindowState()
        var refreshedWindowIds: [UUID] = []
        let manager = makeManager(
            registeredCompositorWindows: { [firstWindow, secondWindow] },
            refreshCompositor: { refreshedWindowIds.append($0.id) }
        )

        manager.updateTabVisibility()

        XCTAssertEqual(refreshedWindowIds, [firstWindow.id, secondWindow.id])
    }

    func testUnloadDisplayedTabMarksAccessedAndPreservesWebView() {
        let tab = makeTabWithWebView()
        var accessedTabIds: [UUID] = []
        let manager = makeManager(
            markTabAccessed: { accessedTabIds.append($0) },
            isTabDisplayedInAnyWindow: { $0 == tab.id }
        )

        manager.unloadTab(tab)

        XCTAssertEqual(accessedTabIds, [tab.id])
        XCTAssertNotNil(tab.currentWebView)
    }

    func testUnloadHiddenTabUnloadsWebView() {
        let tab = makeTabWithWebView()
        var accessedTabIds: [UUID] = []
        let manager = makeManager(
            markTabAccessed: { accessedTabIds.append($0) },
            isTabDisplayedInAnyWindow: { _ in false }
        )

        manager.unloadTab(tab)

        XCTAssertTrue(accessedTabIds.isEmpty)
        XCTAssertNil(tab.currentWebView)
    }

    func testUnloadWithoutRuntimeKeepsLegacyFallbackAndUnloadsWebView() {
        let tab = makeTabWithWebView()
        let manager = TabCompositorManager()

        manager.unloadTab(tab)

        XCTAssertNil(tab.currentWebView)
    }

    private func makeManager(
        markTabAccessed: @escaping @MainActor (UUID) -> Void = { _ in },
        isTabDisplayedInAnyWindow: @escaping @MainActor (UUID) -> Bool = { _ in false },
        registeredCompositorWindows: @escaping @MainActor () -> [BrowserWindowState] = { [] },
        refreshCompositor: @escaping @MainActor (BrowserWindowState) -> Void = { _ in }
    ) -> TabCompositorManager {
        let manager = TabCompositorManager()
        manager.attach(
            runtime: TabCompositorRuntime(
                markTabAccessed: markTabAccessed,
                isTabDisplayedInAnyWindow: isTabDisplayedInAnyWindow,
                registeredCompositorWindows: registeredCompositorWindows,
                refreshCompositor: refreshCompositor
            )
        )
        return manager
    }

    private func makeTabWithWebView() -> Tab {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        tab.replaceUntrackedWebView(WKWebView())
        return tab
    }
}
