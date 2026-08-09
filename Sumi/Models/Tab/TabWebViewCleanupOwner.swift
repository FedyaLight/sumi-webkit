import Foundation
import SumiDomain
import SumiWebRuntime
import WebKit

@MainActor
final class TabWebViewRetirementLedger {
    private let logicallyDeparted = NSHashTable<WKWebView>.weakObjects()
    private let physicallyDestroyed = NSHashTable<WKWebView>.weakObjects()

    func claimLogicalDeparture(_ webViews: [WKWebView]) -> [WKWebView] {
        var seen = Set<ObjectIdentifier>()
        return webViews.filter { webView in
            guard seen.insert(ObjectIdentifier(webView)).inserted,
                  logicallyDeparted.contains(webView) == false else {
                return false
            }
            logicallyDeparted.add(webView)
            return true
        }
    }

    func claimPhysicalDestruction(_ webView: WKWebView) -> Bool {
        guard physicallyDestroyed.contains(webView) == false else {
            return false
        }
        physicallyDestroyed.add(webView)
        return true
    }
}

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
        closeActiveMediaPresentations: Bool
    ) {
        guard closeActiveMediaPresentations else {
            performLifecycle(
                on: webView,
                scope: .normal,
                normalTabRuntime: runtime
            )
            return
        }
        webView.closeAllMediaPresentations {
            Task { @MainActor in
                performLifecycle(
                    on: webView,
                    scope: .normal,
                    normalTabRuntime: runtime
                )
            }
        }
    }

    @MainActor
    static func hasActiveMediaPresentation(on webView: WKWebView) -> Bool {
        if webView.sumiIsInFullscreenElementPresentation {
            return true
        }
        guard let focusableWebView = webView as? FocusableWKWebView,
              let tab = focusableWebView.owningTab else {
            return false
        }
        return tab.mediaRuntime.isPictureInPictureActive(for: webView)
    }

    /// Terminal browser-session shutdown cannot initiate another navigation:
    /// its delegates and model runtime are already unavailable by definition.
    @MainActor
    static func performTerminalShutdown(
        on webView: WKWebView,
        runtime: NormalTabRuntime
    ) {
        perform(
            on: webView,
            runtime: runtime,
            closeActiveMediaPresentations: hasActiveMediaPresentation(on: webView)
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
        normalTabRuntime: NormalTabRuntime?
    ) {
        webView.stopLoading()
        stopNativeMedia(on: webView)

        if let controller = webView.configuration.userContentController.sumiNormalTabUserContentController {
            controller.cleanUpBeforeClosing()
        }

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
            _ intent: TabWebViewTeardownIntent
        ) -> WebViewTabTeardownResult
        let currentPermissionPageId: () -> String
        let profilePartitionId: () -> String?
        let invalidatePermissionPageForReplacement: (String) -> Void
        let claimLogicalDeparture: ([WKWebView]) -> [WKWebView]
        let claimPhysicalDestruction: (WKWebView) -> Bool
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

        let departing = context.claimLogicalDeparture([webView])
        if departing.isEmpty == false {
            preparePermissionLifecycleForRetirement(
                departing,
                context: context
            )
            departing.forEach(context.webViewDidLeaveRuntime)
        }
        if context.claimPhysicalDestruction(webView) {
            destroyRetiredWebView(webView, context: context)
        }
        return true
    }

    @MainActor
    static func preparePermissionLifecycleForRetirement(
        _ webViews: [WKWebView],
        context: Context
    ) {
        let departingIDs = Set(webViews.map(ObjectIdentifier.init))
        let hasSurvivingOwnedWebView = context.remainingOwnedWebViews()
            .contains { departingIDs.contains(ObjectIdentifier($0)) == false }
        guard hasSurvivingOwnedWebView == false else { return }

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

    @MainActor
    static func destroyRetiredWebView(
        _ webView: WKWebView,
        context: Context
    ) {
        let hasActiveMediaPresentation = SumiWebViewShutdown
            .hasActiveMediaPresentation(on: webView)

        SumiWebViewShutdown.perform(
            on: webView,
            runtime: context.shutdownRuntime,
            closeActiveMediaPresentations: hasActiveMediaPresentation
        )
    }

    @MainActor
    @discardableResult
    static func performComprehensiveCleanup(context: Context) -> Bool {
        let teardown = context.removeAllWebViews(.retirement)
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

        let teardown = context.removeAllWebViews(.suspension)
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
