import AppKit
import SwiftUI

struct SidebarColumnHostedRootView: View {
    let environmentContext: SidebarHostEnvironmentContext
    let presentationContext: SidebarPresentationContext

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
                collapsedSidebarChromeBackground
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
        if presentationContext.isCollapsedOverlay {
            let backgroundThemeContext = environmentContext.chromeBackgroundResolvedThemeContext

            ZStack {
                backgroundThemeContext
                    .tokens(settings: environmentContext.sumiSettings)
                    .windowBackground
                    .opacity(presentationContext.mode == .collapsedVisible ? 1 : 0)
                SpaceGradientBackgroundView(surface: .toolbarChrome)
                    .environmentObject(environmentContext.browserManager)
                    .environment(environmentContext.windowState)
                    .environment(\.sumiSettings, environmentContext.sumiSettings)
                    .environment(\.resolvedThemeContext, backgroundThemeContext)
                    .opacity(presentationContext.mode == .collapsedVisible ? 1 : 0)
            }
        }
    }
}

enum SidebarColumnHostedRoot {
    @MainActor
    static func view(
        browserManager: BrowserManager,
        windowState: BrowserWindowState,
        windowRegistry: WindowRegistry,
        commandPalette: CommandPalette,
        sumiSettings: SumiSettingsService,
        resolvedThemeContext: ResolvedThemeContext,
        chromeBackgroundResolvedThemeContext: ResolvedThemeContext,
        presentationContext: SidebarPresentationContext
    ) -> SidebarColumnHostedRootView {
        SidebarColumnHostedRootView(
            environmentContext: SidebarHostEnvironmentContext(
                browserManager: browserManager,
                windowState: windowState,
                windowRegistry: windowRegistry,
                commandPalette: commandPalette,
                sumiSettings: sumiSettings,
                resolvedThemeContext: resolvedThemeContext,
                chromeBackgroundResolvedThemeContext: chromeBackgroundResolvedThemeContext
            ),
            presentationContext: presentationContext
        )
    }
}

struct SidebarColumnRepresentable: NSViewControllerRepresentable {
    @ObservedObject var browserManager: BrowserManager
    var windowState: BrowserWindowState
    var windowRegistry: WindowRegistry
    var commandPalette: CommandPalette
    var sumiSettings: SumiSettingsService
    var resolvedThemeContext: ResolvedThemeContext
    var chromeBackgroundResolvedThemeContext: ResolvedThemeContext
    var presentationContext: SidebarPresentationContext

    func makeNSViewController(context: Context) -> SidebarColumnViewController {
        SidebarColumnViewController(usesCollapsedPanelRoot: presentationContext.isCollapsedOverlay)
    }

    func updateNSViewController(_ controller: SidebarColumnViewController, context: Context) {
        let root = SidebarColumnHostedRoot.view(
            browserManager: browserManager,
            windowState: windowState,
            windowRegistry: windowRegistry,
            commandPalette: commandPalette,
            sumiSettings: sumiSettings,
            resolvedThemeContext: resolvedThemeContext,
            chromeBackgroundResolvedThemeContext: chromeBackgroundResolvedThemeContext,
            presentationContext: presentationContext
        )
        controller.updateHostedSidebar(
            root: root,
            width: presentationContext.sidebarWidth,
            contextMenuController: windowState.sidebarContextMenuController,
            capturesPanelBackgroundPointerEvents: presentationContext.capturesPanelBackgroundPointerEvents,
            isCollapsedPanelHitTestingEnabled: presentationContext.mode == .collapsedVisible,
            onPointerDown: { [weak browserManager] in
                browserManager?.dismissWorkspaceThemePickerIfNeededCommitting()
            }
        )
        #if DEBUG
        SidebarDebugMetrics.recordCollapsedSidebarHost(
            controller: controller,
            presentationMode: presentationContext.mode,
            isMounted: presentationContext.isCollapsedOverlay
        )
        #endif
    }

    static func dismantleNSViewController(_ nsViewController: SidebarColumnViewController, coordinator: ()) {
        #if DEBUG
        SidebarDebugMetrics.recordCollapsedHiddenSidebarHost(
            controller: nsViewController,
            isMounted: false
        )
        #endif
        nsViewController.teardownSidebarHosting()
    }
}
