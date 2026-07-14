import Foundation
import SumiWebRuntime
import WebKit

/// Presentation-state operations that do not mutate canonical ownership.
/// Keeping this separate from admission and placement prevents a constructor cycle
/// between registration cleanup, protected-command dispatch, and visibility.
@MainActor
final class WebViewVisibilityRuntime {
    private let visibleRuntime: VisibleWebViewRuntimeOwner
    private let materialization: TabWebViewMaterializationService
    private let visibleRuntimeProvider: VisibleWebViewRuntimeProvider
    private let hiddenCloneEviction: HiddenCloneEvictionService

    init(
        visibleRuntime: VisibleWebViewRuntimeOwner,
        materialization: TabWebViewMaterializationService,
        visibleRuntimeProvider: VisibleWebViewRuntimeProvider,
        hiddenCloneEviction: HiddenCloneEvictionService
    ) {
        self.visibleRuntime = visibleRuntime
        self.materialization = materialization
        self.visibleRuntimeProvider = visibleRuntimeProvider
        self.hiddenCloneEviction = hiddenCloneEviction
    }

    func visiblePreparationRuntime() -> VisibleWebViewPreparationRuntime {
        visibleRuntimeProvider.runtime { [hiddenCloneEviction] windowID, visibleTabIDs in
            hiddenCloneEviction.evict(
                in: windowID,
                visibleTabIDs: visibleTabIDs
            )
        }
    }

    @discardableResult
    func prepareVisibleWebViews(
        for windowState: BrowserWindowState,
        runtime: VisibleWebViewPreparationRuntime,
        webViewSessions: WebViewSessionRepository,
        existingWebView: @escaping (UUID, UUID) -> WKWebView?,
        createWebView: @escaping (
            any WebRuntimeTabHandle,
            any WebRuntimeWindowHandle
        ) -> WKWebView?
    ) -> Bool {
        visibleRuntime.prepareVisibleWebViews(
            for: windowState,
            runtime: runtime,
            webViewSessions: webViewSessions,
            existingWebView: existingWebView,
            createWebView: createWebView
        )
    }

    func schedulePrepareVisibleWebViews(
        for windowState: BrowserWindowState,
        runtime: VisibleWebViewPreparationRuntime,
        prepare: @escaping (any WebRuntimeWindowHandle) -> Bool
    ) {
        visibleRuntime.schedulePrepareVisibleWebViews(
            for: windowState,
            runtime: runtime,
            prepareVisibleWebViews: prepare
        )
    }

    func visibleTabIDs(in windowID: UUID) -> Set<UUID> {
        visibleRuntime.visibleTabIDSet(
            in: windowID,
            runtime: visiblePreparationRuntime()
        )
    }

    func refreshPrimaryWebView(for tab: Tab) {
        materialization.refreshPrimary(for: tab)
    }

    @discardableResult
    func evictHiddenWebViewsIfNeeded(
        in windowID: UUID,
        visibleTabIDs: Set<UUID>
    ) -> Bool {
        hiddenCloneEviction.evict(in: windowID, visibleTabIDs: visibleTabIDs)
    }
}
