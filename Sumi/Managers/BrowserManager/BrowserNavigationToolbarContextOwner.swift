import Foundation
import WebKit

@MainActor
final class BrowserNavigationToolbarContextOwner {
    struct Dependencies {
        let currentTab: @MainActor (BrowserWindowState) -> Tab?
        let webView: @MainActor (Tab, BrowserWindowState) -> WKWebView?
        let faviconService: @MainActor () -> any BrowserFaviconServicing
        let faviconImageService: @MainActor () -> any BrowserFaviconImageServicing
        let openURLInCurrentTab: @MainActor (URL, BrowserWindowState) -> Void
        let openNewTab: @MainActor (String, BrowserTabOpenContext) -> Void
        let openHistoryURLsInNewWindow: @MainActor ([URL]) -> Void
        let goBack: @MainActor (BrowserWindowState) -> Void
        let goForward: @MainActor (BrowserWindowState) -> Void
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
            historyContext: navigationHistoryContext(for: windowState),
            goBack: { [weak self, weak windowState] in
                guard let self, let windowState else { return }
                self.dependencies.goBack(windowState)
            },
            goForward: { [weak self, weak windowState] in
                guard let self, let windowState else { return }
                self.dependencies.goForward(windowState)
            }
        )
    }

    func navigationHistoryContext(
        for windowState: BrowserWindowState
    ) -> SumiNavigationHistoryContext {
        SumiNavigationHistoryContext(
            faviconService: dependencies.faviconService(),
            faviconImageService: dependencies.faviconImageService(),
            openURLInCurrentTab: { [weak self, weak windowState] url, _ in
                guard let self, let windowState else { return }
                self.dependencies.openURLInCurrentTab(url, windowState)
            },
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

        dependencies.openNewTab(url.absoluteString, context)
    }
}
