//
//  SidebarHoverOverlayView.swift
//  Sumi
//
//

import AppKit
import Combine
import SwiftUI

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
        isOverlayVisible
            || transientUIPinsHoverSidebar
            || sidebarDragPinsHoverSidebar
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

enum SidebarHoverOverlayStartupEmptyStatePolicy {
    static func shouldBootstrapVisible(
        isStartupEmptyStateSyncPending: Bool,
        isSidebarVisible: Bool,
        isShowingEmptyState: Bool
    ) -> Bool {
        isStartupEmptyStateSyncPending
            && !isSidebarVisible
            && isShowingEmptyState
    }

    static func shouldAnimateEmptyStateSync(
        isStartupEmptyStateSyncPending: Bool
    ) -> Bool {
        !isStartupEmptyStateSyncPending
    }

    static func effectiveOverlayVisible(
        isStartupEmptyStateSyncPending: Bool,
        isOverlayVisible: Bool,
        startupEmptyStateBootstrapVisible: Bool
    ) -> Bool {
        // While startup is still pending, the only thing allowed to reveal the
        // collapsed overlay is the empty-state bootstrap. Ignoring the manager's
        // live visibility here guarantees the host is never mounted-then-revealed
        // during launch (which would animate the reveal).
        if isStartupEmptyStateSyncPending {
            return startupEmptyStateBootstrapVisible
        }
        return isOverlayVisible
    }

    static func effectiveOverlayHostPrewarmed(
        isStartupEmptyStateSyncPending: Bool,
        isOverlayHostPrewarmed: Bool,
        startupEmptyStateBootstrapVisible: Bool
    ) -> Bool {
        // During startup, suppress the prewarmed-hidden mount so the collapsed
        // host stays unmounted until the empty-state bootstrap reveals it. That
        // way it mounts fresh already at full reveal (no hidden→visible slide).
        if isStartupEmptyStateSyncPending {
            return startupEmptyStateBootstrapVisible
        }
        return isOverlayHostPrewarmed
    }
}

enum SidebarHoverOverlayMetrics {
    static let cornerRadius: CGFloat = 12
    static let revealAnimationDuration: TimeInterval = HoverSidebarCompactMetrics.revealAnimationDuration
}

struct SidebarHoverOverlayView: View {
    let resolvedThemeContext: ResolvedThemeContext
    let chromeBackgroundResolvedThemeContext: ResolvedThemeContext
    let windowChromeSize: CGSize
    let browserContext: SidebarBrowserContext
    let updaterService: SumiUpdaterService
    let hostActions: SidebarHostActions
    let structuralInvalidation: AnyPublisher<Void, Never>
    @ObservedObject private var dragState: SidebarDragState

    @EnvironmentObject var hoverManager: HoverSidebarManager
    @EnvironmentObject private var nowPlayingController: SumiNativeNowPlayingController
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.sumiSettings) private var sumiSettings
    @State private var isStartupEmptyStateSyncPending = true

    init(
        resolvedThemeContext: ResolvedThemeContext,
        chromeBackgroundResolvedThemeContext: ResolvedThemeContext,
        windowChromeSize: CGSize,
        browserContext: SidebarBrowserContext,
        updaterService: SumiUpdaterService,
        hostActions: SidebarHostActions,
        structuralInvalidation: AnyPublisher<Void, Never>,
        sidebarDragState: SidebarDragState
    ) {
        self.resolvedThemeContext = resolvedThemeContext
        self.chromeBackgroundResolvedThemeContext = chromeBackgroundResolvedThemeContext
        self.windowChromeSize = windowChromeSize
        self.browserContext = browserContext
        self.updaterService = updaterService
        self.hostActions = hostActions
        self.structuralInvalidation = structuralInvalidation
        self._dragState = ObservedObject(wrappedValue: sidebarDragState)
    }

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

    private var emptyStateRequestsCollapsedSidebar: Bool {
        !windowState.isSidebarVisible && windowState.isShowingEmptyState
    }

    private var startupEmptyStateBootstrapVisible: Bool {
        SidebarHoverOverlayStartupEmptyStatePolicy.shouldBootstrapVisible(
            isStartupEmptyStateSyncPending: isStartupEmptyStateSyncPending,
            isSidebarVisible: windowState.isSidebarVisible,
            isShowingEmptyState: windowState.isShowingEmptyState
        )
    }

    private var effectiveOverlayVisible: Bool {
        SidebarHoverOverlayStartupEmptyStatePolicy.effectiveOverlayVisible(
            isStartupEmptyStateSyncPending: isStartupEmptyStateSyncPending,
            isOverlayVisible: hoverManager.isOverlayVisible,
            startupEmptyStateBootstrapVisible: startupEmptyStateBootstrapVisible
        )
    }

    private var effectiveOverlayHostPrewarmed: Bool {
        SidebarHoverOverlayStartupEmptyStatePolicy.effectiveOverlayHostPrewarmed(
            isStartupEmptyStateSyncPending: isStartupEmptyStateSyncPending,
            isOverlayHostPrewarmed: hoverManager.isOverlayHostPrewarmed,
            startupEmptyStateBootstrapVisible: startupEmptyStateBootstrapVisible
        )
    }

    private var overlaySidebarRevealed: Bool {
        SidebarHoverOverlayRevealPolicy.isOverlayRevealed(
            isOverlayVisible: effectiveOverlayVisible,
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
            isOverlayVisible: effectiveOverlayVisible,
            isOverlayHostPrewarmed: effectiveOverlayHostPrewarmed,
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
                                hoverManager.requestPointerOverlayReveal(
                                    animationDuration: SidebarHoverOverlayMetrics.revealAnimationDuration,
                                    sidebarPosition: sumiSettings.sidebarPosition
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
            dragState.requestGeometryRefresh()
        }
        .onAppear {
            if emptyStateRequestsCollapsedSidebar {
                syncEmptyStateOverlayForce(animated: false)
            } else {
                hoverManager.deferOverlayHostRetentionWhileCollapsed()
            }
            retainOverlayHostIfPinned()
            completeStartupEmptyStateSyncIfResolved()
        }
        .onDisappear {
            hoverManager.releaseEmptyStateOverlayForce(
                animated: false,
                sidebarPosition: sumiSettings.sidebarPosition
            )
        }
        .onChange(of: emptyStateRequestsCollapsedSidebar) { _, _ in
            syncEmptyStateOverlayForce(
                animated: SidebarHoverOverlayStartupEmptyStatePolicy.shouldAnimateEmptyStateSync(
                    isStartupEmptyStateSyncPending: isStartupEmptyStateSyncPending
                )
            )
        }
        .onChange(of: windowState.isAwaitingInitialSessionResolution) { _, _ in
            completeStartupEmptyStateSyncIfResolved()
        }
        .onChange(of: pinnedInteractionRequestsHostRetention) { _, isPinned in
            if isPinned {
                retainOverlayHostIfPinned()
            }
        }
    }

    private var collapsedOverlayHost: some View {
        CollapsedSidebarOverlayHost(
            browserContext: browserContext,
            updaterService: updaterService,
            hostActions: hostActions,
            structuralInvalidation: structuralInvalidation,
            windowState: windowState,
            windowRegistry: windowRegistry,
            sumiSettings: sumiSettings,
            nowPlayingController: nowPlayingController,
            resolvedThemeContext: resolvedThemeContext,
            chromeBackgroundResolvedThemeContext: chromeBackgroundResolvedThemeContext,
            windowChromeSize: windowChromeSize,
            sidebarDragState: dragState,
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

    private func syncEmptyStateOverlayForce(animated: Bool) {
        if emptyStateRequestsCollapsedSidebar {
            hoverManager.forceOverlayVisibleForEmptyState(
                animated: animated,
                sidebarPosition: sumiSettings.sidebarPosition
            )
        } else {
            hoverManager.releaseEmptyStateOverlayForce(
                animated: animated,
                sidebarPosition: sumiSettings.sidebarPosition
            )
        }
    }

    private func completeStartupEmptyStateSyncIfResolved() {
        guard isStartupEmptyStateSyncPending,
              !windowState.isAwaitingInitialSessionResolution
        else { return }

        if emptyStateRequestsCollapsedSidebar {
            syncEmptyStateOverlayForce(animated: false)
        }

        isStartupEmptyStateSyncPending = false
    }
}
