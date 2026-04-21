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
    let addGlobalMonitor: (
        NSEvent.EventTypeMask,
        @escaping (NSEvent) -> Void
    ) -> Any?
    let removeMonitor: (Any) -> Void

    static let live = HoverSidebarEventMonitorClient(
        addLocalMonitor: { mask, handler in
            NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler)
        },
        addGlobalMonitor: { mask, handler in
            NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
        },
        removeMonitor: { monitor in
            NSEvent.removeMonitor(monitor)
        }
    )
}

enum HoverSidebarVisibilityPolicy {
    static func shouldShowOverlay(
        mouse: CGPoint,
        windowFrame: CGRect,
        overlayWidth: CGFloat,
        isOverlayVisible: Bool,
        contextMenuPresented: Bool,
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

        let inTriggerZone = (mouse.x >= windowFrame.minX - overshootSlack)
            && (mouse.x <= windowFrame.minX + triggerWidth)
        let inKeepOpenZone = (mouse.x >= windowFrame.minX)
            && (mouse.x <= windowFrame.minX + overlayWidth + keepOpenHysteresis)
        let inSidebarContentZone = (mouse.x >= windowFrame.minX)
            && (mouse.x <= windowFrame.minX + overlayWidth)

        return inTriggerZone || (isOverlayVisible && (inKeepOpenZone || inSidebarContentZone))
    }
}

/// Manages reveal/hide of the overlay sidebar when the real sidebar is collapsed.
/// Uses a local monitor for in-app drag responsiveness plus a minimal global mouse-move
/// monitor to catch slight overshoot beyond the window's left boundary.
final class HoverSidebarManager: ObservableObject {
    // MARK: - Published State
    @Published var isOverlayVisible: Bool = false

    // MARK: - Configuration
    /// Width inside the window that triggers reveal when hovered.
    var triggerWidth: CGFloat = 6
    /// Horizontal slack to the left of the window to catch slight overshoot.
    var overshootSlack: CGFloat = 12
    /// Extra horizontal margin past the overlay to keep it open while interacting.
    var keepOpenHysteresis: CGFloat = 52
    /// Vertical slack to allow small overshoot above/below the window frame.
    var verticalSlack: CGFloat = 24

    // MARK: - Dependencies
    weak var browserManager: BrowserManager?
    weak var windowRegistry: WindowRegistry?
    weak var sumiSettings: SumiSettingsService?
    private var hostedWindowId: UUID?

    // MARK: - Monitors
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isActive: Bool = false
    private var monitorsInstalled: Bool = false
    private var isMouseUpdateScheduled: Bool = false
    private var lastScheduledMouseLocation: CGPoint?
    private var lastMouseUpdateScheduledAt: CFTimeInterval = 0
    private let duplicateMouseMovementThreshold: CGFloat = 0.5
    private let mouseUpdateBypassDistance: CGFloat = 8
    private let mouseUpdateMinimumInterval: CFTimeInterval = 1.0 / 60.0
    private let eventMonitors: HoverSidebarEventMonitorClient
    private let mouseLocationProvider: () -> CGPoint

    init(
        eventMonitors: HoverSidebarEventMonitorClient = .live,
        mouseLocationProvider: @escaping () -> CGPoint = { NSEvent.mouseLocation }
    ) {
        self.eventMonitors = eventMonitors
        self.mouseLocationProvider = mouseLocationProvider
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
              registry.activeWindowId == hostedWindowId,
              let activeState = registry.activeWindow,
              !activeState.isSidebarVisible
        else {
            uninstallMonitors()
            if isOverlayVisible {
                isOverlayVisible = false
            }
            return
        }

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

        // Global monitor to detect near-edge hovers even when cursor overshoots beyond window bounds
        globalMonitor = eventMonitors.addGlobalMonitor([.mouseMoved]) { [weak self] _ in
            self?.scheduleHandleMouseMovement()
        }
    }

    func stop() {
        isActive = false
        uninstallMonitors()
        DispatchQueue.main.async { [weak self] in self?.isOverlayVisible = false }
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
            if isOverlayVisible {
                isOverlayVisible = false
            }
            return
        }

        if activeState.sidebarTransientSessionCoordinator.hasPinnedTransientUI(for: activeState.id) {
            if !isOverlayVisible {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isOverlayVisible = true
                }
            }
            return
        }

        guard let window = activeState.window else {
            if isOverlayVisible {
                isOverlayVisible = false
            }
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
            triggerWidth: triggerWidth,
            overshootSlack: overshootSlack,
            keepOpenHysteresis: keepOpenHysteresis,
            verticalSlack: verticalSlack
        )

        if shouldShow != isOverlayVisible {
            withAnimation(.easeInOut(duration: 0.15)) {
                isOverlayVisible = shouldShow
            }
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
        if let token = globalMonitor {
            eventMonitors.removeMonitor(token)
            globalMonitor = nil
        }
    }
}
