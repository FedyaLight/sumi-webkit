import Foundation

/// Substitutes a user's search text into a search engine template.
///
/// Templates place their query token either inside the query string
/// (`https://github.com/search?q={query}`) or inside the path
/// (`https://open.spotify.com/search/{query}`). The two positions need
/// different encodings: `+` only means "space" under
/// `application/x-www-form-urlencoded`, which applies to query strings, so a
/// path token has to keep `%20`.
public enum SumiSearchQueryEncoding {
    public enum TokenPosition: Equatable, Sendable {
        /// Token sits after a `?`. Spaces encode as `+`, matching what every
        /// mainstream browser sends and what `URLSearchParams` decodes.
        case query
        /// Token sits in the path (or a query-less fragment). Spaces stay
        /// `%20`, which decodes to a space in every position.
        case path
    }

    /// RFC 3986 unreserved set. Everything else is percent-encoded so that
    /// `&`, `=`, `+`, `/` and `#` inside the user's text can never escape the
    /// value they belong to.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    public static func encode(_ query: String, for position: TokenPosition) -> String {
        // Percent-encoding against the unreserved set leaves no literal `+`
        // behind (a typed `+` becomes `%2B`), so promoting `%20` to `+` below
        // stays unambiguous.
        let percentEncoded = query.addingPercentEncoding(withAllowedCharacters: unreserved) ?? query
        switch position {
        case .query:
            return percentEncoded.replacingOccurrences(of: "%20", with: "+")
        case .path:
            return percentEncoded
        }
    }

    /// Replaces every occurrence of `token` in `template` with `query`,
    /// encoded for the position each occurrence sits in. Returns the template
    /// unchanged when it carries no token.
    public static func substitute(
        _ query: String,
        into template: String,
        token: String
    ) -> String {
        guard !token.isEmpty, template.contains(token) else { return template }

        var result = ""
        var remainder = Substring(template)
        // Tracks whether a `?` has been seen so far, which is what decides
        // query vs. path for the next occurrence.
        var sawQuestionMark = false

        while let range = remainder.range(of: token) {
            let prefix = remainder[remainder.startIndex..<range.lowerBound]
            if prefix.contains("?") {
                sawQuestionMark = true
            }
            result += prefix
            result += encode(query, for: sawQuestionMark ? .query : .path)
            remainder = remainder[range.upperBound...]
        }

        result += remainder
        return result
    }
}
