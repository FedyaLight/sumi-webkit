import AppKit
import Foundation

@MainActor
final class TabFolderDeletionPreparationService {
    private let folders: TabFolderCollectionStateOwner
    private let pins: ShortcutPinCollectionStateOwner
    private let hierarchy: TabFolderHierarchyMutationService
    private let membership: TabCollectionMembershipOwner

    init(
        folders: TabFolderCollectionStateOwner,
        pins: ShortcutPinCollectionStateOwner,
        hierarchy: TabFolderHierarchyMutationService,
        membership: TabCollectionMembershipOwner
    ) {
        self.folders = folders
        self.pins = pins
        self.hierarchy = hierarchy
        self.membership = membership
    }

    func prepare(folderID: UUID) -> TabFolderDeletionPreparation? {
        guard let folder = folders.folder(by: folderID) else { return nil }
        let spaceID = folder.spaceId
        let currentFolders = folders.folders(for: spaceID)
        guard currentFolders.contains(where: { $0 === folder }) else {
            return nil
        }
        let deletedFolderIDs = hierarchy.descendantFolderIDs(
            including: folder.id,
            in: spaceID
        )
        let existingPins = pins.spacePinnedPins(for: spaceID)
        let deletedPins = existingPins.filter { pin in
            pin.folderId.map { deletedFolderIDs.contains($0) } ?? false
        }
        let deletedPinIDs = Set(deletedPins.map(\.id))
        let liveTabIDs = membership.allTabs().filter { tab in
            guard let tabFolderID = tab.folderId,
                  deletedFolderIDs.contains(tabFolderID) else {
                return false
            }
            return tab.shortcutPinId.map {
                deletedPinIDs.contains($0) == false
            } ?? true
        }.map(\.id)
        var remainingParentItems = hierarchy.childItems(
            in: folder.parentFolderId,
            spaceID: spaceID
        )
        remainingParentItems.removeAll { item in
            switch item {
            case .folder(let childFolderID):
                return deletedFolderIDs.contains(childFolderID)
            case .shortcut(let pinID):
                return deletedPinIDs.contains(pinID)
            }
        }
        return TabFolderDeletionPreparation(
            spaceID: spaceID,
            deletedFolderIDs: deletedFolderIDs,
            parentFolderID: folder.parentFolderId,
            remainingFolders: currentFolders.filter {
                deletedFolderIDs.contains($0.id) == false
            },
            existingPins: existingPins,
            remainingPins: existingPins.filter { pin in
                pin.folderId.map { deletedFolderIDs.contains($0) } != true
            },
            deletedPins: deletedPins,
            deletedPinIDs: deletedPinIDs,
            liveTabIDs: liveTabIDs,
            remainingParentItems: remainingParentItems
        )
    }
}
