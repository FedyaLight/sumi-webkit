import Foundation

@MainActor
final class BrowserSidebarSplitShortcutRoutingOwner {
    struct Dependencies {
        let tabManager: @MainActor () -> TabManager
        let splitManager: @MainActor () -> SplitViewManager
        let space: @MainActor (UUID?) -> Space?
        let setActiveSpace: @MainActor (Space, BrowserWindowState) -> Void
        let selectTab: @MainActor (Tab, BrowserWindowState) -> Void
        let refreshCompositor: @MainActor (BrowserWindowState) -> Void
        let performImmediateVisualHandoffIfPossible: @MainActor (BrowserWindowState) -> Void
        let persistWindowSession: @MainActor (BrowserWindowState) -> Void
        let showEmptyState: @MainActor (BrowserWindowState) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
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
        guard let group = dependencies.tabManager().splitGroup(with: request.groupId) else {
            dependencies.refreshCompositor(windowState)
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
        let tabManager = dependencies.tabManager()
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

        var didPrepareReplacementBeforeDeactivation = false
        if !preserveLiveInstance, wasSelected {
            if let remainingGroup {
                focusSplitGroup(remainingGroup, in: windowState)
                didPrepareReplacementBeforeDeactivation = true
            } else if let fallback = fallbackVisibleRegularTab(in: windowState) {
                dependencies.selectTab(fallback, windowState)
                didPrepareReplacementBeforeDeactivation = true
            }

            if didPrepareReplacementBeforeDeactivation {
                dependencies.performImmediateVisualHandoffIfPossible(windowState)
            }
        }

        if !preserveLiveInstance, let pinId = member.pinId {
            tabManager.deactivateShortcutLiveTab(pinId: pinId, in: windowState.id)
        }

        if remainingGroup == nil, preserveLiveInstance, let restoredLiveTab {
            dependencies.selectTab(restoredLiveTab, windowState)
        } else if wasSelected {
            if didPrepareReplacementBeforeDeactivation {
                dependencies.persistWindowSession(windowState)
            } else if preserveLiveInstance, let restoredLiveTab {
                dependencies.selectTab(restoredLiveTab, windowState)
            } else if let remainingGroup {
                focusSplitGroup(remainingGroup, in: windowState)
            } else if let fallback = fallbackVisibleRegularTab(in: windowState) {
                dependencies.selectTab(fallback, windowState)
            } else {
                dependencies.showEmptyState(windowState)
            }
        } else {
            dependencies.refreshCompositor(windowState)
            dependencies.persistWindowSession(windowState)
        }

        dependencies.splitManager().refreshPublishedState(for: windowState.id)
    }

    func unloadShortcutHostedSplitGroup(_ group: SplitGroup, in windowState: BrowserWindowState) {
        guard group.isShortcutHosted else { return }

        let tabManager = dependencies.tabManager()
        let fallback = fallbackVisibleRegularTab(in: windowState)
        if let fallback {
            dependencies.selectTab(fallback, windowState)
            dependencies.performImmediateVisualHandoffIfPossible(windowState)
        }

        var updatedGroup = group
        for member in group.members where member.isShortcutBacked {
            guard let pinId = member.pinId else { continue }
            if group.tabIds.contains(member.tabId) {
                updatedGroup = updatedGroup.replacingMemberTab(member.tabId, with: pinId)
            }
            tabManager.deactivateShortcutLiveTab(pinId: pinId, in: windowState.id)
        }

        tabManager.upsertSplitGroup(updatedGroup.settingActiveTab(updatedGroup.tabIds.first))
        if fallback == nil {
            windowState.currentShortcutPinId = nil
            windowState.currentShortcutPinRole = nil
            windowState.currentTabId = nil
            dependencies.showEmptyState(windowState)
        }
        dependencies.splitManager().refreshPublishedState(for: windowState.id)
        dependencies.refreshCompositor(windowState)
    }

    private func focusSplitGroupImmediately(_ group: SplitGroup, in windowState: BrowserWindowState) {
        let tabManager = dependencies.tabManager()
        let resolvedGroup = materializeShortcutSplitMembers(in: group, windowState: windowState)

        if let hostSpaceId = resolvedGroup.hostSpaceId,
           windowState.currentSpaceId != hostSpaceId,
           let hostSpace = dependencies.space(hostSpaceId) {
            dependencies.setActiveSpace(hostSpace, windowState)
        }

        let targetTabId = resolvedGroup.activeTabId.flatMap { resolvedGroup.contains($0) ? $0 : nil }
            ?? resolvedGroup.tabIds.first
        guard let targetTab = targetTabId.flatMap({ tabManager.tab(for: $0) }) else {
            dependencies.refreshCompositor(windowState)
            return
        }

        if tabManager.splitGroup(with: resolvedGroup.id) == nil {
            tabManager.upsertSplitGroup(resolvedGroup)
        }
        dependencies.selectTab(targetTab, windowState)
        dependencies.splitManager().refreshPublishedState(for: windowState.id)
        dependencies.refreshCompositor(windowState)
    }

    @discardableResult
    private func materializeShortcutSplitMembers(
        in group: SplitGroup,
        windowState: BrowserWindowState
    ) -> SplitGroup {
        let tabManager = dependencies.tabManager()
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
        let tabManager = dependencies.tabManager()
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
        let tabManager = dependencies.tabManager()
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
        let tabManager = dependencies.tabManager()
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
        let tabManager = dependencies.tabManager()
        guard let currentSpaceId = windowState.currentSpaceId,
              let currentSpace = dependencies.space(currentSpaceId)
        else {
            return nil
        }
        return tabManager.tabs(in: currentSpace).first
    }
}

extension BrowserSidebarSplitShortcutRoutingOwner.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        let tabManager = browserManager.tabManager
        let splitManager = browserManager.splitManager
        return Self(
            tabManager: { [weak browserManager] in
                browserManager?.tabManager ?? tabManager
            },
            splitManager: { [weak browserManager] in
                browserManager?.splitManager ?? splitManager
            },
            space: { [weak browserManager] spaceId in
                browserManager?.space(for: spaceId)
            },
            setActiveSpace: { [weak browserManager] space, windowState in
                browserManager?.setActiveSpace(space, in: windowState)
            },
            selectTab: { [weak browserManager] tab, windowState in
                browserManager?.selectTab(tab, in: windowState)
            },
            refreshCompositor: { [weak browserManager] windowState in
                browserManager?.refreshCompositor(for: windowState)
            },
            performImmediateVisualHandoffIfPossible: { [weak browserManager] windowState in
                _ = browserManager?.performImmediateVisualHandoffIfPossible(in: windowState)
            },
            persistWindowSession: { [weak browserManager] windowState in
                browserManager?.persistWindowSession(for: windowState)
            },
            showEmptyState: { [weak browserManager] windowState in
                browserManager?.showEmptyState(in: windowState)
            }
        )
    }
}
