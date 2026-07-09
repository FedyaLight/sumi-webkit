import Foundation
import OSLog

/// Public Suffix List matcher backed by the bundled `public_suffix_list.dat`
/// (https://publicsuffix.org), including wildcard (`*.foo`) and exception
/// (`!bar.foo`) rules. Contains both the ICANN and private-domain sections.
public final class SumiPublicSuffixList: Sendable {
    /// The list parsed from the bundled `public_suffix_list.dat`, loaded once.
    public static let bundled = SumiPublicSuffixList()

    private let exactRules: Set<String>
    private let wildcardBases: Set<String>
    private let exceptionRules: Set<String>

    public convenience init() {
        self.init(listText: Self.bundledListText())
    }

    public init(listText: String) {
        var exact: Set<String> = []
        var wildcards: Set<String> = []
        var exceptions: Set<String> = []

        listText.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("//") else { return }

            func insert(_ rule: String) {
                if rule.hasPrefix("!") {
                    exceptions.insert(String(rule.dropFirst()))
                } else if rule.hasPrefix("*.") {
                    wildcards.insert(String(rule.dropFirst(2)))
                } else {
                    exact.insert(rule)
                }
            }

            insert(trimmed)

            // The upstream list spells IDN rules in Unicode; hosts usually
            // arrive punycoded, so index the ASCII form as well.
            if !trimmed.unicodeScalars.allSatisfy({ $0.isASCII }),
               let ascii = SumiPunycode.hostToASCII(
                   trimmed.hasPrefix("!") ? String(trimmed.dropFirst()) : trimmed
               ) {
                insert(trimmed.hasPrefix("!") ? "!" + ascii : ascii)
            }
        }

        exactRules = exact
        wildcardBases = wildcards
        exceptionRules = exceptions
    }

    /// Returns the eTLD+1 for a host, or nil when the host has no listed
    /// public suffix, is itself a public suffix, or is not a dotted DNS name.
    public func registrableDomain(forHost host: String?) -> String? {
        guard let host, !host.isEmpty else { return nil }

        let labels = host.components(separatedBy: ".")
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }) else { return nil }

        guard let suffixStart = publicSuffixStart(labels: labels) else { return nil }
        guard suffixStart >= 1 else { return nil }

        return labels[(suffixStart - 1)...].joined(separator: ".")
    }

    public func isPublicSuffix(_ host: String) -> Bool {
        let labels = host.components(separatedBy: ".")
        guard !labels.isEmpty, labels.allSatisfy({ !$0.isEmpty }) else { return false }
        return publicSuffixStart(labels: labels) == 0
    }

    /// Index of the first label of the longest matching public suffix,
    /// or nil when no rule matches. Exception rules prevail over others.
    private func publicSuffixStart(labels: [String]) -> Int? {
        for start in 0..<labels.count {
            let candidate = labels[start...].joined(separator: ".")

            if exceptionRules.contains(candidate) {
                return start + 1
            }
            if exactRules.contains(candidate) {
                return start
            }
            // A wildcard rule "*.base" matches candidates one label longer
            // than the base.
            if labels.count - start >= 2 {
                let base = labels[(start + 1)...].joined(separator: ".")
                if wildcardBases.contains(base) {
                    return start
                }
            }
        }

        return nil
    }

    private static func bundledListText() -> String {
        let logger = Logger(subsystem: "com.sumi.browser", category: "PublicSuffixList")
        let bundles = [Bundle.module, Bundle(for: SumiPublicSuffixList.self), Bundle.main]
        for bundle in bundles {
            guard let url = bundle.url(forResource: "public_suffix_list", withExtension: "dat") else {
                continue
            }
            do {
                return try String(contentsOf: url, encoding: .utf8)
            } catch {
                logger.debug(
                    "Failed to read bundled Public Suffix List: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        logger.debug(
            "public_suffix_list.dat missing from bundle; registrable-domain resolution disabled"
        )
        return ""
    }
}
