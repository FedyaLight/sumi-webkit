import AppKit
import WebKit

/// Thin façade over history back/forward and open-URL collaborators.
/// Public call sites (`historyNavigationOwner.goBack`, etc.) stay stable.
@MainActor
final class BrowserHistoryNavigationOwner {
    private let backForwardOwner: BrowserHistoryBackForwardOwner
    private let openOwner: BrowserHistoryOpenOwner

    init(
        activeWindow: @escaping @MainActor @Sendable () -> BrowserWindowState?,
        activePage: @escaping @MainActor @Sendable (BrowserWindowState) -> ActivePageResolution?,
        openNativeBrowserSurface: @escaping @MainActor @Sendable (
            SumiNativeBrowserSurfaceKind,
            URL,
            BrowserWindowState,
            UUID?
        ) -> Void,
        openNewTab: @escaping @MainActor @Sendable (String, BrowserTabOpenContext) -> Tab?,
        loadCurrentPageURL: @escaping @MainActor @Sendable (Tab, BrowserWindowState, URL) -> Void,
        windowIds: @escaping @MainActor @Sendable () -> [UUID],
        createNewWindow: @escaping @MainActor @Sendable () -> Void,
        awaitNextRegisteredWindow: @escaping @MainActor @Sendable (Set<UUID>) async -> BrowserWindowState?,
        scheduleRuntimeStatePersistence: @escaping @MainActor @Sendable (Tab) -> Void,
        schedulePrepareVisibleWebViews: @escaping @MainActor @Sendable (BrowserWindowState) -> Void,
        refreshCompositor: @escaping @MainActor @Sendable (BrowserWindowState) -> Void,
        navigateBack: @escaping @MainActor @Sendable (WKWebView) -> Void,
        navigateForward: @escaping @MainActor @Sendable (WKWebView) -> Void
    ) {
        self.backForwardOwner = BrowserHistoryBackForwardOwner(
            activeWindow: activeWindow,
            activePage: activePage,
            navigateBack: navigateBack,
            navigateForward: navigateForward
        )
        self.openOwner = BrowserHistoryOpenOwner(
            activeWindow: activeWindow,
            activePage: activePage,
            openNativeBrowserSurface: openNativeBrowserSurface,
            openNewTab: openNewTab,
            loadCurrentPageURL: loadCurrentPageURL,
            windowIds: windowIds,
            createNewWindow: createNewWindow,
            awaitNextRegisteredWindow: awaitNextRegisteredWindow,
            scheduleRuntimeStatePersistence: scheduleRuntimeStatePersistence,
            schedulePrepareVisibleWebViews: schedulePrepareVisibleWebViews,
            refreshCompositor: refreshCompositor
        )
    }

    var canGoBackInActiveWindow: Bool {
        backForwardOwner.canGoBackInActiveWindow
    }

    var canGoForwardInActiveWindow: Bool {
        backForwardOwner.canGoForwardInActiveWindow
    }

    func canGoBack(in windowState: BrowserWindowState) -> Bool {
        backForwardOwner.canGoBack(in: windowState)
    }

    func canGoForward(in windowState: BrowserWindowState) -> Bool {
        backForwardOwner.canGoForward(in: windowState)
    }

    func goBackInActiveWindow() {
        backForwardOwner.goBackInActiveWindow()
    }

    func goForwardInActiveWindow() {
        backForwardOwner.goForwardInActiveWindow()
    }

    func goBack(in windowState: BrowserWindowState) {
        backForwardOwner.goBack(in: windowState)
    }

    func goForward(in windowState: BrowserWindowState) {
        backForwardOwner.goForward(in: windowState)
    }

    func openHistoryTab(
        selecting range: HistoryRange = .all,
        in windowState: BrowserWindowState? = nil
    ) {
        openOwner.openHistoryTab(selecting: range, in: windowState)
    }

    func openHistoryURLFromMenuItem(_ url: URL) {
        openOwner.openHistoryURLFromMenuItem(url)
    }

    func openHistoryURL(
        _ url: URL,
        in windowState: BrowserWindowState,
        preferredOpenMode: HistoryOpenMode
    ) {
        openOwner.openHistoryURL(url, in: windowState, preferredOpenMode: preferredOpenMode)
    }

    func openURLsInNewTabs(_ urls: [URL], in windowState: BrowserWindowState) {
        openOwner.openURLsInNewTabs(urls, in: windowState)
    }

    func openHistoryURLsInNewTabs(_ urls: [URL], in windowState: BrowserWindowState) {
        openOwner.openHistoryURLsInNewTabs(urls, in: windowState)
    }

    func openURLsInNewWindow(_ urls: [URL]) {
        openOwner.openURLsInNewWindow(urls)
    }

    func openHistoryURLsInNewWindow(_ urls: [URL]) {
        openOwner.openHistoryURLsInNewWindow(urls)
    }
}
