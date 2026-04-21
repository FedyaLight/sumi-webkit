import AppKit
@testable import Sumi

@MainActor
enum WindowChromeTestSupport {
    static let standardButtonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    static var retainedWindows: [NSWindow] = []

    static func retain(_ window: NSWindow) {
        retainedWindows.append(window)
    }

    static func makeBrowserWindow(size: NSSize = NSSize(width: 320, height: 240)) -> NSWindow {
        let window = SumiBrowserWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.prepareNativeWindowControlsForBrowserChrome(buttonTypes: standardButtonTypes)
        return window
    }

    static func makePlainWindow(size: NSSize = NSSize(width: 320, height: 240)) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }
}
