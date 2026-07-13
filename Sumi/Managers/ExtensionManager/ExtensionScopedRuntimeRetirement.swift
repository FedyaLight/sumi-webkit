import Foundation

/// Retires every profile-scoped runtime binding for one extension. Claims are
/// revoked before any external close/unload callback can re-enter the runtime.
/// Package replacement preserves UI anchors; user disable removes them.
@available(macOS 15.5, *)
@MainActor
final class ExtensionScopedRuntimeRetirement {
    struct Resources {
        let auxiliaryWindows: (any ExtensionAuxiliaryWindowControl)?
        let nativeMessagingWakes:
            ExtensionNativeMessagingBackgroundWakeOwner?
        let nativeMessagingRelay: SumiNativeMessagingRelay?
    }

    enum Admission {
        case mutation(ExtensionRuntimeMutationLease)
        case terminal(ExtensionRuntimeTerminalLease)
        case rollback(
            ExtensionContextLoadClaim,
            ExtensionRuntimeMutationLease?
        )
    }

    enum Cause: Equatable {
        case disabled
        case packageReplacement
        case runtimeRollback

        var clearsActionAnchors: Bool {
            self == .disabled
        }
    }

    enum CompletionStatus: Equatable {
        case rejected
        case superseded
        case contextsRemaining
        case completed
    }

    struct Result {
        let completionStatus: CompletionStatus
        let initialProfileIDs: Set<UUID>
        let contextOutcomes:
            [ExtensionRuntimeResidencyState.ScopedKey:
                ExtensionContextRetirement.Outcome]
        let remainingProfileIDs: Set<UUID>

        var completed: Bool {
            completionStatus == .completed
        }

        var isQuiescent: Bool {
            remainingProfileIDs.isEmpty
        }
    }

    private let profileRuntime: ExtensionProfileRuntime
    private let mutationRegistry: ExtensionRuntimeMutationRegistry
    private let loadRegistry: ExtensionContextLoadRegistry
    private let contextRetirement: ExtensionContextRetirement
    private let runtimeCatalog: ExtensionRuntimeCatalog
    private let runtimeResidency: ExtensionRuntimeResidencyAuthority
    private let sourceCache: WebExtensionRuntimeSourceCache
    private let errorObservation: ExtensionContextErrorObservation
    private let nativeMessagingPorts: ExtensionNativeMessagingPortRegistry
    private let optionsWindows: ExtensionOptionsWindowService
    private let actionAnchors: ExtensionActionAnchorStore
    private let diagnostics: ExtensionRuntimeDiagnostics

    init(
        profileRuntime: ExtensionProfileRuntime,
        mutationRegistry: ExtensionRuntimeMutationRegistry,
        loadRegistry: ExtensionContextLoadRegistry,
        contextRetirement: ExtensionContextRetirement,
        runtimeCatalog: ExtensionRuntimeCatalog,
        runtimeResidency: ExtensionRuntimeResidencyAuthority,
        sourceCache: WebExtensionRuntimeSourceCache,
        errorObservation: ExtensionContextErrorObservation,
        nativeMessagingPorts: ExtensionNativeMessagingPortRegistry,
        optionsWindows: ExtensionOptionsWindowService,
        actionAnchors: ExtensionActionAnchorStore,
        diagnostics: ExtensionRuntimeDiagnostics
    ) {
        self.profileRuntime = profileRuntime
        self.mutationRegistry = mutationRegistry
        self.loadRegistry = loadRegistry
        self.contextRetirement = contextRetirement
        self.runtimeCatalog = runtimeCatalog
        self.runtimeResidency = runtimeResidency
        self.sourceCache = sourceCache
        self.errorObservation = errorObservation
        self.nativeMessagingPorts = nativeMessagingPorts
        self.optionsWindows = optionsWindows
        self.actionAnchors = actionAnchors
        self.diagnostics = diagnostics
    }

    @discardableResult
    func retire(
        extensionID: String,
        cause: Cause,
        admission: Admission,
        resources: Resources
    ) -> Result {
        let initialProfileIDs = currentProfileIDs(extensionID: extensionID)
        guard isAdmitted(extensionID: extensionID, admission: admission) else {
            return Result(
                completionStatus: .rejected,
                initialProfileIDs: initialProfileIDs,
                contextOutcomes: [:],
                remainingProfileIDs: initialProfileIDs
            )
        }
        let isRollbackCleanup: Bool
        if case .rollback = admission {
            isRollbackCleanup = true
            // Keep the rollback claim visible until cleanup finishes. A newer
            // claim must be able to supersede this cleanup before it erases
            // extension-scoped state published by the replacement load.
        } else {
            isRollbackCleanup = false
            loadRegistry.invalidate(extensionId: extensionID)
            resources.nativeMessagingWakes?.cancelWakeTasks(
                forExtensionId: extensionID
            )
        }

        var outcomes:
            [ExtensionRuntimeResidencyState.ScopedKey:
                ExtensionContextRetirement.Outcome] = [:]
        var processedReceipts = Set<ExtensionContextBindingReceipt>()

        while true {
            let receipts = isRollbackCleanup
                ? []
                : currentReceipts(extensionID: extensionID).filter {
                    processedReceipts.insert($0).inserted
                }
            guard receipts.isEmpty == false else { break }
            for receipt in receipts {
                guard isAdmitted(
                    extensionID: extensionID,
                    admission: admission
                ) else {
                    return supersededResult(
                        extensionID: extensionID,
                        initialProfileIDs: initialProfileIDs,
                        outcomes: outcomes
                    )
                }
                outcomes[receipt.key] = contextRetirement.retire(receipt)
                guard isAdmitted(
                    extensionID: extensionID,
                    admission: admission
                ) else {
                    return supersededResult(
                        extensionID: extensionID,
                        initialProfileIDs: initialProfileIDs,
                        outcomes: outcomes
                    )
                }
            }
        }

        let remainingProfileIDs = currentProfileIDs(extensionID: extensionID)
        guard remainingProfileIDs.isEmpty else {
            diagnostics.trace(
                "scopedRuntimeRetirement incomplete extensionId=\(extensionID) "
                    + "profiles=\(remainingProfileIDs.map(\.uuidString).sorted().joined(separator: ","))"
            )
            return Result(
                completionStatus: .contextsRemaining,
                initialProfileIDs: initialProfileIDs,
                contextOutcomes: outcomes,
                remainingProfileIDs: remainingProfileIDs
            )
        }
        guard isAdmitted(extensionID: extensionID, admission: admission) else {
            return supersededResult(
                extensionID: extensionID,
                initialProfileIDs: initialProfileIDs,
                outcomes: outcomes
            )
        }

        if isRollbackCleanup {
            resources.nativeMessagingWakes?.cancelWakeTasks(
                forExtensionId: extensionID
            )
        }

        resources.auxiliaryWindows?.closeAuxiliaryWindowSessions(
            forExtensionId: extensionID,
            reason: .extensionDisable
        )
        guard isAdmitted(extensionID: extensionID, admission: admission) else {
            return supersededResult(
                extensionID: extensionID,
                initialProfileIDs: initialProfileIDs,
                outcomes: outcomes
            )
        }
        optionsWindows.closeWindow(for: extensionID)
        guard isAdmitted(extensionID: extensionID, admission: admission) else {
            return supersededResult(
                extensionID: extensionID,
                initialProfileIDs: initialProfileIDs,
                outcomes: outcomes
            )
        }
        nativeMessagingPorts.disconnect(extensionId: extensionID)
        guard isAdmitted(extensionID: extensionID, admission: admission) else {
            return supersededResult(
                extensionID: extensionID,
                initialProfileIDs: initialProfileIDs,
                outcomes: outcomes
            )
        }
        resources.nativeMessagingRelay?.clearLoopGuard(
            forExtensionId: extensionID
        )
        guard isAdmitted(extensionID: extensionID, admission: admission) else {
            return supersededResult(
                extensionID: extensionID,
                initialProfileIDs: initialProfileIDs,
                outcomes: outcomes
            )
        }
        if cause.clearsActionAnchors {
            actionAnchors.clearAnchors(for: extensionID)
        }
        errorObservation.removeObservations(forExtensionID: extensionID)
        errorObservation.removeLoggedErrorFingerprints(
            forExtensionID: extensionID
        )
        runtimeCatalog.retire(extensionID: extensionID)
        sourceCache.remove(extensionID: extensionID)
        runtimeResidency.retire(extensionID: extensionID)

        diagnostics.trace(
            "scopedRuntimeRetirement complete extensionId=\(extensionID) "
                + "cause=\(String(describing: cause))"
        )
        return Result(
            completionStatus: .completed,
            initialProfileIDs: initialProfileIDs,
            contextOutcomes: outcomes,
            remainingProfileIDs: []
        )
    }

    private func isAdmitted(
        extensionID: String,
        admission: Admission
    ) -> Bool {
        switch admission {
        case .mutation(let lease):
            return lease.extensionID == extensionID
                && mutationRegistry.isCurrent(lease)
        case .terminal(let lease):
            return mutationRegistry.isCurrent(lease)
        case .rollback(let claim, let mutationLease):
            return claim.key.extensionId == extensionID
                && loadRegistry.admitsExtensionGlobalRollback(claim)
                && mutationRegistry.admitsLoad(
                    extensionID: extensionID,
                    lease: mutationLease
                )
        }
    }

    private func supersededResult(
        extensionID: String,
        initialProfileIDs: Set<UUID>,
        outcomes: [
            ExtensionRuntimeResidencyState.ScopedKey:
                ExtensionContextRetirement.Outcome
        ]
    ) -> Result {
        let remainingProfileIDs = currentProfileIDs(extensionID: extensionID)
        diagnostics.trace(
            "scopedRuntimeRetirement superseded extensionId=\(extensionID) "
                + "profiles=\(remainingProfileIDs.map(\.uuidString).sorted().joined(separator: ","))"
        )
        return Result(
            completionStatus: .superseded,
            initialProfileIDs: initialProfileIDs,
            contextOutcomes: outcomes,
            remainingProfileIDs: remainingProfileIDs
        )
    }

    private func currentProfileIDs(extensionID: String) -> Set<UUID> {
        Set(
            profileRuntime.contextsByProfile.compactMap { profileID, contexts in
                contexts[extensionID] == nil ? nil : profileID
            }
        )
    }

    private func currentReceipts(
        extensionID: String
    ) -> [ExtensionContextBindingReceipt] {
        profileRuntime.contextsByProfile.keys.compactMap { profileID in
            profileRuntime.contextBindingReceipt(
                extensionId: extensionID,
                profileId: profileID
            )
        }
    }
}
