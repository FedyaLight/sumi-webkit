import Combine
import Foundation

@MainActor
struct WindowViewBrowserRuntime {
    let splitManager: SplitViewManager
    let findManager: FindManager
    let floatingBarBrowserContext: FloatingBarBrowserContext
    let sidebarBrowserContext: SidebarBrowserContext
    let sidebarHostActions: SidebarHostActions
    let sidebarStructuralInvalidation: AnyPublisher<Void, Never>
    let nativeModalPresentation: () -> BrowserNativeModalPresentation?
    let browsingDataDialogContext: () -> SumiBrowsingDataDialogContext
    let hasCurrentSpace: () -> Bool
    let showGradientEditor: (SidebarTransientPresentationSource) -> Void
    let currentProfileID: () -> UUID?
    let essentialPins: (UUID?) -> [ShortcutPin]
    let attachHoverSidebarManager: (HoverSidebarManager, BrowserWindowState) -> Void
    let websiteViewBrowserContext: (SidebarDragState) -> WebsiteViewBrowserContext
    let websiteNativeSurfaceRootBuilders: () -> WebsiteNativeSurfaceRootBuilders
    let currentTab: (BrowserWindowState) -> Tab?
    let workspaceTheme: (UUID?) -> WorkspaceTheme?
    let isNativeModalPresented: (UUID) -> Bool
    let nativeModalPresentationBindingDismissed: (UUID) -> Void
    let dismissNativeModalPresentation: () -> Void
    let findCurrentTabId: () -> UUID?
}

@MainActor
final class WindowViewBrowserContext {
    private let runtime: WindowViewBrowserRuntime

    init(runtime: WindowViewBrowserRuntime) {
        self.runtime = runtime
    }

    var splitManager: SplitViewManager {
        runtime.splitManager
    }

    var findManager: FindManager {
        runtime.findManager
    }

    var floatingBarBrowserContext: FloatingBarBrowserContext {
        runtime.floatingBarBrowserContext
    }

    var sidebarBrowserContext: SidebarBrowserContext {
        runtime.sidebarBrowserContext
    }

    var sidebarHostActions: SidebarHostActions {
        runtime.sidebarHostActions
    }

    var sidebarStructuralInvalidation: AnyPublisher<Void, Never> {
        runtime.sidebarStructuralInvalidation
    }

    var nativeModalPresentation: BrowserNativeModalPresentation? {
        runtime.nativeModalPresentation()
    }

    var browsingDataDialogContext: SumiBrowsingDataDialogContext {
        runtime.browsingDataDialogContext()
    }

    var hasCurrentSpace: Bool {
        runtime.hasCurrentSpace()
    }

    func showGradientEditor(source: SidebarTransientPresentationSource) {
        runtime.showGradientEditor(source)
    }

    func currentProfileID() -> UUID? {
        runtime.currentProfileID()
    }

    func essentialPins(profileId: UUID?) -> [ShortcutPin] {
        runtime.essentialPins(profileId)
    }

    func attachHoverSidebarManager(
        _ hoverSidebarManager: HoverSidebarManager,
        windowState: BrowserWindowState
    ) {
        runtime.attachHoverSidebarManager(hoverSidebarManager, windowState)
    }

    func websiteViewBrowserContext(sidebarDragState: SidebarDragState) -> WebsiteViewBrowserContext {
        runtime.websiteViewBrowserContext(sidebarDragState)
    }

    var websiteNativeSurfaceRootBuilders: WebsiteNativeSurfaceRootBuilders {
        runtime.websiteNativeSurfaceRootBuilders()
    }

    func currentTab(for windowState: BrowserWindowState) -> Tab? {
        runtime.currentTab(windowState)
    }

    func workspaceTheme(for spaceId: UUID?) -> WorkspaceTheme? {
        runtime.workspaceTheme(spaceId)
    }

    func isNativeModalPresented(in windowId: UUID) -> Bool {
        runtime.isNativeModalPresented(windowId)
    }

    func nativeModalPresentationBindingDismissed(for windowId: UUID) {
        runtime.nativeModalPresentationBindingDismissed(windowId)
    }

    func dismissNativeModalPresentation() {
        runtime.dismissNativeModalPresentation()
    }

    func findCurrentTabId() -> UUID? {
        runtime.findCurrentTabId()
    }
}
