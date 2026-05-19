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
        SidebarTabListDragAutoscrollRegistry.shared.autoscrollIfNeeded(
            sender: sender,
            in: self
        )
        return updateDragSlot(sender: sender)
            ? context.dragOperation
            : []
    }

    override func wantsPeriodicDraggingUpdates() -> Bool {
        true
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

enum SidebarTabListAutoscrollDirection: Equatable {
    case up
    case down
}

enum SidebarTabListAutoscrollPolicy {
    static let edgeBandHeight: CGFloat = 32
    static let minimumStep: CGFloat = 8
    static let maximumStep: CGFloat = 28

    static func direction(
        for location: CGPoint,
        in viewport: CGRect,
        edgeBandHeight: CGFloat = Self.edgeBandHeight
    ) -> SidebarTabListAutoscrollDirection? {
        guard viewport.contains(location), edgeBandHeight > 0 else { return nil }

        let topDistance = viewport.maxY - location.y
        let bottomDistance = location.y - viewport.minY
        let effectiveBandHeight = min(edgeBandHeight, viewport.height / 2)

        if topDistance <= effectiveBandHeight, topDistance < bottomDistance {
            return .up
        }
        if bottomDistance <= effectiveBandHeight, bottomDistance < topDistance {
            return .down
        }
        return nil
    }

    static func step(
        for location: CGPoint,
        in viewport: CGRect,
        direction: SidebarTabListAutoscrollDirection,
        edgeBandHeight: CGFloat = Self.edgeBandHeight
    ) -> CGFloat {
        let effectiveBandHeight = max(1, min(edgeBandHeight, viewport.height / 2))
        let distance: CGFloat
        switch direction {
        case .up:
            distance = max(0, viewport.maxY - location.y)
        case .down:
            distance = max(0, location.y - viewport.minY)
        }

        let proximity = max(0, min(1, 1 - (distance / effectiveBandHeight)))
        return minimumStep + ((maximumStep - minimumStep) * proximity)
    }
}

@MainActor
final class SidebarTabListDragAutoscrollRegistry {
    static let shared = SidebarTabListDragAutoscrollRegistry()

    private final class WeakScrollView {
        weak var scrollView: NSScrollView?

        init(_ scrollView: NSScrollView) {
            self.scrollView = scrollView
        }
    }

    private var scrollViewsByIdentifier: [ObjectIdentifier: WeakScrollView] = [:]

    func register(_ scrollView: NSScrollView) {
        cleanupReleasedScrollViews()
        scrollViewsByIdentifier[ObjectIdentifier(scrollView)] = WeakScrollView(scrollView)
    }

    func unregister(_ scrollView: NSScrollView) {
        scrollViewsByIdentifier[ObjectIdentifier(scrollView)] = nil
    }

    @discardableResult
    func autoscrollIfNeeded(
        sender: NSDraggingInfo,
        in destinationView: NSView
    ) -> Bool {
        cleanupReleasedScrollViews()

        let locationInWindow = sender.draggingLocation
        let candidates = scrollViewsByIdentifier.values
            .compactMap(\.scrollView)
            .filter { $0.window === destinationView.window }
            .compactMap { scrollView -> (scrollView: NSScrollView, viewport: CGRect, direction: SidebarTabListAutoscrollDirection)? in
                let viewport = scrollView.contentView.convert(scrollView.contentView.bounds, to: nil)
                guard let direction = SidebarTabListAutoscrollPolicy.direction(
                    for: locationInWindow,
                    in: viewport
                ) else {
                    return nil
                }
                return (scrollView, viewport, direction)
            }
            .sorted { lhs, rhs in
                let lhsArea = lhs.viewport.width * lhs.viewport.height
                let rhsArea = rhs.viewport.width * rhs.viewport.height
                return lhsArea < rhsArea
            }

        guard let candidate = candidates.first else { return false }
        return autoscroll(
            candidate.scrollView,
            locationInWindow: locationInWindow,
            viewport: candidate.viewport,
            direction: candidate.direction
        )
    }

    private func autoscroll(
        _ scrollView: NSScrollView,
        locationInWindow: CGPoint,
        viewport: CGRect,
        direction: SidebarTabListAutoscrollDirection
    ) -> Bool {
        let contentView = scrollView.contentView
        guard let documentView = scrollView.documentView else { return false }

        let step = SidebarTabListAutoscrollPolicy.step(
            for: locationInWindow,
            in: viewport,
            direction: direction
        )
        let visualDelta: CGFloat = {
            switch direction {
            case .up:
                return -step
            case .down:
                return step
            }
        }()
        let signedDelta = documentView.isFlipped ? visualDelta : -visualDelta
        let currentOrigin = contentView.bounds.origin
        let proposedOrigin = CGPoint(
            x: currentOrigin.x,
            y: currentOrigin.y + signedDelta
        )
        let constrainedOrigin = constrainedScrollOrigin(
            proposedOrigin,
            in: contentView
        )

        guard abs(constrainedOrigin.y - currentOrigin.y) > 0.5 else {
            return false
        }

        contentView.scroll(to: constrainedOrigin)
        scrollView.reflectScrolledClipView(contentView)
        scrollView.flashScrollers()
        SidebarDragState.shared.requestGeometryRefresh()
        return true
    }

    private func constrainedScrollOrigin(
        _ origin: CGPoint,
        in contentView: NSClipView
    ) -> CGPoint {
        let documentRect = contentView.documentRect
        let visibleSize = contentView.bounds.size
        let maxX = max(documentRect.minX, documentRect.maxX - visibleSize.width)
        let maxY = max(documentRect.minY, documentRect.maxY - visibleSize.height)

        return CGPoint(
            x: min(max(origin.x, documentRect.minX), maxX),
            y: min(max(origin.y, documentRect.minY), maxY)
        )
    }

    private func cleanupReleasedScrollViews() {
        scrollViewsByIdentifier = scrollViewsByIdentifier.filter { _, weakScrollView in
            weakScrollView.scrollView != nil
        }
    }
}
