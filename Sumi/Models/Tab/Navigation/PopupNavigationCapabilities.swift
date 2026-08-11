import Foundation
import WebKit

@MainActor
protocol PopupPermissionEvaluating: AnyObject {
    func evaluate(
        _ request: SumiPopupPermissionRequest,
        tabContext: SumiPopupPermissionTabContext
    ) async -> SumiPopupPermissionResult

    func evaluateSynchronouslyForWebKitFallback(
        _ request: SumiPopupPermissionRequest,
        tabContext: SumiPopupPermissionTabContext
    ) -> SumiPopupPermissionResult
}

extension SumiPopupPermissionBridge: PopupPermissionEvaluating {}

@MainActor
protocol ExtensionPopupRequestConsuming: AnyObject {
    func consumeRecentlyOpenedExtensionTabRequestIfLoaded(
        for url: URL
    ) -> Bool
}

@MainActor
protocol ExtensionCreatedTabRegistering: AnyObject {
    func registerExtensionCreatedTabWithExtensionRuntimeIfLoaded(
        _ tab: Tab,
        reason: String
    )
}

extension SumiExtensionsModule: ExtensionPopupRequestConsuming,
    ExtensionCreatedTabRegistering {}

@MainActor
protocol ExtensionExternalTabOpening: AnyObject {
    func open(
        _ url: URL,
        from sourceWebView: FocusableWKWebView
    ) -> Bool
}

@MainActor
protocol PhysicalWebPopupOpening: AnyObject {
    func open(
        configuration: WKWebViewConfiguration,
        request: URLRequest,
        windowFeatures: WKWindowFeatures,
        from sourceWebView: FocusableWKWebView,
        isExtensionOriginated: Bool
    ) -> WKWebView?
}

@MainActor
protocol WebKitChildTabOpening: AnyObject {
    func open(
        configuration: WKWebViewConfiguration,
        requestURL: URL?,
        from sourceWebView: FocusableWKWebView,
        selected: Bool,
        isExtensionOriginated: Bool
    ) -> WKWebView?
}

@MainActor
protocol WebKitChildWindowOpening: AnyObject {
    func open(
        configuration: WKWebViewConfiguration,
        requestURL: URL?,
        from sourceWebView: FocusableWKWebView,
        activate: Bool,
        isExtensionOriginated: Bool
    ) -> WKWebView?
}

@MainActor
protocol AutomaticGlanceOpening: AnyObject {
    func openBrowserTab(
        _ url: URL,
        from sourceWebView: FocusableWKWebView,
        originRectInWindow: CGRect?
    ) -> Bool

    func openWebKitChild(
        configuration: WKWebViewConfiguration,
        requestURL: URL,
        from sourceWebView: FocusableWKWebView,
        originRectInWindow: CGRect?
    ) -> WKWebView?
}

@MainActor
protocol BackgroundTabOpenedNotifying: AnyObject {
    func presentBackgroundTabOpenedNotification(
        tabId: UUID,
        in windowState: BrowserWindowState
    )
}

extension BrowserNotificationPresenter: BackgroundTabOpenedNotifying {}

/// One exact browser command, kept separate from WebKit child construction.
/// The live closure weakly captures the session root at the composition edge.
@MainActor
struct BrowserTabSelectionCommand {
    private let action: @MainActor (
        Tab,
        BrowserWindowState,
        TabSelectionLoadPolicy
    ) -> Void

    init(
        _ action: @escaping @MainActor (
            Tab,
            BrowserWindowState,
            TabSelectionLoadPolicy
        ) -> Void
    ) {
        self.action = action
    }

    func select(
        _ tab: Tab,
        in window: BrowserWindowState,
        loadPolicy: TabSelectionLoadPolicy
    ) {
        action(tab, window, loadPolicy)
    }
}
