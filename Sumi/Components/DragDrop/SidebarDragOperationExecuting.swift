import Foundation

/// Narrow mutation authority for sidebar drag commit: resolve pasteboard item
/// into a live payload, then execute the exact presented visual destination.
@MainActor
protocol SidebarDragOperationExecuting: AnyObject {
    func resolveSidebarDragPayload(for item: SumiDragItem) -> DragOperation.Payload?
    func performSidebarDragCommit(_ intent: SidebarDragCommitIntent) -> Bool
}

extension SidebarDragOperationRouter: SidebarDragOperationExecuting {}
