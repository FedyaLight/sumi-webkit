import Foundation

/// One visit recovered from another browser, ready to be written.
struct HistoryImportedVisit: Sendable {
    var url: URL
    var title: String
    var visitedAt: Date
}

/// Namespace for the exact compensation receipt returned by imported-history
/// transactions.
enum HistoryImportedVisitWriter {
    struct Receipt: Codable, Equatable, Sendable {
        var insertedVisitIDs: [UUID] = []
        var createdEntryIDs: [UUID] = []
        var adjustedEntries: [UUID: PriorEntryState] = [:]

        struct PriorEntryState: Codable, Equatable, Sendable {
            var numberOfTotalVisits: Int
            var lastVisit: Date
        }

        mutating func merge(_ other: Receipt) {
            insertedVisitIDs.append(contentsOf: other.insertedVisitIDs)
            createdEntryIDs.append(contentsOf: other.createdEntryIDs)
            adjustedEntries.merge(other.adjustedEntries) { first, _ in first }
        }
    }
}
