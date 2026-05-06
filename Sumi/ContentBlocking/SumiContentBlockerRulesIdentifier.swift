import Foundation

struct SumiContentBlockerRulesIdentifier: Codable, Hashable, Sendable {
    let name: String
    let tdsEtag: String
    let tempListId: String
    let allowListId: String
    let unprotectedSitesHash: String

    struct Difference: OptionSet, CustomDebugStringConvertible, Hashable, Sendable {
        let rawValue: Int

        static let tdsEtag = Difference(rawValue: 1 << 0)
        static let tempListId = Difference(rawValue: 1 << 1)
        static let allowListId = Difference(rawValue: 1 << 2)
        static let unprotectedSites = Difference(rawValue: 1 << 3)

        static let all: Difference = [.tdsEtag, .tempListId, .allowListId, .unprotectedSites]

        var debugDescription: String {
            if self == .all {
                return "all"
            }

            var parts: [String] = []
            if contains(.tdsEtag) {
                parts.append(".tdsEtag")
            }
            if contains(.tempListId) {
                parts.append(".tempListId")
            }
            if contains(.allowListId) {
                parts.append(".allowListId")
            }
            if contains(.unprotectedSites) {
                parts.append(".unprotectedSites")
            }
            return "[\(parts.joined(separator: ", "))]"
        }
    }

    var stringValue: String {
        name + tdsEtag + tempListId + allowListId + unprotectedSitesHash
    }

    init(
        name: String,
        tdsEtag: String,
        tempListId: String?,
        allowListId: String?,
        unprotectedSitesHash: String?
    ) {
        self.name = Self.normalize(identifier: name)
        self.tdsEtag = Self.normalize(identifier: tdsEtag)
        self.tempListId = Self.normalize(identifier: tempListId)
        self.allowListId = Self.normalize(identifier: allowListId)
        self.unprotectedSitesHash = Self.normalize(identifier: unprotectedSitesHash)
    }

    func compare(with identifier: SumiContentBlockerRulesIdentifier) -> Difference {
        var difference = Difference()
        if tdsEtag != identifier.tdsEtag {
            difference.insert(.tdsEtag)
        }
        if tempListId != identifier.tempListId {
            difference.insert(.tempListId)
        }
        if allowListId != identifier.allowListId {
            difference.insert(.allowListId)
        }
        if unprotectedSitesHash != identifier.unprotectedSitesHash {
            difference.insert(.unprotectedSites)
        }
        return difference
    }

    static func == (lhs: SumiContentBlockerRulesIdentifier, rhs: SumiContentBlockerRulesIdentifier) -> Bool {
        lhs.compare(with: rhs).isEmpty
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(tdsEtag)
        hasher.combine(tempListId)
        hasher.combine(allowListId)
        hasher.combine(unprotectedSitesHash)
    }

    private static func normalize(identifier: String?) -> String {
        guard var identifier else {
            return "\"\""
        }

        if !identifier.hasSuffix("\"") {
            identifier += "\""
        }

        if !identifier.hasPrefix("\"") || identifier.count == 1 {
            identifier = "\"" + identifier
        }

        return identifier
    }
}
