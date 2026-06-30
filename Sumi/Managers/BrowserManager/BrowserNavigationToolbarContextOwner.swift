import Foundation
import WebKit

@MainActor
final class BrowserNavigationToolbarContextOwner {
    struct Dependencies {
        let currentTab: @MainActor (BrowserWindowState) -> Tab?
        let webView: @MainActor (Tab, BrowserWindowState) -> WKWebView?
        let faviconService: @MainActor () -> any BrowserFaviconServicing
        let faviconImageService: @MainActor () -> any BrowserFaviconImageServicing
        let activeWindow: @MainActor () -> BrowserWindowState?
        let openNewTab: @MainActor (String, BrowserTabOpenContext) -> Void
        let openHistoryURLsInNewWindow: @MainActor ([URL]) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func navigationToolbarContext(
        for windowState: BrowserWindowState
    ) -> NavigationToolbarBrowserContext {
        NavigationToolbarBrowserContext(
            currentTab: { [weak self, weak windowState] in
                guard let self, let windowState else { return nil }
                return self.dependencies.currentTab(windowState)
            },
            webView: { [weak self, weak windowState] tab in
                guard let self, let windowState else { return nil }
                return self.dependencies.webView(tab, windowState)
            },
            historyContext: navigationHistoryContext(for: windowState)
        )
    }

    func navigationHistoryContext(
        for windowState: BrowserWindowState
    ) -> SumiNavigationHistoryContext {
        SumiNavigationHistoryContext(
            faviconService: dependencies.faviconService(),
            faviconImageService: dependencies.faviconImageService(),
            openURLInNewTab: { [weak self, weak windowState] url, selected, sourceTab in
                self?.openURLFromNavigationHistory(
                    url: url,
                    selected: selected,
                    sourceTab: sourceTab,
                    windowState: windowState
                )
            },
            openURLsInNewWindow: dependencies.openHistoryURLsInNewWindow
        )
    }

    private func openURLFromNavigationHistory(
        url: URL,
        selected: Bool,
        sourceTab: Tab?,
        windowState: BrowserWindowState?
    ) {
        let targetWindowState = windowState ?? dependencies.activeWindow()
        let context: BrowserTabOpenContext
        if selected, let targetWindowState {
            context = .foreground(
                windowState: targetWindowState,
                sourceTab: sourceTab,
                preferredSpaceId: targetWindowState.currentSpaceId
            )
        } else {
            context = .background(
                windowState: targetWindowState,
                sourceTab: sourceTab,
                preferredSpaceId: targetWindowState?.currentSpaceId
            )
        }

        dependencies.openNewTab(url.absoluteString, context)
    }
}

extension BrowserNavigationToolbarContextOwner.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        let dataServices = browserManager.dataServices
        return Self(
            currentTab: { [weak browserManager] windowState in
                browserManager?.currentTab(for: windowState)
            },
            webView: { [weak browserManager] tab, windowState in
                browserManager?.getWebView(for: tab.id, in: windowState.id)
            },
            faviconService: {
                dataServices.faviconService
            },
            faviconImageService: {
                dataServices.faviconImageService
            },
            activeWindow: { [weak browserManager] in
                browserManager?.windowRegistry?.activeWindow
            },
            openNewTab: { [weak browserManager] urlString, context in
                browserManager?.openNewTab(url: urlString, context: context)
            },
            openHistoryURLsInNewWindow: { [weak browserManager] urls in
                browserManager?.openHistoryURLsInNewWindow(urls)
            }
        )
    }
}
