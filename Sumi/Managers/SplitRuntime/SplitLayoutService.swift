import Foundation
import SumiDomain

/// Durable split-layout lifecycle. Every structural change is committed
/// against an exact snapshot; window selection is reconciled only afterward.
@MainActor
final class SplitLayoutService {
    private let tabManager: @MainActor () -> TabManager?
    private let query: WindowSplitQuery
    private let weightMutations: SplitLayoutWeightMutationService
    private let presentations: WindowSplitPresentationSynchronizer
    private let dissolution: SplitGroupDissolutionService
    private let launcherPlacement: ShortcutSplitLauncherPlacementService
    private let restoreShortcutMember: @MainActor (
        SplitMemberID,
        SumiDomain.SplitGroup,
        BrowserWindowState
    ) -> Bool

    init(
        tabManager: @escaping @MainActor () -> TabManager?,
        query: WindowSplitQuery,
        weightMutations: SplitLayoutWeightMutationService,
        presentations: WindowSplitPresentationSynchronizer,
        dissolution: SplitGroupDissolutionService,
        launcherPlacement: ShortcutSplitLauncherPlacementService,
        restoreShortcutMember: @escaping @MainActor (
            SplitMemberID,
            SumiDomain.SplitGroup,
            BrowserWindowState
        ) -> Bool
    ) {
        self.tabManager = tabManager
        self.query = query
        self.weightMutations = weightMutations
        self.presentations = presentations
        self.dissolution = dissolution
        self.launcherPlacement = launcherPlacement
        self.restoreShortcutMember = restoreShortcutMember
    }

    func updateWeights(
        expectedGroup: SumiDomain.SplitGroup,
        path: [Int],
        weights: [Double],
        in windowID: UUID
    ) {
        guard weightMutations.update(
            expectedGroup: expectedGroup,
            path: path,
            weights: weights
        ) else {
            return
        }
        presentations.refreshPresentations(for: [expectedGroup.id])
    }

    func setLayoutKind(_ layoutKind: SplitLayoutKind, in windowID: UUID) {
        guard let tabManager = tabManager(),
              let group = query.group(in: windowID),
              let replacement = group.changingLayout(to: layoutKind),
              replacement != group,
              tabManager.splitGroupMutations.replace(
                  group,
                  with: replacement
              ) else {
            return
        }
        presentations.synchronize(
            previousGroups: [group],
            affectedGroupIDs: [group.id]
        )
    }

    func stageClosedRegularTabs(
        _ tabIDs: Set<UUID>
    ) -> PreparedSplitTabClosureSettlement? {
        guard !tabIDs.isEmpty, let tabManager = tabManager() else { return nil }
        let memberIDs = Set(tabIDs.map(SplitMemberID.regularTab))
        let expected = tabManager.splitGroupStore.groups
        let replacement = expected.compactMap { group in
            memberIDs.reduce(Optional(group)) { candidate, memberID in
                guard let candidate, candidate.contains(memberID) else {
                    return candidate
                }
                return candidate.removingMember(memberID)
            }
        }
        let changedGroups = expected.filter { previous in
            replacement.first(where: { $0.id == previous.id }) != previous
        }
        let remainingMemberIDs = Set(replacement.flatMap(\.memberIDs))
        let releasedShortcuts = changedGroups.flatMap(\.members).filter {
            guard case .shortcutPin = $0.memberID else { return false }
            return !remainingMemberIDs.contains($0.memberID)
        }
        guard let restorations = launcherPlacement.prepareRestorations(
            for: releasedShortcuts
        ) else { return nil }
        guard replacement != expected,
              tabManager.splitGroupMutations.replaceAllAtomically(
                  expected: expected,
                  with: replacement,
                  applying: {
                      restorations.applyAndCommit()
                  }
              ) else {
            return nil
        }
        return PreparedSplitTabClosureSettlement(
            presentations: presentations,
            previousGroups: changedGroups,
            affectedGroupIDs: Set(changedGroups.map(\.id))
        )
    }

    func unsplit(in windowState: BrowserWindowState) {
        guard let group = query.group(in: windowState.id) else {
            return
        }
        _ = dissolution.dissolve(group)
    }

    func expand(tabID: UUID, in windowState: BrowserWindowState) {
        guard let tabManager = tabManager(),
              let presentation = query.resolution(
                  in: windowState.id
              ).presentation,
              let memberID = presentation.memberID(for: tabID) else {
            return
        }
        let group = presentation.group
        if case .shortcutPin = memberID {
            _ = restoreShortcutMember(memberID, group, windowState)
            return
        }
        guard case .regularTab(let regularTabID) = memberID,
              tabManager.regularTabCollectionOwner.tab(for: regularTabID) != nil else {
            return
        }

        let didCommit: Bool
        if let replacement = group.removingMember(memberID) {
            didCommit = tabManager.splitGroupMutations.replace(
                group,
                with: replacement
            )
        } else {
            didCommit = dissolution.dissolve(
                group,
                standaloneMembers: [windowState.id: memberID]
            )
        }
        guard didCommit else { return }
        guard tabManager.splitGroupStore.group(id: group.id) != nil else {
            return
        }
        presentations.synchronize(
            previousGroups: [group],
            affectedGroupIDs: [group.id],
            standaloneMembers: [windowState.id: memberID]
        )
    }
}
