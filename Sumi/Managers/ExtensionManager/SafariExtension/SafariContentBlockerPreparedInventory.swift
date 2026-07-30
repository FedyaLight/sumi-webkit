import Foundation

struct SafariContentBlockerPreparedInventory: Codable, Equatable, Sendable {
    static let schemaVersion = 2

    struct RuleList: Codable, Equatable, Sendable {
        let name: String
        let storeIdentifier: String
        let contentHash: String

        init(_ definition: SumiContentRuleListDefinition) {
            name = definition.name
            storeIdentifier = definition.webKitStoreIdentifier
            contentHash = definition.contentHash
        }

        var definition: SumiContentRuleListDefinition {
            SumiContentRuleListDefinition(
                name: name,
                encodedContentRuleList: "",
                storeIdentifierOverride: storeIdentifier,
                contentHashOverride: contentHash
            )
        }
    }

    struct Blocker: Codable, Equatable, Sendable {
        let id: String
        let resourceFingerprint: String
        let resourceStamp: String
        let ruleLists: [RuleList]

        init(
            record: InstalledSafariContentBlockerRecord,
            locatedRules: SafariContentBlockerLocatedRules
        ) {
            id = record.id
            resourceFingerprint = locatedRules.resourceFingerprint
            resourceStamp = locatedRules.resourceStamp
            ruleLists = locatedRules.definitions.map(RuleList.init)
        }

        func matches(_ record: InstalledSafariContentBlockerRecord) -> Bool {
            id == record.id
                && resourceFingerprint == record.resourceFingerprint
                && ruleLists.isEmpty == false
        }
    }

    let version: Int
    var blockers: [Blocker]

    init(blockers: [Blocker] = []) {
        version = Self.schemaVersion
        self.blockers = blockers.sorted { $0.id < $1.id }
    }

    func preparedBlockers(
        matching records: [InstalledSafariContentBlockerRecord]
    ) -> [Blocker]? {
        guard version == Self.schemaVersion else { return nil }
        let byID = Dictionary(
            blockers.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let matching = records.compactMap { record in
            byID[record.id].flatMap { $0.matches(record) ? $0 : nil }
        }
        return matching.count == records.count ? matching : nil
    }
}
