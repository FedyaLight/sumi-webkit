import Foundation
import WebKit

@MainActor
final class SumiManualWebsiteDataCleanupService {
    private let websiteDataCleanupService: any SumiWebsiteDataCleanupServicing
    private let appResidueCleaner: any SumiBrowsingDataAppResidueCleaning
    private let sharedWebsiteDataStoreProvider: @MainActor () -> WKWebsiteDataStore
    private let referenceDateProvider: @MainActor () -> Date
    /// Website-data mutation is unsafe without this boundary. The cleanup
    /// service therefore owns the installed capability for its full useful
    /// lifetime instead of letting it disappear through a weak reference.
    var destructiveCleanupPreparer: (any SumiDestructiveBrowsingDataCleanupPreparing)?

    init(
        websiteDataCleanupService: any SumiWebsiteDataCleanupServicing,
        appResidueCleaner: any SumiBrowsingDataAppResidueCleaning,
        destructiveCleanupPreparer: (any SumiDestructiveBrowsingDataCleanupPreparing)?,
        sharedWebsiteDataStoreProvider: @escaping @MainActor () -> WKWebsiteDataStore,
        referenceDateProvider: @escaping @MainActor () -> Date
    ) {
        self.websiteDataCleanupService = websiteDataCleanupService
        self.appResidueCleaner = appResidueCleaner
        self.destructiveCleanupPreparer = destructiveCleanupPreparer
        self.sharedWebsiteDataStoreProvider = sharedWebsiteDataStoreProvider
        self.referenceDateProvider = referenceDateProvider
    }

    @discardableResult
    func performDestructiveWebsiteDataCleanup(
        profileIDs: Set<UUID>,
        deletion: @escaping @MainActor () async -> Void
    ) async -> Bool {
        guard !profileIDs.isEmpty else {
            await deletion()
            return true
        }
        guard let destructiveCleanupPreparer else {
            RuntimeDiagnostics.emit(
                "Blocked destructive website-data cleanup because no live-document preparer is attached."
            )
            return false
        }
        return await destructiveCleanupPreparer.performDestructiveDataCleanup(
            profileIDs: profileIDs,
            deletion: deletion
        )
    }

    @discardableResult
    func performDestructiveWebsiteDataCleanupIfNeeded(
        range: SumiBrowsingDataTimeRange,
        categories: Set<SumiBrowsingDataCategory>,
        targetProfiles: [Profile],
        deletion: @escaping @MainActor () async -> Void
    ) async -> Bool {
        guard categories.contains(.siteData) || categories.contains(.cache)
        else {
            await deletion()
            return true
        }
        return await performDestructiveWebsiteDataCleanup(
            profileIDs: Set(targetProfiles.map(\.id)),
            deletion: deletion
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
        domains: Set<String>,
        dataTypes: Set<String>,
        includesCookies: Bool,
        dataStore: WKWebsiteDataStore
    ) async {
        await clearWebsiteData(
            range: range,
            dataTypes: dataTypes,
            includesCookies: includesCookies,
            domains: domains,
            dataStore: dataStore
        )
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

}
