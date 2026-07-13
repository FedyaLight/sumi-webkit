import AppKit
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPopupFocusReceipt {
    weak var window: NSWindow?
    weak var windowState: BrowserWindowState?
    weak var tab: Tab?
    weak var webView: WKWebView?
    weak var responder: NSResponder?

    init(
        window: NSWindow,
        windowState: BrowserWindowState,
        tab: Tab,
        webView: WKWebView,
        responder: NSResponder
    ) {
        self.window = window
        self.windowState = windowState
        self.tab = tab
        self.webView = webView
        self.responder = responder
    }
}

/// Restores focus only when the exact pre-popup source still owns the window
/// and no live responder chosen by the user would be displaced.
@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPopupFocusRestorer {
    private let windows: @MainActor () -> (any ExtensionWindowQuery)?
    private let liveWebView: @MainActor (Tab) -> WKWebView?

    init(
        windows: @escaping @MainActor () -> (any ExtensionWindowQuery)?,
        liveWebView: @escaping @MainActor (Tab) -> WKWebView?
    ) {
        self.windows = windows
        self.liveWebView = liveWebView
    }

    func capture(
        source: ExtensionActionPopupSourceReceipt?
    ) -> ExtensionActionPopupFocusReceipt? {
        guard let resolved = source?.resolveFocusSource(),
              windows()?.currentExtensionTab(in: resolved.windowState)
                  === resolved.tab,
              let webView = liveWebView(resolved.tab),
              webView.window === resolved.window,
              resolved.window.isKeyWindow,
              let responder = resolved.window.firstResponder,
              Self.responder(responder, isInside: webView)
        else {
            return nil
        }
        return ExtensionActionPopupFocusReceipt(
            window: resolved.window,
            windowState: resolved.windowState,
            tab: resolved.tab,
            webView: webView,
            responder: responder
        )
    }

    func transfer(
        _ receipt: ExtensionActionPopupFocusReceipt?,
        to source: ExtensionActionPopupSourceReceipt?
    ) -> ExtensionActionPopupFocusReceipt? {
        guard let receipt,
              let resolved = source?.resolveFocusSource(),
              receipt.window === resolved.window,
              receipt.windowState === resolved.windowState,
              receipt.tab === resolved.tab,
              receipt.webView === liveWebView(resolved.tab),
              windows()?.currentExtensionTab(in: resolved.windowState)
                  === resolved.tab
        else {
            return nil
        }
        return receipt
    }

    func restore(
        _ receipt: ExtensionActionPopupFocusReceipt?,
        ifCurrent: @escaping @MainActor () -> Bool
    ) {
        guard let receipt else { return }
        DispatchQueue.main.async { [receipt] in
            guard ifCurrent(),
                  let window = receipt.window,
                  let windowState = receipt.windowState,
                  let tab = receipt.tab,
                  let webView = receipt.webView,
                  let capturedResponder = receipt.responder,
                  window.isKeyWindow,
                  self.windows()?.appKitWindow(for: windowState) === window,
                  self.windows()?.currentExtensionTab(in: windowState) === tab,
                  self.liveWebView(tab) === webView,
                  webView.window === window,
                  webView.superview != nil,
                  Self.responder(capturedResponder, isInside: webView),
                  webView.sumiIsInFullscreenElementPresentation == false
            else {
                return
            }
            let responder = window.firstResponder
            if Self.responder(responder, isInside: webView) {
                return
            }
            guard responder == nil
                    || responder === window.windowController
            else {
                return
            }
            _ = window.makeFirstResponder(capturedResponder)
        }
    }

    private static func responder(
        _ responder: NSResponder?,
        isInside webView: WKWebView
    ) -> Bool {
        guard let responder else { return false }
        if responder === webView { return true }
        guard let responderView = responder as? NSView else { return false }
        return responderView.isDescendant(of: webView)
    }
}
