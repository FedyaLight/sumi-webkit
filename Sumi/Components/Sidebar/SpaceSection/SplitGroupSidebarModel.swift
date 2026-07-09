//
//  SplitGroupSidebarModel.swift
//  Sumi
//

import SwiftUI

import SwiftUI

enum SplitGroupSidebarItem: Identifiable {
    case tab(Tab)
    case pin(ShortcutPin)

    var id: UUID {
        switch self {
        case .tab(let tab):
            return tab.id
        case .pin(let pin):
            return pin.id
        }
    }

    @MainActor
    var title: String {
        switch self {
        case .tab(let tab):
            return tab.name
        case .pin(let pin):
            return pin.preferredDisplayTitle
        }
    }

    var tab: Tab? {
        if case .tab(let tab) = self { return tab }
        return nil
    }

    var pin: ShortcutPin? {
        if case .pin(let pin) = self { return pin }
        return nil
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
    static func items(for group: SplitGroup, tabManager: TabManager) -> [SplitGroupSidebarItem] {
        group.tabIds.compactMap { id in
            if let tab = tabManager.tabCollectionMembershipOwner.tab(for: id) {
                return .tab(tab)
            }
            if let pinId = group.member(for: id)?.pinId,
               let pin = tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: pinId) {
                return .pin(pin)
            }
            if let pin = tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: id) {
                return .pin(pin)
            }
            return nil
        }
    }

    @MainActor
    static func member(
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

    @MainActor
    static func segmentAction(
        for item: SplitGroupSidebarItem,
        in group: SplitGroup
    ) -> SplitGroupSidebarSegmentAction? {
        if member(for: item, in: group)?.isShortcutBacked == true {
            return .restore
        }
        return item.tab == nil ? nil : .close
    }

    @MainActor
    static func shortcutPin(
        for item: SplitGroupSidebarItem,
        member: SplitGroupMember?,
        tabManager: TabManager
    ) -> ShortcutPin? {
        if let pin = item.pin {
            return pin
        }
        if let pinId = item.tab?.shortcutPinId ?? member?.pinId {
            return tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: pinId)
        }
        return nil
    }

    static func sourceZone(for pin: ShortcutPin, fallbackSpaceId: UUID) -> DropZoneID {
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
