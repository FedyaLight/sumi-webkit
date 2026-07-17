import AppKit
import SwiftUI

struct SidebarColumnHostedRootView: View {
    let environmentContext: SidebarHostEnvironmentContext
    let presentationContext: SidebarPresentationContext
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
    @Environment(\.accessibilityReduceTransparency) private var accessibilityReduceTransparency

    var body: some View {
        SpacesSideBarView(
            browserContext: environmentContext.browserContext,
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
            nowPlayingController: environmentContext.nowPlayingController,
            updaterService: environmentContext.updaterService
        )
            .frame(width: presentationContext.sidebarWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    if presentationContext.isCollapsedOverlay {
                        chromeTokens.windowBackground
                    }
                    collapsedSidebarChromeBackground
                }
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: presentationContext.isCollapsedOverlay
                        ? SidebarHoverOverlayMetrics.cornerRadius
                        : 0,
                    style: .continuous
                )
            )
            .sidebarHostEnvironment(environmentContext)
            .environment(\.sidebarPresentationContext, presentationContext)
            // `NSHostingController` roots do not inherit `ContentView`’s `.ignoresSafeArea`; without this,
            // macOS reserves a title-bar safe area above the sidebar chrome when using `fullSizeContentView`.
            .ignoresSafeArea(.container, edges: .top)
    }

    @ViewBuilder
    private var collapsedSidebarChromeBackground: some View {
        if presentationContext.mode == .docked {
            dockedSidebarChromeBackground
        } else if environmentContext.chromeBackgroundResolvedThemeContext.rendersCustomChromeTheme {
            SpaceGradientBackgroundView(
                surface: .toolbarChrome,
                nativeMaterialRole: .collapsedSidebar,
                gradientFieldSize: resolvedGradientFieldSize,
                viewport: sidebarGradientViewport
            )
            .environment(environmentContext.windowState)
            .environment(\.sumiSettings, environmentContext.sumiSettings)
            .environment(\.resolvedThemeContext, environmentContext.chromeBackgroundResolvedThemeContext)
        } else if accessibilityReduceTransparency {
            chromeTokens.windowBackground
        } else {
            let context = environmentContext.chromeBackgroundResolvedThemeContext
            let usesTransition = context.isInteractiveTransition || !context.sourceWorkspaceTheme.visuallyEquals(context.targetWorkspaceTheme)
            if usesTransition && context.sourceChromeColorScheme != context.targetChromeColorScheme {
                ZStack {
                    NativeChromeMaterialBackground(role: .collapsedSidebar)

                    let currentScheme = context.nativeSurfaceColorScheme
                    let isCurrentLight = currentScheme == .light
                    let maxOpacity: Double = isCurrentLight ? 0.35 : 0.20
                    let overlayColor = SidebarThemeTokens.Colors.collapsedSidebarTransitionOverlay(
                        isNativeSurfaceLight: isCurrentLight
                    )

                    let factor: Double = {
                        if context.transitionProgress < 0.5 {
                            return context.transitionProgress / 0.5
                        } else {
                            return (1.0 - context.transitionProgress) / 0.5
                        }
                    }()

                    overlayColor
                        .opacity(factor * maxOpacity)
                }
            } else {
                NativeChromeMaterialBackground(role: .collapsedSidebar)
            }
        }
    }

    @ViewBuilder
    private var dockedSidebarChromeBackground: some View {
        if environmentContext.chromeBackgroundResolvedThemeContext.rendersCustomChromeTheme {
            Color.clear
        } else if accessibilityReduceTransparency {
            chromeTokens.windowBackground
        } else {
            Color.clear
        }
    }

    private var chromeTokens: ChromeThemeTokens {
        environmentContext.chromeBackgroundResolvedThemeContext.tokens(settings: environmentContext.sumiSettings)
    }

    private var resolvedGradientFieldSize: CGSize? {
        let measuredSize = environmentContext.windowChromeSize
        guard measuredSize.width > 0, measuredSize.height > 0 else {
            return nil
        }
        return measuredSize
    }

    private var sidebarGradientViewport: SpaceGradientViewport {
        let fieldWidth = max(resolvedGradientFieldSize?.width ?? presentationContext.sidebarWidth, 1)
        let viewportWidth = min(max(presentationContext.sidebarWidth / fieldWidth, 0), 1)
        let originX = presentationContext.shellEdge.isLeft
            ? 0
            : max(1 - viewportWidth, 0)
        return SpaceGradientViewport(
            origin: UnitPoint(x: originX, y: 0),
            size: CGSize(width: viewportWidth, height: 1)
        )
    }
}

enum SidebarColumnHostedRoot {
    @MainActor
    static func view(
        environmentContext: SidebarHostEnvironmentContext,
        presentationContext: SidebarPresentationContext,
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
        profileUpdates: SidebarProfileUpdates
    ) -> SidebarColumnHostedRootView {
        SidebarColumnHostedRootView(
            environmentContext: environmentContext,
            presentationContext: presentationContext,
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
            profileUpdates: profileUpdates
        )
    }
}

struct SidebarColumnRepresentable: NSViewControllerRepresentable {
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
    var collapsedShadowAnimationDuration: TimeInterval = 0

    private var environmentContext: SidebarHostEnvironmentContext {
        SidebarHostEnvironmentContext(
            browserContext: browserContext,
            hostActions: hostActions,
            windowState: windowState,
            windowRegistry: windowRegistry,
            sumiSettings: sumiSettings,
            nowPlayingController: nowPlayingController,
            updaterService: updaterService,
            resolvedThemeContext: resolvedThemeContext,
            chromeBackgroundResolvedThemeContext: chromeBackgroundResolvedThemeContext,
            windowChromeSize: windowChromeSize,
            sidebarDragState: sidebarDragState
        )
    }

    private var resizeGrabberColor: NSColor {
        let tokens = resolvedThemeContext.tokens(settings: sumiSettings)
        let accentColor = NSColor(tokens.accent).usingColorSpace(.displayP3)
            ?? NSColor(tokens.accent).usingColorSpace(.sRGB)
            ?? .controlAccentColor
        return ChromePageLoadingIndicatorStyle.fillColor(
            accentColor: accentColor,
            isDarkTheme: ChromePageLoadingIndicatorStyle.isDarkTheme(
                workspaceTheme: resolvedThemeContext.workspaceTheme,
                fallbackColorScheme: resolvedThemeContext.globalColorScheme
            )
        )
    }

    func makeNSViewController(context: Context) -> SidebarColumnViewController {
        SidebarColumnViewController(
            usesCollapsedOverlayRoot: presentationContext.isCollapsedOverlay,
            sidebarRecoveryCoordinator: windowState.sidebarContextMenuController.sidebarRecoveryCoordinator
        )
    }

    func updateNSViewController(_ controller: SidebarColumnViewController, context: Context) {
        windowState.sidebarContextMenuController.settings = sumiSettings
        let root = SidebarColumnHostedRoot.view(
            environmentContext: environmentContext,
            presentationContext: presentationContext,
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
            profileUpdates: profileUpdates
        )
        controller.updateHostedSidebar(
            root: root,
            width: presentationContext.sidebarWidth,
            contextMenuController: windowState.sidebarContextMenuController,
            capturesOverlayBackgroundPointerEvents: presentationContext.capturesOverlayBackgroundPointerEvents,
            isCollapsedOverlayVisible: presentationContext.mode == .collapsedVisible,
            collapsedShadowAnimationDuration: context.transaction.animation == nil
                ? 0
                : collapsedShadowAnimationDuration,
            showsResizeHandle: presentationContext.showsResizeHandle,
            sidebarPosition: presentationContext.sidebarPosition,
            resizeGrabberColor: resizeGrabberColor,
            windowState: windowState,
            onResize: hostActions.updateSidebarWidth,
            onEndResize: hostActions.persistWindowSession,
            onPointerDown: {
                hostActions.dismissThemePickerCommittingIfNeeded()
            }
        )
    }

    static func dismantleNSViewController(_ nsViewController: SidebarColumnViewController, coordinator: ()) {
        nsViewController.teardownSidebarHosting()
    }
}
