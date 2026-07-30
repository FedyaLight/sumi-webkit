import AppKit
import Foundation

@MainActor
final class TabLastSessionFolderMaterializer {
    private let structuralMutations: TabStructuralCollectionMutationOwner

    init(structuralMutations: TabStructuralCollectionMutationOwner) {
        self.structuralMutations = structuralMutations
    }

    func materialize(
        _ plan: TabLastSessionMergePlan,
        existing: [TabLastSessionFolderKey: TabFolder]
    ) {
        for spaceID in plan.orderedSpaceIds {
            let folders = (plan.foldersBySpace[spaceID] ?? []).map {
                placement -> TabFolder in
                if let folder = existing[TabLastSessionFolderKey(
                    spaceID: placement.spaceId,
                    folderID: placement.id
                )] {
                    if let restored = placement.restoredValues {
                        apply(restored, to: folder)
                    }
                    return folder
                }
                guard let restored = placement.restoredValues else {
                    preconditionFailure(
                        "Last-session plan referenced a missing live folder"
                    )
                }
                let folder = TabFolder(
                    id: restored.id,
                    name: restored.name,
                    spaceId: restored.spaceId,
                    parentFolderId: restored.parentFolderId,
                    isLiveFolder: restored.isLiveFolder,
                    icon: restored.icon,
                    color: NSColor(hex: restored.color) ?? .controlAccentColor,
                    index: restored.index
                )
                folder.isOpen = restored.isOpen
                return folder
            }
            structuralMutations.setFolders(folders, for: spaceID)
        }
    }

    private func apply(_ restored: TabPersistenceFolder, to folder: TabFolder) {
        folder.name = restored.name
        folder.icon = SumiZenFolderIconCatalog.normalizedFolderIconValue(
            restored.icon
        )
        folder.color = NSColor(hex: restored.color) ?? .controlAccentColor
        folder.installPlacement(TabFolderPlacement(
            spaceID: restored.spaceId,
            parentFolderID: restored.parentFolderId,
            index: restored.index
        ))
        folder.isOpen = restored.isOpen
        folder.isLiveFolder = restored.isLiveFolder
    }
}
