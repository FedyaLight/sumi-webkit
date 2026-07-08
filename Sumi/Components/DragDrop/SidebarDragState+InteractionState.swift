import Foundation

// Every setter below drops writes that don't change the value. The AppKit drag
// pipeline re-resolves state on each pointer sample (and on periodic dragging
// updates while the pointer is idle); without this guard each sample publishes
// `objectWillChange` to every observing sidebar view even when nothing moved.
extension SidebarDragState {
    var isDragging: Bool {
        get { interactionStateOwner.isDragging }
        set {
            guard interactionStateOwner.isDragging != newValue else { return }
            interactionStateOwner.isDragging = newValue
            activityState.isDragging = newValue
        }
    }

    var hoveredSlot: DropZoneSlot {
        get { interactionStateOwner.hoveredSlot }
        set {
            guard interactionStateOwner.hoveredSlot != newValue else { return }
            interactionStateOwner.hoveredSlot = newValue
        }
    }

    var folderDropIntent: FolderDropIntent {
        get { interactionStateOwner.folderDropIntent }
        set {
            guard interactionStateOwner.folderDropIntent != newValue else { return }
            interactionStateOwner.folderDropIntent = newValue
        }
    }

    var activeHoveredFolderId: UUID? {
        get { interactionStateOwner.activeHoveredFolderId }
        set {
            guard interactionStateOwner.activeHoveredFolderId != newValue else { return }
            interactionStateOwner.activeHoveredFolderId = newValue
        }
    }

    var activeSplitTarget: SplitDropSide? {
        get { interactionStateOwner.activeSplitTarget }
        set {
            guard interactionStateOwner.activeSplitTarget != newValue else { return }
            interactionStateOwner.activeSplitTarget = newValue
        }
    }

    var activeDragItemId: UUID? {
        get { interactionStateOwner.activeDragItemId }
        set {
            guard interactionStateOwner.activeDragItemId != newValue else { return }
            interactionStateOwner.activeDragItemId = newValue
        }
    }

    var previewKind: SidebarDragPreviewKind? {
        get { interactionStateOwner.previewKind }
        set {
            guard interactionStateOwner.previewKind != newValue else { return }
            interactionStateOwner.previewKind = newValue
        }
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
        set {
            guard interactionStateOwner.isInternalDragSession != newValue else { return }
            interactionStateOwner.isInternalDragSession = newValue
        }
    }

    var activeDragScope: SidebarDragScope? {
        get { interactionStateOwner.activeDragScope }
        set {
            guard interactionStateOwner.activeDragScope != newValue else { return }
            interactionStateOwner.activeDragScope = newValue
        }
    }

    var regularExternalDropGap: SidebarRegularExternalDropGap? {
        get { interactionStateOwner.regularExternalDropGap }
        set {
            guard interactionStateOwner.regularExternalDropGap != newValue else { return }
            interactionStateOwner.regularExternalDropGap = newValue
        }
    }
}
