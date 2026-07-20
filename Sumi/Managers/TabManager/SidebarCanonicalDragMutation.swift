import Foundation
import SumiDomain

/// Applies an already canonical, context-validated sidebar drag operation.
@MainActor
final class SidebarCanonicalDragMutation {
    private let folderPlacement: TabFolderPlacementTransaction
    private let shortcuts: ShortcutDragOperationOwner
    private let regularTabs: SidebarRegularTabDragService
    private let splits: SplitGroupContainerConversion
    private let payloads: SidebarDragPayloadResolver

    init(
        folderPlacement: TabFolderPlacementTransaction,
        shortcuts: ShortcutDragOperationOwner,
        regularTabs: SidebarRegularTabDragService,
        splits: SplitGroupContainerConversion,
        payloads: SidebarDragPayloadResolver
    ) {
        self.folderPlacement = folderPlacement
        self.shortcuts = shortcuts
        self.regularTabs = regularTabs
        self.splits = splits
        self.payloads = payloads
    }

    func perform(_ operation: DragOperation) -> Bool {
        if let folder = operation.folder {
            return folderPlacement.handleFolderDragOperation(
                folder,
                operation: operation
            )
        }

        if let splitGroup = operation.splitGroup {
            guard operation.toContainer != .none else { return false }
            return splits.move(splitGroup, operation: operation)
        }

        if let pin = operation.pin {
            return shortcuts.handleShortcutDragOperation(pin, operation: operation)
        }

        guard let tab = operation.tab else { return false }
        if let shortcutID = tab.shortcutPinId,
           let pin = payloads.shortcutPin(for: shortcutID) {
            return shortcuts.handleShortcutDragOperation(
                pin,
                operation: operation
            )
        }
        return regularTabs.execute(tab, dragOperation: operation)
    }
}
