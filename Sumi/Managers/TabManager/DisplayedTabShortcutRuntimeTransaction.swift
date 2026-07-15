import Foundation

/// Window and fresh-membership participant for one displayed conversion.
/// Raw window state is reversible; membership opens only after terminal claim.
@MainActor
final class DisplayedTabShortcutRuntimeTransaction {
    private enum State {
        case prepared, staged, published, rolledBack, abandoned
    }

    let windows: ShortcutTabBindingWindowContribution
    private let binding: PreparedDisplayedTabShortcutBinding
    private let membershipWitness: DisplayedTabShortcutMembershipWitness
    private let containerRemoval: ShortcutContainerRemovalOwner
    private let regularTabs: RegularTabCollectionOwner
    private let structuralLookup: TabStructuralLookupCoordinator
    private let runtimeAttachment: TabRuntimeAttachmentWitness
    private var state = State.prepared

    init(
        windows: ShortcutTabBindingWindowContribution,
        binding: PreparedDisplayedTabShortcutBinding,
        membershipWitness: DisplayedTabShortcutMembershipWitness,
        containerRemoval: ShortcutContainerRemovalOwner,
        regularTabs: RegularTabCollectionOwner,
        structuralLookup: TabStructuralLookupCoordinator,
        runtimeAttachment: TabRuntimeAttachmentWitness
    ) {
        self.windows = windows
        self.binding = binding
        self.membershipWitness = membershipWitness
        self.containerRemoval = containerRemoval
        self.regularTabs = regularTabs
        self.structuralLookup = structuralLookup
        self.runtimeAttachment = runtimeAttachment
    }

    func validateForStaging() -> Bool {
        guard case .prepared = state else { return false }
        guard let sourceSpaceID = binding.sourceSpaceID else { return false }
        return runtimeAttachment.isCurrent()
            && membershipWitness.preparedModelIsExact()
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
        guard runtimeAttachment.isCurrent(),
              sourceContainerWasRemoved(),
              membershipWitness.sourceRemovalIsExact() else { return false }
        state = .staged
        return true
    }

    func stagedModelIsExact() -> Bool {
        guard case .staged = state else { return false }
        return runtimeAttachment.isCurrent()
            && sourceContainerWasRemoved()
            && membershipWitness.stagedResidencesAreExact()
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

    func publishAfterBinding() {
        guard case .staged = state else {
            preconditionFailure("Displayed runtime was not staged")
        }
        state = .published
        let attachment = runtimeAttachment
        structuralLookup.runAfterCurrentBatch { [binding] in
            guard let runtime = attachment.currentRegistry() else { return }
            binding.freshTabs.forEach {
                runtime.webViewLifecycle.materializeVisibleTabWebViewIfNeeded(
                    $0.0,
                    in: $0.1
                )
            }
        }
    }

    private func sourceContainerWasRemoved() -> Bool {
        guard let sourceSpaceID = binding.sourceSpaceID else { return false }
        return regularTabs.containsIdentical(
            binding.sourceTab,
            in: sourceSpaceID
        ) == false
    }
}
