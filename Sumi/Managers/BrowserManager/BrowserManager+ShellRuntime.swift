import Foundation

extension BrowserManager {
    /// App-shell owned factory for AppKit-created browser windows.
    var windowShellContentViewFactory: BrowserWindowShellService.ContentViewFactory? {
        get { shellRuntime.windowShellContentViewFactory }
        set { shellRuntime.windowShellContentViewFactory = newValue }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
