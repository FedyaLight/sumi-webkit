import AppKit
import SwiftData

@MainActor
protocol BrowserMouseButtonCommandRouting: AnyObject {
    func focusFloatingBar(
        in windowState: BrowserWindowState,
        prefill: String,
        navigateCurrentTab: Bool
    )
    func goBack(in windowState: BrowserWindowState)
    func goForward(in windowState: BrowserWindowState)
}

@MainActor
protocol BrowserTabCommandRouting: AnyObject {
    func closeCurrentTab()
    func closeCurrentTab(in windowState: BrowserWindowState)
}

@MainActor
protocol WindowCommandRouting: AnyObject {
    func closeActiveWindow()
    func closeWindow(_ windowState: BrowserWindowState)
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

@MainActor
protocol BrowserAppTerminationHandling: AnyObject {
    func dismissFloatingBarForActiveWindow(preserveDraft: Bool)
    func dismissWorkspaceThemePickerIfNeededCommitting()
    func performSiteDataPolicyAllWindowsClosedCleanup() async
}
