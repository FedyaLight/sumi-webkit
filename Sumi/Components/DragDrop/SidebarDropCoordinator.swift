import AppKit
import SwiftUI

enum SidebarDropCoordinator {
    static func draggedItem(from pasteboard: NSPasteboard) -> SumiDragItem? {
        SidebarDragPasteboardPayload.fromPasteboard(pasteboard)?.item
    }

    static func dragOperation(for pasteboard: NSPasteboard) -> NSDragOperation {
        draggedItem(from: pasteboard) == nil ? .copy : .move
    }

    @MainActor
    static func validatedScope(
        for item: SumiDragItem,
        pasteboard: NSPasteboard,
        dragState: SidebarDragState,
        windowState: BrowserWindowState?
    ) -> SidebarDragScope? {
        guard let payload = SidebarDragPasteboardPayload.fromPasteboard(pasteboard),
              payload.item == item,
              payload.sourceItemId == item.tabId,
              payload.sourceItemKind == item.kind,
              payload.scope.matches(windowId: windowState?.id),
              payload.sourceSpaceId == windowState?.currentSpaceId,
              payload.scope.matches(profileId: windowState?.currentProfileId) else {
            return nil
        }
        return payload.scope
    }

    @MainActor
    static func resolveDropResolution(
        pasteboard: NSPasteboard,
        swiftUILocation: CGPoint,
        previewLocation: CGPoint?,
        dragState: SidebarDragState,
        windowState: BrowserWindowState?,
        draggedItem cachedDraggedItem: SumiDragItem? = nil,
        scope cachedScope: SidebarDragScope? = nil
    ) -> SidebarDropResolution? {
        let draggedItem = cachedDraggedItem ?? draggedItem(from: pasteboard)
        let scope = cachedScope ?? draggedItem.flatMap {
            validatedScope(
                for: $0,
                pasteboard: pasteboard,
                dragState: dragState,
                windowState: windowState
            )
        }

        if draggedItem != nil, scope == nil {
            dragState.clearHoverState()
            return nil
        }

        return SidebarDropResolver.updateState(
            location: swiftUILocation,
            previewLocation: previewLocation,
            state: dragState,
            draggedItem: draggedItem,
            scope: scope
        )
    }

    @MainActor
    static func performDrop(
        pasteboard: NSPasteboard,
        resolution: SidebarDropResolution,
        browserManager: BrowserManager,
        windowState: BrowserWindowState?,
        dragState: SidebarDragState
    ) -> Bool {
        guard resolution.slot != .empty else { return false }

        if let draggedItem = draggedItem(from: pasteboard) {
            guard let scope = validatedScope(
                for: draggedItem,
                pasteboard: pasteboard,
                dragState: dragState,
                windowState: windowState
            ),
                  let payload = browserManager.tabManager.resolveSidebarDragPayload(for: draggedItem) else {
                return false
            }

            let operationIndex = resolvedOperationIndex(
                for: resolution,
                payload: payload,
                scope: scope,
                browserManager: browserManager
            )

            let operation = DragOperation(
                payload: payload,
                scope: scope,
                fromContainer: scope.sourceContainer,
                toContainer: resolution.slot.asDragContainer,
                toIndex: operationIndex
            )

            return browserManager.tabManager.performSidebarDragOperation(operation)
        }

        guard let droppedURL = pasteboard.sumiDroppedURL,
              let windowState else {
            return false
        }

        return browserManager.openDroppedURL(
            droppedURL,
            in: windowState,
            at: resolution.slot
        )
    }

    @MainActor
    private static func resolvedOperationIndex(
        for resolution: SidebarDropResolution,
        payload: DragOperation.Payload,
        scope: SidebarDragScope,
        browserManager: BrowserManager
    ) -> Int {
        let visualIndex = resolution.slot.visualIndex
        guard scope.sourceContainer == resolution.slot.asDragContainer else {
            return visualIndex
        }

        let sourceIndex = sourceIndex(
            for: payload,
            scope: scope,
            browserManager: browserManager
        )
        let projectedVisualIndex = clampedProjectedVisualIndex(
            visualIndex,
            sourceIndex: sourceIndex,
            scope: scope,
            browserManager: browserManager
        )
        return SidebarDropProjection.modelInsertionIndex(
            fromProjectedIndex: projectedVisualIndex,
            sourceIndex: sourceIndex
        )
    }

    @MainActor
    private static func clampedProjectedVisualIndex(
        _ visualIndex: Int,
        sourceIndex: Int?,
        scope: SidebarDragScope,
        browserManager: BrowserManager
    ) -> Int {
        guard sourceIndex != nil,
              let itemCount = sourceContainerItemCount(
                for: scope,
                browserManager: browserManager
              ) else {
            return visualIndex
        }

        return max(0, min(visualIndex, max(itemCount - 1, 0)))
    }

    @MainActor
    private static func sourceContainerItemCount(
        for scope: SidebarDragScope,
        browserManager: BrowserManager
    ) -> Int? {
        let tabManager = browserManager.tabManager

        switch scope.sourceContainer {
        case .essentials:
            return tabManager.essentialPins(for: scope.profileId).count

        case .spacePinned(let spaceId):
            return tabManager.topLevelSpacePinnedItems(for: spaceId).count

        case .spaceRegular(let spaceId):
            return tabManager.tabsBySpace[spaceId]?.count

        case .folder(let folderId):
            guard let spaceId = tabManager.folderSpaceId(for: folderId) else {
                return nil
            }
            return tabManager.folderPinnedPins(for: folderId, in: spaceId).count

        case .none:
            return nil
        }
    }

    @MainActor
    private static func sourceIndex(
        for payload: DragOperation.Payload,
        scope: SidebarDragScope,
        browserManager: BrowserManager
    ) -> Int? {
        let tabManager = browserManager.tabManager
        let sourceItemId = scope.sourceItemId

        switch scope.sourceContainer {
        case .essentials:
            return tabManager.essentialPins(for: scope.profileId)
                .firstIndex { $0.id == sourceItemId || payload.matchesShortcutPinId($0.id) }

        case .spacePinned(let spaceId):
            return tabManager.topLevelSpacePinnedItems(for: spaceId)
                .firstIndex { item in
                    switch item {
                    case .folder(let folder):
                        return folder.id == sourceItemId
                    case .shortcut(let pin):
                        return pin.id == sourceItemId || payload.matchesShortcutPinId(pin.id)
                    }
                }

        case .spaceRegular(let spaceId):
            return tabManager.tabsBySpace[spaceId]?.firstIndex { $0.id == sourceItemId }

        case .folder(let folderId):
            guard let spaceId = tabManager.folderSpaceId(for: folderId) else {
                return nil
            }
            return tabManager.folderPinnedPins(for: folderId, in: spaceId)
                .firstIndex { $0.id == sourceItemId || payload.matchesShortcutPinId($0.id) }

        case .none:
            return nil
        }
    }
}

@MainActor
private extension DragOperation.Payload {
    func matchesShortcutPinId(_ pinId: UUID) -> Bool {
        switch self {
        case .pin(let pin):
            return pin.id == pinId
        case .tab(let tab):
            return tab.shortcutPinId == pinId
        case .folder:
            return false
        }
    }
}
