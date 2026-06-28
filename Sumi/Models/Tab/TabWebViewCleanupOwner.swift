import Foundation
import WebKit

enum SumiWebViewShutdown {
    enum Scope {
        case normal(tabId: UUID)
        case auxiliary(reason: String)
    }

    @MainActor
    static func perform(
        on webView: WKWebView,
        scope: Scope,
        browserManager: BrowserManager?,
        additionalTabCleanup: (() -> Void)? = nil
    ) {
        webView.stopLoading()
        stopNativeMedia(on: webView)

        if case .normal(let tabId) = scope {
            browserManager?.userscriptsModule.cleanupWebViewIfLoaded(
                controller: webView.configuration.userContentController,
                webViewId: tabId
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
            browserManager?.webViewCoordinator?.removeWebViewFromContainers(webView)
        }
    }

    @MainActor
    static func perform(
        on webView: WKWebView,
        tabId: UUID,
        browserManager: BrowserManager?,
        additionalTabCleanup: (() -> Void)? = nil
    ) {
        perform(
            on: webView,
            scope: .normal(tabId: tabId),
            browserManager: browserManager,
            additionalTabCleanup: additionalTabCleanup
        )
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
    static func perform(
        on webView: WKWebView,
        browserManager: BrowserManager?,
        reason: String
    ) {
        SumiWebViewShutdown.perform(
            on: webView,
            scope: .auxiliary(reason: reason),
            browserManager: browserManager
        )
    }
}

enum TabWebViewCleanupOwner {
    struct Context {
        let tabId: UUID
        let tabName: () -> String
        let browserManager: BrowserManager?
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
        context.browserManager?.permissionLifecycleController.handle(
            .webViewDeallocated(
                pageId: pageId,
                tabId: tabId,
                profilePartitionId: context.profilePartitionId(),
                reason: "normal-tab-webview-cleanup"
            )
        )

        if context.browserManager?.webViewCoordinator?.deferProtectedWebViewCleanup(
            webView,
            tabID: context.tabId,
            reason: "Tab.cleanupCloneWebView"
        ) == true {
            return
        }

        SumiWebViewShutdown.perform(
            on: webView,
            tabId: context.tabId,
            browserManager: context.browserManager
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
            notifyNowPlayingTabUnloaded(tabId: context.tabId)
            return
        }

        if let webView = context.currentWebView() {
            cleanupWebView(webView, context: context)
        }
        context.clearCurrentWebView()

        context.resetPlaybackActivity()
        context.setLoadingIdle()
        notifyNowPlayingTabUnloaded(tabId: context.tabId)
    }

    @MainActor
    private static func notifyNowPlayingTabUnloaded(tabId: UUID) {
        SumiNativeNowPlayingController.shared.handleTabUnloaded(tabId)
        SumiNativeNowPlayingController.shared.scheduleRefresh(delayNanoseconds: 0)
    }
}
