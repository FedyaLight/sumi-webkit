import Foundation

/// Owns the runtime contexts that the BrowserManager shell binding attaches to
/// the WebView coordinator and enforces their presence before
/// runtime-dependent WebView operations.
@MainActor
final class WebViewRuntimeContextStore {
    var visible: WebViewCoordinatorVisibleRuntimeContext?
    var browser: WebViewCoordinatorBrowserRuntimeContext?
    var initialDocument: InitialDocumentWebViewRuntimeContext?
    var shutdown: WebViewCoordinatorShutdownRuntimeContext?

    func requireBrowser() -> WebViewCoordinatorBrowserRuntimeContext {
        guard let browser else {
            preconditionFailure(
                "WebViewCoordinator browser runtime context is nil. "
                    + "Attach it via BrowserManager.webViewCoordinator before runtime-dependent WebView operations."
            )
        }
        return browser
    }

    func requireVisible() -> WebViewCoordinatorVisibleRuntimeContext {
        guard let visible else {
            preconditionFailure(
                "WebViewCoordinator visible runtime context is nil. Attach it via BrowserManager.webViewCoordinator before preparing visible WebViews."
            )
        }
        return visible
    }

    func requireInitialDocument() -> InitialDocumentWebViewRuntimeContext {
        guard let initialDocument else {
            preconditionFailure(
                "WebViewCoordinator initial document runtime context is nil. Attach it via BrowserManager.webViewCoordinator before rebuilding WebViews."
            )
        }
        return initialDocument
    }

    func requireShutdown() -> WebViewCoordinatorShutdownRuntimeContext {
        guard let shutdown else {
            preconditionFailure(
                "WebViewCoordinator shutdown runtime context is nil. Attach it via BrowserManager.webViewCoordinator before cleaning WebViews."
            )
        }
        return shutdown
    }
}
