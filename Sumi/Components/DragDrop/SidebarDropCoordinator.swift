import AppKit
import SwiftUI

enum SidebarDropCoordinator {
    static func draggedItem(from pasteboard: NSPasteboard) -> SumiDragItem? {
        SidebarDragPasteboardPayload.fromPasteboard(pasteboard)?.item
    }

    @MainActor
    static func validatedScope(
        for item: SumiDragItem,
        pasteboard: NSPasteboard,
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
        windowState: BrowserWindowState?
    ) -> Bool {
        guard resolution.slot != .empty else { return false }

        if let draggedItem = draggedItem(from: pasteboard) {
            guard let scope = validatedScope(
                for: draggedItem,
                pasteboard: pasteboard,
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
            return tabManager.topLevelSpacePinnedVisualItems(for: spaceId).count

        case .spaceRegular(let spaceId):
            return tabManager.tabsBySpace[spaceId]?.count

        case .folder(let folderId):
            guard let spaceId = tabManager.folderSpaceId(for: folderId) else {
                return nil
            }
            return tabManager.folderChildVisualItems(for: folderId, in: spaceId).count

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
            return tabManager.topLevelSpacePinnedVisualItems(for: spaceId)
                .firstIndex { item in
                    switch item {
                    case .folder(let folderId):
                        return folderId == sourceItemId
                    case .shortcut(let pinId):
                        return pinId == sourceItemId || payload.matchesShortcutPinId(pinId)
                    case .splitGroup(let groupId):
                        return groupId == sourceItemId || payload.matchesSplitGroupId(groupId)
                    }
                }

        case .spaceRegular(let spaceId):
            return tabManager.tabsBySpace[spaceId]?.firstIndex { $0.id == sourceItemId }

        case .folder(let folderId):
            guard let spaceId = tabManager.folderSpaceId(for: folderId) else {
                return nil
            }
            return tabManager.folderChildVisualItems(for: folderId, in: spaceId)
                .firstIndex { item in
                    switch item {
                    case .folder(let childFolderId):
                        return childFolderId == sourceItemId || payload.matchesFolderId(childFolderId)
                    case .shortcut(let pinId):
                        return pinId == sourceItemId || payload.matchesShortcutPinId(pinId)
                    case .splitGroup(let groupId):
                        return groupId == sourceItemId || payload.matchesSplitGroupId(groupId)
                    }
                }

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
        case .folder,
             .splitGroup:
            return false
        }
    }

    func matchesSplitGroupId(_ groupId: UUID) -> Bool {
        guard case .splitGroup(let group) = self else { return false }
        return group.id == groupId
    }

    func matchesFolderId(_ folderId: UUID) -> Bool {
        guard case .folder(let folder) = self else { return false }
        return folder.id == folderId
    }
}
