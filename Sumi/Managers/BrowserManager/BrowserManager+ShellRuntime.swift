import Foundation

extension BrowserManager {
    /// Shared with app shell / `ContentView` via `.environment`; retained strongly so routing never sees a dangling coordinator.
    /// After `SumiApp.setupApplicationLifecycle` runs, this must be set before any WebView routing or coordinator cleanup.
    var webViewCoordinator: WebViewCoordinator? {
        get { shellRuntime.webViewCoordinator }
        set { shellRuntime.bindWebViewCoordinator(newValue) }
    }

    var webViewOwnershipService: WebViewOwnershipService? {
        shellRuntime.webViewCoordinator?.ownershipService
    }

    /// Use for cleanup and cross-window operations; fails fast if the coordinator was not wired (e.g. tests forgot to assign `webViewCoordinator`).
    var windowRegistry: WindowRegistry? {
        get { shellRuntime.windowRegistry }
        set { shellRuntime.bindWindowRegistry(newValue) }
    }

    /// App-shell owned factory for AppKit-created browser windows.
    var windowShellContentViewFactory: BrowserWindowShellService.ContentViewFactory? {
        get { shellRuntime.windowShellContentViewFactory }
        set { shellRuntime.windowShellContentViewFactory = newValue }
    }
}

extension BrowserManager: SumiProfileRoutingSupport {}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
