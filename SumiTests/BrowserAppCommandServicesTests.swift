import WebKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserAppCommandServicesTests: XCTestCase {
    func testMouseRouterFocusesExactWindowWithKeyboardPresentation() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let router = BrowserMouseCommandRouter(
            commandPalette: { [weak browserManager] in
                browserManager?.urlBarBundle.commandPalettePresentation
            },
            history: { nil }
        )

        router.focusCommandPalette(
            in: windowState,
            prefill: "https://mouse.example/path",
            navigateCurrentTab: true
        )

        XCTAssertTrue(windowState.presentationState.isCommandPaletteVisible)
        XCTAssertEqual(windowState.commandPalettePresentationReason, .keyboard)
        XCTAssertEqual(windowState.commandPaletteDraftText, "https://mouse.example/path")
        XCTAssertTrue(windowState.commandPaletteDraftNavigatesCurrentTab)
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
            commandPalette: { nil },
            history: { history }
        )
        let windowState = BrowserWindowState()

        router.goBack(in: windowState)
        router.goForward(in: windowState)

        XCTAssertEqual(events, ["back", "forward"])
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
