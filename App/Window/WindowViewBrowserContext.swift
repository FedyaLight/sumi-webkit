import Foundation

@MainActor
final class WindowViewBrowserContext {
    private let browserManager: BrowserManager

    init(browserManager: BrowserManager) {
        self.browserManager = browserManager
    }

    var browserManagerForUnmigratedChildren: BrowserManager {
        browserManager
    }

    var splitManager: SplitViewManager {
        browserManager.splitManager
    }

    var findManager: FindManager {
        browserManager.findManager
    }

    var nativeModalPresentation: BrowserNativeModalPresentation? {
        browserManager.nativeModalPresentation
    }

    var hasCurrentSpace: Bool {
        browserManager.tabManager.currentSpace != nil
    }

    func showGradientEditor(source: SidebarTransientPresentationSource) {
        browserManager.showGradientEditor(source: source)
    }

    func currentProfileID() -> UUID? {
        browserManager.currentProfile?.id
    }

    func essentialPins(profileId: UUID?) -> [ShortcutPin] {
        browserManager.tabManager.essentialPins(for: profileId)
    }

    func attachHoverSidebarManager(
        _ hoverSidebarManager: HoverSidebarManager,
        windowState: BrowserWindowState
    ) {
        hoverSidebarManager.attach(browserManager: browserManager, windowState: windowState)
    }

    func websiteViewBrowserContext(sidebarDragState: SidebarDragState) -> WebsiteViewBrowserContext {
        browserManager.websiteViewBrowserContext(sidebarDragState: sidebarDragState)
    }

    var websiteNativeSurfaceRootBuilders: WebsiteNativeSurfaceRootBuilders {
        browserManager.websiteNativeSurfaceRootBuilders
    }

    func currentTab(for windowState: BrowserWindowState) -> Tab? {
        browserManager.currentTab(for: windowState)
    }

    func workspaceTheme(for spaceId: UUID?) -> WorkspaceTheme? {
        guard let spaceId else { return nil }
        return browserManager.space(for: spaceId)?.workspaceTheme
    }

    func isNativeModalPresented(in windowId: UUID) -> Bool {
        browserManager.isNativeModalPresented(in: windowId)
    }

    func nativeModalPresentationBindingDismissed(for windowId: UUID) {
        browserManager.nativeModalPresentationBindingDismissed(for: windowId)
    }

    func dismissNativeModalPresentation() {
        browserManager.dismissNativeModalPresentation()
    }

    func findCurrentTabId() -> UUID? {
        browserManager.findManager.currentTab?.id
    }
}
