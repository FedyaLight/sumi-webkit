import Foundation
import SumiWebRuntime
import WebKit

/// Composes hidden-clone eviction from exact cleanup and visibility roles.
@MainActor
final class HiddenCloneEvictionService {
    private let owner: WebViewHiddenCloneEvictionOwner
    private let webViewSessions: WebViewSessionRepository
    private let runtime: WebViewHiddenCloneEvictionOwner.Runtime
    private let globallyVisibleTabIDs: @MainActor () -> Set<UUID>

    init(
        owner: WebViewHiddenCloneEvictionOwner,
        webViewSessions: WebViewSessionRepository,
        runtime: WebViewHiddenCloneEvictionOwner.Runtime,
        globallyVisibleTabIDs: @escaping @MainActor () -> Set<UUID>
    ) {
        self.owner = owner
        self.webViewSessions = webViewSessions
        self.runtime = runtime
        self.globallyVisibleTabIDs = globallyVisibleTabIDs
    }

    @discardableResult
    func evict(
        in windowID: UUID,
        visibleTabIDs: Set<UUID>
    ) -> Bool {
        owner.evictHiddenWebViews(
            in: windowID,
            visibleTabIDs: visibleTabIDs,
            entries: webViewSessions.trackedWebViews(in: windowID),
            runtime: .init(
                tabForID: runtime.tabForID,
                liveWebViews: runtime.liveWebViews,
                globallyVisibleTabIDs: globallyVisibleTabIDs,
                isWebViewProtectedFromCompositorMutation:
                    runtime.isWebViewProtectedFromCompositorMutation,
                enqueueDeferredProtectedCommand:
                    runtime.enqueueDeferredProtectedCommand,
                cleanupUnprotectedTrackedWebView:
                    runtime.cleanupUnprotectedTrackedWebView,
                refreshPrimaryTrackedWebView:
                    runtime.refreshPrimaryTrackedWebView
            )
        )
    }
}
