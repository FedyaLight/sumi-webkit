import CryptoKit
import Foundation

enum AdblockCompiledRuleGroupKind: String, CaseIterable, Hashable, Sendable {
    case network
    case nativeCosmeticCSS
}

struct AdblockCompilationInput: Equatable, Sendable {
    let sourceIdentifier: String
    let filterTexts: [String]
    let selectedOutputGroups: Set<AdblockCompiledRuleGroupKind>

    init(
        sourceIdentifier: String,
        filterTexts: [String],
        selectedOutputGroups: Set<AdblockCompiledRuleGroupKind>
    ) {
        self.sourceIdentifier = sourceIdentifier
        self.filterTexts = filterTexts
        self.selectedOutputGroups = selectedOutputGroups
    }
}

struct AdblockCompilationDiagnostics: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let rule: String
        let reason: String
    }

    var unsupportedRules: [Entry] = []
    var ignoredRules: [Entry] = []
}

struct AdblockCompiledRuleGroup: Equatable, Sendable {
    let kind: AdblockCompiledRuleGroupKind
    let name: String
    let encodedContentRuleList: String
    let convertedRuleCount: Int
    let contentHash: String

    var definition: SumiContentRuleListDefinition {
        SumiContentRuleListDefinition(
            name: name,
            encodedContentRuleList: encodedContentRuleList
        )
    }
}

struct AdblockCompilationOutput: Equatable, Sendable {
    let sourceIdentifier: String
    let groups: [AdblockCompiledRuleGroup]
    let diagnostics: AdblockCompilationDiagnostics
    let inputRuleCount: Int
    let convertedNetworkRuleCount: Int
    let convertedNativeCosmeticRuleCount: Int
    let unsupportedOrIgnoredRuleCount: Int
    let contentHash: String

    var ruleListDefinitions: [SumiContentRuleListDefinition] {
        groups.map(\.definition)
    }
}

protocol AdblockFilterCompiling: AnyObject, Sendable {
    func compile(_ input: AdblockCompilationInput) async throws -> AdblockCompilationOutput
}

final class AdblockRustCompiler: AdblockFilterCompiling, Sendable {
    func compile(_ input: AdblockCompilationInput) async throws -> AdblockCompilationOutput {
        try await Task.detached(priority: .utility) {
            try Self.compileSynchronously(input)
        }.value
    }

    private static func compileSynchronously(_ input: AdblockCompilationInput) throws -> AdblockCompilationOutput {
        var networkRules = [[String: Any]]()
        var cosmeticRules = [[String: Any]]()
        var diagnostics = AdblockCompilationDiagnostics()
        let normalizedRules = input.filterTexts
            .flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for rule in normalizedRules {
            if rule.hasPrefix("!") || rule.hasPrefix("[") {
                diagnostics.ignoredRules.append(.init(rule: rule, reason: "metadata or comment"))
                continue
            }

            do {
                if let cosmeticRule = try cosmeticContentRule(from: rule) {
                    if input.selectedOutputGroups.contains(.nativeCosmeticCSS) {
                        cosmeticRules.append(cosmeticRule)
                    }
                    continue
                }
            } catch AdblockRustCompilerError.unsupportedRule(_, let reason) {
                diagnostics.unsupportedRules.append(.init(rule: rule, reason: reason))
                continue
            }

            if let networkRule = networkContentRule(from: rule) {
                if input.selectedOutputGroups.contains(.network) {
                    networkRules.append(networkRule)
                }
                continue
            }

            diagnostics.unsupportedRules.append(.init(rule: rule, reason: "unsupported ABP/uBO syntax for native WebKit output"))
        }

        var groups = [AdblockCompiledRuleGroup]()
        if input.selectedOutputGroups.contains(.network) {
            let json = try encodedJSON(networkRules)
            groups.append(
                AdblockCompiledRuleGroup(
                    kind: .network,
                    name: "\(input.sourceIdentifier).network",
                    encodedContentRuleList: json,
                    convertedRuleCount: networkRules.count,
                    contentHash: stableHash(json)
                )
            )
        }
        if input.selectedOutputGroups.contains(.nativeCosmeticCSS) {
            let json = try encodedJSON(cosmeticRules)
            groups.append(
                AdblockCompiledRuleGroup(
                    kind: .nativeCosmeticCSS,
                    name: "\(input.sourceIdentifier).native-css",
                    encodedContentRuleList: json,
                    convertedRuleCount: cosmeticRules.count,
                    contentHash: stableHash(json)
                )
            )
        }

        let contentHash = stableHash(groups.map(\.contentHash).joined(separator: ":"))
        return AdblockCompilationOutput(
            sourceIdentifier: input.sourceIdentifier,
            groups: groups,
            diagnostics: diagnostics,
            inputRuleCount: normalizedRules.count,
            convertedNetworkRuleCount: networkRules.count,
            convertedNativeCosmeticRuleCount: cosmeticRules.count,
            unsupportedOrIgnoredRuleCount: diagnostics.unsupportedRules.count + diagnostics.ignoredRules.count,
            contentHash: contentHash
        )
    }

    private static func networkContentRule(from rule: String) -> [String: Any]? {
        let parts = rule.split(separator: "$", maxSplits: 1, omittingEmptySubsequences: false)
        let pattern = String(parts[0])
        guard !pattern.contains("#"), !pattern.hasPrefix("@@") else { return nil }

        var trigger: [String: Any]
        if pattern.hasPrefix("||") {
            let hostPattern = String(pattern.dropFirst(2))
            let host = hostPattern
                .split { $0 == "^" || $0 == "/" || $0 == "*" }
                .first
                .map(String.init) ?? ""
            guard !host.isEmpty else { return nil }
            trigger = ["url-filter": "^[^:]+:(//)?([^/]+\\\\.)?\(escapedRegex(host))"]
        } else {
            trigger = ["url-filter": escapedLooseURLFilter(pattern)]
        }

        if parts.count == 2,
           let domains = domainOptions(from: String(parts[1])) {
            trigger["if-domain"] = domains
        }

        return [
            "trigger": trigger,
            "action": ["type": "block"],
        ]
    }

    private static func cosmeticContentRule(from rule: String) throws -> [String: Any]? {
        guard let markerRange = rule.range(of: "##") else { return nil }
        let selector = String(rule[markerRange.upperBound...])
        let domainPrefix = String(rule[..<markerRange.lowerBound])

        guard !selector.contains("+js(") else {
            throw AdblockRustCompilerError.unsupportedRule(rule, "scriptlet injections require future enhanced runtime cleanup")
        }
        guard !selector.contains(":has("), !selector.contains(":matches-path("), !selector.contains(":xpath(") else {
            throw AdblockRustCompilerError.unsupportedRule(rule, "procedural cosmetic filters are not representable as native CSS hiding")
        }
        guard !selector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        var trigger: [String: Any] = ["url-filter": ".*"]
        let domains = domainPrefix
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("~") }
        if !domains.isEmpty {
            trigger["if-domain"] = domains
        }

        return [
            "trigger": trigger,
            "action": [
                "type": "css-display-none",
                "selector": selector,
            ],
        ]
    }

    private static func domainOptions(from options: String) -> [String]? {
        for option in options.split(separator: ",") {
            let text = String(option)
            guard text.hasPrefix("domain=") else { continue }
            let domains = text.dropFirst("domain=".count)
                .split(separator: "|")
                .map(String.init)
                .filter { !$0.isEmpty && !$0.hasPrefix("~") }
                .map { "*\($0)" }
            return domains.isEmpty ? nil : domains
        }
        return nil
    }

    private static func encodedJSON(_ rules: [[String: Any]]) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: rules,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        return String(decoding: data, as: UTF8.self)
    }

    private static func escapedRegex(_ value: String) -> String {
        NSRegularExpression.escapedPattern(for: value)
    }

    private static func escapedLooseURLFilter(_ value: String) -> String {
        ".*\(escapedRegex(value).replacingOccurrences(of: "\\*", with: ".*")).*"
    }

    private static func stableHash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

enum AdblockRustCompilerError: Error, Equatable {
    case unsupportedRule(String, String)
}
