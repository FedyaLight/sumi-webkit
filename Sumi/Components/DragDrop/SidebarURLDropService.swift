import Foundation
import SumiDomain

@MainActor
final class SidebarURLDropService {
    private let pageOpening: SidebarURLDropTabOpening
    private let destinations: any SidebarURLDropDestinationResolving
    private let shortcutInsertion: any ShortcutURLInserting
    private let orderProjection: any SidebarDropOrderProjecting

    init(
        pageOpening: SidebarURLDropTabOpening,
        destinations: any SidebarURLDropDestinationResolving,
        shortcutInsertion: any ShortcutURLInserting,
        orderProjection: any SidebarDropOrderProjecting = SidebarIdentityDropOrderProjection()
    ) {
        self.pageOpening = pageOpening
        self.destinations = destinations
        self.shortcutInsertion = shortcutInsertion
        self.orderProjection = orderProjection
    }

    func open(
        _ url: URL,
        in windowState: BrowserWindowState,
        atPresentedSlot presentedSlot: DropZoneSlot
    ) -> Bool {
        let slot = orderProjection.storageSlot(for: presentedSlot)
        guard slot != .empty else { return false }

        if windowState.isIncognito {
            return pageOpening.open(url, in: windowState)
        }

        switch slot {
        case .spaceRegular(let spaceID, let index):
            guard let space = destinations.space(spaceID) else { return false }
            return pageOpening.open(
                url,
                in: windowState,
                preferredSpaceID: space.id,
                regularInsertionIndex: index
            )

        case .spacePinned(let spaceID, let index):
            guard url.scheme?.lowercased() != "sumi",
                  let space = destinations.space(spaceID)
            else { return false }
            return shortcutInsertion.insert(
                url,
                placement: ShortcutURLPlacement(
                    role: .spacePinned,
                    profileID: nil,
                    executionProfileID: space.profileId,
                    spaceID: space.id,
                    folderID: nil,
                    index: index,
                    openTargetFolder: true
                ),
                in: windowState
            )

        case .folder(let folderID, let index):
            guard url.scheme?.lowercased() != "sumi",
                  let destination = destinations.folder(folderID)
            else { return false }
            return shortcutInsertion.insert(
                url,
                placement: ShortcutURLPlacement(
                    role: .spacePinned,
                    profileID: nil,
                    executionProfileID: destination.space.profileId,
                    spaceID: destination.space.id,
                    folderID: destination.folder.id,
                    index: index,
                    openTargetFolder: false
                ),
                in: windowState
            )

        case .favorite(let index):
            guard url.scheme?.lowercased() != "sumi",
                  let insertion = destinations.favoriteInsertion(
                    in: windowState,
                    at: index
                  )
            else { return false }
            return shortcutInsertion.insert(
                url,
                placement: ShortcutURLPlacement(
                    role: .favorite,
                    profileID: insertion.profileId,
                    executionProfileID: insertion.profileId,
                    spaceID: nil,
                    folderID: nil,
                    index: insertion.index,
                    openTargetFolder: true
                ),
                in: windowState
            )

        case .empty:
            return false
        }
    }

}
