import Foundation
import OSLog

@MainActor
final class SafariContentBlockerPreparedInventoryStore {
    private static let documentKey =
        "safari-content-blockers.prepared-inventory"
    private static let log = Logger.sumi(category: "SafariContentBlocker")

    private let database: SumiDatabase?
    private var inventory: SafariContentBlockerPreparedInventory

    init(database: SumiDatabase?) {
        self.database = database
        inventory = Self.load(from: database)
    }

    func preparedBlockers(
        matching records: [InstalledSafariContentBlockerRecord]
    ) -> [SafariContentBlockerPreparedInventory.Blocker]? {
        inventory.preparedBlockers(matching: records)
    }

    func sourceStampsMatch(
        _ stamps: [String: String],
        records: [InstalledSafariContentBlockerRecord]
    ) -> Bool {
        let byID = Dictionary(
            inventory.blockers.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        return records.allSatisfy { record in
            guard let prepared = byID[record.id],
                  prepared.resourceFingerprint == record.resourceFingerprint
            else { return false }
            return stamps[record.id] == prepared.resourceStamp
        }
    }

    func upsert(
        record: InstalledSafariContentBlockerRecord,
        locatedRules: SafariContentBlockerLocatedRules
    ) {
        replace(
            with: [
                SafariContentBlockerPreparedInventory.Blocker(
                    record: record,
                    locatedRules: locatedRules
                ),
            ],
            removing: []
        )
    }

    func remove(blockerID: String) {
        replace(with: [], removing: [blockerID])
    }

    func replace(
        with replacements: [SafariContentBlockerPreparedInventory.Blocker],
        removing removedIDs: Set<String>
    ) {
        var byID = Dictionary(
            inventory.blockers.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        removedIDs.forEach { byID.removeValue(forKey: $0) }
        replacements.forEach { byID[$0.id] = $0 }
        inventory = SafariContentBlockerPreparedInventory(
            blockers: Array(byID.values)
        )
        persist()
    }

    private func persist() {
        guard let database else { return }
        do {
            try database.transaction {
                try $0.documents.save(
                    inventory,
                    forKey: Self.documentKey
                )
            }
        } catch {
            Self.log.error(
                "Failed to persist Safari content blocker inventory: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private static func load(
        from database: SumiDatabase?
    ) -> SafariContentBlockerPreparedInventory {
        guard let database else {
            return SafariContentBlockerPreparedInventory()
        }
        do {
            return try database.read {
                try $0.documents.value(
                    SafariContentBlockerPreparedInventory.self,
                    forKey: documentKey
                )
            } ?? SafariContentBlockerPreparedInventory()
        } catch {
            log.error(
                "Failed to restore Safari content blocker inventory: \(error.localizedDescription, privacy: .public)"
            )
            return SafariContentBlockerPreparedInventory()
        }
    }
}
