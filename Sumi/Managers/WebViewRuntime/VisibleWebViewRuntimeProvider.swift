import Foundation
import SumiWebRuntime
import WebKit

/// Builds visible-preparation values from stable process and window ports.
@MainActor
final class VisibleWebViewRuntimeProvider {
    private let webViewSessions: WebViewSessionRepository
    private let context: WebViewVisibleRuntimeContext
    private let visibleRuntime: VisibleWebViewRuntimeOwner

    init(
        webViewSessions: WebViewSessionRepository,
        context: WebViewVisibleRuntimeContext,
        visibleRuntime: VisibleWebViewRuntimeOwner
    ) {
        self.webViewSessions = webViewSessions
        self.context = context
        self.visibleRuntime = visibleRuntime
    }

    func runtime(
        evictHiddenWebViews: @escaping @MainActor (UUID, Set<UUID>) -> Void = { _, _ in }
    ) -> VisibleWebViewPreparationRuntime {
        VisibleWebViewPreparationRuntime(
            windowState: context.windowState,
            currentTabId: context.currentTabId,
            splitVisibleTabIds: context.splitVisibleTabIds,
            resolveTab: context.resolveTab,
            canMaterializeWebViewDuringStartup: context.canMaterializeWebViewDuringStartup,
            markTabAccessed: context.markTabAccessed,
            evictHiddenWebViews: evictHiddenWebViews,
            scheduleTabSuspensionReconcile: context.scheduleTabSuspensionReconcile,
            refreshCompositor: context.refreshCompositor
        )
    }

    func preferredPrimaryCandidate(
        for tabID: UUID
    ) -> (owner: TrackedWebViewOwner, webView: WKWebView)? {
        visibleRuntime.preferredPrimaryWebViewCandidate(
            for: tabID,
            runtime: runtime(),
            webViewSessions: webViewSessions
        )
    }
}
