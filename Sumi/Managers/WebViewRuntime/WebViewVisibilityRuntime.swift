import Foundation
import SumiWebRuntime
import WebKit

/// Presentation-state operations that do not mutate canonical ownership.
/// Keeping this below the ownership service prevents a constructor cycle
/// between registration cleanup, protected-command dispatch, and visibility.
@MainActor
final class WebViewVisibilityRuntime {
    private let visibleRuntime: VisibleWebViewRuntimeOwner
    private let materialization: TabWebViewMaterializationService
    private let runtimeAssembler: WebViewRuntimeAssembler
    private let globallyVisibleTabIDs: @MainActor () -> Set<UUID>

    init(
        visibleRuntime: VisibleWebViewRuntimeOwner,
        materialization: TabWebViewMaterializationService,
        runtimeAssembler: WebViewRuntimeAssembler,
        globallyVisibleTabIDs: @escaping @MainActor () -> Set<UUID>
    ) {
        self.visibleRuntime = visibleRuntime
        self.materialization = materialization
        self.runtimeAssembler = runtimeAssembler
        self.globallyVisibleTabIDs = globallyVisibleTabIDs
    }

    func visiblePreparationRuntime() -> VisibleWebViewPreparationRuntime {
        runtimeAssembler.requireVisiblePreparationRuntime()
    }

    @discardableResult
    func prepareVisibleWebViews(
        for windowState: BrowserWindowState,
        runtime: VisibleWebViewPreparationRuntime,
        webViewSessions: WebViewSessionRepository,
        existingWebView: @escaping (UUID, UUID) -> WKWebView?,
        createWebView: @escaping (any WebRuntimeTabHandle, UUID) -> WKWebView?
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

    func evictHiddenWebViewsIfNeeded(
        in windowID: UUID,
        visibleTabIDs: Set<UUID>
    ) {
        runtimeAssembler.evictHiddenWebViews(
            in: windowID,
            visibleTabIDs: visibleTabIDs,
            globallyVisibleTabIDs: globallyVisibleTabIDs
        )
    }
}
