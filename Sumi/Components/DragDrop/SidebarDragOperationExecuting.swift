import Foundation

/// Narrow mutation authority for sidebar drag commit: resolve pasteboard item
/// into a live payload, then execute a planned `DragOperation`.
@MainActor
protocol SidebarDragOperationExecuting: AnyObject {
    func resolveSidebarDragPayload(for item: SumiDragItem) -> DragOperation.Payload?
    func performSidebarDragOperation(_ operation: DragOperation) -> Bool
}

extension SidebarDragOperationRouter: SidebarDragOperationExecuting {}
