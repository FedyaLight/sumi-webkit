import CryptoKit
import Foundation

enum AdblockCompiledRuleGroupKind: String, Codable, CaseIterable, Hashable, Sendable {
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
    var nativeCosmeticRuleCount = 0
    var unsupportedCosmeticRuleCount = 0
    var ignoredScriptletOrProceduralRuleCount = 0
    var isNativeCosmeticGroupEmpty = true
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
    private let adapter: any AdblockRustAdapterInvoking

    init(adapter: any AdblockRustAdapterInvoking = AdblockRustHelperExecutableAdapter()) {
        self.adapter = adapter
    }

    func compile(_ input: AdblockCompilationInput) async throws -> AdblockCompilationOutput {
        let normalizedRules = Self.normalizedRules(from: input.filterTexts)
        let adapterOutput = try await adapter.compile(normalizedRules)
        return try Self.makeOutput(
            input: input,
            normalizedRules: normalizedRules,
            adapterOutput: adapterOutput
        )
    }

    private static func makeOutput(
        input: AdblockCompilationInput,
        normalizedRules: [String],
        adapterOutput: AdblockRustAdapterOutput
    ) throws -> AdblockCompilationOutput {
        try validateAdapterOutput(adapterOutput)
        var groups = [AdblockCompiledRuleGroup]()
        let networkJSON = try encodedJSON(adapterOutput.network)
        let cosmeticJSON = try encodedJSON(adapterOutput.nativeCosmeticCSS)
        let networkBlockCount = adapterOutput.network.countActions(named: "block")
        let nativeCosmeticCount = adapterOutput.nativeCosmeticCSS.countActions(named: "css-display-none")

        if input.selectedOutputGroups.contains(.network) {
            groups.append(
                AdblockCompiledRuleGroup(
                    kind: .network,
                    name: "\(input.sourceIdentifier).network",
                    encodedContentRuleList: networkJSON,
                    convertedRuleCount: networkBlockCount,
                    contentHash: stableHash(networkJSON)
                )
            )
        }

        if input.selectedOutputGroups.contains(.nativeCosmeticCSS) {
            groups.append(
                AdblockCompiledRuleGroup(
                    kind: .nativeCosmeticCSS,
                    name: "\(input.sourceIdentifier).native-css",
                    encodedContentRuleList: cosmeticJSON,
                    convertedRuleCount: nativeCosmeticCount,
                    contentHash: stableHash(cosmeticJSON)
                )
            )
        }

        let unsupportedDiagnostics = adapterOutput.unsupportedOrIgnored.map {
            AdblockCompilationDiagnostics.Entry(rule: $0.rule, reason: $0.reason)
        }
        let unsupportedCosmeticCount = adapterOutput.unsupportedOrIgnored.filter {
            isCosmeticRule($0.rule)
        }.count
        let scriptletOrProceduralCount = adapterOutput.unsupportedOrIgnored.filter {
            isScriptletOrProceduralCosmeticRule($0.rule) || isScriptletOrProceduralReason($0.reason)
        }.count
        let ignoredRules = normalizedRules
            .filter { $0.hasPrefix("!") || $0.hasPrefix("[") }
            .map { AdblockCompilationDiagnostics.Entry(rule: $0, reason: "metadata or comment") }
        let diagnostics = AdblockCompilationDiagnostics(
            unsupportedRules: unsupportedDiagnostics,
            ignoredRules: ignoredRules,
            nativeCosmeticRuleCount: nativeCosmeticCount,
            unsupportedCosmeticRuleCount: unsupportedCosmeticCount,
            ignoredScriptletOrProceduralRuleCount: scriptletOrProceduralCount,
            isNativeCosmeticGroupEmpty: nativeCosmeticCount == 0
        )
        let contentHash = stableHash(groups.map(\.contentHash).joined(separator: ":"))

        return AdblockCompilationOutput(
            sourceIdentifier: input.sourceIdentifier,
            groups: groups,
            diagnostics: diagnostics,
            inputRuleCount: normalizedRules.count,
            convertedNetworkRuleCount: networkBlockCount,
            convertedNativeCosmeticRuleCount: nativeCosmeticCount,
            unsupportedOrIgnoredRuleCount: diagnostics.unsupportedRules.count + diagnostics.ignoredRules.count,
            contentHash: contentHash
        )
    }

    private static func normalizedRules(from filterTexts: [String]) -> [String] {
        filterTexts
            .flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func encodedJSON(_ rules: [AdblockRustContentRule]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(rules)
        return String(decoding: data, as: UTF8.self)
    }

    private static func validateAdapterOutput(_ output: AdblockRustAdapterOutput) throws {
        try validateContentRules(output.network, groupName: "network") { actionType, _ in
            Set([
                "block",
                "block-cookies",
                "ignore-previous-rules",
                "make-https",
            ]).contains(actionType)
        }
        try validateContentRules(output.nativeCosmeticCSS, groupName: "nativeCosmeticCSS") { actionType, action in
            actionType == "css-display-none"
                && action["selector"]?.stringValue?.isEmpty == false
        }
    }

    private static func validateContentRules(
        _ rules: [AdblockRustContentRule],
        groupName: String,
        allowsAction: (String, [String: JSONObject]) -> Bool
    ) throws {
        for rule in rules {
            guard let action = rule.action.objectValue,
                  let actionType = action["type"]?.stringValue,
                  allowsAction(actionType, action)
            else {
                throw AdblockRustCompilerError.invalidAdapterOutput(
                    "\(groupName) contains unsupported WebKit action"
                )
            }
            guard let trigger = rule.trigger.objectValue,
                  trigger["url-filter"]?.stringValue?.isEmpty == false
            else {
                throw AdblockRustCompilerError.invalidAdapterOutput(
                    "\(groupName) contains a content rule without url-filter"
                )
            }
        }
    }

    private static func isCosmeticRule(_ rule: String) -> Bool {
        rule.contains("##") || rule.contains("#@#") || rule.contains("#?#") || rule.contains("#%#")
    }

    private static func isScriptletOrProceduralCosmeticRule(_ rule: String) -> Bool {
        rule.contains("##+js(")
            || rule.contains("#%#")
            || rule.contains(":has(")
            || rule.contains(":has-text(")
            || rule.contains(":matches-css(")
            || rule.contains(":xpath(")
            || rule.contains(":-abp-")
    }

    private static func isScriptletOrProceduralReason(_ reason: String) -> Bool {
        reason.localizedCaseInsensitiveContains("scriptlet")
            || reason.localizedCaseInsensitiveContains("procedural")
            || reason.localizedCaseInsensitiveContains("generic script inject")
    }

    private static func stableHash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

protocol AdblockRustAdapterInvoking: Sendable {
    func compile(_ normalizedRules: [String]) async throws -> AdblockRustAdapterOutput
}

struct AdblockRustHelperExecutableAdapter: AdblockRustAdapterInvoking {
    func compile(_ normalizedRules: [String]) async throws -> AdblockRustAdapterOutput {
        let helperURL = try Self.helperExecutableURL()
        return try await Task.detached(priority: .utility) {
            try Self.runHelper(at: helperURL, normalizedRules: normalizedRules)
        }.value
    }

    private static func runHelper(
        at helperURL: URL,
        normalizedRules: [String]
    ) throws -> AdblockRustAdapterOutput {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = helperURL
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        inputPipe.fileHandleForWriting.write(Data(normalizedRules.joined(separator: "\n").utf8))
        try? inputPipe.fileHandleForWriting.close()

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderr = String(decoding: errorOutput, as: UTF8.self)
            throw AdblockRustCompilerError.adapterFailed(status: process.terminationStatus, stderr: stderr)
        }

        return try JSONDecoder().decode(AdblockRustAdapterOutput.self, from: output)
    }

    private static func helperExecutableURL() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["SUMI_ADBLOCK_RUST_ADAPTER"],
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }

        let candidateBundles = [Bundle.main, Bundle(for: BundleMarker.self)]
        for bundle in candidateBundles {
            if let url = bundle.url(forAuxiliaryExecutable: "sumi-adblock-rust-adapter") {
                return url
            }
            if let executableURL = bundle.executableURL {
                let adjacentURL = executableURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("sumi-adblock-rust-adapter")
                if FileManager.default.isExecutableFile(atPath: adjacentURL.path) {
                    return adjacentURL
                }
            }
        }

        throw AdblockRustCompilerError.adapterNotFound
    }

    private final class BundleMarker {}
}

struct AdblockRustAdapterOutput: Decodable, Equatable, Sendable {
    let network: [AdblockRustContentRule]
    let nativeCosmeticCSS: [AdblockRustContentRule]
    let unsupportedOrIgnored: [AdblockRustAdapterDiagnostic]

    private enum CodingKeys: String, CodingKey {
        case network
        case nativeCosmeticCSS = "native_cosmetic_css"
        case unsupportedOrIgnored = "unsupported_or_ignored"
    }
}

struct AdblockRustAdapterDiagnostic: Decodable, Equatable, Sendable {
    let rule: String
    let reason: String
}

struct AdblockRustContentRule: Codable, Equatable, Sendable {
    let action: JSONObject
    let trigger: JSONObject
}

extension [AdblockRustContentRule] {
    fileprivate func countActions(named actionName: String) -> Int {
        filter { rule in
            rule.action.objectValue?["type"]?.stringValue == actionName
        }.count
    }
}

enum JSONObject: Codable, Equatable, Sendable {
    case string(String)
    case bool(Bool)
    case array([JSONObject])
    case object([String: JSONObject])
    case null

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    var objectValue: [String: JSONObject]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([JSONObject].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONObject].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

enum AdblockRustCompilerError: Error, Equatable {
    case adapterNotFound
    case adapterFailed(status: Int32, stderr: String)
    case invalidAdapterOutput(String)
}
