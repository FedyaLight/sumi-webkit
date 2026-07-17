import Foundation

@MainActor
final class SidebarFolderSearchPresentationService {
    private let settings: BrowserSettingsAttachmentCoordinator
    private let presenter: FolderSearchPopoverPresenter

    init(
        settings: BrowserSettingsAttachmentCoordinator,
        presenter: FolderSearchPopoverPresenter
    ) {
        self.settings = settings
        self.presenter = presenter
    }

    func show(
        request: FolderSearchPopoverRequest,
        in windowState: BrowserWindowState,
        themeContext: ResolvedThemeContext,
        source: SidebarTransientPresentationSource
    ) {
        guard let settings = settings.settings else { return }
        presenter.present(
            request: request,
            in: windowState,
            themeContext: themeContext,
            presentationContext: FolderSearchPopoverPresentationContext(
                sidebarPosition: settings.sidebarPosition,
                settings: settings
            ),
            source: source
        )
    }

    func setAnchorHovered(
        folderID: UUID,
        in windowState: BrowserWindowState,
        hovering: Bool
    ) {
        presenter.setAnchorHovered(
            folderID: folderID,
            in: windowState,
            hovering: hovering
        )
    }
}
