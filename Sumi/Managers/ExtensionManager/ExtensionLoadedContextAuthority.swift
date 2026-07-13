import Foundation
import WebKit

/// Owns claim, lease, and exact-binding authority for a loaded extension
/// context transaction. Loading, finalization, recovery, and rollback share
/// this one source of truth instead of each reconstructing admission checks.
@available(macOS 15.5, *)
@MainActor
final class ExtensionLoadedContextAuthority {
    enum ExactRollbackDisposition: Equatable {
        case retired
        case replacementPresent
        case exactBindingRemaining
        case exactContextStillLoaded

        var completed: Bool {
            self == .retired || self == .replacementPresent
        }
    }

    enum SharedCleanupDisposition: Equatable {
        case notAttempted
        case completed
        case preservedForActiveBindings
        case preservedForCompetingTransaction
        case supersededWithoutCompetingAuthority
    }

    enum SharedCleanupBlocker: Equatable {
        case activeBinding
        case competingLoad
        case competingMutation
        case none
    }

    struct RollbackResult {
        let outcome: ExtensionContextRetirement.Outcome
        let key: ExtensionRuntimeResidencyState.ScopedKey
        let exactDisposition: ExactRollbackDisposition
        let sharedCleanupDisposition: SharedCleanupDisposition

        var exactRollbackCompleted: Bool {
            exactDisposition.completed
        }

        var permitsExternalStateRollback: Bool {
            exactRollbackCompleted
                && (
                    sharedCleanupDisposition == .completed
                        || sharedCleanupDisposition
                            == .supersededWithoutCompetingAuthority
                )
        }

        func withSharedCleanupDisposition(
            _ disposition: SharedCleanupDisposition
        ) -> Self {
            .init(
                outcome: outcome,
                key: key,
                exactDisposition: exactDisposition,
                sharedCleanupDisposition: disposition
            )
        }
    }

    private let profileRuntime: ExtensionProfileRuntime
    private let mutationRegistry: ExtensionRuntimeMutationRegistry
    private let loadRegistry: ExtensionContextLoadRegistry
    private let contextRetirement: ExtensionContextRetirement

    init(
        profileRuntime: ExtensionProfileRuntime,
        mutationRegistry: ExtensionRuntimeMutationRegistry,
        loadRegistry: ExtensionContextLoadRegistry,
        contextRetirement: ExtensionContextRetirement
    ) {
        self.profileRuntime = profileRuntime
        self.mutationRegistry = mutationRegistry
        self.loadRegistry = loadRegistry
        self.contextRetirement = contextRetirement
    }

    func beginLoad(
        extensionID: String,
        profileID: UUID,
        mutationLease: ExtensionRuntimeMutationLease?
    ) throws -> ExtensionContextLoadClaim {
        guard mutationRegistry.admitsLoad(
            extensionID: extensionID,
            lease: mutationLease
        ) else {
            throw CancellationError()
        }
        return loadRegistry.begin(
            for: .init(profileId: profileID, extensionId: extensionID)
        )
    }

    func beginFinalization(
        extensionID: String,
        profileID: UUID,
        mutationLease: ExtensionRuntimeMutationLease?
    ) throws -> ExtensionRuntimeContextLoader.LoadedContext {
        let key = ExtensionRuntimeResidencyState.ScopedKey(
            profileId: profileID,
            extensionId: extensionID
        )
        guard mutationRegistry.admitsLoad(
            extensionID: extensionID,
            lease: mutationLease
        ), let claim = loadRegistry.beginIfIdle(for: key)
        else {
            throw CancellationError()
        }

        do {
            guard let receipt = profileRuntime.contextBindingReceipt(
                extensionId: extensionID,
                profileId: profileID
            ), let context = profileRuntime.context(ifCurrent: receipt),
            let controller = profileRuntime.controller(ifCurrent: receipt),
            controller.extensionContexts.contains(where: { $0 === context })
            else {
                throw ExtensionError.installationFailed(
                    "The recovered extension context is not loaded in its authoritative controller"
                )
            }
            let loadedContext = ExtensionRuntimeContextLoader.LoadedContext(
                context: context,
                controller: controller,
                bindingReceipt: receipt,
                loadClaim: claim,
                mutationLease: mutationLease
            )
            try validate(loadedContext)
            return loadedContext
        } catch {
            _ = loadRegistry.finishIfCurrent(claim)
            throw error
        }
    }

    func validate(
        _ loadedContext: ExtensionRuntimeContextLoader.LoadedContext
    ) throws {
        try validate(
            loadedContext.loadClaim,
            mutationLease: loadedContext.mutationLease
        )
        guard
              profileRuntime.context(
                  ifCurrent: loadedContext.bindingReceipt
              ) === loadedContext.context,
              profileRuntime.controller(
                  ifCurrent: loadedContext.bindingReceipt
              ) === loadedContext.controller
        else {
            throw CancellationError()
        }
    }

    func validate(
        _ claim: ExtensionContextLoadClaim,
        mutationLease: ExtensionRuntimeMutationLease?
    ) throws {
        try Task.checkCancellation()
        guard loadRegistry.isCurrent(claim),
              mutationRegistry.admitsLoad(
                  extensionID: claim.key.extensionId,
                  lease: mutationLease
              )
        else {
            throw CancellationError()
        }
    }

    func isCurrent(_ claim: ExtensionContextLoadClaim) -> Bool {
        loadRegistry.isCurrent(claim)
    }

    func sharedCleanupBlocker(
        for loadedContext: ExtensionRuntimeContextLoader.LoadedContext
    ) -> SharedCleanupBlocker {
        let extensionID = loadedContext.bindingReceipt.key.extensionId
        if profileRuntime.contextsByProfile.values.contains(where: {
            $0[extensionID] != nil
        }) {
            return .activeBinding
        }
        if loadRegistry.hasCompetingClaim(for: loadedContext.loadClaim) {
            return .competingLoad
        }
        if mutationRegistry.hasCompetingScopedMutation(
            extensionID: extensionID,
            excluding: loadedContext.mutationLease
        ) {
            return .competingMutation
        }
        return .none
    }

    @discardableResult
    func finish(
        _ loadedContext: ExtensionRuntimeContextLoader.LoadedContext
    ) -> Bool {
        loadRegistry.finishIfCurrent(loadedContext.loadClaim)
    }

    @discardableResult
    func finish(_ claim: ExtensionContextLoadClaim) -> Bool {
        loadRegistry.finishIfCurrent(claim)
    }

    func rollback(
        _ loadedContext: ExtensionRuntimeContextLoader.LoadedContext
    ) -> RollbackResult {
        rollback(
            context: loadedContext.context,
            controller: loadedContext.controller,
            receipt: loadedContext.bindingReceipt
        )
    }

    func rollback(
        context: WKWebExtensionContext,
        controller: WKWebExtensionController,
        receipt: ExtensionContextBindingReceipt
    ) -> RollbackResult {
        let outcome = contextRetirement.rollbackLoad(
            context: context,
            controller: controller,
            receipt: receipt
        )
        let exactContextRemainsLoaded = controller.extensionContexts.contains {
            $0 === context
        }
        let currentBinding = profileRuntime.contextBindingReceipt(
            extensionId: receipt.key.extensionId,
            profileId: receipt.key.profileId
        )
        let exactDisposition: ExactRollbackDisposition
        if exactContextRemainsLoaded {
            exactDisposition = .exactContextStillLoaded
        } else if let currentBinding {
            exactDisposition = currentBinding == receipt
                ? .exactBindingRemaining
                : .replacementPresent
        } else {
            exactDisposition = .retired
        }
        return RollbackResult(
            outcome: outcome,
            key: receipt.key,
            exactDisposition: exactDisposition,
            sharedCleanupDisposition: .notAttempted
        )
    }
}

/// Signals that the exact failed WebKit context or its exact binding could not
/// be retired. A surviving replacement or sibling profile is not this error.
@available(macOS 15.5, *)
struct ExtensionRuntimeTransactionFailure: LocalizedError {
    let operationError: any Error
    let rollback: ExtensionLoadedContextAuthority.RollbackResult

    var errorDescription: String? {
        "\(operationError.localizedDescription). Runtime rollback "
            + "finished with \(String(describing: rollback.outcome)); "
            + "the failed exact context remains for "
            + "\(rollback.key.rawValue)"
    }
}
