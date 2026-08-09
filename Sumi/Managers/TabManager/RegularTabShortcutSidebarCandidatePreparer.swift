import Foundation
import SumiDomain

/// Derives the only valid pin destination for a
/// regular tab entering an existing shortcut-sidebar split.
@MainActor
final class RegularTabShortcutSidebarCandidatePreparer {
    private let conversions: RegularTabShortcutCandidatePreparer

    init(conversions: RegularTabShortcutCandidatePreparer) {
        self.conversions = conversions
    }

    func prepare(
        tab: Tab,
        targetGroup: SumiDomain.SplitGroup,
        preferredWindowID: UUID
    ) -> PreparedRegularTabShortcutSidebarDrop? {
        guard case .shortcutSidebar(
            let spaceID,
            _,
            let folderID,
            let groupIndex
        ) = targetGroup.container else { return nil }

        let preparation = conversions.prepare(
            tab,
            preferredWindowID: preferredWindowID
        )
        guard let structure = preparation.structurePlan,
              structure.expectedSplitGroups.contains(targetGroup),
              structure.sourceSplitGroupID != targetGroup.id else {
            return nil
        }
        let index = max(0, groupIndex ?? 0)
        let destination = TabShortcutPinDestination(
            role: .spacePinned,
            profileId: nil,
            spaceId: spaceID,
            folderId: folderID,
            index: index,
            opensFolder: false
        )
        guard let conversion = conversions.candidate(
            for: tab,
            preparation: preparation,
            destination: destination
        ) else { return nil }

        return PreparedRegularTabShortcutSidebarDrop(
            candidatePin: conversion.candidatePin,
            member: .shortcutPin(conversion.candidatePin.id),
            expectedSplitGroups: structure.expectedSplitGroups,
            conversion: conversion,
            targetGroup: targetGroup,
            targetGroupWasExisting: true
        )
    }

    func prepare(
        tab: Tab,
        standaloneTargetPin: ShortcutPin,
        target: SplitDropTarget,
        preferredWindowID: UUID
    ) -> PreparedRegularTabShortcutSidebarDrop? {
        let preparation = conversions.prepare(
            tab,
            preferredWindowID: preferredWindowID
        )
        guard let structure = preparation.structurePlan else { return nil }

        let destination: TabShortcutPinDestination
        let container: SplitGroupContainer
        switch standaloneTargetPin.role {
        case .favorite:
            guard let profileID = standaloneTargetPin.profileId else {
                return nil
            }
            destination = TabShortcutPinDestination(
                role: .favorite,
                profileId: profileID,
                spaceId: nil,
                folderId: nil,
                index: standaloneTargetPin.index,
                opensFolder: false
            )
            container = .favoriteSidebar(
                profileId: profileID,
                index: standaloneTargetPin.index
            )
        case .spacePinned:
            guard let spaceID = standaloneTargetPin.spaceId else {
                return nil
            }
            destination = TabShortcutPinDestination(
                role: .spacePinned,
                profileId: nil,
                spaceId: spaceID,
                folderId: standaloneTargetPin.folderId,
                index: standaloneTargetPin.index,
                opensFolder: false
            )
            container = .shortcutSidebar(
                spaceId: spaceID,
                profileId: standaloneTargetPin.profileId,
                folderId: standaloneTargetPin.folderId,
                index: standaloneTargetPin.index
            )
        }
        guard let conversion = conversions.candidate(
            for: tab,
            preparation: preparation,
            destination: destination
        ) else { return nil }

        let incoming = SplitMember.shortcutPin(conversion.candidatePin.id)
        let existing = SplitMember.shortcutPin(standaloneTargetPin.id)
        let members = target.side.insertsBeforeTarget
            ? [incoming, existing]
            : [existing, incoming]
        let layoutKind: SplitLayoutKind =
            target.side == .top || target.side == .bottom
            ? .horizontal
            : .vertical
        guard let targetGroup = SplitGroup.make(
            members: members,
            layoutKind: layoutKind,
            container: container
        ) else { return nil }

        return PreparedRegularTabShortcutSidebarDrop(
            candidatePin: conversion.candidatePin,
            member: incoming,
            expectedSplitGroups: structure.expectedSplitGroups,
            conversion: conversion,
            targetGroup: targetGroup,
            targetGroupWasExisting: false
        )
    }
}
