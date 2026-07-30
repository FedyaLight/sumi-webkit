import AppKit
import Foundation

@MainActor
final class TabFolderUngroupPreparationService {
    private let folders: TabFolderCollectionStateOwner
    private let hierarchy: TabFolderHierarchyMutationService
    private let membership: TabCollectionMembershipOwner

    init(
        folders: TabFolderCollectionStateOwner,
        hierarchy: TabFolderHierarchyMutationService,
        membership: TabCollectionMembershipOwner
    ) {
        self.folders = folders
        self.hierarchy = hierarchy
        self.membership = membership
    }

    func prepare(folderID: UUID) -> TabFolderUngroupPreparation? {
        guard let folder = folders.folder(by: folderID) else { return nil }
        let spaceID = folder.spaceId
        var currentFolders = folders.folders(for: spaceID)
        guard let folderIndex = currentFolders.firstIndex(where: {
            $0 === folder
        }) else { return nil }
        let liftedItems = hierarchy.childItems(
            in: folder.id,
            spaceID: spaceID
        )
        var parentItems = hierarchy.childItems(
            in: folder.parentFolderId,
            spaceID: spaceID
        )
        if let folderItemIndex = parentItems.firstIndex(
            of: .folder(folder.id)
        ) {
            parentItems.remove(at: folderItemIndex)
            parentItems.insert(contentsOf: liftedItems, at: folderItemIndex)
        } else {
            parentItems.append(contentsOf: liftedItems)
        }
        currentFolders.remove(at: folderIndex)
        return TabFolderUngroupPreparation(
            spaceID: spaceID,
            folderID: folder.id,
            isLiveFolder: folder.isLiveFolder,
            parentFolderID: folder.parentFolderId,
            remainingFolders: currentFolders,
            liftedParentItems: parentItems,
            liveTabs: membership.allTabs().filter {
                $0.folderId == folder.id
            }
        )
    }
}
