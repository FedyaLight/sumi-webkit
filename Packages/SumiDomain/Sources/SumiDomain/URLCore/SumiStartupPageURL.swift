import Foundation

public enum SumiStartupPageURL {
    public static let defaultURLString = SumiSurface.emptyTabURL.absoluteString
    public static let allowedSchemes: Set<String> = ["http", "https", "file", "about", "sumi"]

    public static func normalizedURLString(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased() {
            guard allowedSchemes.contains(scheme) else { return nil }
            if ["http", "https"].contains(scheme) {
                guard hasHTTPHost(url) else {
                    return nil
                }
            }
            return trimmed
        }

        guard isBareDomain(trimmed) else { return nil }
        let normalized = "https://\(trimmed)"
        guard let url = URL(string: normalized),
              hasHTTPHost(url)
        else {
            return nil
        }
        return normalized
    }

    public static func validatedURL(from input: String) -> URL? {
        normalizedURLString(from: input).flatMap(URL.init(string:))
    }

    public static func runtimeURL(from input: String) -> URL {
        validatedURL(from: input) ?? SumiSurface.emptyTabURL
    }

    public static func validationMessage(for input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Sumi will open a blank page until you enter a URL."
        }
        return normalizedURLString(from: trimmed) == nil
            ? "Enter a URL such as https://example.com or example.com."
            : nil
    }

    private static func isBareDomain(_ value: String) -> Bool {
        guard !value.contains(where: \.isWhitespace),
              value.contains("."),
              !value.hasPrefix("."),
              !value.hasSuffix(".")
        else {
            return false
        }

        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }) else {
            return false
        }
        return labels.last?.contains(where: { $0.isLetter || $0.isNumber }) == true
    }

    private static func hasHTTPHost(_ url: URL) -> Bool {
        url.host(percentEncoded: false)?.isEmpty == false || url.host?.isEmpty == false
    }
}
