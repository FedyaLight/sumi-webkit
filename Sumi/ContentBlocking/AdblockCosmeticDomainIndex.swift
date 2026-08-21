import Foundation

/// Domain-scoped cosmetic selectors for one blocker generation.
///
/// Safari content blockers apply every `css-display-none` selector to every
/// document, so thousands of domain-scoped rules tax DOM-heavy pages that
/// they were never written for. This index serves the same rules through the
/// advanced blocking pipeline, where only selectors whose `if-domain`
/// pattern matches the top document host are returned.
///
/// Matching mirrors WebKit's content-blocker semantics: `*example.com`
/// matches `example.com` and its subdomains, while a pattern without `*`
/// must equal the host exactly.
struct AdblockCosmeticDomainIndex: Sendable {
    struct Entry: Codable, Equatable, Sendable {
        let selector: String
        let domains: [String]

        enum CodingKeys: String, CodingKey {
            case selector = "s"
            case domains = "d"
        }
    }

    private struct IndexedSelector: Sendable {
        let order: Int
        let selector: String
    }

    private let exactMatches: [String: [IndexedSelector]]
    private let wildcardMatches: [String: [IndexedSelector]]

    static let artifactRelativePath = ".webext/cosmetic-domains.json"

    init() {
        exactMatches = [:]
        wildcardMatches = [:]
    }

    init(data: Data) throws {
        try self.init(entries: JSONDecoder().decode([Entry].self, from: data))
    }

    init(entries: [Entry]) throws {
        var exactMatches = [String: [IndexedSelector]]()
        var wildcardMatches = [String: [IndexedSelector]]()
        for (order, entry) in entries.enumerated() {
            guard entry.selector.isEmpty == false,
                  entry.domains.isEmpty == false
            else {
                throw AdblockCosmeticDomainIndexError.invalidPayload
            }
            let indexed = IndexedSelector(order: order, selector: entry.selector)
            for domain in entry.domains {
                let normalized = domain.lowercased()
                guard normalized.isEmpty == false else {
                    throw AdblockCosmeticDomainIndexError.invalidPayload
                }
                if normalized.hasPrefix("*") {
                    let suffix = String(normalized.dropFirst())
                    guard suffix.isEmpty == false else {
                        throw AdblockCosmeticDomainIndexError.invalidPayload
                    }
                    wildcardMatches[suffix, default: []].append(indexed)
                } else {
                    exactMatches[normalized, default: []].append(indexed)
                }
            }
        }
        self.exactMatches = exactMatches
        self.wildcardMatches = wildcardMatches
    }

    var isEmpty: Bool { exactMatches.isEmpty && wildcardMatches.isEmpty }

    /// Selectors whose `if-domain` patterns match `host`, in rule order.
    func selectors(forHost host: String?) -> [String] {
        guard let host, isEmpty == false else { return [] }
        let normalizedHost = host.lowercased()
        guard normalizedHost.isEmpty == false else { return [] }

        var matches = exactMatches[normalizedHost] ?? []
        let labels = normalizedHost.split(separator: ".", omittingEmptySubsequences: false)
        for index in labels.indices {
            let suffix = labels[index...].joined(separator: ".")
            matches.append(contentsOf: wildcardMatches[suffix] ?? [])
        }
        matches.sort { $0.order < $1.order }

        var seen = Set<Int>()
        return matches.compactMap { match in
            seen.insert(match.order).inserted ? match.selector : nil
        }
    }

    /// Splits a Safari content-blocker rule array into network rules and
    /// `"s"`/`"d"` payloads for this index. A rule is portable when it hides
    /// via `css-display-none`, is scoped by `if-domain`, and carries no
    /// `unless-domain` escape; everything else stays in the WebKit list.
    static func splitRules(
        _ rules: [[String: Any]]
    ) -> (network: [[String: Any]], cosmetics: [Entry]) {
        var network = [[String: Any]]()
        var cosmetics = [Entry]()
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
            cosmetics.append(Entry(selector: selector, domains: domains))
        }
        return (network, cosmetics)
    }

    static func artifactData(for entries: [Entry]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(entries)
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
