import Foundation
import WebKit

@available(macOS 15.5, *)
enum ExternalStateRollbackDisposition: Equatable {
    case rollbackAllowed
    case preserveForExactRuntime
    case preserveForReplacement
    case preserveForActiveBinding
    case preserveForCompetingTransaction
    case preserveUntilSharedCleanup
}

/// Owns admission and revocation for extension context load claims without
/// depending on WebKit controllers, bound contexts, or rollback machinery.
/// Source preparation can therefore validate publication authority without
/// forcing the destructive runtime graph to initialize.
@available(macOS 15.5, *)
@MainActor
final class ExtensionContextLoadAdmission {
    private let mutationRegistry: ExtensionRuntimeMutationRegistry
    private let loadRegistry: ExtensionContextLoadRegistry

    init(
        mutationRegistry: ExtensionRuntimeMutationRegistry,
        loadRegistry: ExtensionContextLoadRegistry
    ) {
        self.mutationRegistry = mutationRegistry
        self.loadRegistry = loadRegistry
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

    func beginIfIdle(
        for key: ExtensionRuntimeResidencyState.ScopedKey,
        mutationLease: ExtensionRuntimeMutationLease?
    ) throws -> ExtensionContextLoadClaim {
        guard mutationRegistry.admitsLoad(
            extensionID: key.extensionId,
            lease: mutationLease
        ), let claim = loadRegistry.beginIfIdle(for: key)
        else {
            throw CancellationError()
        }
        return claim
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

    @discardableResult
    func finish(_ claim: ExtensionContextLoadClaim) -> Bool {
        loadRegistry.finishIfCurrent(claim)
    }

    func hasCompetingClaim(for claim: ExtensionContextLoadClaim) -> Bool {
        loadRegistry.hasCompetingClaim(for: claim)
    }

    func hasCompetingMutation(
        extensionID: String,
        excluding lease: ExtensionRuntimeMutationLease?
    ) -> Bool {
        mutationRegistry.hasCompetingScopedMutation(
            extensionID: extensionID,
            excluding: lease
        )
    }
}

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

        var externalStateDisposition: ExternalStateRollbackDisposition {
            switch exactDisposition {
            case .exactBindingRemaining, .exactContextStillLoaded:
                return .preserveForExactRuntime
            case .replacementPresent:
                return .preserveForReplacement
            case .retired:
                switch sharedCleanupDisposition {
                case .notAttempted:
                    return .preserveUntilSharedCleanup
                case .completed, .supersededWithoutCompetingAuthority:
                    return .rollbackAllowed
                case .preservedForActiveBindings:
                    return .preserveForActiveBinding
                case .preservedForCompetingTransaction:
                    return .preserveForCompetingTransaction
                }
            }
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
    private let admission: ExtensionContextLoadAdmission
    private let contextRetirement: ExtensionContextRetirement

    init(
        profileRuntime: ExtensionProfileRuntime,
        admission: ExtensionContextLoadAdmission,
        contextRetirement: ExtensionContextRetirement
    ) {
        self.profileRuntime = profileRuntime
        self.admission = admission
        self.contextRetirement = contextRetirement
    }

    convenience init(
        profileRuntime: ExtensionProfileRuntime,
        mutationRegistry: ExtensionRuntimeMutationRegistry,
        loadRegistry: ExtensionContextLoadRegistry,
        contextRetirement: ExtensionContextRetirement
    ) {
        self.init(
            profileRuntime: profileRuntime,
            admission: ExtensionContextLoadAdmission(
                mutationRegistry: mutationRegistry,
                loadRegistry: loadRegistry
            ),
            contextRetirement: contextRetirement
        )
    }

    func beginLoad(
        extensionID: String,
        profileID: UUID,
        mutationLease: ExtensionRuntimeMutationLease?
    ) throws -> ExtensionContextLoadClaim {
        try admission.beginLoad(
            extensionID: extensionID,
            profileID: profileID,
            mutationLease: mutationLease
        )
    }

    func beginFinalization(
        extensionID: String,
        profileID: UUID,
        mutationLease: ExtensionRuntimeMutationLease?
    ) throws -> ExtensionLoadedContext {
        let key = ExtensionRuntimeResidencyState.ScopedKey(
            profileId: profileID,
            extensionId: extensionID
        )
        let claim = try admission.beginIfIdle(
            for: key,
            mutationLease: mutationLease
        )

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
            let loadedContext = ExtensionLoadedContext(
                context: context,
                controller: controller,
                bindingReceipt: receipt,
                loadClaim: claim,
                mutationLease: mutationLease
            )
            try validate(loadedContext)
            return loadedContext
        } catch {
            _ = admission.finish(claim)
            throw error
        }
    }

    func validate(
        _ loadedContext: ExtensionLoadedContext
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
        try admission.validate(claim, mutationLease: mutationLease)
    }

    func isCurrent(_ claim: ExtensionContextLoadClaim) -> Bool {
        admission.isCurrent(claim)
    }

    func sharedCleanupBlocker(
        for loadedContext: ExtensionLoadedContext
    ) -> SharedCleanupBlocker {
        let extensionID = loadedContext.bindingReceipt.key.extensionId
        if profileRuntime.contextsByProfile.values.contains(where: {
            $0[extensionID] != nil
        }) {
            return .activeBinding
        }
        if admission.hasCompetingClaim(for: loadedContext.loadClaim) {
            return .competingLoad
        }
        if admission.hasCompetingMutation(
            extensionID: extensionID,
            excluding: loadedContext.mutationLease
        ) {
            return .competingMutation
        }
        return .none
    }

    @discardableResult
    func finish(
        _ loadedContext: ExtensionLoadedContext
    ) -> Bool {
        admission.finish(loadedContext.loadClaim)
    }

    @discardableResult
    func finish(_ claim: ExtensionContextLoadClaim) -> Bool {
        admission.finish(claim)
    }

    func rollback(
        _ loadedContext: ExtensionLoadedContext
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

/// Carries the exact runtime rollback result whenever external package or
/// metadata rollback must be deferred to a surviving runtime authority.
@available(macOS 15.5, *)
struct ExtensionRuntimeTransactionFailure: LocalizedError {
    let operationError: any Error
    let rollback: ExtensionLoadedContextAuthority.RollbackResult

    var errorDescription: String? {
        let reason: String
        switch rollback.externalStateDisposition {
        case .rollbackAllowed:
            reason = "external package and metadata rollback is allowed"
        case .preserveForExactRuntime:
            reason = "the failed exact runtime is still bound or loaded"
        case .preserveForReplacement:
            reason = "a replacement runtime owns the extension state"
        case .preserveForActiveBinding:
            reason = "another active profile binding owns the extension state"
        case .preserveForCompetingTransaction:
            reason = "a competing runtime transaction may own the extension state"
        case .preserveUntilSharedCleanup:
            reason = "shared runtime cleanup has not completed"
        }
        return "\(operationError.localizedDescription). Runtime rollback "
            + "finished with \(String(describing: rollback.outcome)); "
            + "\(reason) for \(rollback.key.rawValue)"
    }
}
