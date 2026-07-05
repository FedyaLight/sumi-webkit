//
//  HoverSidebarManager.swift
//  Sumi
//
//

import AppKit
import SwiftUI

struct HoverSidebarEventMonitorClient {
    let addLocalMonitor: (
        NSEvent.EventTypeMask,
        @escaping (NSEvent) -> NSEvent?
    ) -> Any?
    let removeMonitor: (Any) -> Void

    static func live() -> HoverSidebarEventMonitorClient {
        HoverSidebarEventMonitorClient(
            addLocalMonitor: { mask, handler in
                NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler)
            },
            removeMonitor: { monitor in
                NSEvent.removeMonitor(monitor)
            }
        )
    }
}

enum HoverSidebarCompactMetrics {
    static let triggerWidth: CGFloat = 5
    static let edgeOvershootSlack: CGFloat = 10
    static let keepOpenHysteresis: CGFloat = 0
    static let verticalBoundsSlack: CGFloat = 7
    static let revealAnimationDuration: TimeInterval = 0.25
    static let hideAnimationDuration: TimeInterval = 0.25
    static let keepHoverDuration: TimeInterval = 0.15
}

enum HoverSidebarVisibilityPolicy {
    static func shouldShowOverlay(
        mouse: CGPoint,
        windowFrame: CGRect,
        overlayWidth: CGFloat,
        isOverlayVisible: Bool,
        contextMenuPresented: Bool,
        sidebarPosition: SidebarPosition = .left,
        triggerWidth: CGFloat,
        overshootSlack: CGFloat,
        keepOpenHysteresis: CGFloat,
        verticalSlack: CGFloat
    ) -> Bool {
        if contextMenuPresented {
            return true
        }

        let verticalOK = mouse.y >= windowFrame.minY - verticalSlack
            && mouse.y <= windowFrame.maxY + verticalSlack
        guard verticalOK else {
            return false
        }

        let shellEdge = sidebarPosition.shellEdge
        let inTriggerZone = shellEdge.containsTriggerZone(
            mouseX: mouse.x,
            windowFrame: windowFrame,
            triggerWidth: triggerWidth,
            overshootSlack: overshootSlack
        )
        let inKeepOpenZone = shellEdge.containsKeepOpenZone(
            mouseX: mouse.x,
            windowFrame: windowFrame,
            overlayWidth: overlayWidth,
            keepOpenHysteresis: keepOpenHysteresis
        )
        let inSidebarContentZone = shellEdge.containsSidebarContentZone(
            mouseX: mouse.x,
            windowFrame: windowFrame,
            overlayWidth: overlayWidth
        )

        return inTriggerZone || (isOverlayVisible && (inKeepOpenZone || inSidebarContentZone))
    }
}

enum HoverSidebarOverlayHostLifecycleState: Equatable {
    case unmounted
    case retainedHidden
    case visible
}

@MainActor
struct HoverSidebarRuntime {
    let browserRuntimeAvailable: @MainActor () -> Bool
    let settings: @MainActor () -> SumiSettingsService?

    static let inactive = HoverSidebarRuntime(
        browserRuntimeAvailable: { false },
        settings: { nil }
    )
}

/// Manages reveal/hide of the overlay sidebar when the real sidebar is collapsed.
/// Uses a local monitor for in-app hover and drag responsiveness without global
/// event monitoring.
@MainActor
final class HoverSidebarManager: ObservableObject {
    // MARK: - Published State
    @Published private(set) var overlayHostLifecycleState: HoverSidebarOverlayHostLifecycleState = .unmounted

    var isOverlayVisible: Bool {
        overlayHostLifecycleState == .visible
    }

    var isOverlayHostPrewarmed: Bool {
        overlayHostLifecycleState != .unmounted
    }

    // MARK: - Configuration
    /// Zen compact exposes `content-element-separation / 2 + 1px`, which is 5px by default.
    var triggerWidth: CGFloat = HoverSidebarCompactMetrics.triggerWidth
    /// Zen keeps edge crossing active within 10px of the window edge.
    var overshootSlack: CGFloat = HoverSidebarCompactMetrics.edgeOvershootSlack
    /// Zen relies on the sidebar's actual bounds, then keeps hover for 150ms after leave.
    var keepOpenHysteresis: CGFloat = HoverSidebarCompactMetrics.keepOpenHysteresis
    /// Zen accepts a 7px vertical bounds error for edge-cross hover retention.
    var verticalSlack: CGFloat = HoverSidebarCompactMetrics.verticalBoundsSlack
    var sidebarPosition: SidebarPosition = .left
    var inactiveHostRetentionDelay: TimeInterval

    // MARK: - Dependencies
    weak var windowRegistry: WindowRegistry?
    private var runtime = HoverSidebarRuntime.inactive
    private var hostedWindowId: UUID?

    // MARK: - Monitors
    private var localMonitor: Any?
    private var isActive: Bool = false
    private var monitorsInstalled: Bool = false
    private var isMouseUpdateScheduled: Bool = false
    private var lastScheduledMouseLocation: CGPoint?
    private var lastMouseUpdateScheduledAt: CFTimeInterval = 0
    private var overlayHostPrewarmGeneration: UInt64 = 0
    private var overlayVisibilityGeneration: UInt64 = 0
    private var isEmptyStateOverlayForceActive = false
    private let duplicateMouseMovementThreshold: CGFloat = 0.5
    private let mouseUpdateBypassDistance: CGFloat = 8
    private let mouseUpdateMinimumInterval: CFTimeInterval = 1.0 / 60.0
    private let eventMonitors: HoverSidebarEventMonitorClient
    private let mouseLocationProvider: () -> CGPoint

    init(
        eventMonitors: HoverSidebarEventMonitorClient = .live(),
        mouseLocationProvider: @escaping () -> CGPoint = { NSEvent.mouseLocation },
        inactiveHostRetentionDelay: TimeInterval = 2
    ) {
        self.eventMonitors = eventMonitors
        self.mouseLocationProvider = mouseLocationProvider
        self.inactiveHostRetentionDelay = inactiveHostRetentionDelay
    }

    // MARK: - Lifecycle
    func attach(runtime: HoverSidebarRuntime, windowState: BrowserWindowState) {
        self.runtime = runtime
        hostedWindowId = windowState.id
    }

    func start() {
        guard !isActive else { return }
        isActive = true
        Task { @MainActor [weak self] in
            self?.refreshMonitoring()
        }
    }

    @MainActor
    func refreshMonitoring() {
        guard isActive,
              let registry = windowRegistry,
              let hostedWindowId,
              let hostedState = registry.windows[hostedWindowId]
        else {
            uninstallMonitors()
            resetOverlayVisibilityAndHost()
            return
        }

        guard !hostedState.isSidebarVisible else {
            uninstallMonitors()
            resetOverlayVisibilityAndHost()
            return
        }

        guard registry.activeWindowId == hostedWindowId else {
            // During startup the registry has not promoted any window to active yet
            // (`activeWindowId == nil`). While the empty-state force is pinning the
            // collapsed sidebar, tearing it down here just to re-reveal it once the
            // window becomes active produces a visible flicker. Hold the pinned
            // overlay until a real active window (this one or another) is resolved.
            if isEmptyStateOverlayForceActive, registry.activeWindowId == nil {
                return
            }
            uninstallMonitors()
            hideOverlayImmediately()
            releaseOverlayHostWhenInactive(after: inactiveHostRetentionDelay)
            return
        }

        deferOverlayHostRetentionWhileCollapsed()
        installMonitorsIfNeeded()
        if isEmptyStateOverlayForceActive, !isOverlayVisible {
            requestOverlayReveal(animationDuration: HoverSidebarCompactMetrics.revealAnimationDuration)
        }
    }

    private func installMonitorsIfNeeded() {
        guard !monitorsInstalled else { return }
        monitorsInstalled = true
        // Local monitor for responsive updates while the app is active
        localMonitor = eventMonitors.addLocalMonitor(
            [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] event in
            self?.scheduleHandleMouseMovement()
            return event
        }
    }

    func stop() {
        isActive = false
        uninstallMonitors()
        DispatchQueue.main.async { [weak self] in
            self?.resetOverlayVisibilityAndHost()
        }
    }

    deinit {
        MainActor.assumeIsolated {
            stop()
        }
    }

    // MARK: - Mouse Logic
    private func scheduleHandleMouseMovement() {
        guard isActive, !isMouseUpdateScheduled else { return }
        let mouse = mouseLocationProvider()
        guard shouldScheduleMouseUpdate(for: mouse) else { return }

        isMouseUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isMouseUpdateScheduled = false
            self.handleMouseMovementOnMain()
        }
    }

    private func shouldScheduleMouseUpdate(for mouse: CGPoint) -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        func recordScheduledMouseUpdate() {
            lastScheduledMouseLocation = mouse
            lastMouseUpdateScheduledAt = now
        }

        guard let previous = lastScheduledMouseLocation else {
            recordScheduledMouseUpdate()
            return true
        }

        let dx = abs(mouse.x - previous.x)
        let dy = abs(mouse.y - previous.y)
        guard dx > duplicateMouseMovementThreshold || dy > duplicateMouseMovementThreshold else {
            return false
        }

        let isLargeJump = dx >= mouseUpdateBypassDistance || dy >= mouseUpdateBypassDistance
        if !isLargeJump && now - lastMouseUpdateScheduledAt < mouseUpdateMinimumInterval {
            return false
        }

        recordScheduledMouseUpdate()
        return true
    }

    @MainActor
    private func handleMouseMovementOnMain() {
        guard runtime.browserRuntimeAvailable(),
              let registry = windowRegistry,
              let hostedWindowId,
              registry.activeWindowId == hostedWindowId,
              let activeState = registry.activeWindow else { return }

        // Never show overlay while the real sidebar is visible
        if activeState.isSidebarVisible {
            resetOverlayVisibilityAndHost()
            return
        }

        // The empty-state force and pinned transient UI both hold the overlay open
        // regardless of pointer position; keep it revealed and skip hover tracking.
        if isEmptyStateOverlayForceActive
            || activeState.sidebarTransientSessionCoordinator.hasPinnedTransientUI(for: activeState.id) {
            revealOverlayForActivePin()
            return
        }

        guard let window = activeState.window else {
            resetOverlayVisibilityAndHost()
            return
        }

        // Mouse and window frames are in screen coordinates
        let mouse = mouseLocationProvider()
        let frame = window.frame

        let overlayWidth = SidebarPresentationContext.collapsedSidebarWidth(
            sidebarWidth: activeState.sidebarWidth,
            savedSidebarWidth: activeState.savedSidebarWidth
        )

        let shouldShow = HoverSidebarVisibilityPolicy.shouldShowOverlay(
            mouse: mouse,
            windowFrame: frame,
            overlayWidth: overlayWidth,
            isOverlayVisible: isOverlayVisible,
            contextMenuPresented: false,
            sidebarPosition: sidebarPosition,
            triggerWidth: triggerWidth,
            overshootSlack: overshootSlack,
            keepOpenHysteresis: keepOpenHysteresis,
            verticalSlack: verticalSlack
        )

        if shouldShow {
            cancelScheduledOverlayHide()
            if !isOverlayVisible {
                requestPointerOverlayReveal(animationDuration: HoverSidebarCompactMetrics.revealAnimationDuration)
            }
        } else if isOverlayVisible {
            // An active empty-state force would have returned early above, so reaching
            // here means no pin is holding the overlay open and it may schedule a hide.
            scheduleOverlayHide(animationDuration: HoverSidebarCompactMetrics.hideAnimationDuration)
        }
    }

    func requestOverlayReveal(animationDuration: TimeInterval) {
        requestOverlayReveal(animationDuration: animationDuration, validatesPointerIntent: false)
    }

    func requestPointerOverlayReveal(
        animationDuration: TimeInterval,
        sidebarPosition: SidebarPosition? = nil
    ) {
        requestOverlayReveal(
            animationDuration: animationDuration,
            validatesPointerIntent: true,
            pointerSidebarPosition: sidebarPosition
        )
    }

    private func requestOverlayReveal(
        animationDuration: TimeInterval,
        validatesPointerIntent: Bool,
        pointerSidebarPosition: SidebarPosition? = nil
    ) {
        retainOverlayHostWhileCollapsed()
        overlayVisibilityGeneration &+= 1
        let generation = overlayVisibilityGeneration

        DispatchQueue.main.async { [weak self] in
            guard let self,
                  generation == self.overlayVisibilityGeneration
            else { return }

            if validatesPointerIntent,
               !self.shouldCompletePendingPointerReveal(
                    sidebarPosition: pointerSidebarPosition ?? self.sidebarPosition
               ) {
                return
            }

            withAnimation(sidebarOverlayAnimation(fallbackDuration: animationDuration)) {
                self.overlayHostLifecycleState = .visible
            }
        }
    }

    func retainOverlayHostForPinnedInteraction() {
        retainOverlayHostWhileCollapsed()
    }

    func retainOverlayHostWhileCollapsed() {
        prewarmOverlayHost()
    }

    func forceOverlayVisibleForEmptyState(
        animated: Bool,
        sidebarPosition: SidebarPosition
    ) {
        self.sidebarPosition = sidebarPosition
        isEmptyStateOverlayForceActive = true
        cancelScheduledOverlayHide()

        if animated {
            requestOverlayReveal(animationDuration: HoverSidebarCompactMetrics.revealAnimationDuration)
        } else {
            revealOverlayImmediately()
        }
    }

    func releaseEmptyStateOverlayForce(
        animated: Bool,
        sidebarPosition: SidebarPosition
    ) {
        guard isEmptyStateOverlayForceActive else { return }

        self.sidebarPosition = sidebarPosition
        isEmptyStateOverlayForceActive = false

        if shouldCompletePendingPointerReveal(sidebarPosition: sidebarPosition) {
            revealOverlayForActivePin()
            return
        }

        if animated {
            hideOverlay(animationDuration: HoverSidebarCompactMetrics.hideAnimationDuration)
        } else {
            hideOverlayImmediately()
        }
    }

    func deferOverlayHostRetentionWhileCollapsed() {
        overlayHostPrewarmGeneration &+= 1
        let generation = overlayHostPrewarmGeneration

        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                  generation == self.overlayHostPrewarmGeneration,
                  self.shouldRetainOverlayHostForCollapsedActiveWindow()
            else {
                return
            }

            self.prewarmOverlayHost()
        }
    }

    func releaseOverlayHostForMemoryPressure() {
        overlayVisibilityGeneration &+= 1
        overlayHostPrewarmGeneration &+= 1
        hideOverlayImmediately()
        overlayHostLifecycleState = .unmounted
    }

    func setOverlayVisibility(_ isVisible: Bool, animationDuration: TimeInterval) {
        if isVisible {
            requestOverlayReveal(animationDuration: animationDuration)
        } else {
            hideOverlay(animationDuration: animationDuration)
        }
    }

    func dismissOverlayForTransientChrome(animationDuration: TimeInterval) {
        guard !isEmptyStateOverlayForceActive else { return }
        setOverlayVisibility(false, animationDuration: animationDuration)
    }

    private func hideOverlay(animationDuration: TimeInterval) {
        overlayVisibilityGeneration &+= 1
        withAnimation(sidebarOverlayAnimation(fallbackDuration: animationDuration)) {
            overlayHostLifecycleState = .retainedHidden
        }
    }

    private func scheduleOverlayHide(animationDuration: TimeInterval) {
        guard !isEmptyStateOverlayForceActive else { return }

        overlayVisibilityGeneration &+= 1
        let generation = overlayVisibilityGeneration

        DispatchQueue.main.asyncAfter(
            deadline: .now() + HoverSidebarCompactMetrics.keepHoverDuration
        ) { [weak self] in
            guard let self,
                  generation == self.overlayVisibilityGeneration
            else { return }

            self.hideOverlay(animationDuration: animationDuration)
        }
    }

    private func cancelScheduledOverlayHide() {
        overlayVisibilityGeneration &+= 1
    }

    private func prewarmOverlayHost() {
        overlayHostPrewarmGeneration &+= 1
        if overlayHostLifecycleState == .unmounted {
            overlayHostLifecycleState = .retainedHidden
        }
    }

    private func shouldRetainOverlayHostForCollapsedActiveWindow() -> Bool {
        guard isActive,
              let registry = windowRegistry,
              let hostedWindowId,
              registry.activeWindowId == hostedWindowId,
              let hostedState = registry.windows[hostedWindowId],
              hostedState.isSidebarVisible == false
        else {
            return false
        }

        return true
    }

    private func shouldCompletePendingPointerReveal(sidebarPosition: SidebarPosition) -> Bool {
        guard isActive,
              runtime.browserRuntimeAvailable(),
              let registry = windowRegistry,
              let hostedWindowId,
              registry.activeWindowId == hostedWindowId,
              let activeState = registry.activeWindow,
              activeState.isSidebarVisible == false,
              let window = activeState.window
        else {
            return false
        }

        if activeState.sidebarTransientSessionCoordinator.hasPinnedTransientUI(for: activeState.id) {
            return true
        }

        let overlayWidth = SidebarPresentationContext.collapsedSidebarWidth(
            sidebarWidth: activeState.sidebarWidth,
            savedSidebarWidth: activeState.savedSidebarWidth
        )

        return HoverSidebarVisibilityPolicy.shouldShowOverlay(
            mouse: mouseLocationProvider(),
            windowFrame: window.frame,
            overlayWidth: overlayWidth,
            isOverlayVisible: true,
            contextMenuPresented: false,
            sidebarPosition: sidebarPosition,
            triggerWidth: triggerWidth,
            overshootSlack: overshootSlack,
            keepOpenHysteresis: keepOpenHysteresis,
            verticalSlack: verticalSlack
        )
    }

    private func releaseOverlayHostWhenInactive(after delay: TimeInterval) {
        overlayHostPrewarmGeneration &+= 1
        let generation = overlayHostPrewarmGeneration

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self,
                  generation == self.overlayHostPrewarmGeneration,
                  !self.isOverlayVisible
            else { return }

            self.overlayHostLifecycleState = .unmounted
        }
    }

    private func hideOverlayImmediately() {
        if isOverlayVisible {
            overlayHostLifecycleState = .retainedHidden
        }
    }

    /// Publishes the overlay as visible without any transition, bumping the reveal
    /// and prewarm generations so any in-flight animated reveal or deferred host
    /// release is cancelled. Mirrors `hideOverlayImmediately()`.
    private func revealOverlayImmediately() {
        overlayHostPrewarmGeneration &+= 1
        overlayVisibilityGeneration &+= 1
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil
        withTransaction(transaction) {
            overlayHostLifecycleState = .visible
        }
    }

    /// Keeps the overlay revealed while a pin (empty-state force or transient UI)
    /// requires it open: cancels any scheduled hide and reveals it if hidden.
    private func revealOverlayForActivePin() {
        cancelScheduledOverlayHide()
        if !isOverlayVisible {
            requestOverlayReveal(animationDuration: HoverSidebarCompactMetrics.revealAnimationDuration)
        }
    }

    private func sidebarOverlayAnimation(fallbackDuration: TimeInterval) -> Animation? {
        SidebarMotionPolicy.overlayAnimation(
            for: SidebarMotionPolicy.appKitCurrentMode(settings: runtime.settings())
        )
            ?? .easeOut(duration: fallbackDuration)
    }

    private func resetOverlayVisibilityAndHost() {
        isEmptyStateOverlayForceActive = false
        overlayVisibilityGeneration &+= 1
        overlayHostPrewarmGeneration &+= 1
        overlayHostLifecycleState = .unmounted
    }

    private func uninstallMonitors() {
        isMouseUpdateScheduled = false
        lastScheduledMouseLocation = nil
        lastMouseUpdateScheduledAt = 0
        monitorsInstalled = false
        if let token = localMonitor {
            eventMonitors.removeMonitor(token)
            localMonitor = nil
        }
    }
}
