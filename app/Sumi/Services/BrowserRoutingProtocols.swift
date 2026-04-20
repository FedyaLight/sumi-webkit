import AppKit
import Sparkle
import SwiftData
import WebKit

@MainActor
protocol BrowserCommandRouting: AnyObject {
    func openCommandPalette(
        in windowState: BrowserWindowState,
        reason: CommandPalettePresentationReason,
        prefill: String,
        navigateCurrentTab: Bool
    )
    func currentTab(for windowState: BrowserWindowState) -> Tab?
    func closeCurrentTab()
}

@MainActor
protocol WindowCommandRouting: AnyObject {
    func closeActiveWindow()
}

@MainActor
protocol WebViewLookup: AnyObject {
    func webView(for tabId: UUID, in windowId: UUID) -> WKWebView?
}

@MainActor
protocol ExternalURLHandling: AnyObject {
    func presentExternalURL(_ url: URL)
}

@MainActor
protocol BrowserPersistenceHandling: AnyObject {
    var modelContext: ModelContext { get }
    var tabRepository: TabRepositoryService { get }
    func cleanupAllTabs()
}

@MainActor
protocol BrowserUpdateHandling: AnyObject {
    func handleUpdaterFoundValidUpdate(_ item: SUAppcastItem)
    func handleUpdaterFinishedDownloading(_ item: SUAppcastItem)
    func handleUpdaterDidNotFindUpdate()
    func handleUpdaterAbortedUpdate()
    func handleUpdaterWillInstallOnQuit(_ item: SUAppcastItem)
}
