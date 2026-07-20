import AppKit
import SumiDomain

private enum SplitDropCaptureViewPolicy {
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
    private let splitDrops: SplitDropService
    private let splitDropTargets: SplitDropTargetService
    private let splitPreviews: SplitPreviewSession
    private let sidebarDragState: SidebarDragState
    private weak var windowState: BrowserWindowState?
    private let resolveDragTab: (SumiDragItem) -> Tab?
    private var currentTarget: SplitDropTarget?
    private var isDragActive = false

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    init(
        frame frameRect: NSRect,
        splitDrops: SplitDropService,
        splitDropTargets: SplitDropTargetService,
        splitPreviews: SplitPreviewSession,
        sidebarDragState: SidebarDragState,
        windowState: BrowserWindowState,
        resolveDragTab: @escaping (SumiDragItem) -> Tab?
    ) {
        self.splitDrops = splitDrops
        self.splitDropTargets = splitDropTargets
        self.splitPreviews = splitPreviews
        self.sidebarDragState = sidebarDragState
        self.windowState = windowState
        self.resolveDragTab = resolveDragTab
        super.init(frame: frameRect)
        commonInit()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        SplitDropCaptureViewPolicy.shouldCaptureHit(
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
        guard let windowState,
              let item = SidebarDropCoordinator.draggedItem(from: sender.draggingPasteboard),
              let target = currentTarget ?? resolvedDropTarget(sender, item: item)
        else {
            finishDrag(resetSidebarDragState: true)
            return false
        }

        let didDrop: Bool
        if let memberID = item.splitMemberID {
            didDrop = splitDrops.drop(
                memberID,
                sourceTab: resolveDragTab(item),
                on: target,
                in: windowState
            )
        } else if let tab = resolveDragTab(item) {
            didDrop = splitDrops.drop(tab, on: target, in: windowState)
        } else {
            didDrop = false
        }
        finishDrag(resetSidebarDragState: true)
        return didDrop
    }

    private func updateDragState(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDragActive = true
        guard let item = SidebarDropCoordinator.draggedItem(from: sender.draggingPasteboard) else {
            cancelActiveDragPreview()
            return []
        }

        let operation = SplitDropCaptureViewPolicy.validatedMoveOperation(
            sourceMask: sender.draggingSourceOperationMask
        )
        guard operation != [] else {
            cancelActiveDragPreview()
            return []
        }

        guard let windowState else { return [] }
        let windowID = windowState.id

        updateSidebarDragPreviewLocation(sender)

        guard let target = resolvedDropTarget(sender, item: item) else {
            cancelActiveDragPreview()
            return []
        }

        currentTarget = target
        if splitPreviews.isActive(in: windowID) {
            splitPreviews.update(
                targetRect: target.targetRect,
                style: target.previewStyle,
                in: windowID
            )
        } else {
            splitPreviews.begin(
                targetRect: target.targetRect,
                style: target.previewStyle,
                in: windowID
            )
        }
        return operation
    }

    private func resolvedDropTarget(
        _ sender: NSDraggingInfo,
        item explicitItem: SumiDragItem? = nil
    ) -> SplitDropTarget? {
        let location = convert(sender.draggingLocation, from: nil)
        let item = explicitItem
            ?? SidebarDropCoordinator.draggedItem(from: sender.draggingPasteboard)
        guard let windowState else { return nil }
        return splitDropTargets.target(
            at: location,
            in: bounds,
            windowID: windowState.id,
            draggedMemberID: item?.splitMemberID,
            draggedLookupID: item?.splitMemberID == nil ? item?.tabId : nil
        )
    }

    private func updateSidebarDragPreviewLocation(_ sender: NSDraggingInfo) {
        guard sidebarDragState.isInternalDragSession,
              let dragLocation = SidebarDragLocationMapper.swiftUIGlobalPoint(
                fromWindowPoint: sender.draggingLocation,
                in: self
              )
        else { return }

        sidebarDragState.clearHoverState()
        sidebarDragState.updateDragLocation(
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
        guard let windowID = windowState?.id else { return hadLocalDragState }
        let hadPreview = splitPreviews.isActive(in: windowID)
        if hadPreview {
            splitPreviews.end(in: windowID)
        }
        return hadLocalDragState || hadPreview
    }

    private func finishDrag(resetSidebarDragState: Bool = false) {
        if endDrag() {
            NotificationCenter.default.post(name: .tabDragDidEnd, object: nil)
        }
        if resetSidebarDragState {
            sidebarDragState.resetInteractionState()
        }
    }

    func cancelActiveDragPreview() {
        _ = endDrag()
    }

    @objc private func handleTabDragDidEnd(_: Notification) {
        cancelActiveDragPreview()
    }
}
