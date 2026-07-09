import Foundation

@MainActor
final class BrowserSidebarChromeCommandOwner {
    private let showGradientEditorAction: @MainActor (SidebarTransientPresentationSource) -> Void
    private let toggleSidebarAction: @MainActor (BrowserWindowState) -> Void
    private let openAppearanceSettingsAction: @MainActor (BrowserWindowState) -> Void
    private let closeDownloadsPopoverAction: @MainActor (BrowserWindowState) -> Void
    private let toggleDownloadsPopoverAction: @MainActor (BrowserWindowState) -> Void

    init(
        showGradientEditor: @escaping @MainActor (SidebarTransientPresentationSource) -> Void,
        toggleSidebar: @escaping @MainActor (BrowserWindowState) -> Void,
        openAppearanceSettings: @escaping @MainActor (BrowserWindowState) -> Void,
        closeDownloadsPopover: @escaping @MainActor (BrowserWindowState) -> Void,
        toggleDownloadsPopover: @escaping @MainActor (BrowserWindowState) -> Void
    ) {
        self.showGradientEditorAction = showGradientEditor
        self.toggleSidebarAction = toggleSidebar
        self.openAppearanceSettingsAction = openAppearanceSettings
        self.closeDownloadsPopoverAction = closeDownloadsPopover
        self.toggleDownloadsPopoverAction = toggleDownloadsPopover
    }

    func showGradientEditor(source: SidebarTransientPresentationSource) {
        showGradientEditorAction(source)
    }

    func toggleSidebar(in windowState: BrowserWindowState) {
        toggleSidebarAction(windowState)
    }

    func openAppearanceSettings(in windowState: BrowserWindowState) {
        openAppearanceSettingsAction(windowState)
    }

    func closeDownloadsPopover(in windowState: BrowserWindowState) {
        closeDownloadsPopoverAction(windowState)
    }

    func toggleDownloadsPopover(in windowState: BrowserWindowState) {
        toggleDownloadsPopoverAction(windowState)
    }
}
