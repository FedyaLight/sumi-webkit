import Foundation
import SumiDomain
import SumiWebRuntime
import WebKit

enum SumiWebViewShutdown {
    private enum Scope {
        case normal
        case auxiliary
    }

    struct NormalTabRuntime {
        let removeWebViewFromContainers: (WKWebView) -> Void
    }

    @MainActor
    static func perform(
        on webView: WKWebView,
        runtime: NormalTabRuntime,
        additionalTabCleanup: (() -> Void)? = nil
    ) {
        performLifecycle(
            on: webView,
            scope: .normal,
            normalTabRuntime: runtime,
            additionalTabCleanup: additionalTabCleanup
        )
    }

    /// Terminal browser-session shutdown cannot initiate another navigation:
    /// its delegates and model runtime are already unavailable by definition.
    @MainActor
    static func performTerminalShutdown(
        on webView: WKWebView,
        runtime: NormalTabRuntime
    ) {
        performLifecycle(
            on: webView,
            scope: .normal,
            normalTabRuntime: runtime,
            prepareForRelease: false
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
        additionalTabCleanup: (() -> Void)? = nil,
        prepareForRelease: Bool = true
    ) {
        webView.stopLoading()
        stopNativeMedia(on: webView)

        if let controller = webView.configuration.userContentController.sumiNormalTabUserContentController {
            controller.cleanUpBeforeClosing()
        }

        if prepareForRelease {
            prepareForReleaseIfNeeded(webView, scope: scope)
        }
        additionalTabCleanup?()

        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()

        if case .normal = scope {
            normalTabRuntime?.removeWebViewFromContainers(webView)
            if let focusableWebView = webView as? FocusableWKWebView {
                focusableWebView.resetPageInteractionState()
                focusableWebView.owningTab = nil
            }
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
        let remainingOwnedWebViews: () -> [WKWebView]
        let clearDetachedWebViews: () -> Void
        let removeAllWebViews: (
            _ closeActiveFullscreenMedia: Bool,
            _ intent: TabWebViewTeardownIntent
        ) -> WebViewTabTeardownResult
        let currentPermissionPageId: () -> String
        let profilePartitionId: () -> String?
        let invalidatePermissionPageForReplacement: (String) -> Void
        let unbindAudioState: (WKWebView) -> Void
        let removeNavigationStateObservers: (WKWebView) -> Void
        let removeNavigationDelegateBundle: (WKWebView) -> Void
        let webViewDidLeaveRuntime: (WKWebView) -> Void
        let resetPlaybackActivity: () -> Void
        let setLoadingIdle: () -> Void
    }

    @MainActor
    static func cleanupWebView(_ webView: WKWebView, context: Context) {
        if context.deferProtectedWebViewCleanup(
            webView,
            context.tabId,
            "Tab.cleanupCloneWebView"
        ) {
            return
        }

        let hasSurvivingOwnedWebView = context.remainingOwnedWebViews().contains {
            $0 !== webView
        }
        if hasSurvivingOwnedWebView == false {
            let pageId = context.currentPermissionPageId()
            let tabId = context.tabId.uuidString.lowercased()
            context.handlePermissionLifecycleEvent(
                .webViewDeallocated(
                    pageId: pageId,
                    tabId: tabId,
                    profilePartitionId: context.profilePartitionId(),
                    reason: "normal-tab-last-webview-cleanup"
                )
            )
        }
        context.webViewDidLeaveRuntime(webView)

        SumiWebViewShutdown.perform(
            on: webView,
            runtime: context.shutdownRuntime
        ) {
            context.unbindAudioState(webView)
            context.removeNavigationStateObservers(webView)
            context.removeNavigationDelegateBundle(webView)
        }
    }

    @MainActor
    static func performComprehensiveCleanup(context: Context) {
        let teardown = context.removeAllWebViews(true, .retirement)
        let remainingWebViews = uniqueWebViews(context.remainingOwnedWebViews())
        guard teardown.foundWebViews || remainingWebViews.isEmpty == false else { return }

        RuntimeDiagnostics.debug(
            "Performing comprehensive WebView cleanup for '\(context.tabName())'.",
            category: "Tab"
        )

        if teardown.isComplete {
            for webView in remainingWebViews {
                cleanupWebView(webView, context: context)
            }
            context.clearDetachedWebViews()
        }

        RuntimeDiagnostics.debug(
            teardown.isComplete
                ? "Completed WebView cleanup for '\(context.tabName())'."
                : "Deferred \(teardown.deferredWebViewCount) protected WebView cleanup(s) for '\(context.tabName())'.",
            category: "Tab"
        )
    }

    @MainActor
    static func unloadWebView(context: Context) {
        context.invalidatePermissionPageForReplacement("normal-tab-webview-unload")

        let teardown = context.removeAllWebViews(true, .suspension)
        let remainingWebViews = uniqueWebViews(context.remainingOwnedWebViews())

        guard teardown.foundWebViews || remainingWebViews.isEmpty == false else {
            context.notifyNowPlayingTabUnloaded(context.tabId)
            return
        }

        if teardown.isComplete {
            for webView in remainingWebViews {
                cleanupWebView(webView, context: context)
            }
            context.clearDetachedWebViews()
        }

        context.resetPlaybackActivity()
        context.setLoadingIdle()
        context.notifyNowPlayingTabUnloaded(context.tabId)
    }

    private static func uniqueWebViews(_ webViews: [WKWebView]) -> [WKWebView] {
        var seen: Set<ObjectIdentifier> = []
        return webViews.filter { seen.insert(ObjectIdentifier($0)).inserted }
    }
}
