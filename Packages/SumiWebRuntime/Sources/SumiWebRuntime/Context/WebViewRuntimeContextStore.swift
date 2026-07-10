import Foundation

public struct WebViewRuntimeEnvironment {
    public let visible: WebViewCoordinatorVisibleRuntimeContext
    public let browser: WebViewCoordinatorBrowserRuntimeContext
    public let initialDocument: InitialDocumentWebViewRuntimeContext
    public let shutdown: WebViewCoordinatorShutdownRuntimeContext

    public init(
        visible: WebViewCoordinatorVisibleRuntimeContext,
        browser: WebViewCoordinatorBrowserRuntimeContext,
        initialDocument: InitialDocumentWebViewRuntimeContext,
        shutdown: WebViewCoordinatorShutdownRuntimeContext
    ) {
        self.visible = visible
        self.browser = browser
        self.initialDocument = initialDocument
        self.shutdown = shutdown
    }
}

/// Owns the runtime contexts that the BrowserManager shell binding attaches to
/// the WebView coordinator and enforces their presence before
/// runtime-dependent WebView operations.
@MainActor
public final class WebViewRuntimeContextStore {
    public private(set) var environment: WebViewRuntimeEnvironment?

    public init() {}

    public var browser: WebViewCoordinatorBrowserRuntimeContext? {
        environment?.browser
    }

    public func attach(_ environment: WebViewRuntimeEnvironment) {
        self.environment = environment
    }

    public func detach() {
        environment = nil
    }

    public func requireBrowser() -> WebViewCoordinatorBrowserRuntimeContext {
        guard let browser = environment?.browser else {
            preconditionFailure(
                "WebViewCoordinator browser runtime context is nil. "
                    + "Attach it via the shell webViewCoordinator binding before runtime-dependent WebView operations."
            )
        }
        return browser
    }

    public func requireVisible() -> WebViewCoordinatorVisibleRuntimeContext {
        guard let visible = environment?.visible else {
            preconditionFailure(
                "WebViewCoordinator visible runtime context is nil. Attach it via the shell webViewCoordinator binding before preparing visible WebViews."
            )
        }
        return visible
    }

    public func requireInitialDocument() -> InitialDocumentWebViewRuntimeContext {
        guard let initialDocument = environment?.initialDocument else {
            preconditionFailure(
                "WebViewCoordinator initial document runtime context is nil. Attach it via the shell webViewCoordinator binding before rebuilding WebViews."
            )
        }
        return initialDocument
    }

    public func requireShutdown() -> WebViewCoordinatorShutdownRuntimeContext {
        guard let shutdown = environment?.shutdown else {
            preconditionFailure(
                "WebViewCoordinator shutdown runtime context is nil. Attach it via the shell webViewCoordinator binding before cleaning WebViews."
            )
        }
        return shutdown
    }
}
