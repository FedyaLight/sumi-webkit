@MainActor
final class RegularTabShortcutTerminalEffects {
    private let persistence: TabStructuralPersistenceService
    private let folders: TabFolderOpenStateService
    private let destination: TabShortcutPinDestination

    init(
        persistence: TabStructuralPersistenceService,
        folders: TabFolderOpenStateService,
        destination: TabShortcutPinDestination
    ) {
        self.persistence = persistence
        self.folders = folders
        self.destination = destination
    }

    func publish() {
        persistence.scheduleStructuralPersistence()
        if destination.opensFolder, let folderID = destination.folderId {
            folders.openFolderIfNeeded(folderID)
        }
    }
}

@MainActor
final class RegularTabShortcutTerminalEffectsFactory {
    private let persistence: TabStructuralPersistenceService
    private let folders: TabFolderOpenStateService

    init(
        persistence: TabStructuralPersistenceService,
        folders: TabFolderOpenStateService
    ) {
        self.persistence = persistence
        self.folders = folders
    }

    func make(
        destination: TabShortcutPinDestination
    ) -> RegularTabShortcutTerminalEffects {
        RegularTabShortcutTerminalEffects(
            persistence: persistence,
            folders: folders,
            destination: destination
        )
    }

    func requestFolderCommit(
        for sidebar: RegularTabShortcutSidebarBindingContribution
    ) {
        sidebar.requestTerminalFolderCommit(using: folders)
    }
}
