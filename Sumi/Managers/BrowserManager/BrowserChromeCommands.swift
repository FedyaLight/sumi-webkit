import Foundation
import WebKit

/// Chrome-level command façade: popover presentation and page-privacy actions.
/// Absorbs the former `BrowserChromePopoverRoutingOwner` and
/// `BrowserPagePrivacyCommandOwner` so BrowserManager no longer holds two
/// separate `.live(browserManager:)` Owners for thin chrome routing.
@MainActor
final class BrowserChromeCommands {
    let downloadsPopoverPresenter: DownloadsPopoverPresenter
    let urlBarHubPopoverPresenter: URLBarHubPopoverPresenter

    private weak var browserManager: BrowserManager?

    init(browserManager: BrowserManager) {
        self.browserManager = browserManager
        let recovery = browserManager.sidebarHostRecoveryCoordinator
        self.downloadsPopoverPresenter = DownloadsPopoverPresenter(
            sidebarRecoveryCoordinator: recovery
        )
        self.urlBarHubPopoverPresenter = URLBarHubPopoverPresenter(
            sidebarRecoveryCoordinator: recovery
        )
    }

    // MARK: - Popovers

    private func syncPopoverRegistries() {
        let registry = browserManager?.windowRegistry
        downloadsPopoverPresenter.windowRegistry = registry
    }

    func showDownloads() {
        guard let windowState = browserManager?.windowRegistry?.activeWindow else { return }
        toggleDownloadsPopover(in: windowState)
    }

    func toggleDownloadsPopover(in windowState: BrowserWindowState) {
        syncPopoverRegistries()
        guard let downloadManager = browserManager?.downloadManager else { return }
        downloadsPopoverPresenter.toggle(in: windowState, downloadManager: downloadManager)
    }

    func closeDownloadsPopover(in windowState: BrowserWindowState) {
        syncPopoverRegistries()
        downloadsPopoverPresenter.close(in: windowState)
    }

    func toggleURLBarHubPopover(in windowState: BrowserWindowState) {
        syncPopoverRegistries()
        guard let browserContext = browserManager?.urlBarBundle.contextOwner.urlBarHubContext else { return }
        urlBarHubPopoverPresenter.toggle(
            in: windowState,
            browserContext: browserContext
        )
    }

    func presentURLBarHubPopover(in windowState: BrowserWindowState) {
        syncPopoverRegistries()
        guard let browserContext = browserManager?.urlBarBundle.contextOwner.urlBarHubContext else { return }
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
              let tab = browserManager.shellRuntime.activePageResolver
                .resolveActiveWindow()?.tab,
              !tab.representsSumiNativeSurface,
              let context = makePrivacyContext()
        else { return }
        browserManager.dataServices.privacyService.clearCurrentPageCookies(using: context)
    }

    func hardReloadCurrentPage() {
        guard let browserManager,
              let tab = browserManager.shellRuntime.activePageResolver
                .resolveActiveWindow()?.tab,
              !tab.representsSumiNativeSurface,
              let context = makePrivacyContext()
        else { return }
        browserManager.dataServices.privacyService.hardReloadCurrentPage(using: context)
    }

    private func makePrivacyContext() -> BrowserPrivacyService.Context? {
        guard browserManager != nil else { return nil }
        return BrowserPrivacyService.Context(
            currentDataStore: { [weak browserManager] in
                browserManager?.shellRuntime.activePageResolver
                    .resolveActiveWindow()?.tab.resolveProfile()?.dataStore
                    ?? browserManager?.currentProfile?.dataStore
                    ?? WKWebsiteDataStore.default()
            },
            currentTab: { [weak browserManager] in
                browserManager?.shellRuntime.activePageResolver
                    .resolveActiveWindow()?.tab
            },
            activeWindowId: { [weak browserManager] in
                browserManager?.windowRegistry?.activeWindow?.id
            },
            reloadWindowScopedPage: { [weak browserManager] tab, windowId, reason, policy in
                guard let browserManager,
                      let windowState = browserManager.windowRegistry?.windows[windowId]
                else { return }
                if let page = browserManager.shellRuntime.activePageResolver
                    .resolve(in: windowState),
                   page.source == .glancePreview,
                   page.tab.id == tab.id {
                    _ = page.tab.navigationCommandOwner.refresh(page.tab)
                    return
                }
                browserManager.webViewRoutingService.refreshPage(
                    for: tab,
                    in: windowState,
                    reason: reason,
                    policy: policy
                )
            }
        )
    }
}
