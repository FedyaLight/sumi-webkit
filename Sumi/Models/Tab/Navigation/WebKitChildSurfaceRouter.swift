import Foundation
import SumiDomain
import SumiWebRuntime
import WebKit

/// Routes one already-authorized WebKit child request to its exact browser
/// surface. Admission and permission state live in
/// `WebKitChildWebViewTransaction`; this type owns only disposition.
@MainActor
final class WebKitChildSurfaceRouter {
    struct Request {
        let configuration: WKWebViewConfiguration
        let navigationRequest: URLRequest
        let windowFeatures: WKWindowFeatures
        let sourceWebView: FocusableWKWebView
        let sourceURL: URL?
        let policy: SumiNewWindowPolicy
        let isExtensionOriginated: Bool
        let gestureReceipt: WebViewGestureReceipt?
    }

    private let extensionTabs: (any ExtensionExternalTabOpening)?
    private let webPopups: (any PhysicalWebPopupOpening)?
    private let childTabs: (any WebKitChildTabOpening)?
    private let childWindows: (any WebKitChildWindowOpening)?

    init(
        extensionTabs: (any ExtensionExternalTabOpening)?,
        webPopups: (any PhysicalWebPopupOpening)?,
        childTabs: (any WebKitChildTabOpening)?,
        childWindows: (any WebKitChildWindowOpening)?
    ) {
        self.extensionTabs = extensionTabs
        self.webPopups = webPopups
        self.childTabs = childTabs
        self.childWindows = childWindows
    }

    func open(_ request: Request) -> WKWebView? {
        let targetURL = request.navigationRequest.url
        guard targetURL?.sumiNavigationalScheme != .javascript else {
            return nil
        }
        if request.policy.isPopup,
           let targetURL,
           SumiSurface.isNativeSurfaceURL(targetURL) {
            return nil
        }

        if let targetURL,
           SumiPopupNavigationOrigin
            .isExtensionOriginatedExternalPopupNavigation(
                sourceURL: request.sourceURL,
                requestURL: targetURL
            ) {
            if extensionTabs?.open(
                targetURL,
                from: request.sourceWebView
            ) == true {
                clearGesture(for: request)
            }
            return nil
        }

        if request.policy.isPopup {
            let popupWebView = webPopups?.open(
                configuration: request.configuration,
                request: request.navigationRequest,
                windowFeatures: request.windowFeatures,
                from: request.sourceWebView,
                isExtensionOriginated: request.isExtensionOriginated
            )
            if popupWebView != nil {
                clearGesture(for: request)
            }
            return popupWebView
        }

        if case .window(let active) = request.policy {
            let childWebView = childWindows?.open(
                configuration: request.configuration,
                requestURL: targetURL,
                from: request.sourceWebView,
                activate: active,
                isExtensionOriginated: request.isExtensionOriginated
            )
            if childWebView != nil {
                clearGesture(for: request)
            }
            return childWebView
        }

        WebContentProcessDisplayNameProvider.apply(
            WebContentProcessDisplayNameProvider.popup,
            to: request.configuration
        )
        guard case .tab(let selected) = request.policy else {
            return nil
        }
        let childWebView = childTabs?.open(
            configuration: request.configuration,
            requestURL: targetURL,
            from: request.sourceWebView,
            selected: selected,
            isExtensionOriginated: request.isExtensionOriginated
        )
        if childWebView != nil {
            clearGesture(for: request)
        }
        return childWebView
    }

    private func clearGesture(for request: Request) {
        request.sourceWebView.gestures.clear(
            ifCurrent: request.gestureReceipt
        )
    }
}
