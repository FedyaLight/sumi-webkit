import Foundation

enum SumiPermissionDisplayDomainFormatter {
    static func lowercasedDisplayDomain(
        _ value: String,
        fallback: String = "Unknown Origin"
    ) -> String {
        normalizedDisplayDomain(value, fallback: fallback, lowercased: true)
    }

    static func trimmedDisplayDomain(
        _ value: String,
        fallback: String = "Current site"
    ) -> String {
        normalizedDisplayDomain(value, fallback: fallback, lowercased: false)
    }

    private static func normalizedDisplayDomain(
        _ value: String,
        fallback: String,
        lowercased: Bool
    ) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return lowercased ? trimmed.lowercased() : trimmed
    }
}
