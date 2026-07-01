import Combine
import Foundation

@MainActor
final class SidebarDragInteractionStateOwner: ObservableObject {
    @Published var isDragging: Bool = false
    @Published var hoveredSlot: DropZoneSlot = .empty
    @Published var folderDropIntent: FolderDropIntent = .none
    @Published var activeHoveredFolderId: UUID?
    @Published var activeSplitTarget: SplitDropSide?
    @Published var activeDragItemId: UUID?
    @Published var previewKind: SidebarDragPreviewKind?
    @Published var previewAssets: [SidebarDragPreviewKind: SidebarDragPreviewAsset] = [:]
    @Published var previewModel: SidebarDragPreviewModel?
    @Published var isInternalDragSession: Bool = false
    @Published var activeDragScope: SidebarDragScope?
}
