import Foundation
import SumiDomain
import WebKit

@MainActor
final class BrowserNavigationToolbarContextOwner {
    private let windowTabs: BrowserWindowTabContext
    private let webViews: BrowserWebViewRoutingService
    private let dataServices: BrowserManagerDataServices
    private let history: BrowserHistoryNavigationOwner
    private let tabOpening: BrowserTabOpeningOwner

    init(
        windowTabs: BrowserWindowTabContext,
        webViews: BrowserWebViewRoutingService,
        dataServices: BrowserManagerDataServices,
        history: BrowserHistoryNavigationOwner,
        tabOpening: BrowserTabOpeningOwner
    ) {
        self.windowTabs = windowTabs
        self.webViews = webViews
        self.dataServices = dataServices
        self.history = history
        self.tabOpening = tabOpening
    }

    func navigationToolbarContext(
        for windowState: BrowserWindowState
    ) -> NavigationToolbarBrowserContext {
        NavigationToolbarBrowserContext(
            currentTab: { [weak self, weak windowState] in
                guard let self, let windowState else { return nil }
                return self.windowTabs.currentTab(for: windowState)
            },
            webView: { [weak self, weak windowState] tab in
                guard let self, let windowState else { return nil }
                return self.webViews.windowOwnedWebView(
                    for: tab,
                    in: windowState.id
                )
            },
            historyContext: navigationHistoryContext(for: windowState),
            goBack: { [weak self, weak windowState] in
                guard let self, let windowState else { return }
                self.history.goBack(in: windowState)
            },
            goForward: { [weak self, weak windowState] in
                guard let self, let windowState else { return }
                self.history.goForward(in: windowState)
            },
            reload: { [weak self, weak windowState] tab in
                guard let self, let windowState else { return }
                _ = self.webViews.refreshPage(
                    for: tab,
                    in: windowState,
                    reason: "NavigationToolbar.reload"
                )
            }
        )
    }

    func navigationHistoryContext(
        for windowState: BrowserWindowState
    ) -> SumiNavigationHistoryContext {
        SumiNavigationHistoryContext(
            faviconService: dataServices.faviconService,
            faviconImageReader: dataServices.faviconCapabilities.images,
            openURLInCurrentTab: { [weak self, weak windowState] url, _ in
                guard let self, let windowState else { return }
                self.history.openHistoryURL(
                    url,
                    in: windowState,
                    preferredOpenMode: .currentTab
                )
            },
            openURLInNewTab: { [weak self, weak windowState] url, selected, sourceTab in
                self?.openURLFromNavigationHistory(
                    url: url,
                    selected: selected,
                    sourceTab: sourceTab,
                    windowState: windowState
                )
            },
            openURLsInNewWindow: { [history] urls in
                history.openHistoryURLsInNewWindow(urls)
            }
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

        tabOpening.openNewTab(url: url.absoluteString, context: context)
    }
}
