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

enum SidebarHoverOverlayMetrics {
    static let cornerRadius: CGFloat = 12
    static let hiddenPadding: CGFloat = 18
}

struct SidebarHoverOverlayView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var hoverManager: HoverSidebarManager
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

    private var overlaySidebarRevealed: Bool {
        hoverManager.isOverlayVisible || transientUIPinsHoverSidebar
    }

    private var isCollapsedSidebar: Bool {
        !windowState.isSidebarVisible
    }

    private var overlayBaseSidebarWidth: CGFloat {
        SidebarPresentationContext.collapsedSidebarWidth(
            sidebarWidth: windowState.sidebarWidth,
            savedSidebarWidth: windowState.savedSidebarWidth
        )
    }

    private var presentationContext: SidebarPresentationContext {
        if windowState.isSidebarVisible {
            return .docked(sidebarWidth: windowState.sidebarWidth)
        }

        if overlaySidebarRevealed {
            return .collapsedVisible(sidebarWidth: overlayBaseSidebarWidth)
        }

        return .collapsedHidden(sidebarWidth: overlayBaseSidebarWidth)
    }

    private var hiddenOffset: CGFloat {
        let distance = presentationContext.sidebarWidth + SidebarHoverOverlayMetrics.hiddenPadding
        return -distance
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
        ZStack(alignment: .leading) {
            // Full-window layout without hit-testing so points outside the edge strip and sidebar host
            // are not absorbed by an implicit full-screen hit target.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

            if isCollapsedSidebar {
                Color.clear
                    .frame(width: hoverManager.triggerWidth)
                    .contentShape(Rectangle())
                    .onHover { isIn in
                        if isIn && isCollapsedSidebar {
                            withAnimation(.easeInOut(duration: 0.12)) {
                                hoverManager.isOverlayVisible = true
                            }
                        }
                        NSCursor.arrow.set()
                    }
            }

            sidebarHost
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: presentationContext) { _, _ in
            SidebarDragState.shared.requestGeometryRefresh()
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
