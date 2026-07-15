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

    func preparedModelIsCurrent(
        _ plan: WindowSplitPresentationSettlementPlan
    ) -> Bool {
        modelIsCurrent(
            plan,
            expectedWindowStates: Dictionary(uniqueKeysWithValues:
                plan.windows.map { ($0.window.id, $0.expectedWindowState) }
            ),
            validating: witnessPreparedIdentityIsCurrent
        )
    }

    func modelIsCurrent(
        _ plan: WindowSplitPresentationSettlementPlan,
        expectedWindowStates: [UUID: BrowserWindowShortcutMutationState]
    ) -> Bool {
        modelIsCurrent(
            plan,
            expectedWindowStates: expectedWindowStates,
            validating: witnessBoundIdentityIsCurrent
        )
    }

    private func modelIsCurrent(
        _ plan: WindowSplitPresentationSettlementPlan,
        expectedWindowStates: [UUID: BrowserWindowShortcutMutationState],
        validating witnessIsCurrent: (WindowSplitPresentationMemberWitness)
            -> Bool
    ) -> Bool {
        guard splitGroups.groups == plan.expectedGroups,
              let windowsByID = exactWindowsByID() else { return false }
        return plan.windows.allSatisfy { windowPlan in
            guard windowsByID[windowPlan.window.id] === windowPlan.window,
                  windowPlan.window.unpublishedShortcutMutationState
                    == expectedWindowStates[windowPlan.window.id],
                  windowPlan.memberWitnesses.allSatisfy(witnessIsCurrent)
            else { return false }
            return activeMemberIsCurrent(
                windowPlan,
                validating: witnessIsCurrent
            )
        }
    }

    func terminalWindowIsCurrent(
        _ plan: WindowSplitPresentationSettlementPlan,
        _ windowPlan: WindowSplitPresentationWindowPlan,
        expectedWindowState: BrowserWindowShortcutMutationState? = nil
    ) -> Bool {
        guard splitGroups.groups == plan.expectedGroups,
              let windowsByID = exactWindowsByID(),
              windowsByID[windowPlan.window.id] === windowPlan.window,
              windowPlan.window.unpublishedShortcutMutationState
                == (expectedWindowState ?? windowPlan.targetWindowState),
              windowPlan.memberWitnesses.allSatisfy(
                  witnessBoundIdentityIsCurrent
              )
        else { return false }
        return activeMemberIsCurrent(
            windowPlan,
            validating: witnessBoundIdentityIsCurrent
        )
    }

    private func exactWindowsByID() -> [UUID: BrowserWindowState]? {
        let windows = currentWindows()
        guard Set(windows.map(\.id)).count == windows.count else { return nil }
        return Dictionary(
            uniqueKeysWithValues: windows.map { ($0.id, $0) }
        )
    }

    private func activeMemberIsCurrent(
        _ windowPlan: WindowSplitPresentationWindowPlan,
        validating witnessIsCurrent: (WindowSplitPresentationMemberWitness)
            -> Bool
    ) -> Bool {
        guard let activeMemberID = windowPlan.activeMemberID,
              let activeTab = windowPlan.activeTab else { return true }
        return windowPlan.memberWitnesses.contains {
            $0.memberID == activeMemberID
                && $0.tab === activeTab
                && $0.windowID == windowPlan.window.id
                && witnessIsCurrent($0)
        }
    }

    private func witnessPreparedIdentityIsCurrent(
        _ witness: WindowSplitPresentationMemberWitness
    ) -> Bool {
        switch witness {
        case .regular(let tabID, let tab, _):
            return tab.id == tabID && regularTabs.tab(for: tabID) === tab
        case .shortcut(let shortcut):
            return shortcut.preparedIdentityIsExact(in: liveShortcuts)
        }
    }

    private func witnessBoundIdentityIsCurrent(
        _ witness: WindowSplitPresentationMemberWitness
    ) -> Bool {
        switch witness {
        case .regular(let tabID, let tab, _):
            return tab.id == tabID && regularTabs.tab(for: tabID) === tab
        case .shortcut(let shortcut):
            return shortcut.boundIdentityIsExact(in: liveShortcuts)
        }
    }
}
