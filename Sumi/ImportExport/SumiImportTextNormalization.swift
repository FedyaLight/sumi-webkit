import Foundation

enum SumiImportTextNormalization {
    static func nilIfBlank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func mozillaContainerName(
        name: String?,
        localizationID: String?,
        fallback: String
    ) -> String {
        if let name = nilIfBlank(name) { return name }
        guard var key = nilIfBlank(localizationID) else { return fallback }

        for prefix in ["user-context-", "userContextId", "userContext"] where key.hasPrefix(prefix) {
            key.removeFirst(prefix.count)
            break
        }
        if key.hasSuffix(".label") {
            key.removeLast(".label".count)
        }
        key = key.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        return nilIfBlank(key)?.localizedCapitalized ?? fallback
    }
}
