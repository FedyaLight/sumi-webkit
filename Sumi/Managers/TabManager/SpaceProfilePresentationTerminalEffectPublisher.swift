import Foundation

/// Executes irreversible WebView destruction after the enclosing structural
/// model is complete but before its first external structural publication.
@MainActor
final class SpaceProfilePresentationTerminalEffectPublisher {
    private let structuralLookup: TabStructuralLookupCoordinator
    private let runtimeTeardown: TabRuntimeTeardownService

    init(
        structuralLookup: TabStructuralLookupCoordinator,
        runtimeTeardown: TabRuntimeTeardownService
    ) {
        self.structuralLookup = structuralLookup
        self.runtimeTeardown = runtimeTeardown
    }

    func publish(
        _ receipt: SpaceProfilePresentationTerminalEffectReceipt,
        terminalRetirement: SpaceProfileTerminalRetirementParticipant?,
        expectedTabIDs: Set<UUID>,
        canPublishNormally: @escaping () -> Bool,
        afterTeardown: @escaping (RuntimePortRegistry?) -> Void
    ) {
        structuralLookup.runBeforeCurrentBatchPublication {
            [runtimeTeardown] in
            guard canPublishNormally() else {
                receipt.claimDrain { effects in
                    if let terminalRetirement {
                        terminalRetirement.settleTerminalDrain(effects)
                        return
                    }
                    guard case .committed(let committed) = effects else {
                        return
                    }
                    runtimeTeardown.retirement
                        .destroyAfterTerminalDrain(committed)
                }
                return
            }
            receipt.claimNormal { effects in
                if let terminalRetirement {
                    terminalRetirement.publish(
                        effects,
                        canPublishNormally: canPublishNormally,
                        afterTeardown: afterTeardown
                    )
                    return
                }
                let runtime: RuntimePortRegistry?
                switch effects {
                case .none:
                    runtime = nil
                case .committed(let committed):
                    guard let claimed = runtimeTeardown.retirement
                        .claimNormalRuntimePublication(committed) else {
                        return
                    }
                    precondition(
                        runtimeTeardown.retirement.publishClaimedRuntime(
                            claimed,
                            beforeDestruction: { runtime in
                                guard canPublishNormally() else { return }
                                afterTeardown(runtime)
                            }
                        )
                            == expectedTabIDs
                    )
                    return
                case .empty(let prepared):
                    precondition(
                        runtimeTeardown.finish(prepared) == expectedTabIDs
                    )
                    runtime = prepared.runtime
                }
                afterTeardown(runtime)
            }
        }
    }
}
