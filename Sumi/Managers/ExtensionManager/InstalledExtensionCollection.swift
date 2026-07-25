import Combine
import Foundation

/// The single mutable store for the installed-extension catalog.
@available(macOS 15.5, *)
@MainActor
final class InstalledExtensionCollection: ObservableObject {
    enum RecordDurability: Equatable {
        case durable
        case volatileExactRuntime
    }

    @Published private(set) var records: [InstalledExtension] = []
    private var didChangeRecords: (() -> Void)?
    private let revisions = InstalledExtensionRecordRevisions()
    private var durabilityByID: [String: RecordDurability] = [:]

    func connectRecordChanges(_ handler: @escaping () -> Void) {
        precondition(
            didChangeRecords == nil && records.isEmpty,
            "Installed-extension record changes must be connected exactly once before publication"
        )
        didChangeRecords = handler
    }

    func recordRevision(for id: String) -> UInt64 {
        revisions.revision(for: id)
    }

    func recordDurability(for id: String) -> RecordDurability? {
        durabilityByID[id]
    }

    func markRecordDurable(_ id: String) {
        guard records.contains(where: { $0.id == id }) else { return }
        durabilityByID[id] = .durable
    }

    func upsert(
        _ record: InstalledExtension,
        durability: RecordDurability = .durable
    ) {
        let advancesRevision: Bool
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            advancesRevision = Self.sameCatalogRecord(records[index], record) == false
            records[index] = record
        } else {
            advancesRevision = true
            records.append(record)
        }
        durabilityByID[record.id] = durability
        if advancesRevision {
            revisions.bump(record.id)
        }
        sortRecords()
        notifyRecordChanges()
    }

    func replace(at index: Int, with record: InstalledExtension) {
        guard records.indices.contains(index) else { return }
        let previousID = records[index].id
        records[index] = record
        durabilityByID[record.id] = .durable
        revisions.bump(previousID)
        if record.id != previousID {
            durabilityByID.removeValue(forKey: previousID)
            revisions.bump(record.id)
        }
        notifyRecordChanges()
    }

    func remove(id: String) {
        let originalCount = records.count
        records.removeAll { $0.id == id }
        guard records.count != originalCount else { return }
        durabilityByID.removeValue(forKey: id)
        revisions.bump(id)
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
                revisions.bump(id)
            case (.some(let previous), .some(let replacement)):
                if Self.sameCatalogRecord(previous, replacement) == false {
                    revisions.bump(id)
                }
            case (nil, nil):
                break
            }
        }
        self.records = records
        durabilityByID = Dictionary(
            records.map { ($0.id, .durable) },
            uniquingKeysWith: { _, current in current }
        )
        notifyRecordChanges()
    }

    func sort() {
        sortRecords()
        notifyRecordChanges()
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
            && lhs.packagePath == rhs.packagePath
            && lhs.sourceKind == rhs.sourceKind
            && lhs.incognitoMode == rhs.incognitoMode
            && lhs.sourcePathFingerprint == rhs.sourcePathFingerprint
            && lhs.manifestRootFingerprint == rhs.manifestRootFingerprint
            && lhs.sourceBundlePath == rhs.sourceBundlePath
            && lhs.safariRuntimeIdentity == rhs.safariRuntimeIdentity
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
