import Foundation

@MainActor
final class PreparedTabTerminalModelRetirement {
    enum PhysicalClaimOutcome: Equatable {
        case claimed, alreadyOwned, rejected
    }

    private enum State {
        case prepared, modelClaimed, silentModelCommitted
        case physicalEffectClaimed, lifecyclePublished, terminal
    }

    private let tabs: [Tab]
    private let membership: TabCollectionMembershipOwner
    private let publisher: TabTerminalModelPublisher
    private let sourceModelIsExact: @MainActor () -> Bool
    private var physicalEffect: (@MainActor () -> Void)?
    private var state = State.prepared

    init?(
        tabs: [Tab],
        membership: TabCollectionMembershipOwner,
        publisher: TabTerminalModelPublisher,
        sourceModelIsExact: @escaping @MainActor () -> Bool
    ) {
        guard tabs.isEmpty == false,
              Set(tabs.map(\.id)).count == tabs.count else { return nil }
        self.tabs = tabs
        self.membership = membership
        self.publisher = publisher
        self.sourceModelIsExact = sourceModelIsExact
        let witnesses = membership.allIdentityWitnesses()
        guard tabs.allSatisfy({ tab in
            membership.contains(tab)
                && membership.isTransientExtensionTab(tab) == false
                && membership.isAuxiliaryMiniWindowTab(tab) == false
                && witnesses.filter { $0.id == tab.id }.count == 1
                && witnesses.first { $0.id == tab.id } === tab
        }), isCurrent() else { return nil }
    }

    func isCurrent() -> Bool {
        guard case .prepared = state else { return false }
        return exactSourceModelIsRetained()
    }

    func claimModel() -> Bool {
        guard isCurrent() else { return false }
        state = .modelClaimed
        return claimedModelIsExact()
    }

    func claimedModelIsExact() -> Bool {
        guard case .modelClaimed = state else { return false }
        return exactSourceModelIsRetained()
    }

    func commitSilentModel(after sourcePublication: () -> Void) -> Bool {
        guard claimedModelIsExact() else { return false }
        sourcePublication()
        guard publisher.settleExact(tabs) == .settled(Set(tabs.map(\.id))) else {
            state = .terminal
            return false
        }
        state = .silentModelCommitted
        return true
    }

    func claimPhysicalEffect(
        preparing effect: () -> (@MainActor () -> Void)?
    ) -> PhysicalClaimOutcome {
        switch state {
        case .silentModelCommitted:
            let witnesses = membership.allIdentityWitnesses()
            guard tabs.allSatisfy({ tab in
                witnesses.contains { $0.id == tab.id } == false
            }) else { return .rejected }
            state = .physicalEffectClaimed
            guard let effect = effect() else {
                state = .terminal
                return .rejected
            }
            physicalEffect = effect
            return .claimed
        case .physicalEffectClaimed, .lifecyclePublished, .terminal:
            return .alreadyOwned
        case .prepared, .modelClaimed:
            return .rejected
        }
    }

    func publishLifecycle() -> Bool {
        guard case .physicalEffectClaimed = state else { return false }
        state = .lifecyclePublished
        precondition(publisher.publishEffects(tabs) == Set(tabs.map(\.id)))
        return true
    }

    func physicalEffectIsClaimed() -> Bool {
        switch state {
        case .physicalEffectClaimed, .lifecyclePublished: return true
        case .prepared, .modelClaimed, .silentModelCommitted, .terminal:
            return false
        }
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

    func cancelPrepared() -> Bool {
        switch state {
        case .prepared, .modelClaimed:
            state = .terminal
            return true
        case .silentModelCommitted, .physicalEffectClaimed,
                .lifecyclePublished, .terminal:
            return false
        }
    }

    private func exactSourceModelIsRetained() -> Bool {
        sourceModelIsExact() && membership.canDetachExact(tabs)
    }
}
