import AppKit
import SwiftData

@MainActor
protocol BrowserCommandRouting: AnyObject {
    func focusFloatingBar(
        in windowState: BrowserWindowState,
        prefill: String,
        navigateCurrentTab: Bool
    )
    func currentTab(for windowState: BrowserWindowState) -> Tab?
    func goBack(in windowState: BrowserWindowState)
    func goForward(in windowState: BrowserWindowState)
    func closeCurrentTab()
}

@MainActor
protocol WindowCommandRouting: AnyObject {
    func closeActiveWindow()
}

@MainActor
protocol BrowserWindowLifecycleHandling: AnyObject {
    var tabManager: TabManager { get }
    func persistWindowSession(for windowState: BrowserWindowState)
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
