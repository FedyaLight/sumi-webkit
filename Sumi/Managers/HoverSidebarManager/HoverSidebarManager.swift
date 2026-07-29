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

    static let inactive = HoverSidebarRuntime(
        browserRuntimeAvailable: { false }
    )
}

/// Manages reveal/hide of the overlay sidebar when the real sidebar is collapsed.
/// Uses a local monitor for in-app hover and drag responsiveness without global
/// event monitoring.
@MainActor
final class HoverSidebarManager: ObservableObject {
    private enum ScheduledOverlayVisibilityIntent {
        case reveal
        case hide
    }

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
    private weak var chromePresentation: BrowserWindowChromePresentation?

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
    private var isPinnedInteractionActive = false
    private var isStartupResolutionPending = false
    private var overlayMotionMode: SidebarMotionPolicy.Mode = .standard
    private let duplicateMouseMovementThreshold: CGFloat = 0.5
    private let mouseUpdateBypassDistance: CGFloat = 8
    private let mouseUpdateMinimumInterval: CFTimeInterval = 1.0 / 60.0
    private let eventMonitors: HoverSidebarEventMonitorClient
    private let mouseLocationProvider: () -> CGPoint
    private let delayedActions: MainActorDelayedActionScheduler
    private var cancelScheduledOverlayVisibilityAction: MainActorDelayedActionScheduler.Cancellation?
    private var scheduledOverlayVisibilityIntent: ScheduledOverlayVisibilityIntent?
    private var cancelInactiveHostReleaseAction: MainActorDelayedActionScheduler.Cancellation?

    init(
        eventMonitors: HoverSidebarEventMonitorClient = .live(),
        mouseLocationProvider: @escaping () -> CGPoint = { NSEvent.mouseLocation },
        inactiveHostRetentionDelay: TimeInterval = 2,
        delayedActions: MainActorDelayedActionScheduler = .live
    ) {
        self.eventMonitors = eventMonitors
        self.mouseLocationProvider = mouseLocationProvider
        self.inactiveHostRetentionDelay = inactiveHostRetentionDelay
        self.delayedActions = delayedActions
    }

    // MARK: - Lifecycle
    func attach(runtime: HoverSidebarRuntime, windowState: BrowserWindowState) {
        self.runtime = runtime
        hostedWindowId = windowState.id
        chromePresentation = windowState.chromePresentation
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
            requestOverlayReveal()
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
        invalidateOverlayVisibilityWork()
        invalidateOverlayHostPrewarmWork()
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
            self.handleMouseMovementOnMain(mouse: mouse)
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
    private func handleMouseMovementOnMain(mouse: CGPoint) {
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
            || isPinnedInteractionActive
            || activeState.sidebarTransientSessionCoordinator.hasPinnedTransientUI(for: activeState.id) {
            revealOverlayForActivePin()
            return
        }

        guard let window = windowRegistry?.appKitWindow(for: activeState) else {
            resetOverlayVisibilityAndHost()
            return
        }

        // Mouse and window frames are in screen coordinates
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
                requestPointerOverlayReveal()
            }
        } else if isOverlayVisible {
            // An active empty-state force would have returned early above, so reaching
            // here means no pin is holding the overlay open and it may schedule a hide.
            scheduleOverlayHide()
        }
    }

    func requestOverlayReveal() {
        requestOverlayReveal(validatesPointerIntent: false)
    }

    func requestPointerOverlayReveal() {
        requestOverlayReveal(
            validatesPointerIntent: true
        )
    }

    private func requestOverlayReveal(
        validatesPointerIntent: Bool
    ) {
        retainOverlayHostWhileCollapsed()
        invalidateOverlayVisibilityWork()
        let generation = overlayVisibilityGeneration

        cancelScheduledOverlayVisibilityAction = delayedActions.schedule(after: 0) { [weak self] in
            guard let self,
                  generation == self.overlayVisibilityGeneration
            else { return }

            self.cancelScheduledOverlayVisibilityAction = nil
            self.scheduledOverlayVisibilityIntent = nil
            if validatesPointerIntent,
               !self.shouldCompletePendingPointerReveal(
                    sidebarPosition: self.sidebarPosition
               ) {
                return
            }

            self.performOverlayMotion(
                toward: .visible,
                animation: SidebarMotionPolicy.overlayMotion(
                    for: self.overlayMotionMode
                ).animation
            ) {
                self.overlayHostLifecycleState = .visible
            }
        }
        scheduledOverlayVisibilityIntent = .reveal
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
            requestOverlayReveal()
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
            hideOverlay()
        } else {
            hideOverlayImmediately()
        }
    }

    func deferOverlayHostRetentionWhileCollapsed() {
        guard !isStartupResolutionPending else { return }
        invalidateOverlayHostPrewarmWork()
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
        invalidateOverlayVisibilityWork()
        invalidateOverlayHostPrewarmWork()
        hideOverlayImmediately()
        overlayHostLifecycleState = .unmounted
    }

    func dismissOverlayForTransientChrome() {
        guard !isEmptyStateOverlayForceActive else { return }
        hideOverlay()
    }

    func configureMotionMode(_ mode: SidebarMotionPolicy.Mode) {
        overlayMotionMode = mode
    }

    func setStartupResolutionPending(_ isPending: Bool) {
        guard isStartupResolutionPending != isPending else { return }
        isStartupResolutionPending = isPending
        if isPending {
            invalidateOverlayHostPrewarmWork()
            if !isOverlayVisible {
                overlayHostLifecycleState = .unmounted
            }
        } else {
            deferOverlayHostRetentionWhileCollapsed()
        }
    }

    func setPinnedInteractionActive(_ isActive: Bool) {
        guard isPinnedInteractionActive != isActive else { return }
        isPinnedInteractionActive = isActive
        if isActive {
            retainOverlayHostWhileCollapsed()
            revealOverlayForActivePin()
        } else if isOverlayVisible,
                  !shouldCompletePendingPointerReveal(sidebarPosition: sidebarPosition) {
            scheduleOverlayHide()
        }
    }

    private func hideOverlay() {
        invalidateOverlayVisibilityWork()
        performOverlayMotion(
            toward: .hidden,
            animation: SidebarMotionPolicy.overlayMotion(for: overlayMotionMode).animation
        ) {
            self.overlayHostLifecycleState = .retainedHidden
        }
    }

    private func scheduleOverlayHide() {
        guard !isEmptyStateOverlayForceActive else { return }

        invalidateOverlayVisibilityWork()
        let generation = overlayVisibilityGeneration

        cancelScheduledOverlayVisibilityAction = delayedActions.schedule(
            after: HoverSidebarCompactMetrics.keepHoverDuration
        ) { [weak self] in
            guard let self,
                  generation == self.overlayVisibilityGeneration
            else { return }

            self.cancelScheduledOverlayVisibilityAction = nil
            self.scheduledOverlayVisibilityIntent = nil
            self.hideOverlay()
        }
        scheduledOverlayVisibilityIntent = .hide
    }

    private func cancelScheduledOverlayHide() {
        guard scheduledOverlayVisibilityIntent == .hide else { return }
        invalidateOverlayVisibilityWork()
    }

    private func prewarmOverlayHost() {
        invalidateOverlayHostPrewarmWork()
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
              hostedState.isSidebarVisible == false,
              !isStartupResolutionPending
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
              let window = windowRegistry?.appKitWindow(for: activeState)
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
        invalidateOverlayHostPrewarmWork()
        let generation = overlayHostPrewarmGeneration

        cancelInactiveHostReleaseAction = delayedActions.schedule(after: delay) { [weak self] in
            guard let self,
                  generation == self.overlayHostPrewarmGeneration,
                  !self.isOverlayVisible
            else { return }

            self.cancelInactiveHostReleaseAction = nil
            self.overlayHostLifecycleState = .unmounted
        }
    }

    private func hideOverlayImmediately() {
        performOverlayMotion(toward: .hidden, animation: nil) {
            if self.isOverlayVisible {
                self.overlayHostLifecycleState = .retainedHidden
            }
        }
    }

    /// Publishes the overlay as visible without any transition, bumping the reveal
    /// and prewarm generations so any in-flight animated reveal or deferred host
    /// release is cancelled. Mirrors `hideOverlayImmediately()`.
    private func revealOverlayImmediately() {
        invalidateOverlayHostPrewarmWork()
        invalidateOverlayVisibilityWork()
        performOverlayMotion(toward: .visible, animation: nil) {
            self.overlayHostLifecycleState = .visible
        }
    }

    /// Keeps the overlay revealed while a pin (empty-state force or transient UI)
    /// requires it open: cancels any scheduled hide and reveals it if hidden.
    private func revealOverlayForActivePin() {
        cancelScheduledOverlayHide()
        if !isOverlayVisible {
            requestOverlayReveal()
        }
    }

    private func performOverlayMotion(
        toward visibility: BrowserWindowSidebarLayoutVisibility,
        animation: Animation?,
        update: @escaping @MainActor () -> Void
    ) {
        if let chromePresentation {
            chromePresentation.performSidebarMotion(
                surface: .collapsed,
                toward: visibility,
                animation: animation,
                updateLayout: update
            )
        } else if let animation {
            withAnimation(
                animation,
                completionCriteria: .removed,
                update,
                completion: {
                    // No chrome authority exists in isolated manager tests.
                }
            )
        } else {
            var transaction = Transaction()
            transaction.animation = nil
            transaction.disablesAnimations = true
            withTransaction(transaction, update)
        }
    }

    private func resetOverlayVisibilityAndHost() {
        isEmptyStateOverlayForceActive = false
        isPinnedInteractionActive = false
        invalidateOverlayVisibilityWork()
        invalidateOverlayHostPrewarmWork()
        overlayHostLifecycleState = .unmounted
    }

    private func invalidateOverlayVisibilityWork() {
        overlayVisibilityGeneration &+= 1
        cancelScheduledOverlayVisibilityAction?()
        cancelScheduledOverlayVisibilityAction = nil
        scheduledOverlayVisibilityIntent = nil
    }

    private func invalidateOverlayHostPrewarmWork() {
        overlayHostPrewarmGeneration &+= 1
        cancelInactiveHostReleaseAction?()
        cancelInactiveHostReleaseAction = nil
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
