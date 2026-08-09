import Foundation
import SumiWebRuntime
import WebKit

@MainActor
protocol DeferredWebViewCommandTabResolving: AnyObject {
    func resolveRuntimeTab(with tabID: UUID) -> Tab?
    func resolveCollectionTab(with tabID: UUID) -> Tab?
    func resolveTabForCleanup(with tabID: UUID) -> Tab?
}

/// Resolves app Tabs through the canonical weak runtime registry. The fallback
/// is the single composition seam to the browser model, not a command surface.
@MainActor
final class DeferredWebViewCommandTabResolver: DeferredWebViewCommandTabResolving {
    private let runtimeTabs: WebViewRuntimeTabRegistry
    private let resolveRuntimeTab: WebViewRuntimeTabRegistry.RuntimeTabResolver
    private let resolveCollectionTab: @MainActor (UUID) -> Tab?

    init(
        runtimeTabs: WebViewRuntimeTabRegistry,
        resolveRuntimeTab: @escaping WebViewRuntimeTabRegistry.RuntimeTabResolver,
        resolveCollectionTab: @escaping @MainActor (UUID) -> Tab?
    ) {
        self.runtimeTabs = runtimeTabs
        self.resolveRuntimeTab = resolveRuntimeTab
        self.resolveCollectionTab = resolveCollectionTab
    }

    func resolveRuntimeTab(with tabID: UUID) -> Tab? {
        runtimeTabs.resolve(tabID, resolveRuntimeTab: resolveRuntimeTab)
    }

    func resolveCollectionTab(with tabID: UUID) -> Tab? {
        guard let tab = resolveCollectionTab(tabID) else { return nil }
        guard runtimeTabs.bind(tab).isAccepted else { return nil }
        return tab
    }

    func resolveTabForCleanup(with tabID: UUID) -> Tab? {
        runtimeTabs.tabForCleanup(
            tabID,
            resolveRuntimeTab: resolveRuntimeTab
        )
    }
}

@MainActor
protocol DeferredWebViewCommandWindowQuerying {
    func containsWindow(with windowID: UUID) -> Bool
}

@MainActor
protocol DeferredWebViewSpaceProfileIntentValidating {
    func isCurrent(_ intent: DeferredWebViewSpaceProfileAssignmentIntent) -> Bool
}

/// Converts an identity-only deferred command into exact, currently-authorized
/// runtime values. Preparation has no side effects and prepared values must be
/// executed immediately on the main actor rather than retained in the buffer.
@MainActor
final class DeferredWebViewCommandAuthority {
    enum PreparedCommand {
        case removeWebViewFromContainers(webView: WKWebView)
        case removeTrackedWebView(
            webView: WKWebView,
            owner: TrackedWebViewOwner,
            tab: Tab?
        )
        case closeWebViewFromWebKit(webView: WKWebView)
        case cleanupWindow(windowID: UUID)
        case cleanupAllWebViews
        case rebuildLiveWebViews(
            tab: Tab,
            preferredPrimaryWindowID: UUID?,
            intent: DeferredWebViewRebuildIntent
        )
        case assignProfile(
            tab: Tab,
            preferredPrimaryWindowID: UUID?,
            intent: DeferredWebViewProfileAssignmentIntent
        )
        case assignSpaceProfile(intent: DeferredWebViewSpaceProfileAssignmentIntent)
        case synchronizeTrackedNavigation(
            webView: WKWebView,
            tab: Tab,
            owner: TrackedWebViewOwner,
            intent: DeferredWebViewNavigationIntent
        )
        case reloadTrackedNavigation(
            webView: WKWebView,
            tab: Tab,
            owner: TrackedWebViewOwner,
            intent: DeferredWebViewReloadIntent
        )
        case evictHiddenWebViews(windowID: UUID)
        case cleanupTabWebView(webView: WKWebView, tabID: UUID, tab: Tab?)
        case retireTabWebViewGeneration(tab: Tab, expectedGeneration: UInt64)
        case performFallbackWebViewCleanup(
            webView: WKWebView,
            lease: WebViewPendingCleanupLease,
            tab: Tab?
        )
    }

    private let webViews: WebViewRuntimeWebViewResolver
    private let webViewSessions: WebViewSessionRepository
    private let tabs: any DeferredWebViewCommandTabResolving
    private let tabScopedCleanupValidation: WebViewTabScopedCleanupValidationOwner
    private let visibleRuntime: VisibleWebViewRuntimeOwner
    private let windows: any DeferredWebViewCommandWindowQuerying
    private let spaceProfileIntents: any DeferredWebViewSpaceProfileIntentValidating

    init(
        webViews: WebViewRuntimeWebViewResolver,
        webViewSessions: WebViewSessionRepository,
        tabs: any DeferredWebViewCommandTabResolving,
        tabScopedCleanupValidation: WebViewTabScopedCleanupValidationOwner,
        visibleRuntime: VisibleWebViewRuntimeOwner,
        windows: any DeferredWebViewCommandWindowQuerying,
        spaceProfileIntents: any DeferredWebViewSpaceProfileIntentValidating
    ) {
        self.webViews = webViews
        self.webViewSessions = webViewSessions
        self.tabs = tabs
        self.tabScopedCleanupValidation = tabScopedCleanupValidation
        self.visibleRuntime = visibleRuntime
        self.windows = windows
        self.spaceProfileIntents = spaceProfileIntents
    }

    func prepare(_ command: DeferredWebViewCommand) -> PreparedCommand? {
        switch command {
        case .removeWebViewFromContainers(let webViewID):
            guard let webView = webViews.resolve(webViewID) else { return nil }
            return .removeWebViewFromContainers(webView: webView)

        case .removeTrackedWebView(let webViewID, let tabID, let windowID):
            let owner = TrackedWebViewOwner(tabID: tabID, windowID: windowID)
            guard webViewSessions.trackedOwner(with: webViewID) == owner,
                  let webView = webViews.resolve(webViewID) else { return nil }
            return .removeTrackedWebView(
                webView: webView,
                owner: owner,
                tab: tabs.resolveTabForCleanup(with: tabID)
            )

        case .closeWebViewFromWebKit(let webViewID):
            guard let webView = webViews.resolve(webViewID) else { return nil }
            return .closeWebViewFromWebKit(webView: webView)

        case .cleanupWindow(let windowID):
            guard webViewSessions.trackedWebViews(in: windowID).isEmpty == false
                    || visibleRuntime.compositorContainerView(for: windowID) != nil else {
                return nil
            }
            return .cleanupWindow(windowID: windowID)

        case .cleanupAllWebViews:
            guard webViewSessions.isTrackingEmpty == false else { return nil }
            return .cleanupAllWebViews

        case .rebuildLiveWebViews(
            let tabID,
            let preferredPrimaryWindowID,
            let intent
        ):
            guard let tab = tabs.resolveRuntimeTab(with: tabID),
                  tab.webViewRebuildEpoch.isCurrent(intent.revision) else { return nil }
            return .rebuildLiveWebViews(
                tab: tab,
                preferredPrimaryWindowID: preferredPrimaryWindowID,
                intent: intent
            )

        case .assignProfile(let tabID, let preferredPrimaryWindowID, let intent):
            guard let tab = tabs.resolveCollectionTab(with: tabID),
                  tab.profileAssignment.isCurrent(intent),
                  tab.mainFrameLoads.isCurrent(
                      revision: intent.navigationRevision,
                      targetURL: intent.targetURL
                  ) else { return nil }
            return .assignProfile(
                tab: tab,
                preferredPrimaryWindowID: preferredPrimaryWindowID,
                intent: intent
            )

        case .assignSpaceProfile(let intent):
            guard spaceProfileIntents.isCurrent(intent) else { return nil }
            return .assignSpaceProfile(intent: intent)

        case .synchronizeTrackedNavigation(
            let webViewID,
            let tabID,
            let windowID,
            let intent
        ):
            let owner = TrackedWebViewOwner(tabID: tabID, windowID: windowID)
            guard let webView = webViews.resolve(webViewID),
                  webViewSessions.trackedOwner(with: webViewID) == owner,
                  let tab = tabs.resolveRuntimeTab(with: tabID),
                  tab.mainFrameLoads.isCurrent(
                    revision: intent.revision,
                    targetURL: intent.targetURL
                  ) else { return nil }
            return .synchronizeTrackedNavigation(
                webView: webView,
                tab: tab,
                owner: owner,
                intent: intent
            )

        case .reloadTrackedNavigation(
            let webViewID,
            let tabID,
            let windowID,
            let intent
        ):
            let owner = TrackedWebViewOwner(tabID: tabID, windowID: windowID)
            guard let webView = webViews.resolve(webViewID),
                  webViewSessions.trackedOwner(with: webViewID) == owner,
                  let tab = tabs.resolveRuntimeTab(with: tabID),
                  tab.mainFrameLoads.isCurrent(
                    revision: intent.revision,
                    targetURL: intent.targetURL
                  ) else { return nil }
            return .reloadTrackedNavigation(
                webView: webView,
                tab: tab,
                owner: owner,
                intent: intent
            )

        case .evictHiddenWebViews(let windowID):
            guard windows.containsWindow(with: windowID) else { return nil }
            return .evictHiddenWebViews(windowID: windowID)

        case .cleanupTabWebView(let webViewID, let tabID):
            guard tabScopedCleanupValidation.canCleanUpDetachedWebView(
                with: webViewID,
                tabID: tabID,
                context: tabScopedCleanupValidationContext()
            ), let webView = webViews.resolve(webViewID) else { return nil }
            return .cleanupTabWebView(
                webView: webView,
                tabID: tabID,
                tab: tabs.resolveTabForCleanup(with: tabID)
            )

        case .retireTabWebViewGeneration(let tabID, let expectedGeneration):
            guard let tab = tabs.resolveTabForCleanup(with: tabID),
                  tab.webViewSession.generation == expectedGeneration,
                  tab.webViewSession.allKnownWebViews.isEmpty == false else {
                return nil
            }
            return .retireTabWebViewGeneration(
                tab: tab,
                expectedGeneration: expectedGeneration
            )

        case .performFallbackWebViewCleanup(let webViewID, let lease):
            guard tabScopedCleanupValidation.canPerformFallbackCleanup(
                with: webViewID,
                lease: lease,
                context: tabScopedCleanupValidationContext()
            ), let webView = webViews.resolve(webViewID) else { return nil }
            return .performFallbackWebViewCleanup(
                webView: webView,
                lease: lease,
                tab: tabs.resolveTabForCleanup(with: lease.tabID)
            )
        }
    }

    private func tabScopedCleanupValidationContext()
        -> WebViewTabScopedCleanupValidationOwner.Context {
        WebViewTabScopedCleanupValidationOwner.Context(
            resolveWebView: { [webViews] webViewID in
                webViews.resolve(webViewID)
            },
            residence: { [webViewSessions] webView in
                webViewSessions.residence(of: webView)
            }
        )
    }
}
