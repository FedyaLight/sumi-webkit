import AppKit
import WebKit

/// Chooses the admitted child request's final presentation without owning
/// permission or source-document validation.
@MainActor
final class WebKitChildPresentationRouter {
    struct Request {
        let tab: Tab
        let childRequest: WebKitChildSurfaceRouter.Request
        let modifierFlags: NSEvent.ModifierFlags
        let isMiddleButtonClick: Bool
        let shouldDownload: Bool
    }

    private let automaticGlance: (any AutomaticGlanceOpening)?
    private let childSurfaceRouter: WebKitChildSurfaceRouter

    init(
        automaticGlance: (any AutomaticGlanceOpening)?,
        childSurfaceRouter: WebKitChildSurfaceRouter
    ) {
        self.automaticGlance = automaticGlance
        self.childSurfaceRouter = childSurfaceRouter
    }

    func open(_ request: Request) -> WKWebView? {
        let child = request.childRequest
        if AutomaticGlancePolicy.shouldPresent(
            child.navigationRequest.url,
            from: request.tab,
            ordinaryPolicy: child.policy,
            modifierFlags: request.modifierFlags,
            isExtensionOriginated: child.isExtensionOriginated,
            isMiddleButtonClick: request.isMiddleButtonClick,
            shouldDownload: request.shouldDownload
        ),
           let targetURL = child.navigationRequest.url,
           let webView = automaticGlance?.openWebKitChild(
               configuration: child.configuration,
               requestURL: targetURL,
               from: child.sourceWebView,
               originRectInWindow: child.sourceWebView.gestures
                   .recentGlanceOriginRect(maxAge: 2)
           ) {
            child.sourceWebView.gestures.clear(ifCurrent: child.gestureReceipt)
            return webView
        }
        return childSurfaceRouter.open(child)
    }
}
