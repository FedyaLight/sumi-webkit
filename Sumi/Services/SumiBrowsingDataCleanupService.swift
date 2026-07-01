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

@MainActor
final class SumiBrowsingDataAppResidueCleaner: SumiBrowsingDataAppResidueCleaning {
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
    let websiteDataCleanupService: any SumiWebsiteDataCleanupServicing
    private let localCleanupOwner: SumiBrowsingDataLocalCleanupOwner
    private let domainInventory: SumiBrowsingDataDomainInventory
    private let manualWebsiteDataCleanupOwner: SumiManualWebsiteDataCleanupOwner
    private let referenceDateProvider: @MainActor () -> Date
    var destructiveCleanupPreparer: (any SumiDestructiveBrowsingDataCleanupPreparing)? {
        get { manualWebsiteDataCleanupOwner.destructiveCleanupPreparer }
        set { manualWebsiteDataCleanupOwner.destructiveCleanupPreparer = newValue }
    }

    init(
        websiteDataCleanupService: any SumiWebsiteDataCleanupServicing,
        faviconCacheCleaner: any SumiBrowsingDataFaviconCleaning,
        appResidueCleaner: any SumiBrowsingDataAppResidueCleaning,
        basicAuthCredentialStore: any SumiBasicAuthCredentialCleaning,
        visitedLinkStore: any SumiVisitedLinkStoreReplacing,
        destructiveCleanupPreparer: (any SumiDestructiveBrowsingDataCleanupPreparing)? = nil,
        sharedWebsiteDataStoreProvider: @escaping @MainActor () -> WKWebsiteDataStore = {
            .default()
        },
        referenceDateProvider: @escaping @MainActor () -> Date = { Date() }
    ) {
        let domainInventory = SumiBrowsingDataDomainInventory(
            websiteDataCleanupService: websiteDataCleanupService
        )
        self.websiteDataCleanupService = websiteDataCleanupService
        self.localCleanupOwner = SumiBrowsingDataLocalCleanupOwner(
            faviconCacheCleaner: faviconCacheCleaner,
            basicAuthCredentialStore: basicAuthCredentialStore,
            visitedLinkStore: visitedLinkStore
        )
        self.domainInventory = domainInventory
        self.manualWebsiteDataCleanupOwner = SumiManualWebsiteDataCleanupOwner(
            websiteDataCleanupService: websiteDataCleanupService,
            appResidueCleaner: appResidueCleaner,
            domainInventory: domainInventory,
            destructiveCleanupPreparer: destructiveCleanupPreparer,
            sharedWebsiteDataStoreProvider: sharedWebsiteDataStoreProvider,
            referenceDateProvider: referenceDateProvider
        )
        self.referenceDateProvider = referenceDateProvider
    }

    func prepareForDestructiveWebsiteDataCleanup(profileIDs: Set<UUID>) async {
        await manualWebsiteDataCleanupOwner.prepareForDestructiveWebsiteDataCleanup(
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
        let historyVisitCount = await domainInventory.countVisits(
            matching: query,
            profileId: historyProfileId,
            referenceDate: referenceDate,
            historyManager: historyManager
        )
        let visitedDomains = domainInventory.normalizeDomains(
            await domainInventory.visitDomains(
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
                await domainInventory.websiteDataDomains(
                    ofTypes: WKWebsiteDataStore.sumiSiteDataTypes,
                    includeCookies: true,
                    in: dataStore
                )
            )
            cacheDomains.formUnion(
                await domainInventory.websiteDataDomains(
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
        let domains = domainInventory.normalizeDomains(
            await domainInventory.visitDomains(
                matching: query,
                profileId: historyProfileId,
                referenceDate: referenceDate,
                historyManager: historyManager
            )
        )

        if categories.contains(.history) {
            await localCleanupOwner.clearHistory(SumiBrowsingHistoryCleanupRequest(
                query: query,
                range: range,
                historyProfileId: historyProfileId,
                targetProfileIds: targetProfileIds,
                includeAllProfiles: includeAllProfiles,
                historyManager: historyManager,
                referenceDate: referenceDate,
                domains: domains
            ))
        }

        await manualWebsiteDataCleanupOwner.prepareForDestructiveWebsiteDataCleanupIfNeeded(
            range: range,
            categories: categories,
            targetProfiles: targetProfiles
        )

        let dataTypes = manualWebsiteDataCleanupOwner.websiteDataTypes(for: categories)
        let includesCookies = categories.contains(.siteData)
        for profile in targetProfiles {
            let siteDataFaviconDomains = await manualWebsiteDataCleanupOwner.clearProfileWebsiteData(
                range: range,
                categories: categories,
                domains: domains,
                dataTypes: dataTypes,
                includesCookies: includesCookies,
                dataStore: profile.dataStore
            )
            localCleanupOwner.invalidateSiteDataFavicons(
                domains: siteDataFaviconDomains,
                partition: SumiFaviconPartition.regular(profile.id)
            )
        }

        await manualWebsiteDataCleanupOwner.clearAppLevelWebsiteResidueIfNeeded(
            range: range,
            categories: categories,
            dataTypes: dataTypes,
            includesCookies: includesCookies
        )

        await manualWebsiteDataCleanupOwner.prunePersistentDataStoresIfNeeded(
            range: range,
            categories: categories,
            targetProfiles: targetProfiles,
            targetProfileIds: targetProfileIds,
            includeAllProfiles: includeAllProfiles
        )

        localCleanupOwner.clearSavedHTTPAuthCredentialsIfNeeded(
            range: range,
            categories: categories,
            targetProfileIds: targetProfileIds
        )
        await localCleanupOwner.clearFaviconCacheIfNeeded(
            range: range,
            categories: categories,
            domains: domains
        )
    }
}

@MainActor
final class SumiAutomaticBrowsingDataCleanupService {
    private let websiteDataCleanupService: any SumiWebsiteDataCleanupServicing
    private let faviconCacheCleaner: any SumiBrowsingDataFaviconCleaning
    private let basicAuthCredentialStore: any SumiBasicAuthCredentialCleaning
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
        websiteDataCleanupService: any SumiWebsiteDataCleanupServicing,
        faviconCacheCleaner: any SumiBrowsingDataFaviconCleaning,
        basicAuthCredentialStore: any SumiBasicAuthCredentialCleaning,
        userDefaults: UserDefaults = .standard,
        referenceDateProvider: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.websiteDataCleanupService = websiteDataCleanupService
        self.faviconCacheCleaner = faviconCacheCleaner
        self.basicAuthCredentialStore = basicAuthCredentialStore
        self.userDefaults = userDefaults
        self.referenceDateProvider = referenceDateProvider
    }

    deinit {
        scheduledTask?.cancel()
    }

    func scheduleIfNeeded(_ request: SumiBrowsingDataCleanupScheduleRequest) {
        scheduledTask?.cancel()
        guard request.retentionPeriod.isEnabled else { return }

        scheduledTask = Task { @MainActor [weak self, weak historyManager = request.historyManager] in
            let delay = request.delayNanoseconds ?? self?.defaultDelayNanoseconds ?? 0
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            var shouldForceRun = request.force
            while !Task.isCancelled {
                guard let self,
                      let historyManager
                else {
                    return
                }
                _ = await self.runIfNeeded(
                    retentionPeriod: request.retentionPeriod,
                    historyManager: historyManager,
                    profiles: request.profiles,
                    currentProfileId: request.currentProfileId,
                    force: shouldForceRun,
                    reason: request.reason
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
                    savedLogins: basicAuthCredentialStore.allCredentialHosts()
                )
            }
            return deletedCount
        } catch {
            RuntimeDiagnostics.emit("Error during automatic browsing data cleanup: \(error)")
            return 0
        }
    }
}
