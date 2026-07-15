import Foundation
import SumiDomain

/// Binds a topology draft to the exact regular and newly prepared shortcut
/// Tabs, producing the immutable model snapshots consumed by settlement.
@MainActor
struct WindowSplitPresentationSettlementPlanner {
    private struct ShortcutSlot: Hashable {
        let windowID: UUID
        let pinID: UUID
    }

    func prepare(
        _ draftPlan: WindowSplitPresentationDraftPlan,
        shortcutWitnesses: [WindowSplitPresentationShortcutWitness],
        regularTabs: RegularTabCollectionOwner
    ) -> WindowSplitPresentationSettlementPlan? {
        guard shortcutWitnesses.count == draftPlan.activationRequests.count,
              zip(draftPlan.activationRequests, shortcutWitnesses).allSatisfy({
                  request, witness in
                  request.windowID == witness.windowID
                    && request.pinID == witness.pinID
              }) else {
            return nil
        }
        let shortcutTabs = Dictionary(
            uniqueKeysWithValues: zip(
                draftPlan.activationRequests,
                shortcutWitnesses
            ).map { request, witness in
                (
                    ShortcutSlot(
                        windowID: request.windowID,
                        pinID: request.pinID
                    ),
                    witness
                )
            }
        )
        guard let windowPlans = makeWindowPlans(
            draftPlan.drafts,
            shortcutTabs: shortcutTabs,
            regularTabs: regularTabs
        ) else { return nil }

        return WindowSplitPresentationSettlementPlan(
            expectedGroups: draftPlan.expectedGroups,
            windows: windowPlans,
            sessionWriteUrgency: draftPlan.sessionWriteUrgency
        )
    }

    private func makeWindowPlans(
        _ drafts: [WindowSplitPresentationDraft],
        shortcutTabs: [ShortcutSlot: WindowSplitPresentationShortcutWitness],
        regularTabs: RegularTabCollectionOwner
    ) -> [WindowSplitPresentationWindowPlan]? {
        var plans: [WindowSplitPresentationWindowPlan] = []
        for draft in drafts {
            let materialized = draft.materializedMembers.compactMap {
                resolvedTab(
                    for: $0,
                    windowID: draft.window.id,
                    shortcutTabs: shortcutTabs,
                    regularTabs: regularTabs
                )
            }
            guard materialized.count == draft.materializedMembers.count,
                  Set(materialized.map { $0.tab.id }).count
                    == materialized.count else {
                return nil
            }
            let activeWitness = draft.activeMemberID.flatMap { activeID in
                materialized.first { $0.memberID == activeID }
            }
            guard draft.activeMemberID == nil || activeWitness != nil else {
                return nil
            }
            let memberWitnesses = materialized

            let expectedWindowState = draft.window
                .unpublishedShortcutMutationState
            var targetWindowState = expectedWindowState
            activeWitness?.applySelection(to: &targetWindowState)
            targetWindowState.splitSelection = draft.splitSelection
            plans.append(WindowSplitPresentationWindowPlan(
                window: draft.window,
                expectedWindowState: expectedWindowState,
                targetWindowState: targetWindowState,
                memberWitnesses: memberWitnesses,
                activeWitness: activeWitness,
                before: WindowSplitPresentationPersistedState(draft.window)
            ))
        }
        return plans
    }

    private func resolvedTab(
        for memberID: SplitMemberID,
        windowID: UUID,
        shortcutTabs: [ShortcutSlot: WindowSplitPresentationShortcutWitness],
        regularTabs: RegularTabCollectionOwner
    ) -> WindowSplitPresentationMemberWitness? {
        switch memberID {
        case .regularTab(let tabID):
            return regularTabs.tab(for: tabID).map {
                .regular(tabID: tabID, tab: $0, windowID: windowID)
            }
        case .shortcutPin(let pinID):
            return shortcutTabs[ShortcutSlot(
                windowID: windowID,
                pinID: pinID
            )].map(WindowSplitPresentationMemberWitness.shortcut)
        }
    }
}
