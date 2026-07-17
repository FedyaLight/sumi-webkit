import Foundation
import WebKit

@MainActor
final class BrowserChromeCommands {
    let downloadsPopoverPresenter: DownloadsPopoverPresenter
    let urlBarHubPopoverPresenter: URLBarHubPopoverPresenter

    private let windows: WindowRegistry
    private let downloads: DownloadManager
    private let privacy: BrowserPagePrivacyCommandOwner

    init(
        windows: WindowRegistry,
        downloads: DownloadManager,
        privacy: BrowserPagePrivacyCommandOwner,
        downloadsPopoverPresenter: DownloadsPopoverPresenter,
        urlBarHubPopoverPresenter: URLBarHubPopoverPresenter
    ) {
        self.windows = windows
        self.downloads = downloads
        self.privacy = privacy
        self.downloadsPopoverPresenter = downloadsPopoverPresenter
        self.urlBarHubPopoverPresenter = urlBarHubPopoverPresenter
    }

    func showDownloads() {
        guard let windowState = windows.activeWindow else { return }
        toggleDownloadsPopover(in: windowState)
    }

    func toggleDownloadsPopover(in windowState: BrowserWindowState) {
        downloadsPopoverPresenter.windowRegistry = windows
        downloadsPopoverPresenter.toggle(
            in: windowState,
            downloadManager: downloads
        )
    }

    func closeDownloadsPopover(in windowState: BrowserWindowState) {
        downloadsPopoverPresenter.windowRegistry = windows
        downloadsPopoverPresenter.close(in: windowState)
    }

    func toggleURLBarHubPopover(
        in windowState: BrowserWindowState,
        browserContext: URLBarHubBrowserContext
    ) {
        urlBarHubPopoverPresenter.toggle(
            in: windowState,
            browserContext: browserContext
        )
    }

    func presentURLBarHubPopover(
        in windowState: BrowserWindowState,
        browserContext: URLBarHubBrowserContext
    ) {
        urlBarHubPopoverPresenter.present(
            in: windowState,
            browserContext: browserContext
        )
    }

    func closeURLBarHubPopover(in windowState: BrowserWindowState) {
        urlBarHubPopoverPresenter.close(in: windowState)
    }

    func clearCurrentPageCookies() {
        privacy.clearCurrentPageCookies()
    }

    func hardReloadCurrentPage() {
        privacy.hardReloadCurrentPage()
    }
}
