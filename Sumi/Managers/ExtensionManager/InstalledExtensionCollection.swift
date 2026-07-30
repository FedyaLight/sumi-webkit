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
    private let catalogIndex = InstalledExtensionCatalogIndex()

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

    func record(for id: String) -> InstalledExtension? {
        catalogIndex.record(for: id)
    }

    var enabledRecords: [InstalledExtension] { catalogIndex.enabledRecords }
    var enabledContentScriptRecords: [InstalledExtension] {
        catalogIndex.enabledContentScriptRecords
    }

    var hasEnabledRecords: Bool {
        catalogIndex.enabledRecords.isEmpty == false
    }

    func recordDurability(for id: String) -> RecordDurability? {
        durabilityByID[id]
    }

    func markRecordDurable(_ id: String) {
        guard record(for: id) != nil else { return }
        durabilityByID[id] = .durable
    }

    func upsert(
        _ record: InstalledExtension,
        durability: RecordDurability = .durable
    ) {
        let advancesRevision: Bool
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            advancesRevision = InstalledExtensionCatalogIdentity.matches(
                records[index],
                record
            ) == false
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
        rebuildIndexes()
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
        rebuildIndexes()
        notifyRecordChanges()
    }

    func remove(id: String) {
        let originalCount = records.count
        records.removeAll { $0.id == id }
        guard records.count != originalCount else { return }
        durabilityByID.removeValue(forKey: id)
        revisions.bump(id)
        rebuildIndexes()
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
                if InstalledExtensionCatalogIdentity.matches(
                    previous,
                    replacement
                ) == false {
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
        sortRecords()
        rebuildIndexes()
        notifyRecordChanges()
    }

    func sort() {
        sortRecords()
        rebuildIndexes()
        notifyRecordChanges()
    }

    private func sortRecords() {
        records.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func rebuildIndexes() {
        catalogIndex.rebuild(from: records)
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
