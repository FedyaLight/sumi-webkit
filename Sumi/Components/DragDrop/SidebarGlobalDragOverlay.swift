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
    private struct DragContext {
        let pasteboardChangeCount: Int
        let draggedItem: SumiDragItem?
        let scope: SidebarDragScope?
        let hasDroppedURL: Bool

        var dragOperation: NSDragOperation {
            draggedItem == nil ? .copy : .move
        }

        var canResolveDrop: Bool {
            draggedItem != nil || hasDroppedURL
        }
    }

    weak var browserManager: BrowserManager?
    var windowState: BrowserWindowState?
    private var cachedDragContext: DragContext?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([
            .string,
            .URL,
            .fileURL,
            NSPasteboard.PasteboardType.sumiSidebarDragPayload
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil // Pass through all normal mouse events
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let state = SidebarDragState.shared
        cachedDragContext = nil
        let context = dragContext(for: sender)

        if let item = context.draggedItem {
            guard context.scope != nil else {
                state.clearHoverState()
                return []
            }
            if state.isInternalDragSession {
                state.activeDragItemId = item.tabId
            } else {
                state.beginExternalDragSession(itemId: item.tabId)
            }
        } else if !state.isInternalDragSession {
            guard context.hasDroppedURL else {
                state.resetInteractionState()
                return []
            }
            state.beginExternalDragSession(itemId: nil)
        }
        return updateDragSlot(sender: sender)
            ? context.dragOperation
            : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let context = dragContext(for: sender)
        guard context.canResolveDrop else {
            return []
        }
        return updateDragSlot(sender: sender)
            ? context.dragOperation
            : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        let state = SidebarDragState.shared
        if state.isInternalDragSession {
            state.clearHoverState()
        } else {
            state.resetInteractionState()
        }
        cachedDragContext = nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let state = SidebarDragState.shared
        let resolution = resolveDropResolution(sender: sender)

        defer {
            runWithoutDropAnimations {
                state.resetInteractionState()
            }
            cachedDragContext = nil
        }

        guard let resolution,
              resolution.slot != .empty,
              let browserManager = browserManager else { return false }
        state.beginDropCommit()
        return runWithoutDropAnimations {
            SidebarDropCoordinator.performDrop(
                pasteboard: sender.draggingPasteboard,
                resolution: resolution,
                browserManager: browserManager,
                windowState: windowState,
                dragState: state
            )
        }
    }

    private func runWithoutDropAnimations<T>(_ operation: () -> T) -> T {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        return withTransaction(transaction, operation)
    }

    private func updateDragSlot(sender: NSDraggingInfo) -> Bool {
        guard let resolution = resolveDropResolution(sender: sender) else {
            return false
        }
        return resolution.slot != .empty
    }

    @discardableResult
    private func resolveDropResolution(
        sender: NSDraggingInfo
    ) -> SidebarDropResolution? {
        guard let swiftUILocation = resolvedSwiftUILocation(for: sender) else { return nil }
        let previewLocation = resolvedSwiftUIPreviewLocation(for: sender)
        let context = dragContext(for: sender)
        return SidebarDropCoordinator.resolveDropResolution(
            pasteboard: sender.draggingPasteboard,
            swiftUILocation: swiftUILocation,
            previewLocation: previewLocation,
            dragState: SidebarDragState.shared,
            windowState: windowState,
            draggedItem: context.draggedItem,
            scope: context.scope
        )
    }

    private func dragContext(for sender: NSDraggingInfo) -> DragContext {
        let pasteboard = sender.draggingPasteboard
        if let cachedDragContext,
           cachedDragContext.pasteboardChangeCount == pasteboard.changeCount {
            return cachedDragContext
        }

        let item = SidebarDropCoordinator.draggedItem(from: pasteboard)
        let scope = item.flatMap {
            SidebarDropCoordinator.validatedScope(
                for: $0,
                pasteboard: pasteboard,
                dragState: SidebarDragState.shared,
                windowState: windowState
            )
        }
        let context = DragContext(
            pasteboardChangeCount: pasteboard.changeCount,
            draggedItem: item,
            scope: scope,
            hasDroppedURL: item == nil && pasteboard.sumiDroppedURL != nil
        )
        cachedDragContext = context
        return context
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

}
