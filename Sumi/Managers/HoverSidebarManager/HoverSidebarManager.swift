//
//  HoverSidebarManager.swift
//  Sumi
//
//  Created by Jonathan Caudill on 2025-09-13.
//

import SwiftUI
import AppKit

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
/// Uses a global mouse-move monitor to handle edge hover, including slight overshoot
/// beyond the window's left boundary.
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
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            self?.scheduleHandleMouseMovement()
            return event
        }

        // Global monitor to detect near-edge hovers even when cursor overshoots beyond window bounds
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] _ in
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
        isMouseUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isMouseUpdateScheduled = false
            self.handleMouseMovementOnMain()
        }
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

        guard let window = NSApp.keyWindow else {
            if isOverlayVisible {
                isOverlayVisible = false
            }
            return
        }

        // Mouse and window frames are in screen coordinates
        let mouse = NSEvent.mouseLocation
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
        monitorsInstalled = false
        if let token = localMonitor { NSEvent.removeMonitor(token); localMonitor = nil }
        if let token = globalMonitor { NSEvent.removeMonitor(token); globalMonitor = nil }
    }
}
