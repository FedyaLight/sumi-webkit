import SumiWebRuntime
import WebKit

/// Supplies the single physical shutdown capability without retaining a graph.
@MainActor
struct WebViewShutdownRuntimeProvider {
    let removeWebViewFromContainers: @MainActor (WKWebView) -> Void

    func runtime() -> SumiWebViewShutdown.NormalTabRuntime {
        SumiWebViewShutdown.NormalTabRuntime(
            removeWebViewFromContainers: removeWebViewFromContainers
        )
    }
}
