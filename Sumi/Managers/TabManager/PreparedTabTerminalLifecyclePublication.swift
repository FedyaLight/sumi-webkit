import Foundation

@MainActor
final class PreparedTabTerminalLifecyclePublication {
    enum PhysicalClaimOutcome: Equatable {
        case claimed, alreadyOwned, rejected
    }

    private enum State {
        case prepared, stagedModelClaimed, silentModelCommitted
        case physicalEffectClaimed, lifecyclePublished, terminal
    }

    private let tabs: [Tab]
    private let membership: TabCollectionMembershipOwner
    private let publisher: TabTerminalModelPublisher
    private let modelIsExact: @MainActor () -> Bool
    private var physicalEffect: (@MainActor () -> Void)?
    private var state = State.prepared

    init?(
        tabs: [Tab],
        membership: TabCollectionMembershipOwner,
        publisher: TabTerminalModelPublisher,
        modelIsExact: @escaping @MainActor () -> Bool
    ) {
        guard tabs.isEmpty == false,
              Set(tabs.map(\.id)).count == tabs.count else { return nil }
        self.tabs = tabs
        self.membership = membership
        self.publisher = publisher
        self.modelIsExact = modelIsExact
        guard preparedModelIsExact() else { return nil }
    }

    func isCurrentBeforeModelStage() -> Bool {
        guard case .prepared = state else { return false }
        return preparedModelIsExact()
    }

    func canClaimStagedModel() -> Bool {
        guard case .prepared = state else { return false }
        return exactDetachedModelIsRetained()
    }

    func claimStagedModel() -> Bool {
        guard canClaimStagedModel() else { return false }
        state = .stagedModelClaimed
        return true
    }

    func commitSilentModel() -> Bool {
        guard case .stagedModelClaimed = state,
              exactDetachedModelIsRetained() else {
            state = .terminal
            return false
        }
        state = .silentModelCommitted
        guard publisher.settleAlreadyDetachedExact(tabs)
            == .settled(Set(tabs.map(\.id))) else {
            state = .terminal
            return false
        }
        return true
    }

    func claimPhysicalEffect(
        preparing effect: () -> (@MainActor () -> Void)?
    ) -> PhysicalClaimOutcome {
        switch state {
        case .silentModelCommitted:
            guard exactDetachedModelIsRetained() else { return .rejected }
            state = .physicalEffectClaimed
            guard let effect = effect() else {
                state = .terminal
                return .rejected
            }
            physicalEffect = effect
            return .claimed
        case .physicalEffectClaimed, .lifecyclePublished, .terminal:
            return .alreadyOwned
        case .prepared, .stagedModelClaimed:
            return .rejected
        }
    }

    func publishLifecycle() -> Bool {
        guard case .physicalEffectClaimed = state else { return false }
        state = .lifecyclePublished
        return publisher.publishEffects(tabs) == Set(tabs.map(\.id))
    }

    func finishPhysicalEffect() -> Bool {
        guard case .lifecyclePublished = state, let physicalEffect else {
            return false
        }
        self.physicalEffect = nil
        state = .terminal
        physicalEffect()
        return true
    }

    func cancelBeforeSilentCommit() {
        switch state {
        case .prepared, .stagedModelClaimed:
            state = .terminal
        case .silentModelCommitted, .physicalEffectClaimed,
             .lifecyclePublished, .terminal:
            break
        }
    }

    private func preparedModelIsExact() -> Bool {
        let witnesses = membership.allIdentityWitnesses()
        return modelIsExact()
            && membership.canDetachExact(tabs)
            && tabs.allSatisfy { tab in
                membership.isTransientExtensionTab(tab) == false
                && membership.isAuxiliaryMiniWindowTab(tab) == false
                && witnesses.filter { $0.id == tab.id }.count == 1
                && witnesses.first { $0.id == tab.id } === tab
            }
    }

    private func exactDetachedModelIsRetained() -> Bool {
        let retiredIDs = Set(tabs.map(\.id))
        return modelIsExact() && membership.allIdentityWitnesses().allSatisfy {
            retiredIDs.contains($0.id) == false
        }
    }
}
