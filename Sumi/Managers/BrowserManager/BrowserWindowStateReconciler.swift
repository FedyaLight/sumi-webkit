import Foundation
/// Repairs registered window state and commits only actual changes.
@MainActor
final class BrowserWindowStateReconciler {
    private let windows: () -> [BrowserWindowState]
    private let spaceContext: BrowserWindowSpaceContextReconciler
    private let selectionRepair: BrowserWindowSelectionRepairService
    private let focusedRuntime: FocusedSpaceRuntimeStateSynchronizer
    private let persistWindowSession: (BrowserWindowState) -> Void
    private let refreshCompositor: (BrowserWindowState) -> Void

    init(
        windows: @escaping () -> [BrowserWindowState],
        spaceContext: BrowserWindowSpaceContextReconciler,
        selectionRepair: BrowserWindowSelectionRepairService,
        focusedRuntime: FocusedSpaceRuntimeStateSynchronizer,
        persistWindowSession: @escaping (BrowserWindowState) -> Void,
        refreshCompositor: @escaping (BrowserWindowState) -> Void
    ) {
        self.windows = windows
        self.spaceContext = spaceContext
        self.selectionRepair = selectionRepair
        self.focusedRuntime = focusedRuntime
        self.persistWindowSession = persistWindowSession
        self.refreshCompositor = refreshCompositor
    }

    @discardableResult
    func validateWindowStates() -> Set<UUID> {
        var persistedWindowIds = Set<UUID>()
        for windowState in windows() {
            let didChangeSpaceContext = spaceContext.reconcile(windowState)
            let didRepairSelection = selectionRepair.reconcile(windowState)
            guard didChangeSpaceContext || didRepairSelection else { continue }

            refreshCompositor(windowState)
            persistWindowSession(windowState)
            persistedWindowIds.insert(windowState.id)
        }

        focusedRuntime.synchronizeActiveWindow()
        return persistedWindowIds
    }

    func synchronizeSpaceContext(in windowState: BrowserWindowState) {
        spaceContext.synchronize(windowState)
        focusedRuntime.synchronizeActiveWindow()
    }

    func synchronizeFocusedSpaceContext(in windowState: BrowserWindowState) {
        focusedRuntime.synchronize(windowState)
    }
}
