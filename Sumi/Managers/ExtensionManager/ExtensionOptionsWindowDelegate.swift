import AppKit
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionOptionsWindowDelegate: NSObject, NSWindowDelegate, WKUIDelegate {
    private(set) var receipt: ExtensionOptionsWindowReceipt?
    private weak var service: ExtensionOptionsWindowService?
    private weak var webView: WKWebView?
    private weak var window: NSWindow?
    var isCleaningUp = false

    init(
        service: ExtensionOptionsWindowService,
        webView: WKWebView,
        window: NSWindow
    ) {
        self.service = service
        self.webView = webView
        self.window = window
        super.init()
    }

    func bind(_ receipt: ExtensionOptionsWindowReceipt) {
        precondition(self.receipt == nil)
        self.receipt = receipt
    }

    func windowWillClose(_ notification: Notification) {
        guard isCleaningUp == false, let receipt else { return }
        service?.retire(
            receipt,
            window: notification.object as? NSWindow,
            webView: webView,
            shouldOrderOut: false
        )
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard isCleaningUp == false, let receipt else { return }
        service?.retire(
            receipt,
            window: window,
            webView: webView,
            shouldOrderOut: true
        )
    }
}
