import AppKit
import SwiftUI

/// DDG-style hover bridge for sidebar chrome.
///
/// DuckDuckGo macOS keeps ordinary hover on the local AppKit view via
/// `HoverTrackingArea`/`MouseOverView`; SwiftUI receives only the local boolean.
/// That avoids publishing hover through a window/sidebar-wide observable object.
struct SidebarDDGHoverBridge: NSViewRepresentable {
    @Binding var isHovered: Bool
    let isEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SidebarDDGHoverTrackingView {
        let view = SidebarDDGHoverTrackingView(frame: .zero)
        update(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: SidebarDDGHoverTrackingView, context: Context) {
        update(nsView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ nsView: SidebarDDGHoverTrackingView, coordinator: Coordinator) {
        coordinator.detach(from: nsView)
        nsView.onHoverChanged = nil
        nsView.setHoverTrackingEnabled(false)
    }

    private func update(_ view: SidebarDDGHoverTrackingView, coordinator: Coordinator) {
        coordinator.updateBinding($isHovered)
        coordinator.attach(view)
        coordinator.performViewUpdate {
            if view.isHoverTrackingEnabled != isEnabled {
                view.setHoverTrackingEnabled(isEnabled)
            }
        }
        coordinator.scheduleLifecycleReconcile(from: view)
    }

    @MainActor
    final class Coordinator {
        private var isHovered: Binding<Bool>?
        private weak var view: SidebarDDGHoverTrackingView?
        private weak var pendingLifecycleView: SidebarDDGHoverTrackingView?
        private var isUpdatingView = false
        private var isLifecycleReconcileScheduled = false

        func updateBinding(_ isHovered: Binding<Bool>) {
            self.isHovered = isHovered
        }

        func attach(_ view: SidebarDDGHoverTrackingView) {
            guard self.view !== view else { return }

            self.view = view
            view.onHoverChanged = { [weak self] hovering in
                self?.publishEventHover(hovering)
            }
        }

        func detach(from view: SidebarDDGHoverTrackingView) {
            guard self.view === view else { return }

            pendingLifecycleView = nil
            isLifecycleReconcileScheduled = false
            self.view = nil
            isHovered = nil
        }

        func performViewUpdate(_ update: () -> Void) {
            isUpdatingView = true
            defer { isUpdatingView = false }
            update()
        }

        func scheduleLifecycleReconcile(from view: SidebarDDGHoverTrackingView) {
            pendingLifecycleView = view
            guard !isLifecycleReconcileScheduled else { return }

            isLifecycleReconcileScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                self.isLifecycleReconcileScheduled = false
                guard let view = self.pendingLifecycleView, self.view === view else { return }

                let effectiveHover = view.currentEffectiveHover
                view.markReportedHover(effectiveHover)
                self.setBindingIfNeeded(effectiveHover)
            }
        }

        private func publishEventHover(_ hovering: Bool) {
            guard !isUpdatingView else {
                if let view {
                    scheduleLifecycleReconcile(from: view)
                }
                return
            }

            setBindingIfNeeded(hovering)
        }

        private func setBindingIfNeeded(_ hovering: Bool) {
            guard let isHovered, isHovered.wrappedValue != hovering else { return }
            isHovered.wrappedValue = hovering
        }
    }
}

final class SidebarDDGHoverTrackingView: NSView, Hoverable {
    var onHoverChanged: ((Bool) -> Void)?

    override var isOpaque: Bool {
        false
    }

    @objc dynamic var backgroundColor: NSColor?
    @objc dynamic var mouseOverColor: NSColor?
    @objc dynamic var mouseDownColor: NSColor?
    @objc dynamic var cornerRadius: CGFloat = 0
    @objc dynamic var backgroundInset: NSPoint = .zero
    @objc dynamic var mustAnimateOnMouseOver: Bool = false
    @objc dynamic var isMouseDown: Bool = false

    @objc dynamic var isMouseOver: Bool = false {
        didSet {
            if isMouseDown {
                isMouseDown = false
            }
        }
    }

    private var hoverTrackingEnabled = true
    private var lastReportedHover = false
    private var lastDeliveredHoverEventTimestamp = -Double.infinity

    var isHoverTrackingEnabled: Bool {
        hoverTrackingEnabled
    }

    var currentEffectiveHover: Bool {
        hoverTrackingEnabled && isMouseOver
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        clipsToBounds = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // Paintless hover sensor. Visual state belongs to the SwiftUI row/tile.
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func backgroundLayer(createIfNeeded: Bool) -> CALayer? {
        nil
    }

    func setHoverTrackingEnabled(_ enabled: Bool) {
        guard hoverTrackingEnabled != enabled else {
            if enabled {
                reconcileHoverForLifecycle()
            } else {
                clearMouseOverForLifecycle()
            }
            return
        }

        hoverTrackingEnabled = enabled
        if !enabled {
            clearMouseOverForLifecycle()
        }
        updateTrackingAreas()
    }

    func markReportedHover(_ hovering: Bool) {
        lastReportedHover = hovering
    }

    func reconcileHoverForLifecycle(mouseLocationInWindow: NSPoint? = nil) {
        let hovering = hoverTrackingEnabled && containsMouseLocation(mouseLocationInWindow)
        setMouseOver(hovering)
        reportAcceptedEventHoverIfNeeded()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        removeSidebarHoverTrackingAreas()

        guard hoverTrackingEnabled else {
            clearMouseOverForLifecycle()
            return
        }

        addTrackingArea(SidebarDDGHoverTrackingArea(owner: self))
        reconcileHoverForLifecycle()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTrackingAreas()
        reconcileHoverForLifecycle()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            clearMouseOverForLifecycle()
        }
    }

    override func layout() {
        super.layout()
        reconcileHoverForLifecycle()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        reconcileHoverForLifecycle()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        guard acceptHoverEvent(event) else { return }

        setMouseOver(true)
        reportAcceptedEventHoverIfNeeded()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard acceptHoverEvent(event) else { return }

        if !isMouseOver {
            setMouseOver(true)
        }
        reportAcceptedEventHoverIfNeeded()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        guard acceptHoverEvent(event) else { return }

        setMouseOver(false)
        reportAcceptedEventHoverIfNeeded()
    }

    private func acceptHoverEvent(_ event: NSEvent) -> Bool {
        guard event.timestamp >= lastDeliveredHoverEventTimestamp else {
            restoreMouseOverFromReportedHover()
            return false
        }

        lastDeliveredHoverEventTimestamp = event.timestamp
        return true
    }

    private func restoreMouseOverFromReportedHover() {
        setMouseOver(hoverTrackingEnabled && lastReportedHover)
    }

    private func setMouseOver(_ hovering: Bool) {
        if isMouseOver != hovering {
            isMouseOver = hovering
        }
    }

    private func clearMouseOverForLifecycle() {
        setMouseOver(false)
        lastReportedHover = false
    }

    private func reportAcceptedEventHoverIfNeeded() {
        let effectiveHover = currentEffectiveHover
        guard effectiveHover != lastReportedHover else { return }

        lastReportedHover = effectiveHover
        onHoverChanged?(effectiveHover)
    }

    private func removeSidebarHoverTrackingAreas() {
        for trackingArea in trackingAreas where trackingArea is SidebarDDGHoverTrackingArea {
            removeTrackingArea(trackingArea)
        }
    }

    private func containsMouseLocation(_ mouseLocationInWindow: NSPoint?) -> Bool {
        guard let window else { return false }
        let mouseLocation = mouseLocationInWindow ?? window.mouseLocationOutsideOfEventStream
        let localPoint = convert(mouseLocation, from: nil)
        return sumi_findVisibleRectClampedToBounds().contains(localPoint)
    }
}

private final class SidebarDDGHoverTrackingArea: NSTrackingArea {
    init(owner: SidebarDDGHoverTrackingView) {
        super.init(
            rect: .zero,
            options: [
                .mouseEnteredAndExited,
                .mouseMoved,
                .activeInActiveApp,
                .inVisibleRect,
            ],
            owner: owner,
            userInfo: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct SidebarDDGHoverModifier: ViewModifier {
    @Binding var isHovered: Bool
    let isEnabled: Bool

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sidebarPresentationContext) private var presentationContext
    @ObservedObject private var dragState = SidebarDragState.shared

    private var effectiveIsEnabled: Bool {
        isEnabled
            && presentationContext.allowsInteractiveWork
            && !dragState.isDragging
            && !windowState.sidebarInteractionState.freezesSidebarHoverState
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        content
            .overlay {
                SidebarDDGHoverBridge(
                    isHovered: $isHovered,
                    isEnabled: effectiveIsEnabled
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .onChange(of: effectiveIsEnabled) { _, enabled in
                if !enabled {
                    isHovered = false
                }
            }
            .onDisappear {
                isHovered = false
            }
    }
}

extension View {
    func sidebarDDGHover(
        _ isHovered: Binding<Bool>,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            SidebarDDGHoverModifier(
                isHovered: isHovered,
                isEnabled: isEnabled
            )
        )
    }
}

enum SidebarHoverVisualState: Equatable {
    case selected
    case hovered
    case idle
}

enum SidebarHoverChrome {
    static func visualState(isSelected: Bool, isHovered: Bool) -> SidebarHoverVisualState {
        if isSelected {
            return .selected
        }
        if isHovered {
            return .hovered
        }
        return .idle
    }

    static func displayHover(_ isHovered: Bool, freezesHoverState: Bool) -> Bool {
        isHovered && !freezesHoverState
    }

    static func showsTrailingAction(isHovered: Bool, isSelected: Bool) -> Bool {
        isHovered || isSelected
    }

    static func trailingFadePadding(showsTrailingAction: Bool) -> CGFloat {
        showsTrailingAction ? SidebarRowLayout.trailingActionFadePadding : 0
    }

}
