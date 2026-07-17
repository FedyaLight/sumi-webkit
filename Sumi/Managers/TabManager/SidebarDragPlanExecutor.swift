import Foundation
import SumiDomain

@MainActor
final class SidebarDragPlanExecutor {
    private let folderPlacement: TabFolderPlacementTransaction
    private let shortcuts: ShortcutDragOperationOwner
    private let regularTabs: SidebarRegularTabDragService
    private let splits: SplitGroupSidebarOrderingService

    init(
        folderPlacement: TabFolderPlacementTransaction,
        shortcuts: ShortcutDragOperationOwner,
        regularTabs: SidebarRegularTabDragService,
        splits: SplitGroupSidebarOrderingService
    ) {
        self.folderPlacement = folderPlacement
        self.shortcuts = shortcuts
        self.regularTabs = regularTabs
        self.splits = splits
    }

    func execute(
        _ plan: SidebarDragOperationPlan,
        operation: DragOperation
    ) -> Bool {
        switch plan.kind {
        case .folderHeaderReorder(let folder, _),
             .folderHeaderUnsupported(let folder):
            return folderPlacement.handleFolderDragOperation(
                folder,
                operation: operation
            )

        case .shortcutSplitGroup(let group):
            guard case .spacePinned(let sourceSpaceID) = operation.fromContainer,
                  case .spacePinned(let targetSpaceID) = operation.toContainer,
                  sourceSpaceID == targetSpaceID else {
                return false
            }
            return splits.moveGroup(group, in: targetSpaceID, to: operation.toIndex)

        case .launcher(let pin, _):
            return shortcuts.handleShortcutDragOperation(pin, operation: operation)

        case .regularTab(let tab, let regularOperation):
            return regularTabs.execute(
                tab,
                regularOperation: regularOperation,
                dragOperation: operation
            )

        case .unsupported:
            return false
        }
    }
}
