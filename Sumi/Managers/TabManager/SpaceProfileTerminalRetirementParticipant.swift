import Foundation

/// Owns exact membership settlement and the final runtime effect for the tabs
/// retired by one Space-profile transaction.
@MainActor
final class SpaceProfileTerminalRetirementParticipant {
    private enum State {
        case prepared
        case modelClaimed
        case silentModelCommitted
        case terminal
    }

    private let expectedTabIDs: Set<UUID>
    private let terminalLifecycle: PreparedTabTerminalLifecyclePublication
    private let teardown: TabRuntimeTeardownService
    private var state = State.prepared

    init?(
        tabs: [Tab],
        teardown: TabRuntimeTeardownService,
        sourceModelIsExact: @escaping @MainActor () -> Bool
    ) {
        guard let terminalLifecycle = teardown.terminalRetirement
            .prepareTerminalLifecyclePublication(
                afterDetaching: tabs,
                modelIsExact: sourceModelIsExact
            ) else { return nil }
        expectedTabIDs = Set(tabs.map(\.id))
        self.terminalLifecycle = terminalLifecycle
        self.teardown = teardown
    }

    func isCurrentBeforeModelStage() -> Bool {
        guard case .prepared = state else { return false }
        return terminalLifecycle.isCurrentBeforeModelStage()
    }

    func canClaimModel() -> Bool {
        guard case .prepared = state else { return false }
        return terminalLifecycle.canClaimStagedModel()
    }

    func claimModel() -> Bool {
        guard case .prepared = state,
              terminalLifecycle.claimStagedModel() else { return false }
        state = .modelClaimed
        return true
    }

    func commitSilentModel() -> Bool {
        guard case .modelClaimed = state,
              terminalLifecycle.commitSilentModel() else {
            state = .terminal
            return false
        }
        state = .silentModelCommitted
        return true
    }

    func cancelBeforeSilentCommit() {
        switch state {
        case .prepared, .modelClaimed:
            terminalLifecycle.cancelBeforeSilentCommit()
        case .silentModelCommitted, .terminal:
            break
        }
        state = .terminal
    }

    func publish(
        _ effects: SpaceProfilePresentationTerminalEffects,
        canPublishNormally: @escaping () -> Bool,
        afterTeardown: @escaping (RuntimePortRegistry?) -> Void
    ) {
        guard case .silentModelCommitted = state else { return }
        let claim = terminalLifecycle.claimPhysicalEffect { [teardown] in
            Self.preparePhysicalEffect(
                effects,
                teardown: teardown,
                expectedTabIDs: expectedTabIDs,
                canPublishNormally: canPublishNormally,
                afterTeardown: afterTeardown
            )
        }
        state = .terminal
        switch claim {
        case .claimed:
            precondition(terminalLifecycle.publishLifecycle())
            precondition(terminalLifecycle.finishPhysicalEffect())
        case .rejected:
            guard case .committed(let ownership) = effects else { return }
            teardown.retirement.destroyCommittedRuntime(ownership)
        case .alreadyOwned:
            break
        }
    }

    func settleTerminalDrain(
        _ effects: SpaceProfilePresentationTerminalEffects
    ) {
        switch state {
        case .prepared, .modelClaimed:
            terminalLifecycle.cancelBeforeSilentCommit()
        case .silentModelCommitted, .terminal:
            break
        }
        state = .terminal
        guard case .committed(let ownership) = effects else { return }
        teardown.retirement.destroyAfterTerminalDrain(ownership)
    }

    private static func preparePhysicalEffect(
        _ effects: SpaceProfilePresentationTerminalEffects,
        teardown: TabRuntimeTeardownService,
        expectedTabIDs: Set<UUID>,
        canPublishNormally: @escaping () -> Bool,
        afterTeardown: @escaping (RuntimePortRegistry?) -> Void
    ) -> (@MainActor () -> Void)? {
        switch effects {
        case .none:
            return { afterTeardown(nil) }
        case .committed(let ownership):
            guard let cleanup = teardown.retirement
                .claimNormalRuntimePublication(ownership) else { return nil }
            return {
                guard canPublishNormally() else {
                    teardown.retirement.destroyClaimedAfterTerminalDrain(cleanup)
                    return
                }
                precondition(
                    teardown.retirement.publishClaimedRuntime(
                        cleanup,
                        beforeDestruction: { runtime in
                            guard canPublishNormally() else { return }
                            afterTeardown(runtime)
                        }
                    ) == expectedTabIDs
                )
            }
        case .empty(let prepared):
            return {
                guard canPublishNormally() else { return }
                precondition(
                    teardown.finishRuntime(prepared) == expectedTabIDs
                )
                afterTeardown(prepared.runtime)
            }
        }
    }
}
