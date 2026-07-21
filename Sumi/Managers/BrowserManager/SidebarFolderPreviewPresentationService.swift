import Foundation

/// Resolves the settings the folder hover preview needs (sidebar side) and hands
/// the request to the window's own preview session owner.
@MainActor
final class SidebarFolderPreviewPresentationService {
    private let settings: BrowserSettingsAttachmentCoordinator

    init(settings: BrowserSettingsAttachmentCoordinator) {
        self.settings = settings
    }

    func show(
        request: SidebarFolderPreviewRequest,
        in windowState: BrowserWindowState,
        source: SidebarTransientPresentationSource
    ) {
        guard let settings = settings.settings else { return }
        windowState.sidebarFolderPreview.open(
            request: request,
            sidebarPosition: settings.sidebarPosition,
            source: source
        )
    }

    func dismiss(
        folderID: UUID,
        in windowState: BrowserWindowState
    ) {
        windowState.sidebarFolderPreview.close(folderID: folderID)
    }

    func setAnchorHovered(
        folderID: UUID,
        in windowState: BrowserWindowState,
        hovering: Bool
    ) {
        windowState.sidebarFolderPreview.setAnchorHovered(
            folderID: folderID,
            hovering: hovering
        )
    }
}
