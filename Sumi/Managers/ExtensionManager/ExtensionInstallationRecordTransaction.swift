import Foundation

@available(macOS 15.5, *)
@MainActor
protocol ExtensionInstallationRecordPersisting: AnyObject {
    func persist(record: InstalledExtension) throws
    func restore(
        originalRecord: InstalledExtension?,
        extensionID: String
    ) throws
}

/// Commits one candidate to durable metadata before publishing it to the live
/// catalog. Exact-runtime reconciliation is explicit because a WebKit context
/// that could not be retired must remain paired with its candidate record even
/// when persistence is unavailable.
@available(macOS 15.5, *)
@MainActor
final class ExtensionInstallationRecordTransaction {
    struct Snapshot {
        let extensionID: String
        let originalRecord: InstalledExtension?
    }

    struct CommitFailure: LocalizedError {
        let persistenceError: any Error
        let restorationError: (any Error)?

        var errorDescription: String? {
            var description =
                "Candidate metadata persistence failed: "
                + persistenceError.localizedDescription
            if let restorationError {
                description +=
                    ". Persisted-state restoration also failed: "
                    + restorationError.localizedDescription
            }
            return description
        }
    }

    enum ExactRuntimeReconciliation {
        case durable
        case volatileCandidatePublished(CommitFailure)
    }

    private let persistence: any ExtensionInstallationRecordPersisting
    private let installedRecords: InstalledExtensionCollection

    init(
        persistence: any ExtensionInstallationRecordPersisting,
        installedRecords: InstalledExtensionCollection
    ) {
        self.persistence = persistence
        self.installedRecords = installedRecords
    }

    func commitCandidate(
        _ candidate: InstalledExtension,
        replacing snapshot: Snapshot
    ) throws {
        do {
            try persistence.persist(record: candidate)
        } catch {
            throw compensatePersistenceFailure(error, snapshot: snapshot)
        }
        installedRecords.upsert(candidate)
    }

    func reconcileCandidateWithExactRuntime(
        _ candidate: InstalledExtension,
        replacing snapshot: Snapshot
    ) -> ExactRuntimeReconciliation {
        do {
            try commitCandidate(candidate, replacing: snapshot)
            return .durable
        } catch let failure as CommitFailure {
            // The exact WebKit runtime and its package are already
            // authoritative. Publishing the candidate keeps permission/action
            // routing coherent for this process, but the typed outcome makes
            // the lack of durability impossible to misreport.
            installedRecords.upsert(
                candidate,
                durability: .volatileExactRuntime
            )
            return .volatileCandidatePublished(failure)
        } catch {
            let failure = CommitFailure(
                persistenceError: error,
                restorationError: nil
            )
            installedRecords.upsert(
                candidate,
                durability: .volatileExactRuntime
            )
            return .volatileCandidatePublished(failure)
        }
    }

    private func compensatePersistenceFailure(
        _ persistenceError: any Error,
        snapshot: Snapshot
    ) -> CommitFailure {
        do {
            try persistence.restore(
                originalRecord: snapshot.originalRecord,
                extensionID: snapshot.extensionID
            )
            return CommitFailure(
                persistenceError: persistenceError,
                restorationError: nil
            )
        } catch {
            return CommitFailure(
                persistenceError: persistenceError,
                restorationError: error
            )
        }
    }
}
