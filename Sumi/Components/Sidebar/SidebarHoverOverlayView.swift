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
    static let hiddenPadding: CGFloat = 18
    static let revealAnimationDuration: TimeInterval = 0.12
}

struct SidebarHoverOverlayView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var hoverManager: HoverSidebarManager
    @EnvironmentObject private var trafficLightRenderState: BrowserWindowTrafficLightRenderState
    @ObservedObject private var dragState = SidebarDragState.shared
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(CommandPalette.self) private var commandPalette
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

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

    private var hiddenOffset: CGFloat {
        presentationContext.shellEdge.hiddenOffset(
            sidebarWidth: presentationContext.sidebarWidth,
            hiddenPadding: SidebarHoverOverlayMetrics.hiddenPadding
        )
    }

    private var usesCollapsedChrome: Bool {
        presentationContext.isCollapsedOverlay
    }

    private var drawsCollapsedSidebarChromeBackground: Bool {
        presentationContext.mode == .collapsedVisible
    }

    private var sidebarPanelOffset: CGFloat {
        presentationContext.mode == .collapsedHidden ? hiddenOffset : 0
    }

    private var sidebarPanelOpacity: Double {
        presentationContext.mode == .collapsedHidden ? 0 : 1
    }

    private var sidebarPanelAllowsHitTesting: Bool {
        presentationContext.mode != .collapsedHidden
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

                    if shouldMountCollapsedSidebarHost {
                        sidebarHost
                    }
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
        .onDisappear {
            windowState.updateWebContentInputExclusionRegion(.empty)
        }
    }

    private var sidebarHost: some View {
        SidebarColumnRepresentable(
            browserManager: browserManager,
            windowState: windowState,
            windowRegistry: windowRegistry,
            commandPalette: commandPalette,
            sumiSettings: sumiSettings,
            resolvedThemeContext: themeContext,
            trafficLightRenderState: trafficLightRenderState,
            presentationContext: presentationContext
        )
        .id("shared-sidebar-column")
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
        .frame(width: presentationContext.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background {
            ZStack {
                themeContext.tokens(settings: sumiSettings).windowBackground
                    .opacity(drawsCollapsedSidebarChromeBackground ? 1 : 0)
                SpaceGradientBackgroundView(surface: .toolbarChrome)
                    .environmentObject(browserManager)
                    .environment(windowState)
                    .opacity(drawsCollapsedSidebarChromeBackground ? 1 : 0)
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: usesCollapsedChrome ? SidebarHoverOverlayMetrics.cornerRadius : 0,
                    style: .continuous
                )
            )
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: usesCollapsedChrome ? SidebarHoverOverlayMetrics.cornerRadius : 0,
                style: .continuous
            )
        )
        .compositingGroup()
        .zIndex(5000)
        .alwaysArrowCursor()
        .offset(x: sidebarPanelOffset)
        .opacity(sidebarPanelOpacity)
        .allowsHitTesting(sidebarPanelAllowsHitTesting)
        .accessibilityHidden(presentationContext.mode == .collapsedHidden)
    }
}
