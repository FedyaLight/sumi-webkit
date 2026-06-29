import AppKit
import SwiftUI

struct SidebarColumnHostedRootView: View {
    let environmentContext: SidebarHostEnvironmentContext
    let presentationContext: SidebarPresentationContext
    @Environment(\.accessibilityReduceTransparency) private var accessibilityReduceTransparency

    var body: some View {
        SpacesSideBarView()
            .frame(width: presentationContext.sidebarWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: presentationContext.shellEdge.resizeHandleAlignment) {
                if presentationContext.showsResizeHandle {
                    SidebarResizeView(sidebarPosition: presentationContext.sidebarPosition)
                        .frame(maxHeight: .infinity)
                        .zIndex(2000)
                }
            }
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
            .environmentObject(environmentContext.browserManager)
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
                    let overlayColor = isCurrentLight ? Color.black : Color.white

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
        browserManager: BrowserManager,
        windowState: BrowserWindowState,
        windowRegistry: WindowRegistry,
        sumiSettings: SumiSettingsService,
        resolvedThemeContext: ResolvedThemeContext,
        chromeBackgroundResolvedThemeContext: ResolvedThemeContext,
        windowChromeSize: CGSize,
        sidebarDragState: SidebarDragState,
        presentationContext: SidebarPresentationContext
    ) -> SidebarColumnHostedRootView {
        SidebarColumnHostedRootView(
            environmentContext: SidebarHostEnvironmentContext(
                browserManager: browserManager,
                windowState: windowState,
                windowRegistry: windowRegistry,
                sumiSettings: sumiSettings,
                resolvedThemeContext: resolvedThemeContext,
                chromeBackgroundResolvedThemeContext: chromeBackgroundResolvedThemeContext,
                windowChromeSize: windowChromeSize,
                sidebarDragState: sidebarDragState
            ),
            presentationContext: presentationContext
        )
    }
}

struct SidebarColumnRepresentable: NSViewControllerRepresentable {
    @ObservedObject var browserManager: BrowserManager
    var windowState: BrowserWindowState
    var windowRegistry: WindowRegistry
    var sumiSettings: SumiSettingsService
    var resolvedThemeContext: ResolvedThemeContext
    var chromeBackgroundResolvedThemeContext: ResolvedThemeContext
    var windowChromeSize: CGSize
    var sidebarDragState: SidebarDragState = SidebarDragState.shared
    var presentationContext: SidebarPresentationContext

    func makeNSViewController(context: Context) -> SidebarColumnViewController {
        SidebarColumnViewController(usesCollapsedOverlayRoot: presentationContext.isCollapsedOverlay)
    }

    func updateNSViewController(_ controller: SidebarColumnViewController, context: Context) {
        let root = SidebarColumnHostedRoot.view(
            browserManager: browserManager,
            windowState: windowState,
            windowRegistry: windowRegistry,
            sumiSettings: sumiSettings,
            resolvedThemeContext: resolvedThemeContext,
            chromeBackgroundResolvedThemeContext: chromeBackgroundResolvedThemeContext,
            windowChromeSize: windowChromeSize,
            sidebarDragState: sidebarDragState,
            presentationContext: presentationContext
        )
        controller.updateHostedSidebar(
            root: root,
            width: presentationContext.sidebarWidth,
            contextMenuController: windowState.sidebarContextMenuController,
            capturesOverlayBackgroundPointerEvents: presentationContext.capturesOverlayBackgroundPointerEvents,
            isCollapsedOverlayHitTestingEnabled: presentationContext.mode == .collapsedVisible,
            onPointerDown: { [weak browserManager] in
                browserManager?.dismissWorkspaceThemePickerIfNeededCommitting()
            }
        )
    }

    static func dismantleNSViewController(_ nsViewController: SidebarColumnViewController, coordinator: ()) {
        nsViewController.teardownSidebarHosting()
    }
}
