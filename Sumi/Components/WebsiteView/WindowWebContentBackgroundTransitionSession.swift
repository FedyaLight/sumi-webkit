import WebKit
import SumiWebRuntime

@MainActor
final class WindowWebContentBackgroundTransitionSession {
    private let compositorRuntime: WebViewCompositorRuntime
    private var leasesByWebViewID: [
        ObjectIdentifier: WebViewBackgroundTransitionLease
    ] = [:]

    init(compositorRuntime: WebViewCompositorRuntime) {
        self.compositorRuntime = compositorRuntime
    }

    func begin(for webView: WKWebView) {
        let webViewID = ObjectIdentifier(webView)
        leasesByWebViewID[webViewID] = compositorRuntime
            .beginBackgroundTransition(for: webView)
    }

    func scheduleRestore(
        for webView: WKWebView,
        containerRegistration: WebViewCompositorContainerRegistration
    ) {
        guard let lease = leasesByWebViewID[ObjectIdentifier(webView)] else {
            return
        }
        compositorRuntime.scheduleBackgroundRestore(
            matching: lease,
            containerRegistration: containerRegistration
        )
    }

    func finish(for webView: WKWebView) {
        guard let lease = leasesByWebViewID.removeValue(
            forKey: ObjectIdentifier(webView)
        ) else {
            return
        }
        compositorRuntime.finishBackgroundTransition(matching: lease)
    }

    func settle(_ webView: WKWebView) {
        if leasesByWebViewID[ObjectIdentifier(webView)] == nil {
            begin(for: webView)
        }
        finish(for: webView)
    }
}
