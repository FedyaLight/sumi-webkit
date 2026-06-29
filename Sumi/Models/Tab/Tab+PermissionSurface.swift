import Foundation
import WebKit

extension Tab {
    func currentPermissionPageId() -> String {
        permissionSurfaceOwner.currentPageId()
    }

    func permissionRequestSurfaceState(for webView: WKWebView?) -> (isActive: Bool, isVisible: Bool) {
        permissionSurfaceOwner.surfaceState(for: webView)
    }

    func permissionRequestIsActiveSurface(for webView: WKWebView?) -> Bool {
        permissionSurfaceOwner.isActiveSurface(for: webView)
    }

    func permissionRequestIsVisibleSurface(for webView: WKWebView?) -> Bool {
        permissionSurfaceOwner.isVisibleSurface(for: webView)
    }

    func popupPermissionTabContext(for webView: WKWebView) -> SumiPopupPermissionTabContext? {
        permissionSurfaceOwner.popupContext(for: webView)
    }

    func externalSchemePermissionTabContext(for webView: WKWebView) -> SumiExternalSchemePermissionTabContext? {
        permissionSurfaceOwner.externalSchemeContext(for: webView)
    }

    func handleNormalTabPermissionNavigation(to targetURL: URL?) {
        permissionSurfaceOwner.handleNormalTabPermissionNavigation(to: targetURL)
    }

    func cleanupNormalTabPermissionRuntime(reason: String) {
        permissionSurfaceOwner.cleanupNormalTabPermissionRuntime(reason: reason)
    }

    func invalidateCurrentPermissionPageForWebViewReplacement(reason: String) {
        permissionSurfaceOwner.invalidateCurrentPageForWebViewReplacement(reason: reason)
    }
}
