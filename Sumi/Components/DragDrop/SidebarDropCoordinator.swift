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
              payload.sourceItemId == item.stableID,
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
        dragOperations: any SidebarDragOperationExecuting,
        urlDropService: SidebarURLDropService,
        splitPairing: (any SidebarSplitPairingCommitting)? = nil,
        windowState: BrowserWindowState?
    ) -> Bool {
        guard resolution.slot != .empty else { return false }

        if let draggedItem = draggedItem(from: pasteboard) {
            guard let scope = validatedScope(
                for: draggedItem,
                pasteboard: pasteboard,
                windowState: windowState
            ),
                  let payload = dragOperations.resolveSidebarDragPayload(for: draggedItem) else {
                return false
            }

            if let target = resolution.splitPairingTarget {
                guard let windowState else { return false }
                return splitPairing?.commit(
                    payload,
                    to: target,
                    in: windowState
                ) ?? false
            }

            let intent = SidebarDragCommitIntent(
                payload: payload,
                scope: scope,
                fromContainer: scope.sourceContainer,
                toContainer: resolution.slot.asDragContainer,
                presentedVisualIndex: resolution.slot.visualIndex,
                presentedRegularBoundary: resolution.presentedRegularBoundary
            )

            return dragOperations.performSidebarDragCommit(intent)
        }

        guard let droppedURL = pasteboard.sumiDroppedURL,
              let windowState else {
            return false
        }

        return urlDropService.open(
            droppedURL,
            in: windowState,
            atPresentedSlot: resolution.slot
        )
    }
}
