import Foundation

/// Retries persistence for a candidate record that had to remain live because
/// its exact WebKit runtime could not be rolled back. Lifecycle work must not
/// read older durable metadata until this reconciliation succeeds.
@available(macOS 15.5, *)
@MainActor
final class ExtensionVolatileInstallationRecordReconciler {
    private let persistence: any ExtensionInstallationRecordPersisting
    private let installedRecords: InstalledExtensionCollection

    init(
        persistence: any ExtensionInstallationRecordPersisting,
        installedRecords: InstalledExtensionCollection
    ) {
        self.persistence = persistence
        self.installedRecords = installedRecords
    }

    func reconcile(_ extensionID: String) throws {
        guard installedRecords.recordDurability(for: extensionID)
                == .volatileExactRuntime,
              let record = installedRecords.records.first(where: {
                  $0.id == extensionID
              }) else {
            return
        }
        try persistence.persist(record: record)
        installedRecords.markRecordDurable(extensionID)
    }

    func reconcileAll() throws {
        let volatileIDs = installedRecords.records.compactMap { record in
            installedRecords.recordDurability(for: record.id)
                == .volatileExactRuntime ? record.id : nil
        }
        for extensionID in volatileIDs {
            try reconcile(extensionID)
        }
    }
}
