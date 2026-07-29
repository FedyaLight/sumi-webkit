//
//  RegularSplitSegmentResolver.swift
//  Sumi
//

import Foundation
import SumiDomain
import SwiftUI

/// Pure sidebar projection for split groups hosted by the regular tab list.
@MainActor
struct RegularSplitSegmentResolver {
    let space: Space
    let isInteractive: Bool

    func visibleSplitGroups(
        currentTabs: [Tab],
        splitGroup: (SplitMemberID) -> SplitGroup?
    ) -> [SplitGroup] {
        let currentMemberIDs = Set(
            currentTabs.map { SplitMemberID.regularTab($0.id) }
        )
        var seenGroupIDs = Set<UUID>()

        return currentTabs.compactMap { tab in
            let memberID = SplitMemberID.regularTab(tab.id)
            guard let group = splitGroup(memberID),
                  case .regularTabs = group.container,
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
        splitPresentation: SidebarSplitDragPresentation,
        isGroupSelected: Bool
    ) -> SidebarDragSourceConfiguration? {
        guard let tab = item.tab else { return nil }
        let memberIcon = SplitGroupMemberIconResolver.resolve(
            item: item,
            loadedStoredFavicon: nil,
            faviconPartition: .regular(
                item.pin?.executionProfileId
                    ?? item.pin?.profileId
                    ?? item.tab?.profileId
            ),
            imageReader: faviconImageReader
        )
        return SidebarDragSourceConfiguration(
            item: SumiDragItem.splitGroup(
                group.id,
                title: group.iconAsset == nil
                    ? tab.name : SplitGroupSidebarModel.displayTitle(for: group),
                urlString: tab.url.absoluteString
            ),
            sourceZone: .spaceRegular(space.id),
            previewKind: .row,
            previewIcon: group.iconAsset.flatMap { iconAsset in
                SumiPersistentGlyph.presentsAsEmoji(iconAsset)
                    ? nil
                    : Image(systemName:
                        SumiPersistentGlyph.resolvedLauncherSystemImageName(
                            iconAsset
                        )
                    )
            } ?? memberIcon.image,
            previewGlyphText: group.iconAsset.flatMap {
                SumiPersistentGlyph.presentsAsEmoji($0) ? $0 : nil
            },
            splitPresentation: group.iconAsset == nil
                ? splitPresentation : nil,
            chromeTemplateSystemImageName: group.iconAsset.flatMap {
                SumiPersistentGlyph.presentsAsEmoji($0)
                    ? nil
                    : SumiPersistentGlyph.resolvedLauncherSystemImageName($0)
            },
            previewPresentationState: isGroupSelected
                ? .visuallySelected : .liveBackgrounded,
            exclusionZones: [.trailingStrip(32)],
            isEnabled: isInteractive
        )
    }
}
