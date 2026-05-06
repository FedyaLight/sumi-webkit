//
//  UserScriptMatchEngine.swift
//  Sumi
//
//  URL matching engine implementing the MDN Match Pattern specification
//  and Greasemonkey @include/@exclude glob/regex patterns.
//
//  Reference: https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Match_patterns
//

import Foundation

enum UserScriptMatchEngine {

    // MARK: - Public API

    /// Returns true if the given URL matches a script's match/include/exclude rules.
    static func shouldInject(script: SumiInstalledUserScript, into url: URL) -> Bool {
        guard script.isEnabled else { return false }

        let urlString = url.absoluteString

        // Must have at least one @match or @include to run
        let hasMatchPatterns = !script.metadata.matches.isEmpty
        let hasIncludePatterns = !script.metadata.includes.isEmpty
        guard hasMatchPatterns || hasIncludePatterns else { return false }

        // Check @exclude-match first (highest priority exclusion)
        for pattern in script.metadata.excludeMatches {
            if matchPattern(pattern, matches: url) {
                return false
            }
        }

        // Check @exclude (glob/regex exclusion)
        for pattern in script.metadata.excludes {
            if includePattern(pattern, matches: urlString) {
                return false
            }
        }

        // Check @match patterns
        if hasMatchPatterns {
            var matched = false
            for pattern in script.metadata.matches {
                if matchPattern(pattern, matches: url) {
                    matched = true
                    break
                }
            }
            if !matched && !hasIncludePatterns {
                return false
            }
            if matched {
                return true
            }
        }

        // Check @include patterns (glob/regex)
        if hasIncludePatterns {
            for pattern in script.metadata.includes {
                if includePattern(pattern, matches: urlString) {
                    return true
                }
            }
            return false
        }

        return false
    }

    // MARK: - Match Pattern (MDN spec)

    /// Cache for compiled match pattern regexes.
    private static let matchPatternCache = UserScriptRegexCache()

    /// Matches a URL against an MDN match pattern.
    /// Format: <scheme>://<host>/<path>
    /// Special: <all_urls>
    static func matchPattern(_ pattern: String, matches url: URL) -> Bool {
        let trimmed = pattern.trimmingCharacters(in: .whitespaces)

        if trimmed == "<all_urls>" {
            let scheme = url.scheme ?? ""
            return scheme == "http" || scheme == "https"
        }

        guard let regex = compiledMatchPattern(trimmed) else {
            return false
        }

        let urlString = url.absoluteString
        let range = NSRange(location: 0, length: (urlString as NSString).length)
        return regex.firstMatch(in: urlString, options: [], range: range) != nil
    }

    private static func compiledMatchPattern(_ pattern: String) -> NSRegularExpression? {
        if let cached = matchPatternCache[pattern] {
            return cached
        }

        guard let regex = convertMatchPatternToRegex(pattern) else {
            return nil
        }

        matchPatternCache[pattern] = regex
        return regex
    }

    /// Converts an MDN match pattern to a regex.
    /// *://  matches http or https
    /// *.example.com matches example.com and all subdomains
    /// /path/* matches /path/ and all sub-paths
    private static func convertMatchPatternToRegex(_ pattern: String) -> NSRegularExpression? {
        // Split into scheme://host/path
        guard let schemeEnd = pattern.range(of: "://") else {
            return nil
        }

        let scheme = String(pattern[pattern.startIndex..<schemeEnd.lowerBound])
        let rest = String(pattern[schemeEnd.upperBound...])

        // Split host and path
        let slashIndex = rest.firstIndex(of: "/") ?? rest.endIndex
        let host = String(rest[rest.startIndex..<slashIndex])
        let path = slashIndex < rest.endIndex ? String(rest[slashIndex...]) : "/"

        // Build regex
        var regexParts: [String] = ["^"]

        // Scheme
        if scheme == "*" {
            regexParts.append("https?")
        } else {
            regexParts.append(NSRegularExpression.escapedPattern(for: scheme))
        }
        regexParts.append("://")

        // Host
        if host == "*" {
            // Match any host
            regexParts.append("[^/]*")
        } else if host.hasPrefix("*.") {
            // Match domain and all subdomains
            let domain = NSRegularExpression.escapedPattern(for: String(host.dropFirst(2)))
            regexParts.append("([^/]*\\.)?")
            regexParts.append(domain)
        } else {
            regexParts.append(NSRegularExpression.escapedPattern(for: host))
        }

        // Path
        let pathRegex = path
            .split(separator: "*", omittingEmptySubsequences: false)
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: ".*")
        regexParts.append(pathRegex)

        regexParts.append("$")

        let regexString = regexParts.joined()
        return try? NSRegularExpression(pattern: regexString, options: [.caseInsensitive])
    }

    // MARK: - Include/Exclude Pattern (Greasemonkey glob/regex)

    /// Cache for compiled include pattern regexes.
    private static let includePatternCache = UserScriptRegexCache()

    /// Matches a URL string against a Greasemonkey @include/@exclude pattern.
    /// Supports:
    /// - Glob patterns: * and ?
    /// - Regex patterns: /pattern/flags
    static func includePattern(_ pattern: String, matches urlString: String) -> Bool {
        let trimmed = pattern.trimmingCharacters(in: .whitespaces)

        if let cached = includePatternCache[trimmed] {
            let range = NSRange(location: 0, length: (urlString as NSString).length)
            return cached.firstMatch(in: urlString, options: [], range: range) != nil
        }

        let regex: NSRegularExpression?

        if trimmed.hasPrefix("/") && trimmed.count > 1 {
            // Regex pattern: /pattern/ or /pattern/flags
            regex = compileRegexInclude(trimmed)
        } else {
            // Glob pattern
            regex = compileGlobInclude(trimmed)
        }

        if let regex {
            includePatternCache[trimmed] = regex

            let range = NSRange(location: 0, length: (urlString as NSString).length)
            return regex.firstMatch(in: urlString, options: [], range: range) != nil
        }

        return false
    }

    private static func compileRegexInclude(_ pattern: String) -> NSRegularExpression? {
        // Strip leading and trailing slashes, handle flags
        var p = pattern
        p.removeFirst()  // Remove leading /

        var options: NSRegularExpression.Options = []
        if let lastSlash = p.lastIndex(of: "/") {
            let flags = String(p[p.index(after: lastSlash)...])
            p = String(p[p.startIndex..<lastSlash])

            if flags.contains("i") { options.insert(.caseInsensitive) }
            if flags.contains("s") { options.insert(.dotMatchesLineSeparators) }
        }

        return try? NSRegularExpression(pattern: p, options: options)
    }

    private static func compileGlobInclude(_ pattern: String) -> NSRegularExpression? {
        // Convert glob to regex
        var regex = "^"
        for char in pattern {
            switch char {
            case "*":
                regex += ".*"
            case "?":
                regex += "."
            case ".", "(", ")", "[", "]", "{", "}", "+", "^", "$", "|", "\\":
                regex += "\\\(char)"
            default:
                regex += String(char)
            }
        }
        regex += "$"
        return try? NSRegularExpression(pattern: regex, options: [.caseInsensitive])
    }
}

private final class UserScriptRegexCache: @unchecked Sendable {
    // Shared regex instances are immutable after compilation; dictionary access is
    // serialized here so static caches can remain synchronous and process-wide.
    private let lock = NSLock()
    private var cache = [String: NSRegularExpression]()

    subscript(pattern: String) -> NSRegularExpression? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return cache[pattern]
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            cache[pattern] = newValue
        }
    }
}
