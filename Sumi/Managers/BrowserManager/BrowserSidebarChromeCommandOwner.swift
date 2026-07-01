import Foundation

@MainActor
final class BrowserSidebarChromeCommandOwner {
    struct Dependencies {
        let showGradientEditor: @MainActor (SidebarTransientPresentationSource) -> Void
        let toggleSidebar: @MainActor (BrowserWindowState) -> Void
        let openAppearanceSettings: @MainActor (BrowserWindowState) -> Void
        let closeDownloadsPopover: @MainActor (BrowserWindowState) -> Void
        let toggleDownloadsPopover: @MainActor (BrowserWindowState) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func showGradientEditor(source: SidebarTransientPresentationSource) {
        dependencies.showGradientEditor(source)
    }

    func toggleSidebar(in windowState: BrowserWindowState) {
        dependencies.toggleSidebar(windowState)
    }

    func openAppearanceSettings(in windowState: BrowserWindowState) {
        dependencies.openAppearanceSettings(windowState)
    }

    func closeDownloadsPopover(in windowState: BrowserWindowState) {
        dependencies.closeDownloadsPopover(windowState)
    }

    func toggleDownloadsPopover(in windowState: BrowserWindowState) {
        dependencies.toggleDownloadsPopover(windowState)
    }
}

extension BrowserSidebarChromeCommandOwner.Dependencies {
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            showGradientEditor: { [weak browserManager] source in
                browserManager?.workspaceThemeEditorOwner.showGradientEditor(source: source)
            },
            toggleSidebar: { [weak browserManager] windowState in
                browserManager?.toggleSidebar(for: windowState)
            },
            openAppearanceSettings: { [weak browserManager] windowState in
                browserManager?.openSettingsTab(selecting: .appearance, in: windowState)
            },
            closeDownloadsPopover: { [weak browserManager] windowState in
                browserManager?.chromePopoverRoutingOwner.closeDownloadsPopover(in: windowState)
            },
            toggleDownloadsPopover: { [weak browserManager] windowState in
                browserManager?.chromePopoverRoutingOwner.toggleDownloadsPopover(in: windowState)
            }
        )
    }
}
