import Foundation

struct SidebarDropCommitProjectionState: Equatable {
    private(set) var isCompletingDrop = false
    private var itemId: UUID?
    private var scope: SidebarDragScope?
    private var slot: DropZoneSlot = .empty
    private var folderIntent: FolderDropIntent = .none

    func isDropProjectionActive(isDragging: Bool) -> Bool {
        isDragging || isCompletingDrop
    }

    func dragItemId(activeDragItemId: UUID?) -> UUID? {
        activeDragItemId ?? itemId
    }

    func dragScope(activeDragScope: SidebarDragScope?) -> SidebarDragScope? {
        activeDragScope ?? scope
    }

    func hoveredSlot(activeHoveredSlot: DropZoneSlot) -> DropZoneSlot {
        activeHoveredSlot != .empty ? activeHoveredSlot : slot
    }

    func folderDropIntent(activeFolderDropIntent: FolderDropIntent) -> FolderDropIntent {
        activeFolderDropIntent != .none ? activeFolderDropIntent : folderIntent
    }

    func shouldHideCommittedCrossContainerPlaceholder(
        activeDragScope: SidebarDragScope?,
        targetContainer: TabDragManager.DragContainer,
        targetAlreadyContainsDraggedItem: Bool
    ) -> Bool {
        SidebarDragPlaceholderPolicy.shouldHideCommittedCrossContainerPlaceholder(
            isCompletingDrop: isCompletingDrop,
            sourceContainer: dragScope(activeDragScope: activeDragScope)?.sourceContainer,
            targetContainer: targetContainer,
            targetAlreadyContainsDraggedItem: targetAlreadyContainsDraggedItem
        )
    }

    mutating func begin(
        itemId: UUID?,
        scope: SidebarDragScope?,
        slot: DropZoneSlot,
        folderIntent: FolderDropIntent
    ) {
        self.itemId = itemId
        self.scope = scope
        self.slot = slot
        self.folderIntent = folderIntent
        isCompletingDrop = true
    }

    mutating func finish() {
        isCompletingDrop = false
        itemId = nil
        scope = nil
        slot = .empty
        folderIntent = .none
    }
}
