import AppKit

enum SplitDropCaptureHitPolicy {
    enum Mode {
        case create
        case rearrange
    }

    static let edgeZoneFraction: CGFloat = 0.25

    static func sides(at location: CGPoint, in bounds: CGRect, mode: Mode) -> [SplitDropSide] {
        guard bounds.width > 0, bounds.height > 0 else { return [] }
        guard bounds.contains(location) else { return [] }
        let distanceLeft = location.x - bounds.minX
        let distanceRight = bounds.maxX - location.x
        let distanceBottom = location.y - bounds.minY
        let distanceTop = bounds.maxY - location.y
        let horizontalThreshold = bounds.width * edgeZoneFraction
        let verticalThreshold = bounds.height * edgeZoneFraction

        var matchingEdges: [(side: SplitDropSide, distance: CGFloat)] = []
        if distanceLeft <= horizontalThreshold { matchingEdges.append((.left, distanceLeft)) }
        if distanceRight <= horizontalThreshold { matchingEdges.append((.right, distanceRight)) }
        if distanceTop <= verticalThreshold { matchingEdges.append((.top, distanceTop)) }
        if distanceBottom <= verticalThreshold { matchingEdges.append((.bottom, distanceBottom)) }

        if matchingEdges.isEmpty, mode == .rearrange {
            return [.center]
        }

        return matchingEdges
            .sorted { $0.distance < $1.distance }
            .map(\.side)
    }

    static func side(at location: CGPoint, in bounds: CGRect, mode: Mode) -> SplitDropSide? {
        sides(at: location, in: bounds, mode: mode).first
    }

    static func shouldCaptureHit(
        at point: CGPoint,
        in bounds: CGRect
    ) -> Bool {
        bounds.contains(point)
    }

    static func validatedMoveOperation(sourceMask: NSDragOperation) -> NSDragOperation {
        sourceMask.contains(.move) ? .move : []
    }
}

final class SplitDropCaptureView: NSView {
    weak var browserManager: BrowserManager?
    weak var splitManager: SplitViewManager?
    var windowId: UUID?
    private var currentTarget: SplitDropTarget?
    private var isDragActive = false

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTabDragDidEnd),
            name: .tabDragDidEnd,
            object: nil
        )
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview == nil {
            cancelActiveDragPreview()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            cancelActiveDragPreview()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        SplitDropCaptureHitPolicy.shouldCaptureHit(
            at: point,
            in: bounds
        ) ? self : nil
    }

    override var acceptsFirstResponder: Bool { false }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDragState(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDragState(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        cancelActiveDragPreview()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        finishDrag(resetSidebarDragState: true)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let bm = browserManager,
              let sm = splitManager,
              let windowId,
              let windowState = bm.windowRegistry?.windows[windowId],
              let item = SidebarDropCoordinator.draggedItem(from: sender.draggingPasteboard),
              let tab = bm.tabManager.resolveDragTab(for: item.tabId),
              let target = currentTarget ?? resolvedDropTarget(sender)
        else {
            finishDrag(resetSidebarDragState: true)
            return false
        }

        let didDrop = sm.dropTab(tab, on: target, in: windowState)
        finishDrag(resetSidebarDragState: true)
        return didDrop
    }

    private func updateDragState(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDragActive = true
        guard let item = SidebarDropCoordinator.draggedItem(from: sender.draggingPasteboard) else {
            cancelActiveDragPreview()
            return []
        }

        let operation = SplitDropCaptureHitPolicy.validatedMoveOperation(
            sourceMask: sender.draggingSourceOperationMask
        )
        guard operation != [] else {
            cancelActiveDragPreview()
            return []
        }

        guard let windowId, let splitManager else { return [] }

        updateSidebarDragPreviewLocation(sender)

        guard let target = resolvedDropTarget(sender, draggedTabId: item.tabId) else {
            cancelActiveDragPreview()
            return []
        }

        currentTarget = target
        if splitManager.isPreviewActive(for: windowId) {
            splitManager.updatePreview(
                side: target.side,
                targetRect: target.targetRect,
                style: target.previewStyle,
                for: windowId
            )
        } else {
            splitManager.beginPreview(
                side: target.side,
                targetRect: target.targetRect,
                style: target.previewStyle,
                for: windowId
            )
        }
        return operation
    }

    private func resolvedDropTarget(_ sender: NSDraggingInfo, draggedTabId: UUID? = nil) -> SplitDropTarget? {
        let location = convert(sender.draggingLocation, from: nil)
        let resolvedDraggedTabId = draggedTabId
            ?? SidebarDropCoordinator.draggedItem(from: sender.draggingPasteboard)?.tabId
        guard let windowId, let splitManager else { return nil }
        return splitManager.dropTarget(
            at: location,
            in: bounds,
            for: windowId,
            draggedTabId: resolvedDraggedTabId
        )
    }

    private func updateSidebarDragPreviewLocation(_ sender: NSDraggingInfo) {
        let state = SidebarDragState.shared
        guard state.isInternalDragSession,
              let dragLocation = SidebarDragLocationMapper.swiftUIGlobalPoint(
                fromWindowPoint: sender.draggingLocation,
                in: self
              )
        else { return }

        state.clearHoverState()
        state.updateDragLocation(
            dragLocation,
            previewLocation: SidebarDragLocationMapper.swiftUIPreviewPoint(
                fromWindowPoint: sender.draggingLocation,
                in: self
            )
        )
    }

    @discardableResult
    private func endDrag() -> Bool {
        let hadLocalDragState = isDragActive || currentTarget != nil
        isDragActive = false
        currentTarget = nil
        guard let windowId, let splitManager else { return hadLocalDragState }
        let hadPreview = splitManager.isPreviewActive(for: windowId)
        splitManager.endPreview(for: windowId)
        return hadLocalDragState || hadPreview
    }

    private func finishDrag(resetSidebarDragState: Bool = false) {
        if endDrag() {
            NotificationCenter.default.post(name: .tabDragDidEnd, object: nil)
        }
        if resetSidebarDragState {
            SidebarDragState.shared.resetInteractionState()
        }
    }

    func cancelActiveDragPreview() {
        _ = endDrag()
    }

    @objc private func handleTabDragDidEnd(_ notification: Notification) {
        cancelActiveDragPreview()
    }
}
