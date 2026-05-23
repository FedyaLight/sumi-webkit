import Foundation

@MainActor
extension BrowserManager {
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
        guard let group = tabManager.splitGroup(with: request.groupId) else {
            refreshCompositor(for: windowState)
            return
        }
        focusSplitGroupImmediately(group, in: windowState)
    }

    private func focusSplitGroupImmediately(_ group: SplitGroup, in windowState: BrowserWindowState) {
        let resolvedGroup = materializeShortcutSplitMembers(in: group, windowState: windowState)

        if let hostSpaceId = resolvedGroup.hostSpaceId,
           windowState.currentSpaceId != hostSpaceId,
           let hostSpace = space(for: hostSpaceId) {
            setActiveSpace(hostSpace, in: windowState)
        }

        let targetTabId = resolvedGroup.activeTabId.flatMap { resolvedGroup.contains($0) ? $0 : nil }
            ?? resolvedGroup.tabIds.first
        guard let targetTab = targetTabId.flatMap({ tabManager.tab(for: $0) }) else {
            refreshCompositor(for: windowState)
            return
        }

        if tabManager.splitGroup(with: resolvedGroup.id) == nil {
            tabManager.upsertSplitGroup(resolvedGroup)
        }
        selectTab(targetTab, in: windowState)
        splitManager.refreshPublishedState(for: windowState.id)
        refreshCompositor(for: windowState)
    }

    func restoreShortcutSplitMember(
        _ itemId: UUID,
        from group: SplitGroup,
        in windowState: BrowserWindowState,
        preserveLiveInstance: Bool = true
    ) {
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
            tabManager.upsertSplitGroup(remainingGroup)
        } else {
            tabManager.removeSplitGroup(id: group.id)
        }

        restoreShortcutLauncherPosition(for: member)

        if !preserveLiveInstance, let pinId = member.pinId {
            tabManager.deactivateShortcutLiveTab(pinId: pinId, in: windowState.id)
        }

        if remainingGroup == nil, preserveLiveInstance, let restoredLiveTab {
            selectTab(restoredLiveTab, in: windowState)
        } else if wasSelected {
            if preserveLiveInstance, let restoredLiveTab {
                selectTab(restoredLiveTab, in: windowState)
            } else if let remainingGroup {
                focusSplitGroup(remainingGroup, in: windowState)
            } else if let fallback = fallbackVisibleRegularTab(in: windowState) {
                selectTab(fallback, in: windowState)
            } else {
                showEmptyState(in: windowState)
            }
        } else {
            refreshCompositor(for: windowState)
            persistWindowSession(for: windowState)
        }

        splitManager.refreshPublishedState(for: windowState.id)
    }

    func unloadShortcutHostedSplitGroup(_ group: SplitGroup, in windowState: BrowserWindowState) {
        guard group.isShortcutHosted else { return }

        var updatedGroup = group
        for member in group.members where member.isShortcutBacked {
            guard let pinId = member.pinId else { continue }
            if group.tabIds.contains(member.tabId) {
                updatedGroup = updatedGroup.replacingMemberTab(member.tabId, with: pinId)
            }
            tabManager.deactivateShortcutLiveTab(pinId: pinId, in: windowState.id)
        }

        tabManager.upsertSplitGroup(updatedGroup.settingActiveTab(updatedGroup.tabIds.first))
        windowState.currentShortcutPinId = nil
        windowState.currentShortcutPinRole = nil
        windowState.currentTabId = nil

        if let fallback = fallbackVisibleRegularTab(in: windowState) {
            selectTab(fallback, in: windowState)
        } else {
            showEmptyState(in: windowState)
        }
        splitManager.refreshPublishedState(for: windowState.id)
        refreshCompositor(for: windowState)
    }

    @discardableResult
    private func materializeShortcutSplitMembers(
        in group: SplitGroup,
        windowState: BrowserWindowState
    ) -> SplitGroup {
        var updatedGroup = group
        var didChange = false

        for leafId in group.tabIds {
            if tabManager.tab(for: leafId) != nil {
                continue
            }

            guard let member = updatedGroup.member(for: leafId),
                  let pinId = member.pinId,
                  let pin = tabManager.shortcutPin(by: pinId)
            else {
                continue
            }

            let liveTab = tabManager.activateShortcutPin(
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
                  tabManager.tab(for: member.tabId) == nil,
                  let pin = tabManager.shortcutPin(by: pinId)
            else {
                continue
            }

            let liveTab = tabManager.activateShortcutPin(
                pin,
                in: windowState.id,
                currentSpaceId: group.hostSpaceId ?? pin.spaceId ?? windowState.currentSpaceId
            )
            updatedGroup = updatedGroup.replacingMemberTab(member.tabId, with: liveTab.id)
            didChange = true
        }

        if didChange {
            tabManager.upsertSplitGroup(updatedGroup)
        }
        return updatedGroup
    }

    private func splitMember(for itemId: UUID, in group: SplitGroup) -> SplitGroupMember? {
        if let direct = group.member(for: itemId) {
            return direct
        }
        if let tab = tabManager.tab(for: itemId), let pinId = tab.shortcutPinId {
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
        if let tab = tabManager.tab(for: member.tabId) {
            return tab
        }
        if let tab = tabManager.tab(for: itemId) {
            return tab
        }
        if let pinId = member.pinId {
            return tabManager.shortcutLiveTab(for: pinId, in: windowState.id)
        }
        return nil
    }

    private func restoreShortcutLauncherPosition(for member: SplitGroupMember) {
        guard let pinId = member.pinId,
              let pin = tabManager.shortcutPin(by: pinId)
        else {
            return
        }

        switch member.origin {
        case .essential(let profileId, let index):
            guard let targetProfileId = profileId ?? pin.profileId else { return }
            _ = tabManager.moveShortcutPin(
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
                tabManager.folderSpaceId(for: folderId) == spaceId ? folderId : nil
            }
            _ = tabManager.moveShortcutPin(
                pin,
                to: .spacePinned,
                profileId: nil,
                spaceId: spaceId,
                folderId: targetFolderId,
                index: index,
                openTargetFolder: targetFolderId != nil
            )
        case .generatedSpacePinnedFromRegular(let spaceId, _):
            _ = tabManager.moveShortcutPin(
                pin,
                to: .spacePinned,
                profileId: nil,
                spaceId: spaceId,
                folderId: nil,
                index: tabManager.topLevelSpacePinnedItems(for: spaceId).count,
                openTargetFolder: false
            )
        case .regular:
            break
        }
    }

    private func fallbackVisibleRegularTab(in windowState: BrowserWindowState) -> Tab? {
        guard let currentSpaceId = windowState.currentSpaceId,
              let currentSpace = space(for: currentSpaceId)
        else {
            return tabManager.tabs.first
        }
        return tabManager.tabs(in: currentSpace).first
    }
}
