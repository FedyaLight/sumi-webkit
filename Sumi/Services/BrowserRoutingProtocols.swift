import AppKit
import SwiftData
import WebKit

@MainActor
protocol BrowserCommandRouting: AnyObject {
    func focusFloatingBar(
        in windowState: BrowserWindowState,
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
    func cleanupAllTabs()
    func flushPendingWindowSessionPersistence()
    func flushRuntimeStatePersistenceAwaitingResult() async -> Int
    func persistFullReconcileAwaitingResult(reason: String) async -> Bool
}
