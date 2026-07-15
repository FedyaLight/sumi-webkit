import Foundation

/// Revalidates the exact windows, Tabs and split topology retained by a plan.
/// It has no mutation or publication authority.
@MainActor
final class WindowSplitPresentationSettlementValidator {
    private let splitGroups: SplitGroupStore
    private let regularTabs: RegularTabCollectionOwner
    private let liveShortcuts: LiveShortcutTabRegistry
    private let currentWindows: @MainActor () -> [BrowserWindowState]

    init(
        splitGroups: SplitGroupStore,
        regularTabs: RegularTabCollectionOwner,
        liveShortcuts: LiveShortcutTabRegistry,
        currentWindows: @escaping @MainActor () -> [BrowserWindowState]
    ) {
        self.splitGroups = splitGroups
        self.regularTabs = regularTabs
        self.liveShortcuts = liveShortcuts
        self.currentWindows = currentWindows
    }

    func canStage(_ plan: WindowSplitPresentationSettlementPlan) -> Bool {
        splitGroups.groups == plan.expectedGroups
            && plan.windows.allSatisfy {
                $0.window.unpublishedShortcutMutationState
                    == $0.expectedWindowState
            }
    }

    func isCurrentForWindowSettlement(
        _ plan: WindowSplitPresentationSettlementPlan
    ) -> Bool {
        guard splitGroups.groups == plan.expectedGroups,
              let windowsByID = exactWindowsByID() else { return false }
        return plan.windows.allSatisfy { windowPlan in
            guard windowsByID[windowPlan.window.id] === windowPlan.window,
                  windowPlan.window.unpublishedShortcutMutationState
                    == windowPlan.expectedWindowState,
                  windowPlan.memberWitnesses.allSatisfy(witnessIsCurrent)
            else { return false }
            return activeMemberIsCurrent(windowPlan)
        }
    }

    func terminalWindowIsCurrent(
        _ windowPlan: WindowSplitPresentationWindowPlan
    ) -> Bool {
        guard let windowsByID = exactWindowsByID(),
              windowsByID[windowPlan.window.id] === windowPlan.window,
              windowPlan.window.unpublishedShortcutMutationState
                == windowPlan.targetWindowState,
              windowPlan.memberWitnesses.allSatisfy(witnessIsCurrent)
        else { return false }
        return activeMemberIsCurrent(windowPlan)
    }

    private func exactWindowsByID() -> [UUID: BrowserWindowState]? {
        let windows = currentWindows()
        guard Set(windows.map(\.id)).count == windows.count else { return nil }
        return Dictionary(
            uniqueKeysWithValues: windows.map { ($0.id, $0) }
        )
    }

    private func activeMemberIsCurrent(
        _ windowPlan: WindowSplitPresentationWindowPlan
    ) -> Bool {
        guard let activeMemberID = windowPlan.activeMemberID,
              let activeTab = windowPlan.activeTab else { return true }
        return witnessIsCurrent(WindowSplitPresentationMemberWitness(
            memberID: activeMemberID,
            tab: activeTab,
            windowID: windowPlan.window.id
        ))
    }

    private func witnessIsCurrent(
        _ witness: WindowSplitPresentationMemberWitness
    ) -> Bool {
        switch witness.memberID {
        case .regularTab(let tabID):
            return witness.tab.id == tabID
                && regularTabs.tab(for: tabID) === witness.tab
        case .shortcutPin(let pinID):
            guard let entry = liveShortcuts.entry(containing: witness.tab)
            else { return false }
            return entry.windowId == witness.windowID
                && entry.pinId == pinID
                && entry.tab === witness.tab
        }
    }
}
