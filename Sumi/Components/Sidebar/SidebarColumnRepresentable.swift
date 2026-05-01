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
            .sidebarHostEnvironment(environmentContext)
            .environment(\.sidebarPresentationContext, presentationContext)
            // `NSHostingController` roots do not inherit `ContentView`’s `.ignoresSafeArea`; without this,
            // macOS reserves a title-bar safe area above the sidebar chrome when using `fullSizeContentView`.
            .ignoresSafeArea(.container, edges: .top)
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
        trafficLightRenderState: BrowserWindowTrafficLightRenderState,
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
                trafficLightRenderState: trafficLightRenderState
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
    var trafficLightRenderState: BrowserWindowTrafficLightRenderState
    var presentationContext: SidebarPresentationContext

    func makeNSViewController(context: Context) -> SidebarColumnViewController {
        SidebarColumnViewController()
    }

    func updateNSViewController(_ controller: SidebarColumnViewController, context: Context) {
        let root = SidebarColumnHostedRoot.view(
            browserManager: browserManager,
            windowState: windowState,
            windowRegistry: windowRegistry,
            commandPalette: commandPalette,
            sumiSettings: sumiSettings,
            resolvedThemeContext: resolvedThemeContext,
            trafficLightRenderState: trafficLightRenderState,
            presentationContext: presentationContext
        )
        controller.updateHostedSidebar(
            root: root,
            width: presentationContext.sidebarWidth,
            contextMenuController: windowState.sidebarContextMenuController,
            capturesPanelBackgroundPointerEvents: presentationContext.capturesPanelBackgroundPointerEvents
        )
        #if DEBUG
        SidebarDebugMetrics.recordCollapsedSidebarHost(
            controller: controller,
            presentationMode: presentationContext.mode,
            isMounted: presentationContext.isCollapsedOverlay
        )
        #endif
        controller.updateWebContentInputExclusion(
            presentationContext: presentationContext,
            windowState: windowState
        )
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
