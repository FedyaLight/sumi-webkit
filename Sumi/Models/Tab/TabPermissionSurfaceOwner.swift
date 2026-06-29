import Foundation
import WebKit

@MainActor
final class TabPermissionSurfaceOwner {
    private unowned let tab: Tab

    init(tab: Tab) {
        self.tab = tab
    }

    func currentPageId() -> String {
        "\(tab.id.uuidString.lowercased()):\(tab.extensionRuntimeDocumentSequence)"
    }

    func surfaceState(for webView: WKWebView?) -> (isActive: Bool, isVisible: Bool) {
        if let webView,
           isActiveGlancePreviewSurface(for: webView) {
            return (true, true)
        }
        return (tab.isCurrentTab, tab.primaryWindowId != nil)
    }

    func isActiveSurface(for webView: WKWebView?) -> Bool {
        surfaceState(for: webView).isActive
    }

    func isVisibleSurface(for webView: WKWebView?) -> Bool {
        surfaceState(for: webView).isVisible
    }

    func popupContext(for webView: WKWebView) -> SumiPopupPermissionTabContext? {
        guard let profile = tab.resolveProfile() else { return nil }

        let identity = pageIdentity()
        let committedURL = tab.extensionRuntimeCommittedMainDocumentURL
        return SumiPopupPermissionTabContext(
            tabId: identity.tabId,
            pageId: identity.pageId,
            profilePartitionId: profile.id.uuidString.lowercased(),
            isEphemeralProfile: profile.isEphemeral,
            committedURL: committedURL,
            visibleURL: webView.url ?? tab.url,
            mainFrameURL: committedURL ?? webView.url ?? tab.url,
            isActiveTab: tab.isCurrentTab,
            isVisibleTab: tab.primaryWindowId != nil,
            navigationOrPageGeneration: identity.pageGeneration
        )
    }

    func externalSchemeContext(for webView: WKWebView) -> SumiExternalSchemePermissionTabContext? {
        guard let profile = tab.resolveProfile() else { return nil }

        let identity = pageIdentity()
        let committedURL = tab.extensionRuntimeCommittedMainDocumentURL
        return SumiExternalSchemePermissionTabContext(
            tabId: identity.tabId,
            pageId: identity.pageId,
            profilePartitionId: profile.id.uuidString.lowercased(),
            isEphemeralProfile: profile.isEphemeral,
            committedURL: committedURL,
            visibleURL: webView.url ?? tab.url,
            mainFrameURL: committedURL ?? webView.url ?? tab.url,
            isActiveTab: tab.isCurrentTab,
            isVisibleTab: tab.primaryWindowId != nil,
            navigationOrPageGeneration: identity.pageGeneration,
            isCurrentPage: isCurrentPageClosure(
                pageId: identity.pageId,
                pageGeneration: identity.pageGeneration
            )
        )
    }

    func geolocationContext(for webView: WKWebView) -> SumiWebKitGeolocationTabContext? {
        guard let profile = tab.resolveProfile() else { return nil }

        let identity = pageIdentity()
        let committedURL = tab.extensionRuntimeCommittedMainDocumentURL
        let surfaceState = surfaceState(for: webView)
        return SumiWebKitGeolocationTabContext(
            tabId: identity.tabId,
            pageId: identity.pageId,
            profilePartitionId: profile.id.uuidString.lowercased(),
            isEphemeralProfile: profile.isEphemeral,
            committedURL: committedURL,
            visibleURL: webView.url ?? tab.url,
            mainFrameURL: committedURL ?? webView.url ?? tab.url,
            isActiveTab: surfaceState.isActive,
            isVisibleTab: surfaceState.isVisible,
            navigationOrPageGeneration: identity.pageGeneration,
            isCurrentPage: isCurrentPageClosure(
                pageId: identity.pageId,
                pageGeneration: identity.pageGeneration
            )
        )
    }

    func mediaCaptureContext(
        for webView: WKWebView,
        fallbackMainFrameURL: URL? = nil
    ) -> SumiWebKitMediaCaptureTabContext? {
        guard let profile = tab.resolveProfile() else { return nil }

        let identity = pageIdentity()
        let committedURL = tab.extensionRuntimeCommittedMainDocumentURL
        let surfaceState = surfaceState(for: webView)
        return SumiWebKitMediaCaptureTabContext(
            tabId: identity.tabId,
            pageId: identity.pageId,
            profilePartitionId: profile.id.uuidString.lowercased(),
            isEphemeralProfile: profile.isEphemeral,
            committedURL: committedURL,
            visibleURL: webView.url ?? tab.url,
            mainFrameURL: committedURL ?? fallbackMainFrameURL ?? webView.url ?? tab.url,
            isActiveTab: surfaceState.isActive,
            isVisibleTab: surfaceState.isVisible,
            navigationOrPageGeneration: identity.pageGeneration,
            isCurrentPage: isCurrentPageClosure(
                pageId: identity.pageId,
                pageGeneration: identity.pageGeneration
            )
        )
    }

    func filePickerContext(for webView: WKWebView) -> SumiFilePickerPermissionTabContext? {
        guard let profile = tab.resolveProfile() else { return nil }

        let identity = pageIdentity()
        let committedURL = tab.extensionRuntimeCommittedMainDocumentURL
        let surfaceState = surfaceState(for: webView)
        return SumiFilePickerPermissionTabContext(
            tabId: identity.tabId,
            pageId: identity.pageId,
            profilePartitionId: profile.id.uuidString.lowercased(),
            isEphemeralProfile: profile.isEphemeral,
            committedURL: committedURL,
            visibleURL: webView.url ?? tab.url,
            mainFrameURL: committedURL ?? webView.url ?? tab.url,
            isActiveTab: surfaceState.isActive,
            isVisibleTab: surfaceState.isVisible,
            navigationOrPageGeneration: identity.pageGeneration
        )
    }

    func storageAccessContext(for webView: WKWebView) -> SumiStorageAccessTabContext? {
        guard let profile = tab.resolveProfile() else { return nil }

        let identity = pageIdentity()
        let committedURL = tab.extensionRuntimeCommittedMainDocumentURL
        let surfaceState = surfaceState(for: webView)
        return SumiStorageAccessTabContext(
            tabId: identity.tabId,
            pageId: identity.pageId,
            profilePartitionId: profile.id.uuidString.lowercased(),
            isEphemeralProfile: profile.isEphemeral,
            committedURL: committedURL,
            visibleURL: webView.url ?? tab.url,
            mainFrameURL: committedURL ?? webView.url ?? tab.url,
            isActiveTab: surfaceState.isActive,
            isVisibleTab: surfaceState.isVisible,
            navigationOrPageGeneration: identity.pageGeneration,
            isCurrentPage: isCurrentPageClosure(
                pageId: identity.pageId,
                pageGeneration: identity.pageGeneration
            )
        )
    }

    func handleNormalTabPermissionNavigation(to targetURL: URL?) {
        let pageId = currentPageId()
        let tabId = tab.id.uuidString.lowercased()
        tab.browserManager?.permissionLifecycleController.handle(
            .mainFrameNavigation(
                pageId: pageId,
                tabId: tabId,
                profilePartitionId: tab.resolveProfile()?.id.uuidString,
                targetURL: targetURL,
                reason: "normal-tab-main-frame-navigation"
            )
        )
    }

    func cleanupNormalTabPermissionRuntime(reason: String) {
        let pageId = currentPageId()
        let tabId = tab.id.uuidString.lowercased()
        tab.browserManager?.permissionLifecycleController.handle(
            .tabClosed(
                pageId: pageId,
                tabId: tabId,
                profilePartitionId: tab.resolveProfile()?.id.uuidString,
                reason: reason
            )
        )
    }

    func invalidateCurrentPageForWebViewReplacement(reason: String) {
        let pageId = currentPageId()
        let tabId = tab.id.uuidString.lowercased()
        tab.browserManager?.permissionLifecycleController.handle(
            .webViewReplaced(
                pageId: pageId,
                tabId: tabId,
                profilePartitionId: tab.resolveProfile()?.id.uuidString,
                reason: reason
            )
        )
        tab.extensionRuntimeDocumentSequence &+= 1
    }

    private func isActiveGlancePreviewSurface(for webView: WKWebView) -> Bool {
        guard let browserManager = tab.browserManager,
              let session = browserManager.glanceManager.currentSession,
              session.previewTab.id == tab.id,
              session.previewTab.existingWebView === webView,
              let windowState = browserManager.windowRegistry?.windows[session.windowId],
              browserManager.glanceManager.activeSession(for: windowState)?.id == session.id
        else {
            return false
        }
        return true
    }

    private func pageIdentity() -> (tabId: String, pageGeneration: String, pageId: String) {
        let tabId = tab.id.uuidString.lowercased()
        let pageGeneration = String(tab.extensionRuntimeDocumentSequence)
        return (tabId, pageGeneration, "\(tabId):\(pageGeneration)")
    }

    private func isCurrentPageClosure(
        pageId: String,
        pageGeneration: String
    ) -> @MainActor @Sendable () -> Bool {
        let tab = self.tab
        return { [weak tab] in
            guard let tab else { return false }
            return tab.currentPermissionPageId() == pageId
                && String(tab.extensionRuntimeDocumentSequence) == pageGeneration
        }
    }
}
