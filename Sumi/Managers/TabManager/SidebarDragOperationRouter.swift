import Foundation
import SumiDomain

/// Resolves sidebar drag provenance and delegates mutations to exact
/// transaction boundaries.
@MainActor
final class SidebarDragOperationRouter {
    private let resolution: SidebarDragPayloadResolver
    private let dragOperations: SidebarDragOperationTransaction
    private let explicitMoves: SidebarExplicitTabMoveTransaction

    init(
        resolution: SidebarDragPayloadResolver,
        dragOperations: SidebarDragOperationTransaction,
        explicitMoves: SidebarExplicitTabMoveTransaction
    ) {
        self.resolution = resolution
        self.dragOperations = dragOperations
        self.explicitMoves = explicitMoves
    }

    @discardableResult
    func performSidebarDragCommit(_ intent: SidebarDragCommitIntent) -> Bool {
        dragOperations.perform(intent)
    }

    /// Internal command path for callers that already own durable placement
    /// semantics. Sidebar DnD must use `performSidebarDragCommit` instead.
    @discardableResult
    func performSidebarDragOperation(_ operation: DragOperation) -> Bool {
        dragOperations.perform(operation)
    }

    @discardableResult
    func handleDragOperation(_ operation: DragOperation) -> Bool {
        dragOperations.perform(operation)
    }

    func resolveDragTab(for id: UUID) -> Tab? {
        resolution.resolveTab(for: id)
    }

    func resolveDragTab(for item: SumiDragItem) -> Tab? {
        resolution.resolveTab(for: item)
    }

    func resolveSidebarDragPayload(
        for item: SumiDragItem
    ) -> DragOperation.Payload? {
        resolution.resolvePayload(for: item)
    }

    func moveTab(_ tabID: UUID, to targetSpaceID: UUID) {
        _ = explicitMoves.move(tabID, to: targetSpaceID)
    }
}
