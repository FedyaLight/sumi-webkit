import Combine
import Foundation

/// The single mutable store for the installed-extension catalog.
@available(macOS 15.5, *)
@MainActor
final class InstalledExtensionCollection: ObservableObject {
    @Published private(set) var records: [InstalledExtension] = []
    private var didChangeRecords: (() -> Void)?
    // Tombstoned per-extension mutation revisions: entries survive removal so
    // remove/re-add cannot revive authority captured against an older record.
    private var recordRevisionsByID: [String: UInt64] = [:]

    func connectRecordChanges(_ handler: @escaping () -> Void) {
        precondition(
            didChangeRecords == nil && records.isEmpty,
            "Installed-extension record changes must be connected exactly once before publication"
        )
        didChangeRecords = handler
    }

    /// Monotonic revision of one extension's catalog record. Any semantic
    /// mutation of that record (install, replace, enable/disable, removal)
    /// advances it; unrelated extensions keep their revisions.
    func recordRevision(for id: String) -> UInt64 {
        recordRevisionsByID[id] ?? 0
    }

    func upsert(_ record: InstalledExtension) {
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.append(record)
        }
        bumpRecordRevision(record.id)
        sortRecords()
        notifyRecordChanges()
    }

    func replace(at index: Int, with record: InstalledExtension) {
        guard records.indices.contains(index) else { return }
        let previousID = records[index].id
        records[index] = record
        bumpRecordRevision(previousID)
        if record.id != previousID {
            bumpRecordRevision(record.id)
        }
        notifyRecordChanges()
    }

    func remove(id: String) {
        let originalCount = records.count
        records.removeAll { $0.id == id }
        guard records.count != originalCount else { return }
        bumpRecordRevision(id)
        notifyRecordChanges()
    }

    func setAll(_ records: [InstalledExtension]) {
        let previousByID = Dictionary(
            self.records.map { ($0.id, $0) },
            uniquingKeysWith: { _, current in current }
        )
        let replacementByID = Dictionary(
            records.map { ($0.id, $0) },
            uniquingKeysWith: { _, current in current }
        )
        for id in Set(previousByID.keys).union(replacementByID.keys) {
            switch (previousByID[id], replacementByID[id]) {
            case (nil, .some), (.some, nil):
                bumpRecordRevision(id)
            case (.some(let previous), .some(let replacement)):
                if Self.sameCatalogRecord(previous, replacement) == false {
                    bumpRecordRevision(id)
                }
            case (nil, nil):
                break
            }
        }
        self.records = records
        notifyRecordChanges()
    }

    func sort() {
        sortRecords()
        notifyRecordChanges()
    }

    func nativeMessagingLoadSource(
        for extensionID: String?
    ) -> SafariAppExtensionRuntimeLoadSource? {
        guard let extensionID,
              let installed = records.first(where: { $0.id == extensionID })
        else {
            return nil
        }
        return installed.sourceKind == .safariAppExtension
            ? .originalAppexBundle
            : .copiedPackage
    }

    private func bumpRecordRevision(_ id: String) {
        let current = recordRevisionsByID[id] ?? 0
        precondition(current < UInt64.max, "Installed-extension record revision exhausted")
        recordRevisionsByID[id] = current + 1
    }

    /// Value identity used only to keep idempotent catalog reloads from
    /// invalidating in-flight exact authority. The fingerprints cover package
    /// content; the remaining fields cover install/enable state.
    private static func sameCatalogRecord(
        _ lhs: InstalledExtension,
        _ rhs: InstalledExtension
    ) -> Bool {
        lhs.id == rhs.id
            && lhs.version == rhs.version
            && lhs.manifestVersion == rhs.manifestVersion
            && lhs.isEnabled == rhs.isEnabled
            && lhs.installDate == rhs.installDate
            && lhs.lastUpdateDate == rhs.lastUpdateDate
            && lhs.packagePath == rhs.packagePath
            && lhs.sourceKind == rhs.sourceKind
            && lhs.incognitoMode == rhs.incognitoMode
            && lhs.sourcePathFingerprint == rhs.sourcePathFingerprint
            && lhs.manifestRootFingerprint == rhs.manifestRootFingerprint
            && lhs.sourceBundlePath == rhs.sourceBundlePath
    }

    private func sortRecords() {
        records.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func notifyRecordChanges() {
        guard let didChangeRecords else {
            preconditionFailure(
                "Installed-extension records cannot mutate before change handling is connected"
            )
        }
        didChangeRecords()
    }
}
