import Foundation

@MainActor
final class DetachedTabShortcutSourceModelTransaction {
    private struct Identity {
        let tab: Tab
        let spaceID: UUID
        let selectedTab: Tab?
    }

    private enum State {
        case prepared, staging, staged, awaitingStructuralRollback, conflicted, terminal
    }

    private let identity: Identity
    private let container: ShortcutContainerRemovalOwner
    private let membership: TabCollectionMembershipOwner
    private let selection: TabSelectionStateOwner
    private var state = State.prepared

    var tab: Tab { identity.tab }

    init?(
        tab: Tab,
        container: ShortcutContainerRemovalOwner,
        membership: TabCollectionMembershipOwner,
        selection: TabSelectionStateOwner
    ) {
        guard let spaceID = tab.spaceId else { return nil }
        identity = Identity(
            tab: tab,
            spaceID: spaceID,
            selectedTab: selection.currentTab
        )
        self.container = container
        self.membership = membership
        self.selection = selection
        guard validateForStaging() else { return nil }
    }

    func validateForStaging() -> Bool {
        guard case .prepared = state else { return false }
        return sourceIsExact()
    }

    func stage() -> Bool {
        guard validateForStaging() else { return false }
        state = .staging
        container.removeFromCurrentContainer(identity.tab)
        if selection.currentTab === identity.tab {
            selection.replaceCurrentTab(nil)
        }
        guard stagedStructureIsExact() else {
            state = .conflicted
            return false
        }
        state = .staged
        return true
    }

    func stagedModelIsExact() -> Bool {
        guard case .staged = state else { return false }
        return stagedStructureIsExact()
    }

    private func stagedStructureIsExact() -> Bool {
        container.containsIdenticalRegularTab(
            identity.tab,
            in: identity.spaceID
        ) == false
            && membership.tab(for: identity.tab.id) === identity.tab
            && identity.tab.spaceId == identity.spaceID
            && identity.tab.isShortcutLiveInstance == false
            && selectionMatchesStagedTarget()
    }

    func terminalSourceModelIsExact() -> Bool {
        switch state {
        case .prepared: return validateForStaging()
        case .staged: return stagedModelIsExact()
        case .staging, .awaitingStructuralRollback, .conflicted, .terminal:
            return false
        }
    }

    func commitSilentModel() -> Bool {
        guard stagedModelIsExact() else { return false }
        state = .terminal
        return true
    }

    func prepareStructuralRollback() -> Bool {
        switch state {
        case .prepared:
            state = .awaitingStructuralRollback
            return true
        case .staged:
            guard selectionMatchesStagedTarget() else {
                state = .conflicted
                return false
            }
            if identity.selectedTab === identity.tab {
                selection.replaceCurrentTab(identity.tab)
            }
            guard selectionIsExpected() else {
                state = .conflicted
                return false
            }
            state = .awaitingStructuralRollback
            return true
        case .awaitingStructuralRollback:
            return true
        case .staging, .conflicted, .terminal:
            return false
        }
    }

    func confirmStructuralRollback() -> Bool {
        guard case .awaitingStructuralRollback = state,
              sourceIsExact() else { return false }
        state = .terminal
        return true
    }

    func cancelPrepared() -> Bool {
        guard case .prepared = state else { return false }
        state = .terminal
        return true
    }

    private func sourceIsExact() -> Bool {
        container.containsIdenticalRegularTab(
            identity.tab,
            in: identity.spaceID
        )
            && membership.tab(for: identity.tab.id) === identity.tab
            && identity.tab.spaceId == identity.spaceID
            && identity.tab.isShortcutLiveInstance == false
            && selectionIsExpected()
    }

    private func selectionIsExpected() -> Bool {
        sameSelection(selection.currentTab, identity.selectedTab)
    }

    private func selectionMatchesStagedTarget() -> Bool {
        identity.selectedTab === identity.tab
            ? selection.currentTab == nil
            : selectionIsExpected()
    }

    private func sameSelection(_ lhs: Tab?, _ rhs: Tab?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case (.some(let lhs), .some(let rhs)): return lhs === rhs
        case (.some, nil), (nil, .some): return false
        }
    }
}
