//
//  SidebarHoverOverlayView.swift
//  Sumi
//
//

import SwiftUI

enum SidebarHoverOverlayMetrics {
    static let cornerRadius: CGFloat = 12
    static let shadowOpacity: Float = 0.18
    static let shadowRadius: CGFloat = 8
    static let shadowOffset: CGSize = .zero
}

struct SidebarHoverOverlayView: View {
    let resolvedThemeContext: ResolvedThemeContext
    let chromeBackgroundResolvedThemeContext: ResolvedThemeContext
    let windowChromeSize: CGSize
    let browserContext: SidebarBrowserContext
    let spaceCatalog: SidebarSpaceCatalogProjection
    let inventory: SidebarSpaceInventoryProjection
    let selection: SidebarWindowSelectionQuery
    let pinProjection: SidebarPinFolderProjection
    let pinCommands: SidebarPinCommands
    let pinExecution: SidebarPinExecutionCommands
    let folderCommands: SidebarFolderCommands
    let spaceLifecycle: SidebarSpaceLifecycle
    let regularTabCatalog: SidebarRegularTabCatalog
    let regularTabTargets: SidebarRegularTabTargetQuery
    let regularTabLifecycleCommands: SidebarRegularTabLifecycleCommands
    let regularTabShortcutCommands: SidebarRegularTabShortcutCommands
    let regularTabPlacementCommands: SidebarRegularTabPlacementCommands
    let dragTransactions: SidebarDragTransactionPort
    let inventoryUpdates: SidebarInventoryUpdates
    let profileUpdates: SidebarProfileUpdates
    let updaterService: SumiUpdaterService
    let hostActions: SidebarHostActions
    @ObservedObject private var dragState: SidebarDragState

    @EnvironmentObject var hoverManager: HoverSidebarManager
    @EnvironmentObject private var nowPlayingController: SumiNativeNowPlayingController
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        resolvedThemeContext: ResolvedThemeContext,
        chromeBackgroundResolvedThemeContext: ResolvedThemeContext,
        windowChromeSize: CGSize,
        browserContext: SidebarBrowserContext,
        spaceCatalog: SidebarSpaceCatalogProjection,
        inventory: SidebarSpaceInventoryProjection,
        selection: SidebarWindowSelectionQuery,
        pinProjection: SidebarPinFolderProjection,
        pinCommands: SidebarPinCommands,
        pinExecution: SidebarPinExecutionCommands,
        folderCommands: SidebarFolderCommands,
        spaceLifecycle: SidebarSpaceLifecycle,
        regularTabCatalog: SidebarRegularTabCatalog,
        regularTabTargets: SidebarRegularTabTargetQuery,
        regularTabLifecycleCommands: SidebarRegularTabLifecycleCommands,
        regularTabShortcutCommands: SidebarRegularTabShortcutCommands,
        regularTabPlacementCommands: SidebarRegularTabPlacementCommands,
        dragTransactions: SidebarDragTransactionPort,
        inventoryUpdates: SidebarInventoryUpdates,
        profileUpdates: SidebarProfileUpdates,
        updaterService: SumiUpdaterService,
        hostActions: SidebarHostActions,
        sidebarDragState: SidebarDragState
    ) {
        self.resolvedThemeContext = resolvedThemeContext
        self.chromeBackgroundResolvedThemeContext = chromeBackgroundResolvedThemeContext
        self.windowChromeSize = windowChromeSize
        self.browserContext = browserContext
        self.spaceCatalog = spaceCatalog
        self.inventory = inventory
        self.selection = selection
        self.pinProjection = pinProjection
        self.pinCommands = pinCommands
        self.pinExecution = pinExecution
        self.folderCommands = folderCommands
        self.spaceLifecycle = spaceLifecycle
        self.regularTabCatalog = regularTabCatalog
        self.regularTabTargets = regularTabTargets
        self.regularTabLifecycleCommands = regularTabLifecycleCommands
        self.regularTabShortcutCommands = regularTabShortcutCommands
        self.regularTabPlacementCommands = regularTabPlacementCommands
        self.dragTransactions = dragTransactions
        self.inventoryUpdates = inventoryUpdates
        self.profileUpdates = profileUpdates
        self.updaterService = updaterService
        self.hostActions = hostActions
        self._dragState = ObservedObject(wrappedValue: sidebarDragState)
    }

    /// Keep the hover sidebar on-screen while any sidebar transient UI is alive in compact mode.
    private var transientUIPinsHoverSidebar: Bool {
        windowState.sidebarTransientSessionCoordinator.currentPresentationWindowID
            == windowState.id
            && !windowState.isSidebarVisible
    }

    private var sidebarDragPinsHoverSidebar: Bool {
        windowRegistry.activeWindowId == windowState.id
            && !windowState.isSidebarVisible
            && dragState.isDragging
            && dragState.isInternalDragSession
    }

    private var emptyStateRequestsCollapsedSidebar: Bool {
        !windowState.isSidebarVisible && windowState.isShowingEmptyState
    }

    private var overlaySidebarRevealed: Bool {
        hoverManager.isOverlayVisible
    }

    private var shouldMountCollapsedSidebarHost: Bool {
        !windowState.isSidebarVisible && hoverManager.isOverlayHostPrewarmed
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

    private var motionMode: SidebarMotionPolicy.Mode {
        SidebarMotionPolicy.currentMode(
            reduceMotion: reduceMotion,
            energySaverReducesMotion: sumiSettings.shouldReduceChromeMotion
        )
    }

    var body: some View {
        ZStack(alignment: presentationContext.shellEdge.overlayAlignment) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

            collapsedOverlayHost
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: presentationContext.shellEdge.frameAlignment
        )
        .onChange(of: presentationContext) { _, _ in
            dragState.requestGeometryRefresh()
        }
        .onAppear {
            hoverManager.configureMotionMode(motionMode)
            hoverManager.setStartupResolutionPending(
                windowState.restorationState.isAwaitingInitialResolution
            )
            syncEmptyStateOverlayForce(animated: false)
            syncPinnedInteraction()
        }
        .onDisappear {
            hoverManager.setPinnedInteractionActive(false)
            hoverManager.releaseEmptyStateOverlayForce(
                animated: false,
                sidebarPosition: sumiSettings.sidebarPosition
            )
        }
        .onChange(of: emptyStateRequestsCollapsedSidebar) { _, _ in
            syncEmptyStateOverlayForce(
                animated: !windowState.restorationState.isAwaitingInitialResolution
            )
        }
        .onChange(of: windowState.restorationState.isAwaitingInitialResolution) { _, isPending in
            hoverManager.setStartupResolutionPending(isPending)
            syncEmptyStateOverlayForce(animated: false)
        }
        .onChange(of: pinnedInteractionRequestsHostRetention) { _, _ in
            syncPinnedInteraction()
        }
        .onChange(of: motionMode) { _, newMode in
            hoverManager.configureMotionMode(newMode)
        }
    }

    private var collapsedOverlayHost: some View {
        CollapsedSidebarOverlayHost(
            browserContext: browserContext,
            spaceCatalog: spaceCatalog,
            inventory: inventory,
            selection: selection,
            pinProjection: pinProjection,
            pinCommands: pinCommands,
            pinExecution: pinExecution,
            folderCommands: folderCommands,
            spaceLifecycle: spaceLifecycle,
            regularTabCatalog: regularTabCatalog,
            regularTabTargets: regularTabTargets,
            regularTabLifecycleCommands: regularTabLifecycleCommands,
            regularTabShortcutCommands: regularTabShortcutCommands,
            regularTabPlacementCommands: regularTabPlacementCommands,
            dragTransactions: dragTransactions,
            inventoryUpdates: inventoryUpdates,
            profileUpdates: profileUpdates,
            updaterService: updaterService,
            hostActions: hostActions,
            windowState: windowState,
            windowRegistry: windowRegistry,
            sumiSettings: sumiSettings,
            nowPlayingController: nowPlayingController,
            resolvedThemeContext: resolvedThemeContext,
            chromeBackgroundResolvedThemeContext: chromeBackgroundResolvedThemeContext,
            windowChromeSize: windowChromeSize,
            sidebarDragState: dragState,
            presentationContext: presentationContext,
            motionMode: motionMode,
            isHostRequested: shouldMountCollapsedSidebarHost
        )
        .id("collapsed-sidebar-overlay-host")
        .frame(width: overlayBaseSidebarWidth)
        .frame(maxHeight: .infinity)
    }

    private func syncPinnedInteraction() {
        hoverManager.setPinnedInteractionActive(
            pinnedInteractionRequestsHostRetention
        )
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
}
