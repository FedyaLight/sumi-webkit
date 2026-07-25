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
            publishExpansionChange([folder.id: folder.isOpen], in: folder.spaceId)
        }
    }

    func toggleFolderOpenState(_ folderID: UUID) {
        structuralLookup.withTransaction {
            guard let folder = folders.folder(by: folderID) else { return }
            folder.isOpen.toggle()
            publishExpansionChange([folder.id: folder.isOpen], in: folder.spaceId)
        }
    }

    func setAllFolders(open isOpen: Bool, in spaceID: UUID) {
        structuralLookup.withTransaction {
            let candidates = folders.folders(for: spaceID).filter {
                $0.isOpen != isOpen
            }
            guard candidates.isEmpty == false else { return }
            candidates.forEach { $0.isOpen = isOpen }
            publishExpansionChange(
                Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0.isOpen) }),
                in: spaceID
            )
        }
    }

    func openFolderIfNeeded(_ folderID: UUID) {
        setFolder(folderID, open: true)
    }

    private func publishExpansionChange(
        _ expansionByFolderID: [UUID: Bool],
        in spaceID: UUID
    ) {
        persistence.markFoldersStructurallyDirty(for: spaceID)
        structuralLookup.publishFolderExpansionChange(
            spaceID: spaceID,
            expansionByFolderID: expansionByFolderID
        )
        persistence.scheduleStructuralPersistence()
    }
}
