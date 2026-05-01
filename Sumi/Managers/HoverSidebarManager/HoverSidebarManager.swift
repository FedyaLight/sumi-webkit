//
//  HoverSidebarManager.swift
//  Sumi
//
//  Created by Jonathan Caudill on 2025-09-13.
//

import SwiftUI
import AppKit

struct HoverSidebarEventMonitorClient {
    let addLocalMonitor: (
        NSEvent.EventTypeMask,
        @escaping (NSEvent) -> NSEvent?
    ) -> Any?
    let removeMonitor: (Any) -> Void

    static let live = HoverSidebarEventMonitorClient(
        addLocalMonitor: { mask, handler in
            NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler)
        },
        removeMonitor: { monitor in
            NSEvent.removeMonitor(monitor)
        }
    )
}

enum HoverSidebarCompactMetrics {
    static let triggerWidth: CGFloat = 5
    static let edgeOvershootSlack: CGFloat = 10
    static let keepOpenHysteresis: CGFloat = 0
    static let verticalBoundsSlack: CGFloat = 7
    static let revealAnimationDuration: TimeInterval = 0.25
    static let hideAnimationDuration: TimeInterval = 0.15
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

/// Manages reveal/hide of the overlay sidebar when the real sidebar is collapsed.
/// Uses a local monitor for in-app hover and drag responsiveness without global
/// event monitoring.
final class HoverSidebarManager: ObservableObject {
    // MARK: - Published State
    @Published var isOverlayVisible: Bool = false
    @Published private(set) var isOverlayHostPrewarmed: Bool = false

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
    weak var browserManager: BrowserManager?
    weak var windowRegistry: WindowRegistry?
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
    private let duplicateMouseMovementThreshold: CGFloat = 0.5
    private let mouseUpdateBypassDistance: CGFloat = 8
    private let mouseUpdateMinimumInterval: CFTimeInterval = 1.0 / 60.0
    private let eventMonitors: HoverSidebarEventMonitorClient
    private let mouseLocationProvider: () -> CGPoint

    init(
        eventMonitors: HoverSidebarEventMonitorClient = .live,
        mouseLocationProvider: @escaping () -> CGPoint = { NSEvent.mouseLocation },
        inactiveHostRetentionDelay: TimeInterval = 30
    ) {
        self.eventMonitors = eventMonitors
        self.mouseLocationProvider = mouseLocationProvider
        self.inactiveHostRetentionDelay = inactiveHostRetentionDelay
    }

    // MARK: - Lifecycle
    func attach(browserManager: BrowserManager, windowState: BrowserWindowState) {
        self.browserManager = browserManager
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
            uninstallMonitors()
            hideOverlayImmediately()
            releaseOverlayHostWhenInactive(after: inactiveHostRetentionDelay)
            return
        }

        retainOverlayHostWhileCollapsed()
        installMonitorsIfNeeded()
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

    deinit { stop() }

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
        guard browserManager != nil,
              let registry = windowRegistry,
              let hostedWindowId,
              registry.activeWindowId == hostedWindowId,
              let activeState = registry.activeWindow else { return }

        // Never show overlay while the real sidebar is visible
        if activeState.isSidebarVisible {
            resetOverlayVisibilityAndHost()
            return
        }

        if activeState.sidebarTransientSessionCoordinator.hasPinnedTransientUI(for: activeState.id) {
            cancelScheduledOverlayHide()
            if !isOverlayVisible {
                requestOverlayReveal(animationDuration: HoverSidebarCompactMetrics.revealAnimationDuration)
            }
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
                requestOverlayReveal(animationDuration: HoverSidebarCompactMetrics.revealAnimationDuration)
            }
        } else if isOverlayVisible {
            scheduleOverlayHide(animationDuration: HoverSidebarCompactMetrics.hideAnimationDuration)
        }
    }

    func requestOverlayReveal(animationDuration: TimeInterval) {
        retainOverlayHostWhileCollapsed()
        overlayVisibilityGeneration &+= 1
        let generation = overlayVisibilityGeneration

        DispatchQueue.main.async { [weak self] in
            guard let self,
                  generation == self.overlayVisibilityGeneration
            else { return }

            withAnimation(.easeInOut(duration: animationDuration)) {
                self.isOverlayVisible = true
            }
        }
    }

    func retainOverlayHostForPinnedInteraction() {
        retainOverlayHostWhileCollapsed()
    }

    func retainOverlayHostWhileCollapsed() {
        prewarmOverlayHost()
    }

    func releaseOverlayHostForMemoryPressure() {
        overlayVisibilityGeneration &+= 1
        overlayHostPrewarmGeneration &+= 1
        hideOverlayImmediately()
        if isOverlayHostPrewarmed {
            isOverlayHostPrewarmed = false
        }
    }

    func setOverlayVisibility(_ isVisible: Bool, animationDuration: TimeInterval) {
        if isVisible {
            requestOverlayReveal(animationDuration: animationDuration)
        } else {
            hideOverlay(animationDuration: animationDuration)
        }
    }

    private func hideOverlay(animationDuration: TimeInterval) {
        overlayVisibilityGeneration &+= 1
        withAnimation(.easeInOut(duration: animationDuration)) {
            isOverlayVisible = false
        }
    }

    private func scheduleOverlayHide(animationDuration: TimeInterval) {
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
        if !isOverlayHostPrewarmed {
            isOverlayHostPrewarmed = true
        }
    }

    private func releaseOverlayHostWhenInactive(after delay: TimeInterval) {
        overlayHostPrewarmGeneration &+= 1
        let generation = overlayHostPrewarmGeneration

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self,
                  generation == self.overlayHostPrewarmGeneration,
                  !self.isOverlayVisible
            else { return }

            self.isOverlayHostPrewarmed = false
        }
    }

    private func hideOverlayImmediately() {
        if isOverlayVisible {
            isOverlayVisible = false
        }
    }

    private func resetOverlayVisibilityAndHost() {
        overlayVisibilityGeneration &+= 1
        overlayHostPrewarmGeneration &+= 1
        if isOverlayVisible {
            isOverlayVisible = false
        }
        if isOverlayHostPrewarmed {
            isOverlayHostPrewarmed = false
        }
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
