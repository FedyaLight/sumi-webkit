import Foundation

extension BrowserManager {
    /// App-shell registry attachment remains late because windows are created
    /// after the process-lifetime browser and WebView runtimes.
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
