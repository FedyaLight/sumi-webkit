import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SidebarGlobalDragOverlay: NSViewRepresentable {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) var windowState

    func makeNSView(context: Context) -> SidebarDragNSView {
        let view = SidebarDragNSView()
        view.browserManager = browserManager
        view.windowState = windowState
        return view
    }

    func updateNSView(_ nsView: SidebarDragNSView, context: Context) {
        nsView.browserManager = browserManager
        nsView.windowState = windowState
    }
}

class SidebarDragNSView: NSView {
    weak var browserManager: BrowserManager?
    var windowState: BrowserWindowState?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.string, .URL, .fileURL, NSPasteboard.PasteboardType.sumiTabItem])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil // Pass through all normal mouse events
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let state = SidebarDragState.shared
        if let item = SumiDragItem.fromPasteboard(sender.draggingPasteboard) {
            guard validatedScope(for: item) != nil else {
                state.clearHoverState()
                return []
            }
            if state.isInternalDragSession {
                state.activeDragItemId = item.tabId
            } else {
                state.beginExternalDragSession(itemId: item.tabId)
            }
        } else if !state.isInternalDragSession {
            state.beginExternalDragSession(itemId: nil)
        }
        return updateDragSlot(sender: sender) ? .move : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDragSlot(sender: sender) ? .move : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        let state = SidebarDragState.shared
        if state.isInternalDragSession {
            state.clearHoverState()
        } else {
            state.resetInteractionState()
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let state = SidebarDragState.shared
        let draggedItem = SumiDragItem.fromPasteboard(sender.draggingPasteboard)
        let resolution = resolveDropResolution(sender: sender, draggedItem: draggedItem)

        defer {
            state.resetInteractionState()
        }

        guard let resolution,
              resolution.slot != .empty,
              let browserManager = browserManager else { return false }
        
        // Sumi Drag Resolution
        if let draggedItem {
            guard let scope = validatedScope(for: draggedItem) else { return false }
            guard let payload = browserManager.tabManager.resolveSidebarDragPayload(for: draggedItem) else { return false }
            
            let operation = DragOperation(
                payload: payload,
                scope: scope,
                fromContainer: scope.sourceContainer,
                toContainer: resolution.slot.asDragContainer,
                toIndex: resolution.slot.visualIndex
            )
            
            var accepted = false
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                accepted = browserManager.tabManager.performSidebarDragOperation(operation)
            }
            return accepted
        }

        // Add additional drag payload extraction for raw URLs dropped into sidebar here

        return false
    }

    private func updateDragSlot(sender: NSDraggingInfo) -> Bool {
        let draggedItem = SumiDragItem.fromPasteboard(sender.draggingPasteboard)
        guard let resolution = resolveDropResolution(sender: sender, draggedItem: draggedItem) else {
            return false
        }
        return resolution.slot != .empty
    }

    @discardableResult
    private func resolveDropResolution(
        sender: NSDraggingInfo,
        draggedItem: SumiDragItem?
    ) -> SidebarDropResolution? {
        guard let swiftUILocation = resolvedSwiftUILocation(for: sender) else { return nil }
        let previewLocation = resolvedSwiftUIPreviewLocation(for: sender)
        let state = SidebarDragState.shared
        let scope = draggedItem.flatMap { validatedScope(for: $0) }
        if draggedItem != nil, scope == nil {
            state.clearHoverState()
            return nil
        }
        return SidebarDropResolver.updateState(
            location: swiftUILocation,
            previewLocation: previewLocation,
            state: state,
            draggedItem: draggedItem,
            scope: scope
        )
    }

    private func resolvedSwiftUILocation(for sender: NSDraggingInfo) -> CGPoint? {
        SidebarDragLocationMapper.swiftUIGlobalPoint(
            fromWindowPoint: sender.draggingLocation,
            in: self
        )
    }

    private func resolvedSwiftUIPreviewLocation(for sender: NSDraggingInfo) -> CGPoint? {
        SidebarDragLocationMapper.swiftUIPreviewPoint(
            fromWindowPoint: sender.draggingLocation,
            in: self
        )
    }

    private func validatedScope(for item: SumiDragItem) -> SidebarDragScope? {
        let state = SidebarDragState.shared
        guard let scope = state.activeDragScope,
              scope.sourceItemId == item.tabId,
              scope.sourceItemKind == item.kind,
              scope.matches(windowId: windowState?.id),
              scope.spaceId == windowState?.currentSpaceId,
              scope.matches(profileId: windowState?.currentProfileId)
        else {
            return nil
        }
        return scope
    }
}
