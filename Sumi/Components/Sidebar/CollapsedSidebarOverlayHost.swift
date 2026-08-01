import SwiftUI

private struct ZenCompactSidebarOffset: @preconcurrency AnimatableModifier {
    let hiddenOffset: CGFloat
    let usesTravel: Bool
    var revealProgress: CGFloat

    var animatableData: CGFloat {
        get { revealProgress }
        set { revealProgress = newValue }
    }

    func body(content: Content) -> some View {
        content.offset(x: usesTravel ? hiddenOffset * (1 - revealProgress) : 0)
    }
}

struct CollapsedSidebarOverlayHost: View {
    var browserContext: SidebarBrowserContext
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
    var updaterService: SumiUpdaterService
    var hostActions: SidebarHostActions
    var windowState: BrowserWindowState
    var windowRegistry: WindowRegistry
    var sumiSettings: SumiSettingsService
    var nowPlayingController: SumiNativeNowPlayingController
    var resolvedThemeContext: ResolvedThemeContext
    var chromeBackgroundResolvedThemeContext: ResolvedThemeContext
    var windowChromeSize: CGSize
    var sidebarDragState: SidebarDragState
    var presentationContext: SidebarPresentationContext
    var motionMode: SidebarMotionPolicy.Mode
    var isHostRequested: Bool

    private var isRevealed: Bool {
        presentationContext.mode == .collapsedVisible
    }

    private var hiddenOffset: CGFloat {
        presentationContext.shellEdge.isLeft
            ? -presentationContext.sidebarWidth
            : presentationContext.sidebarWidth
    }

    var body: some View {
        let motion = SidebarMotionPolicy.overlayMotion(for: motionMode)
        if isHostRequested {
            ZStack {
                SidebarColumnRepresentable(
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
                    keyboardShortcutManager: keyboardShortcutManager,
                    nowPlayingController: nowPlayingController,
                    resolvedThemeContext: resolvedThemeContext,
                    chromeBackgroundResolvedThemeContext: chromeBackgroundResolvedThemeContext,
                    windowChromeSize: windowChromeSize,
                    sidebarDragState: sidebarDragState,
                    presentationContext: presentationContext,
                    collapsedShadowAnimationDuration: motion.shadowDuration
                )

                if isRevealed {
                    WebContentHoverShieldSensorView()
                }
            }
            .id("collapsed-sidebar-overlay-column")
            .frame(width: presentationContext.sidebarWidth)
            .frame(maxHeight: .infinity)
            .chromeCursor(
                .arrow,
                isEnabled: presentationContext.ownsArrowCursorRegion
            )
            .modifier(ZenCompactSidebarOffset(
                hiddenOffset: hiddenOffset,
                usesTravel: motion.usesTravel,
                revealProgress: isRevealed ? 1 : 0
            ))
            .opacity(isRevealed || motion.usesTravel ? 1 : 0)
            .allowsHitTesting(isRevealed)
            .accessibilityHidden(!isRevealed)
        }
    }

    @Environment(KeyboardShortcutManager.self) private var keyboardShortcutManager
}
