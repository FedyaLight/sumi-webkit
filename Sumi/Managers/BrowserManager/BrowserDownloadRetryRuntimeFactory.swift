import Foundation

@MainActor
enum BrowserDownloadRetryRuntimeFactory {
    static func runtime(for browserManager: BrowserManager) -> DownloadManager.RetryRuntime {
        DownloadManager.RetryRuntime(
            activeWindow: { [weak browserManager] in
                browserManager?.windowRegistry?.activeWindow
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.currentTab(for: windowState)
            },
            windowOwnedWebView: { [weak browserManager] tab, windowId in
                browserManager?.windowOwnedWebView(for: tab, in: windowId)
            }
        )
    }
}
