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
                browserManager?.urlBarBundle.commandPalette.presentation
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

    func testWindowLifecycleServicePersistsExactWindow() throws {
        let suiteName = "BrowserAppCommandServicesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let snapshotStore = WindowSessionSnapshotStore(
            key: "window-session",
            userDefaults: defaults,
            environment: { [:] }
        )
        let currentTabID = UUID()
        let windowState = BrowserWindowState()
        windowState.currentTabId = currentTabID
        let windows = WindowRegistry()
        windows.register(windowState)
        let persistence = WindowSessionPersistenceTestComposition(
            snapshotStore: snapshotStore,
            scheduler: WindowSessionPersistenceScheduler(),
            snapshotFactory: WindowSessionSnapshotFactory(
                glanceManager: GlanceManager()
            ),
            windows: windows
        )
        let service = BrowserWindowLifecycleService(
            persistence: persistence.coordinator
        )

        service.persistWindowSession(for: windowState)

        XCTAssertEqual(
            snapshotStore.loadSnapshot()?.snapshot.currentTabId,
            currentTabID
        )
    }

    func testWindowLifecycleServiceDoesNotRetainBrowserManagerRoot() {
        var browserManager: BrowserManager? = BrowserManager()
        let service = BrowserWindowLifecycleService(
            persistence: browserManager!.windowSessionPersistenceCoordinator
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
