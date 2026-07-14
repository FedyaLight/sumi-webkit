import WebKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserAppCommandServicesTests: XCTestCase {
    func testMouseRouterFocusesExactWindowWithKeyboardPresentation() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let router = BrowserMouseCommandRouter(
            floatingBar: { [weak browserManager] in
                browserManager?.urlBarBundle.floatingBar.presentation
            },
            history: { nil }
        )

        router.focusFloatingBar(
            in: windowState,
            prefill: "https://mouse.example/path",
            navigateCurrentTab: true
        )

        XCTAssertTrue(windowState.presentationState.isFloatingBarVisible)
        XCTAssertEqual(windowState.floatingBarPresentationReason, .keyboard)
        XCTAssertEqual(windowState.floatingBarDraftText, "https://mouse.example/path")
        XCTAssertTrue(windowState.floatingBarDraftNavigatesCurrentTab)
    }

    func testMouseRouterForwardsBackAndForwardToHistoryCapability() {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let webView = NavigableHistoryWebView()
        var events: [String] = []
        let history = BrowserHistoryNavigationOwner(
            activeWindow: { nil },
            activePage: { windowState in
                ActivePageResolution(
                    source: .selectedTab,
                    windowState: windowState,
                    tab: tab,
                    url: tab.url,
                    canonicalWebView: webView
                )
            },
            openNativeBrowserSurface: { _, _, _, _ in },
            openNewTab: { _, _ in nil },
            loadCurrentPageURL: { _, _, _ in },
            windowIds: { [] },
            createNewWindow: {},
            awaitNextRegisteredWindow: { _ in nil },
            scheduleRuntimeStatePersistence: { _ in },
            schedulePrepareVisibleWebViews: { _ in },
            refreshCompositor: { _ in },
            navigateBack: { _ in events.append("back") },
            navigateForward: { _ in events.append("forward") }
        )
        let router = BrowserMouseCommandRouter(
            floatingBar: { nil },
            history: { history }
        )
        let windowState = BrowserWindowState()

        router.goBack(in: windowState)
        router.goForward(in: windowState)

        XCTAssertEqual(events, ["back", "forward"])
    }

    func testWindowLifecycleServiceExposesTabManagerAndPersistsExactWindow() {
        let tabManager = BrowserManager().tabManager
        var persistedWindows: [BrowserWindowState] = []
        let service = BrowserWindowLifecycleService(
            tabManager: tabManager,
            persist: { persistedWindows.append($0) }
        )
        let windowState = BrowserWindowState()

        service.persistWindowSession(for: windowState)

        XCTAssertIdentical(service.tabManager, tabManager)
        XCTAssertEqual(persistedWindows.count, 1)
        XCTAssertIdentical(persistedWindows.first, windowState)
    }

    func testWindowLifecycleServiceDoesNotRetainBrowserManagerRoot() {
        var browserManager: BrowserManager? = BrowserManager()
        let service = BrowserWindowLifecycleService(
            tabManager: browserManager!.tabManager,
            persist: { [weak browserManager] windowState in
                browserManager?.windowSessionBundle.persistence.persist(windowState)
            }
        )
        weak let releasedBrowserManager = browserManager

        browserManager = nil

        XCTAssertNil(releasedBrowserManager)
        withExtendedLifetime(service) {}
    }
}

@MainActor
private final class NavigableHistoryWebView: WKWebView {
    init() {
        super.init(frame: .zero, configuration: WKWebViewConfiguration())
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canGoBack: Bool { true }
    override var canGoForward: Bool { true }
}
