import Foundation

/// Owns the runtime contexts that the BrowserManager shell binding attaches to
/// the WebView coordinator and enforces their presence before
/// runtime-dependent WebView operations.
@MainActor
public final class WebViewRuntimeContextStore {
    public var visible: WebViewCoordinatorVisibleRuntimeContext?
    public var browser: WebViewCoordinatorBrowserRuntimeContext?
    public var initialDocument: InitialDocumentWebViewRuntimeContext?
    public var shutdown: WebViewCoordinatorShutdownRuntimeContext?

    public init() {}

    public func requireBrowser() -> WebViewCoordinatorBrowserRuntimeContext {
        guard let browser else {
            preconditionFailure(
                "WebViewCoordinator browser runtime context is nil. "
                    + "Attach it via the shell webViewCoordinator binding before runtime-dependent WebView operations."
            )
        }
        return browser
    }

    public func requireVisible() -> WebViewCoordinatorVisibleRuntimeContext {
        guard let visible else {
            preconditionFailure(
                "WebViewCoordinator visible runtime context is nil. Attach it via the shell webViewCoordinator binding before preparing visible WebViews."
            )
        }
        return visible
    }

    public func requireInitialDocument() -> InitialDocumentWebViewRuntimeContext {
        guard let initialDocument else {
            preconditionFailure(
                "WebViewCoordinator initial document runtime context is nil. Attach it via the shell webViewCoordinator binding before rebuilding WebViews."
            )
        }
        return initialDocument
    }

    public func requireShutdown() -> WebViewCoordinatorShutdownRuntimeContext {
        guard let shutdown else {
            preconditionFailure(
                "WebViewCoordinator shutdown runtime context is nil. Attach it via the shell webViewCoordinator binding before cleaning WebViews."
            )
        }
        return shutdown
    }
}
