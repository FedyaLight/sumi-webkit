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
            if state.isInternalDragSession {
                state.activeDragItemId = item.tabId
            } else {
                state.beginExternalDragSession(itemId: item.tabId)
            }
        } else if !state.isInternalDragSession {
            state.beginExternalDragSession(itemId: nil)
        }
        updateDragSlot(sender: sender)
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDragSlot(sender: sender)
        return .move
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
            guard let payload = browserManager.tabManager.resolveSidebarDragPayload(for: draggedItem) else { return false }
            
            let sourceContainer = resolveSourceContainer(for: draggedItem)
            
            let operation = DragOperation(
                payload: payload,
                fromContainer: sourceContainer,
                toContainer: resolution.slot.asDragContainer,
                toIndex: resolution.slot.visualIndex,
                toSpaceId: resolution.targetSpaceId,
                toProfileId: resolution.targetProfileId
            )
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                browserManager.tabManager.performSidebarDragOperation(operation)
            }
            return true
        }

        // Add additional drag payload extraction for raw URLs dropped into sidebar here

        return false
    }

    private func updateDragSlot(sender: NSDraggingInfo) {
        let draggedItem = SumiDragItem.fromPasteboard(sender.draggingPasteboard)
        _ = resolveDropResolution(sender: sender, draggedItem: draggedItem)
    }

    @discardableResult
    private func resolveDropResolution(
        sender: NSDraggingInfo,
        draggedItem: SumiDragItem?
    ) -> SidebarDropResolution? {
        guard let swiftUILocation = resolvedSwiftUILocation(for: sender) else { return nil }
        let previewLocation = resolvedSwiftUIPreviewLocation(for: sender)
        let state = SidebarDragState.shared
        return SidebarDropResolver.updateState(
            location: swiftUILocation,
            previewLocation: previewLocation,
            state: state,
            draggedItem: draggedItem
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
    
    // Dynamic Resolution Helpers
    private func resolveSourceContainer(for item: SumiDragItem) -> TabDragManager.DragContainer {
        guard let tabManager = browserManager?.tabManager else { return .none }
        if item.kind == .folder {
            guard let folder = tabManager.folder(by: item.tabId) else { return .none }
            // Sumi folders in sidebar exist in spacePinned natively
            return .spacePinned(folder.spaceId)
        } else {
            if let pin = tabManager.shortcutPin(by: item.tabId) {
                if pin.role == .essential { return .essentials }
                if pin.role == .spacePinned {
                    if let folderId = pin.folderId { return .folder(folderId) }
                    if let sid = pin.spaceId { return .spacePinned(sid) }
                }
            }
            
            guard let tab = tabManager.resolveDragTab(for: item.tabId) else { return .none }
            
            if tab.isPinned {
                return .essentials
            }
            if tab.isSpacePinned, let sid = tab.spaceId {
                if let folderId = tab.folderId {
                    return .folder(folderId)
                } else {
                    return .spacePinned(sid)
                }
            }
            if let sid = tab.spaceId {
                return .spaceRegular(sid)
            }
        }
        return .none
    }
    
}
