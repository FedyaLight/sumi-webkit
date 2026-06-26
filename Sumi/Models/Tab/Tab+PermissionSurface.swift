import Foundation
import WebKit

extension Tab {
    func currentPermissionPageId() -> String {
        "\(id.uuidString.lowercased()):\(extensionRuntimeDocumentSequence)"
    }

    func permissionRequestSurfaceState(for webView: WKWebView?) -> (isActive: Bool, isVisible: Bool) {
        if let webView,
           isActiveGlancePreviewSurface(for: webView) {
            return (true, true)
        }
        return (isCurrentTab, primaryWindowId != nil)
    }

    func permissionRequestIsActiveSurface(for webView: WKWebView?) -> Bool {
        permissionRequestSurfaceState(for: webView).isActive
    }

    func permissionRequestIsVisibleSurface(for webView: WKWebView?) -> Bool {
        permissionRequestSurfaceState(for: webView).isVisible
    }

    private func isActiveGlancePreviewSurface(for webView: WKWebView) -> Bool {
        guard let browserManager,
              let session = browserManager.glanceManager.currentSession,
              session.previewTab.id == id,
              session.previewTab.existingWebView === webView,
              let windowState = browserManager.windowRegistry?.windows[session.windowId],
              browserManager.glanceManager.activeSession(for: windowState)?.id == session.id
        else {
            return false
        }
        return true
    }

    func popupPermissionTabContext(for webView: WKWebView) -> SumiPopupPermissionTabContext? {
        guard let profile = resolveProfile() else { return nil }

        let tabId = id.uuidString.lowercased()
        let pageGeneration = String(extensionRuntimeDocumentSequence)
        let committedURL = extensionRuntimeCommittedMainDocumentURL
        return SumiPopupPermissionTabContext(
            tabId: tabId,
            pageId: "\(tabId):\(pageGeneration)",
            profilePartitionId: profile.id.uuidString.lowercased(),
            isEphemeralProfile: profile.isEphemeral,
            committedURL: committedURL,
            visibleURL: webView.url ?? url,
            mainFrameURL: committedURL ?? webView.url ?? url,
            isActiveTab: isCurrentTab,
            isVisibleTab: primaryWindowId != nil,
            navigationOrPageGeneration: pageGeneration
        )
    }

    func externalSchemePermissionTabContext(for webView: WKWebView) -> SumiExternalSchemePermissionTabContext? {
        guard let profile = resolveProfile() else { return nil }

        let tabId = id.uuidString.lowercased()
        let pageGeneration = String(extensionRuntimeDocumentSequence)
        let pageId = "\(tabId):\(pageGeneration)"
        let committedURL = extensionRuntimeCommittedMainDocumentURL
        return SumiExternalSchemePermissionTabContext(
            tabId: tabId,
            pageId: pageId,
            profilePartitionId: profile.id.uuidString.lowercased(),
            isEphemeralProfile: profile.isEphemeral,
            committedURL: committedURL,
            visibleURL: webView.url ?? url,
            mainFrameURL: committedURL ?? webView.url ?? url,
            isActiveTab: isCurrentTab,
            isVisibleTab: primaryWindowId != nil,
            navigationOrPageGeneration: pageGeneration,
            isCurrentPage: { [weak self] in
                guard let self else { return false }
                return self.currentPermissionPageId() == pageId
                    && String(self.extensionRuntimeDocumentSequence) == pageGeneration
            }
        )
    }

    func handleNormalTabPermissionNavigation(to targetURL: URL?) {
        let pageId = currentPermissionPageId()
        let tabId = id.uuidString.lowercased()
        browserManager?.permissionLifecycleController.handle(
            .mainFrameNavigation(
                pageId: pageId,
                tabId: tabId,
                profilePartitionId: resolveProfile()?.id.uuidString,
                targetURL: targetURL,
                reason: "normal-tab-main-frame-navigation"
            )
        )
    }

    func cleanupNormalTabPermissionRuntime(reason: String) {
        let pageId = currentPermissionPageId()
        let tabId = id.uuidString.lowercased()
        browserManager?.permissionLifecycleController.handle(
            .tabClosed(
                pageId: pageId,
                tabId: tabId,
                profilePartitionId: resolveProfile()?.id.uuidString,
                reason: reason
            )
        )
    }

    func invalidateCurrentPermissionPageForWebViewReplacement(reason: String) {
        let pageId = currentPermissionPageId()
        let tabId = id.uuidString.lowercased()
        browserManager?.permissionLifecycleController.handle(
            .webViewReplaced(
                pageId: pageId,
                tabId: tabId,
                profilePartitionId: resolveProfile()?.id.uuidString,
                reason: reason
            )
        )
        extensionRuntimeDocumentSequence &+= 1
    }
}
