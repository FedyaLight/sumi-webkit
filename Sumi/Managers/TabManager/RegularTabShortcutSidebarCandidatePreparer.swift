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
            targetGroup: targetGroup
        )
    }
}
