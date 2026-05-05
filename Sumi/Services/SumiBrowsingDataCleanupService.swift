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

    static var primaryRanges: [Self] {
        [.last15Minutes, .lastHour]
    }

    static var moreRanges: [Self] {
        [.last24Hours, .last7Days, .last4Weeks, .allTime]
    }

    func historyQuery(referenceDate: Date) -> HistoryQuery {
        guard let startDate = startDate(referenceDate: referenceDate) else {
            return .rangeFilter(.all)
        }
        return .timeRange(start: startDate, end: referenceDate)
    }

    private func startDate(referenceDate: Date) -> Date? {
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

    var iconName: String {
        switch self {
        case .history:
            return "clock.arrow.circlepath"
        case .siteData:
            return "network"
        case .cache:
            return "internaldrive"
        }
    }

    var chromeIconName: String? {
        switch self {
        case .siteData:
            return "cookies-fill"
        case .history, .cache:
            return nil
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

@MainActor
final class SumiBrowsingDataCleanupService {
    static let shared = SumiBrowsingDataCleanupService()

    private let websiteDataCleanupService: any SumiWebsiteDataCleanupServicing
    private let referenceDateProvider: @MainActor () -> Date

    init(
        websiteDataCleanupService: (any SumiWebsiteDataCleanupServicing)? = nil,
        referenceDateProvider: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.websiteDataCleanupService = websiteDataCleanupService
            ?? SumiWebsiteDataCleanupService.shared
        self.referenceDateProvider = referenceDateProvider
    }

    func summary(
        range: SumiBrowsingDataTimeRange,
        historyManager: HistoryManager,
        dataStore: WKWebsiteDataStore
    ) async -> SumiBrowsingDataSummary {
        let query = range.historyQuery(referenceDate: referenceDateProvider())
        let historyVisitCount = await historyManager.countVisits(matching: query)
        let visitedDomains = normalizeDomains(await historyManager.visitDomains(matching: query))

        if range == .allTime {
            let siteDataDomains = await websiteDataDomains(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                includeCookies: true,
                in: dataStore
            )
            let cacheDomains = await websiteDataDomains(
                ofTypes: WKWebsiteDataStore.sumiCacheDataTypes,
                includeCookies: false,
                in: dataStore
            )

            return SumiBrowsingDataSummary(
                historyVisitCount: historyVisitCount,
                siteDataSiteCount: siteDataDomains.count,
                cacheSiteCount: cacheDomains.count
            )
        }

        return SumiBrowsingDataSummary(
            historyVisitCount: historyVisitCount,
            siteDataSiteCount: visitedDomains.count,
            cacheSiteCount: visitedDomains.count
        )
    }

    func clear(
        range: SumiBrowsingDataTimeRange,
        categories: Set<SumiBrowsingDataCategory>,
        historyManager: HistoryManager,
        dataStore: WKWebsiteDataStore
    ) async {
        guard !categories.isEmpty else { return }

        let query = range.historyQuery(referenceDate: referenceDateProvider())
        let historyVisitCount = await historyManager.countVisits(matching: query)
        let domains = normalizeDomains(await historyManager.visitDomains(matching: query))

        if categories.contains(.history) {
            if range == .allTime {
                await historyManager.clearAll()
            } else if historyVisitCount > 0 {
                await historyManager.delete(query: query)
            }
        }

        if categories.contains(.siteData) {
            if range == .allTime {
                await websiteDataCleanupService.clearAllProfileWebsiteData(in: dataStore)
            } else if !domains.isEmpty {
                await websiteDataCleanupService.removeWebsiteDataForDomains(
                    domains,
                    ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                    includingCookies: true,
                    in: dataStore
                )
            }
        } else if categories.contains(.cache) {
            if range == .allTime {
                await websiteDataCleanupService.removeWebsiteData(
                    ofTypes: WKWebsiteDataStore.sumiCacheDataTypes,
                    modifiedSince: .distantPast,
                    in: dataStore
                )
                await clearFaviconCacheIfHistoryWasNotCleared(categories: categories)
            } else if !domains.isEmpty {
                await websiteDataCleanupService.removeWebsiteDataForDomains(
                    domains,
                    ofTypes: WKWebsiteDataStore.sumiCacheDataTypes,
                    includingCookies: false,
                    in: dataStore
                )
            }
        }
    }

    private func clearFaviconCacheIfHistoryWasNotCleared(categories: Set<SumiBrowsingDataCategory>) async {
        guard !categories.contains(.history) else { return }
        await SumiFaviconSystem.shared.burnAfterHistoryClear(
            savedLogins: BasicAuthCredentialStore().allCredentialHosts()
        )
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
