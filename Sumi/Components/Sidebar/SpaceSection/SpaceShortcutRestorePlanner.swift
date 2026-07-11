//
//  SpaceShortcutRestorePlanner.swift
//  Sumi
//

import Foundation
import SumiDomain

/// Resolves the visual launcher gap for a durable shortcut member.
/// Exact state is looked up by IDs at the moment the animation phase starts.
@MainActor
struct SpaceShortcutRestorePlanner {
    let browserContext: SidebarBrowserContext
    let space: Space

    func shortcutRestoreGap(
        groupID: UUID,
        memberID: SplitMemberID
    ) -> ShortcutRestoreGap? {
        guard let group = browserContext.tabManager.splitGroupStore.group(
            id: groupID
        ),
              let member = group.member(for: memberID),
              case .shortcutPin(let pinID) = memberID,
              browserContext.tabManager.shortcutPinCollectionStateOwner
                .shortcutPin(by: pinID) != nil,
              let returnPlacement = member.returnPlacement else {
            return nil
        }

        switch returnPlacement {
        case .spacePinned(let spaceID, let folderID, let index):
            guard spaceID == space.id else { return nil }
            if let folderID {
                guard browserContext.tabManager.folderCollectionStateOwner
                    .spaceId(for: folderID) == spaceID,
                      browserContext.tabManager.folderCollectionStateOwner
                        .folder(by: folderID)?.isOpen == true else {
                    return nil
                }
                return ShortcutRestoreGap(
                    pinId: pinID,
                    container: .folder(folderID),
                    index: index
                )
            }
            return ShortcutRestoreGap(
                pinId: pinID,
                container: .spacePinned(spaceID),
                index: index
            )

        case .generatedSpacePinnedFromRegular(let spaceID, _):
            guard spaceID == space.id else { return nil }
            return ShortcutRestoreGap(
                pinId: pinID,
                container: .spacePinned(spaceID),
                index: browserContext.tabManager.splitGroupSidebarOrdering
                    .topLevelItems(for: spaceID).count
            )

        case .essential:
            return nil
        }
    }
}
