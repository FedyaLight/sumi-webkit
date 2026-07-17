import Foundation

@MainActor
extension BrowserWindowStateReconciler {
    static func live(
        windows: WindowRegistry,
        spaceContext: BrowserWindowSpaceContextSynchronizer,
        selectionRepair: BrowserWindowSelectionRepairService,
        publication: BrowserWindowStateRepairPublication,
        workspaceThemes: BrowserWorkspaceThemeTransitionOwner
    ) -> BrowserWindowStateReconciler {
        BrowserWindowStateReconciler(
            windows: windows,
            spaceContext: spaceContext,
            selectionRepair: selectionRepair,
            publication: publication,
            workspaceThemes: workspaceThemes
        )
    }
}
