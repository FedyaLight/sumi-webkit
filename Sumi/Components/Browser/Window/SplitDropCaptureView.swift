import AppKit
import WebKit

enum SplitDropCaptureHitPolicy {
    static let cardWidth: CGFloat = 237
    static let cardHeight: CGFloat = 394
    static let cardPadding: CGFloat = 20

    static func side(at location: CGPoint, in bounds: CGRect) -> SplitViewManager.Side? {
        let cardTop = bounds.minY + ((bounds.height - cardHeight) / 2)
        let cardBottom = cardTop + cardHeight

        let leftCardLeft = bounds.minX + cardPadding
        let leftCardRight = leftCardLeft + cardWidth

        let rightCardRight = bounds.maxX - cardPadding
        let rightCardLeft = rightCardRight - cardWidth

        if location.x >= leftCardLeft && location.x <= leftCardRight &&
            location.y >= cardTop && location.y <= cardBottom {
            return .left
        }

        if location.x >= rightCardLeft && location.x <= rightCardRight &&
            location.y >= cardTop && location.y <= cardBottom {
            return .right
        }

        return nil
    }

    static func shouldCaptureHit(
        at point: CGPoint,
        in bounds: CGRect,
        isDragActive: Bool
    ) -> Bool {
        isDragActive && side(at: point, in: bounds) != nil
    }
}

final class SplitDropCaptureView: NSView {
    weak var browserManager: BrowserManager?
    weak var splitManager: SplitViewManager?
    var windowId: UUID?
    private var isDragActive: Bool = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        registerForDraggedTypes([.sumiSidebarDragPayload])
    }

    override func hitTest(_ point: NSPoint) -> NSView? { 
        SplitDropCaptureHitPolicy.shouldCaptureHit(
            at: point,
            in: bounds,
            isDragActive: isDragActive
        ) ? self : nil
    }
    
    // Override acceptsFirstResponder to prevent this view from intercepting events
    override var acceptsFirstResponder: Bool { false }

    // MARK: - Dragging
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDragActive = true
        updatePreview(sender)
        updateDragLocation(sender)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDragActive = true
        updateDragLocation(sender)
        updatePreview(sender)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        endDrag()
        if let windowId {
            splitManager?.updateDragLocation(nil, for: windowId)
            splitManager?.endPreview(cancel: true, for: windowId)
        }
        // Signal UI to clear any drag-hiding state even on invalid drops
        NotificationCenter.default.post(name: .tabDragDidEnd, object: nil)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let bm = browserManager, let sm = splitManager, let windowId else {
            endDrag()
            return false
        }
        let pb = sender.draggingPasteboard
        guard let id = SidebarDropCoordinator.draggedItem(from: pb)?.tabId else {
            // Invalid payload; clear any lingering drag UI state
            endDrag()
            sm.updateDragLocation(nil, for: windowId)
            sm.endPreview(cancel: false, for: windowId)
            NotificationCenter.default.post(name: .tabDragDidEnd, object: nil)
            return false
        }
        guard let tab = bm.tabManager.resolveDragTab(for: id) else {
            endDrag()
            sm.updateDragLocation(nil, for: windowId)
            sm.endPreview(cancel: false, for: windowId)
            NotificationCenter.default.post(name: .tabDragDidEnd, object: nil)
            return false
        }
        
        let side = sideForDragInCard(sender)
        guard let dropSide = side else {
            endDrag()
            sm.updateDragLocation(nil, for: windowId)
            sm.endPreview(cancel: false, for: windowId)
            return false
        }
        
        sm.updateDragLocation(nil, for: windowId)
        sm.endPreview(cancel: false, for: windowId)
        
        // Redundant replace guard
        if sm.isSplit(for: windowId) {
            let leftId = sm.leftTabId(for: windowId)
            let rightId = sm.rightTabId(for: windowId)
            if (dropSide == .left && leftId == tab.id) || (dropSide == .right && rightId == tab.id) {
                endDrag()
                return true
            }
        }
        if let windowState = bm.windowRegistry?.windows[windowId] {
            sm.enterSplit(with: tab, placeOn: dropSide, in: windowState)
        }
        endDrag()
        return true
    }

    // MARK: - Helpers
    private func updatePreview(_ sender: NSDraggingInfo) {
        let side = sideForDragInCard(sender)
        guard let windowId, let sm = splitManager else { return }
        
        let currentState = sm.getSplitState(for: windowId)
        if currentState.isPreviewActive {
            sm.updatePreviewSide(side, for: windowId)
        } else {
            sm.beginPreview(side: side, for: windowId)
        }
    }
    
    private func updateDragLocation(_ sender: NSDraggingInfo) {
        let loc = convert(sender.draggingLocation, from: nil)
        if let windowId {
            splitManager?.updateDragLocation(loc, for: windowId)
        }
    }

    private func sideForDragInCard(_ sender: NSDraggingInfo) -> SplitViewManager.Side? {
        let loc = convert(sender.draggingLocation, from: nil)
        return SplitDropCaptureHitPolicy.side(at: loc, in: bounds)
    }

    private func endDrag() {
        isDragActive = false
    }
}
