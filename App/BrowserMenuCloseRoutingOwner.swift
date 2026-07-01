import AppKit

struct BrowserMenuCloseRoutingOwner {
    @MainActor
    func closeCurrentTab(
        keyWindow: NSWindow?,
        sender: Any?,
        windowRegistry: WindowRegistry?,
        closeCurrentTab: (BrowserWindowState) -> Void
    ) {
        route(
            keyWindow: keyWindow,
            sender: sender,
            windowRegistry: windowRegistry,
            routeManagedWindow: closeCurrentTab
        )
    }

    @MainActor
    func closeWindow(
        keyWindow: NSWindow?,
        sender: Any?,
        windowRegistry: WindowRegistry?,
        closeWindow: (BrowserWindowState) -> Void
    ) {
        route(
            keyWindow: keyWindow,
            sender: sender,
            windowRegistry: windowRegistry,
            routeManagedWindow: closeWindow
        )
    }

    @MainActor
    private func route(
        keyWindow: NSWindow?,
        sender: Any?,
        windowRegistry: WindowRegistry?,
        routeManagedWindow: (BrowserWindowState) -> Void
    ) {
        if let keyWindow {
            guard let windowState = browserWindowState(matching: keyWindow, in: windowRegistry) else {
                keyWindow.performClose(sender)
                return
            }
            routeManagedWindow(windowState)
            return
        }

        if let activeWindow = windowRegistry?.activeWindow {
            routeManagedWindow(activeWindow)
        }
    }

    @MainActor
    private func browserWindowState(
        matching keyWindow: NSWindow,
        in windowRegistry: WindowRegistry?
    ) -> BrowserWindowState? {
        windowRegistry?.windows.values.first { $0.window === keyWindow }
    }
}
