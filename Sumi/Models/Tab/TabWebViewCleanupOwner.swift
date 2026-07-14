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
    @discardableResult
    static func cleanupWebView(
        _ webView: WKWebView,
        context: Context
    ) -> Bool {
        if context.deferProtectedWebViewCleanup(
            webView,
            context.tabId,
            "Tab.cleanupCloneWebView"
        ) {
            return false
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
        return true
    }

    @MainActor
    @discardableResult
    static func performComprehensiveCleanup(context: Context) -> Bool {
        let teardown = context.removeAllWebViews(true, .retirement)
        let remainingWebViews = uniqueWebViews(context.remainingOwnedWebViews())
        guard teardown.foundWebViews || remainingWebViews.isEmpty == false else {
            return teardown.isComplete
        }

        RuntimeDiagnostics.debug(
            "Performing comprehensive WebView cleanup for '\(context.tabName())'.",
            category: "Tab"
        )

        let detachedCleanupCompleted = teardown.isComplete
            && remainingWebViews.map {
                cleanupWebView($0, context: context)
            }.allSatisfy { $0 }
        if detachedCleanupCompleted {
            context.clearDetachedWebViews()
        }

        RuntimeDiagnostics.debug(
            detachedCleanupCompleted
                ? "Completed WebView cleanup for '\(context.tabName())'."
                : "Deferred protected WebView cleanup for '\(context.tabName())'.",
            category: "Tab"
        )
        return teardown.isComplete && detachedCleanupCompleted
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

        let detachedCleanupCompleted = teardown.isComplete
            && remainingWebViews.map {
                cleanupWebView($0, context: context)
            }.allSatisfy { $0 }
        if detachedCleanupCompleted {
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
