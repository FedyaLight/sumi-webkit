import AppKit
import WebKit

/// Single owner for every WebKit element-fullscreen presentation concern of a
/// `WKWebView`: presentation state, the native placeholder view, and the
/// programmatic exit path.
///
/// While an element is presented fullscreen, WebKit moves the web content into
/// its own private FullScreen `NSWindow` and leaves a native
/// `_fullScreenPlaceholderView` in the original location. The compositor drives
/// this placeholder (via ``tabContentView``) during space/tab switches so the
/// live web view is never reparented out from under the fullscreen presentation.
@MainActor
public struct WKWebViewFullscreenPresentation {
    public let webView: WKWebView

    public init(webView: WKWebView) {
        self.webView = webView
    }

    private enum Selector {
        static let placeholderView = NSSelectorFromString("_fullScreenPlaceholderView")
    }

    /// Whether WebKit is currently presenting an element in fullscreen.
    public var isPresentingElement: Bool {
        webView.fullscreenState != .notInFullscreen
    }

    /// WebKit's native fullscreen placeholder snapshot, present only while an
    /// element is fullscreen. Returns `nil` when the private accessor is
    /// unavailable, degrading to the web view itself via ``tabContentView``.
    public var placeholderView: NSView? {
        guard webView.responds(to: Selector.placeholderView) else {
            return nil
        }
        return webView.value(
            forKey: NSStringFromSelector(Selector.placeholderView)
        ) as? NSView
    }

    /// The view that represents this tab's content in the compositor: the native
    /// fullscreen placeholder while an element is presented, otherwise the web
    /// view itself.
    public var tabContentView: NSView {
        placeholderView ?? webView
    }

    /// Initiates a programmatic exit from media fullscreen via the documented
    /// `closeAllMediaPresentations()`, which closes out-of-window media
    /// presentations (`<video>` fullscreen and Picture in Picture). Fire-and-
    /// forget: teardown of the underlying web view is gated on the
    /// `fullscreenState` observer, not on this call returning.
    public func requestExit() {
        let webView = webView
        Task { @MainActor in
            await webView.closeAllMediaPresentations()
        }
    }
}

@MainActor
public extension WKWebView {
    var sumiFullscreenPresentation: WKWebViewFullscreenPresentation {
        WKWebViewFullscreenPresentation(webView: self)
    }

    /// Whether WebKit is currently presenting an element in fullscreen. Element
    /// fullscreen is owned by `WKWebView.fullscreenState`, not by AppKit's
    /// `NSView` fullscreen mode flag.
    var sumiIsInFullscreenElementPresentation: Bool {
        sumiFullscreenPresentation.isPresentingElement
    }
}
