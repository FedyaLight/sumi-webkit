import Combine
import Foundation

@MainActor
final class SidebarDragInteractionStateOwner: ObservableObject {
    @Published var isDragging: Bool = false
    @Published var hoveredSlot: DropZoneSlot = .empty
    @Published var folderDropIntent: FolderDropIntent = .none
    @Published var activeHoveredFolderId: UUID? = nil
    @Published var activeSplitTarget: SplitDropSide? = nil
    @Published var activeDragItemId: UUID? = nil
    @Published var previewKind: SidebarDragPreviewKind? = nil
    @Published var previewAssets: [SidebarDragPreviewKind: SidebarDragPreviewAsset] = [:]
    @Published var previewModel: SidebarDragPreviewModel? = nil
    @Published var isInternalDragSession: Bool = false
    @Published var activeDragScope: SidebarDragScope? = nil
}
