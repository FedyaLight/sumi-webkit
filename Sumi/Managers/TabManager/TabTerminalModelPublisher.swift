@MainActor
final class TabTerminalModelPublisher {
    private let persistence: TabStructuralPersistenceService
    private let membership: TabCollectionMembershipOwner

    init(
        persistence: TabStructuralPersistenceService,
        membership: TabCollectionMembershipOwner
    ) {
        self.persistence = persistence
        self.membership = membership
    }

    func prepareRetirement(
        _ tabs: [Tab],
        sourceModelIsExact: @escaping @MainActor () -> Bool
    ) -> PreparedTabTerminalModelRetirement? {
        PreparedTabTerminalModelRetirement(
            tabs: tabs,
            membership: membership,
            publisher: self,
            sourceModelIsExact: sourceModelIsExact
        )
    }

    func prepareLifecyclePublication(
        afterDetaching tabs: [Tab],
        modelIsExact: @escaping @MainActor () -> Bool
    ) -> PreparedTabTerminalLifecyclePublication? {
        PreparedTabTerminalLifecyclePublication(
            tabs: tabs,
            membership: membership,
            publisher: self,
            modelIsExact: modelIsExact
        )
    }

    @discardableResult
    func publish(_ tabs: [Tab]) -> Set<UUID> {
        let tabIDs = settle(tabs)
        precondition(publishEffects(tabs) == tabIDs)
        return tabIDs
    }

    @discardableResult
    func settle(_ tabs: [Tab]) -> Set<UUID> {
        let tabIDs = Set(tabs.map(\.id))
        guard tabIDs.isEmpty == false else { return [] }
        for tab in tabs {
            persistence.cancelRuntimeStatePersistence(for: tab.id)
            membership.detach(tab)
        }
        return tabIDs
    }

    func settleExact(
        _ tabs: [Tab]
    ) -> TabTerminalModelExactSettlementOutcome {
        guard membership.canDetachExact(tabs), tabs.allSatisfy({
            membership.isTransientExtensionTab($0) == false
                && membership.isAuxiliaryMiniWindowTab($0) == false
        }) else { return .rejected }
        let tabIDs = Set(tabs.map(\.id))
        tabs.forEach { persistence.cancelRuntimeStatePersistence(for: $0.id) }
        precondition(membership.detachExact(tabs))
        return .settled(tabIDs)
    }

    func settleAlreadyDetachedExact(
        _ tabs: [Tab]
    ) -> TabTerminalModelExactSettlementOutcome {
        let retiredIDs = Set(tabs.map(\.id))
        guard retiredIDs.isEmpty == false,
              membership.allIdentityWitnesses().allSatisfy({
                  retiredIDs.contains($0.id) == false
              }) else { return .rejected }
        tabs.forEach { persistence.cancelRuntimeStatePersistence(for: $0.id) }
        return .settled(retiredIDs)
    }

    @discardableResult
    func publishEffects(_ tabs: [Tab]) -> Set<UUID> {
        let tabIDs = Set(tabs.map(\.id))
        tabs.forEach { $0.stateChangeEmitter.postLifecycleDidChange(for: $0) }
        return tabIDs
    }
}

enum TabTerminalModelExactSettlementOutcome: Equatable {
    case settled(Set<UUID>)
    case rejected
}
