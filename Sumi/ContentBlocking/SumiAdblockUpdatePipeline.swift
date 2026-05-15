import Combine
import CryptoKit
import Foundation

enum AdblockFilterListCategory: String, Codable, CaseIterable, Sendable {
    case baseAds
    case nativeCosmeticCompatibleAds
    case annoyances
    case regional
}

struct AdblockFilterListDescriptor: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let category: AdblockFilterListCategory
    let remoteURL: URL
    let homepageURL: URL?
    let defaultEnabled: Bool
    let localeTags: [String]
    let licenseNoticeHint: String?
    let mayContainCosmeticFilters: Bool
    let isAllowedInNativeOnlyMode: Bool
}

struct AdblockFilterListRegistry: Equatable, Sendable {
    let descriptors: [AdblockFilterListDescriptor]

    init(descriptors: [AdblockFilterListDescriptor] = Self.defaultDescriptors) {
        self.descriptors = descriptors
    }

    var defaultSelectionIdentifiers: [String] {
        descriptors
            .filter(\.defaultEnabled)
            .map(\.id)
            .sorted()
    }

    func selectedDescriptors(
        selection: SumiAdblockFilterListSelection,
        locale: Locale = .autoupdatingCurrent
    ) -> [AdblockFilterListDescriptor] {
        let ids = selection.usesDefaultSelection
            ? Set(defaultSelectionIdentifiers + recommendedRegionalIdentifiers(for: locale))
            : Set(selection.identifiers)
        return descriptors
            .filter { ids.contains($0.id) }
            .sorted { $0.id < $1.id }
    }

    func recommendedRegionalIdentifiers(for locale: Locale) -> [String] {
        let candidates = [
            locale.identifier.lowercased(),
            locale.language.languageCode?.identifier.lowercased(),
            locale.region?.identifier.lowercased(),
        ].compactMap { $0 }

        return descriptors
            .filter { descriptor in
                descriptor.category == .regional
                    && descriptor.localeTags.contains { tag in
                        candidates.contains(tag.lowercased())
                    }
            }
            .prefix(1)
            .map(\.id)
    }

    static let defaultDescriptors: [AdblockFilterListDescriptor] = [
        AdblockFilterListDescriptor(
            id: "easylist",
            displayName: "EasyList",
            category: .baseAds,
            remoteURL: URL(string: "https://easylist.to/easylist/easylist.txt")!,
            homepageURL: URL(string: "https://easylist.to/"),
            defaultEnabled: true,
            localeTags: ["en"],
            licenseNoticeHint: "Fetched from EasyList; list content is maintained upstream and may have its own terms.",
            mayContainCosmeticFilters: true,
            isAllowedInNativeOnlyMode: true
        ),
        AdblockFilterListDescriptor(
            id: "easylist-without-element-hiding",
            displayName: "EasyList without element hiding",
            category: .nativeCosmeticCompatibleAds,
            remoteURL: URL(string: "https://easylist-downloads.adblockplus.org/easylist_noelemhide.txt")!,
            homepageURL: URL(string: "https://easylist.to/pages/other-supplementary-filter-lists-and-easylist-variants.html")!,
            defaultEnabled: false,
            localeTags: ["en"],
            licenseNoticeHint: "Fetched from EasyList; list content is maintained upstream and may have its own terms.",
            mayContainCosmeticFilters: false,
            isAllowedInNativeOnlyMode: true
        ),
        AdblockFilterListDescriptor(
            id: "fanboy-annoyances",
            displayName: "Fanboy's Annoyance List",
            category: .annoyances,
            remoteURL: URL(string: "https://secure.fanboy.co.nz/fanboy-annoyance.txt")!,
            homepageURL: URL(string: "https://easylist.to/")!,
            defaultEnabled: false,
            localeTags: [],
            licenseNoticeHint: "Fetched from EasyList/Fanboy upstream; list content may have its own terms.",
            mayContainCosmeticFilters: true,
            isAllowedInNativeOnlyMode: true
        ),
        AdblockFilterListDescriptor(
            id: "easylist-germany",
            displayName: "EasyList Germany",
            category: .regional,
            remoteURL: URL(string: "https://easylist.to/easylistgermany/easylistgermany.txt")!,
            homepageURL: URL(string: "https://easylist.to/pages/other-supplementary-filter-lists-and-easylist-variants.html")!,
            defaultEnabled: false,
            localeTags: ["de", "de_de", "de-at", "de-ch"],
            licenseNoticeHint: "Fetched from EasyList Germany upstream; list content may have its own terms.",
            mayContainCosmeticFilters: true,
            isAllowedInNativeOnlyMode: true
        ),
        AdblockFilterListDescriptor(
            id: "liste-fr",
            displayName: "Liste FR",
            category: .regional,
            remoteURL: URL(string: "https://easylist-downloads.adblockplus.org/liste_fr.txt")!,
            homepageURL: URL(string: "https://easylist.to/pages/other-supplementary-filter-lists-and-easylist-variants.html")!,
            defaultEnabled: false,
            localeTags: ["fr", "fr_fr", "fr-ca", "fr-be", "fr-ch"],
            licenseNoticeHint: "Fetched from Liste FR upstream; list content may have its own terms.",
            mayContainCosmeticFilters: true,
            isAllowedInNativeOnlyMode: true
        ),
        AdblockFilterListDescriptor(
            id: "ru-adlist",
            displayName: "RU AdList",
            category: .regional,
            remoteURL: URL(string: "https://easylist-downloads.adblockplus.org/advblock.txt")!,
            homepageURL: URL(string: "https://easylist.to/pages/other-supplementary-filter-lists-and-easylist-variants.html")!,
            defaultEnabled: false,
            localeTags: ["ru", "ru_ru", "uk", "uk_ua"],
            licenseNoticeHint: "Fetched from RU AdList upstream; list content may have its own terms.",
            mayContainCosmeticFilters: true,
            isAllowedInNativeOnlyMode: true
        ),
        AdblockFilterListDescriptor(
            id: "easylist-polish",
            displayName: "EasyList Polish",
            category: .regional,
            remoteURL: URL(string: "https://easylist-downloads.adblockplus.org/easylistpolish.txt")!,
            homepageURL: URL(string: "https://easylist.to/pages/other-supplementary-filter-lists-and-easylist-variants.html")!,
            defaultEnabled: false,
            localeTags: ["pl", "pl_pl"],
            licenseNoticeHint: "Fetched from EasyList Polish upstream; list content may have its own terms.",
            mayContainCosmeticFilters: true,
            isAllowedInNativeOnlyMode: true
        ),
    ]
}

struct SumiAdblockFilterListSelection: Codable, Equatable, Sendable {
    var identifiers: [String]

    static let defaultSelection = SumiAdblockFilterListSelection(identifiers: [])

    var usesDefaultSelection: Bool {
        identifiers.isEmpty
    }
}

struct AdblockFilterListHTTPMetadata: Codable, Equatable, Sendable {
    var eTag: String?
    var lastModified: String?
    var lastCheckedDate: Date?
    var lastSuccessfulDownloadDate: Date?
    var contentHash: String?
    var failureSummary: String?
}

struct AdblockRuleListGeneration: Codable, Equatable, Sendable {
    let id: String
    let createdDate: Date
}

struct AdblockCompiledGenerationManifest: Codable, Equatable, Sendable {
    struct SelectedFilterList: Codable, Equatable, Sendable {
        let id: String
        let displayName: String
        let contentHash: String
    }

    struct Group: Codable, Equatable, Sendable {
        let kind: AdblockCompiledRuleGroupKind
        let webKitIdentifier: String
        let contentHash: String
        let convertedRuleCount: Int
    }

    let schemaVersion: Int
    let activeGenerationId: String
    let createdDate: Date
    let selectedFilterLists: [SelectedFilterList]
    let webKitRuleListIdentifiers: [String]
    let groupedOutputs: [Group]
    let compilerDiagnosticsSummary: String
    let lastSuccessfulUpdateDate: Date
    let previousGenerationId: String?
}

struct AdblockUpdateDiagnostics: Error, LocalizedError, Equatable, Sendable {
    var summary: String
    var listFailures: [String: String] = [:]

    var errorDescription: String? { summary }
}

enum AdblockDownloadOutcome: Equatable, Sendable {
    case downloaded(Data, HTTPURLResponse)
    case notModified(HTTPURLResponse)
}

protocol AdblockFilterListDownloading: Sendable {
    func download(
        descriptor: AdblockFilterListDescriptor,
        previousMetadata: AdblockFilterListHTTPMetadata?
    ) async throws -> AdblockDownloadOutcome
}

struct AdblockFilterListDownloader: AdblockFilterListDownloading {
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let fetch: Fetch

    init(
        fetch: @escaping Fetch = { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw AdblockUpdateDiagnostics(summary: "Invalid HTTP response")
            }
            return (data, response)
        }
    ) {
        self.fetch = fetch
    }

    func download(
        descriptor: AdblockFilterListDescriptor,
        previousMetadata: AdblockFilterListHTTPMetadata?
    ) async throws -> AdblockDownloadOutcome {
        var request = URLRequest(url: descriptor.remoteURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        if let eTag = previousMetadata?.eTag, !eTag.isEmpty {
            request.setValue(eTag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = previousMetadata?.lastModified, !lastModified.isEmpty {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let (data, response) = try await fetch(request)
        if response.statusCode == 304 {
            return .notModified(response)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw AdblockUpdateDiagnostics(summary: "HTTP \(response.statusCode)")
        }
        guard !data.isEmpty else {
            throw AdblockUpdateDiagnostics(summary: "Downloaded list is empty")
        }
        return .downloaded(data, response)
    }
}

actor AdblockUpdateManifestStore {
    private let fileManager: FileManager
    private let rootDirectory: URL
    private let manifestURL: URL
    private let metadataURL: URL

    init(
        fileManager: FileManager = .default,
        rootDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.rootDirectory = rootDirectory ?? Self.defaultRootDirectory()
        manifestURL = self.rootDirectory.appendingPathComponent("active-generation.json")
        metadataURL = self.rootDirectory.appendingPathComponent("filter-list-http-metadata.json")
    }

    nonisolated var storageRoot: URL {
        rootDirectory
    }

    func activeManifest() throws -> AdblockCompiledGenerationManifest? {
        guard fileManager.fileExists(atPath: manifestURL.path) else { return nil }
        let data = try Data(contentsOf: manifestURL)
        return try JSONDecoder().decode(AdblockCompiledGenerationManifest.self, from: data)
    }

    func loadHTTPMetadata() throws -> [String: AdblockFilterListHTTPMetadata] {
        guard fileManager.fileExists(atPath: metadataURL.path) else { return [:] }
        let data = try Data(contentsOf: metadataURL)
        return try JSONDecoder().decode([String: AdblockFilterListHTTPMetadata].self, from: data)
    }

    func rawListData(forListIdentifier identifier: String) throws -> Data? {
        let url = rawListURL(forListIdentifier: identifier)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    func beginStaging() throws -> URL {
        let stagingRoot = rootDirectory.appendingPathComponent("Staging", isDirectory: true)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        let stagingURL = stagingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        return stagingURL
    }

    func writeRawList(_ data: Data, identifier: String, stagingDirectory: URL) throws -> URL {
        let url = stagingDirectory.appendingPathComponent("\(identifier).txt")
        try data.write(to: url, options: .atomic)
        return url
    }

    func writeCompiledGroup(_ group: AdblockCompiledRuleGroup, stagingDirectory: URL) throws -> URL {
        let url = stagingDirectory.appendingPathComponent("\(group.kind.rawValue).json")
        try Data(group.encodedContentRuleList.utf8).write(to: url, options: .atomic)
        return url
    }

    func commit(
        manifest: AdblockCompiledGenerationManifest,
        httpMetadata: [String: AdblockFilterListHTTPMetadata],
        stagedRawListURLs: [String: URL]
    ) throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let rawDirectory = rootDirectory.appendingPathComponent("RawLists", isDirectory: true)
        try fileManager.createDirectory(at: rawDirectory, withIntermediateDirectories: true)

        for (identifier, stagedURL) in stagedRawListURLs {
            let destination = rawDirectory.appendingPathComponent("\(identifier).txt")
            try replaceItem(at: destination, withItemAt: stagedURL)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try atomicWrite(encoder.encode(httpMetadata), to: metadataURL)
        try atomicWrite(encoder.encode(manifest), to: manifestURL)
    }

    func removeStagingDirectory(_ url: URL) {
        try? fileManager.removeItem(at: url)
    }

    private func rawListURL(forListIdentifier identifier: String) -> URL {
        rootDirectory
            .appendingPathComponent("RawLists", isDirectory: true)
            .appendingPathComponent("\(identifier).txt")
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: tempURL, options: .atomic)
        try replaceItem(at: url, withItemAt: tempURL)
    }

    private func replaceItem(at destination: URL, withItemAt source: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: source)
        } else {
            try fileManager.moveItem(at: source, to: destination)
        }
    }

    private static func defaultRootDirectory() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Sumi/Adblock", isDirectory: true)
    }
}

@MainActor
final class AdblockManifestRuleListProvider: SumiContentRuleListSetProviding {
    private var manifest: AdblockCompiledGenerationManifest?
    private var cosmeticMode: SumiAdblockCosmeticMode
    private let changesSubject = PassthroughSubject<Void, Never>()

    init(
        manifest: AdblockCompiledGenerationManifest?,
        cosmeticMode: SumiAdblockCosmeticMode
    ) {
        self.manifest = manifest
        self.cosmeticMode = cosmeticMode
    }

    var changesPublisher: AnyPublisher<Void, Never> {
        changesSubject.eraseToAnyPublisher()
    }

    var hasProfileSpecificRuleLists: Bool {
        false
    }

    var activeManifest: AdblockCompiledGenerationManifest? {
        manifest
    }

    func updateManifest(_ manifest: AdblockCompiledGenerationManifest?) {
        guard self.manifest != manifest else { return }
        self.manifest = manifest
        changesSubject.send(())
    }

    func updateCosmeticMode(_ cosmeticMode: SumiAdblockCosmeticMode) {
        guard self.cosmeticMode != cosmeticMode else { return }
        self.cosmeticMode = cosmeticMode
        changesSubject.send(())
    }

    func ruleListSet(profileId: UUID?) throws -> SumiTrackingRuleListSet {
        guard let manifest else { return SumiTrackingRuleListSet() }
        let allowedKinds = Self.attachedGroupKinds(for: cosmeticMode)
        let definitions = manifest.groupedOutputs
            .filter { allowedKinds.contains($0.kind) }
            .map { group in
                SumiContentRuleListDefinition(
                    name: group.webKitIdentifier,
                    encodedContentRuleList: "[]",
                    storeIdentifierOverride: group.webKitIdentifier
                )
            }
        return SumiTrackingRuleListSet(trackerDataSet: definitions)
    }

    static func attachedGroupKinds(
        for cosmeticMode: SumiAdblockCosmeticMode
    ) -> Set<AdblockCompiledRuleGroupKind> {
        switch cosmeticMode {
        case .off:
            return [.network]
        case .nativeCSS, .enhancedRuntime:
            return [.network, .nativeCosmeticCSS]
        }
    }
}

@MainActor
protocol AdblockRuleListPublishing: AnyObject, Sendable {
    func publish(
        manifest: AdblockCompiledGenerationManifest,
        definitions: [SumiContentRuleListDefinition]
    ) async throws
}

@MainActor
final class AdblockRuleListPublisher: AdblockRuleListPublishing {
    private let ruleListProvider: AdblockManifestRuleListProvider
    private let contentBlockingService: SumiContentBlockingService

    init(
        ruleListProvider: AdblockManifestRuleListProvider,
        contentBlockingService: SumiContentBlockingService
    ) {
        self.ruleListProvider = ruleListProvider
        self.contentBlockingService = contentBlockingService
    }

    func publish(
        manifest: AdblockCompiledGenerationManifest,
        definitions: [SumiContentRuleListDefinition]
    ) async throws {
        let prepared = try await contentBlockingService.prepareRuleListUpdate(ruleLists: definitions)
        ruleListProvider.updateManifest(manifest)
        contentBlockingService.commitPreparedContentBlockingUpdate(prepared)
    }
}

actor AdblockUpdateCoordinator {
    private let registry: AdblockFilterListRegistry
    private let selection: @Sendable () async -> SumiAdblockFilterListSelection
    private let isAdblockEnabled: @Sendable () async -> Bool
    private let downloader: any AdblockFilterListDownloading
    private let manifestStore: AdblockUpdateManifestStore
    private let filterCompiler: any AdblockFilterCompiling
    private let publisher: any AdblockRuleListPublishing
    private let now: @Sendable () -> Date

    init(
        registry: AdblockFilterListRegistry,
        selection: @escaping @Sendable () async -> SumiAdblockFilterListSelection,
        isAdblockEnabled: @escaping @Sendable () async -> Bool,
        downloader: any AdblockFilterListDownloading,
        manifestStore: AdblockUpdateManifestStore,
        filterCompiler: any AdblockFilterCompiling,
        publisher: any AdblockRuleListPublishing,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.registry = registry
        self.selection = selection
        self.isAdblockEnabled = isAdblockEnabled
        self.downloader = downloader
        self.manifestStore = manifestStore
        self.filterCompiler = filterCompiler
        self.publisher = publisher
        self.now = now
    }

    func updateIfEnabled(reason: String) async throws -> AdblockCompiledGenerationManifest? {
        guard await isAdblockEnabled() else { return nil }

        let selection = await selection()
        let descriptors = registry.selectedDescriptors(selection: selection)
        guard !descriptors.isEmpty else {
            throw AdblockUpdateDiagnostics(summary: "No selected Adblock filter lists")
        }

        let previousManifest = try await manifestStore.activeManifest()
        let previousMetadata = try await manifestStore.loadHTTPMetadata()
        let stagingDirectory = try await manifestStore.beginStaging()
        defer {
            Task { await manifestStore.removeStagingDirectory(stagingDirectory) }
        }

        var updatedMetadata = previousMetadata
        var stagedRawURLs = [String: URL]()
        var filterTexts = [String]()
        var selectedLists = [AdblockCompiledGenerationManifest.SelectedFilterList]()
        var failures = [String: String]()

        for descriptor in descriptors {
            do {
                let result = try await downloader.download(
                    descriptor: descriptor,
                    previousMetadata: previousMetadata[descriptor.id]
                )
                let listData: Data
                var metadata = previousMetadata[descriptor.id] ?? AdblockFilterListHTTPMetadata()
                metadata.lastCheckedDate = now()
                metadata.failureSummary = nil

                switch result {
                case .downloaded(let data, let response):
                    listData = data
                    metadata.eTag = response.value(forHTTPHeaderField: "ETag")
                    metadata.lastModified = response.value(forHTTPHeaderField: "Last-Modified")
                    metadata.lastSuccessfulDownloadDate = now()
                    metadata.contentHash = data.sumiAdblockSHA256Digest
                    let stagedURL = try await manifestStore.writeRawList(
                        data,
                        identifier: descriptor.id,
                        stagingDirectory: stagingDirectory
                    )
                    stagedRawURLs[descriptor.id] = stagedURL
                case .notModified:
                    guard let previous = try await manifestStore.rawListData(forListIdentifier: descriptor.id) else {
                        throw AdblockUpdateDiagnostics(summary: "304 without previous raw list")
                    }
                    listData = previous
                    metadata.contentHash = previous.sumiAdblockSHA256Digest
                }

                updatedMetadata[descriptor.id] = metadata
                filterTexts.append(String(decoding: listData, as: UTF8.self))
                selectedLists.append(
                    AdblockCompiledGenerationManifest.SelectedFilterList(
                        id: descriptor.id,
                        displayName: descriptor.displayName,
                        contentHash: listData.sumiAdblockSHA256Digest
                    )
                )
            } catch {
                failures[descriptor.id] = error.localizedDescription
                var metadata = previousMetadata[descriptor.id] ?? AdblockFilterListHTTPMetadata()
                metadata.lastCheckedDate = now()
                metadata.failureSummary = error.localizedDescription
                updatedMetadata[descriptor.id] = metadata
            }
        }

        if !failures.isEmpty {
            throw AdblockUpdateDiagnostics(
                summary: "Adblock update failed before compilation",
                listFailures: failures
            )
        }

        guard await isAdblockEnabled() else { return nil }

        let seed = selectedLists.map { "\($0.id):\($0.contentHash)" }.joined(separator: "|")
        let generationHash = Self.shortHash(seed)
        let generation = AdblockRuleListGeneration(
            id: "\(Self.timestampString(now()))-\(generationHash)",
            createdDate: now()
        )
        let sourceIdentifier = "sumi.adblock.\(generationHash)"

        let output: AdblockCompilationOutput
        do {
            output = try await filterCompiler.compile(
                AdblockCompilationInput(
                    sourceIdentifier: sourceIdentifier,
                    filterTexts: filterTexts,
                    selectedOutputGroups: [.network, .nativeCosmeticCSS]
                )
            )
        } catch {
            throw AdblockUpdateDiagnostics(summary: "Adblock Rust compilation failed: \(error.localizedDescription)")
        }

        guard await isAdblockEnabled() else { return nil }

        var definitions = [SumiContentRuleListDefinition]()
        var groups = [AdblockCompiledGenerationManifest.Group]()
        for group in output.groups.sorted(by: { $0.kind.rawValue < $1.kind.rawValue }) {
            _ = try await manifestStore.writeCompiledGroup(group, stagingDirectory: stagingDirectory)
            let webKitIdentifier = Self.webKitIdentifier(kind: group.kind, generationHash: generationHash)
            definitions.append(
                SumiContentRuleListDefinition(
                    name: webKitIdentifier,
                    encodedContentRuleList: group.encodedContentRuleList,
                    storeIdentifierOverride: webKitIdentifier
                )
            )
            groups.append(
                AdblockCompiledGenerationManifest.Group(
                    kind: group.kind,
                    webKitIdentifier: webKitIdentifier,
                    contentHash: group.contentHash,
                    convertedRuleCount: group.convertedRuleCount
                )
            )
        }

        let manifest = AdblockCompiledGenerationManifest(
            schemaVersion: 1,
            activeGenerationId: generation.id,
            createdDate: generation.createdDate,
            selectedFilterLists: selectedLists.sorted { $0.id < $1.id },
            webKitRuleListIdentifiers: groups.map(\.webKitIdentifier).sorted(),
            groupedOutputs: groups,
            compilerDiagnosticsSummary: Self.diagnosticsSummary(output.diagnostics),
            lastSuccessfulUpdateDate: now(),
            previousGenerationId: previousManifest?.activeGenerationId
        )

        try await publisher.publish(manifest: manifest, definitions: definitions)
        try await manifestStore.commit(
            manifest: manifest,
            httpMetadata: updatedMetadata,
            stagedRawListURLs: stagedRawURLs
        )
        return manifest
    }

    static func webKitIdentifier(
        kind: AdblockCompiledRuleGroupKind,
        generationHash: String
    ) -> String {
        switch kind {
        case .network:
            return "sumi.adblock.network.\(generationHash)"
        case .nativeCosmeticCSS:
            return "sumi.adblock.nativeCSS.\(generationHash)"
        }
    }

    static func isAdblockGeneratedWebKitIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix("sumi.adblock.network.")
            || identifier.hasPrefix("sumi.adblock.nativeCSS.")
            || identifier.hasPrefix("sumi.adblock.regional.")
    }

    private static func diagnosticsSummary(_ diagnostics: AdblockCompilationDiagnostics) -> String {
        "unsupported=\(diagnostics.unsupportedRules.count); ignored=\(diagnostics.ignoredRules.count)"
    }

    private static func timestampString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    private static func shortHash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

private extension Data {
    var sumiAdblockSHA256Digest: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
