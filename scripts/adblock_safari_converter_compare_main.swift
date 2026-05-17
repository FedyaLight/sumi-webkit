import ContentBlockerConverter
import CryptoKit
import Darwin
import Foundation
import WebKit

struct MemorySnapshot: Codable {
    let stage: String
    let residentMemoryBytes: UInt64?
}

struct ShardReport: Codable {
    let id: String
    let groupID: String
    let kind: String
    let path: String
    let ruleCount: Int
    let jsonSizeBytes: Int
    var webKitCompileSucceeded: Bool?
    var webKitError: String?
}

struct GroupConversionReport: Codable {
    let compiler: String
    let integrationStatus: String
    let profile: String
    let groupID: String
    let groupingModel: String
    let conversionSucceeded: Bool
    let version: String
    let sourceListIDs: [String]
    let sourceCategories: [String]
    let inputRuleCount: Int
    let outputRuleCount: Int
    let networkRuleCount: Int
    let nativeCSSRuleCount: Int
    let unsupportedOrAdvancedRuleCount: Int
    let unsafeNativeCSSFilteredRuleCount: Int
    let droppedUnsafeNativeCSSRuleCount: Int
    let diagnostics: [String]
    let webKitCompileSucceeded: Bool
    let jsonSizeBytes: Int
    let conversionTimeMilliseconds: Double
    let ruleCapHit: Bool
    let discardedRuleCount: Int
    let shards: [ShardReport]
    let memorySnapshots: [MemorySnapshot]
}

struct SanitizationReport: Codable {
    let inputRuleCount: Int
    let outputRuleCount: Int
    let nativeCSSRuleCount: Int
    let unsafeNativeCSSFilteredRuleCount: Int
    let droppedUnsafeNativeCSSRuleCount: Int
    let filteredSelectors: [FilteredSelector]
}

struct FilteredSelector: Codable {
    let selector: String
    let reason: String
}

struct ValidationOutput: Codable {
    let webKitCompileSucceeded: Bool
    let webKitError: String?
    let memorySnapshots: [MemorySnapshot]
}

struct WebKitPlan: Decodable {
    let compiler: String
    let profile: String
    let trackingProtectionState: String
    let cosmeticMode: String
    let enhancedRuntimeState: String
    let attachKinds: [String]
    let shards: [WebKitPlanShard]
}

struct WebKitPlanShard: Decodable {
    let id: String
    let groupID: String?
    let kind: String
    let path: String
}

struct WebKitPageRunReport: Codable {
    let compiler: String
    let profile: String
    let trackingProtectionState: String
    let cosmeticMode: String
    let enhancedRuntimeState: String
    let pageURL: String?
    let webKitCompileSucceeded: Bool
    let compiledShardCount: Int
    let attachedShardCount: Int
    let attachedShardIdentifiers: [String]
    let failedShardIdentifier: String?
    let webKitError: String?
    let scoreText: String?
    let scorePercent: Int?
    let scoreFinalized: Bool
    let scoreSource: String?
    let blankPageResult: String
    let pageTitle: String?
    let bodyTextSample: String?
    let memorySnapshots: [MemorySnapshot]
}

typealias JSONRule = [String: Any]

@main
enum Main {
    @MainActor
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            throw HarnessError.usage("missing command")
        }
        let options = Options(arguments.dropFirst())

        switch command {
        case "--validate-json":
            let json = Self.readStandardInput()
            let output = await validateJSON(json)
            try writeJSON(output)
        case "--sanitize-json":
            let json = Self.readStandardInput()
            let sanitized = try sanitizeJSON(json)
            if let reportPath = options.value(for: "--report-path") {
                try writeJSON(sanitized.report, to: URL(fileURLWithPath: reportPath))
            }
            FileHandle.standardOutput.write(Data(sanitized.json.utf8))
        case "--convert-safari-group":
            let report = try await convertSafariGroup(options: options)
            try writeJSON(report)
        case "--webkit-plan":
            let report = try await runWebKitPlan(options: options)
            try writeJSON(report)
        case "--safety-self-test":
            try safetySelfTest()
            try writeJSON(["ok": true])
        default:
            throw HarnessError.usage("unknown command: \(command)")
        }
    }

    private static func convertSafariGroup(options: Options) async throws -> GroupConversionReport {
        let profile = try options.requiredValue(for: "--profile")
        let groupID = try options.requiredValue(for: "--group-id")
        let shardDirectory = URL(fileURLWithPath: try options.requiredValue(for: "--shard-dir"))
        let sourceListIDs = options.csv(for: "--source-list-ids")
        let sourceCategories = options.csv(for: "--source-categories")
        let generationID = options.value(for: "--generation-id") ?? stableHash(profile + ":" + groupID)
        let input = Self.readStandardInput()
        var contiguousInput = input
        contiguousInput.makeContiguousUTF8()
        let rules = contiguousInput.components(separatedBy: .newlines)
        var snapshots = [memorySnapshot("beforeSafariConversion")]
        let started = Date()
        let results = convertRecursively(rules: rules)
        let elapsed = Date().timeIntervalSince(started) * 1000
        snapshots.append(memorySnapshot("afterSafariConversion"))

        var combinedRules = [JSONRule]()
        var advancedRulesCount = 0
        var errorsCount = 0
        var discardedRuleCount = 0
        var sourceRulesCount = 0
        var sourceCompatibleRulesCount = 0
        for result in results {
            combinedRules.append(contentsOf: try contentRules(from: result.safariRulesJSON))
            advancedRulesCount += result.advancedRulesCount
            errorsCount += result.errorsCount
            discardedRuleCount += result.discardedSafariRules
            sourceRulesCount += result.sourceRulesCount
            sourceCompatibleRulesCount += result.sourceSafariCompatibleRulesCount
        }

        let sanitized = sanitizeRules(combinedRules)
        snapshots.append(memorySnapshot("afterNativeCSSSafetyFilter"))

        let networkRules = sanitized.rules.filter { actionType(in: $0) != "css-display-none" }
        let nativeCSSRules = sanitized.rules.filter { actionType(in: $0) == "css-display-none" }
        let networkShards = try writeShards(
            rules: networkRules,
            kind: "network",
            groupID: groupID,
            generationID: generationID,
            shardDirectory: shardDirectory
        )
        let nativeCSSShards = try writeShards(
            rules: nativeCSSRules,
            kind: "nativeCSS",
            groupID: groupID,
            generationID: generationID,
            shardDirectory: shardDirectory
        )
        let shards = networkShards + nativeCSSShards
        snapshots.append(memorySnapshot("afterShardJSONGeneration"))

        return GroupConversionReport(
            compiler: "SafariConverterLib",
            integrationStatus: "external-harness-only",
            profile: profile,
            groupID: groupID,
            groupingModel: "experimentalAdGuardNative/grouped-by-category",
            conversionSucceeded: true,
            version: ContentBlockerConverterVersion.library,
            sourceListIDs: sourceListIDs,
            sourceCategories: sourceCategories,
            inputRuleCount: sourceRulesCount,
            outputRuleCount: sanitized.rules.count,
            networkRuleCount: networkRules.count,
            nativeCSSRuleCount: nativeCSSRules.count,
            unsupportedOrAdvancedRuleCount: errorsCount + advancedRulesCount + discardedRuleCount,
            unsafeNativeCSSFilteredRuleCount: sanitized.filteredSelectors.count,
            droppedUnsafeNativeCSSRuleCount: sanitized.droppedRuleCount,
            diagnostics: [
                "sourceSafariCompatibleRules=\(sourceCompatibleRulesCount)",
                "errors=\(errorsCount)",
                "advanced=\(advancedRulesCount)",
                "discarded=\(discardedRuleCount)",
                "recursiveConversionResults=\(results.count)",
            ],
            webKitCompileSucceeded: false,
            jsonSizeBytes: shards.reduce(0) { $0 + $1.jsonSizeBytes },
            conversionTimeMilliseconds: elapsed,
            ruleCapHit: discardedRuleCount > 0,
            discardedRuleCount: discardedRuleCount,
            shards: shards,
            memorySnapshots: snapshots
        )
    }

    @MainActor
    private static func runWebKitPlan(options: Options) async throws -> WebKitPageRunReport {
        let planPath = try options.requiredValue(for: "--plan-path")
        let pageURLString = options.value(for: "--page-url")
        let planData = try Data(contentsOf: URL(fileURLWithPath: planPath))
        let plan = try JSONDecoder().decode(WebKitPlan.self, from: planData)
        let attachKinds = Set(plan.attachKinds)
        var snapshots = [memorySnapshot("beforeWKContentRuleListStoreCompile")]
        var compiled = [(WebKitPlanShard, WKContentRuleList)]()
        var failedShardIdentifier: String?
        var webKitError: String?

        for shard in plan.shards {
            do {
                let json = try String(contentsOf: URL(fileURLWithPath: shard.path), encoding: .utf8)
                let ruleList = try await compileWithWebKit(identifier: shard.id, json: json)
                guard await lookupWithWebKit(identifier: shard.id) != nil else {
                    throw HarnessError.runtime("compiled shard could not be looked up: \(shard.id)")
                }
                compiled.append((shard, ruleList))
            } catch {
                failedShardIdentifier = shard.id
                webKitError = error.localizedDescription
                break
            }
        }
        snapshots.append(memorySnapshot("afterWKContentRuleListStoreCompile"))

        guard failedShardIdentifier == nil else {
            return WebKitPageRunReport(
                compiler: plan.compiler,
                profile: plan.profile,
                trackingProtectionState: plan.trackingProtectionState,
                cosmeticMode: plan.cosmeticMode,
                enhancedRuntimeState: plan.enhancedRuntimeState,
                pageURL: pageURLString,
                webKitCompileSucceeded: false,
                compiledShardCount: compiled.count,
                attachedShardCount: 0,
                attachedShardIdentifiers: [],
                failedShardIdentifier: failedShardIdentifier,
                webKitError: webKitError,
                scoreText: nil,
                scorePercent: nil,
                scoreFinalized: false,
                scoreSource: nil,
                blankPageResult: "not loaded; WebKit compile failed",
                pageTitle: nil,
                bodyTextSample: nil,
                memorySnapshots: snapshots
            )
        }

        let controller = WKUserContentController()
        let attached = compiled.filter { attachKinds.contains($0.0.kind) }
        for item in attached {
            controller.add(item.1)
        }
        snapshots.append(memorySnapshot("afterPageAttachment"))

        var pageTitle: String?
        var bodyText: String?
        var blankPageResult = "not loaded"
        if let pageURLString, let pageURL = URL(string: pageURLString) {
            let configuration = WKWebViewConfiguration()
            configuration.userContentController = controller
            let webView = WKWebView(
                frame: CGRect(x: 0, y: 0, width: 1280, height: 900),
                configuration: configuration
            )
            do {
                try await load(URLRequest(url: pageURL), into: webView)
                let pageState = try await waitForPageState(in: webView)
                pageTitle = pageState.title
                bodyText = pageState.searchText
                blankPageResult = pageState.isBlank ? "blank" : "visible"
            } catch {
                webKitError = error.localizedDescription
                blankPageResult = "load failed: \(error.localizedDescription)"
            }
        }
        snapshots.append(memorySnapshot("afterPageLoad"))

        for item in compiled {
            try? await removeWithWebKit(identifier: item.0.id)
        }
        snapshots.append(memorySnapshot("afterCleanup"))

        let finalScore = finalScoreFromBodyText(bodyText)
        let score = finalScore ?? scoreFromBodyText(bodyText)
        return WebKitPageRunReport(
            compiler: plan.compiler,
            profile: plan.profile,
            trackingProtectionState: plan.trackingProtectionState,
            cosmeticMode: plan.cosmeticMode,
            enhancedRuntimeState: plan.enhancedRuntimeState,
            pageURL: pageURLString,
            webKitCompileSucceeded: true,
            compiledShardCount: compiled.count,
            attachedShardCount: attached.count,
            attachedShardIdentifiers: attached.map(\.0.id).sorted(),
            failedShardIdentifier: nil,
            webKitError: webKitError,
            scoreText: score.text,
            scorePercent: score.percent,
            scoreFinalized: finalScore?.percent != nil,
            scoreSource: finalScore?.percent != nil
                ? "turtlecute-final-totals"
                : (score.percent != nil ? "visual-percentage-timeout-fallback" : nil),
            blankPageResult: blankPageResult,
            pageTitle: pageTitle,
            bodyTextSample: bodyText.map { String($0.prefix(4000)) },
            memorySnapshots: snapshots
        )
    }

    private static func validateJSON(_ json: String) async -> ValidationOutput {
        var snapshots = [memorySnapshot("beforeWKContentRuleListStoreCompile")]
        do {
            let identifier = "sumi.adblock.compare.validation.\(UUID().uuidString)"
            _ = try await compileWithWebKit(identifier: identifier, json: json)
            let canLookup = await lookupWithWebKit(identifier: identifier) != nil
            try? await removeWithWebKit(identifier: identifier)
            snapshots.append(memorySnapshot("afterWKContentRuleListStoreCompile"))
            return ValidationOutput(
                webKitCompileSucceeded: canLookup,
                webKitError: nil,
                memorySnapshots: snapshots
            )
        } catch {
            snapshots.append(memorySnapshot("afterWKContentRuleListStoreCompile"))
            return ValidationOutput(
                webKitCompileSucceeded: false,
                webKitError: error.localizedDescription,
                memorySnapshots: snapshots
            )
        }
    }

    private static func convertRecursively(rules: [String]) -> [ConversionResult] {
        guard !rules.isEmpty else { return [] }
        let result = ContentBlockerConverter().convertArray(
            rules: rules,
            safariVersion: .autodetect(),
            advancedBlocking: false
        )
        if result.discardedSafariRules > 0, rules.count > 1 {
            let midpoint = rules.count / 2
            return convertRecursively(rules: Array(rules[..<midpoint]))
                + convertRecursively(rules: Array(rules[midpoint...]))
        }
        return result.safariRulesCount > 0 ? [result] : []
    }

    private static func writeShards(
        rules: [JSONRule],
        kind: String,
        groupID: String,
        generationID: String,
        shardDirectory: URL
    ) throws -> [ShardReport] {
        try FileManager.default.createDirectory(at: shardDirectory, withIntermediateDirectories: true)
        let chunks = try deterministicChunks(from: rules)
        return try chunks.enumerated().map { index, chunk in
            let json = try encodedJSON(chunk)
            let hash = stableHash(json)
            let shardIndex = index + 1
            let id = "sumi.adblock.experimentalAdGuardNative.\(groupID).\(kind).\(generationID).\(String(format: "%04d", shardIndex)).\(hash)"
            let path = shardDirectory
                .appendingPathComponent("\(groupID)-\(kind)-\(String(format: "%04d", shardIndex)).json")
            try json.write(to: path, atomically: true, encoding: .utf8)
            return ShardReport(
                id: id,
                groupID: groupID,
                kind: kind,
                path: path.path,
                ruleCount: chunk.count,
                jsonSizeBytes: json.utf8.count,
                webKitCompileSucceeded: nil,
                webKitError: nil
            )
        }
    }

    private static func deterministicChunks(from rules: [JSONRule]) throws -> [[JSONRule]] {
        let maxRulesPerShard = 25_000
        let maxJSONBytesPerShard = 3_000_000
        guard !rules.isEmpty else { return [] }
        var chunks = [[JSONRule]]()
        var current = [JSONRule]()
        var currentEstimatedByteCount = 2

        for rule in rules {
            let encodedRuleByteCount = try encodedJSON(rule).utf8.count
            let separatorByteCount = current.isEmpty ? 0 : 1
            let wouldExceedRuleLimit = current.count >= maxRulesPerShard
            let wouldExceedByteLimit = !current.isEmpty
                && currentEstimatedByteCount + separatorByteCount + encodedRuleByteCount > maxJSONBytesPerShard

            if wouldExceedRuleLimit || wouldExceedByteLimit {
                chunks.append(current)
                current = []
                currentEstimatedByteCount = 2
            }

            let actualSeparatorByteCount = current.isEmpty ? 0 : 1
            current.append(rule)
            currentEstimatedByteCount += actualSeparatorByteCount + encodedRuleByteCount
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return try chunks.flatMap { try splitChunkIfNeeded($0, maxJSONBytesPerShard: maxJSONBytesPerShard) }
    }

    private static func splitChunkIfNeeded(
        _ chunk: [JSONRule],
        maxJSONBytesPerShard: Int
    ) throws -> [[JSONRule]] {
        let encodedByteCount = try encodedJSON(chunk).utf8.count
        guard encodedByteCount > maxJSONBytesPerShard, chunk.count > 1 else {
            return [chunk]
        }
        let midpoint = chunk.count / 2
        return try splitChunkIfNeeded(Array(chunk[..<midpoint]), maxJSONBytesPerShard: maxJSONBytesPerShard)
            + splitChunkIfNeeded(Array(chunk[midpoint...]), maxJSONBytesPerShard: maxJSONBytesPerShard)
    }

    private static func sanitizeJSON(_ json: String) throws -> (json: String, report: SanitizationReport) {
        let rules = try contentRules(from: json)
        let sanitized = sanitizeRules(rules)
        let nativeCSSRuleCount = sanitized.rules.filter { actionType(in: $0) == "css-display-none" }.count
        let report = SanitizationReport(
            inputRuleCount: rules.count,
            outputRuleCount: sanitized.rules.count,
            nativeCSSRuleCount: nativeCSSRuleCount,
            unsafeNativeCSSFilteredRuleCount: sanitized.filteredSelectors.count,
            droppedUnsafeNativeCSSRuleCount: sanitized.droppedRuleCount,
            filteredSelectors: sanitized.filteredSelectors
        )
        return (try encodedJSON(sanitized.rules), report)
    }

    private static func sanitizeRules(
        _ rules: [JSONRule]
    ) -> (rules: [JSONRule], filteredSelectors: [FilteredSelector], droppedRuleCount: Int) {
        var sanitizedRules = [JSONRule]()
        var filteredSelectors = [FilteredSelector]()
        var droppedRuleCount = 0
        sanitizedRules.reserveCapacity(rules.count)

        for rule in rules {
            guard var action = rule["action"] as? [String: Any],
                  action["type"] as? String == "css-display-none",
                  let selector = action["selector"] as? String
            else {
                sanitizedRules.append(rule)
                continue
            }

            let selectorComponents = splitSelectorList(selector)
            let retainedSelectors = selectorComponents.filter { component in
                if let unsafeReason = unsafeNativeCSSSelectorReason(component) {
                    filteredSelectors.append(FilteredSelector(selector: component, reason: unsafeReason))
                    return false
                }
                return true
            }

            guard !retainedSelectors.isEmpty else {
                droppedRuleCount += 1
                continue
            }

            if retainedSelectors.count == selectorComponents.count {
                sanitizedRules.append(rule)
            } else {
                var rewritten = rule
                action["selector"] = retainedSelectors.joined(separator: ", ")
                rewritten["action"] = action
                sanitizedRules.append(rewritten)
            }
        }

        return (sanitizedRules, filteredSelectors, droppedRuleCount)
    }

    private static func safetySelfTest() throws {
        let json = """
        [
          {"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":"html, HTML, body, body::before, #app, body > div[id][class*=\\" \\"], .ad-banner"}},
          {"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":"#__next"}},
          {"trigger":{"url-filter":".*"},"action":{"type":"block"}}
        ]
        """
        let result = try sanitizeJSON(json)
        guard result.report.unsafeNativeCSSFilteredRuleCount == 6 else {
            throw HarnessError.runtime("expected 6 unsafe selector filters, got \(result.report.unsafeNativeCSSFilteredRuleCount)")
        }
        guard result.report.droppedUnsafeNativeCSSRuleCount == 1 else {
            throw HarnessError.runtime("expected 1 dropped unsafe CSS rule, got \(result.report.droppedUnsafeNativeCSSRuleCount)")
        }
        guard result.json.contains("body::before"),
              result.json.contains(".ad-banner"),
              !result.json.contains("#__next"),
              !result.json.contains("body > div[id][class*=") else {
            throw HarnessError.runtime("safety self-test sanitized JSON mismatch")
        }
    }

    private static func unsafeNativeCSSSelectorReason(_ selector: String) -> String? {
        if targetsDocumentRootOrAppContainer(selector) {
            return "unsafe native CSS root-container selector"
        }
        if targetsRootChildPageShellContainer(selector) {
            return "unsafe native CSS root-child page shell selector"
        }
        return nil
    }

    private static func targetsDocumentRootOrAppContainer(_ selector: String) -> Bool {
        let trimmed = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let subject = rightmostSelectorCompound(in: trimmed)
        guard !subject.isEmpty else { return false }

        let caseInsensitiveSubject = subject.lowercased()
        if isUnsafeRootSelectorSubject(caseInsensitiveSubject, root: "html")
            || isUnsafeRootSelectorSubject(caseInsensitiveSubject, root: "body")
            || isUnsafeRootSelectorSubject(caseInsensitiveSubject, root: ":root") {
            return true
        }

        for appRoot in ["#app", "#root", "#__next", "#__nuxt"] {
            if subject == appRoot
                || subject.hasPrefix(appRoot + ".")
                || subject.hasPrefix(appRoot + "[")
                || (subject.hasPrefix(appRoot + ":") && !subject.hasPrefix(appRoot + "::")) {
                return true
            }
        }

        return false
    }

    private static func targetsRootChildPageShellContainer(_ selector: String) -> Bool {
        let normalized = normalizedRootChildSubjectSelector(normalizedRootChildSelector(selector))
        return [
            "body > div[id][class*=\" \"]",
            "body > div[id][class*=\" \"]:first-child",
            "html > body > div[id][class*=\" \"]",
            "html > body > div[id][class*=\" \"]:first-child",
        ].contains(normalized)
    }

    private static func normalizedRootChildSelector(_ selector: String) -> String {
        selector
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[class*=' ']", with: "[class*=\" \"]")
            .replacingOccurrences(of: #"\s*>\s*"#, with: " > ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func normalizedRootChildSubjectSelector(_ selector: String) -> String {
        guard let hasRange = selector.range(of: ":has(") else {
            return selector
        }
        return String(selector[..<hasRange.lowerBound])
    }

    private static func isUnsafeRootSelectorSubject(_ subject: String, root: String) -> Bool {
        guard subject.hasPrefix(root) else { return false }
        let suffix = subject.dropFirst(root.count)
        if suffix.isEmpty {
            return true
        }
        if suffix.hasPrefix("::") {
            return false
        }
        return suffix.hasPrefix(".")
            || suffix.hasPrefix("[")
            || suffix.hasPrefix(":")
    }

    private static func rightmostSelectorCompound(in selector: String) -> String {
        var depth = 0
        var quote: Character?
        var lastBoundary = selector.startIndex
        var index = selector.startIndex

        while index < selector.endIndex {
            let character = selector[index]
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else if character == "\\" {
                    index = selector.index(after: index)
                }
            } else {
                switch character {
                case "\"", "'":
                    quote = character
                case "[", "(":
                    depth += 1
                case "]", ")":
                    depth = max(0, depth - 1)
                case ">", "+", "~":
                    if depth == 0 {
                        lastBoundary = selector.index(after: index)
                    }
                default:
                    if depth == 0, character.isWhitespace {
                        lastBoundary = selector.index(after: index)
                    }
                }
            }
            index = selector.index(after: index)
        }

        return String(selector[lastBoundary...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func splitSelectorList(_ selector: String) -> [String] {
        var parts = [String]()
        var depth = 0
        var quote: Character?
        var start = selector.startIndex
        var index = selector.startIndex

        while index < selector.endIndex {
            let character = selector[index]
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else if character == "\\" {
                    index = selector.index(after: index)
                }
            } else {
                switch character {
                case "\"", "'":
                    quote = character
                case "[", "(":
                    depth += 1
                case "]", ")":
                    depth = max(0, depth - 1)
                case "," where depth == 0:
                    parts.append(String(selector[start..<index]).trimmingCharacters(in: .whitespacesAndNewlines))
                    start = selector.index(after: index)
                default:
                    break
                }
            }
            index = selector.index(after: index)
        }

        parts.append(String(selector[start...]).trimmingCharacters(in: .whitespacesAndNewlines))
        return parts.filter { !$0.isEmpty }
    }

    private static func contentRules(from json: String) throws -> [JSONRule] {
        let data = Data(json.utf8)
        guard let array = try JSONSerialization.jsonObject(with: data) as? [JSONRule] else {
            throw HarnessError.runtime("expected WebKit content rule JSON array")
        }
        return array
    }

    private static func encodedJSON(_ rules: [JSONRule]) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: rules,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        return String(decoding: data, as: UTF8.self)
    }

    private static func encodedJSON(_ rule: JSONRule) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: rule,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        return String(decoding: data, as: UTF8.self)
    }

    private static func actionType(in rule: JSONRule) -> String? {
        (rule["action"] as? [String: Any])?["type"] as? String
    }

    @MainActor
    private static func compileWithWebKit(identifier: String, json: String) async throws -> WKContentRuleList {
        try await withCheckedThrowingContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: json
            ) { ruleList, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let ruleList {
                    continuation.resume(returning: ruleList)
                } else {
                    continuation.resume(throwing: HarnessError.runtime("compiled rule list missing: \(identifier)"))
                }
            }
        }
    }

    @MainActor
    private static func lookupWithWebKit(identifier: String) async -> WKContentRuleList? {
        await withCheckedContinuation { continuation in
            WKContentRuleListStore.default().lookUpContentRuleList(forIdentifier: identifier) { ruleList, _ in
                continuation.resume(returning: ruleList)
            }
        }
    }

    @MainActor
    private static func removeWithWebKit(identifier: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            WKContentRuleListStore.default().removeContentRuleList(forIdentifier: identifier) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    @MainActor
    private static func load(_ request: URLRequest, into webView: WKWebView) async throws {
        let delegate = NavigationDelegateBox()
        webView.navigationDelegate = delegate
        try await withCheckedThrowingContinuation { continuation in
            delegate.finish = { continuation.resume() }
            delegate.fail = { continuation.resume(throwing: $0) }
            webView.load(request)
        }
        webView.navigationDelegate = nil
    }

    @MainActor
    private static func waitForPageState(in webView: WKWebView) async throws -> (title: String, searchText: String, isBlank: Bool) {
        var latest = try await evaluatePageState(in: webView)
        for _ in 0..<60 {
            if finalScoreFromBodyText(latest.searchText)?.percent != nil {
                return latest
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
            latest = try await evaluatePageState(in: webView)
        }
        return latest
    }

    @MainActor
    private static func evaluatePageState(in webView: WKWebView) async throws -> (title: String, searchText: String, isBlank: Bool) {
        let script = """
        (() => {
          const body = document.body;
          const text = body ? body.innerText : "";
          const candidateSelectors = [
            ".lt_value",
            "#adb_test_r",
            "#test_log",
            "[id*=score]",
            "[class*=score]",
            "[id*=total]",
            "[class*=total]",
            "[aria-label*=score i]",
            "[aria-label*=total i]"
          ];
          const candidates = [];
          for (const selector of candidateSelectors) {
            for (const element of document.querySelectorAll(selector)) {
              const value = [
                element.innerText || "",
                element.textContent || "",
                element.getAttribute("aria-label") || "",
                element.getAttribute("data-score") || "",
                element.getAttribute("data-total") || ""
              ].join(" ");
              if (value.trim()) candidates.push(value);
            }
          }
          for (const node of [document.documentElement, body].filter(Boolean)) {
            try {
              const styles = getComputedStyle(node);
              for (const property of ["--liquid-title", "--liquid-percentage"]) {
                const value = styles.getPropertyValue(property);
                if (value && value.trim()) candidates.push(value);
              }
            } catch (_) {}
          }
          try {
            const stored = localStorage.getItem("adb_tool");
            if (stored && stored.trim()) candidates.push(stored);
          } catch (_) {}
          const rect = body ? body.getBoundingClientRect() : { width: 0, height: 0 };
          const visible = body && getComputedStyle(body).display !== "none" && rect.width > 0 && rect.height > 0;
          return {
            title: document.title || "",
            searchText: [text || "", ...candidates].join("\\n"),
            blank: !visible || (text || "").trim().length === 0
          };
        })();
        """
        let result = try await webView.evaluateJavaScript(script)
        guard let dictionary = result as? [String: Any] else {
            throw HarnessError.runtime("unexpected page-state result")
        }
        return (
            dictionary["title"] as? String ?? "",
            dictionary["searchText"] as? String ?? "",
            dictionary["blank"] as? Bool ?? true
        )
    }

    private static func scoreFromBodyText(_ bodyText: String?) -> (text: String?, percent: Int?) {
        guard let bodyText else { return (nil, nil) }
        if let finalScore = finalScoreFromBodyText(bodyText), finalScore.percent != nil {
            return finalScore
        }

        let patterns = [
            #"(?i)Total\s*:?\s*(\d{1,3})\s*%"#,
            #"(?i)(\d{1,3})\s*%\s*(?:blocked|total|protection)"#,
            #"(?i)score\s*:?\s*(\d{1,3})\s*%"#,
            #"(?i)['"]?(\d{1,3})\s*%['"]?"#,
        ]
        for pattern in patterns {
            if let match = bodyText.range(of: pattern, options: .regularExpression) {
                let text = String(bodyText[match])
                let digits = text.filter(\.isNumber)
                if let value = Int(digits), (0...100).contains(value) {
                    return (text, value)
                }
            }
        }
        return (nil, nil)
    }

    private static func finalScoreFromBodyText(_ bodyText: String?) -> (text: String?, percent: Int?)? {
        guard let bodyText else { return nil }
        let totalPatterns = [
            #"(?is)Total\s*:?\s*(\d{1,4}).{0,2000}?Blocked\s*:?\s*(\d{1,4}).{0,2000}?Not\s*Blocked\s*:?\s*(\d{1,4})"#,
            #"(?is)Total\s*:?\s*(\d{1,4}).{0,1000}?(\d{1,4})\s+blocked.{0,1000}?(\d{1,4})\s+not\s+blocked"#,
            #"(?is)"total"\s*:?\s*(\d{1,4}).{0,2000}?"blocked"\s*:?\s*(\d{1,4}).{0,2000}?"notblocked"\s*:?\s*(\d{1,4})"#,
        ]
        for pattern in totalPatterns {
            if let groups = firstRegexGroups(pattern: pattern, in: bodyText),
               groups.count == 3,
               let total = Int(groups[0]),
               let blocked = Int(groups[1]),
               let notBlocked = Int(groups[2]),
               total > 0,
               blocked <= total,
               notBlocked <= total {
                let percent = Int((Double(blocked) * 100 / Double(total)).rounded())
                guard (0...100).contains(percent) else { continue }
                return ("Total: \(total), Blocked: \(blocked), Not Blocked: \(notBlocked)", percent)
            }
        }
        return nil
    }

    private static func firstRegexGroups(pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange),
              match.numberOfRanges > 1 else {
            return nil
        }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func stableHash(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    private static func memorySnapshot(_ stage: String) -> MemorySnapshot {
        MemorySnapshot(stage: stage, residentMemoryBytes: residentMemoryBytes())
    }

    private static func residentMemoryBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.phys_footprint)
    }

    private static func readStandardInput() -> String {
        String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL? = nil) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        if let url {
            try data.write(to: url, options: .atomic)
        } else {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }
}

struct Options {
    let values: [String: String]

    init<S: Sequence>(_ arguments: S) where S.Element == String {
        var values = [String: String]()
        var iterator = Array(arguments).makeIterator()
        while let key = iterator.next() {
            guard key.hasPrefix("--"), let value = iterator.next() else { continue }
            values[key] = value
        }
        self.values = values
    }

    func value(for key: String) -> String? {
        values[key]
    }

    func requiredValue(for key: String) throws -> String {
        guard let value = values[key], !value.isEmpty else {
            throw HarnessError.usage("missing \(key)")
        }
        return value
    }

    func csv(for key: String) -> [String] {
        values[key]?
            .split(separator: ",")
            .map(String.init)
            .filter { !$0.isEmpty } ?? []
    }
}

enum HarnessError: Error, LocalizedError {
    case usage(String)
    case runtime(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message), .runtime(let message):
            return message
        }
    }
}

@MainActor
private final class NavigationDelegateBox: NSObject, WKNavigationDelegate {
    var finish: (() -> Void)?
    var fail: ((Error) -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish?()
        finish = nil
        fail = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail?(error)
        finish = nil
        fail = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail?(error)
        finish = nil
        fail = nil
    }
}
