import Foundation

@available(macOS 15.5, *)
@MainActor
protocol ExtensionInstallationPackageSettling: AnyObject {
    var ownership: ExtensionInstallationPackage.Ownership { get }
    func commit()
    func rollback() throws
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionInstallationPreviousRuntimeRecovering: AnyObject {
    func recover(
        _ previousRuntime:
            ExtensionInstallationRuntimeReplacement.PreviousRuntime,
        mutationLease: ExtensionRuntimeMutationLease
    ) async throws
}

/// Executes compensation after one prepared installation fails. It does not
/// resolve sources, build candidates, or perform the happy-path commit.
@available(macOS 15.5, *)
@MainActor
final class ExtensionInstallationFailureSettlement {
    struct Context {
        let error: any Error
        let package: any ExtensionInstallationPackageSettling
        let recordSnapshot: ExtensionInstallationRecordTransaction.Snapshot
        let candidateRecord: InstalledExtension?
        let previousRuntime:
            ExtensionInstallationRuntimeReplacement.PreviousRuntime?
        let rollbackRuntimeActivation: (@MainActor @Sendable () ->
            ExtensionLoadedContextAuthority.RollbackResult)?
        let mutationLease: ExtensionRuntimeMutationLease
    }

    private let recordTransaction: ExtensionInstallationRecordTransaction
    private let runtimeReplacement:
        any ExtensionInstallationPreviousRuntimeRecovering

    init(
        recordTransaction: ExtensionInstallationRecordTransaction,
        runtimeReplacement: any ExtensionInstallationPreviousRuntimeRecovering
    ) {
        self.recordTransaction = recordTransaction
        self.runtimeReplacement = runtimeReplacement
    }

    func settle(_ context: Context) async -> any Error {
        var disposition =
            (context.error as? ExtensionRuntimeTransactionFailure)?
                .rollback.externalStateDisposition
                ?? .rollbackAllowed
        if let rollbackRuntimeActivation = context.rollbackRuntimeActivation {
            disposition = rollbackRuntimeActivation()
                .externalStateDisposition
        }

        let resolution = ExtensionInstallationFailurePolicy.resolve(
            packageOwnership: context.package.ownership,
            disposition: disposition
        )
        var recoveryFailures: [String] = []
        var didRestorePackage = true

        var exactRuntimeRecordOutcome: String?
        switch resolution.record {
        case .leaveOriginal:
            if let failure = context.error as?
                ExtensionInstallationRecordTransaction.CommitFailure,
               let restorationError = failure.restorationError {
                recoveryFailures.append(
                    "persisted metadata state is indeterminate because restoration failed: "
                        + restorationError.localizedDescription
                )
            }
        case .reconcileCandidateWithExactRuntime:
            if let candidate = context.candidateRecord {
                switch recordTransaction.reconcileCandidateWithExactRuntime(
                    candidate,
                    replacing: context.recordSnapshot
                ) {
                case .durable:
                    exactRuntimeRecordOutcome =
                        "candidate metadata were preserved durably"
                case .volatileCandidatePublished(let failure):
                    exactRuntimeRecordOutcome =
                        "candidate metadata could not be persisted; a volatile live-catalog record was published to match the surviving exact runtime"
                    recoveryFailures.append(failure.localizedDescription)
                }
            } else {
                recoveryFailures.append(
                    "the surviving exact runtime has no candidate installation record"
                )
            }
        }

        switch resolution.package {
        case .rollback:
            do {
                try context.package.rollback()
            } catch {
                didRestorePackage = false
                recoveryFailures.append(
                    "package rollback failed: " + error.localizedDescription
                )
            }
        case .preserve:
            context.package.commit()
        case .none:
            break
        }

        if resolution.runtime == .recoverPrevious,
           didRestorePackage,
           let previousRuntime = context.previousRuntime {
            do {
                try await runtimeReplacement.recover(
                    previousRuntime,
                    mutationLease: context.mutationLease
                )
            } catch {
                recoveryFailures.append(
                    "previous runtime recovery failed: "
                        + error.localizedDescription
                )
            }
        }

        if disposition == .rollbackAllowed, recoveryFailures.isEmpty {
            return context.error
        }

        let dispositionDescription: String
        switch disposition {
        case .rollbackAllowed:
            dispositionDescription =
                "Installation failed and recovery was incomplete"
        case .preserveForExactRuntime:
            dispositionDescription =
                "Installation failed after the candidate WebKit runtime remained authoritative; "
                + (exactRuntimeRecordOutcome
                    ?? "candidate record reconciliation was unavailable")
        case .preserveForReplacement:
            dispositionDescription =
                "Installation failed after a replacement runtime acquired authority; this transaction did not publish over that live authority"
        case .preserveForActiveBinding:
            dispositionDescription =
                "Installation failed while another active profile binding retained authority; this transaction did not publish over that live authority"
        case .preserveForCompetingTransaction:
            dispositionDescription =
                "Installation failed while a competing runtime transaction retained authority; this transaction did not publish over that live authority"
        case .preserveUntilSharedCleanup:
            dispositionDescription =
                "Installation failed before shared runtime cleanup completed; external package state was conservatively preserved"
        }
        return ExtensionError.installationFailed(
            dispositionDescription
                + (recoveryFailures.isEmpty
                    ? ""
                    : ". Recovery issues: "
                        + recoveryFailures.joined(separator: "; "))
                + ". Original error: " + context.error.localizedDescription
        )
    }
}
