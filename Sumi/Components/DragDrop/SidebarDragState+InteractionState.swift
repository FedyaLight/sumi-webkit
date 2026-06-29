import Foundation

extension SidebarDragState {
    var isDragging: Bool {
        get { interactionStateOwner.isDragging }
        set { interactionStateOwner.isDragging = newValue }
    }

    var hoveredSlot: DropZoneSlot {
        get { interactionStateOwner.hoveredSlot }
        set { interactionStateOwner.hoveredSlot = newValue }
    }

    var folderDropIntent: FolderDropIntent {
        get { interactionStateOwner.folderDropIntent }
        set { interactionStateOwner.folderDropIntent = newValue }
    }

    var activeHoveredFolderId: UUID? {
        get { interactionStateOwner.activeHoveredFolderId }
        set { interactionStateOwner.activeHoveredFolderId = newValue }
    }

    var activeSplitTarget: SplitDropSide? {
        get { interactionStateOwner.activeSplitTarget }
        set { interactionStateOwner.activeSplitTarget = newValue }
    }

    var activeDragItemId: UUID? {
        get { interactionStateOwner.activeDragItemId }
        set { interactionStateOwner.activeDragItemId = newValue }
    }

    var previewKind: SidebarDragPreviewKind? {
        get { interactionStateOwner.previewKind }
        set { interactionStateOwner.previewKind = newValue }
    }

    var previewAssets: [SidebarDragPreviewKind: SidebarDragPreviewAsset] {
        get { interactionStateOwner.previewAssets }
        set { interactionStateOwner.previewAssets = newValue }
    }

    var previewModel: SidebarDragPreviewModel? {
        get { interactionStateOwner.previewModel }
        set { interactionStateOwner.previewModel = newValue }
    }

    var isInternalDragSession: Bool {
        get { interactionStateOwner.isInternalDragSession }
        set { interactionStateOwner.isInternalDragSession = newValue }
    }

    var activeDragScope: SidebarDragScope? {
        get { interactionStateOwner.activeDragScope }
        set { interactionStateOwner.activeDragScope = newValue }
    }
}
