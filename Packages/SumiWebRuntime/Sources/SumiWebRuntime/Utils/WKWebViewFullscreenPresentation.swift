import WebKit

@MainActor
public extension WKWebView {
    /// Whether WebKit is currently presenting an element in fullscreen. Element
    /// fullscreen is owned by `WKWebView.fullscreenState`, not by AppKit's
    /// `NSView` fullscreen mode flag.
    var sumiIsInFullscreenElementPresentation: Bool {
        fullscreenState != .notInFullscreen
    }
}
