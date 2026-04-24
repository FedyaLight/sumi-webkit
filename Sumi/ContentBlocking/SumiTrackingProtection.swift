import Combine
import Common
import CryptoKit
import Foundation
@preconcurrency import TrackerRadarKit

enum SumiTrackingProtectionGlobalMode: String, Codable, CaseIterable, Sendable {
    case enabled
    case disabled
}

enum SumiTrackingProtectionSiteOverride: String, Codable, CaseIterable, Sendable {
    case inherit
    case enabled
    case disabled

    var displayTitle: String {
        switch self {
        case .inherit:
            return "Use Global Setting"
        case .enabled:
            return "Enabled"
        case .disabled:
            return "Disabled"
        }
    }
}

enum SumiTrackingProtectionEffectiveSource: Equatable, Sendable {
    case global
    case siteOverride(SumiTrackingProtectionSiteOverride)
}

struct SumiTrackingProtectionEffectivePolicy: Equatable, Sendable {
    let host: String?
    let isEnabled: Bool
    let source: SumiTrackingProtectionEffectiveSource
}

struct SumiTrackingProtectionPolicy: Equatable, Sendable {
    let globalMode: SumiTrackingProtectionGlobalMode
    let enabledSiteHosts: [String]
    let disabledSiteHosts: [String]

    var requiresRuleList: Bool {
        globalMode == .enabled || !enabledSiteHosts.isEmpty
    }

    var isFullyDisabled: Bool {
        globalMode == .disabled && enabledSiteHosts.isEmpty
    }
}

@MainActor
final class SumiTrackingProtectionSettings: ObservableObject {
    static let shared = SumiTrackingProtectionSettings()

    private enum DefaultsKey {
        static let globalMode = "settings.trackingProtection.globalMode"
        static let siteOverrides = "settings.trackingProtection.siteOverrides"
    }

    @Published private(set) var globalMode: SumiTrackingProtectionGlobalMode
    @Published private(set) var siteOverrides: [String: SumiTrackingProtectionSiteOverride]

    private let userDefaults: UserDefaults
    private let tld: TLD
    private let changesSubject = PassthroughSubject<Void, Never>()

    var changesPublisher: AnyPublisher<Void, Never> {
        changesSubject.eraseToAnyPublisher()
    }

    init(userDefaults: UserDefaults = .standard, tld: TLD = TLD()) {
        self.userDefaults = userDefaults
        self.tld = tld

        if let rawMode = userDefaults.string(forKey: DefaultsKey.globalMode),
           let mode = SumiTrackingProtectionGlobalMode(rawValue: rawMode) {
            globalMode = mode
        } else {
            globalMode = .disabled
        }

        siteOverrides = Self.loadSiteOverrides(from: userDefaults)
    }

    var policy: SumiTrackingProtectionPolicy {
        let enabledHosts = siteOverrides
            .filter { $0.value == .enabled }
            .map(\.key)
            .sorted()
        let disabledHosts = siteOverrides
            .filter { $0.value == .disabled }
            .map(\.key)
            .sorted()
        return SumiTrackingProtectionPolicy(
            globalMode: globalMode,
            enabledSiteHosts: enabledHosts,
            disabledSiteHosts: disabledHosts
        )
    }

    var sortedSiteOverrides: [(host: String, override: SumiTrackingProtectionSiteOverride)] {
        siteOverrides
            .map { ($0.key, $0.value) }
            .sorted { lhs, rhs in lhs.0.localizedCaseInsensitiveCompare(rhs.0) == .orderedAscending }
    }

    func setGlobalMode(_ mode: SumiTrackingProtectionGlobalMode) {
        guard globalMode != mode else { return }
        globalMode = mode
        userDefaults.set(mode.rawValue, forKey: DefaultsKey.globalMode)
        changesSubject.send(())
    }

    func setSiteOverride(_ override: SumiTrackingProtectionSiteOverride, for url: URL?) {
        guard let host = normalizedHost(for: url) else { return }
        setSiteOverride(override, forNormalizedHost: host)
    }

    func setSiteOverride(_ override: SumiTrackingProtectionSiteOverride, forUserInput input: String) -> Bool {
        guard let host = normalizedHost(fromUserInput: input) else { return false }
        setSiteOverride(override, forNormalizedHost: host)
        return true
    }

    func removeSiteOverride(forNormalizedHost host: String) {
        setSiteOverride(.inherit, forNormalizedHost: host)
    }

    func override(for url: URL?) -> SumiTrackingProtectionSiteOverride {
        guard let host = normalizedHost(for: url) else { return .inherit }
        return siteOverrides[host] ?? .inherit
    }

    func resolve(for url: URL?) -> SumiTrackingProtectionEffectivePolicy {
        let host = normalizedHost(for: url)
        if let host, let siteOverride = siteOverrides[host] {
            switch siteOverride {
            case .enabled:
                return SumiTrackingProtectionEffectivePolicy(
                    host: host,
                    isEnabled: true,
                    source: .siteOverride(.enabled)
                )
            case .disabled:
                return SumiTrackingProtectionEffectivePolicy(
                    host: host,
                    isEnabled: false,
                    source: .siteOverride(.disabled)
                )
            case .inherit:
                break
            }
        }

        return SumiTrackingProtectionEffectivePolicy(
            host: host,
            isEnabled: globalMode == .enabled,
            source: .global
        )
    }

    func normalizedHost(for url: URL?) -> String? {
        guard let rawHost = url?.host else { return nil }
        return normalizedHost(fromRawHost: rawHost)
    }

    func normalizedHost(fromUserInput input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.host != nil {
            return normalizedHost(for: url)
        }
        if let url = URL(string: "https://\(trimmed)"), url.host != nil {
            return normalizedHost(for: url)
        }
        return normalizedHost(fromRawHost: trimmed)
    }

    private func setSiteOverride(
        _ override: SumiTrackingProtectionSiteOverride,
        forNormalizedHost host: String
    ) {
        var updated = siteOverrides
        if override == .inherit {
            updated.removeValue(forKey: host)
        } else {
            updated[host] = override
        }
        guard updated != siteOverrides else { return }
        siteOverrides = updated
        persistSiteOverrides()
        changesSubject.send(())
    }

    private func normalizedHost(fromRawHost rawHost: String) -> String? {
        let host = rawHost
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        guard !host.isEmpty else { return nil }
        return tld.eTLDplus1(host) ?? host
    }

    private func persistSiteOverrides() {
        let encoded = siteOverrides.mapValues(\.rawValue)
        guard let data = try? JSONEncoder().encode(encoded) else { return }
        userDefaults.set(data, forKey: DefaultsKey.siteOverrides)
    }

    private static func loadSiteOverrides(
        from userDefaults: UserDefaults
    ) -> [String: SumiTrackingProtectionSiteOverride] {
        guard
            let data = userDefaults.data(forKey: DefaultsKey.siteOverrides),
            let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }

        return decoded.reduce(into: [:]) { result, entry in
            guard let override = SumiTrackingProtectionSiteOverride(rawValue: entry.value),
                  override != .inherit
            else { return }
            result[entry.key] = override
        }
    }
}

enum SumiTrackingProtectionDataSource: String, Sendable {
    case bundled = "Bundled"
    case downloaded = "Downloaded"
}

struct SumiTrackingProtectionDataMetadata: Equatable, Sendable {
    var currentSource: SumiTrackingProtectionDataSource
    var lastSuccessfulUpdateDate: Date?
    var lastUpdateError: String?
}

struct SumiTrackerDataSet {
    let trackerData: TrackerData
    let encodedTrackerData: String
    let etag: String
    let source: SumiTrackingProtectionDataSource
}

protocol SumiBundledTrackerDataProviding: Sendable {
    var embeddedDataEtag: String { get }
    var embeddedDataSHA: String { get }
    func embeddedData() throws -> Data
}

struct SumiBundleTrackerDataProvider: SumiBundledTrackerDataProviding {
    let embeddedDataEtag = "\"54459ec6535c6508e5a529d96f20eb1f\""
    let embeddedDataSHA = "0243a5443fc87652f22322c9d217cff547c2d808dd9f073cde8d607bf13a1dd8"

    func embeddedData() throws -> Data {
        guard let url = Bundle.main.url(forResource: "trackerData", withExtension: "json") else {
            throw SumiTrackingProtectionDataError.bundledTrackerDataMissing
        }
        return try Data(contentsOf: url)
    }
}

enum SumiTrackingProtectionDataError: LocalizedError {
    case bundledTrackerDataMissing
    case downloadedTrackerDataMissing
    case invalidDownloadedStatus(Int)
    case invalidHTTPResponse

    var errorDescription: String? {
        switch self {
        case .bundledTrackerDataMissing:
            return "Bundled tracker data is missing."
        case .downloadedTrackerDataMissing:
            return "Downloaded tracker data is missing."
        case .invalidDownloadedStatus(let status):
            return "Tracker data update failed with HTTP status \(status)."
        case .invalidHTTPResponse:
            return "Tracker data update did not return an HTTP response."
        }
    }
}

@MainActor
final class SumiTrackingProtectionDataStore: ObservableObject {
    static let shared = SumiTrackingProtectionDataStore()

    private enum DefaultsKey {
        static let downloadedETag = "settings.trackingProtection.trackerData.downloadedEtag"
        static let lastSuccessfulUpdateDate = "settings.trackingProtection.trackerData.lastSuccessfulUpdateDate"
        static let lastUpdateError = "settings.trackingProtection.trackerData.lastUpdateError"
    }

    @Published private(set) var metadata: SumiTrackingProtectionDataMetadata
    @Published private(set) var isUpdating = false

    private let userDefaults: UserDefaults
    private let fileManager: FileManager
    private let storageDirectory: URL
    private let bundledProvider: SumiBundledTrackerDataProviding
    private let changesSubject = PassthroughSubject<Void, Never>()

    var changesPublisher: AnyPublisher<Void, Never> {
        changesSubject.eraseToAnyPublisher()
    }

    init(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        storageDirectory: URL? = nil,
        bundledProvider: SumiBundledTrackerDataProviding = SumiBundleTrackerDataProvider()
    ) {
        self.userDefaults = userDefaults
        self.fileManager = fileManager
        self.storageDirectory = storageDirectory ?? Self.defaultStorageDirectory()
        self.bundledProvider = bundledProvider
        metadata = Self.loadMetadata(
            userDefaults: userDefaults,
            fileManager: fileManager,
            downloadedDataURL: (storageDirectory ?? Self.defaultStorageDirectory())
                .appendingPathComponent("trackerData.json")
        )
    }

    var downloadedDataURL: URL {
        storageDirectory.appendingPathComponent("trackerData.json")
    }

    var downloadedETag: String? {
        userDefaults.string(forKey: DefaultsKey.downloadedETag)
    }

    func loadActiveDataSet() throws -> SumiTrackerDataSet {
        if let downloadedETag,
           fileManager.fileExists(atPath: downloadedDataURL.path),
           let downloadedData = try? Data(contentsOf: downloadedDataURL),
           let trackerData = try? JSONDecoder().decode(TrackerData.self, from: downloadedData),
           let encodedTrackerData = String(data: downloadedData, encoding: .utf8) {
            return SumiTrackerDataSet(
                trackerData: trackerData,
                encodedTrackerData: encodedTrackerData,
                etag: downloadedETag,
                source: .downloaded
            )
        }

        let bundledData = try bundledProvider.embeddedData()
        let trackerData = try JSONDecoder().decode(TrackerData.self, from: bundledData)
        return SumiTrackerDataSet(
            trackerData: trackerData,
            encodedTrackerData: String(data: bundledData, encoding: .utf8) ?? "{}",
            etag: bundledProvider.embeddedDataEtag,
            source: .bundled
        )
    }

    func storeDownloadedData(_ data: Data, etag: String, date: Date = Date()) throws {
        _ = try JSONDecoder().decode(TrackerData.self, from: data)
        try fileManager.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true
        )
        try data.write(to: downloadedDataURL, options: .atomic)
        userDefaults.set(etag, forKey: DefaultsKey.downloadedETag)
        userDefaults.set(date, forKey: DefaultsKey.lastSuccessfulUpdateDate)
        userDefaults.removeObject(forKey: DefaultsKey.lastUpdateError)
        reloadMetadata()
        changesSubject.send(())
    }

    func noteSuccessfulNotModifiedUpdate(date: Date = Date()) {
        userDefaults.set(date, forKey: DefaultsKey.lastSuccessfulUpdateDate)
        userDefaults.removeObject(forKey: DefaultsKey.lastUpdateError)
        reloadMetadata()
    }

    func recordUpdateError(_ error: Error) {
        userDefaults.set(error.localizedDescription, forKey: DefaultsKey.lastUpdateError)
        reloadMetadata()
    }

    func resetToBundled() {
        try? fileManager.removeItem(at: downloadedDataURL)
        userDefaults.removeObject(forKey: DefaultsKey.downloadedETag)
        userDefaults.removeObject(forKey: DefaultsKey.lastSuccessfulUpdateDate)
        userDefaults.removeObject(forKey: DefaultsKey.lastUpdateError)
        reloadMetadata()
        changesSubject.send(())
    }

    func updateTrackerData(using updater: SumiTrackerDataUpdater = SumiTrackerDataUpdater()) async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }

        do {
            let result = try await updater.updateTrackerData(currentETag: downloadedETag ?? bundledProvider.embeddedDataEtag)
            switch result {
            case .downloaded(let data, let etag, let date):
                try storeDownloadedData(data, etag: etag, date: date)
            case .notModified(let date):
                noteSuccessfulNotModifiedUpdate(date: date)
            }
        } catch {
            recordUpdateError(error)
        }
    }

    private func reloadMetadata() {
        metadata = Self.loadMetadata(
            userDefaults: userDefaults,
            fileManager: fileManager,
            downloadedDataURL: downloadedDataURL
        )
    }

    private static func loadMetadata(
        userDefaults: UserDefaults,
        fileManager: FileManager,
        downloadedDataURL: URL
    ) -> SumiTrackingProtectionDataMetadata {
        let hasDownloadedData = userDefaults.string(forKey: DefaultsKey.downloadedETag) != nil
            && fileManager.fileExists(atPath: downloadedDataURL.path)
        return SumiTrackingProtectionDataMetadata(
            currentSource: hasDownloadedData ? .downloaded : .bundled,
            lastSuccessfulUpdateDate: userDefaults.object(forKey: DefaultsKey.lastSuccessfulUpdateDate) as? Date,
            lastUpdateError: userDefaults.string(forKey: DefaultsKey.lastUpdateError)
        )
    }

    private static func defaultStorageDirectory() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Sumi/TrackingProtection", isDirectory: true)
    }
}

enum SumiTrackerDataUpdateResult: Sendable {
    case downloaded(data: Data, etag: String, date: Date)
    case notModified(date: Date)
}

struct SumiTrackerDataUpdater: Sendable {
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    static let defaultTrackerDataURL = URL(
        string: "https://staticcdn.duckduckgo.com/trackerblocking/v6/current/macos-tds.json"
    )!

    private let trackerDataURL: URL
    private let fetch: Fetch

    init(
        trackerDataURL: URL = Self.defaultTrackerDataURL,
        fetch: @escaping Fetch = { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SumiTrackingProtectionDataError.invalidHTTPResponse
            }
            return (data, httpResponse)
        }
    ) {
        self.trackerDataURL = trackerDataURL
        self.fetch = fetch
    }

    func updateTrackerData(currentETag: String?) async throws -> SumiTrackerDataUpdateResult {
        var request = URLRequest(url: trackerDataURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let currentETag, !currentETag.isEmpty {
            request.setValue(currentETag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await fetch(request)
        if response.statusCode == 304 {
            return .notModified(date: Date())
        }
        guard (200..<300).contains(response.statusCode) else {
            throw SumiTrackingProtectionDataError.invalidDownloadedStatus(response.statusCode)
        }
        _ = try JSONDecoder().decode(TrackerData.self, from: data)
        let etag = response.value(forHTTPHeaderField: "ETag") ?? data.sumiSHA256Digest
        return .downloaded(data: data, etag: etag, date: Date())
    }
}

@MainActor
protocol SumiTrackingProtectionRuleProviding: AnyObject {
    func ruleLists(for policy: SumiTrackingProtectionPolicy) throws -> [SumiContentRuleListDefinition]
}

@MainActor
final class SumiEmbeddedDDGTrackerDataRuleSource: SumiTrackingProtectionRuleProviding {
    private let dataStore: SumiTrackingProtectionDataStore

    init(dataStore: SumiTrackingProtectionDataStore? = nil) {
        self.dataStore = dataStore ?? .shared
    }

    func ruleLists(for policy: SumiTrackingProtectionPolicy) throws -> [SumiContentRuleListDefinition] {
        guard policy.requiresRuleList else { return [] }

        let dataSet = try dataStore.loadActiveDataSet()
        let builder = ContentBlockerRulesBuilder(trackerData: dataSet.trackerData)

        let rules: [ContentBlockerRule]
        switch policy.globalMode {
        case .enabled:
            rules = builder.buildRules(
                withExceptions: policy.disabledSiteHosts.map { "*\($0)" },
                andTemporaryUnprotectedDomains: nil,
                andTrackerAllowlist: []
            )
        case .disabled:
            var scopedRules = builder.buildRules(
                withExceptions: nil,
                andTemporaryUnprotectedDomains: nil,
                andTrackerAllowlist: []
            )
            if !policy.enabledSiteHosts.isEmpty {
                let enabledDomains = policy.enabledSiteHosts.map { "*\($0)" }
                let ignoreEverywhereExceptEnabledSites = ContentBlockerRulesBuilder.buildRule(
                    trigger: .trigger(
                        urlFilter: ".*",
                        unlessDomain: enabledDomains,
                        loadTypes: [.firstParty, .thirdParty]
                    ),
                    withAction: .ignorePreviousRules()
                )
                scopedRules.append(ignoreEverywhereExceptEnabledSites)
            }
            rules = scopedRules
        }

        let encodedRules = try JSONEncoder().encode(rules)
        let encodedRuleList = String(data: encodedRules, encoding: .utf8) ?? "[]"
        return [
            SumiContentRuleListDefinition(
                name: "SumiTrackingProtectionTrackerDataSet",
                encodedContentRuleList: encodedRuleList
            )
        ]
    }
}

private extension Data {
    var sumiSHA256Digest: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
