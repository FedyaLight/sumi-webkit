import Foundation
import WebKit

enum SumiBrowsingDataTimeRange: String, CaseIterable, Identifiable {
    case last15Minutes
    case lastHour
    case last24Hours
    case last7Days
    case last4Weeks
    case allTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .last15Minutes:
            return "Last 15 min"
        case .lastHour:
            return "Last hour"
        case .last24Hours:
            return "Last 24 hours"
        case .last7Days:
            return "Last 7 days"
        case .last4Weeks:
            return "Last 4 weeks"
        case .allTime:
            return "All time"
        }
    }

    func historyQuery(referenceDate: Date) -> HistoryQuery {
        guard let startDate = startDate(referenceDate: referenceDate) else {
            return .rangeFilter(.all)
        }
        return .timeRange(start: startDate, end: referenceDate)
    }

    func startDate(referenceDate: Date) -> Date? {
        switch self {
        case .last15Minutes:
            return referenceDate.addingTimeInterval(-15 * 60)
        case .lastHour:
            return referenceDate.addingTimeInterval(-60 * 60)
        case .last24Hours:
            return referenceDate.addingTimeInterval(-24 * 60 * 60)
        case .last7Days:
            return referenceDate.addingTimeInterval(-7 * 24 * 60 * 60)
        case .last4Weeks:
            return referenceDate.addingTimeInterval(-28 * 24 * 60 * 60)
        case .allTime:
            return nil
        }
    }
}

enum SumiBrowsingDataRetentionPeriod: Int, CaseIterable, Identifiable, Codable, Hashable {
    case off = 0
    case oneDay = 1
    case sevenDays = 7
    case thirtyDays = 30
    case ninetyDays = 90

    var id: Int { rawValue }

    var title: String {
        guard self != .off else { return "Off" }
        return rawValue == 1 ? "1 day" : "\(rawValue) days"
    }

    var isEnabled: Bool {
        self != .off
    }

    static let defaultPeriod: Self = .off

    static func persistedValue(_ rawValue: Int?) -> Self {
        guard let rawValue,
              let period = Self(rawValue: rawValue)
        else {
            return defaultPeriod
        }
        return period
    }

    func cutoffDate(
        referenceDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        guard isEnabled else { return referenceDate }
        return calendar.date(
            byAdding: .day,
            value: -rawValue,
            to: referenceDate
        ) ?? referenceDate.addingTimeInterval(-TimeInterval(rawValue) * 24 * 60 * 60)
    }
}

enum SumiBrowsingDataCategory: String, CaseIterable, Identifiable {
    case history
    case siteData
    case cache

    var id: String { rawValue }

    var title: String {
        switch self {
        case .history:
            return "Browsing history"
        case .siteData:
            return "Cookies and other site data"
        case .cache:
            return "Cached images and files"
        }
    }

    static var defaultSelection: Set<Self> {
        Set(allCases)
    }
}

struct SumiBrowsingDataSummary: Equatable {
    var historyVisitCount: Int = 0
    var siteDataSiteCount: Int = 0
    var cacheSiteCount: Int = 0
}

struct SumiAutomaticBrowsingDataCleanupResult: Equatable {
    var didRun = false
    var deletedHistoryVisitCount = 0
    var cleanedWebsiteDataProfileCount = 0
}

@MainActor
protocol SumiBrowsingDataFaviconCleaning: AnyObject {
    func burnAfterHistoryClear(savedLogins: Set<String>) async
    func burnDomains(
        _ domains: Set<String>,
        remainingHistoryHosts: Set<String>,
        savedLogins: Set<String>
    ) async
    func invalidateSite(domain: String, partition: SumiFaviconPartition)
}

extension SumiFaviconSystem: SumiBrowsingDataFaviconCleaning {}

@MainActor
protocol SumiBrowsingDataAppResidueCleaning: AnyObject {
    func clearSharedURLCache()
    func clearFaviconNegativeCache()
}

@MainActor
protocol SumiDestructiveBrowsingDataCleanupPreparing: AnyObject {
    func prepareForDestructiveDataCleanup(profileIDs: Set<UUID>) async
}

@MainActor
protocol SumiVisitedLinkStoreReplacing: AnyObject {
    func replaceVisitedLinks(_ urls: [URL], for profileId: UUID)
}

extension SharedVisitedLinkStoreProvider: SumiVisitedLinkStoreReplacing {}

@MainActor
final class SumiBrowsingDataAppResidueCleaner: SumiBrowsingDataAppResidueCleaning {
    static let shared = SumiBrowsingDataAppResidueCleaner()

    private static let faviconNegativeCacheKey = "favicon.resolver.negativeCache.v1"
    private let urlCache: URLCache
    private let userDefaults: UserDefaults

    init(
        urlCache: URLCache = .shared,
        userDefaults: UserDefaults = .standard
    ) {
        self.urlCache = urlCache
        self.userDefaults = userDefaults
    }

    func clearSharedURLCache() {
        urlCache.removeAllCachedResponses()
    }

    func clearFaviconNegativeCache() {
        userDefaults.removeObject(forKey: Self.faviconNegativeCacheKey)
    }
}

@MainActor
final class SumiBrowsingDataCleanupService {
    static let shared = SumiBrowsingDataCleanupService()

    private let websiteDataCleanupService: any SumiWebsiteDataCleanupServicing
    private let faviconCacheCleaner: any SumiBrowsingDataFaviconCleaning
    private let appResidueCleaner: any SumiBrowsingDataAppResidueCleaning
    private let basicAuthCredentialStore: any SumiBasicAuthCredentialCleaning
    private let visitedLinkStore: any SumiVisitedLinkStoreReplacing
    private let sharedWebsiteDataStoreProvider: @MainActor () -> WKWebsiteDataStore
    private let referenceDateProvider: @MainActor () -> Date
    weak var destructiveCleanupPreparer: (any SumiDestructiveBrowsingDataCleanupPreparing)?

    init(
        websiteDataCleanupService: (any SumiWebsiteDataCleanupServicing)? = nil,
        faviconCacheCleaner: (any SumiBrowsingDataFaviconCleaning)? = nil,
        appResidueCleaner: (any SumiBrowsingDataAppResidueCleaning)? = nil,
        basicAuthCredentialStore: (any SumiBasicAuthCredentialCleaning)? = nil,
        visitedLinkStore: (any SumiVisitedLinkStoreReplacing)? = nil,
        destructiveCleanupPreparer: (any SumiDestructiveBrowsingDataCleanupPreparing)? = nil,
        sharedWebsiteDataStoreProvider: @escaping @MainActor () -> WKWebsiteDataStore = {
            .default()
        },
        referenceDateProvider: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.websiteDataCleanupService = websiteDataCleanupService
            ?? SumiWebsiteDataCleanupService.shared
        self.faviconCacheCleaner = faviconCacheCleaner ?? SumiFaviconSystem.shared
        self.appResidueCleaner = appResidueCleaner ?? SumiBrowsingDataAppResidueCleaner.shared
        self.basicAuthCredentialStore = basicAuthCredentialStore ?? BasicAuthCredentialStore()
        self.visitedLinkStore = visitedLinkStore ?? SharedVisitedLinkStoreProvider.shared
        self.destructiveCleanupPreparer = destructiveCleanupPreparer
        self.sharedWebsiteDataStoreProvider = sharedWebsiteDataStoreProvider
        self.referenceDateProvider = referenceDateProvider
    }

    func prepareForDestructiveWebsiteDataCleanup(profileIDs: Set<UUID>) async {
        guard !profileIDs.isEmpty else { return }
        await destructiveCleanupPreparer?.prepareForDestructiveDataCleanup(
            profileIDs: profileIDs
        )
    }

    func summary(
        range: SumiBrowsingDataTimeRange,
        historyManager: HistoryManager,
        profiles: [Profile],
        includeAllProfiles: Bool
    ) async -> SumiBrowsingDataSummary {
        let regularProfiles = profiles.filter { !$0.isEphemeral }
        let targetProfiles = includeAllProfiles
            ? regularProfiles
            : regularProfiles.filter { $0.id == historyManager.currentProfileId }
        let dataStores = targetProfiles.map(\.dataStore)
        let historyProfileId = includeAllProfiles ? nil : historyManager.currentProfileId
        return await summary(
            range: range,
            historyManager: historyManager,
            profileDataStores: dataStores,
            historyProfileId: historyProfileId
        )
    }

    private func summary(
        range: SumiBrowsingDataTimeRange,
        historyManager: HistoryManager,
        profileDataStores: [WKWebsiteDataStore],
        historyProfileId: UUID?
    ) async -> SumiBrowsingDataSummary {
        let referenceDate = referenceDateProvider()
        let query = range.historyQuery(referenceDate: referenceDate)
        let historyVisitCount = await countVisits(
            matching: query,
            profileId: historyProfileId,
            referenceDate: referenceDate,
            historyManager: historyManager
        )
        let visitedDomains = normalizeDomains(
            await visitDomains(
                matching: query,
                profileId: historyProfileId,
                referenceDate: referenceDate,
                historyManager: historyManager
            )
        )

        guard range == .allTime else {
            return SumiBrowsingDataSummary(
                historyVisitCount: historyVisitCount,
                siteDataSiteCount: visitedDomains.count,
                cacheSiteCount: visitedDomains.count
            )
        }

        var siteDataDomains = Set<String>()
        var cacheDomains = Set<String>()
        for dataStore in profileDataStores {
            siteDataDomains.formUnion(
                await websiteDataDomains(
                    ofTypes: WKWebsiteDataStore.sumiSiteDataTypes,
                    includeCookies: true,
                    in: dataStore
                )
            )
            cacheDomains.formUnion(
                await websiteDataDomains(
                    ofTypes: WKWebsiteDataStore.sumiCacheDataTypes,
                    includeCookies: false,
                    in: dataStore
                )
            )
        }

        siteDataDomains.formUnion(visitedDomains)
        cacheDomains.formUnion(visitedDomains)

        return SumiBrowsingDataSummary(
            historyVisitCount: historyVisitCount,
            siteDataSiteCount: siteDataDomains.count,
            cacheSiteCount: cacheDomains.count
        )
    }

    func clear(
        range: SumiBrowsingDataTimeRange,
        categories: Set<SumiBrowsingDataCategory>,
        historyManager: HistoryManager,
        profiles: [Profile],
        includeAllProfiles: Bool
    ) async {
        let regularProfiles = profiles.filter { !$0.isEphemeral }
        let currentProfileId = historyManager.currentProfileId
        let targetProfiles = includeAllProfiles
            ? regularProfiles
            : regularProfiles.filter { $0.id == currentProfileId }

        await clear(
            range: range,
            categories: categories,
            historyManager: historyManager,
            targetProfiles: targetProfiles,
            targetProfileIds: Set(targetProfiles.map(\.id)),
            includeAllProfiles: includeAllProfiles
        )
    }

    private func clear(
        range: SumiBrowsingDataTimeRange,
        categories: Set<SumiBrowsingDataCategory>,
        historyManager: HistoryManager,
        targetProfiles: [Profile],
        targetProfileIds: Set<UUID>,
        includeAllProfiles: Bool
    ) async {
        guard !categories.isEmpty else { return }

        let referenceDate = referenceDateProvider()
        let query = range.historyQuery(referenceDate: referenceDate)
        let historyProfileId = includeAllProfiles ? nil : historyManager.currentProfileId
        let domains = normalizeDomains(
            await visitDomains(
                matching: query,
                profileId: historyProfileId,
                referenceDate: referenceDate,
                historyManager: historyManager
            )
        )

        if categories.contains(.history) {
            await clearHistory(
                query: query,
                range: range,
                historyProfileId: historyProfileId,
                targetProfileIds: targetProfileIds,
                includeAllProfiles: includeAllProfiles,
                historyManager: historyManager,
                referenceDate: referenceDate,
                domains: domains
            )
        }

        await prepareForDestructiveWebsiteDataCleanupIfNeeded(
            range: range,
            categories: categories,
            targetProfiles: targetProfiles
        )

        let dataTypes = websiteDataTypes(for: categories)
        let includesCookies = categories.contains(.siteData)
        for profile in targetProfiles {
            let siteDataFaviconDomains = await siteDataFaviconDomainsToInvalidate(
                range: range,
                categories: categories,
                domains: domains,
                dataTypes: dataTypes,
                includesCookies: includesCookies,
                dataStore: profile.dataStore
            )
            await clearWebsiteData(
                range: range,
                dataTypes: dataTypes,
                includesCookies: includesCookies,
                domains: domains,
                dataStore: profile.dataStore
            )
            invalidateSiteDataFavicons(
                domains: siteDataFaviconDomains,
                partition: SumiFaviconPartition.regular(profile.id)
            )
        }

        await clearAppLevelWebsiteResidueIfNeeded(
            range: range,
            categories: categories,
            dataTypes: dataTypes,
            includesCookies: includesCookies
        )

        if includeAllProfiles,
           range == .allTime,
           !targetProfiles.isEmpty,
           categories.contains(.siteData) || categories.contains(.cache) {
            _ = await websiteDataCleanupService.prunePersistentDataStores(
                keeping: targetProfileIds
            )
        }

        clearSavedHTTPAuthCredentialsIfNeeded(
            range: range,
            categories: categories,
            targetProfileIds: targetProfileIds
        )
        await clearFaviconCacheIfNeeded(range: range, categories: categories, domains: domains)
    }

    private func clearSavedHTTPAuthCredentialsIfNeeded(
        range: SumiBrowsingDataTimeRange,
        categories: Set<SumiBrowsingDataCategory>,
        targetProfileIds: Set<UUID>
    ) {
        guard range == .allTime,
              categories == SumiBrowsingDataCategory.defaultSelection
        else { return }

        for profileId in targetProfileIds {
            _ = basicAuthCredentialStore.deleteCredentials(
                profilePartitionId: profileId,
                isEphemeralProfile: false
            )
        }
    }

    private func clearAppLevelWebsiteResidueIfNeeded(
        range: SumiBrowsingDataTimeRange,
        categories: Set<SumiBrowsingDataCategory>,
        dataTypes: Set<String>,
        includesCookies: Bool
    ) async {
        guard range == .allTime else { return }

        if categories.contains(.cache) {
            appResidueCleaner.clearSharedURLCache()
            appResidueCleaner.clearFaviconNegativeCache()
        }

        guard categories == SumiBrowsingDataCategory.defaultSelection else { return }
        await clearWebsiteData(
            range: range,
            dataTypes: dataTypes,
            includesCookies: includesCookies,
            domains: [],
            dataStore: sharedWebsiteDataStoreProvider()
        )
    }

    private func clearHistory(
        query: HistoryQuery,
        range: SumiBrowsingDataTimeRange,
        historyProfileId: UUID?,
        targetProfileIds: Set<UUID>,
        includeAllProfiles: Bool,
        historyManager: HistoryManager,
        referenceDate: Date,
        domains: Set<String>
    ) async {
        let historyVisitCount = await countVisits(
            matching: query,
            profileId: historyProfileId,
            referenceDate: referenceDate,
            historyManager: historyManager
        )
        guard historyVisitCount > 0 else { return }

        if !includeAllProfiles, historyProfileId == historyManager.currentProfileId {
            if range == .allTime {
                await historyManager.clearAll()
            } else {
                await historyManager.delete(query: query)
            }
            return
        }

        do {
            _ = try await historyManager.store.deleteVisits(
                matching: query,
                profileId: historyProfileId,
                referenceDate: referenceDate,
                calendar: .autoupdatingCurrent
            )
            for profileId in targetProfileIds {
                try await reloadVisitedLinks(for: profileId, historyManager: historyManager)
            }
            await clearHistoryFavicons(
                range: range,
                domains: domains,
                historyProfileId: historyProfileId,
                historyManager: historyManager
            )
            await historyManager.refreshAfterExternalMutation()
        } catch {
            RuntimeDiagnostics.emit("Error clearing browsing history: \(error)")
        }
    }

    private func clearHistoryFavicons(
        range: SumiBrowsingDataTimeRange,
        domains: Set<String>,
        historyProfileId: UUID?,
        historyManager: HistoryManager
    ) async {
        let savedLogins = basicAuthCredentialStore.allCredentialHosts()

        if range == .allTime {
            await faviconCacheCleaner.burnAfterHistoryClear(savedLogins: savedLogins)
        } else if !domains.isEmpty {
            do {
                let remainingHosts = try await historyManager.store.remainingHistoryHosts(
                    forSiteDomains: domains,
                    profileId: historyProfileId
                )
                await faviconCacheCleaner.burnDomains(
                    domains,
                    remainingHistoryHosts: remainingHosts,
                    savedLogins: savedLogins
                )
            } catch {
                RuntimeDiagnostics.emit("Error clearing browsing history favicons: \(error)")
            }
        }
    }

    private func reloadVisitedLinks(
        for profileId: UUID,
        historyManager: HistoryManager
    ) async throws {
        let urls = try await historyManager.store.fetchVisitedURLs(profileId: profileId)
        visitedLinkStore.replaceVisitedLinks(urls, for: profileId)
    }

    private func clearWebsiteData(
        range: SumiBrowsingDataTimeRange,
        dataTypes: Set<String>,
        includesCookies: Bool,
        domains: Set<String>,
        dataStore: WKWebsiteDataStore
    ) async {
        guard !dataTypes.isEmpty || includesCookies else { return }

        if range == .allTime {
            if dataTypes == WKWebsiteDataStore.sumiManualFullCleanupDataTypes,
               includesCookies {
                await websiteDataCleanupService.clearAllProfileWebsiteData(in: dataStore)
                return
            }
            await websiteDataCleanupService.removeWebsiteData(
                ofTypes: dataTypes,
                modifiedSince: .distantPast,
                in: dataStore
            )
            if includesCookies {
                await websiteDataCleanupService.removeCookies(.all, in: dataStore)
            }
            return
        }

        if !domains.isEmpty {
            await websiteDataCleanupService.removeWebsiteDataForDomains(
                domains,
                ofTypes: dataTypes,
                includingCookies: includesCookies,
                in: dataStore
            )
        }

        if dataTypes.contains(WKWebsiteDataTypeSearchFieldRecentSearches),
           let startDate = range.startDate(referenceDate: referenceDateProvider()) {
            await websiteDataCleanupService.removeWebsiteData(
                ofTypes: [WKWebsiteDataTypeSearchFieldRecentSearches],
                modifiedSince: startDate,
                in: dataStore
            )
        }
    }

    private func prepareForDestructiveWebsiteDataCleanupIfNeeded(
        range: SumiBrowsingDataTimeRange,
        categories: Set<SumiBrowsingDataCategory>,
        targetProfiles: [Profile]
    ) async {
        guard range == .allTime else { return }
        guard categories.contains(.siteData) || categories.contains(.cache) else { return }
        await prepareForDestructiveWebsiteDataCleanup(
            profileIDs: Set(targetProfiles.map(\.id))
        )
    }

    private func websiteDataTypes(
        for categories: Set<SumiBrowsingDataCategory>
    ) -> Set<String> {
        var dataTypes = Set<String>()
        if categories.contains(.history) {
            dataTypes.formUnion(WKWebsiteDataStore.sumiHistoryDataTypes)
        }
        if categories.contains(.siteData) {
            dataTypes.formUnion(WKWebsiteDataStore.sumiSiteDataTypes)
        }
        if categories.contains(.cache) {
            dataTypes.formUnion(WKWebsiteDataStore.sumiCacheDataTypes)
        }
        if categories == SumiBrowsingDataCategory.defaultSelection {
            dataTypes = WKWebsiteDataStore.sumiManualFullCleanupDataTypes
        }
        return dataTypes
    }

    private func countVisits(
        matching query: HistoryQuery,
        profileId: UUID?,
        referenceDate: Date,
        historyManager: HistoryManager
    ) async -> Int {
        do {
            return try await historyManager.store.countVisits(
                matching: query,
                profileId: profileId,
                referenceDate: referenceDate,
                calendar: .autoupdatingCurrent
            )
        } catch {
            RuntimeDiagnostics.emit("Error counting browsing history: \(error)")
            return 0
        }
    }

    private func visitDomains(
        matching query: HistoryQuery,
        profileId: UUID?,
        referenceDate: Date,
        historyManager: HistoryManager
    ) async -> Set<String> {
        do {
            return try await historyManager.store.domains(
                matching: query,
                profileId: profileId,
                referenceDate: referenceDate,
                calendar: .autoupdatingCurrent
            )
        } catch {
            RuntimeDiagnostics.emit("Error loading browsing history domains: \(error)")
            return []
        }
    }

    private func clearFaviconCacheIfNeeded(
        range: SumiBrowsingDataTimeRange,
        categories: Set<SumiBrowsingDataCategory>,
        domains: Set<String>
    ) async {
        guard categories.contains(.cache) else { return }
        guard !categories.contains(.history) else { return }
        let savedLogins = basicAuthCredentialStore.allCredentialHosts()

        if range == .allTime {
            await faviconCacheCleaner.burnAfterHistoryClear(savedLogins: savedLogins)
        } else if !domains.isEmpty {
            await faviconCacheCleaner.burnDomains(
                domains,
                remainingHistoryHosts: [],
                savedLogins: savedLogins
            )
        }
    }

    private func siteDataFaviconDomainsToInvalidate(
        range: SumiBrowsingDataTimeRange,
        categories: Set<SumiBrowsingDataCategory>,
        domains: Set<String>,
        dataTypes: Set<String>,
        includesCookies: Bool,
        dataStore: WKWebsiteDataStore
    ) async -> Set<String> {
        guard categories.contains(.siteData) else { return [] }
        guard !categories.contains(.history) else { return [] }

        if range == .allTime {
            return normalizeDomains(
                await websiteDataDomains(
                    ofTypes: dataTypes,
                    includeCookies: includesCookies,
                    in: dataStore
                )
            )
        }
        return domains
    }

    private func invalidateSiteDataFavicons(
        domains: Set<String>,
        partition: SumiFaviconPartition
    ) {
        for domain in domains {
            faviconCacheCleaner.invalidateSite(domain: domain, partition: partition)
        }
    }

    private func normalizeDomains(_ domains: Set<String>) -> Set<String> {
        Set(
            domains
                .map(\.normalizedBrowsingDataDomain)
                .filter { !$0.isEmpty }
        )
    }

    private func websiteDataDomains(
        ofTypes dataTypes: Set<String>,
        includeCookies: Bool,
        in dataStore: WKWebsiteDataStore
    ) async -> Set<String> {
        let records = await websiteDataCleanupService.fetchWebsiteDataRecords(
            ofTypes: dataTypes,
            in: dataStore
        )
        var domains = Set(
            records
                .map(\.displayName)
                .map { siteDomain(for: $0) }
                .filter { !$0.isEmpty }
        )

        if includeCookies {
            let cookies = await websiteDataCleanupService.fetchCookies(in: dataStore)
            domains.formUnion(
                cookies
                    .map(\.domain)
                    .map { siteDomain(for: $0) }
                    .filter { !$0.isEmpty }
            )
        }

        return domains
    }

    private func siteDomain(for domain: String) -> String {
        let normalizedDomain = domain.normalizedBrowsingDataDomain
        guard !normalizedDomain.isEmpty else { return "" }
        guard let url = URL(string: "https://\(normalizedDomain)") else {
            return normalizedDomain
        }
        return HistoryDomainResolver.siteDomain(for: url) ?? normalizedDomain
    }
}

@MainActor
final class SumiAutomaticBrowsingDataCleanupService {
    static let shared = SumiAutomaticBrowsingDataCleanupService()

    private let websiteDataCleanupService: any SumiWebsiteDataCleanupServicing
    private let faviconCacheCleaner: any SumiBrowsingDataFaviconCleaning
    private let userDefaults: UserDefaults
    private let referenceDateProvider: @MainActor () -> Date
    private var scheduledTask: Task<Void, Never>?

    private let lastRunKey =
        "\(SumiAppIdentity.runtimeBundleIdentifier).browsingData.autoCleanup.lastRunAt"
    private let lastRetentionKey =
        "\(SumiAppIdentity.runtimeBundleIdentifier).browsingData.autoCleanup.lastRetentionDays"
    private let runInterval: TimeInterval = 24 * 60 * 60
    private let defaultDelayNanoseconds: UInt64 = 10_000_000_000

    init(
        websiteDataCleanupService: (any SumiWebsiteDataCleanupServicing)? = nil,
        faviconCacheCleaner: (any SumiBrowsingDataFaviconCleaning)? = nil,
        userDefaults: UserDefaults = .standard,
        referenceDateProvider: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.websiteDataCleanupService = websiteDataCleanupService
            ?? SumiWebsiteDataCleanupService.shared
        self.faviconCacheCleaner = faviconCacheCleaner ?? SumiFaviconSystem.shared
        self.userDefaults = userDefaults
        self.referenceDateProvider = referenceDateProvider
    }

    deinit {
        scheduledTask?.cancel()
    }

    func scheduleIfNeeded(
        retentionPeriod: SumiBrowsingDataRetentionPeriod,
        historyManager: HistoryManager,
        profiles: [Profile],
        currentProfileId: UUID?,
        force: Bool = false,
        reason: String,
        delayNanoseconds: UInt64? = nil
    ) {
        scheduledTask?.cancel()
        guard retentionPeriod.isEnabled else { return }

        scheduledTask = Task { @MainActor [weak self, weak historyManager] in
            let delay = delayNanoseconds ?? self?.defaultDelayNanoseconds ?? 0
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            var shouldForceRun = force
            while !Task.isCancelled {
                guard let self,
                      let historyManager
                else {
                    return
                }
                _ = await self.runIfNeeded(
                    retentionPeriod: retentionPeriod,
                    historyManager: historyManager,
                    profiles: profiles,
                    currentProfileId: currentProfileId,
                    force: shouldForceRun,
                    reason: reason
                )
                shouldForceRun = false
                try? await Task.sleep(nanoseconds: UInt64(self.runInterval * 1_000_000_000))
            }
        }
    }

    @discardableResult
    func runIfNeeded(
        retentionPeriod: SumiBrowsingDataRetentionPeriod,
        historyManager: HistoryManager,
        profiles: [Profile],
        currentProfileId: UUID?,
        force: Bool = false,
        reason: String
    ) async -> SumiAutomaticBrowsingDataCleanupResult {
        guard retentionPeriod.isEnabled else {
            return SumiAutomaticBrowsingDataCleanupResult()
        }

        let referenceDate = referenceDateProvider()
        guard force || shouldRun(
            retentionPeriod: retentionPeriod,
            referenceDate: referenceDate
        ) else {
            return SumiAutomaticBrowsingDataCleanupResult()
        }

        let result = await runCleanup(
            retentionPeriod: retentionPeriod,
            historyManager: historyManager,
            profiles: profiles,
            currentProfileId: currentProfileId,
            referenceDate: referenceDate,
            reason: reason
        )
        userDefaults.set(referenceDate, forKey: lastRunKey)
        userDefaults.set(retentionPeriod.rawValue, forKey: lastRetentionKey)
        return result
    }

    private func shouldRun(
        retentionPeriod: SumiBrowsingDataRetentionPeriod,
        referenceDate: Date
    ) -> Bool {
        if userDefaults.integer(forKey: lastRetentionKey) != retentionPeriod.rawValue {
            return true
        }
        guard let lastRun = userDefaults.object(forKey: lastRunKey) as? Date else {
            return true
        }
        return referenceDate.timeIntervalSince(lastRun) >= runInterval
    }

    private func runCleanup(
        retentionPeriod: SumiBrowsingDataRetentionPeriod,
        historyManager: HistoryManager,
        profiles: [Profile],
        currentProfileId: UUID?,
        referenceDate: Date,
        reason: String
    ) async -> SumiAutomaticBrowsingDataCleanupResult {
        let cutoffDate = retentionPeriod.cutoffDate(referenceDate: referenceDate)
        let query = HistoryQuery.timeRange(start: .distantPast, end: cutoffDate)
        var result = SumiAutomaticBrowsingDataCleanupResult(didRun: true)

        for profile in profiles where !profile.isEphemeral {
            result.deletedHistoryVisitCount += await deleteExpiredHistory(
                query: query,
                profile: profile,
                currentProfileId: currentProfileId,
                historyManager: historyManager,
                referenceDate: referenceDate
            )

            await websiteDataCleanupService.removeWebsiteData(
                ofTypes: WKWebsiteDataStore.sumiAutomaticCleanupDataTypes,
                modifiedSince: .distantPast,
                in: profile.dataStore
            )
            result.cleanedWebsiteDataProfileCount += 1
        }

        RuntimeDiagnostics.debug(
            "Automatic browsing data cleanup completed reason=\(reason) retention=\(retentionPeriod.rawValue)d historyDeleted=\(result.deletedHistoryVisitCount) profiles=\(result.cleanedWebsiteDataProfileCount).",
            category: "BrowsingDataCleanup"
        )
        return result
    }

    private func deleteExpiredHistory(
        query: HistoryQuery,
        profile: Profile,
        currentProfileId: UUID?,
        historyManager: HistoryManager,
        referenceDate: Date
    ) async -> Int {
        do {
            let oldVisitCount = try await historyManager.store.countVisits(
                matching: query,
                profileId: profile.id,
                referenceDate: referenceDate,
                calendar: .autoupdatingCurrent
            )
            guard oldVisitCount > 0 else { return 0 }

            if profile.id == currentProfileId {
                await historyManager.delete(query: query)
                return oldVisitCount
            }

            let oldDomains = try await historyManager.store.domains(
                matching: query,
                profileId: profile.id,
                referenceDate: referenceDate,
                calendar: .autoupdatingCurrent
            )
            let deletedCount = try await historyManager.store.deleteVisits(
                matching: query,
                profileId: profile.id,
                referenceDate: referenceDate,
                calendar: .autoupdatingCurrent
            )
            if deletedCount > 0, !oldDomains.isEmpty {
                let remainingHosts = try await historyManager.store.remainingHistoryHosts(
                    forSiteDomains: oldDomains,
                    profileId: profile.id
                )
                await faviconCacheCleaner.burnDomains(
                    oldDomains,
                    remainingHistoryHosts: remainingHosts,
                    savedLogins: BasicAuthCredentialStore().allCredentialHosts()
                )
            }
            return deletedCount
        } catch {
            RuntimeDiagnostics.emit("Error during automatic browsing data cleanup: \(error)")
            return 0
        }
    }
}

private extension String {
    var normalizedBrowsingDataDomain: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingPrefix(".")
            .lowercased()
    }

    func trimmingPrefix(_ prefix: String) -> String {
        guard hasPrefix(prefix) else { return self }
        return String(dropFirst(prefix.count))
    }
}
