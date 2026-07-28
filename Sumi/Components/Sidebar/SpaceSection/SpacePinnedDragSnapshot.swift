import Foundation

/// Exact drag values consumed by the flattened sidebar scene.
struct SpacePinnedDragSnapshot: Equatable {
    let isDragging: Bool
    let isCompletingDrop: Bool
    let activeDragItemID: UUID?
    let activeHoveredFolderID: UUID?
    let folderDropIntent: FolderDropIntent
    let splitPairingTarget: SidebarSplitPairingTarget?
    let isHoveringEmptySection: Bool
    let geometryGeneration: Int

    init(
        isDragging: Bool,
        isCompletingDrop: Bool,
        activeDragItemID: UUID?,
        activeHoveredFolderID: UUID?,
        folderDropIntent: FolderDropIntent,
        splitPairingTarget: SidebarSplitPairingTarget? = nil,
        isHoveringEmptySection: Bool,
        geometryGeneration: Int
    ) {
        self.isDragging = isDragging
        self.isCompletingDrop = isCompletingDrop
        self.activeDragItemID = activeDragItemID
        self.activeHoveredFolderID = activeHoveredFolderID
        self.folderDropIntent = folderDropIntent
        self.splitPairingTarget = splitPairingTarget
        self.isHoveringEmptySection = isHoveringEmptySection
        self.geometryGeneration = geometryGeneration
    }

    @MainActor
    init(
        frame: SidebarListDragPresentationFrame,
        geometryGeneration: Int,
        spaceID: UUID
    ) {
        self.init(
            isDragging: frame.isDragging,
            isCompletingDrop: frame.isCompletingDrop,
            activeDragItemID: frame.activeDragItemID,
            activeHoveredFolderID: frame.activeHoveredFolderID,
            folderDropIntent: frame.folderDropIntent,
            splitPairingTarget: frame.splitPairingTarget,
            isHoveringEmptySection: frame.hoveredPinnedSpaceID == spaceID,
            geometryGeneration: geometryGeneration
        )
    }

    var folderSnapshot: SidebarFolderDragSnapshot {
        SidebarFolderDragSnapshot(
            isDragging: isDragging,
            isCompletingDrop: isCompletingDrop,
            activeDragItemID: activeDragItemID,
            activeHoveredFolderID: activeHoveredFolderID,
            folderDropIntent: folderDropIntent,
            splitPairingTarget: splitPairingTarget,
            geometryGeneration: geometryGeneration
        )
    }
}
