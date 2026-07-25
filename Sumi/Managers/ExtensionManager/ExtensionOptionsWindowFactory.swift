import AppKit

/// Builds the physical AppKit window an extension options page is presented in:
/// its chrome, its default content rect, and the release-ownership policy that
/// keeps the registry — not AppKit's legacy close-time release — in charge of
/// the window's lifetime.
@available(macOS 15.5, *)
@MainActor
enum ExtensionOptionsWindowFactory {
    static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        // The registry, rather than AppKit's legacy close-time release,
        // owns extension windows until their WebView teardown completes.
        window.isReleasedWhenClosed = false
        return window
    }
}
