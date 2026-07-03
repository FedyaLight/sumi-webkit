import Foundation

/// Resolves candidate tabs into split-group membership: mapping dragged tabs and shortcut
/// pins to their live tab instances, computing the group host and member origins, and
/// locating the source group entries a moved tab must be removed from.
@MainActor
final class SplitMembershipResolutionOwner {
    struct ResolvedSplitTab {
        let tab: Tab
        let member: SplitGroupMember
    }

    private let tabManager: @MainActor () -> TabManager?

    init(tabManager: @escaping @MainActor () -> TabManager?) {
        self.tabManager = tabManager
    }

    func resolvedSplitTab(
        _ candidate: Tab,
        host: SplitGroupHost,
        sourceGroup: SplitGroup?,
        in windowState: BrowserWindowState
    ) -> ResolvedSplitTab? {
        guard let tabManager = tabManager() else { return nil }

        let sourceMember = sourceMember(for: candidate, sourceGroup: sourceGroup)
        let sourcePin = sourceMember?.pinId.flatMap { tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: $0) }
        if let pin = shortcutPin(for: candidate) ?? sourcePin {
            let liveTab = resolvedLiveShortcutTab(for: pin, candidate: candidate, in: windowState)
            guard let origin = sourceMember?.origin
                ?? splitMemberOrigin(for: pin, host: host, windowState: windowState)
            else {
                return nil
            }
            return ResolvedSplitTab(
                tab: liveTab,
                member: SplitGroupMember(
                    tabId: liveTab.id,
                    pinId: pin.id,
                    origin: origin
                )
            )
        }

        if host.isShortcutPinned {
            guard let spaceId = host.spaceId ?? candidate.spaceId ?? windowState.currentSpaceId else {
                return nil
            }
            let insertionIndex = tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: spaceId).count
            guard let pin = tabManager.convertTabToShortcutPin(
                candidate,
                role: .spacePinned,
                profileId: nil,
                spaceId: spaceId,
                folderId: nil,
                at: insertionIndex,
                openTargetFolder: false
            ),
            let liveTab = tabManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: windowState.id)
            else {
                return nil
            }
            return ResolvedSplitTab(
                tab: liveTab,
                member: SplitGroupMember(
                    tabId: liveTab.id,
                    pinId: pin.id,
                    origin: .generatedSpacePinnedFromRegular(spaceId: spaceId, index: insertionIndex)
                )
            )
        }

        return ResolvedSplitTab(
            tab: candidate,
            member: sourceMember ?? SplitGroupMember(
                tabId: candidate.id,
                pinId: nil,
                origin: .regular(spaceId: candidate.spaceId, index: candidate.index)
            )
        )
    }

    func initialHost(
        for incoming: Tab,
        targetTab: Tab,
        in windowState: BrowserWindowState
    ) -> SplitGroupHost {
        let incomingPin = shortcutPin(for: incoming)
        let targetPin = shortcutPin(for: targetTab)
        if incomingPin != nil, targetPin != nil {
            let spaceId = incomingPin?.spaceId
                ?? targetPin?.spaceId
                ?? targetTab.spaceId
                ?? incoming.spaceId
                ?? windowState.currentSpaceId
            if let spaceId {
                return .shortcutPinned(
                    spaceId: spaceId,
                    profileId: incomingPin?.profileId ?? targetPin?.profileId ?? windowState.currentProfileId,
                    index: initialShortcutHostIndex(
                        incomingPin: incomingPin,
                        targetPin: targetPin,
                        incomingTab: incoming,
                        targetTab: targetTab,
                        in: windowState
                    )
                )
            }
        }

        return .regular(spaceId: targetTab.spaceId ?? incoming.spaceId ?? windowState.currentSpaceId)
    }

    func sourceSplitGroup(for tab: Tab) -> SplitGroup? {
        guard let tabManager = tabManager() else { return nil }
        if let group = tabManager.splitGroupStructureOwner.splitGroup(containing: tab.id) {
            return group
        }
        if let pinId = tab.shortcutPinId,
           let group = tabManager.splitGroupStructureOwner.splitGroup(containingPinId: pinId) {
            return group
        }
        if let pin = tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: tab.id),
           let group = tabManager.splitGroupStructureOwner.splitGroup(containingPinId: pin.id) {
            return group
        }
        return nil
    }

    func sourceRemovalId(for tab: Tab, in sourceGroup: SplitGroup?) -> UUID? {
        guard let sourceGroup else { return nil }
        if sourceGroup.tabIds.contains(tab.id) {
            return tab.id
        }

        if let pinId = tab.shortcutPinId ?? tabManager()?.shortcutPinCollectionStateOwner.shortcutPin(by: tab.id)?.id,
           let member = sourceGroup.member(forPinId: pinId) {
            if sourceGroup.tabIds.contains(member.tabId) {
                return member.tabId
            }
            if sourceGroup.tabIds.contains(pinId) {
                return pinId
            }
        }

        guard let member = sourceGroup.member(for: tab.id) else {
            return nil
        }
        if sourceGroup.tabIds.contains(member.tabId) {
            return member.tabId
        }
        if let pinId = member.pinId, sourceGroup.tabIds.contains(pinId) {
            return pinId
        }
        return nil
    }

    func preferredFocusTabAfterUnsplit(
        _ group: SplitGroup,
        in windowState: BrowserWindowState
    ) -> Tab? {
        let candidateIds = [
            windowState.currentTabId,
            group.activeTabId,
        ] + group.tabIds.map(Optional.some)

        for candidateId in candidateIds {
            guard let candidateId else { continue }
            if let tab = tabManager()?.tab(for: candidateId) {
                return tab
            }
            if let pinId = group.member(for: candidateId)?.pinId,
               let tab = tabManager()?.shortcutPresentationOwner.shortcutLiveTab(for: pinId, in: windowState.id) {
                return tab
            }
            if let tab = tabManager()?.shortcutPresentationOwner.shortcutLiveTab(for: candidateId, in: windowState.id) {
                return tab
            }
        }
        return nil
    }

    private func initialShortcutHostIndex(
        incomingPin: ShortcutPin?,
        targetPin: ShortcutPin?,
        incomingTab: Tab,
        targetTab: Tab,
        in windowState: BrowserWindowState
    ) -> Int? {
        let pins = [incomingPin, targetPin].compactMap { $0 }
        let spacePinnedPins = pins.filter { $0.role == .spacePinned }
        guard !spacePinnedPins.isEmpty else { return 0 }

        if let focusedPin = spacePinnedPins.first(where: { pin in
            windowState.currentShortcutPinId == pin.id
                || windowState.currentTabId == incomingTab.id && incomingPin?.id == pin.id
                || windowState.currentTabId == targetTab.id && targetPin?.id == pin.id
        }) {
            return focusedPin.index
        }

        return targetPin?.role == .spacePinned ? targetPin?.index : incomingPin?.index
    }

    private func shortcutPin(for tab: Tab) -> ShortcutPin? {
        guard let tabManager = tabManager() else { return nil }
        if let shortcutPinId = tab.shortcutPinId,
           let pin = tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: shortcutPinId) {
            return pin
        }
        if let pin = tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: tab.id) {
            return pin
        }
        return nil
    }

    private func sourceMember(
        for tab: Tab,
        sourceGroup: SplitGroup?
    ) -> SplitGroupMember? {
        guard let tabManager = tabManager() else { return nil }
        let pinId = tab.shortcutPinId ?? tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: tab.id)?.id
        let candidateGroups: [SplitGroup?] = [
            sourceGroup,
            tabManager.splitGroupStructureOwner.splitGroup(containing: tab.id),
            pinId.flatMap { tabManager.splitGroupStructureOwner.splitGroup(containingPinId: $0) },
        ]
        var seenGroupIds = Set<UUID>()
        for group in candidateGroups.compactMap({ $0 }) where seenGroupIds.insert(group.id).inserted {
            if let pinId, let member = group.member(forPinId: pinId) {
                return member
            }
            if let member = group.member(for: tab.id) {
                return member
            }
        }
        return nil
    }

    private func resolvedLiveShortcutTab(
        for pin: ShortcutPin,
        candidate: Tab,
        in windowState: BrowserWindowState
    ) -> Tab {
        guard let tabManager = tabManager() else { return candidate }
        if candidate.isShortcutLiveInstance,
           candidate.shortcutPinId == pin.id,
           tabManager.tab(for: candidate.id) != nil {
            return candidate
        }
        if let liveTab = tabManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: windowState.id) {
            return liveTab
        }
        return tabManager.activateShortcutPin(
            pin,
            in: windowState.id,
            currentSpaceId: pin.spaceId ?? windowState.currentSpaceId
        )
    }

    private func splitMemberOrigin(
        for pin: ShortcutPin,
        host: SplitGroupHost,
        windowState: BrowserWindowState
    ) -> SplitGroupMemberOrigin? {
        switch pin.role {
        case .essential:
            return .essential(profileId: pin.profileId, index: pin.index)
        case .spacePinned:
            guard let spaceId = pin.spaceId ?? host.spaceId ?? windowState.currentSpaceId else {
                return nil
            }
            return .spacePinned(
                spaceId: spaceId,
                folderId: pin.folderId,
                index: pin.index
            )
        }
    }
}
