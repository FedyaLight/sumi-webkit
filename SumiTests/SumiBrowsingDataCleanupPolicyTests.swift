import WebKit
import XCTest

@testable import Sumi

@MainActor
extension SumiWebsiteDataCleanupServiceTests {
    func testBrowsingDataAllProfilesClearsAllHistoryAndAllProfileStores() async throws {
        let harness = try makeHistoryHarness()
        let cleanupService = FakeCleanupService()
        let appResidueCleaner = FakeAppResidueCleaner()
        let destructiveCleanupPreparer = FakeDestructiveCleanupPreparer()
        let visitedLinkStore = WebsiteDataCleanupVisitedLinkStoreStub()
        let otherProfileID = UUID()
        try installHistoryTestProfile(
            id: otherProfileID,
            in: harness.container
        )
        let service = makeBrowsingDataCleanupService(
            websiteDataCleanupService: cleanupService,
            appResidueCleaner: appResidueCleaner,
            visitedLinkStore: visitedLinkStore,
            destructiveCleanupPreparer: destructiveCleanupPreparer,
            sharedWebsiteDataStoreProvider: { .nonPersistent() },
            referenceDateProvider: { historyTestDate("2026-04-23T12:00:00Z") }
        )
        let currentProfile = Profile(
            id: harness.profileID,
            name: "Current",
            dataStore: .nonPersistent()
        )
        let otherProfile = Profile(
            id: otherProfileID,
            name: "Other",
            dataStore: .nonPersistent()
        )

        try await harness.historyManager.store.recordVisit(
            url: URL(string: "https://current.example")!,
            title: "Current",
            visitedAt: historyTestDate("2026-04-23T11:45:00Z"),
            profileId: harness.profileID
        )
        try await harness.historyManager.store.recordVisit(
            url: URL(string: "https://other.example")!,
            title: "Other",
            visitedAt: historyTestDate("2026-04-23T11:30:00Z"),
            profileId: otherProfileID
        )

        await service.clear(
            range: .allTime,
            categories: SumiBrowsingDataCategory.defaultSelection,
            historyManager: harness.historyManager,
            profiles: [currentProfile, otherProfile],
            includeAllProfiles: true
        )

        let currentProfileRemaining = await harness.historyManager.historyPage(
            query: .rangeFilter(.all),
            limit: 10
        ).items
        let otherProfileVisits = try await harness.historyManager.store.fetchVisitRecordsForExplicitAction(
            matching: .rangeFilter(.all),
            profileId: otherProfileID,
            referenceDate: historyTestDate("2026-04-23T12:00:00Z"),
            calendar: .autoupdatingCurrent
        )
        XCTAssertTrue(currentProfileRemaining.isEmpty)
        XCTAssertTrue(otherProfileVisits.isEmpty)
        XCTAssertEqual(cleanupService.clearedProfileStores, 3)
        XCTAssertEqual(
            destructiveCleanupPreparer.preparedProfileIDSets,
            [Set([harness.profileID, otherProfileID])]
        )
        XCTAssertEqual(cleanupService.prunedKeepSets, [Set([harness.profileID, otherProfileID])])
        XCTAssertEqual(
            Set(visitedLinkStore.replaceCalls.map(\.profileID)),
            Set([harness.profileID, otherProfileID])
        )
        XCTAssertTrue(visitedLinkStore.replaceCalls.allSatisfy(\.urls.isEmpty))
        XCTAssertEqual(appResidueCleaner.clearSharedURLCacheCallCount, 1)
        XCTAssertEqual(appResidueCleaner.clearFaviconNegativeCacheCallCount, 1)
    }

    func testBrowsingDataFiniteRangePreparesLiveWebViewsForCleanup() async throws {
        let harness = try makeHistoryHarness()
        let cleanupService = FakeCleanupService()
        let destructiveCleanupPreparer = FakeDestructiveCleanupPreparer()
        let service = makeBrowsingDataCleanupService(
            websiteDataCleanupService: cleanupService,
            destructiveCleanupPreparer: destructiveCleanupPreparer,
            referenceDateProvider: { historyTestDate("2026-04-23T12:00:00Z") }
        )

        try await harness.historyManager.store.recordVisit(
            url: URL(string: "https://www.reddit.com/r/browsers")!,
            title: "Recent",
            visitedAt: historyTestDate("2026-04-23T11:45:00Z"),
            profileId: harness.profileID
        )

        await service.clear(
            range: .lastHour,
            categories: [.siteData, .cache],
            historyManager: harness.historyManager,
            profiles: [testProfile(id: harness.profileID)],
            includeAllProfiles: false
        )

        XCTAssertEqual(
            destructiveCleanupPreparer.preparedProfileIDSets,
            [Set([harness.profileID])]
        )
        XCTAssertEqual(cleanupService.removedDomainSets.count, 1)
    }

    func testBrowsingDataSiteDataOnlyClearInvalidatesFaviconsForAffectedDomains() async throws {
        let harness = try makeHistoryHarness()
        let cleanupService = FakeCleanupService()
        let faviconCleaner = FakeFaviconCleaner()
        let service = makeBrowsingDataCleanupService(
            websiteDataCleanupService: cleanupService,
            faviconCacheCleaner: faviconCleaner,
            referenceDateProvider: { historyTestDate("2026-04-23T12:00:00Z") }
        )

        try await harness.historyManager.store.recordVisit(
            url: URL(string: "https://www.reddit.com/r/browsers")!,
            title: "Recent",
            visitedAt: historyTestDate("2026-04-23T11:45:00Z"),
            profileId: harness.profileID
        )

        await service.clear(
            range: .lastHour,
            categories: [.siteData],
            historyManager: harness.historyManager,
            profiles: [testProfile(id: harness.profileID)],
            includeAllProfiles: false
        )

        XCTAssertEqual(cleanupService.removedDomainSets.count, 1)
        XCTAssertEqual(cleanupService.removedDomainSets[0].domains, ["reddit.com"])
        XCTAssertEqual(faviconCleaner.invalidateSiteCalls.count, 1)
        XCTAssertEqual(faviconCleaner.invalidateSiteCalls[0].domain, "reddit.com")
        XCTAssertEqual(
            faviconCleaner.invalidateSiteCalls[0].partition,
            SumiFaviconPartition.regular(harness.profileID)
        )
        XCTAssertTrue(faviconCleaner.burnDomainsCalls.isEmpty)
        XCTAssertTrue(faviconCleaner.burnAfterHistoryClearSavedLogins.isEmpty)
    }

    func testBrowsingDataAllTimeSiteDataOnlyInvalidatesDiscoveredWebsiteDataDomains() async throws {
        let harness = try makeHistoryHarness()
        let cleanupService = FakeCleanupService()
        cleanupService.recordResponses = [
            [FakeWKWebsiteDataRecord(displayName: "reddit.com", dataTypes: WKWebsiteDataStore.sumiSiteDataTypes)],
        ]
        let faviconCleaner = FakeFaviconCleaner()
        let service = makeBrowsingDataCleanupService(
            websiteDataCleanupService: cleanupService,
            faviconCacheCleaner: faviconCleaner,
            referenceDateProvider: { historyTestDate("2026-04-23T12:00:00Z") }
        )

        await service.clear(
            range: .allTime,
            categories: [.siteData],
            historyManager: harness.historyManager,
            profiles: [testProfile(id: harness.profileID)],
            includeAllProfiles: false
        )

        XCTAssertEqual(cleanupService.removedWebsiteDataTypes.count, 1)
        XCTAssertEqual(
            cleanupService.removedWebsiteDataTypes[0],
            WKWebsiteDataStore.sumiSiteDataTypes
        )
        XCTAssertEqual(cleanupService.cookieRemovalSelections, [.all])
        XCTAssertEqual(faviconCleaner.invalidateSiteCalls.count, 1)
        XCTAssertEqual(faviconCleaner.invalidateSiteCalls[0].domain, "reddit.com")
        XCTAssertEqual(
            faviconCleaner.invalidateSiteCalls[0].partition,
            SumiFaviconPartition.regular(harness.profileID)
        )
        XCTAssertTrue(faviconCleaner.burnDomainsCalls.isEmpty)
        XCTAssertTrue(faviconCleaner.burnAfterHistoryClearSavedLogins.isEmpty)
    }

    func testBrowsingDataFiniteCacheClearBurnsAffectedFaviconsWithoutHistorySelection() async throws {
        let harness = try makeHistoryHarness()
        let cleanupService = FakeCleanupService()
        let faviconCleaner = FakeFaviconCleaner()
        let service = makeBrowsingDataCleanupService(
            websiteDataCleanupService: cleanupService,
            faviconCacheCleaner: faviconCleaner,
            referenceDateProvider: { historyTestDate("2026-04-23T12:00:00Z") }
        )

        try await harness.historyManager.store.recordVisit(
            url: URL(string: "https://www.reddit.com/r/browsers")!,
            title: "Recent",
            visitedAt: historyTestDate("2026-04-23T11:45:00Z"),
            profileId: harness.profileID
        )

        await service.clear(
            range: .lastHour,
            categories: [.cache],
            historyManager: harness.historyManager,
            profiles: [testProfile(id: harness.profileID)],
            includeAllProfiles: false
        )

        XCTAssertEqual(cleanupService.removedDomainSets.count, 1)
        XCTAssertEqual(cleanupService.removedDomainSets[0].domains, ["reddit.com"])
        XCTAssertEqual(faviconCleaner.burnDomainsCalls.count, 1)
        XCTAssertEqual(faviconCleaner.burnDomainsCalls[0].domains, ["reddit.com"])
        XCTAssertTrue(faviconCleaner.burnDomainsCalls[0].remainingHistoryHosts.isEmpty)
        XCTAssertTrue(faviconCleaner.burnAfterHistoryClearSavedLogins.isEmpty)
    }

    func testAutomaticBrowsingDataCleanupDeletesExpiredHistoryWithoutMutatingWebsiteData() async throws {
        let harness = try makeHistoryHarness()
        let suiteName = "SumiBrowsingDataCleanupTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let referenceDate = historyTestDate("2026-04-23T12:00:00Z")
        let service = makeAutomaticBrowsingDataCleanupService(
            userDefaults: defaults,
            referenceDateProvider: { referenceDate }
        )

        try await harness.historyManager.store.recordVisit(
            url: URL(string: "https://old.example")!,
            title: "Old",
            visitedAt: historyTestDate("2026-04-01T12:00:00Z"),
            profileId: harness.profileID
        )
        try await harness.historyManager.store.recordVisit(
            url: URL(string: "https://recent.example")!,
            title: "Recent",
            visitedAt: historyTestDate("2026-04-22T12:00:00Z"),
            profileId: harness.profileID
        )

        let result = await service.runIfNeeded(
            retentionPeriod: .sevenDays,
            historyManager: harness.historyManager,
            profileIDs: [harness.profileID],
            currentProfileId: harness.profileID,
            force: true,
            reason: "unit-test"
        )

        let remaining = await harness.historyManager.historyPage(
            query: .rangeFilter(.all),
            limit: 10
        ).items
        XCTAssertTrue(result.didRun)
        XCTAssertEqual(result.deletedHistoryVisitCount, 1)
        XCTAssertEqual(remaining.map(\.domain), ["recent.example"])
    }

    func testAutomaticBrowsingDataCleanupOffDoesNotRunEvenWhenForced() async throws {
        XCTAssertEqual(SumiBrowsingDataRetentionPeriod.persistedValue(nil), .off)

        let harness = try makeHistoryHarness()
        let suiteName = "SumiBrowsingDataCleanupTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = makeAutomaticBrowsingDataCleanupService(
            userDefaults: defaults,
            referenceDateProvider: { historyTestDate("2026-04-23T12:00:00Z") }
        )

        try await harness.historyManager.store.recordVisit(
            url: URL(string: "https://old.example")!,
            title: "Old",
            visitedAt: historyTestDate("2026-04-01T12:00:00Z"),
            profileId: harness.profileID
        )

        let result = await service.runIfNeeded(
            retentionPeriod: .off,
            historyManager: harness.historyManager,
            profileIDs: [harness.profileID],
            currentProfileId: harness.profileID,
            force: true,
            reason: "unit-test"
        )

        let remaining = await harness.historyManager.historyPage(
            query: .rangeFilter(.all),
            limit: 10
        ).items
        XCTAssertFalse(result.didRun)
        XCTAssertEqual(remaining.map(\.domain), ["old.example"])
    }

    func testAutomaticBrowsingDataCleanupThrottlesUntilRetentionChanges() async throws {
        let harness = try makeHistoryHarness()
        let suiteName = "SumiBrowsingDataCleanupTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = makeAutomaticBrowsingDataCleanupService(
            userDefaults: defaults,
            referenceDateProvider: { historyTestDate("2026-04-23T12:00:00Z") }
        )

        _ = await service.runIfNeeded(
            retentionPeriod: .thirtyDays,
            historyManager: harness.historyManager,
            profileIDs: [harness.profileID],
            currentProfileId: harness.profileID,
            reason: "first"
        )
        let throttled = await service.runIfNeeded(
            retentionPeriod: .thirtyDays,
            historyManager: harness.historyManager,
            profileIDs: [harness.profileID],
            currentProfileId: harness.profileID,
            reason: "second"
        )
        let afterRetentionChange = await service.runIfNeeded(
            retentionPeriod: .sevenDays,
            historyManager: harness.historyManager,
            profileIDs: [harness.profileID],
            currentProfileId: harness.profileID,
            reason: "changed"
        )

        XCTAssertFalse(throttled.didRun)
        XCTAssertTrue(afterRetentionChange.didRun)
    }
}
