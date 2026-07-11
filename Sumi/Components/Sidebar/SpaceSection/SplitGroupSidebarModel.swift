//
//  SplitGroupSidebarModel.swift
//  Sumi
//

import SumiDomain
import SwiftUI

/// Window presentation for one durable split member.
///
/// `id` is the canonical member identity. In particular, a shortcut segment
/// keeps its pin identity even when this window currently has a live tab for
/// it. That makes SwiftUI diffing, drag payloads, and delayed actions immune to
/// live-tab replacement.
struct SplitGroupSidebarItem: Identifiable {
    let member: SplitMember
    let tab: Tab?
    let pin: ShortcutPin?

    var id: SplitMemberID { member.memberID }

    var persistentID: UUID {
        switch id {
        case .regularTab(let tabID):
            return tabID
        case .shortcutPin(let pinID):
            return pinID
        }
    }

    var stableIDDescription: String {
        switch id {
        case .regularTab(let tabID):
            return "regular-tab-\(tabID.uuidString)"
        case .shortcutPin(let pinID):
            return "shortcut-pin-\(pinID.uuidString)"
        }
    }

    @MainActor
    var title: String {
        tab?.name ?? pin?.preferredDisplayTitle ?? "Split member"
    }

    @MainActor
    static func regular(_ member: SplitMember, tab: Tab) -> Self? {
        guard case .regularTab(let tabID) = member.memberID,
              tab.id == tabID else {
            return nil
        }
        return Self(member: member, tab: tab, pin: nil)
    }

    @MainActor
    static func shortcut(
        _ member: SplitMember,
        pin: ShortcutPin,
        liveTab: Tab?
    ) -> Self? {
        guard case .shortcutPin(let pinID) = member.memberID,
              pin.id == pinID,
              liveTab?.shortcutPinId == pinID || liveTab == nil else {
            return nil
        }
        return Self(member: member, tab: liveTab, pin: pin)
    }
}

enum SplitGroupSidebarSegmentAction {
    case close
    case restore

    var systemImageName: String {
        switch self {
        case .close:
            return "xmark"
        case .restore:
            return "arrow.uturn.backward"
        }
    }

    var accessibilityPrefix: String {
        switch self {
        case .close:
            return "space-split-tab-close"
        case .restore:
            return "space-split-segment-restore"
        }
    }

    var help: String {
        switch self {
        case .close:
            return "Close split segment"
        case .restore:
            return "Return pinned tab to original place"
        }
    }
}

enum SplitGroupSidebarModel {
    @MainActor
    static func items(
        for group: SplitGroup,
        tabManager: TabManager,
        windowID: UUID? = nil
    ) -> [SplitGroupSidebarItem] {
        group.members.compactMap { member in
            switch member.memberID {
            case .regularTab(let tabID):
                guard let tab = tabManager.tabCollectionMembershipOwner
                    .tab(for: tabID) else {
                    return nil
                }
                return .regular(member, tab: tab)

            case .shortcutPin(let pinID):
                guard let pin = tabManager.shortcutPinCollectionStateOwner
                    .shortcutPin(by: pinID) else {
                    return nil
                }
                let liveTab = windowID.flatMap { windowID in
                    tabManager.shortcutPresentationOwner.shortcutLiveTab(
                        for: pinID,
                        in: windowID
                    )
                }
                return .shortcut(member, pin: pin, liveTab: liveTab)
            }
        }
    }

    static func segmentAction(
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

    static func shortcutPin(
        for item: SplitGroupSidebarItem,
        member _: SplitMember?,
        tabManager _: TabManager
    ) -> ShortcutPin? {
        item.pin
    }

    static func sourceZone(
        for pin: ShortcutPin,
        fallbackSpaceId: UUID
    ) -> DropZoneID {
        switch pin.role {
        case .essential:
            return .essentials
        case .spacePinned:
            if let folderId = pin.folderId {
                return .folder(folderId)
            }
            return .spacePinned(pin.spaceId ?? fallbackSpaceId)
        }
    }
}
