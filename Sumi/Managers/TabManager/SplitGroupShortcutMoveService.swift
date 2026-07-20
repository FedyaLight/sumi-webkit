import Foundation
import SumiDomain

/// Converts a regular split into one launcher-backed sidebar item while the
/// existing regular-tab conversion aggregate preserves every displayed Tab
/// and WebView. The group is removed only for the short conversion interval;
/// its identity, layout and metadata are restored with launcher member IDs.
@MainActor
final class SplitGroupShortcutMoveService {
    private let conversion: RegularTabShortcutConversionService
    private let groups: SplitGroupMutationService
    private let structuralLookup: TabStructuralLookupCoordinator
    private let runtimeConnection: TabRuntimePortConnection
    private let windowMutations: BrowserWindowShortcutMutationOwner

    init(
        conversion: RegularTabShortcutConversionService,
        groups: SplitGroupMutationService,
        structuralLookup: TabStructuralLookupCoordinator,
        runtimeConnection: TabRuntimePortConnection,
        windowMutations: BrowserWindowShortcutMutationOwner
    ) {
        self.conversion = conversion
        self.groups = groups
        self.structuralLookup = structuralLookup
        self.runtimeConnection = runtimeConnection
        self.windowMutations = windowMutations
    }

    func move(
        _ group: SplitGroup,
        tabs: [Tab],
        to container: SplitGroupContainer,
        destination: TabShortcutPinDestination,
        preferredWindowID: UUID?
    ) -> Bool {
        guard case .regularTabs = group.container,
              tabs.count == group.memberIDs.count,
              zip(group.memberIDs, tabs).allSatisfy({ memberID, tab in
                  memberID == .regularTab(tab.id)
              }),
              tabs.allSatisfy({
                  conversion.prepare(
                      $0,
                      preferredWindowId: preferredWindowID
                  ).structurePlan != nil
              }) else { return false }

        let selectedMembers = selectedMemberIDs(
            for: group,
            preferredWindowID: preferredWindowID
        )
        return structuralLookup.withTransaction {
            guard groups.remove(group, persist: false) else { return false }

            var tree = group.layoutTree
            var replacementIDs: [UUID: SplitMemberID] = [:]
            for (offset, tab) in tabs.enumerated() {
                let memberDestination = TabShortcutPinDestination(
                    role: destination.role,
                    profileId: destination.profileId,
                    spaceId: destination.spaceId,
                    folderId: destination.folderId,
                    index: destination.index + offset,
                    opensFolder: destination.opensFolder
                )
                let preparation = conversion.prepareSplitGroupMoveMember(
                    tab,
                    sourceGroupID: group.id,
                    preferredWindowId: preferredWindowID
                )
                guard let accepted = conversion.commit(
                    tab,
                    preparation: preparation,
                    destination: memberDestination
                ) else {
                    preconditionFailure(
                        "Preflighted split member conversion diverged"
                    )
                }
                let oldID = SplitMemberID.regularTab(tab.id)
                let newID = SplitMemberID.shortcutPin(accepted.pinID)
                replacementIDs[tab.id] = newID
                guard let replacement = tree.replacingMember(
                    oldID,
                    with: .shortcutPin(accepted.pinID)
                ) else {
                    preconditionFailure("Split conversion lost its member leaf")
                }
                tree = replacement
            }

            guard let replacementGroup = SplitGroup(
                id: group.id,
                layoutKind: group.layoutKind,
                layoutTree: tree,
                container: container,
                title: group.title,
                iconAsset: group.iconAsset
            ) else {
                preconditionFailure("Converted split topology was invalid")
            }
            precondition(
                groups.insert(replacementGroup, persist: false),
                "Converted split group could not restore its identity"
            )
            reconcileSelections(
                selectedMembers,
                groupID: group.id,
                replacementIDs: replacementIDs
            )
            return true
        }
    }

    private func selectedMemberIDs(
        for group: SplitGroup,
        preferredWindowID: UUID?
    ) -> [(BrowserWindowState, UUID)] {
        guard let runtime = runtimeConnection.captureLease().registry else {
            return []
        }
        var result: [(BrowserWindowState, UUID)] = []
        runtime.forEachWindow { _, window in
            guard window.splitSelection?.groupID == group.id,
                  case .regularTab(let tabID) =
                    window.splitSelection?.activeMemberID else { return }
            result.append((window, tabID))
        }
        return result.sorted { lhs, rhs in
            if lhs.0.id == preferredWindowID { return true }
            if rhs.0.id == preferredWindowID { return false }
            return lhs.0.id.uuidString < rhs.0.id.uuidString
        }
    }

    private func reconcileSelections(
        _ selections: [(BrowserWindowState, UUID)],
        groupID: UUID,
        replacementIDs: [UUID: SplitMemberID]
    ) {
        precondition(windowMutations.withAggregate {
            for (window, tabID) in selections {
                guard let memberID = replacementIDs[tabID] else {
                    return false
                }
                _ = windowMutations.stage(window) { state in
                    state.splitSelection = WindowSplitSelection(
                        groupID: groupID,
                        activeMemberID: memberID
                    )
                }
            }
            return true
        })
    }
}
