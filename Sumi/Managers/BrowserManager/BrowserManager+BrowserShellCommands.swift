//
//  BrowserManager+BrowserShellCommands.swift
//  Sumi
//
//

@MainActor
extension BrowserManager {
    func showDownloads() {
        guard let windowState = windowRegistry?.activeWindow else { return }

        downloadsPopoverPresenter.toggle(in: windowState, downloadManager: downloadManager)
    }

    func showHistory() {
        openHistoryTab()
    }

    func toggleDownloadsPopover(in windowState: BrowserWindowState) {
        downloadsPopoverPresenter.toggle(in: windowState, downloadManager: downloadManager)
    }

    func closeDownloadsPopover(in windowState: BrowserWindowState) {
        downloadsPopoverPresenter.close(in: windowState)
    }

    func toggleURLBarHubPopover(in windowState: BrowserWindowState) {
        urlBarHubPopoverPresenter.toggle(
            in: windowState,
            browserContext: urlBarHubBrowserContext
        )
    }

    func presentURLBarHubPopover(in windowState: BrowserWindowState) {
        urlBarHubPopoverPresenter.present(
            in: windowState,
            browserContext: urlBarHubBrowserContext
        )
    }

    func closeURLBarHubPopover(in windowState: BrowserWindowState) {
        urlBarHubPopoverPresenter.close(in: windowState)
    }
}
