import Foundation

struct SumiContentBlockerRulesIdentifier: Equatable, Codable, Sendable {
    let name: String
    let tdsEtag: String
    let tempListId: String
    let allowListId: String
    let unprotectedSitesHash: String

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
