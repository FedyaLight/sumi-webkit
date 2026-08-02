import AppKit
import SwiftUI

/// A pointer transition is immediate. A lifecycle transition is coalesced
/// because SwiftUI can rebuild many native regions in one layout pass.
enum SidebarHoverChangeSource: Equatable {
    case pointer
    case lifecycle
}

fileprivate struct SidebarHoverSignal {
    let source: SidebarHoverChangeSource
    let timestamp: TimeInterval?
    let mouseLocationInWindow: NSPoint?
}

/// Paintless native sensor. It never owns hover state: enter/exit events only
/// tell the window-local session when to resolve state from current geometry.
@MainActor
final class SidebarHoverTrackingView: NSView {
    fileprivate var onHoverSignal: ((SidebarHoverSignal) -> Void)?
    private(set) var isHoverTrackingEnabled = true

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        clipsToBounds = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // SwiftUI owns every pixel; this view owns only an NSTrackingArea.
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func setHoverTrackingEnabled(_ enabled: Bool) {
        guard isHoverTrackingEnabled != enabled else {
            requestLifecycleReconcile()
            return
        }

        isHoverTrackingEnabled = enabled
        updateTrackingAreas()
        requestLifecycleReconcile()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        removeSidebarHoverTrackingAreas()
        if isHoverTrackingEnabled {
            addTrackingArea(SidebarHoverTrackingArea(owner: self))
        }
        requestLifecycleReconcile()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTrackingAreas()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            requestLifecycleReconcile()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        reportPointerEvent(event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        reportPointerEvent(event)
    }

    fileprivate func containsMouse(_ mouseLocationInWindow: NSPoint) -> Bool {
        guard isHoverTrackingEnabled,
              window != nil,
              superview != nil,
              !isHiddenOrHasHiddenAncestor
        else { return false }

        let localPoint = convert(mouseLocationInWindow, from: nil)
        return sumi_chromeVisibleRectClampedToBounds().contains(localPoint)
    }

    private func reportPointerEvent(_ event: NSEvent) {
        guard isHoverTrackingEnabled else { return }
        onHoverSignal?(SidebarHoverSignal(
            source: .pointer,
            timestamp: event.timestamp,
            mouseLocationInWindow: event.locationInWindow
        ))
    }

    private func requestLifecycleReconcile() {
        onHoverSignal?(SidebarHoverSignal(
            source: .lifecycle,
            timestamp: nil,
            mouseLocationInWindow: nil
        ))
    }

    private func removeSidebarHoverTrackingAreas() {
        for trackingArea in trackingAreas where trackingArea is SidebarHoverTrackingArea {
            removeTrackingArea(trackingArea)
        }
    }
}

/// Window-local source of truth for native hover.
///
/// The interface deliberately accepts only registrations, pointer signals,
/// and suspension. Event pairing, stale-event rejection, lifecycle coalescing,
/// application/window teardown, and geometry reconciliation stay inside.
@MainActor
final class SidebarHoverSession: NSObject {
    private struct WeakRegistration {
        weak var value: SidebarHoverRegistration?
    }

    private var registrations: [ObjectIdentifier: WeakRegistration] = [:]
    // AppKit can send viewWillMove(toWindow: nil) while an NSPopoverWindow is
    // already deallocating. Queue the stable registration, never that window;
    // the next main-queue pass resolves whichever window the view belongs to then.
    private var pendingLifecycleRegistrations: [ObjectIdentifier: WeakRegistration] = [:]
    private var lastPointerTimestampByWindow: [ObjectIdentifier: TimeInterval] = [:]
    private var lifecycleReconcileScheduled = false
    private var isSuspended = false
    private var isScrollSuppressed = false
    private var isApplicationActive = true
    private var observesLifecycle = false
    private let pointerScreenLocation: () -> NSPoint
    private var lastPointerScreenLocation: NSPoint

    init(pointerScreenLocation: @escaping () -> NSPoint = { NSEvent.mouseLocation }) {
        self.pointerScreenLocation = pointerScreenLocation
        lastPointerScreenLocation = pointerScreenLocation()
        super.init()
    }

    func register(_ registration: SidebarHoverRegistration) {
        registrations[ObjectIdentifier(registration)] = WeakRegistration(value: registration)
        installLifecycleObserversIfNeeded()
        requestLifecycleReconcile(for: registration)
    }

    func unregister(_ registration: SidebarHoverRegistration) {
        registrations.removeValue(forKey: ObjectIdentifier(registration))
        registration.publish(false, source: .lifecycle)
        pruneRegistrations()
        removeLifecycleObserversIfUnused()
    }

    fileprivate func receive(_ signal: SidebarHoverSignal, from registration: SidebarHoverRegistration) {
        guard registrations[ObjectIdentifier(registration)]?.value === registration else { return }

        switch signal.source {
        case .pointer:
            guard let window = registration.view?.window,
                  let mouseLocation = signal.mouseLocationInWindow,
                  acceptPointerTimestamp(signal.timestamp, in: window)
            else { return }
            guard !isHoverResolutionSuspended, isApplicationActive else { return }

            // A BrowserWindowState can briefly own both docked and overlay
            // hosts. One physical pointer event belongs to exactly one window.
            clearRegistrations(exceptIn: window)
            reconcile(
                window: window,
                mouseLocationInWindow: mouseLocation,
                source: pointerChangeSource()
            )
        case .lifecycle:
            requestLifecycleReconcile(for: registration)
        }
    }

    func setSuspended(_ suspended: Bool) {
        guard isSuspended != suspended else { return }
        isSuspended = suspended
        if suspended {
            pendingLifecycleRegistrations.removeAll()
            clearAll()
        } else {
            requestLifecycleReconcileForAllWindows()
        }
    }

    /// Scroll suppression is independent from drag/transient suspension. A
    /// scroll can finish while another interaction is still holding hover
    /// suspended, so the two reasons must not overwrite each other.
    func setScrollSuppressed(_ suppressed: Bool) {
        guard isScrollSuppressed != suppressed else { return }
        isScrollSuppressed = suppressed
        if suppressed {
            pendingLifecycleRegistrations.removeAll()
            clearAll()
        } else {
            requestLifecycleReconcileForAllWindows()
        }
    }

    /// Internal seam used by deterministic tests and by the coalesced lifecycle pass.
    func reconcile(
        window: NSWindow,
        mouseLocationInWindow: NSPoint,
        source: SidebarHoverChangeSource = .lifecycle
    ) {
        pruneRegistrations()
        guard !isHoverResolutionSuspended, isApplicationActive else {
            clearRegistrations(in: window)
            return
        }

        for registration in liveRegistrations where registration.view?.window === window {
            let hovering = registration.isEnabled
                && registration.view?.containsMouse(mouseLocationInWindow) == true
            registration.publish(hovering, source: source)
        }
    }

    private func requestLifecycleReconcile(for registration: SidebarHoverRegistration) {
        pendingLifecycleRegistrations[ObjectIdentifier(registration)] =
            WeakRegistration(value: registration)
        scheduleLifecycleReconcileIfNeeded()
    }

    private func requestLifecycleReconcile(in window: NSWindow) {
        for registration in liveRegistrations where registration.view?.window === window {
            pendingLifecycleRegistrations[ObjectIdentifier(registration)] =
                WeakRegistration(value: registration)
        }
        scheduleLifecycleReconcileIfNeeded()
    }

    private func scheduleLifecycleReconcileIfNeeded() {
        guard !lifecycleReconcileScheduled else { return }
        lifecycleReconcileScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lifecycleReconcileScheduled = false
            let pendingRegistrations = self.pendingLifecycleRegistrations.values.compactMap(\.value)
            self.pendingLifecycleRegistrations.removeAll()
            guard !self.isHoverResolutionSuspended, self.isApplicationActive else {
                self.clearAll()
                return
            }

            var windows: [ObjectIdentifier: NSWindow] = [:]
            for registration in pendingRegistrations {
                guard self.registrations[ObjectIdentifier(registration)]?.value === registration else {
                    continue
                }
                guard let window = registration.view?.window else {
                    registration.publish(false, source: .lifecycle)
                    continue
                }
                windows[ObjectIdentifier(window)] = window
            }

            for window in windows.values {
                self.reconcile(
                    window: window,
                    mouseLocationInWindow: window.mouseLocationOutsideOfEventStream,
                    source: .lifecycle
                )
            }
        }
    }

    private func requestLifecycleReconcileForAllWindows() {
        for registration in liveRegistrations {
            requestLifecycleReconcile(for: registration)
        }
    }

    private func acceptPointerTimestamp(_ timestamp: TimeInterval?, in window: NSWindow) -> Bool {
        guard let timestamp else { return true }
        let windowID = ObjectIdentifier(window)
        let previous = lastPointerTimestampByWindow[windowID] ?? -.infinity
        guard timestamp >= previous else { return false }
        lastPointerTimestampByWindow[windowID] = timestamp
        return true
    }

    /// AppKit can synthesize enter/exit callbacks when a tracking area is
    /// installed or a window becomes visible. Those callbacks describe the
    /// parked pointer, not user motion, so consumers such as the folder-preview
    /// timer must see them as lifecycle reconciliation.
    private func pointerChangeSource() -> SidebarHoverChangeSource {
        let currentLocation = pointerScreenLocation()
        defer { lastPointerScreenLocation = currentLocation }
        return currentLocation == lastPointerScreenLocation ? .lifecycle : .pointer
    }

    private var liveRegistrations: [SidebarHoverRegistration] {
        registrations.values.compactMap(\.value)
    }

    private var isHoverResolutionSuspended: Bool {
        isSuspended || isScrollSuppressed
    }

    private func clearAll() {
        for registration in liveRegistrations {
            registration.publish(false, source: .lifecycle)
        }
    }

    private func clearRegistrations(in window: NSWindow) {
        for registration in liveRegistrations where registration.view?.window === window {
            registration.publish(false, source: .lifecycle)
        }
    }

    private func clearRegistrations(exceptIn window: NSWindow) {
        for registration in liveRegistrations where registration.view?.window !== window {
            registration.publish(false, source: .lifecycle)
        }
    }

    private func pruneRegistrations() {
        registrations = registrations.filter { $0.value.value != nil }
    }

    private func installLifecycleObserversIfNeeded() {
        guard !observesLifecycle else { return }
        observesLifecycle = true
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(applicationDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(windowDidBecomeUnavailable(_:)),
            name: NSWindow.didMiniaturizeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(windowDidBecomeUnavailable(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(windowDidBecomeAvailable(_:)),
            name: NSWindow.didDeminiaturizeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(windowOcclusionDidChange(_:)),
            name: NSWindow.didChangeOcclusionStateNotification,
            object: nil
        )
    }

    private func removeLifecycleObserversIfUnused() {
        guard registrations.isEmpty, observesLifecycle else { return }
        NotificationCenter.default.removeObserver(self)
        observesLifecycle = false
        pendingLifecycleRegistrations.removeAll()
        lastPointerTimestampByWindow.removeAll()
    }

    @objc private func applicationDidResignActive() {
        isApplicationActive = false
        pendingLifecycleRegistrations.removeAll()
        clearAll()
    }

    @objc private func applicationDidBecomeActive() {
        isApplicationActive = true
        requestLifecycleReconcileForAllWindows()
    }

    @objc private func windowDidBecomeUnavailable(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        clearRegistrations(in: window)
        pendingLifecycleRegistrations = pendingLifecycleRegistrations.filter {
            $0.value.value?.view?.window !== window
        }
        lastPointerTimestampByWindow.removeValue(forKey: ObjectIdentifier(window))
    }

    @objc private func windowDidBecomeAvailable(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        requestLifecycleReconcile(in: window)
    }

    @objc private func windowOcclusionDidChange(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window.occlusionState.contains(.visible) {
            requestLifecycleReconcile(in: window)
        } else {
            clearRegistrations(in: window)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

/// One registered hover region. The session owns truth; this adapter only
/// connects a native view to a narrowly invalidating sink.
@MainActor
final class SidebarHoverRegistration {
    fileprivate weak var view: SidebarHoverTrackingView?
    fileprivate private(set) var isEnabled = false

    private weak var session: SidebarHoverSession?
    private var onHoverChanged: (Bool, SidebarHoverChangeSource) -> Void = { _, _ in }
    private var publishedHover = false

    func update(
        view: SidebarHoverTrackingView,
        session: SidebarHoverSession,
        isEnabled: Bool,
        onHoverChanged: @escaping (Bool, SidebarHoverChangeSource) -> Void
    ) {
        self.onHoverChanged = onHoverChanged

        if self.view !== view {
            self.view?.onHoverSignal = nil
            self.view = view
            view.onHoverSignal = { [weak self] signal in
                guard let self else { return }
                self.session?.receive(signal, from: self)
            }
        }

        if self.session !== session {
            self.session?.unregister(self)
            self.session = session
            session.register(self)
        }

        let didChangeEnabled = self.isEnabled != isEnabled
        self.isEnabled = isEnabled
        if view.isHoverTrackingEnabled != isEnabled {
            view.setHoverTrackingEnabled(isEnabled)
        } else if didChangeEnabled {
            session.receive(
                SidebarHoverSignal(source: .lifecycle, timestamp: nil, mouseLocationInWindow: nil),
                from: self
            )
        }
        if !isEnabled {
            publish(false, source: .lifecycle)
        }
    }

    func disconnect() {
        session?.unregister(self)
        session = nil
        view?.onHoverSignal = nil
        view?.setHoverTrackingEnabled(false)
        view = nil
        publish(false, source: .lifecycle)
        onHoverChanged = { _, _ in }
    }

    fileprivate func publish(_ hovering: Bool, source: SidebarHoverChangeSource) {
        guard publishedHover != hovering else { return }
        publishedHover = hovering
        onHoverChanged(hovering, source)
    }
}

@MainActor
final class SidebarHoverBindingCoordinator {
    let registration = SidebarHoverRegistration()
    private var isHovered: Binding<Bool>?

    func update(
        view: SidebarHoverTrackingView,
        session: SidebarHoverSession,
        isHovered: Binding<Bool>,
        isEnabled: Bool
    ) {
        self.isHovered = isHovered
        registration.update(
            view: view,
            session: session,
            isEnabled: isEnabled
        ) { [weak self] hovering, _ in
            self?.setBindingIfNeeded(hovering)
        }
    }

    func detach() {
        registration.disconnect()
        setBindingIfNeeded(false)
        isHovered = nil
    }

    private func setBindingIfNeeded(_ hovering: Bool) {
        guard let isHovered, isHovered.wrappedValue != hovering else { return }
        isHovered.wrappedValue = hovering
    }
}

@MainActor
final class SidebarHoverCallbackCoordinator {
    let registration = SidebarHoverRegistration()
    private var onChange: ((Bool) -> Void)?

    func update(
        view: SidebarHoverTrackingView,
        session: SidebarHoverSession,
        isEnabled: Bool,
        onChange: @escaping (Bool) -> Void
    ) {
        self.onChange = onChange
        registration.update(
            view: view,
            session: session,
            isEnabled: isEnabled
        ) { [weak self] hovering, _ in
            self?.onChange?(hovering)
        }
    }

    func detach() {
        registration.disconnect()
        onChange = nil
    }
}

private final class SidebarHoverTrackingArea: NSTrackingArea {
    init(owner: SidebarHoverTrackingView) {
        super.init(
            rect: .zero,
            options: [
                .mouseEnteredAndExited,
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
