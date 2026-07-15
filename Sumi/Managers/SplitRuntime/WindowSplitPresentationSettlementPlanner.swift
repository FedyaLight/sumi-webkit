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
        activationTabs: [Tab],
        regularTabs: RegularTabCollectionOwner
    ) -> WindowSplitPresentationSettlementPlan? {
        guard activationTabs.count == draftPlan.activationRequests.count else {
            return nil
        }
        let shortcutTabs = Dictionary(
            uniqueKeysWithValues: zip(
                draftPlan.activationRequests,
                activationTabs
            ).map { request, tab in
                (
                    ShortcutSlot(
                        windowID: request.windowID,
                        pinID: request.pinID
                    ),
                    tab
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
        shortcutTabs: [ShortcutSlot: Tab],
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
                  Set(materialized.map(\.id)).count == materialized.count else {
                return nil
            }
            let activeTab = draft.activeMemberID.flatMap {
                resolvedTab(
                    for: $0,
                    windowID: draft.window.id,
                    shortcutTabs: shortcutTabs,
                    regularTabs: regularTabs
                )
            }
            guard draft.activeMemberID == nil || activeTab != nil else {
                return nil
            }
            let memberWitnesses = zip(
                draft.materializedMembers,
                materialized
            ).map {
                WindowSplitPresentationMemberWitness(
                    memberID: $0,
                    tab: $1,
                    windowID: draft.window.id
                )
            }
            guard memberWitnesses.allSatisfy(witnessHasExpectedIdentity)
            else { return nil }

            let expectedWindowState = draft.window
                .unpublishedShortcutMutationState
            var targetWindowState = expectedWindowState
            if let activeTab {
                _ = WindowTabSelectionStateApplicator.apply(
                    activeTab,
                    to: &targetWindowState,
                    updateSpaceFromTab: true,
                    rememberSelection: true
                )
            }
            targetWindowState.splitSelection = draft.splitSelection
            plans.append(WindowSplitPresentationWindowPlan(
                window: draft.window,
                expectedWindowState: expectedWindowState,
                targetWindowState: targetWindowState,
                memberWitnesses: memberWitnesses,
                activeMemberID: draft.activeMemberID,
                activeTab: activeTab,
                before: WindowSplitPresentationPersistedState(draft.window)
            ))
        }
        return plans
    }

    private func resolvedTab(
        for memberID: SplitMemberID,
        windowID: UUID,
        shortcutTabs: [ShortcutSlot: Tab],
        regularTabs: RegularTabCollectionOwner
    ) -> Tab? {
        switch memberID {
        case .regularTab(let tabID):
            return regularTabs.tab(for: tabID)
        case .shortcutPin(let pinID):
            return shortcutTabs[ShortcutSlot(
                windowID: windowID,
                pinID: pinID
            )]
        }
    }

    private func witnessHasExpectedIdentity(
        _ witness: WindowSplitPresentationMemberWitness
    ) -> Bool {
        switch witness.memberID {
        case .regularTab(let tabID):
            witness.tab.id == tabID
        case .shortcutPin(let pinID):
            witness.tab.shortcutPinId == pinID
        }
    }
}
