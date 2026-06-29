import Foundation
import WebKit

@MainActor
final class SumiManualWebsiteDataCleanupOwner {
    private let websiteDataCleanupService: any SumiWebsiteDataCleanupServicing
    private let appResidueCleaner: any SumiBrowsingDataAppResidueCleaning
    private let domainInventory: SumiBrowsingDataDomainInventory
    private let sharedWebsiteDataStoreProvider: @MainActor () -> WKWebsiteDataStore
    private let referenceDateProvider: @MainActor () -> Date
    weak var destructiveCleanupPreparer: (any SumiDestructiveBrowsingDataCleanupPreparing)?

    init(
        websiteDataCleanupService: any SumiWebsiteDataCleanupServicing,
        appResidueCleaner: any SumiBrowsingDataAppResidueCleaning,
        domainInventory: SumiBrowsingDataDomainInventory,
        destructiveCleanupPreparer: (any SumiDestructiveBrowsingDataCleanupPreparing)?,
        sharedWebsiteDataStoreProvider: @escaping @MainActor () -> WKWebsiteDataStore,
        referenceDateProvider: @escaping @MainActor () -> Date
    ) {
        self.websiteDataCleanupService = websiteDataCleanupService
        self.appResidueCleaner = appResidueCleaner
        self.domainInventory = domainInventory
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

    func prepareForDestructiveWebsiteDataCleanupIfNeeded(
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

    func websiteDataTypes(
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

    func clearProfileWebsiteData(
        range: SumiBrowsingDataTimeRange,
        categories: Set<SumiBrowsingDataCategory>,
        domains: Set<String>,
        dataTypes: Set<String>,
        includesCookies: Bool,
        dataStore: WKWebsiteDataStore
    ) async -> Set<String> {
        let siteDataFaviconDomains = await siteDataFaviconDomainsToInvalidate(
            range: range,
            categories: categories,
            domains: domains,
            dataTypes: dataTypes,
            includesCookies: includesCookies,
            dataStore: dataStore
        )
        await clearWebsiteData(
            range: range,
            dataTypes: dataTypes,
            includesCookies: includesCookies,
            domains: domains,
            dataStore: dataStore
        )
        return siteDataFaviconDomains
    }

    func clearAppLevelWebsiteResidueIfNeeded(
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

    func prunePersistentDataStoresIfNeeded(
        range: SumiBrowsingDataTimeRange,
        categories: Set<SumiBrowsingDataCategory>,
        targetProfiles: [Profile],
        targetProfileIds: Set<UUID>,
        includeAllProfiles: Bool
    ) async {
        guard includeAllProfiles,
              range == .allTime,
              !targetProfiles.isEmpty,
              categories.contains(.siteData) || categories.contains(.cache)
        else { return }

        let prunedDataStoreIdentifiers = await websiteDataCleanupService.prunePersistentDataStores(
            keeping: targetProfileIds
        )
        if !prunedDataStoreIdentifiers.isEmpty {
            RuntimeDiagnostics.debug(
                "Manual browsing data cleanup pruned \(prunedDataStoreIdentifiers.count) orphan WebKit persistent data stores.",
                category: "BrowsingDataCleanup"
            )
        }
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
            return domainInventory.normalizeDomains(
                await domainInventory.websiteDataDomains(
                    ofTypes: dataTypes,
                    includeCookies: includesCookies,
                    in: dataStore
                )
            )
        }
        return domains
    }
}
