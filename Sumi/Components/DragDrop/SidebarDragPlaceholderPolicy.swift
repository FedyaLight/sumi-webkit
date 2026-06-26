import Foundation

enum SidebarDragPlaceholderPolicy {
    static func shouldHideCommittedCrossContainerPlaceholder(
        isCompletingDrop: Bool,
        sourceContainer: TabDragManager.DragContainer?,
        targetContainer: TabDragManager.DragContainer,
        targetAlreadyContainsDraggedItem: Bool
    ) -> Bool {
        guard isCompletingDrop,
              let sourceContainer else {
            return false
        }

        if sourceContainer.createsNewLauncherIdentity(whenDroppedInto: targetContainer) {
            return true
        }

        guard targetAlreadyContainsDraggedItem else {
            return false
        }
        return sourceContainer != targetContainer
    }
}

private extension TabDragManager.DragContainer {
    func createsNewLauncherIdentity(whenDroppedInto target: TabDragManager.DragContainer) -> Bool {
        guard case .spaceRegular = self else {
            return false
        }

        switch target {
        case .essentials, .spacePinned, .folder:
            return true
        case .spaceRegular, .none:
            return false
        }
    }
}
