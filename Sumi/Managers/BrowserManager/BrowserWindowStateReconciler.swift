import Foundation

/// Repairs registered window state and commits only actual changes.
@MainActor
final class BrowserWindowStateReconciler {
    private let windows: WindowRegistry
    private let spaceContext: BrowserWindowSpaceContextSynchronizer
    private let selectionRepair: BrowserWindowSelectionRepairService
    private let publication: BrowserWindowStateRepairPublication
    private let workspaceThemes: BrowserWorkspaceThemeTransitionOwner

    init(
        windows: WindowRegistry,
        spaceContext: BrowserWindowSpaceContextSynchronizer,
        selectionRepair: BrowserWindowSelectionRepairService,
        publication: BrowserWindowStateRepairPublication,
        workspaceThemes: BrowserWorkspaceThemeTransitionOwner
    ) {
        self.windows = windows
        self.spaceContext = spaceContext
        self.selectionRepair = selectionRepair
        self.publication = publication
        self.workspaceThemes = workspaceThemes
    }

    @discardableResult
    func validateWindowStates() -> Set<UUID> {
        var persistedWindowIds = Set<UUID>()
        for windowState in windows.allWindows {
            let didChangeSpaceContext = spaceContext.reconcile(windowState)
            workspaceThemes.commitWorkspaceTheme(
                spaceContext.workspaceTheme(for: windowState),
                for: windowState
            )
            let didRepairSelection = selectionRepair.reconcile(windowState)
            guard didChangeSpaceContext || didRepairSelection else { continue }

            publication.publish(windowState)
            persistedWindowIds.insert(windowState.id)
        }

        spaceContext.synchronizeActiveWindow()
        return persistedWindowIds
    }

    func synchronizeSpaceContext(in windowState: BrowserWindowState) {
        spaceContext.synchronize(windowState)
    }

    func synchronizeFocusedSpaceContext(in windowState: BrowserWindowState) {
        spaceContext.synchronizeFocusedWindow(windowState)
    }
}
