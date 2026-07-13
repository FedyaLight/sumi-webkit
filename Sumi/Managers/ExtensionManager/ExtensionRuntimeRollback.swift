import Foundation

/// Completes compensation for one failed context transaction. Exact WebKit
/// retirement happens first; extension-scoped publications and caches are
/// cleared only when no exact or replacement binding remains.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeRollback {
    private let authority: ExtensionLoadedContextAuthority
    private let retirement: ExtensionRuntimeRetirement

    init(
        authority: ExtensionLoadedContextAuthority,
        retirement: ExtensionRuntimeRetirement
    ) {
        self.authority = authority
        self.retirement = retirement
    }

    func rollBack(
        _ loadedContext: ExtensionLoadedContext
    ) -> ExtensionLoadedContextAuthority.RollbackResult {
        let contextRollback = authority.rollback(loadedContext)
        guard contextRollback.exactRollbackCompleted else {
            return contextRollback
        }

        let cleanup = retirement.cleanUpAfterQuiescentRollback(
            extensionID: contextRollback.key.extensionId,
            claim: loadedContext.loadClaim,
            mutationLease: loadedContext.mutationLease
        )
        let disposition:
            ExtensionLoadedContextAuthority.SharedCleanupDisposition
        switch cleanup.completionStatus {
        case .completed:
            disposition = .completed
        case .contextsRemaining:
            disposition = .preservedForActiveBindings
        case .rejected, .superseded:
            switch authority.sharedCleanupBlocker(for: loadedContext) {
            case .activeBinding:
                disposition = .preservedForActiveBindings
            case .competingLoad, .competingMutation:
                disposition = .preservedForCompetingTransaction
            case .none:
                disposition = .supersededWithoutCompetingAuthority
            }
        }
        return contextRollback.withSharedCleanupDisposition(disposition)
    }
}
