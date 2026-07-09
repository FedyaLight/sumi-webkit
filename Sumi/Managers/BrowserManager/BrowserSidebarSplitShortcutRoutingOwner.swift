import Foundation

@MainActor
protocol BrowserSidebarSplitShortcutRouting: AnyObject {
    func focusSplitGroup(_ group: SplitGroup, in windowState: BrowserWindowState)
    func restoreShortcutSplitMember(
        _ itemId: UUID,
        from group: SplitGroup,
        in windowState: BrowserWindowState,
        preserveLiveInstance: Bool
    )
}

@MainActor
extension BrowserSidebarSplitShortcutRouting {
    func restoreShortcutSplitMember(
        _ itemId: UUID,
        from group: SplitGroup,
        in windowState: BrowserWindowState
    ) {
        restoreShortcutSplitMember(
            itemId,
            from: group,
            in: windowState,
            preserveLiveInstance: true
        )
    }
}

@MainActor
final class BrowserSidebarSplitShortcutRoutingOwner: BrowserSidebarSplitShortcutRouting {
    private let tabManager: @MainActor () -> TabManager
    private let splitManager: @MainActor () -> SplitViewManager
    private let space: @MainActor (UUID?) -> Space?
    private let setActiveSpace: @MainActor (Space, BrowserWindowState) -> Void
    private let selectTab: @MainActor (Tab, BrowserWindowState) -> Void
    private let refreshCompositor: @MainActor (BrowserWindowState) -> Void
    private let performImmediateVisualHandoffIfPossible: @MainActor (BrowserWindowState) -> Void
    private let persistWindowSession: @MainActor (BrowserWindowState) -> Void
    private let showEmptyState: @MainActor (BrowserWindowState) -> Void

    init(
        tabManager: @escaping @MainActor () -> TabManager,
        splitManager: @escaping @MainActor () -> SplitViewManager,
        space: @escaping @MainActor (UUID?) -> Space?,
        setActiveSpace: @escaping @MainActor (Space, BrowserWindowState) -> Void,
        selectTab: @escaping @MainActor (Tab, BrowserWindowState) -> Void,
        refreshCompositor: @escaping @MainActor (BrowserWindowState) -> Void,
        performImmediateVisualHandoffIfPossible: @escaping @MainActor (BrowserWindowState) -> Void,
        persistWindowSession: @escaping @MainActor (BrowserWindowState) -> Void,
        showEmptyState: @escaping @MainActor (BrowserWindowState) -> Void
    ) {
        self.tabManager = tabManager
        self.splitManager = splitManager
        self.space = space
        self.setActiveSpace = setActiveSpace
        self.selectTab = selectTab
        self.refreshCompositor = refreshCompositor
        self.performImmediateVisualHandoffIfPossible = performImmediateVisualHandoffIfPossible
        self.persistWindowSession = persistWindowSession
        self.showEmptyState = showEmptyState
    }

    func focusSplitGroup(_ group: SplitGroup, in windowState: BrowserWindowState) {
        if let hostSpaceId = group.hostSpaceId,
           windowState.currentSpaceId != hostSpaceId {
            windowState.pendingSplitGroupFocusRequest = SplitGroupFocusRequest(
                groupId: group.id,
                targetSpaceId: hostSpaceId
            )
            return
        }

        focusSplitGroupImmediately(group, in: windowState)
    }

    func completePendingSplitGroupFocusIfReady(in windowState: BrowserWindowState, spaceId: UUID) {
        guard let request = windowState.pendingSplitGroupFocusRequest,
              request.targetSpaceId == spaceId else {
            return
        }

        windowState.pendingSplitGroupFocusRequest = nil
        guard let group = tabManager().splitGroupCollectionStateOwner.group(with: request.groupId) else {
            refreshCompositor(windowState)
            return
        }
        focusSplitGroupImmediately(group, in: windowState)
    }

    func restoreShortcutSplitMember(
        _ itemId: UUID,
        from group: SplitGroup,
        in windowState: BrowserWindowState,
        preserveLiveInstance: Bool = true
    ) {
        let tabManager = tabManager()
        guard let member = splitMember(for: itemId, in: group),
              member.isShortcutBacked,
              let removalId = splitRemovalId(for: itemId, member: member, in: group)
        else {
            return
        }

        let restoredLiveTab = restoredLiveTab(for: itemId, member: member, in: windowState)
        let wasSelected = windowState.currentTabId == member.tabId
            || windowState.currentTabId == itemId
            || member.pinId == windowState.currentShortcutPinId

        let remainingGroup = group.removing(tabId: removalId)
        if let remainingGroup {
            tabManager.splitGroupStructureOwner.upsertSplitGroup(remainingGroup)
        } else {
            tabManager.splitGroupStructureOwner.removeSplitGroup(id: group.id)
        }

        restoreShortcutLauncherPosition(for: member)

        var didPrepareReplacementBeforeDeactivation = false
        if !preserveLiveInstance, wasSelected {
            if let remainingGroup {
                focusSplitGroup(remainingGroup, in: windowState)
                didPrepareReplacementBeforeDeactivation = true
            } else if let fallback = fallbackVisibleRegularTab(in: windowState) {
                selectTab(fallback, windowState)
                didPrepareReplacementBeforeDeactivation = true
            }

            if didPrepareReplacementBeforeDeactivation {
                performImmediateVisualHandoffIfPossible(windowState)
            }
        }

        if !preserveLiveInstance, let pinId = member.pinId {
            tabManager.shortcutLiveTabOwner.deactivateShortcutLiveTab(pinId: pinId, in: windowState.id)
        }

        if remainingGroup == nil, preserveLiveInstance, let restoredLiveTab {
            selectTab(restoredLiveTab, windowState)
        } else if wasSelected {
            if didPrepareReplacementBeforeDeactivation {
                persistWindowSession(windowState)
            } else if preserveLiveInstance, let restoredLiveTab {
                selectTab(restoredLiveTab, windowState)
            } else if let remainingGroup {
                focusSplitGroup(remainingGroup, in: windowState)
            } else if let fallback = fallbackVisibleRegularTab(in: windowState) {
                selectTab(fallback, windowState)
            } else {
                showEmptyState(windowState)
            }
        } else {
            refreshCompositor(windowState)
            persistWindowSession(windowState)
        }

        splitManager().refreshPublishedState(for: windowState.id)
    }

    func unloadShortcutHostedSplitGroup(_ group: SplitGroup, in windowState: BrowserWindowState) {
        guard group.isShortcutHosted else { return }

        let tabManager = tabManager()
        let fallback = fallbackVisibleRegularTab(in: windowState)
        if let fallback {
            selectTab(fallback, windowState)
            performImmediateVisualHandoffIfPossible(windowState)
        }

        var updatedGroup = group
        for member in group.members where member.isShortcutBacked {
            guard let pinId = member.pinId else { continue }
            if group.tabIds.contains(member.tabId) {
                updatedGroup = updatedGroup.replacingMemberTab(member.tabId, with: pinId)
            }
            tabManager.shortcutLiveTabOwner.deactivateShortcutLiveTab(pinId: pinId, in: windowState.id)
        }

        tabManager.splitGroupStructureOwner.upsertSplitGroup(updatedGroup.settingActiveTab(updatedGroup.tabIds.first))
        if fallback == nil {
            windowState.currentShortcutPinId = nil
            windowState.currentShortcutPinRole = nil
            windowState.currentTabId = nil
            showEmptyState(windowState)
        }
        splitManager().refreshPublishedState(for: windowState.id)
        refreshCompositor(windowState)
    }

    private func focusSplitGroupImmediately(_ group: SplitGroup, in windowState: BrowserWindowState) {
        let tabManager = tabManager()
        let resolvedGroup = materializeShortcutSplitMembers(in: group, windowState: windowState)

        if let hostSpaceId = resolvedGroup.hostSpaceId,
           windowState.currentSpaceId != hostSpaceId,
           let hostSpace = space(hostSpaceId) {
            setActiveSpace(hostSpace, windowState)
        }

        let targetTabId = resolvedGroup.activeTabId.flatMap { resolvedGroup.contains($0) ? $0 : nil }
            ?? resolvedGroup.tabIds.first
        guard let targetTab = targetTabId.flatMap({ tabManager.tabCollectionMembershipOwner.tab(for: $0) }) else {
            refreshCompositor(windowState)
            return
        }

        if tabManager.splitGroupCollectionStateOwner.group(with: resolvedGroup.id) == nil {
            tabManager.splitGroupStructureOwner.upsertSplitGroup(resolvedGroup)
        }
        selectTab(targetTab, windowState)
        splitManager().refreshPublishedState(for: windowState.id)
        refreshCompositor(windowState)
    }

    @discardableResult
    private func materializeShortcutSplitMembers(
        in group: SplitGroup,
        windowState: BrowserWindowState
    ) -> SplitGroup {
        let tabManager = tabManager()
        var updatedGroup = group
        var didChange = false

        for leafId in group.tabIds {
            if tabManager.tabCollectionMembershipOwner.tab(for: leafId) != nil {
                continue
            }

            guard let member = updatedGroup.member(for: leafId),
                  let pinId = member.pinId,
                  let pin = tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: pinId)
            else {
                continue
            }

            let liveTab = tabManager.shortcutLiveTabOwner.activateShortcutPin(
                pin,
                in: windowState.id,
                currentSpaceId: group.hostSpaceId ?? pin.spaceId ?? windowState.currentSpaceId
            )
            updatedGroup = updatedGroup.replacingMemberTab(leafId, with: liveTab.id)
            didChange = true
        }

        for member in updatedGroup.members where member.isShortcutBacked {
            guard let pinId = member.pinId,
                  updatedGroup.tabIds.contains(member.tabId),
                  tabManager.tabCollectionMembershipOwner.tab(for: member.tabId) == nil,
                  let pin = tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: pinId)
            else {
                continue
            }

            let liveTab = tabManager.shortcutLiveTabOwner.activateShortcutPin(
                pin,
                in: windowState.id,
                currentSpaceId: group.hostSpaceId ?? pin.spaceId ?? windowState.currentSpaceId
            )
            updatedGroup = updatedGroup.replacingMemberTab(member.tabId, with: liveTab.id)
            didChange = true
        }

        if didChange {
            tabManager.splitGroupStructureOwner.upsertSplitGroup(updatedGroup)
        }
        return updatedGroup
    }

    private func splitMember(for itemId: UUID, in group: SplitGroup) -> SplitGroupMember? {
        let tabManager = tabManager()
        if let direct = group.member(for: itemId) {
            return direct
        }
        if let tab = tabManager.tabCollectionMembershipOwner.tab(for: itemId), let pinId = tab.shortcutPinId {
            return group.member(forPinId: pinId)
        }
        return nil
    }

    private func splitRemovalId(
        for itemId: UUID,
        member: SplitGroupMember,
        in group: SplitGroup
    ) -> UUID? {
        if group.tabIds.contains(itemId) {
            return itemId
        }
        if group.tabIds.contains(member.tabId) {
            return member.tabId
        }
        if let pinId = member.pinId, group.tabIds.contains(pinId) {
            return pinId
        }
        return nil
    }

    private func restoredLiveTab(
        for itemId: UUID,
        member: SplitGroupMember,
        in windowState: BrowserWindowState
    ) -> Tab? {
        let tabManager = tabManager()
        if let tab = tabManager.tabCollectionMembershipOwner.tab(for: member.tabId) {
            return tab
        }
        if let tab = tabManager.tabCollectionMembershipOwner.tab(for: itemId) {
            return tab
        }
        if let pinId = member.pinId {
            return tabManager.shortcutPresentationOwner.shortcutLiveTab(for: pinId, in: windowState.id)
        }
        return nil
    }

    private func restoreShortcutLauncherPosition(for member: SplitGroupMember) {
        let tabManager = tabManager()
        guard let pinId = member.pinId,
              let pin = tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: pinId)
        else {
            return
        }

        switch member.origin {
        case .essential(let profileId, let index):
            guard let targetProfileId = profileId ?? pin.profileId else { return }
            _ = tabManager.shortcutPinCommandOwner.moveShortcutPin(
                pin,
                to: .essential,
                profileId: targetProfileId,
                spaceId: nil,
                folderId: nil,
                index: index,
                openTargetFolder: false
            )
        case .spacePinned(let spaceId, let folderId, let index):
            let targetFolderId = folderId.flatMap { folderId in
                tabManager.folderCollectionStateOwner.spaceId(for: folderId) == spaceId ? folderId : nil
            }
            _ = tabManager.shortcutPinCommandOwner.moveShortcutPin(
                pin,
                to: .spacePinned,
                profileId: nil,
                spaceId: spaceId,
                folderId: targetFolderId,
                index: index,
                openTargetFolder: targetFolderId != nil
            )
        case .generatedSpacePinnedFromRegular(let spaceId, _):
            _ = tabManager.shortcutPinCommandOwner.moveShortcutPin(
                pin,
                to: .spacePinned,
                profileId: nil,
                spaceId: spaceId,
                folderId: nil,
                index: tabManager.spacePinnedStructureOwner.topLevelSpacePinnedItems(for: spaceId).count,
                openTargetFolder: false
            )
        case .regular:
            break
        }
    }

    private func fallbackVisibleRegularTab(in windowState: BrowserWindowState) -> Tab? {
        let tabManager = tabManager()
        guard let currentSpaceId = windowState.currentSpaceId,
              let currentSpace = space(currentSpaceId)
        else {
            return nil
        }
        return tabManager.regularTabCollectionOwner.tabs(in: currentSpace).first
    }
}
