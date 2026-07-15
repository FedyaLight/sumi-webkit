import Foundation

/// Owns publication and persistence for folder expansion state without
/// depending on the higher-level folder and shortcut command graph.
@MainActor
final class TabFolderOpenStateService {
    private let folders: TabFolderCollectionStateOwner
    private let structuralLookup: TabStructuralLookupCoordinator
    private let persistence: TabStructuralPersistenceService

    init(
        folders: TabFolderCollectionStateOwner,
        structuralLookup: TabStructuralLookupCoordinator,
        persistence: TabStructuralPersistenceService
    ) {
        self.folders = folders
        self.structuralLookup = structuralLookup
        self.persistence = persistence
    }

    func setFolder(_ folderID: UUID, open isOpen: Bool) {
        structuralLookup.withTransaction {
            guard let folder = folders.folder(by: folderID),
                  folder.isOpen != isOpen else { return }
            folder.isOpen = isOpen
            publishChange(in: folder.spaceId)
        }
    }

    func toggleFolderOpenState(_ folderID: UUID) {
        structuralLookup.withTransaction {
            guard let folder = folders.folder(by: folderID) else { return }
            folder.isOpen.toggle()
            publishChange(in: folder.spaceId)
        }
    }

    func setAllFolders(open isOpen: Bool, in spaceID: UUID) {
        structuralLookup.withTransaction {
            let candidates = folders.folders(for: spaceID).filter {
                $0.isOpen != isOpen
            }
            guard candidates.isEmpty == false else { return }
            candidates.forEach { $0.isOpen = isOpen }
            publishChange(in: spaceID)
        }
    }

    func openFolderIfNeeded(_ folderID: UUID) {
        setFolder(folderID, open: true)
    }

    private func publishChange(in spaceID: UUID) {
        persistence.markFoldersStructurallyDirty(for: spaceID)
        structuralLookup.requestPublish(scope: .space(spaceID))
        persistence.scheduleStructuralPersistence()
    }
}
