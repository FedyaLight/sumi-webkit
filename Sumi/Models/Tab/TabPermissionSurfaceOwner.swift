import Foundation
import WebKit

@MainActor
final class TabPermissionSurfaceOwner {
    struct Context {
        let tabId: UUID
        let currentURL: @MainActor () -> URL
        let resolveProfile: @MainActor () -> Profile?
        let isActiveTab: @MainActor () -> Bool
        let isVisibleTab: @MainActor () -> Bool
        let pageIdentity: @MainActor () -> TabExtensionPageIdentity
        let committedMainDocumentURL: @MainActor () -> URL?
        let isCurrentPage: @MainActor (_ pageId: String, _ pageGeneration: String) -> Bool
        let invalidateCurrentPageForWebViewReplacement: @MainActor () -> Void
        let handlePermissionLifecycleEvent: @MainActor (SumiPermissionLifecycleEvent) -> Void
        let isActiveGlancePreviewSurface: @MainActor (WKWebView) -> Bool
    }

    private let context: Context

    init(context: Context) {
        self.context = context
    }

    func currentPageId() -> String {
        pageIdentity().pageId
    }

    func surfaceState(for webView: WKWebView?) -> (isActive: Bool, isVisible: Bool) {
        if let webView,
           isActiveGlancePreviewSurface(for: webView) {
            return (true, true)
        }
        return (context.isActiveTab(), context.isVisibleTab())
    }

    func isActiveSurface(for webView: WKWebView?) -> Bool {
        surfaceState(for: webView).isActive
    }

    func isVisibleSurface(for webView: WKWebView?) -> Bool {
        surfaceState(for: webView).isVisible
    }

    func popupContext(for webView: WKWebView) -> SumiPopupPermissionTabContext? {
        guard let profile = context.resolveProfile() else { return nil }

        let identity = pageIdentity()
        let committedURL = committedExtensionRuntimeMainDocumentURL()
        let currentURL = context.currentURL()
        return SumiPopupPermissionTabContext(
            tabId: identity.tabId,
            pageId: identity.pageId,
            profilePartitionId: profile.id.uuidString.lowercased(),
            isEphemeralProfile: profile.isEphemeral,
            committedURL: committedURL,
            visibleURL: webView.url ?? currentURL,
            mainFrameURL: committedURL ?? webView.url ?? currentURL,
            isActiveTab: context.isActiveTab(),
            isVisibleTab: context.isVisibleTab(),
            navigationOrPageGeneration: identity.pageGeneration
        )
    }

    func externalSchemeContext(for webView: WKWebView) -> SumiExternalSchemePermissionTabContext? {
        guard let profile = context.resolveProfile() else { return nil }

        let identity = pageIdentity()
        let committedURL = committedExtensionRuntimeMainDocumentURL()
        let currentURL = context.currentURL()
        return SumiExternalSchemePermissionTabContext(
            tabId: identity.tabId,
            pageId: identity.pageId,
            profilePartitionId: profile.id.uuidString.lowercased(),
            isEphemeralProfile: profile.isEphemeral,
            committedURL: committedURL,
            visibleURL: webView.url ?? currentURL,
            mainFrameURL: committedURL ?? webView.url ?? currentURL,
            isActiveTab: context.isActiveTab(),
            isVisibleTab: context.isVisibleTab(),
            navigationOrPageGeneration: identity.pageGeneration,
            isCurrentPage: isCurrentPageClosure(
                pageId: identity.pageId,
                pageGeneration: identity.pageGeneration
            )
        )
    }

    func geolocationContext(for webView: WKWebView) -> SumiWebKitGeolocationTabContext? {
        guard let profile = context.resolveProfile() else { return nil }

        let identity = pageIdentity()
        let committedURL = committedExtensionRuntimeMainDocumentURL()
        let surfaceState = surfaceState(for: webView)
        let currentURL = context.currentURL()
        return SumiWebKitGeolocationTabContext(
            tabId: identity.tabId,
            pageId: identity.pageId,
            profilePartitionId: profile.id.uuidString.lowercased(),
            isEphemeralProfile: profile.isEphemeral,
            committedURL: committedURL,
            visibleURL: webView.url ?? currentURL,
            mainFrameURL: committedURL ?? webView.url ?? currentURL,
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
        guard let profile = context.resolveProfile() else { return nil }

        let identity = pageIdentity()
        let committedURL = committedExtensionRuntimeMainDocumentURL()
        let surfaceState = surfaceState(for: webView)
        let currentURL = context.currentURL()
        return SumiWebKitMediaCaptureTabContext(
            tabId: identity.tabId,
            pageId: identity.pageId,
            profilePartitionId: profile.id.uuidString.lowercased(),
            isEphemeralProfile: profile.isEphemeral,
            committedURL: committedURL,
            visibleURL: webView.url ?? currentURL,
            mainFrameURL: committedURL ?? fallbackMainFrameURL ?? webView.url ?? currentURL,
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
        guard let profile = context.resolveProfile() else { return nil }

        let identity = pageIdentity()
        let committedURL = committedExtensionRuntimeMainDocumentURL()
        let surfaceState = surfaceState(for: webView)
        let currentURL = context.currentURL()
        return SumiFilePickerPermissionTabContext(
            tabId: identity.tabId,
            pageId: identity.pageId,
            profilePartitionId: profile.id.uuidString.lowercased(),
            isEphemeralProfile: profile.isEphemeral,
            committedURL: committedURL,
            visibleURL: webView.url ?? currentURL,
            mainFrameURL: committedURL ?? webView.url ?? currentURL,
            isActiveTab: surfaceState.isActive,
            isVisibleTab: surfaceState.isVisible,
            navigationOrPageGeneration: identity.pageGeneration
        )
    }

    func storageAccessContext(for webView: WKWebView) -> SumiStorageAccessTabContext? {
        guard let profile = context.resolveProfile() else { return nil }

        let identity = pageIdentity()
        let committedURL = committedExtensionRuntimeMainDocumentURL()
        let surfaceState = surfaceState(for: webView)
        let currentURL = context.currentURL()
        return SumiStorageAccessTabContext(
            tabId: identity.tabId,
            pageId: identity.pageId,
            profilePartitionId: profile.id.uuidString.lowercased(),
            isEphemeralProfile: profile.isEphemeral,
            committedURL: committedURL,
            visibleURL: webView.url ?? currentURL,
            mainFrameURL: committedURL ?? webView.url ?? currentURL,
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
        let tabId = context.tabId.uuidString.lowercased()
        context.handlePermissionLifecycleEvent(
            .mainFrameNavigation(
                pageId: pageId,
                tabId: tabId,
                profilePartitionId: context.resolveProfile()?.id.uuidString,
                targetURL: targetURL,
                reason: "normal-tab-main-frame-navigation"
            )
        )
    }

    func cleanupNormalTabPermissionRuntime(reason: String) {
        let pageId = currentPageId()
        let tabId = context.tabId.uuidString.lowercased()
        context.handlePermissionLifecycleEvent(
            .tabClosed(
                pageId: pageId,
                tabId: tabId,
                profilePartitionId: context.resolveProfile()?.id.uuidString,
                reason: reason
            )
        )
    }

    func invalidateCurrentPageForWebViewReplacement(reason: String) {
        let pageId = currentPageId()
        let tabId = context.tabId.uuidString.lowercased()
        context.handlePermissionLifecycleEvent(
            .webViewReplaced(
                pageId: pageId,
                tabId: tabId,
                profilePartitionId: context.resolveProfile()?.id.uuidString,
                reason: reason
            )
        )
        context.invalidateCurrentPageForWebViewReplacement()
    }

    private func isActiveGlancePreviewSurface(for webView: WKWebView) -> Bool {
        context.isActiveGlancePreviewSurface(webView)
    }

    private func pageIdentity() -> (tabId: String, pageGeneration: String, pageId: String) {
        let identity = context.pageIdentity()
        return (identity.tabId, identity.pageGeneration, identity.pageId)
    }

    private func committedExtensionRuntimeMainDocumentURL() -> URL? {
        context.committedMainDocumentURL()
    }

    private func isCurrentPageClosure(
        pageId: String,
        pageGeneration: String
    ) -> @MainActor @Sendable () -> Bool {
        let isCurrentPage = context.isCurrentPage
        return {
            isCurrentPage(pageId, pageGeneration)
        }
    }
}

extension TabPermissionSurfaceOwner.Context {
    @MainActor
    static func live(tab: Tab) -> Self {
        let tabId = tab.id
        return Self(
            tabId: tabId,
            currentURL: { [weak tab] in
                tab?.url ?? SumiSurface.emptyTabURL
            },
            resolveProfile: { [weak tab] in
                tab?.resolveProfile()
            },
            isActiveTab: { [weak tab] in
                tab?.isCurrentTab ?? false
            },
            isVisibleTab: { [weak tab] in
                tab?.primaryWindowId != nil
            },
            pageIdentity: { [weak tab] in
                tab?.extensionPageRuntimeOwner.pageIdentity(tabId: tabId)
                    ?? fallbackPageIdentity(tabId: tabId)
            },
            committedMainDocumentURL: { [weak tab] in
                tab?.extensionPageRuntimeOwner.committedMainDocumentURLForCurrentPage()
            },
            isCurrentPage: { [weak tab] pageId, pageGeneration in
                guard let tab else { return false }
                return tab.extensionPageRuntimeOwner.isCurrentPage(
                    tabId: tabId,
                    pageId: pageId,
                    pageGeneration: pageGeneration
                )
            },
            invalidateCurrentPageForWebViewReplacement: { [weak tab] in
                tab?.extensionPageRuntimeOwner.invalidateCurrentPageForWebViewReplacement()
            },
            handlePermissionLifecycleEvent: { [weak tab] event in
                tab?.permissionRuntime.handlePermissionLifecycleEvent(event)
            },
            isActiveGlancePreviewSurface: { [weak tab] webView in
                tab?.permissionRuntime.isActiveGlancePreviewSurface(tabId, webView) ?? false
            }
        )
    }

    private static func fallbackPageIdentity(tabId: UUID) -> TabExtensionPageIdentity {
        let tabIdString = tabId.uuidString.lowercased()
        return TabExtensionPageIdentity(
            tabId: tabIdString,
            pageGeneration: "0",
            pageId: "\(tabIdString):0"
        )
    }
}
