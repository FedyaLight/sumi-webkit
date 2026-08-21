import Foundation

/// Domain-scoped cosmetic selectors for one blocker generation.
///
/// Safari content blockers apply every `css-display-none` selector to every
/// document, so thousands of domain-scoped rules tax DOM-heavy pages that
/// they were never written for. This index serves the same rules through the
/// advanced blocking pipeline, where only selectors whose `if-domain`
/// pattern matches the current document host are returned.
///
/// Matching mirrors WebKit's content-blocker semantics: a leading `*`
/// matches any character sequence at the start of the host (so
/// `*example.com` also matches `badexample.com`), and a pattern without one
/// must equal the host exactly.
struct AdblockCosmeticDomainIndex: Sendable {
    private struct Entry: Sendable {
        let selector: String
        let patterns: [String]
    }

    private let entries: [Entry]

    static let artifactRelativePath = ".webext/cosmetic-domains.json"

    init() {
        entries = []
    }

    init(data: Data) throws {
        try self.init(json: try JSONSerialization.jsonObject(with: data))
    }

    init(json: Any) throws {
        guard let decoded = json as? [[String: Any]] else {
            throw AdblockCosmeticDomainIndexError.invalidPayload
        }
        var parsed = [Entry]()
        parsed.reserveCapacity(decoded.count)
        for object in decoded {
            guard let selector = object["s"] as? String,
                  selector.isEmpty == false,
                  let patterns = object["d"] as? [String],
                  patterns.isEmpty == false,
                  patterns.allSatisfy({ $0.isEmpty == false })
            else {
                throw AdblockCosmeticDomainIndexError.invalidPayload
            }
            parsed.append(
                Entry(selector: selector, patterns: patterns.map { $0.lowercased() })
            )
        }
        entries = parsed
    }

    var isEmpty: Bool { entries.isEmpty }

    /// Selectors whose `if-domain` patterns match `host`, in rule order.
    func selectors(forHost host: String?) -> [String] {
        guard let host, isEmpty == false else { return [] }
        let normalizedHost = host.lowercased()
        guard normalizedHost.isEmpty == false else { return [] }
        var matched = [String]()
        for entry in entries
        where entry.patterns.contains(where: { Self.pattern($0, matchesHost: normalizedHost) }) {
            matched.append(entry.selector)
        }
        return matched
    }

    /// Splits a Safari content-blocker rule array into network rules and
    /// `"s"`/`"d"` payloads for this index. A rule is portable when it hides
    /// via `css-display-none`, is scoped by `if-domain`, and carries no
    /// `unless-domain` escape; everything else stays in the WebKit list.
    static func splitRules(
        _ rules: [[String: Any]]
    ) -> (network: [[String: Any]], cosmetics: [[String: Any]]) {
        var network = [[String: Any]]()
        var cosmetics = [[String: Any]]()
        for rule in rules {
            guard let action = rule["action"] as? [String: Any],
                  action["type"] as? String == "css-display-none",
                  let selector = action["selector"] as? String,
                  selector.isEmpty == false,
                  let trigger = rule["trigger"] as? [String: Any],
                  let domains = trigger["if-domain"] as? [String],
                  domains.isEmpty == false,
                  trigger["unless-domain"] == nil
            else {
                network.append(rule)
                continue
            }
            cosmetics.append(["s": selector, "d": domains])
        }
        return (network, cosmetics)
    }

    private static func pattern(
        _ pattern: String,
        matchesHost host: String
    ) -> Bool {
        guard pattern.hasPrefix("*") else { return host == pattern }
        let suffix = String(pattern.dropFirst())
        return host == suffix || host.hasSuffix(suffix)
    }
}

enum AdblockCosmeticDomainIndexError: Error, LocalizedError {
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .invalidPayload:
            "Cosmetic domains payload is not a valid selector/domain array."
        }
    }
}
