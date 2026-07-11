import Foundation

@MainActor
extension BrowserWindowStateReconciler {
    convenience init(browserManager: BrowserManager) {
        let spaceContext = BrowserWindowSpaceContextReconciler(
            browserManager: browserManager
        )
        self.init(
            windows: { [weak browserManager] in
                browserManager?.windowRegistry?.allWindows ?? []
            },
            spaceContext: spaceContext,
            selectionRepair: BrowserWindowSelectionRepairService(
                browserManager: browserManager
            ),
            focusedRuntime: FocusedSpaceRuntimeStateSynchronizer(
                activeWindow: { [weak browserManager] in
                    browserManager?.windowRegistry?.activeWindow
                },
                windowContext: spaceContext,
                runtimeState: browserManager.tabManager.profileRuntimeState
            ),
            persistWindowSession: { [weak browserManager] windowState in
                browserManager?.windowSessionBundle.persistence
                    .persist(windowState)
            },
            refreshCompositor: { [weak browserManager] windowState in
                browserManager?.shellRuntime.windowVisuals
                    .refreshCompositor(for: windowState)
            }
        )
    }
}
