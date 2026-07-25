import CoreGraphics
import Foundation

struct SidebarFolderDragSnapshot: Equatable {
    let isDragging: Bool
    let isCompletingDrop: Bool
    let activeDragItemID: UUID?
    let activeHoveredFolderID: UUID?
    let folderDropIntent: FolderDropIntent
    let geometryGeneration: Int

    init(
        isDragging: Bool = false,
        isCompletingDrop: Bool = false,
        activeDragItemID: UUID? = nil,
        activeHoveredFolderID: UUID? = nil,
        folderDropIntent: FolderDropIntent = .none,
        geometryGeneration: Int = 0
    ) {
        self.isDragging = isDragging
        self.isCompletingDrop = isCompletingDrop
        self.activeDragItemID = activeDragItemID
        self.activeHoveredFolderID = activeHoveredFolderID
        self.folderDropIntent = folderDropIntent
        self.geometryGeneration = geometryGeneration
    }

    func isContainTargeted(folderID: UUID) -> Bool {
        folderDropIntent == .contain(folderId: folderID)
    }

    func isFolderPreviewOpen(folderID: UUID, isOpen: Bool) -> Bool {
        isOpen || (isDragging && activeHoveredFolderID == folderID)
    }

    func afterDropTargetHeight(rowHeight: CGFloat) -> CGFloat {
        isDragging ? rowHeight * 0.45 : 0
    }

    func childOpacity(itemID: UUID) -> Double {
        isDragging && activeDragItemID == itemID ? SidebarDragSourceDim.opacity : 1
    }
}
