import Foundation

/// Owns the Presented Drop Intent from hover presentation through the short
/// post-commit projection interval. The active and committed destinations are
/// kept together so rendered gaps and structural commits cannot diverge.
struct SidebarPresentedDropIntentState: Equatable {
    private var activeResolution = SidebarDropResolution.empty
    private var committedResolution: SidebarDropResolution?
    private(set) var isCompletingDrop = false
    private var itemId: UUID?
    private var scope: SidebarDragScope?

    var active: SidebarDropResolution { activeResolution }

    var projected: SidebarDropResolution {
        activeResolution.slot == .empty
            ? committedResolution ?? .empty
            : activeResolution
    }

    mutating func present(_ resolution: SidebarDropResolution) {
        activeResolution = resolution
    }

    mutating func clearPresentation() {
        activeResolution = .empty
    }

    func isDropProjectionActive(isDragging: Bool) -> Bool {
        isDragging || isCompletingDrop
    }

    func dragItemId(activeDragItemId: UUID?) -> UUID? {
        activeDragItemId ?? itemId
    }

    func dragScope(activeDragScope: SidebarDragScope?) -> SidebarDragScope? {
        activeDragScope ?? scope
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
        resolution: SidebarDropResolution
    ) {
        self.itemId = itemId
        self.scope = scope
        activeResolution = resolution
        committedResolution = resolution
        isCompletingDrop = true
    }

    mutating func finish() {
        isCompletingDrop = false
        itemId = nil
        scope = nil
        committedResolution = nil
    }
}
