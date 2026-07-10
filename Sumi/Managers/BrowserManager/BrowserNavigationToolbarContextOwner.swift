import Foundation
import WebKit
import SumiDomain

@MainActor
final class BrowserNavigationToolbarContextOwner {
    private let currentTab: @MainActor (BrowserWindowState) -> Tab?
    private let webView: @MainActor (Tab, BrowserWindowState) -> WKWebView?
    private let faviconService: @MainActor () -> any BrowserFaviconServicing
    private let faviconImageReader: @MainActor () -> any BrowserFaviconImageReading
    private let openURLInCurrentTab: @MainActor (URL, BrowserWindowState) -> Void
    private let openNewTab: @MainActor (String, BrowserTabOpenContext) -> Void
    private let openHistoryURLsInNewWindow: @MainActor ([URL]) -> Void
    private let goBack: @MainActor (BrowserWindowState) -> Void
    private let goForward: @MainActor (BrowserWindowState) -> Void
    private let reload: @MainActor (Tab, BrowserWindowState) -> Void

    init(
        currentTab: @escaping @MainActor (BrowserWindowState) -> Tab?,
        webView: @escaping @MainActor (Tab, BrowserWindowState) -> WKWebView?,
        faviconService: @escaping @MainActor () -> any BrowserFaviconServicing,
        faviconImageReader: @escaping @MainActor () -> any BrowserFaviconImageReading,
        openURLInCurrentTab: @escaping @MainActor (URL, BrowserWindowState) -> Void,
        openNewTab: @escaping @MainActor (String, BrowserTabOpenContext) -> Void,
        openHistoryURLsInNewWindow: @escaping @MainActor ([URL]) -> Void,
        goBack: @escaping @MainActor (BrowserWindowState) -> Void,
        goForward: @escaping @MainActor (BrowserWindowState) -> Void,
        reload: @escaping @MainActor (Tab, BrowserWindowState) -> Void
    ) {
        self.currentTab = currentTab
        self.webView = webView
        self.faviconService = faviconService
        self.faviconImageReader = faviconImageReader
        self.openURLInCurrentTab = openURLInCurrentTab
        self.openNewTab = openNewTab
        self.openHistoryURLsInNewWindow = openHistoryURLsInNewWindow
        self.goBack = goBack
        self.goForward = goForward
        self.reload = reload
    }

    func navigationToolbarContext(
        for windowState: BrowserWindowState
    ) -> NavigationToolbarBrowserContext {
        NavigationToolbarBrowserContext(
            currentTab: { [weak self, weak windowState] in
                guard let self, let windowState else { return nil }
                return self.currentTab(windowState)
            },
            webView: { [weak self, weak windowState] tab in
                guard let self, let windowState else { return nil }
                return self.webView(tab, windowState)
            },
            historyContext: navigationHistoryContext(for: windowState),
            goBack: { [weak self, weak windowState] in
                guard let self, let windowState else { return }
                self.goBack(windowState)
            },
            goForward: { [weak self, weak windowState] in
                guard let self, let windowState else { return }
                self.goForward(windowState)
            },
            reload: { [weak self, weak windowState] tab in
                guard let self, let windowState else { return }
                self.reload(tab, windowState)
            }
        )
    }

    func navigationHistoryContext(
        for windowState: BrowserWindowState
    ) -> SumiNavigationHistoryContext {
        SumiNavigationHistoryContext(
            faviconService: faviconService(),
            faviconImageReader: faviconImageReader(),
            openURLInCurrentTab: { [weak self, weak windowState] url, _ in
                guard let self, let windowState else { return }
                self.openURLInCurrentTab(url, windowState)
            },
            openURLInNewTab: { [weak self, weak windowState] url, selected, sourceTab in
                self?.openURLFromNavigationHistory(
                    url: url,
                    selected: selected,
                    sourceTab: sourceTab,
                    windowState: windowState
                )
            },
            openURLsInNewWindow: openHistoryURLsInNewWindow
        )
    }

    private func openURLFromNavigationHistory(
        url: URL,
        selected: Bool,
        sourceTab: Tab?,
        windowState: BrowserWindowState?
    ) {
        guard let targetWindowState = windowState else { return }
        let context: BrowserTabOpenContext
        if selected {
            context = .foreground(
                windowState: targetWindowState,
                sourceTab: sourceTab,
                preferredSpaceId: targetWindowState.currentSpaceId
            )
        } else {
            context = .background(
                windowState: targetWindowState,
                sourceTab: sourceTab,
                preferredSpaceId: targetWindowState.currentSpaceId
            )
        }

        openNewTab(url.absoluteString, context)
    }
}
