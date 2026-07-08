//
//  RegularSplitSegmentResolver.swift
//  Sumi
//

import Foundation

/// Resolves the display/action/drag semantics for a single segment (tab or
/// shortcut-backed placeholder) inside a split group rendered in the regular
/// tabs section of a space. Pure decision logic — no environment/state
/// dependencies — so it can be exercised directly in tests.
@MainActor
struct RegularSplitSegmentResolver {
    let space: Space
    let isInteractive: Bool

    /// Visible split groups for the current tab list: dragging suppresses all
    /// split-group rendering, and each group must still contain at least the
    /// minimum member count and at least one currently-visible tab.
    func visibleSplitGroups(
        currentTabs: [Tab],
        isDragging: Bool,
        splitGroup: (UUID) -> SplitGroup?
    ) -> [SplitGroup] {
        guard !isDragging else { return [] }
        let currentTabIds = Set(currentTabs.map(\.id))
        var seenGroupIds = Set<UUID>()
        return currentTabs.compactMap { tab in
            guard let group = splitGroup(tab.id),
                  !group.isShortcutHosted,
                  seenGroupIds.insert(group.id).inserted,
                  group.tabIds.count >= SplitGroup.minimumTabs,
                  group.tabIds.contains(where: { currentTabIds.contains($0) })
            else {
                return nil
            }
            return group
        }
    }

    func splitGroupItems(
        for group: SplitGroup,
        tabById: [UUID: Tab],
        liveTab: (UUID) -> Tab?,
        shortcutPin: (UUID) -> ShortcutPin?
    ) -> [SplitGroupSidebarItem] {
        group.tabIds.compactMap { id in
            if let tab = tabById[id] ?? liveTab(id) {
                return .tab(tab)
            }
            if let pinId = group.member(for: id)?.pinId,
               let pin = shortcutPin(pinId) {
                return .pin(pin)
            }
            if let pin = shortcutPin(id) {
                return .pin(pin)
            }
            return nil
        }
    }

    func action(
        for item: SplitGroupSidebarItem,
        in group: SplitGroup
    ) -> SplitGroupSidebarSegmentAction? {
        if member(for: item, in: group)?.isShortcutBacked == true {
            return .restore
        }
        return item.tab == nil ? nil : .close
    }

    func member(
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

    func shortcutPin(
        for item: SplitGroupSidebarItem,
        member: SplitGroupMember?,
        shortcutPin: (UUID) -> ShortcutPin?
    ) -> ShortcutPin? {
        if let pin = item.pin {
            return pin
        }
        if let pinId = item.tab?.shortcutPinId ?? member?.pinId {
            return shortcutPin(pinId)
        }
        return nil
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
        shortcutPin: (UUID) -> ShortcutPin?,
        onActivateTab: @escaping (Tab) -> Void,
        onActivateGroup: @escaping () -> Void
    ) -> SidebarDragSourceConfiguration? {
        let resolvedMember = member(for: item, in: group)
        if let pin = self.shortcutPin(for: item, member: resolvedMember, shortcutPin: shortcutPin) {
            let dragItemId = item.tab?.id ?? pin.id
            return SidebarDragSourceConfiguration(
                item: SumiDragItem(
                    tabId: dragItemId,
                    title: item.title,
                    urlString: item.tab?.url.absoluteString ?? pin.launchURL.absoluteString
                ),
                sourceZone: sourceZone(for: pin),
                previewKind: .row,
                previewIcon: item.tab?.favicon ?? pin.storedFavicon,
                exclusionZones: [.trailingStrip(32)],
                onActivate: {
                    if let tab = item.tab {
                        onActivateTab(tab)
                    } else {
                        onActivateGroup()
                    }
                },
                isEnabled: isInteractive
            )
        }

        guard let tab = item.tab else { return nil }
        return SidebarDragSourceConfiguration(
            item: SumiDragItem(
                tabId: tab.id,
                title: tab.name,
                urlString: tab.url.absoluteString
            ),
            sourceZone: .spaceRegular(space.id),
            previewKind: .row,
            previewIcon: tab.favicon,
            exclusionZones: [.trailingStrip(32)],
            onActivate: { onActivateTab(tab) },
            isEnabled: isInteractive
        )
    }
}
