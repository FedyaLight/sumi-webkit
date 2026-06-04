import Foundation
import URLPredictor

enum SumiURLNormalizationContext: Equatable {
    case searchBar(queryTemplate: String)
    case startupPage
    case shortcutEditor
    case searchEngineTemplate
}

enum SumiURLNormalization {
    static func normalize(_ input: String, context: SumiURLNormalizationContext) -> String {
        switch context {
        case .searchBar(let queryTemplate):
            return normalizeSearchBarInput(input, queryTemplate: queryTemplate)
        case .startupPage:
            return normalizedStartupURLString(from: input) ?? input.trimmingCharacters(in: .whitespacesAndNewlines)
        case .shortcutEditor:
            return normalizedShortcutURLString(from: input) ?? input.trimmingCharacters(in: .whitespacesAndNewlines)
        case .searchEngineTemplate:
            return normalizedSearchEngineTemplate(input)
        }
    }

    static func normalizedStartupURLString(from input: String) -> String? {
        SumiStartupPageURL.normalizedURLString(from: input)
    }

    static func normalizedShortcutURL(from input: String) -> URL? {
        guard let normalized = normalizedShortcutURLString(from: input) else { return nil }
        return URL(string: normalized)
    }

    static func normalizedShortcutURLString(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let direct = URL(string: trimmed), direct.scheme != nil {
            return trimmed
        }
        let prefixed = "https://\(trimmed)"
        return URL(string: prefixed) != nil ? prefixed : nil
    }

    static func normalizedSearchEngineTemplate(_ template: String) -> String {
        if template.hasPrefix("http://") || template.hasPrefix("https://") {
            return template
        }
        return "https://\(template)"
    }

    private static func normalizeSearchBarInput(_ input: String, queryTemplate: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") ||
            trimmed.hasPrefix("file://") || trimmed.hasPrefix("about:") {
            return trimmed
        }

        if trimmed.lowercased().hasPrefix("sumi:") {
            return trimmed
        }

        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("webkit-extension:") || lowered.hasPrefix("safari-web-extension:") {
            return trimmed
        }

        if let decision = try? Classifier.classify(input: trimmed),
           case .navigate(let url) = decision {
            return url.absoluteString
        }

        if trimmed.contains(".") && !trimmed.contains(" ") {
            return "https://\(trimmed)"
        }

        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        return String(format: queryTemplate, encoded)
    }
}

func normalizeURL(_ input: String, queryTemplate: String) -> String {
    SumiURLNormalization.normalize(input, context: .searchBar(queryTemplate: queryTemplate))
}
