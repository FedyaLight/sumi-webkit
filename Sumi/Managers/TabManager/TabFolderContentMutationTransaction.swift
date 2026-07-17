import AppKit
import Foundation

@MainActor
final class TabFolderContentMutationTransaction {
    private let structuralLookup: TabStructuralLookupCoordinator
    private let spaces: TabSpaceCollectionStateOwner
    private let folders: TabFolderCollectionStateOwner
    private let hierarchy: TabFolderHierarchyMutationService
    private let persistence: TabStructuralPersistenceService

    init(
        structuralLookup: TabStructuralLookupCoordinator,
        spaces: TabSpaceCollectionStateOwner,
        folders: TabFolderCollectionStateOwner,
        hierarchy: TabFolderHierarchyMutationService,
        persistence: TabStructuralPersistenceService
    ) {
        self.structuralLookup = structuralLookup
        self.spaces = spaces
        self.folders = folders
        self.hierarchy = hierarchy
        self.persistence = persistence
    }

    func createFolder(
        for spaceID: UUID,
        parentFolderID: UUID?,
        name: String
    ) -> TabFolder? {
        structuralLookup.withTransaction {
            if let parentFolderID {
                guard folders.spaceId(for: parentFolderID) == spaceID else {
                    return nil
                }
            }
            let folder = TabFolder(
                name: name,
                spaceId: spaceID,
                parentFolderId: parentFolderID,
                color: spaces.spaces.first(where: {
                    $0.id == spaceID
                })?.color ?? .controlAccentColor,
                index: hierarchy.childItems(
                    in: parentFolderID,
                    spaceID: spaceID
                ).count
            )
            hierarchy.appendFolder(folder, in: spaceID)
            persistence.scheduleStructuralPersistence()
            return folder
        }
    }

    func renameFolder(_ folderID: UUID, newName: String) {
        structuralLookup.withTransaction {
            guard let folder = folders.folder(by: folderID) else { return }
            folder.name = newName
            publishFolderObjectChange(in: folder.spaceId)
        }
    }

    func updateFolderIcon(_ folderID: UUID, icon: String) {
        let normalizedIcon = SumiZenFolderIconCatalog.normalizedFolderIconValue(
            icon.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        structuralLookup.withTransaction {
            guard let folder = folders.folder(by: folderID) else { return }
            folder.icon = normalizedIcon
            publishFolderObjectChange(in: folder.spaceId)
        }
    }

    func alphabetizeFolderPins(_ folderID: UUID, in spaceID: UUID) {
        structuralLookup.withTransaction {
            guard folders.folder(by: folderID)?.spaceId == spaceID else {
                return
            }
            guard hierarchy.alphabetizePins(
                in: folderID,
                spaceID: spaceID
            ) else { return }
            persistence.scheduleStructuralPersistence()
        }
    }

    private func publishFolderObjectChange(in spaceID: UUID) {
        persistence.markFoldersStructurallyDirty(for: spaceID)
        structuralLookup.requestPublish(scope: .space(spaceID))
        persistence.scheduleStructuralPersistence()
    }
}
