import Foundation
import SumiDomain
import SumiWebRuntime
import WebKit

@MainActor
final class TabPermissionSurfaceOwner {
    private struct ExactPermissionDocument {
        let lease: TabMainFrameDocumentLease
        let committedURL: URL
    }

    struct Context {
        let tabId: UUID
        let currentURL: @MainActor () -> URL
        let resolveProfile: @MainActor () -> Profile?
        let profile: @MainActor (WKWebView) -> Profile?
        let surfaceState: @MainActor (WKWebView) -> TabPermissionSurfaceState
        let pageIdentity: @MainActor () -> TabExtensionPageIdentity
        let documentLease: @MainActor (WKWebView) -> TabMainFrameDocumentLease?
        let isCurrentPage: @MainActor (_ pageId: String, _ pageGeneration: String) -> Bool
        let invalidatePageForWebViewReplacement: @MainActor () -> Void
        let handlePermissionLifecycleEvent: @MainActor (SumiPermissionLifecycleEvent) -> Void
        let isActiveGlancePreviewSurface: @MainActor (WKWebView) -> Bool
        let isAuxiliaryMiniWindow: @MainActor () -> Bool
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
        guard let webView else { return (false, false) }
        let state = context.surfaceState(webView)
        return (state.isActive, state.isVisible)
    }

    func permissionSurface(for webView: WKWebView?) -> SumiPermissionSecurityContext.Surface {
        if let webView,
           isActiveGlancePreviewSurface(for: webView) {
            // Glance is fail-closed for permission prompt UI (`canPresentPromptUI` is false).
            return .glance
        }
        if context.isAuxiliaryMiniWindow() {
            // MiniWindow is fail-closed for permission prompt UI (`canPresentPromptUI` is false).
            return .miniWindow
        }
        return .normalTab
    }

    func isActiveSurface(for webView: WKWebView?) -> Bool {
        surfaceState(for: webView).isActive
    }

    func isVisibleSurface(for webView: WKWebView?) -> Bool {
        surfaceState(for: webView).isVisible
    }

    func popupContext(for webView: WKWebView) -> SumiPopupPermissionTabContext? {
        guard let profile = context.profile(webView),
              let document = exactPermissionDocument(for: webView) else {
            return nil
        }

        let identity = pageIdentity()
        let committedURL = document.committedURL
        let currentURL = context.currentURL()
        let surfaceState = surfaceState(for: webView)
        return SumiPopupPermissionTabContext(
            tabId: identity.tabId,
            pageId: identity.pageId,
            surface: permissionSurface(for: webView),
            profilePartitionId: profile.id.uuidString.lowercased(),
            isEphemeralProfile: profile.isEphemeral,
            committedURL: committedURL,
            visibleURL: webView.url ?? currentURL,
            mainFrameURL: committedURL,
            isActiveTab: surfaceState.isActive,
            isVisibleTab: surfaceState.isVisible,
            navigationOrPageGeneration: identity.pageGeneration,
            isCurrentPage: isCurrentPageClosure(
                pageId: identity.pageId,
                pageGeneration: identity.pageGeneration,
                webView: webView,
                documentLease: document.lease
            )
        )
    }

    func externalSchemeContext(for webView: WKWebView) -> SumiExternalSchemePermissionTabContext? {
        guard let profile = context.profile(webView),
              let document = exactPermissionDocument(for: webView) else {
            return nil
        }

        let identity = pageIdentity()
        let committedURL = document.committedURL
        let currentURL = context.currentURL()
        let surfaceState = surfaceState(for: webView)
        return SumiExternalSchemePermissionTabContext(
            tabId: identity.tabId,
            pageId: identity.pageId,
            surface: permissionSurface(for: webView),
            profilePartitionId: profile.id.uuidString.lowercased(),
            isEphemeralProfile: profile.isEphemeral,
            committedURL: committedURL,
            visibleURL: webView.url ?? currentURL,
            mainFrameURL: committedURL,
            isActiveTab: surfaceState.isActive,
            isVisibleTab: surfaceState.isVisible,
            navigationOrPageGeneration: identity.pageGeneration,
            isCurrentPage: isCurrentPageClosure(
                pageId: identity.pageId,
                pageGeneration: identity.pageGeneration,
                webView: webView,
                documentLease: document.lease
            )
        )
    }

    func geolocationContext(for webView: WKWebView) -> SumiWebKitGeolocationTabContext? {
        guard let profile = context.profile(webView),
              let document = exactPermissionDocument(for: webView) else {
            return nil
        }

        let identity = pageIdentity()
        let committedURL = document.committedURL
        let surfaceState = surfaceState(for: webView)
        let currentURL = context.currentURL()
        return SumiWebKitGeolocationTabContext(
            tabId: identity.tabId,
            pageId: identity.pageId,
            surface: permissionSurface(for: webView),
            profilePartitionId: profile.id.uuidString.lowercased(),
            isEphemeralProfile: profile.isEphemeral,
            committedURL: committedURL,
            visibleURL: webView.url ?? currentURL,
            mainFrameURL: committedURL,
            isActiveTab: surfaceState.isActive,
            isVisibleTab: surfaceState.isVisible,
            navigationOrPageGeneration: identity.pageGeneration,
            isCurrentPage: isCurrentPageClosure(
                pageId: identity.pageId,
                pageGeneration: identity.pageGeneration,
                webView: webView,
                documentLease: document.lease
            )
        )
    }

    func mediaCaptureContext(for webView: WKWebView) -> SumiWebKitMediaCaptureTabContext? {
        guard let profile = context.profile(webView),
              let document = exactPermissionDocument(for: webView) else {
            return nil
        }

        let identity = pageIdentity()
        let committedURL = document.committedURL
        let surfaceState = surfaceState(for: webView)
        let currentURL = context.currentURL()
        return SumiWebKitMediaCaptureTabContext(
            tabId: identity.tabId,
            pageId: identity.pageId,
            surface: permissionSurface(for: webView),
            profilePartitionId: profile.id.uuidString.lowercased(),
            isEphemeralProfile: profile.isEphemeral,
            committedURL: committedURL,
            visibleURL: webView.url ?? currentURL,
            mainFrameURL: committedURL,
            isActiveTab: surfaceState.isActive,
            isVisibleTab: surfaceState.isVisible,
            navigationOrPageGeneration: identity.pageGeneration,
            isCurrentPage: isCurrentPageClosure(
                pageId: identity.pageId,
                pageGeneration: identity.pageGeneration,
                webView: webView,
                documentLease: document.lease
            )
        )
    }

    func filePickerContext(for webView: WKWebView) -> SumiFilePickerPermissionTabContext? {
        guard let profile = context.profile(webView),
              let document = exactPermissionDocument(for: webView) else {
            return nil
        }

        let identity = pageIdentity()
        let committedURL = document.committedURL
        let surfaceState = surfaceState(for: webView)
        let currentURL = context.currentURL()
        return SumiFilePickerPermissionTabContext(
            tabId: identity.tabId,
            pageId: identity.pageId,
            surface: permissionSurface(for: webView),
            profilePartitionId: profile.id.uuidString.lowercased(),
            isEphemeralProfile: profile.isEphemeral,
            committedURL: committedURL,
            visibleURL: webView.url ?? currentURL,
            mainFrameURL: committedURL,
            isActiveTab: surfaceState.isActive,
            isVisibleTab: surfaceState.isVisible,
            navigationOrPageGeneration: identity.pageGeneration,
            isCurrentPage: isCurrentPageClosure(
                pageId: identity.pageId,
                pageGeneration: identity.pageGeneration,
                webView: webView,
                documentLease: document.lease
            )
        )
    }

    func storageAccessContext(for webView: WKWebView) -> SumiStorageAccessTabContext? {
        guard let profile = context.profile(webView),
              let document = exactPermissionDocument(for: webView) else {
            return nil
        }

        let identity = pageIdentity()
        let committedURL = document.committedURL
        let surfaceState = surfaceState(for: webView)
        let currentURL = context.currentURL()
        return SumiStorageAccessTabContext(
            tabId: identity.tabId,
            pageId: identity.pageId,
            surface: permissionSurface(for: webView),
            profilePartitionId: profile.id.uuidString.lowercased(),
            isEphemeralProfile: profile.isEphemeral,
            committedURL: committedURL,
            visibleURL: webView.url ?? currentURL,
            mainFrameURL: committedURL,
            isActiveTab: surfaceState.isActive,
            isVisibleTab: surfaceState.isVisible,
            navigationOrPageGeneration: identity.pageGeneration,
            isCurrentPage: isCurrentPageClosure(
                pageId: identity.pageId,
                pageGeneration: identity.pageGeneration,
                webView: webView,
                documentLease: document.lease
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

    func invalidatePageForWebViewReplacement(reason: String) {
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
        context.invalidatePageForWebViewReplacement()
    }

    private func isActiveGlancePreviewSurface(for webView: WKWebView) -> Bool {
        context.isActiveGlancePreviewSurface(webView)
    }

    private func pageIdentity() -> TabExtensionPageIdentity {
        context.pageIdentity()
    }

    private func exactPermissionDocument(
        for webView: WKWebView
    ) -> ExactPermissionDocument? {
        guard let callbackCommittedURL = webView.committedURL,
              let lease = context.documentLease(webView),
              lease.webViewID == ObjectIdentifier(webView),
              Self.matchesPhysicalDocument(
                  callbackCommittedURL,
                  presentationURL: lease.presentationURL
              )
        else {
            return nil
        }
        return ExactPermissionDocument(
            lease: lease,
            committedURL: lease.committedURL
        )
    }

    private func isCurrentPageClosure(
        pageId: String,
        pageGeneration: String,
        webView: WKWebView,
        documentLease: TabMainFrameDocumentLease
    ) -> @MainActor @Sendable () -> Bool {
        let isCurrentPage = context.isCurrentPage
        let currentDocumentLease = context.documentLease
        return { [weak webView] in
            guard let webView,
                  currentDocumentLease(webView) == documentLease,
                  let committedURL = webView.committedURL,
                  Self.matchesPhysicalDocument(
                      committedURL,
                      presentationURL: documentLease.presentationURL
                  ) else {
                return false
            }
            return isCurrentPage(pageId, pageGeneration)
        }
    }

    private static func matchesPhysicalDocument(
        _ callbackURL: URL,
        presentationURL: URL
    ) -> Bool {
        WebRuntimeNavigationIdentity.matches(callbackURL, presentationURL)
            || callbackURL.isSameDocument(presentationURL)
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
            profile: { [weak tab] webView in
                guard let tab else { return nil }
                return tab.navigationRuntime.permissionRuntime.profile(
                    tabId,
                    webView
                )
            },
            surfaceState: { [weak tab] webView in
                guard let tab else { return .inactive }
                return tab.navigationRuntime.permissionRuntime.surfaceState(
                    tabId,
                    webView
                )
            },
            pageIdentity: { [weak tab] in
                tab?.extensionPageRuntimeOwner.pageIdentity(tabId: tabId)
                    ?? fallbackPageIdentity(tabId: tabId)
            },
            documentLease: { [weak tab] webView in
                tab?.committedDocumentRuntime.lease(for: webView)
            },
            isCurrentPage: { [weak tab] pageId, pageGeneration in
                guard let tab else { return false }
                return tab.extensionPageRuntimeOwner.isCurrentPage(
                    tabId: tabId,
                    pageId: pageId,
                    pageGeneration: pageGeneration
                )
            },
            invalidatePageForWebViewReplacement: { [weak tab] in
                tab?.extensionPageRuntimeOwner.invalidatePageForWebViewReplacement()
            },
            handlePermissionLifecycleEvent: { [weak tab] event in
                tab?.navigationRuntime.permissionRuntime.handlePermissionLifecycleEvent(event)
            },
            isActiveGlancePreviewSurface: { [weak tab] webView in
                tab?.navigationRuntime.permissionRuntime.isActiveGlancePreviewSurface(tabId, webView) ?? false
            },
            isAuxiliaryMiniWindow: { [weak tab] in
                tab?.isAuxiliaryMiniWindow ?? false
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
