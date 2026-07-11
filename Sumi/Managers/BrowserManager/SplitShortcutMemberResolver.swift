import Foundation

struct SplitShortcutMemberResolution {
    let member: SplitGroupMember
    let removalId: UUID
    let restoredLiveTab: Tab?
}

/// Resolves persisted pin identities and window-local live tab identities
/// without retaining browser state or performing mutations.
@MainActor
enum SplitShortcutMemberResolver {
    static func resolve(
        itemId: UUID,
        in group: SplitGroup,
        windowState: BrowserWindowState,
        tabManager: TabManager
    ) -> SplitShortcutMemberResolution? {
        guard let member = member(
            for: itemId,
            in: group,
            tabManager: tabManager
        ), member.isShortcutBacked,
           let removalId = removalId(
               for: itemId,
               member: member,
               in: group
           ) else {
            return nil
        }
        return SplitShortcutMemberResolution(
            member: member,
            removalId: removalId,
            restoredLiveTab: restoredLiveTab(
                for: itemId,
                member: member,
                in: windowState,
                tabManager: tabManager
            )
        )
    }

    private static func member(
        for itemId: UUID,
        in group: SplitGroup,
        tabManager: TabManager
    ) -> SplitGroupMember? {
        if let direct = group.member(for: itemId) { return direct }
        guard let pinId = tabManager.tabCollectionMembershipOwner
            .tab(for: itemId)?.shortcutPinId else { return nil }
        return group.member(forPinId: pinId)
    }

    private static func removalId(
        for itemId: UUID,
        member: SplitGroupMember,
        in group: SplitGroup
    ) -> UUID? {
        if group.tabIds.contains(itemId) { return itemId }
        if group.tabIds.contains(member.tabId) { return member.tabId }
        guard let pinId = member.pinId,
              group.tabIds.contains(pinId) else { return nil }
        return pinId
    }

    private static func restoredLiveTab(
        for itemId: UUID,
        member: SplitGroupMember,
        in windowState: BrowserWindowState,
        tabManager: TabManager
    ) -> Tab? {
        if let tab = tabManager.tabCollectionMembershipOwner
            .tab(for: member.tabId) {
            return tab
        }
        if let tab = tabManager.tabCollectionMembershipOwner.tab(for: itemId) {
            return tab
        }
        guard let pinId = member.pinId else { return nil }
        return tabManager.shortcutPresentationOwner.shortcutLiveTab(
            for: pinId,
            in: windowState.id
        )
    }
}
