import Foundation

@MainActor
final class SidebarSpaceDeletionPresentationOwner {
    private let lifecycle: SidebarSpaceLifecycle
    private let windows: SidebarWindowIdentityQuery
    private let settings: BrowserSettingsAttachmentCoordinator

    init(
        lifecycle: SidebarSpaceLifecycle,
        windows: SidebarWindowIdentityQuery,
        settings: BrowserSettingsAttachmentCoordinator
    ) {
        self.lifecycle = lifecycle
        self.windows = windows
        self.settings = settings
    }

    func confirmDelete(
        _ space: Space,
        in windowState: BrowserWindowState
    ) {
        SpaceDeletionConfirmationPresenter.confirmDelete(
            space: space,
            lifecycle: lifecycle,
            window: windows.shellWindow(for: windowState),
            windowState: windows.contains(windowState) ? windowState : nil,
            settings: settings.settings
        )
    }
}
