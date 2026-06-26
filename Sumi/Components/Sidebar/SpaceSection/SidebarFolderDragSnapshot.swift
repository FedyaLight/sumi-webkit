import CoreGraphics
import Foundation

struct SidebarFolderDragSnapshot: Equatable {
    let isDragging: Bool
    let isCompletingDrop: Bool
    let activeDragItemID: UUID?
    let activeHoveredFolderID: UUID?
    let folderDropIntent: FolderDropIntent
    let geometryGeneration: Int
    let isDropProjectionActive: Bool
    let projectionDragItemID: UUID?
    let projectionSourceContainer: TabDragManager.DragContainer?
    let projectionFolderDropIntent: FolderDropIntent

    init(
        isDragging: Bool = false,
        isCompletingDrop: Bool = false,
        activeDragItemID: UUID? = nil,
        activeHoveredFolderID: UUID? = nil,
        folderDropIntent: FolderDropIntent = .none,
        geometryGeneration: Int = 0,
        isDropProjectionActive: Bool? = nil,
        projectionDragItemID: UUID? = nil,
        projectionSourceContainer: TabDragManager.DragContainer? = nil,
        projectionFolderDropIntent: FolderDropIntent = .none
    ) {
        self.isDragging = isDragging
        self.isCompletingDrop = isCompletingDrop
        self.activeDragItemID = activeDragItemID
        self.activeHoveredFolderID = activeHoveredFolderID
        self.folderDropIntent = folderDropIntent
        self.geometryGeneration = geometryGeneration
        self.isDropProjectionActive = isDropProjectionActive ?? (isDragging || isCompletingDrop)
        self.projectionDragItemID = projectionDragItemID
        self.projectionSourceContainer = projectionSourceContainer
        self.projectionFolderDropIntent = projectionFolderDropIntent
    }

    @MainActor
    init(dragState: SidebarDragState) {
        self.init(
            isDragging: dragState.isDragging,
            isCompletingDrop: dragState.isCompletingDrop,
            activeDragItemID: dragState.activeDragItemId,
            activeHoveredFolderID: dragState.activeHoveredFolderId,
            folderDropIntent: dragState.folderDropIntent,
            geometryGeneration: dragState.sidebarGeometryGeneration,
            isDropProjectionActive: dragState.isDropProjectionActive,
            projectionDragItemID: dragState.projectionDragItemId,
            projectionSourceContainer: dragState.projectionDragScope?.sourceContainer,
            projectionFolderDropIntent: dragState.projectionFolderDropIntent
        )
    }

    var projectionSourceFolderID: UUID? {
        guard case .folder(let folderID) = projectionSourceContainer else {
            return nil
        }
        return folderID
    }

    func isContainTargeted(folderID: UUID) -> Bool {
        folderDropIntent == .contain(folderId: folderID)
    }

    func isFolderPreviewOpen(folderID: UUID, isOpen: Bool) -> Bool {
        isOpen || (isDragging && activeHoveredFolderID == folderID)
    }

    func allowsLayoutAnimation(isInteractive: Bool) -> Bool {
        isInteractive && !isCompletingDrop
    }

    func afterDropTargetHeight(rowHeight: CGFloat) -> CGFloat {
        isDragging ? rowHeight * 0.45 : 0
    }

    func childOpacity(itemID: UUID) -> Double {
        isDragging && activeDragItemID == itemID ? 0.001 : 1
    }

    func shouldHideCommittedPlaceholder(
        into targetContainer: TabDragManager.DragContainer,
        targetAlreadyContainsDraggedItem: Bool
    ) -> Bool {
        SidebarDragPlaceholderPolicy.shouldHideCommittedCrossContainerPlaceholder(
            isCompletingDrop: isCompletingDrop,
            sourceContainer: projectionSourceContainer,
            targetContainer: targetContainer,
            targetAlreadyContainsDraggedItem: targetAlreadyContainsDraggedItem
        )
    }
}
