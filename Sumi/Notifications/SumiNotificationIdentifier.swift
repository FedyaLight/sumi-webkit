import Foundation

struct SumiNotificationIdentifier: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = Self.normalized(rawValue)
    }

    static func website(
        profilePartitionId: String,
        tabId: String,
        pageId: String,
        requestId: String
    ) -> SumiNotificationIdentifier {
        SumiNotificationIdentifier(
            rawValue: [
                "sumi-web",
                profilePartitionId,
                tabId,
                pageId,
                requestId,
            ].map(normalizedComponent).joined(separator: "-")
        )
    }

    private static func normalized(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "sumi-notification" : trimmed
    }

    private static func normalizedComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let result = String(scalars)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
            .lowercased()
        return result.isEmpty ? "unknown" : result
    }
}
