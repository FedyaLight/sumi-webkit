import Foundation

/// Presents and dismisses chrome popovers (downloads, URL-bar hub),
/// owning their presenters.
@MainActor
final class BrowserChromePopoverRoutingOwner {
    struct Dependencies {
        let activeWindow: @MainActor () -> BrowserWindowState?
        let downloadManager: @MainActor () -> DownloadManager?
        let urlBarHubBrowserContext: @MainActor () -> URLBarHubBrowserContext?
    }

    let downloadsPopoverPresenter = DownloadsPopoverPresenter()
    let urlBarHubPopoverPresenter = URLBarHubPopoverPresenter()
    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func showDownloads() {
        guard let windowState = dependencies.activeWindow() else { return }
        toggleDownloadsPopover(in: windowState)
    }

    func toggleDownloadsPopover(in windowState: BrowserWindowState) {
        guard let downloadManager = dependencies.downloadManager() else { return }
        downloadsPopoverPresenter.toggle(in: windowState, downloadManager: downloadManager)
    }

    func closeDownloadsPopover(in windowState: BrowserWindowState) {
        downloadsPopoverPresenter.close(in: windowState)
    }

    func toggleURLBarHubPopover(in windowState: BrowserWindowState) {
        guard let browserContext = dependencies.urlBarHubBrowserContext() else { return }
        urlBarHubPopoverPresenter.toggle(
            in: windowState,
            browserContext: browserContext
        )
    }

    func presentURLBarHubPopover(in windowState: BrowserWindowState) {
        guard let browserContext = dependencies.urlBarHubBrowserContext() else { return }
        urlBarHubPopoverPresenter.present(
            in: windowState,
            browserContext: browserContext
        )
    }

    func closeURLBarHubPopover(in windowState: BrowserWindowState) {
        urlBarHubPopoverPresenter.close(in: windowState)
    }
}

extension BrowserChromePopoverRoutingOwner.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            activeWindow: { [weak browserManager] in
                browserManager?.windowRegistry?.activeWindow
            },
            downloadManager: { [weak browserManager] in
                browserManager?.downloadManager
            },
            urlBarHubBrowserContext: { [weak browserManager] in
                browserManager?.urlBarContextOwner.urlBarHubContext
            }
        )
    }
}
