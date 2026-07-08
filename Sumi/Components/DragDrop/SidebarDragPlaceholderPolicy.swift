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

    /// True when a drop is completing from a shortcut-hosting container
    /// (essentials/space-pinned/folder) into a *different* target container —
    /// i.e. the dragged item is losing its persistent shortcut identity and
    /// becoming (or returning to being) a plain item in `targetContainer`.
    /// Used to suppress a stale commit-time insertion gap at the target while
    /// the item's identity transition settles.
    static func shouldSuppressCommitGapForExternalSource(
        isCompletingDrop: Bool,
        sourceContainer: TabDragManager.DragContainer?,
        targetContainer: TabDragManager.DragContainer
    ) -> Bool {
        guard isCompletingDrop,
              let sourceContainer,
              sourceContainer != targetContainer else {
            return false
        }
        return sourceContainer.hostsShortcutIdentity
    }
}

private extension TabDragManager.DragContainer {
    var hostsShortcutIdentity: Bool {
        switch self {
        case .essentials, .spacePinned, .folder:
            return true
        case .spaceRegular, .none:
            return false
        }
    }

    func createsNewLauncherIdentity(whenDroppedInto target: TabDragManager.DragContainer) -> Bool {
        guard case .spaceRegular = self else {
            return false
        }
        return target.hostsShortcutIdentity
    }
}
