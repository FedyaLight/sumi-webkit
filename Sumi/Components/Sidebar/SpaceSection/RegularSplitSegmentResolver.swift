//
//  RegularSplitSegmentResolver.swift
//  Sumi
//

import Foundation
import SumiDomain

/// Pure sidebar projection for split groups hosted by the regular tab list.
@MainActor
struct RegularSplitSegmentResolver {
    let space: Space
    let isInteractive: Bool

    func visibleSplitGroups(
        currentTabs: [Tab],
        isDragging: Bool,
        splitGroup: (SplitMemberID) -> SplitGroup?
    ) -> [SplitGroup] {
        guard !isDragging else { return [] }
        let currentMemberIDs = Set(
            currentTabs.map { SplitMemberID.regularTab($0.id) }
        )
        var seenGroupIDs = Set<UUID>()

        return currentTabs.compactMap { tab in
            let memberID = SplitMemberID.regularTab(tab.id)
            guard let group = splitGroup(memberID),
                  !group.container.isShortcutSidebar,
                  seenGroupIDs.insert(group.id).inserted,
                  group.memberIDs.count >= SplitGroup.minimumMembers,
                  group.memberIDs.contains(where: currentMemberIDs.contains)
            else {
                return nil
            }
            return group
        }
    }

    func splitGroupItems(
        for group: SplitGroup,
        tabByID: [UUID: Tab],
        regularTab: (UUID) -> Tab?,
        shortcutLiveTab: (UUID) -> Tab?,
        shortcutPin: (UUID) -> ShortcutPin?
    ) -> [SplitGroupSidebarItem] {
        group.members.compactMap { member in
            switch member.memberID {
            case .regularTab(let tabID):
                guard let tab = tabByID[tabID] ?? regularTab(tabID) else {
                    return nil
                }
                return .regular(member, tab: tab)

            case .shortcutPin(let pinID):
                guard let pin = shortcutPin(pinID) else { return nil }
                return .shortcut(
                    member,
                    pin: pin,
                    liveTab: shortcutLiveTab(pinID)
                )
            }
        }
    }

    func action(
        for item: SplitGroupSidebarItem,
        in _: SplitGroup
    ) -> SplitGroupSidebarSegmentAction? {
        switch item.id {
        case .shortcutPin:
            return .restore
        case .regularTab:
            return item.tab == nil ? nil : .close
        }
    }

    func member(
        for item: SplitGroupSidebarItem,
        in group: SplitGroup
    ) -> SplitMember? {
        group.member(for: item.id)
    }

    func shortcutPin(
        for item: SplitGroupSidebarItem,
        member _: SplitMember?,
        shortcutPin _: (UUID) -> ShortcutPin?
    ) -> ShortcutPin? {
        item.pin
    }

    func sourceZone(for pin: ShortcutPin) -> DropZoneID {
        switch pin.role {
        case .essential:
            return .essentials
        case .spacePinned:
            if let folderId = pin.folderId {
                return .folder(folderId)
            }
            return .spacePinned(pin.spaceId ?? space.id)
        }
    }

    func dragSource(
        for item: SplitGroupSidebarItem,
        in group: SplitGroup,
        faviconImageReader: any BrowserFaviconImageReading,
        shortcutPin: (UUID) -> ShortcutPin?,
        onActivateMember: @escaping () -> Void
    ) -> SidebarDragSourceConfiguration? {
        if let pin = self.shortcutPin(
            for: item,
            member: member(for: item, in: group),
            shortcutPin: shortcutPin
        ) {
            return SidebarDragSourceConfiguration(
                item: SumiDragItem.splitMember(
                    item.id,
                    groupID: group.id,
                    title: item.title,
                    urlString: item.tab?.url.absoluteString
                        ?? pin.launchURL.absoluteString
                ),
                sourceZone: sourceZone(for: pin),
                previewKind: .row,
                previewIcon: item.tab?.favicon ?? pin.storedFaviconImage(
                    partition: .regular(pin.executionProfileId ?? pin.profileId),
                    imageReader: faviconImageReader
                ),
                exclusionZones: [.trailingStrip(32)],
                onActivate: onActivateMember,
                isEnabled: isInteractive
            )
        }

        guard let tab = item.tab else { return nil }
        return SidebarDragSourceConfiguration(
            item: SumiDragItem.splitMember(
                item.id,
                groupID: group.id,
                title: tab.name,
                urlString: tab.url.absoluteString
            ),
            sourceZone: .spaceRegular(space.id),
            previewKind: .row,
            previewIcon: tab.favicon,
            exclusionZones: [.trailingStrip(32)],
            onActivate: onActivateMember,
            isEnabled: isInteractive
        )
    }
}
