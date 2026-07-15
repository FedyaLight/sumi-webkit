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
        expectedTabIDs: Set<UUID>,
        canPublishNormally: @escaping () -> Bool,
        afterTeardown: @escaping (RuntimePortRegistry?) -> Void
    ) {
        structuralLookup.runBeforeCurrentBatchPublication {
            [runtimeTeardown] in
            guard canPublishNormally() else {
                receipt.claimDrain { effects in
                    guard case .committed(let committed) = effects else {
                        return
                    }
                    runtimeTeardown.retirement
                        .destroyAfterTerminalDrain(committed)
                }
                return
            }
            receipt.claimNormal { effects in
                let runtime: RuntimePortRegistry?
                switch effects {
                case .none:
                    runtime = nil
                case .committed(let committed):
                    precondition(
                        runtimeTeardown.retirement.publish(committed)
                            == expectedTabIDs
                    )
                    runtime = committed.runtime
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
