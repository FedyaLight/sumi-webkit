import AppKit

final class SidebarResizeGrabberView: NSView {
    weak var windowState: BrowserWindowState?
    var onResize: ((_ width: CGFloat, _ windowState: BrowserWindowState, _ persist: Bool) -> Void)?
    var onEndResize: ((_ windowState: BrowserWindowState) -> Void)?
    var onPointerDown: (() -> Void)?

    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            isHidden = !isEnabled
            if !isEnabled {
                resetInteractionState()
            }
            updateTrackingAreas()
            updateIndicatorAppearance()
            syncCursorState()
        }
    }

    var sidebarPosition: SidebarPosition = .left {
        didSet {
            guard sidebarPosition != oldValue else { return }
            needsLayout = true
        }
    }

    var indicatorColor: NSColor = .labelColor {
        didSet {
            indicatorLayer.backgroundColor = indicatorColor.cgColor
        }
    }

    private let indicatorLayer = CALayer()
    private var interactionState = SidebarResizeGrabberInteractionState()
    private var trackingArea: NSTrackingArea?
    private var suppressionObserver: NSObjectProtocol?
    private var activationWorkItem: DispatchWorkItem?
    private var hoverFlashWorkItem: DispatchWorkItem?
    private var startingWidth: CGFloat = 0
    private var startingMouseX: CGFloat = 0
    private var lastAppliedWidth: CGFloat = 0

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        indicatorLayer.backgroundColor = indicatorColor.cgColor
        indicatorLayer.masksToBounds = true
        indicatorLayer.opacity = 0
        layer?.addSublayer(indicatorLayer)

        isHidden = true
        suppressionObserver = NotificationCenter.default.addObserver(
            forName: SidebarChromePointerArbitration.didChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncSuppressionState()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        if let suppressionObserver {
            NotificationCenter.default.removeObserver(suppressionObserver)
        }
        cancelActivation()
        cancelHoverFlash()
    }

    override func layout() {
        super.layout()
        let indicatorFrame = SidebarResizeGrabberLayout.indicatorFrame(
            in: bounds,
            sidebarPosition: sidebarPosition
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        indicatorLayer.frame = indicatorFrame
        indicatorLayer.cornerRadius = indicatorFrame.width / 2
        CATransaction.commit()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
            self.trackingArea = nil
        }

        guard isEnabled else { return }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        self.trackingArea = trackingArea
        addTrackingArea(trackingArea)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        guard !isHidden,
              isResizeEligible,
              SidebarResizeGrabberLayout.resizeZoneFrame(in: bounds, sidebarPosition: sidebarPosition).contains(localPoint)
        else {
            return nil
        }
        return self
    }

    override func mouseEntered(with event: NSEvent) {
        beginHoverFlash()
        updateHoverState(with: event)
        syncCursorState()
    }

    override func mouseMoved(with event: NSEvent) {
        updateHoverState(with: event)
        syncCursorState()
    }

    override func mouseExited(with event: NSEvent) {
        guard !interactionState.isResizing else { return }
        setHovering(false)
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard SidebarResizeGrabberLayout.resizeZoneFrame(in: bounds, sidebarPosition: sidebarPosition).contains(point),
              let windowState,
              interactionState.beginResize(
                canBeginResize: SidebarResizeGrabberLayout.canBeginResize(
                    isEnabled: isEnabled,
                    isArmed: interactionState.isArmed,
                    isResizeSuppressed: isResizeSuppressed,
                    isSidebarVisible: windowState.isSidebarVisible
                )
              )
        else {
            return
        }

        onPointerDown?()
        cancelHoverFlash()
        startingWidth = windowState.sidebarWidth
        startingMouseX = event.locationInWindow.x
        lastAppliedWidth = startingWidth
        syncResizeScrollSuppression()
        updateIndicatorAppearance()
    }

    override func mouseDragged(with event: NSEvent) {
        guard interactionState.isResizing, let windowState else { return }

        let mouseMovement = sidebarPosition.shellEdge.resizeDelta(
            startingMouseX: startingMouseX,
            currentMouseX: event.locationInWindow.x
        )
        let newWidth = startingWidth + mouseMovement
        let clampedWidth = BrowserWindowState.clampedSidebarWidth(newWidth)
            .rounded(.toNearestOrAwayFromZero)
        guard clampedWidth != lastAppliedWidth else { return }
        lastAppliedWidth = clampedWidth

        onResize?(clampedWidth, windowState, false)
    }

    override func mouseUp(with event: NSEvent) {
        guard interactionState.isResizing else { return }
        let finishedWindowState = windowState
        interactionState.endResize()
        lastAppliedWidth = 0
        syncResizeScrollSuppression()
        updateHoverState(with: event)
        updateIndicatorAppearance()

        let point = convert(event.locationInWindow, from: nil)
        if !SidebarResizeGrabberLayout.resizeZoneFrame(in: bounds, sidebarPosition: sidebarPosition).contains(point) {
            NSCursor.arrow.set()
        }

        if let finishedWindowState {
            onEndResize?(finishedWindowState)
        }
    }

    func configure(
        isEnabled: Bool,
        sidebarPosition: SidebarPosition,
        indicatorColor: NSColor,
        windowState: BrowserWindowState?,
        onResize: @escaping (_ width: CGFloat, _ windowState: BrowserWindowState, _ persist: Bool) -> Void,
        onEndResize: @escaping (_ windowState: BrowserWindowState) -> Void,
        onPointerDown: (() -> Void)?
    ) {
        self.sidebarPosition = sidebarPosition
        self.indicatorColor = indicatorColor
        self.windowState = windowState
        self.onResize = onResize
        self.onEndResize = onEndResize
        self.onPointerDown = onPointerDown
        self.isEnabled = isEnabled
        syncSuppressionState()
        needsLayout = true
    }

    func resetForReuse() {
        windowState = nil
        onResize = nil
        onEndResize = nil
        onPointerDown = nil
        isEnabled = false
        resetInteractionState()
    }

    private var isResizeSuppressed: Bool {
        SidebarChromePointerArbitration.isResizeSuppressed(in: window)
    }

    private var isResizeEligible: Bool {
        SidebarResizeGrabberLayout.shouldUseResizeCursor(
            isEnabled: isEnabled,
            isResizeSuppressed: isResizeSuppressed,
            isArmed: interactionState.isArmed,
            isResizing: interactionState.isResizing
        )
    }

    private func syncSuppressionState() {
        if isResizeSuppressed {
            resetInteractionState()
        } else {
            updateHoverStateFromCurrentMouseLocation()
        }
        syncCursorState()
    }

    private func setHovering(_ hovering: Bool) {
        let action = interactionState.setHovering(
            hovering,
            isEnabled: isEnabled,
            isResizeSuppressed: isResizeSuppressed
        )
        applyActivationAction(action)
        updateIndicatorAppearance()
    }

    private func updateHoverState(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        setHovering(SidebarResizeGrabberLayout.resizeZoneFrame(in: bounds, sidebarPosition: sidebarPosition).contains(point))
    }

    private func updateHoverStateFromCurrentMouseLocation() {
        guard let window else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setHovering(SidebarResizeGrabberLayout.resizeZoneFrame(in: bounds, sidebarPosition: sidebarPosition).contains(point))
    }

    private func applyActivationAction(_ action: SidebarResizeGrabberActivationAction) {
        switch action {
        case .none:
            break
        case .schedule:
            scheduleActivation()
        case .cancel:
            cancelActivation()
        }
    }

    private func scheduleActivation() {
        guard activationWorkItem == nil,
              !interactionState.isArmed,
              isEnabled,
              !isResizeSuppressed
        else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.completeActivationIfPossible()
            }
        }
        activationWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + SidebarResizeGrabberLayout.activationDelay,
            execute: workItem
        )
    }

    private func completeActivationIfPossible() {
        activationWorkItem = nil
        let didArm = interactionState.completeActivation(
            canBeginResize: windowState.map {
                SidebarResizeGrabberLayout.canBeginResize(
                    isEnabled: isEnabled,
                    isArmed: true,
                    isResizeSuppressed: isResizeSuppressed,
                    isSidebarVisible: $0.isSidebarVisible
                )
            } ?? false
        )
        if didArm {
            cancelHoverFlash()
        }
        updateIndicatorAppearance()
    }

    private func cancelActivation() {
        activationWorkItem?.cancel()
        activationWorkItem = nil
    }

    private func resetInteractionState() {
        cancelActivation()
        cancelHoverFlash()
        interactionState.reset()
        lastAppliedWidth = 0
        syncResizeScrollSuppression()
        updateIndicatorAppearance()
    }

    private func beginHoverFlash() {
        guard isEnabled, !isResizeSuppressed else { return }
        cancelHoverFlash()
        guard let generation = interactionState.beginHoverFlash() else {
            updateIndicatorAppearance()
            return
        }
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.fadeOutHoverFlash(generation: generation)
            }
        }
        hoverFlashWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + SidebarResizeGrabberLayout.hoverFlashVisibleDuration,
            execute: workItem
        )
        updateIndicatorAppearance()
    }

    private func fadeOutHoverFlash(generation: Int) {
        guard interactionState.finishHoverFlash(generation: generation) else {
            return
        }
        hoverFlashWorkItem = nil
        updateIndicatorAppearance()
    }

    private func cancelHoverFlash() {
        hoverFlashWorkItem?.cancel()
        hoverFlashWorkItem = nil
    }

    private func syncResizeScrollSuppression() {
        SidebarChromePointerArbitration.setResizeSuppressesScrollIndicator(
            interactionState.isResizing,
            owner: self,
            window: window
        )
    }

    private func updateIndicatorAppearance() {
        let targetOpacity: Float
        switch interactionState.visualState {
        case .hidden:
            targetOpacity = 0
        case .hoverFlash:
            targetOpacity = SidebarResizeGrabberLayout.inactiveOpacity
        case .persistent:
            targetOpacity = SidebarResizeGrabberLayout.activeOpacity
        }

        let shouldFadeOut = targetOpacity == 0 && indicatorLayer.opacity > 0
        CATransaction.begin()
        if shouldFadeOut {
            CATransaction.setAnimationDuration(SidebarResizeGrabberLayout.hoverFlashFadeOutDuration)
        } else {
            CATransaction.setDisableActions(true)
        }
        indicatorLayer.opacity = targetOpacity
        CATransaction.commit()
        syncCursorState()
    }

    private func syncCursorState() {
        guard let window else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)

        if isResizeEligible,
           SidebarResizeGrabberLayout.resizeZoneFrame(in: bounds, sidebarPosition: sidebarPosition).contains(point) {
            NSCursor.resizeLeftRight.set()
        } else if bounds.contains(point) {
            NSCursor.arrow.set()
        }
    }
}
