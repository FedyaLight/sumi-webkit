//
//  SidebarHoverOverlayView.swift
//  Sumi
//
//  Created by Jonathan Caudill on 2025-09-13.
//

import SwiftUI
import AppKit

enum SidebarHoverOverlayTransientPinningPolicy {
    static func shouldPinHoverSidebar(
        transientWindowID: UUID?,
        currentWindowID: UUID,
        isSidebarVisible: Bool
    ) -> Bool {
        guard let transientWindowID else { return false }
        return transientWindowID == currentWindowID && !isSidebarVisible
    }
}

enum SidebarHoverOverlayDragPinningPolicy {
    static func shouldPinHoverSidebar(
        activeWindowID: UUID?,
        currentWindowID: UUID,
        isSidebarVisible: Bool,
        isDragging: Bool,
        isInternalDragSession: Bool
    ) -> Bool {
        activeWindowID == currentWindowID
            && !isSidebarVisible
            && isDragging
            && isInternalDragSession
    }
}

enum SidebarHoverOverlayRevealPolicy {
    static func isOverlayRevealed(
        isOverlayVisible: Bool,
        transientUIPinsHoverSidebar: Bool,
        sidebarDragPinsHoverSidebar: Bool
    ) -> Bool {
        isOverlayVisible || transientUIPinsHoverSidebar || sidebarDragPinsHoverSidebar
    }
}

enum SidebarHoverOverlayHostMountPolicy {
    static func shouldMountCollapsedHost(
        isSidebarVisible: Bool,
        isOverlayVisible: Bool,
        isOverlayHostPrewarmed: Bool,
        transientUIPinsHoverSidebar: Bool,
        sidebarDragPinsHoverSidebar: Bool
    ) -> Bool {
        guard !isSidebarVisible else { return false }
        return isOverlayHostPrewarmed
            || SidebarHoverOverlayRevealPolicy.isOverlayRevealed(
                isOverlayVisible: isOverlayVisible,
                transientUIPinsHoverSidebar: transientUIPinsHoverSidebar,
                sidebarDragPinsHoverSidebar: sidebarDragPinsHoverSidebar
            )
    }
}

enum SidebarHoverOverlayMetrics {
    static let cornerRadius: CGFloat = 12
    static let revealAnimationDuration: TimeInterval = HoverSidebarCompactMetrics.revealAnimationDuration
}

struct SidebarHoverOverlayView: View {
    let resolvedThemeContext: ResolvedThemeContext
    let chromeBackgroundResolvedThemeContext: ResolvedThemeContext

    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var hoverManager: HoverSidebarManager
    @ObservedObject private var dragState = SidebarDragState.shared
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(CommandPalette.self) private var commandPalette
    @Environment(\.sumiSettings) private var sumiSettings

    /// Keep the hover sidebar on-screen while any sidebar transient UI is alive in compact mode.
    private var transientUIPinsHoverSidebar: Bool {
        SidebarHoverOverlayTransientPinningPolicy.shouldPinHoverSidebar(
            transientWindowID: windowState.sidebarTransientSessionCoordinator.currentPresentationWindowID,
            currentWindowID: windowState.id,
            isSidebarVisible: windowState.isSidebarVisible
        )
    }

    private var sidebarDragPinsHoverSidebar: Bool {
        SidebarHoverOverlayDragPinningPolicy.shouldPinHoverSidebar(
            activeWindowID: windowRegistry.activeWindowId,
            currentWindowID: windowState.id,
            isSidebarVisible: windowState.isSidebarVisible,
            isDragging: dragState.isDragging,
            isInternalDragSession: dragState.isInternalDragSession
        )
    }

    private var overlaySidebarRevealed: Bool {
        SidebarHoverOverlayRevealPolicy.isOverlayRevealed(
            isOverlayVisible: hoverManager.isOverlayVisible,
            transientUIPinsHoverSidebar: transientUIPinsHoverSidebar,
            sidebarDragPinsHoverSidebar: sidebarDragPinsHoverSidebar
        )
    }

    private var isCollapsedSidebar: Bool {
        !windowState.isSidebarVisible
    }

    private var shouldMountCollapsedSidebarHost: Bool {
        SidebarHoverOverlayHostMountPolicy.shouldMountCollapsedHost(
            isSidebarVisible: windowState.isSidebarVisible,
            isOverlayVisible: hoverManager.isOverlayVisible,
            isOverlayHostPrewarmed: hoverManager.isOverlayHostPrewarmed,
            transientUIPinsHoverSidebar: transientUIPinsHoverSidebar,
            sidebarDragPinsHoverSidebar: sidebarDragPinsHoverSidebar
        )
    }

    private var pinnedInteractionRequestsHostRetention: Bool {
        transientUIPinsHoverSidebar || sidebarDragPinsHoverSidebar
    }

    private var overlayBaseSidebarWidth: CGFloat {
        SidebarPresentationContext.collapsedSidebarWidth(
            sidebarWidth: windowState.sidebarWidth,
            savedSidebarWidth: windowState.savedSidebarWidth
        )
    }

    private var presentationContext: SidebarPresentationContext {
        if overlaySidebarRevealed {
            return .collapsedVisible(
                sidebarWidth: overlayBaseSidebarWidth,
                sidebarPosition: sumiSettings.sidebarPosition
            )
        }

        return .collapsedHidden(
            sidebarWidth: overlayBaseSidebarWidth,
            sidebarPosition: sumiSettings.sidebarPosition
        )
    }

    var body: some View {
        Group {
            if isCollapsedSidebar {
                ZStack(alignment: presentationContext.shellEdge.overlayAlignment) {
                    // Full-window layout without hit-testing so points outside the edge strip and sidebar host
                    // are not absorbed by an implicit full-screen hit target.
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)

                    Color.clear
                        .frame(width: hoverManager.triggerWidth)
                        .contentShape(Rectangle())
                        .onHover { isIn in
                            if isIn && isCollapsedSidebar {
                                hoverManager.requestOverlayReveal(
                                    animationDuration: SidebarHoverOverlayMetrics.revealAnimationDuration
                                )
                            }
                            NSCursor.arrow.set()
                        }

                    collapsedOverlayHost
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: presentationContext.shellEdge.frameAlignment
                )
            }
        }
        .onChange(of: presentationContext) { _, _ in
            SidebarDragState.shared.requestGeometryRefresh()
        }
        .onAppear {
            hoverManager.retainOverlayHostWhileCollapsed()
            retainOverlayHostIfPinned()
        }
        .onChange(of: pinnedInteractionRequestsHostRetention) { _, isPinned in
            if isPinned {
                retainOverlayHostIfPinned()
            }
        }
    }

    private var collapsedOverlayHost: some View {
        CollapsedSidebarOverlayHost(
            browserManager: browserManager,
            windowState: windowState,
            windowRegistry: windowRegistry,
            commandPalette: commandPalette,
            sumiSettings: sumiSettings,
            resolvedThemeContext: resolvedThemeContext,
            chromeBackgroundResolvedThemeContext: chromeBackgroundResolvedThemeContext,
            presentationContext: presentationContext,
            isHostRequested: shouldMountCollapsedSidebarHost
        )
        .id("collapsed-sidebar-overlay-host")
        .frame(width: overlayBaseSidebarWidth)
        .frame(maxHeight: .infinity)
    }

    private func retainOverlayHostIfPinned() {
        if pinnedInteractionRequestsHostRetention {
            hoverManager.retainOverlayHostForPinnedInteraction()
        }
    }
}
