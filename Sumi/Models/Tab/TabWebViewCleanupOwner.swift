import Foundation
import WebKit

enum SumiWebViewShutdown {
    private enum Scope {
        case normal(tabId: UUID)
        case auxiliary
    }

    struct NormalTabRuntime {
        let cleanupUserScripts: (WKUserContentController, UUID) -> Void
        let removeWebViewFromContainers: (WKWebView) -> Void
    }

    @MainActor
    static func perform(
        on webView: WKWebView,
        tabId: UUID,
        runtime: NormalTabRuntime,
        additionalTabCleanup: (() -> Void)? = nil
    ) {
        performLifecycle(
            on: webView,
            scope: .normal(tabId: tabId),
            normalTabRuntime: runtime,
            additionalTabCleanup: additionalTabCleanup
        )
    }

    @MainActor
    fileprivate static func performAuxiliary(
        on webView: WKWebView
    ) {
        performLifecycle(
            on: webView,
            scope: .auxiliary,
            normalTabRuntime: nil
        )
    }

    @MainActor
    private static func performLifecycle(
        on webView: WKWebView,
        scope: Scope,
        normalTabRuntime: NormalTabRuntime?,
        additionalTabCleanup: (() -> Void)? = nil
    ) {
        webView.stopLoading()
        stopNativeMedia(on: webView)

        if case .normal(let tabId) = scope {
            normalTabRuntime?.cleanupUserScripts(
                webView.configuration.userContentController,
                tabId
            )
        }

        if let controller = webView.configuration.userContentController.sumiNormalTabUserContentController {
            controller.cleanUpBeforeClosing()
        }

        prepareForReleaseIfNeeded(webView, scope: scope)
        additionalTabCleanup?()

        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()

        if case .normal = scope {
            normalTabRuntime?.removeWebViewFromContainers(webView)
        }
    }

    @MainActor
    private static func stopNativeMedia(on webView: WKWebView) {
        webView.pauseAllMediaPlayback(completionHandler: nil)

        if webView.cameraCaptureState != .none {
            webView.setCameraCaptureState(.none, completionHandler: nil)
        }
        if webView.microphoneCaptureState != .none {
            webView.setMicrophoneCaptureState(.none, completionHandler: nil)
        }
    }

    @MainActor
    private static func prepareForReleaseIfNeeded(_ webView: WKWebView, scope: Scope) {
        guard case .normal = scope else { return }
        guard webView.url?.absoluteString != SumiSurface.emptyTabURL.absoluteString else { return }
        _ = webView.load(URLRequest(url: SumiSurface.emptyTabURL))
    }
}

enum SumiAuxiliaryWebViewShutdown {
    @MainActor
    static func perform(on webView: WKWebView) {
        SumiWebViewShutdown.performAuxiliary(
            on: webView
        )
    }
}

enum TabWebViewCleanupOwner {
    typealias PermissionLifecycleEventHandler = (SumiPermissionLifecycleEvent) -> Void
    typealias ProtectedWebViewCleanupDeferrer = (WKWebView, UUID, String) -> Bool

    struct Context {
        let tabId: UUID
        let tabName: () -> String
        let handlePermissionLifecycleEvent: PermissionLifecycleEventHandler
        let deferProtectedWebViewCleanup: ProtectedWebViewCleanupDeferrer
        let shutdownRuntime: SumiWebViewShutdown.NormalTabRuntime
        let notifyNowPlayingTabUnloaded: (UUID) -> Void
        let currentWebView: () -> WKWebView?
        let clearCurrentWebView: () -> Void
        let removeAllWebViews: (_ closeActiveFullscreenMedia: Bool) -> Bool
        let currentPermissionPageId: () -> String
        let profilePartitionId: () -> String?
        let invalidateCurrentPermissionPageForWebViewReplacement: (String) -> Void
        let unbindAudioState: (WKWebView) -> Void
        let removeNavigationStateObservers: (WKWebView) -> Void
        let removeNavigationDelegateBundle: (WKWebView) -> Void
        let resetPlaybackActivity: () -> Void
        let setLoadingIdle: () -> Void
    }

    @MainActor
    static func cleanupWebView(_ webView: WKWebView, context: Context) {
        let pageId = context.currentPermissionPageId()
        let tabId = context.tabId.uuidString.lowercased()
        context.handlePermissionLifecycleEvent(
            .webViewDeallocated(
                pageId: pageId,
                tabId: tabId,
                profilePartitionId: context.profilePartitionId(),
                reason: "normal-tab-webview-cleanup"
            )
        )

        if context.deferProtectedWebViewCleanup(
            webView,
            context.tabId,
            "Tab.cleanupCloneWebView"
        ) {
            return
        }

        SumiWebViewShutdown.perform(
            on: webView,
            tabId: context.tabId,
            runtime: context.shutdownRuntime
        ) {
            context.unbindAudioState(webView)
            context.removeNavigationStateObservers(webView)
            context.removeNavigationDelegateBundle(webView)
        }
    }

    @MainActor
    static func performComprehensiveCleanup(context: Context) {
        let removedTrackedWebViews = context.removeAllWebViews(true)
        guard removedTrackedWebViews || context.currentWebView() != nil else { return }

        RuntimeDiagnostics.debug(
            "Performing comprehensive WebView cleanup for '\(context.tabName())'.",
            category: "Tab"
        )

        if let webView = context.currentWebView() {
            cleanupWebView(webView, context: context)
        }

        context.clearCurrentWebView()

        RuntimeDiagnostics.debug(
            "Completed WebView cleanup for '\(context.tabName())'.",
            category: "Tab"
        )
    }

    @MainActor
    static func unloadWebView(context: Context) {
        context.invalidateCurrentPermissionPageForWebViewReplacement("normal-tab-webview-unload")

        let removedTrackedWebViews = context.removeAllWebViews(true)

        guard removedTrackedWebViews || context.currentWebView() != nil else {
            context.notifyNowPlayingTabUnloaded(context.tabId)
            return
        }

        if let webView = context.currentWebView() {
            cleanupWebView(webView, context: context)
        }
        context.clearCurrentWebView()

        context.resetPlaybackActivity()
        context.setLoadingIdle()
        context.notifyNowPlayingTabUnloaded(context.tabId)
    }
}
