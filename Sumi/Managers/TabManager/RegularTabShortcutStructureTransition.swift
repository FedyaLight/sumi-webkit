import Foundation

/// Prepares the durable structural half of regular-tab to shortcut conversion.
/// A split member keeps its current layout leaf until the window-local split
/// presentation model can own live shortcut identities independently.
@MainActor
final class RegularTabShortcutStructureTransition {
    private let regularTabs: RegularTabCollectionOwner
    private let splitGroupContaining: (UUID) -> SplitGroup?
    private let structuralRevision: () -> UInt64
    private let upsertSplitGroup: (SplitGroup) -> Void

    init(
        regularTabs: RegularTabCollectionOwner,
        splitGroupContaining: @escaping (UUID) -> SplitGroup?,
        structuralRevision: @escaping () -> UInt64,
        upsertSplitGroup: @escaping (SplitGroup) -> Void
    ) {
        self.regularTabs = regularTabs
        self.splitGroupContaining = splitGroupContaining
        self.structuralRevision = structuralRevision
        self.upsertSplitGroup = upsertSplitGroup
    }

    func prepare(_ tab: Tab) -> RegularTabShortcutStructurePlan? {
        guard regularTabs.contains(tab),
              tab.isShortcutLiveInstance == false else {
            return nil
        }
        let revision = structuralRevision()
        guard let group = splitGroupContaining(tab.id) else {
            return standalonePlan(for: tab, revision: revision)
        }
        guard group.tabIds.contains(tab.id),
              group.member(for: tab.id)?.isShortcutBacked != true else {
            return nil
        }
        return splitPlan(for: tab, group: group, revision: revision)
    }

    private func standalonePlan(
        for tab: Tab,
        revision: UInt64
    ) -> RegularTabShortcutStructurePlan {
        RegularTabShortcutStructurePlan(
            sourceTabId: tab.id,
            sourceSplitGroupSnapshot: nil,
            isCurrent: { [regularTabs, splitGroupContaining, structuralRevision] candidate in
                candidate === tab
                    && regularTabs.contains(candidate)
                    && candidate.isShortcutLiveInstance == false
                    && splitGroupContaining(tab.id) == nil
                    && structuralRevision() == revision
            },
            runtimeExposureIsValid: { tabId, windowIds, runtime in
                windowIds.allSatisfy {
                    runtime.visibleSplitTabIds(for: $0).contains(tabId) == false
                }
            },
            authorizeStructure: { _ in
                AuthorizedShortcutStructureTransition { _ in
                    // Standalone conversion has no split structure to mutate.
                }
            }
        )
    }

    private func splitPlan(
        for tab: Tab,
        group: SplitGroup,
        revision: UInt64
    ) -> RegularTabShortcutStructurePlan {
        RegularTabShortcutStructurePlan(
            sourceTabId: tab.id,
            sourceSplitGroupSnapshot: group,
            isCurrent: { [regularTabs, splitGroupContaining, structuralRevision] candidate in
                candidate === tab
                    && regularTabs.contains(candidate)
                    && candidate.isShortcutLiveInstance == false
                    && splitGroupContaining(tab.id) == group
                    && structuralRevision() == revision
            },
            runtimeExposureIsValid: { tabId, windowIds, runtime in
                guard windowIds.count == 1,
                      let windowId = windowIds.first,
                      runtime.webViewLifecycle.primaryTrackedWindowId(
                          for: tabId
                      ) == windowId else {
                    return false
                }
                let visibleIds = Set(runtime.visibleSplitTabIds(for: windowId))
                return visibleIds.contains(tabId)
                    && visibleIds == Set(group.tabIds)
            },
            authorizeStructure: { [upsertSplitGroup] candidatePin in
                AuthorizedShortcutStructureTransition.forSplit(
                    for: candidatePin,
                    sourceTabId: tab.id,
                    group: group,
                    upsertSplitGroup: upsertSplitGroup
                )
            }
        )
    }
}
