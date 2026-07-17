import Foundation

/// Window and fresh-membership participant for one displayed conversion.
/// Raw window state is reversible; membership opens only after terminal claim.
@MainActor
final class DisplayedTabShortcutSourceModelTransaction {
    private enum State {
        case prepared, staged, published, rolledBack, abandoned
    }

    private let binding: PreparedDisplayedTabShortcutBinding
    private let membershipWitness: DisplayedTabShortcutMembershipWitness
    private let containerRemoval: ShortcutContainerRemovalOwner
    private let regularTabs: RegularTabCollectionOwner
    private var state = State.prepared

    init(
        binding: PreparedDisplayedTabShortcutBinding,
        membershipWitness: DisplayedTabShortcutMembershipWitness,
        containerRemoval: ShortcutContainerRemovalOwner,
        regularTabs: RegularTabCollectionOwner
    ) {
        self.binding = binding
        self.membershipWitness = membershipWitness
        self.containerRemoval = containerRemoval
        self.regularTabs = regularTabs
    }

    func validateForStaging() -> Bool {
        guard case .prepared = state else { return false }
        guard let sourceSpaceID = binding.sourceSpaceID else { return false }
        return membershipWitness.preparedModelIsExact()
            && regularTabs.containsIdentical(
                binding.sourceTab,
                in: sourceSpaceID
            )
    }

    func stage() -> Bool {
        guard validateForStaging() else { return false }
        membershipWitness.prepareFreshTabsForRuntime()
        guard validateForStaging() else { return false }
        containerRemoval.removeFromCurrentContainer(binding.sourceTab)
        guard sourceContainerWasRemoved(),
              membershipWitness.sourceRemovalIsExact() else { return false }
        state = .staged
        return true
    }

    func stagedModelIsExact() -> Bool {
        guard case .staged = state else { return false }
        return sourceContainerWasRemoved()
            && membershipWitness.stagedResidencesAreExact()
    }

    func stagedSourceRemovalIsExact() -> Bool {
        guard case .staged = state else { return false }
        return sourceContainerWasRemoved()
            && membershipWitness.sourceRemovalIsExact()
    }

    func rollback() -> Bool {
        guard case .staged = state else { return false }
        state = .rolledBack
        return true
    }

    func cancelPrepared() -> Bool {
        guard case .prepared = state else { return false }
        state = .rolledBack
        return true
    }

    func settleAfterFailedStage() -> Bool {
        switch state {
        case .prepared:
            return cancelPrepared()
        case .staged:
            return rollback()
        case .rolledBack:
            return true
        case .published, .abandoned:
            return false
        }
    }

    func abandonForTerminalDrain() {
        precondition(canAbandonForTerminalDrain())
        state = .abandoned
    }

    func canAbandonForTerminalDrain() -> Bool {
        stagedModelIsExact()
    }

    func publishBeforeBinding() {
        guard case .staged = state else {
            preconditionFailure("Displayed runtime lost terminal window model")
        }
        guard membershipWitness.publishFreshAttachments() else {
            preconditionFailure("Displayed membership lost terminal authority")
        }
    }

    func finishPublication() {
        guard case .staged = state else {
            preconditionFailure("Displayed runtime was not staged")
        }
        state = .published
    }

    var freshTabs: [(Tab, BrowserWindowState)] { binding.freshTabs }

    private func sourceContainerWasRemoved() -> Bool {
        guard let sourceSpaceID = binding.sourceSpaceID else { return false }
        return regularTabs.containsIdentical(
            binding.sourceTab,
            in: sourceSpaceID
        ) == false
    }
}
