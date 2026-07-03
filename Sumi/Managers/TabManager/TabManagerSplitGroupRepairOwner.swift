import Foundation

@MainActor
final class TabManagerSplitGroupRepairOwner {
    struct Dependencies {
        let shortcutPin: @MainActor (UUID) -> ShortcutPin?
        let tab: @MainActor (UUID) -> Tab?
        let folderSpaceId: @MainActor (UUID) -> UUID?
        let spaceExists: @MainActor (UUID) -> Bool
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func repairingShortcutBackedMembers(in group: SplitGroup) -> SplitGroup {
        var members = group.members
        var didRepair = false

        for leafId in group.tabIds {
            guard let pin = shortcutPinForSplitLeaf(leafId) else {
                continue
            }

            let existingMember = group.member(for: leafId) ?? group.member(forPinId: pin.id)
            guard let repairedOrigin = repairedSplitMemberOrigin(
                existingMember: existingMember,
                pin: pin,
                in: group
            ) else {
                let filteredMembers = members.filter { member in
                    member.tabId != leafId
                        && member.pinId != pin.id
                        && member.stableId != pin.id
                }
                if filteredMembers.count != members.count {
                    didRepair = true
                    members = filteredMembers
                }
                continue
            }
            let repairedMember = SplitGroupMember(
                tabId: leafId,
                pinId: pin.id,
                origin: repairedOrigin
            )

            let filteredMembers = members.filter { member in
                member.tabId != leafId
                    && member.pinId != pin.id
                    && member.stableId != repairedMember.stableId
            }
            if filteredMembers.count != members.count || existingMember != repairedMember {
                didRepair = true
            }
            members = filteredMembers + [repairedMember]
        }

        guard didRepair else { return group }
        return group.settingMembers(members)
    }

    private func repairedSplitMemberOrigin(
        existingMember: SplitGroupMember?,
        pin: ShortcutPin,
        in group: SplitGroup
    ) -> SplitGroupMemberOrigin? {
        if let existingOrigin = existingMember?.origin,
           isValidShortcutBackedOrigin(existingOrigin, for: pin, in: group) {
            return existingOrigin
        }
        return splitMemberOrigin(for: pin, in: group)
    }

    private func isValidShortcutBackedOrigin(
        _ origin: SplitGroupMemberOrigin,
        for pin: ShortcutPin,
        in group: SplitGroup
    ) -> Bool {
        switch (pin.role, origin) {
        case (.essential, .essential(let profileId, _)):
            return pin.profileId.map { $0 == profileId } ?? true
        case (.spacePinned, .spacePinned(let spaceId, let folderId, _)):
            guard resolvedSpacePinnedOriginSpaceId(for: pin, in: group) == spaceId else {
                return false
            }
            return folderId.map { dependencies.folderSpaceId($0) == spaceId } ?? true
        case (.spacePinned, .generatedSpacePinnedFromRegular(let spaceId, _)):
            return resolvedSpacePinnedOriginSpaceId(for: pin, in: group) == spaceId
        default:
            return false
        }
    }

    private func shortcutPinForSplitLeaf(_ leafId: UUID) -> ShortcutPin? {
        if let pin = dependencies.shortcutPin(leafId) {
            return pin
        }
        guard let pinId = dependencies.tab(leafId)?.shortcutPinId else {
            return nil
        }
        return dependencies.shortcutPin(pinId)
    }

    private func splitMemberOrigin(for pin: ShortcutPin, in group: SplitGroup) -> SplitGroupMemberOrigin? {
        switch pin.role {
        case .essential:
            return .essential(profileId: pin.profileId, index: pin.index)
        case .spacePinned:
            guard let spaceId = resolvedSpacePinnedOriginSpaceId(for: pin, in: group) else {
                return nil
            }
            return .spacePinned(
                spaceId: spaceId,
                folderId: pin.folderId.flatMap {
                    dependencies.folderSpaceId($0) == spaceId ? $0 : nil
                },
                index: pin.index
            )
        }
    }

    private func resolvedSpacePinnedOriginSpaceId(for pin: ShortcutPin, in group: SplitGroup) -> UUID? {
        if let spaceId = pin.spaceId,
           dependencies.spaceExists(spaceId) {
            return spaceId
        }
        if let spaceId = group.hostSpaceId,
           dependencies.spaceExists(spaceId) {
            return spaceId
        }
        return nil
    }
}

@MainActor
extension TabManagerSplitGroupRepairOwner.Dependencies {
    static func live(tabManager: TabManager) -> Self {
        Self(
            shortcutPin: { [weak tabManager] id in
                tabManager?.shortcutPinCollectionStateOwner.shortcutPin(by: id)
            },
            tab: { [weak tabManager] id in
                tabManager?.tab(for: id)
            },
            folderSpaceId: { [weak tabManager] folderId in
                tabManager?.folderCollectionStateOwner.spaceId(for: folderId)
            },
            spaceExists: { [weak tabManager] spaceId in
                tabManager?.spaces.contains(where: { $0.id == spaceId }) ?? false
            }
        )
    }
}
