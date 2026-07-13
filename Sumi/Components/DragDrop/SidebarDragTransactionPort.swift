import AppKit

/// The single sidebar drop commit boundary. Intent and pasteboard evidence are
/// resolved by the UI; this port validates the exact window owner and delegates
/// one canonical structural transaction to the existing drag router.
@MainActor
final class SidebarDragTransactionPort {
    private let windows: SidebarWindowIdentityQuery
    private let sourceInventory: any SidebarDragSourceInventorying
    private let dragOperations: any SidebarDragOperationExecuting
    private let urlDropService: SidebarURLDropService

    init(
        windows: SidebarWindowIdentityQuery,
        sourceInventory: any SidebarDragSourceInventorying,
        dragOperations: any SidebarDragOperationExecuting,
        urlDropService: SidebarURLDropService
    ) {
        self.windows = windows
        self.sourceInventory = sourceInventory
        self.dragOperations = dragOperations
        self.urlDropService = urlDropService
    }

    func commit(
        pasteboard: NSPasteboard,
        resolution: SidebarDropResolution,
        windowState: BrowserWindowState?
    ) -> Bool {
        guard let windowState, windows.contains(windowState) else {
            return false
        }
        return SidebarDropCoordinator.performDrop(
            pasteboard: pasteboard,
            resolution: resolution,
            sourceInventory: sourceInventory,
            dragOperations: dragOperations,
            urlDropService: urlDropService,
            windowState: windowState
        )
    }
}
