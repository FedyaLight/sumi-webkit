import Foundation

@MainActor
final class SidebarFolderEditorPresentationService {
    private let settings: BrowserSettingsAttachmentCoordinator
    private let folderCommands: SidebarFolderCommands
    private let presenter: FolderEditorPopoverPresenter

    init(
        settings: BrowserSettingsAttachmentCoordinator,
        folderCommands: SidebarFolderCommands,
        presenter: FolderEditorPopoverPresenter
    ) {
        self.settings = settings
        self.folderCommands = folderCommands
        self.presenter = presenter
    }

    func show(
        folder: TabFolder,
        in windowState: BrowserWindowState,
        themeContext: ResolvedThemeContext,
        source: SidebarTransientPresentationSource
    ) {
        guard let settings = settings.settings else { return }
        presenter.present(
            folder: folder,
            in: windowState,
            themeContext: themeContext,
            presentationContext: FolderEditorPopoverPresentationContext(
                sidebarPosition: settings.sidebarPosition,
                settings: settings,
                commit: { [weak self] in self?.commit($0) }
            ),
            source: source
        )
    }

    func commit(_ session: FolderEditorSession) {
        guard session.canCommit, session.hasChanges else { return }
        if session.trimmedName != session.originalName {
            folderCommands.renameFolder(session.folderID, to: session.trimmedName)
        }
        if session.icon != session.originalIcon {
            folderCommands.updateFolderIcon(session.folderID, icon: session.icon)
        }
    }
}
