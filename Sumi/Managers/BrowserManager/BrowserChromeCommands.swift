import Foundation
import WebKit

/// Chrome-level command façade: popover presentation and page-privacy actions.
/// Absorbs the former `BrowserChromePopoverRoutingOwner` and
/// `BrowserPagePrivacyCommandOwner` so BrowserManager no longer holds two
/// separate `.live(browserManager:)` Owners for thin chrome routing.
@MainActor
final class BrowserChromeCommands {
    let downloadsPopoverPresenter = DownloadsPopoverPresenter()
    let urlBarHubPopoverPresenter = URLBarHubPopoverPresenter()

    private weak var browserManager: BrowserManager?

    init(browserManager: BrowserManager) {
        self.browserManager = browserManager
    }

    // MARK: - Popovers

    func showDownloads() {
        guard let windowState = browserManager?.windowRegistry?.activeWindow else { return }
        toggleDownloadsPopover(in: windowState)
    }

    func toggleDownloadsPopover(in windowState: BrowserWindowState) {
        guard let downloadManager = browserManager?.downloadManager else { return }
        downloadsPopoverPresenter.toggle(in: windowState, downloadManager: downloadManager)
    }

    func closeDownloadsPopover(in windowState: BrowserWindowState) {
        downloadsPopoverPresenter.close(in: windowState)
    }

    func toggleURLBarHubPopover(in windowState: BrowserWindowState) {
        guard let browserContext = browserManager?.urlBarContextOwner.urlBarHubContext else { return }
        urlBarHubPopoverPresenter.toggle(
            in: windowState,
            browserContext: browserContext
        )
    }

    func presentURLBarHubPopover(in windowState: BrowserWindowState) {
        guard let browserContext = browserManager?.urlBarContextOwner.urlBarHubContext else { return }
        urlBarHubPopoverPresenter.present(
            in: windowState,
            browserContext: browserContext
        )
    }

    func closeURLBarHubPopover(in windowState: BrowserWindowState) {
        urlBarHubPopoverPresenter.close(in: windowState)
    }

    // MARK: - Page privacy

    func clearCurrentPageCookies() {
        guard let browserManager,
              let tab = browserManager.activePageRoutingOwner.activePageTabForActiveWindow(),
              !tab.representsSumiNativeSurface,
              let context = makePrivacyContext()
        else { return }
        browserManager.dataServices.privacyService.clearCurrentPageCookies(using: context)
    }

    func hardReloadCurrentPage() {
        guard let browserManager,
              let tab = browserManager.activePageRoutingOwner.activePageTabForActiveWindow(),
              !tab.representsSumiNativeSurface,
              let context = makePrivacyContext()
        else { return }
        browserManager.dataServices.privacyService.hardReloadCurrentPage(using: context)
    }

    private func makePrivacyContext() -> BrowserPrivacyService.Context? {
        guard browserManager != nil else { return nil }
        return BrowserPrivacyService.Context(
            currentDataStore: { [weak browserManager] in
                browserManager?.activePageRoutingOwner.activePageTabForActiveWindow()?.resolveProfile()?.dataStore
                    ?? browserManager?.currentProfile?.dataStore
                    ?? WKWebsiteDataStore.default()
            },
            currentTab: { [weak browserManager] in
                browserManager?.activePageRoutingOwner.activePageTabForActiveWindow()
            },
            activeWindowId: { [weak browserManager] in
                browserManager?.windowRegistry?.activeWindow?.id
            },
            webViewLookup: { [weak browserManager] tab, windowId in
                browserManager?.webViewRoutingService.windowOwnedWebView(for: tab, in: windowId)
            },
            reloadWindowScopedPage: { [weak browserManager] tab, windowId, reason in
                guard let browserManager,
                      let windowState = browserManager.windowRegistry?.windows[windowId]
                else { return }
                browserManager.windowScopedNavigationOwner.refreshWindowScopedPage(
                    tab: tab,
                    in: windowState,
                    reason: reason
                )
            }
        )
    }
}
