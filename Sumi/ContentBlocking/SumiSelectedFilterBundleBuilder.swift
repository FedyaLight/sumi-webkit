import ContentBlockerConverter
import CryptoKit
import FilterEngine
import Foundation
import SumiDomain

enum SumiSelectedFilterBundleBuilderError: Error, LocalizedError {
    case invalidResponse(URL)
    case emptyList(String)
    case ruleLimitExceeded(slot: Int, discarded: Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let url):
            "Could not download filter list from \(url.absoluteString)."
        case .emptyList(let name):
            "Filter list \(name) is empty."
        case .ruleLimitExceeded(let slot, let discarded):
            "Filter slot \(slot) exceeded Safari's rule limit by \(discarded) converted rules. Disable one or more large lists."
        }
    }
}

/// Builds one combined prepared generation for an exact filter selection.
/// Download/cache layout, slot distribution, affinity handling,
/// conversion and FilterEngine serialization remain behind this one method.
actor SumiSelectedFilterBundleBuilder {
    typealias Fetch = @Sendable (URL) async throws -> Data

    private struct Source: Sendable {
        let list: SumiFilterListCatalog.List
        let fileURL: URL
        let hash: String
        let byteCount: Int
        let ruleCount: Int
    }

    struct Conversion: Sendable {
        let json: Data
        let safariRuleCount: Int
        let advancedRules: String
        let discardedRuleCount: Int
        /// Domain-scoped cosmetic rules extracted from the Safari JSON so the
        /// advanced pipeline can serve them selectively instead of WebKit
        /// applying every selector to every document.
        let domainCosmetics: [DomainCosmetic]
    }

    struct DomainCosmetic: Sendable {
        let selector: String
        let domains: [String]
    }

    private static var slotTypes: [[ContentBlockerType]] {
        [
            [.general],
            [.privacy],
            [.socialWidgetsAndAnnoyances, .security],
            [.other],
            [.custom],
        ]
    }

    private let fileManager: FileManager
    private let fetch: Fetch
    private let buildRoot: URL

    init(
        fileManager: FileManager = .default,
        buildRoot: URL? = nil,
        fetch: @escaping Fetch = SumiSelectedFilterBundleBuilder.fetchList
    ) {
        self.fileManager = fileManager
        self.fetch = fetch
        if let buildRoot {
            self.buildRoot = buildRoot
        } else {
            let canonical = SumiApplicationSupportDirectory
                .cachesRootURL(fileManager: fileManager)
                .appendingPathComponent(
                    "ContentBlocking/SelectedFilterBundles",
                    isDirectory: true
                )
            let legacy = fileManager.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            )[0]
            .appendingPathComponent(
                "Sumi/ContentBlocking/SelectedFilterBundles",
                isDirectory: true
            )
            self.buildRoot = SumiApplicationSupportDirectory
                .migrateLegacyDirectoryIfNeeded(
                    from: legacy,
                    to: canonical,
                    fileManager: fileManager
                )
        }
        Self.removeAbandonedTransactions(
            in: self.buildRoot,
            fileManager: fileManager
        )
    }

    func build(
        selectedLists: [SumiFilterListCatalog.List]
    ) async throws -> URL {
        let transactionRoot = buildRoot.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        var retainTransaction = false
        defer {
            if retainTransaction == false {
                try? fileManager.removeItem(at: transactionRoot)
            }
        }
        let sourcesRoot = transactionRoot.appendingPathComponent(
            "Sources",
            isDirectory: true
        )
        let bundleURL = transactionRoot.appendingPathComponent(
            SumiAdblockNativeRuleBundle.directoryName,
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: sourcesRoot,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: bundleURL,
            withIntermediateDirectories: true
        )

        let sources = try await download(
            selectedLists.sorted { $0.id < $1.id },
            to: sourcesRoot
        )
        let assignments = Self.distribute(sources)
        let networkDirectory = bundleURL.appendingPathComponent(
            "network",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: networkDirectory,
            withIntermediateDirectories: true
        )
        let webExtensionDirectory = bundleURL.appendingPathComponent(
            ".webext",
            isDirectory: true
        )
        let rulesBySlot = try Self.groupedRules(
            from: sources,
            assignments: assignments
        )
        var rawConversions: [Conversion] = []
        for (slot, rules) in rulesBySlot.enumerated() {
            let safariVersion = SafariVersion.autodetect()
            let conversion = await Task.detached(priority: .utility) {
                Self.convert(rules: rules, safariVersion: safariVersion)
            }.value
            if conversion.discardedRuleCount > 0 {
                throw SumiSelectedFilterBundleBuilderError.ruleLimitExceeded(
                    slot: slot + 1,
                    discarded: conversion.discardedRuleCount
                )
            }
            rawConversions.append(conversion)
        }

        // Route domain-scoped cosmetic rules away from the WebKit rule lists:
        // Safari applies every css-display-none selector to every document,
        // while the advanced pipeline can match them by document host.
        var conversions: [Conversion] = []
        var extractedCosmetics = [DomainCosmetic]()
        for conversion in rawConversions {
            let partitioned = try Self.partitionDomainCosmetics(conversion)
            extractedCosmetics.append(contentsOf: partitioned.cosmetics)
            conversions.append(partitioned.conversion)
        }

        let nativeShards = conversions
            .filter { $0.safariRuleCount > 0 }
            .map { (data: $0.json, ruleCount: $0.safariRuleCount) }
        var shardPayloads: [(relativePath: String, data: Data, ruleCount: Int)] = []
        for (index, shard) in nativeShards.enumerated() {
            let relativePath = String(
                format: "network/network-%04d.json",
                index + 1
            )
            try shard.data.write(
                to: bundleURL.appendingPathComponent(relativePath),
                options: .atomic
            )
            shardPayloads.append((
                relativePath,
                shard.data,
                shard.ruleCount
            ))
        }
        if shardPayloads.isEmpty {
            // WebKit rejects an empty content-rule-list array. `^$` is valid
            // in its regex subset and cannot match a non-empty request URL.
            let data = Data(
                "[{\"action\":{\"type\":\"block\"},\"trigger\":{\"url-filter\":\"^$\"}}]\n".utf8
            )
            let relativePath = "network/network-0001.json"
            try data.write(
                to: bundleURL.appendingPathComponent(relativePath),
                options: .atomic
            )
            shardPayloads.append((relativePath, data, 0))
        }

        let advancedRules = conversions
            .map(\.advancedRules)
            .filter { $0.isEmpty == false }
            .joined(separator: "\n")
        var domainCosmeticsData: Data?
        if extractedCosmetics.isEmpty == false {
            let payload: [[String: Any]] = extractedCosmetics.map { cosmetic in
                ["s": cosmetic.selector, "d": cosmetic.domains]
            }
            domainCosmeticsData = try JSONSerialization.data(
                withJSONObject: payload,
                options: [.sortedKeys]
            )
        }
        let advanced: AdvancedBlockingGenerationDescriptor?
        if advancedRules.isEmpty {
            // The engine artifacts only exist for converted advanced rules;
            // without them the extracted cosmetics stay in the Safari lists.
            advanced = nil
        } else {
            let safariVersion = SafariVersion.autodetect()
            try await Task.detached(priority: .utility) {
                let extensionRuntime = try WebExtension(
                    containerURL: bundleURL,
                    version: safariVersion
                )
                _ = try extensionRuntime.buildFilterEngine(
                    rules: advancedRules
                )
            }.value
            let urlCleaningArtifact = try SumiRemoveParamRuleBuilder
                .writeRules(
                    from: sources.map(\.fileURL),
                    to: webExtensionDirectory.appendingPathComponent(
                        "removeparam.json"
                    )
                )
            var domainCosmeticsArtifact: AdvancedBlockingGenerationDescriptor
                .Artifact?
            if let domainCosmeticsData {
                let path = webExtensionDirectory.appendingPathComponent(
                    "cosmetic-domains.json"
                )
                try domainCosmeticsData.write(to: path, options: .atomic)
                domainCosmeticsArtifact = AdvancedBlockingGenerationDescriptor
                    .Artifact(
                        role: .domainCosmeticRules,
                        relativePath: AdblockCosmeticDomainIndex
                            .artifactRelativePath,
                        hash: Self.hash(domainCosmeticsData),
                        byteSize: domainCosmeticsData.count
                    )
            }
            advanced = try Self.advancedDescriptor(
                in: bundleURL,
                ruleCount: advancedRules.split(separator: "\n").count,
                urlCleaningArtifact: urlCleaningArtifact,
                domainCosmeticsArtifact: domainCosmeticsArtifact
            )
        }
        let manifest = Self.manifest(
            sources: sources,
            shardPayloads: shardPayloads,
            advanced: advanced
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(
            to: bundleURL.appendingPathComponent(
                SumiAdblockNativeRuleBundle.manifestFileName
            ),
            options: .atomic
        )
        _ = try SumiAdblockNativeBundleReader().load(from: bundleURL)
        retainTransaction = true
        return bundleURL
    }

    func discard(_ bundleURL: URL) {
        let transactionRoot = bundleURL.deletingLastPathComponent()
            .standardizedFileURL
        let expectedRoot = buildRoot.standardizedFileURL.path + "/"
        guard transactionRoot.path.hasPrefix(expectedRoot),
              transactionRoot.deletingLastPathComponent().standardizedFileURL
                == buildRoot.standardizedFileURL
        else {
            return
        }
        try? fileManager.removeItem(at: transactionRoot)
    }

    private static func removeAbandonedTransactions(
        in buildRoot: URL,
        fileManager: FileManager
    ) {
        let root = buildRoot.standardizedFileURL
        do {
            let children = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isSymbolicLinkKey]
            )
            for child in children where
                UUID(uuidString: child.lastPathComponent) != nil
                    && child.deletingLastPathComponent().standardizedFileURL
                        == root {
                let values = try child.resourceValues(
                    forKeys: [.isSymbolicLinkKey]
                )
                guard values.isSymbolicLink != true else { continue }
                try fileManager.removeItem(at: child)
            }
        } catch {}
    }

    private func download(
        _ lists: [SumiFilterListCatalog.List],
        to directory: URL
    ) async throws -> [Source] {
        var sources: [Source] = []
        sources.reserveCapacity(lists.count)
        for list in lists {
            let data = try await fetch(list.url)
            guard data.isEmpty == false else {
                throw SumiSelectedFilterBundleBuilderError.emptyList(
                    list.displayName
                )
            }
            let fileURL = directory.appendingPathComponent("\(list.id).txt")
            try data.write(to: fileURL, options: .atomic)
            sources.append(Source(
                list: list,
                fileURL: fileURL,
                hash: Self.hash(data),
                byteCount: data.count,
                ruleCount: Self.ruleCount(data)
            ))
        }
        return sources
    }

    private static func fetchList(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              data.isEmpty == false
        else {
            throw SumiSelectedFilterBundleBuilderError.invalidResponse(url)
        }
        return data
    }

    private static func distribute(_ sources: [Source]) -> [[Source]] {
        var slots = Array(repeating: [Source](), count: slotTypes.count)
        var totals = Array(repeating: 0, count: slotTypes.count)
        for source in sources.sorted(by: {
            if $0.ruleCount != $1.ruleCount {
                return $0.ruleCount > $1.ruleCount
            }
            return $0.list.id < $1.list.id
        }) {
            let slot = totals.indices.min {
                (totals[$0], $0) < (totals[$1], $1)
            } ?? 0
            slots[slot].append(source)
            totals[slot] += source.ruleCount
        }
        return slots
    }

    private static func groupedRules(
        from sources: [Source],
        assignments: [[Source]]
    ) throws -> [[String]] {
        let defaultTypes = Dictionary(uniqueKeysWithValues:
            assignments.enumerated().flatMap { slot, sources in
                sources.map { ($0.list.id, slotTypes[slot][0]) }
            }
        )
        let batches = try sources.map { source in
            let content = try String(contentsOf: source.fileURL, encoding: .utf8)
            return (
                defaultTypes[source.list.id] ?? .general,
                content.components(separatedBy: .newlines)
            )
        }
        let grouped = AffinityRulesGrouper.group(rules: batches)
        return slotTypes.map { types in
            var seen = Set<String>()
            return types.flatMap { grouped[$0] ?? [] }
                .filter { seen.insert($0).inserted }
        }
    }

    private static func convert(
        rules: [String],
        safariVersion: SafariVersion
    ) -> Conversion {
        let result = ContentBlockerConverter().convertArray(
            rules: rules,
            safariVersion: safariVersion,
            advancedBlocking: true
        )
        return Conversion(
            json: Data((result.safariRulesJSON + "\n").utf8),
            safariRuleCount: result.safariRulesCount,
            advancedRules: result.advancedRulesText ?? "",
            discardedRuleCount: result.discardedSafariRules,
            domainCosmetics: []
        )
    }

    /// Splits `css-display-none` rules with an `if-domain` trigger out of a
    /// converted Safari JSON array. Generic and `unless-domain` cosmetics stay
    /// in the WebKit list because they apply to (almost) every document and
    /// benefit from WebKit's first-paint timing.
    static func partitionDomainCosmetics(
        _ conversion: Conversion
    ) throws -> (conversion: Conversion, cosmetics: [DomainCosmetic]) {
        var extracted = [DomainCosmetic]()
        guard let rules = try JSONSerialization.jsonObject(with: conversion.json)
            as? [[String: Any]]
        else {
            return (conversion, [])
        }
        var kept = [[String: Any]]()
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
                kept.append(rule)
                continue
            }
            extracted.append(DomainCosmetic(selector: selector, domains: domains))
        }
        guard extracted.isEmpty == false else { return (conversion, []) }
        let networkData = try JSONSerialization.data(withJSONObject: kept)
        let partitioned = Conversion(
            json: networkData,
            safariRuleCount: kept.count,
            advancedRules: conversion.advancedRules,
            discardedRuleCount: conversion.discardedRuleCount,
            domainCosmetics: extracted
        )
        return (partitioned, extracted)
    }

    private static func advancedDescriptor(
        in bundleURL: URL,
        ruleCount: Int,
        urlCleaningArtifact: SumiRemoveParamRuleBuilder.Artifact,
        domainCosmeticsArtifact: AdvancedBlockingGenerationDescriptor.Artifact?
    ) throws -> AdvancedBlockingGenerationDescriptor {
        let paths: [(AdvancedBlockingArtifactRole, String)] = [
            (.ruleStorage, ".webext/rules.bin"),
            (.engineIndex, ".webext/engine.bin"),
            (.engineMetadata, ".webext/meta.bin"),
            (.sourceRules, ".webext/rules.txt"),
        ]
        var artifacts = try paths.map { role, path in
            let data = try Data(
                contentsOf: bundleURL.appendingPathComponent(path)
            )
            return AdvancedBlockingGenerationDescriptor.Artifact(
                role: role,
                relativePath: path,
                hash: hash(data),
                byteSize: data.count
            )
        }
        artifacts.append(AdvancedBlockingGenerationDescriptor.Artifact(
            role: .urlCleaningRules,
            relativePath: ".webext/removeparam.json",
            hash: urlCleaningArtifact.hash,
            byteSize: urlCleaningArtifact.byteCount
        ))
        if let domainCosmeticsArtifact {
            artifacts.append(domainCosmeticsArtifact)
        }
        return AdvancedBlockingGenerationDescriptor(
            format: AdvancedBlockingGenerationDescriptor
                .safariConverterFormat,
            schemaVersion: 1,
            runtimeVersion: "4.3.0",
            ruleCount: ruleCount,
            artifacts: artifacts
        )
    }

    private static func manifest(
        sources: [Source],
        shardPayloads: [(relativePath: String, data: Data, ruleCount: Int)],
        advanced: AdvancedBlockingGenerationDescriptor?
    ) -> SumiAdblockNativeRuleBundleManifest {
        let seed = (
            sources.map { "\($0.list.id):\($0.hash)" }
                + shardPayloads.map { hash($0.data) }
                + (advanced?.artifacts.map(\.hash) ?? [])
        ).joined(separator: "\n")
        let generationHash = String(hash(Data(seed.utf8)).prefix(12))
        let generationID = "selected-\(generationHash)"
        let nativeShards = shardPayloads.enumerated().map { index, payload in
            let digest = hash(payload.data)
            return SumiAdblockNativeRuleBundleManifest.Shard(
                kind: "network",
                group: SumiProtectionGroupKind.adblockAdsPrivacyNetwork
                    .rawValue,
                logicalGroup: SumiProtectionGroupKind
                    .adblockAdsPrivacyNetwork.rawValue,
                relativePath: payload.relativePath,
                hash: digest,
                byteSize: payload.data.count,
                ruleCount: payload.ruleCount,
                webKitIdentifier:
                    "sumi.adblock.selected.\(generationHash).\(index + 1).\(digest.prefix(12))"
            )
        }
        let lists = sources.map {
            SumiAdblockNativeRuleBundleManifest.SourceList(
                id: $0.list.id,
                displayName: $0.list.displayName,
                hash: $0.hash,
                byteSize: $0.byteCount,
                ruleCount: $0.ruleCount,
                category: manifestCategory($0.list.category)
            )
        }
        return SumiAdblockNativeRuleBundleManifest(
            schemaVersion: 1,
            bundleId: "sumi.adblock.bundle.local.selected.\(generationHash)",
            generationId: generationID,
            profileId: SumiProtectionBundleProfile.adblock,
            lists: lists,
            shards: nativeShards,
            advancedBlocking: advanced
        )
    }

    private static func manifestCategory(
        _ category: SumiFilterListCatalog.List.Category
    ) -> AdblockFilterListCategory {
        switch category {
        case .ads, .multipurpose, .security, .experimental, .scripts, .custom:
            .baseAds
        case .privacy:
            .privacyOverlap
        case .annoyances:
            .annoyances
        case .foreign:
            .regional
        }
    }

    private static func ruleCount(_ data: Data) -> Int {
        String(decoding: data, as: UTF8.self)
            .components(separatedBy: .newlines)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter {
                $0.isEmpty == false
                    && $0.hasPrefix("!") == false
                    && $0.hasPrefix("[") == false
            }
            .count
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
