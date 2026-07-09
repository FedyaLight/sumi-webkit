//
//  SpaceShortcutRestoreOwner.swift
//  Sumi
//

import Foundation

/// Resolves shortcut-restore gap placement for split segments without
/// coupling `SpaceView` directly to `tabManager`.
@MainActor
struct SpaceShortcutRestoreOwner {
    let browserContext: SidebarBrowserContext
    let space: Space

    func shortcutRestoreGap(
        for item: SplitGroupSidebarItem,
        in group: SplitGroup
    ) -> ShortcutRestoreGap? {
        guard let member = shortcutRestoreMember(for: item, in: group),
              member.isShortcutBacked,
              let pinId = member.pinId,
              browserContext.tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: pinId) != nil
        else {
            return nil
        }

        switch member.origin {
        case .spacePinned(let spaceId, let folderId, let index):
            guard spaceId == space.id else { return nil }
            if let folderId {
                guard browserContext.tabManager.folderCollectionStateOwner.spaceId(for: folderId) == spaceId,
                      browserContext.tabManager.folderCollectionStateOwner.folder(by: folderId)?.isOpen == true
                else {
                    return nil
                }
                return ShortcutRestoreGap(
                    pinId: pinId,
                    container: .folder(folderId),
                    index: index
                )
            }
            return ShortcutRestoreGap(
                pinId: pinId,
                container: .spacePinned(spaceId),
                index: index
            )

        case .generatedSpacePinnedFromRegular(let spaceId, _):
            guard spaceId == space.id else { return nil }
            return ShortcutRestoreGap(
                pinId: pinId,
                container: .spacePinned(spaceId),
                index: browserContext.tabManager.spacePinnedStructureOwner.topLevelSpacePinnedItems(for: spaceId).count
            )

        case .essential, .regular:
            return nil
        }
    }

    private func shortcutRestoreMember(
        for item: SplitGroupSidebarItem,
        in group: SplitGroup
    ) -> SplitGroupMember? {
        if let pin = item.pin {
            return group.member(forPinId: pin.id) ?? group.member(for: pin.id)
        }
        if let tab = item.tab {
            if let pinId = tab.shortcutPinId {
                return group.member(forPinId: pinId) ?? group.member(for: tab.id)
            }
            return group.member(for: tab.id)
        }
        return nil
    }
}
