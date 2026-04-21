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

    static func shouldPinHoverSidebar(
        sessionHostWindowID: UUID?,
        currentWindowID: UUID,
        isSidebarVisible: Bool
    ) -> Bool {
        shouldPinHoverSidebar(
            transientWindowID: sessionHostWindowID,
            currentWindowID: currentWindowID,
            isSidebarVisible: isSidebarVisible
        )
    }
}

typealias SidebarHoverOverlayThemePinningPolicy = SidebarHoverOverlayTransientPinningPolicy

enum SidebarHoverOverlayMetrics {
    static let cornerRadius: CGFloat = 12
    static let horizontalInset: CGFloat = 7
    static let verticalInset: CGFloat = 7
    static let hiddenPadding: CGFloat = 18
    static let revealedWidthBoost: CGFloat = 18

    static func revealedWidth(
        sidebarWidth: CGFloat,
        savedSidebarWidth: CGFloat
    ) -> CGFloat {
        max(sidebarWidth, savedSidebarWidth) + revealedWidthBoost
    }
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
        max(windowState.sidebarWidth, windowState.savedSidebarWidth)
    }

    private var overlaySidebarWidth: CGFloat {
        SidebarHoverOverlayMetrics.revealedWidth(
            sidebarWidth: overlayBaseSidebarWidth,
            savedSidebarWidth: overlayBaseSidebarWidth
        )
    }

    private var presentationContext: SidebarPresentationContext {
        if windowState.isSidebarVisible {
            return .docked(sidebarWidth: windowState.sidebarWidth)
        }

        if overlaySidebarRevealed {
            return .collapsedVisible(
                sidebarWidth: overlayBaseSidebarWidth,
                shellWidth: overlaySidebarWidth
            )
        }

        return .collapsedHidden(
            sidebarWidth: overlayBaseSidebarWidth,
            shellWidth: overlaySidebarWidth
        )
    }

    private var hiddenOffset: CGFloat {
        let distance = overlaySidebarWidth + SidebarHoverOverlayMetrics.horizontalInset + SidebarHoverOverlayMetrics.hiddenPadding
        return -distance
    }

    private var usesCollapsedChrome: Bool {
        presentationContext.isCollapsedOverlay
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
        .frame(width: presentationContext.shellWidth)
        .frame(maxHeight: .infinity)
        .background {
            ZStack {
                // Opaque chrome base (matches `WindowBackground`) so web content does not show through.
                themeContext.tokens(settings: sumiSettings).windowBackground
                    .opacity(usesCollapsedChrome ? 1 : 0)
                SpaceGradientBackgroundView()
                    .environmentObject(browserManager)
                    .environment(windowState)
                    .opacity(usesCollapsedChrome ? 1 : 0)
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
        .padding(.leading, usesCollapsedChrome ? SidebarHoverOverlayMetrics.horizontalInset : 0)
        .padding(.top, usesCollapsedChrome ? 4 : 0)
        .padding(.bottom, usesCollapsedChrome ? SidebarHoverOverlayMetrics.verticalInset : 0)
        .offset(x: sidebarPanelOffset)
        .opacity(sidebarPanelOpacity)
        .allowsHitTesting(sidebarPanelAllowsHitTesting)
        .accessibilityHidden(presentationContext.mode == .collapsedHidden)
    }
}
