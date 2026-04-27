import SwiftData
import WebKit
import WKAbstractions
import XCTest

@testable import Sumi

@MainActor
final class SumiWebsiteDataCleanupServiceTests: XCTestCase {
    func testClearAllProfileWebsiteDataUsesDDGOrderedAsyncCleanup() async {
        let cookieStore = FakeDDGCookieStore(cookies: [
            .make(domain: "example.com")
        ])
        let store = FakeDDGWebsiteDataStore(
            cookieStore: cookieStore,
            records: [
                FakeDDGWebsiteDataRecord(displayName: "example.com")
            ]
        )
        let service = SumiWebsiteDataCleanupService()

        await service.clearAllProfileWebsiteData(
            using: store,
            storeIdentifier: "ordered-store"
        )

        XCTAssertEqual(store.modifiedSinceRemovals.map(\.types).first, WKWebsiteDataStore.safelyRemovableWebsiteDataTypes)
        XCTAssertEqual(store.recordRemovals.first?.types, WKWebsiteDataStore.allWebsiteDataTypesExceptCookies)
        XCTAssertEqual(store.recordRemovals.first?.records.map(\.displayName), ["example.com"])
        XCTAssertEqual(cookieStore.deletedCookies.map(\.domain), ["example.com"])
    }

    func testRepeatedCleanupRequestsCoalesce() async {
        let store = FakeDDGWebsiteDataStore(
            records: [FakeDDGWebsiteDataRecord(displayName: "example.com")]
        )
        store.delayNanoseconds = 50_000_000
        let service = SumiWebsiteDataCleanupService()

        async let first: Void = service.clearAllProfileWebsiteData(
            using: store,
            storeIdentifier: "coalesced-store"
        )
        await Task.yield()
        async let second: Void = service.clearAllProfileWebsiteData(
            using: store,
            storeIdentifier: "coalesced-store"
        )
        _ = await (first, second)

        XCTAssertEqual(store.modifiedSinceRemovals.count, 1)
        XCTAssertEqual(store.recordRemovals.count, 1)
    }

    func testDomainScopedDeletionCallsRecordRemovalWithExpectedTypes() async {
        let store = FakeDDGWebsiteDataStore(
            records: [
                FakeDDGWebsiteDataRecord(displayName: "example.com"),
                FakeDDGWebsiteDataRecord(displayName: "sub.example.com"),
                FakeDDGWebsiteDataRecord(displayName: "other.com")
            ]
        )
        let service = SumiWebsiteDataCleanupService()

        await service.removeWebsiteDataForDomain(
            "example.com",
            includingCookies: false,
            using: store,
            storeIdentifier: "domain-store"
        )

        XCTAssertEqual(store.recordRemovals.count, 1)
        XCTAssertEqual(store.recordRemovals[0].types, WKWebsiteDataStore.allWebsiteDataTypesExceptCookies)
        XCTAssertEqual(
            Set(store.recordRemovals[0].records.map(\.displayName)),
            Set(["example.com", "sub.example.com"])
        )
    }

    func testBulkDomainScopedDeletionFetchesRecordsOnceAndDeletesMatchingCookies() async {
        let cookieStore = FakeDDGCookieStore(cookies: [
            .make(domain: "example.com"),
            .make(domain: "sub.example.com"),
            .make(domain: "other.com")
        ])
        let store = FakeDDGWebsiteDataStore(
            cookieStore: cookieStore,
            records: [
                FakeDDGWebsiteDataRecord(displayName: "example.com"),
                FakeDDGWebsiteDataRecord(displayName: "sub.example.com"),
                FakeDDGWebsiteDataRecord(displayName: "unrelated.com")
            ]
        )
        let service = SumiWebsiteDataCleanupService()

        await service.removeWebsiteDataForDomains(
            ["example.com"],
            ofTypes: WKWebsiteDataStore.sumiCacheDataTypes,
            includingCookies: true,
            using: store,
            storeIdentifier: "bulk-domain-store"
        )

        XCTAssertEqual(store.fetchTypes, [WKWebsiteDataStore.sumiCacheDataTypes])
        XCTAssertEqual(store.recordRemovals.count, 1)
        XCTAssertEqual(store.recordRemovals[0].types, WKWebsiteDataStore.sumiCacheDataTypes)
        XCTAssertEqual(
            Set(store.recordRemovals[0].records.map(\.displayName)),
            Set(["example.com", "sub.example.com"])
        )
        XCTAssertEqual(
            Set(cookieStore.deletedCookies.map(\.domain)),
            Set(["example.com", "sub.example.com"])
        )
    }

    func testSiteDataEntriesIncludeCurrentSiteAndSubdomainsWithExactCounts() async {
        let cookieStore = FakeDDGCookieStore(cookies: [
            .make(name: "root", domain: "example.com"),
            .make(name: "sub", domain: ".sub.example.com"),
            .make(name: "other", domain: "other.com")
        ])
        let store = FakeDDGWebsiteDataStore(
            cookieStore: cookieStore,
            records: [
                FakeDDGWebsiteDataRecord(displayName: "example.com"),
                FakeDDGWebsiteDataRecord(displayName: "sub.example.com"),
                FakeDDGWebsiteDataRecord(displayName: "unrelated.com")
            ]
        )
        let service = SumiWebsiteDataCleanupService()

        let entries = await service.fetchSiteDataEntries(
            forDomain: "example.com",
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            using: store
        )

        XCTAssertEqual(entries.map(\.domain), ["example.com", "sub.example.com"])
        XCTAssertEqual(entries[0].cookieCount, 1)
        XCTAssertEqual(entries[0].recordCount, 1)
        XCTAssertEqual(entries[1].cookieCount, 1)
        XCTAssertEqual(entries[1].recordCount, 1)
    }

    func testExactHostDeletionDoesNotDeleteParentOrSiblingData() async {
        let cookieStore = FakeDDGCookieStore(cookies: [
            .make(name: "root", domain: "example.com"),
            .make(name: "sharedRoot", domain: ".example.com"),
            .make(name: "sub", domain: "sub.example.com"),
            .make(name: "sibling", domain: "sibling.example.com"),
            .make(name: "other", domain: "other.com")
        ])
        let store = FakeDDGWebsiteDataStore(
            cookieStore: cookieStore,
            records: [
                FakeDDGWebsiteDataRecord(displayName: "example.com"),
                FakeDDGWebsiteDataRecord(displayName: "sub.example.com"),
                FakeDDGWebsiteDataRecord(displayName: "sibling.example.com"),
                FakeDDGWebsiteDataRecord(displayName: "other.com")
            ]
        )
        let service = SumiWebsiteDataCleanupService()

        await service.removeWebsiteDataForExactHost(
            "sub.example.com",
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            includingCookies: true,
            using: store,
            storeIdentifier: "exact-sub-host-store"
        )

        XCTAssertEqual(store.recordRemovals.count, 1)
        XCTAssertEqual(store.recordRemovals[0].records.map(\.displayName), ["sub.example.com"])
        XCTAssertEqual(cookieStore.deletedCookies.map(\.domain), ["sub.example.com"])
        XCTAssertEqual(
            Set(cookieStore.cookies.map(\.domain)),
            Set(["example.com", ".example.com", "sibling.example.com", "other.com"])
        )
    }

    func testExactRootHostDeletionDeletesOnlyRootNormalizedCookieDomain() async {
        let cookieStore = FakeDDGCookieStore(cookies: [
            .make(name: "root", domain: "example.com"),
            .make(name: "sharedRoot", domain: ".example.com"),
            .make(name: "sub", domain: "sub.example.com"),
            .make(name: "sibling", domain: "sibling.example.com"),
            .make(name: "other", domain: "other.com")
        ])
        let store = FakeDDGWebsiteDataStore(
            cookieStore: cookieStore,
            records: [
                FakeDDGWebsiteDataRecord(displayName: "example.com"),
                FakeDDGWebsiteDataRecord(displayName: "sub.example.com"),
                FakeDDGWebsiteDataRecord(displayName: "sibling.example.com"),
                FakeDDGWebsiteDataRecord(displayName: "other.com")
            ]
        )
        let service = SumiWebsiteDataCleanupService()

        await service.removeWebsiteDataForExactHost(
            "example.com",
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            includingCookies: true,
            using: store,
            storeIdentifier: "exact-root-host-store"
        )

        XCTAssertEqual(store.recordRemovals.count, 1)
        XCTAssertEqual(store.recordRemovals[0].records.map(\.displayName), ["example.com"])
        XCTAssertEqual(
            Set(cookieStore.deletedCookies.map(\.domain)),
            Set(["example.com", ".example.com"])
        )
        XCTAssertEqual(
            Set(cookieStore.cookies.map(\.domain)),
            Set(["sub.example.com", "sibling.example.com", "other.com"])
        )
    }

    func testCookieDeletionUsesDDGDomainMatching() async {
        let cookieStore = FakeDDGCookieStore(cookies: [
            .make(domain: "example.com"),
            .make(domain: "sub.example.com"),
            .make(domain: "example.com.fake.com"),
            .make(domain: "other.com")
        ])
        let store = FakeDDGWebsiteDataStore(cookieStore: cookieStore)
        let service = SumiWebsiteDataCleanupService()

        await service.removeCookies(
            .domains(["example.com"]),
            using: store,
            storeIdentifier: "cookie-store"
        )

        XCTAssertEqual(
            Set(cookieStore.deletedCookies.map(\.domain)),
            Set(["example.com", "sub.example.com"])
        )
    }

    func testFireStyleClearUsesEmptySumiPreservationPolicyByDefault() async {
        let cookieStore = FakeDDGCookieStore(cookies: [
            .make(domain: "preserved.example")
        ])
        let store = FakeDDGWebsiteDataStore(
            cookieStore: cookieStore,
            records: [
                FakeDDGWebsiteDataRecord(displayName: "preserved.example")
            ]
        )
        let service = SumiWebsiteDataCleanupService()

        await service.clearAllProfileWebsiteData(
            using: store,
            storeIdentifier: "empty-policy-store"
        )

        XCTAssertEqual(store.recordRemovals.first?.records.map(\.displayName), ["preserved.example"])
        XCTAssertEqual(cookieStore.deletedCookies.map(\.domain), ["preserved.example"])
    }

    func testSiteDataPolicyStoreScopesRulesByProfileAndHost() {
        let suiteName = "SumiSiteDataPolicyStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SumiSiteDataPolicyStore(userDefaults: defaults)
        let profileA = UUID()
        let profileB = UUID()

        store.setBlockStorage(true, forHost: ".YouTube.com", profileId: profileA)
        store.setDeleteWhenAllWindowsClosed(true, forHost: "accounts.youtube.com", profileId: profileB)

        XCTAssertTrue(store.state(forHost: "youtube.com", profileId: profileA).blockStorage)
        XCTAssertFalse(store.state(forHost: "youtube.com", profileId: profileB).blockStorage)
        XCTAssertEqual(store.hostsBlockingStorage(profileId: profileA), ["youtube.com"])
        XCTAssertEqual(store.hostsDeletingWhenAllWindowsClosed(profileId: profileB), ["accounts.youtube.com"])
    }

    func testSiteDataCookieBlockingRuleSourceUsesProfileScopedHosts() throws {
        let suiteName = "SumiSiteDataRuleSourceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SumiSiteDataPolicyStore(userDefaults: defaults)
        let profileA = UUID()
        let profileB = UUID()
        store.setBlockStorage(true, forHost: "youtube.com", profileId: profileA)
        store.setBlockStorage(true, forHost: "reddit.com", profileId: profileB)
        let source = SumiSiteDataCookieBlockingRuleSource(policyStore: store)

        let profileARules = try source.ruleLists(profileId: profileA)
        let encoded = profileARules.first?.encodedContentRuleList ?? ""

        XCTAssertEqual(profileARules.count, 1)
        XCTAssertTrue(encoded.contains("\"block-cookies\""))
        XCTAssertTrue(encoded.contains("*youtube.com"))
        XCTAssertFalse(encoded.contains("*reddit.com"))
    }

    func testSiteDataBlockStoragePolicyDeletesExactHostImmediately() async {
        let suiteName = "SumiSiteDataBlockStorageTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SumiSiteDataPolicyStore(userDefaults: defaults)
        let cleanupService = FakeCleanupService()
        let service = SumiSiteDataPolicyEnforcementService(
            policyStore: store,
            cleanupService: cleanupService
        )
        let profile = Profile(
            name: "Primary",
            icon: "person.crop.circle",
            dataStore: .nonPersistent()
        )

        await service.setBlockStorage(true, forHost: ".YouTube.com", profile: profile)

        XCTAssertTrue(store.state(forHost: "youtube.com", profileId: profile.id).blockStorage)
        XCTAssertEqual(cleanupService.removedExactHosts.count, 1)
        XCTAssertEqual(cleanupService.removedExactHosts[0].host, "youtube.com")
        XCTAssertTrue(cleanupService.removedExactHosts[0].includingCookies)
        XCTAssertEqual(cleanupService.removedExactHosts[0].dataTypes, WKWebsiteDataStore.allWebsiteDataTypes())
    }

    func testSiteDataDeleteWhenAllWindowsClosePolicyRunsDeferredCleanup() async {
        let suiteName = "SumiSiteDataDeleteOnCloseTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SumiSiteDataPolicyStore(userDefaults: defaults)
        let cleanupService = FakeCleanupService()
        let service = SumiSiteDataPolicyEnforcementService(
            policyStore: store,
            cleanupService: cleanupService
        )
        let profile = Profile(
            name: "Primary",
            icon: "person.crop.circle",
            dataStore: .nonPersistent()
        )

        service.setDeleteWhenAllWindowsClosed(
            true,
            forHost: "accounts.youtube.com",
            profile: profile
        )

        XCTAssertTrue(
            store.state(
                forHost: "accounts.youtube.com",
                profileId: profile.id
            ).deleteWhenAllWindowsClosed
        )
        XCTAssertTrue(cleanupService.removedExactHosts.isEmpty)

        await service.performAllWindowsClosedCleanup(profiles: [profile])

        XCTAssertEqual(cleanupService.removedExactHosts.count, 1)
        XCTAssertEqual(cleanupService.removedExactHosts[0].host, "accounts.youtube.com")
        XCTAssertTrue(cleanupService.removedExactHosts[0].includingCookies)
        XCTAssertEqual(cleanupService.removedExactHosts[0].dataTypes, WKWebsiteDataStore.allWebsiteDataTypes())
    }

    func testNoSynchronousWaitsRemainInCleanupPaths() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let paths = [
            "Sumi/Services/SumiBrowsingDataCleanupService.swift",
            "Sumi/Services/SumiWebsiteDataCleanupService.swift",
            "Sumi/Services/BrowserPrivacyService.swift",
            "Sumi/Models/Profile/Profile.swift",
            "Sumi/Components/Settings/PrivacySettingsView.swift"
        ]

        let source = try paths
            .map { path in
                try String(contentsOf: repoRoot.appendingPathComponent(path), encoding: .utf8)
            }
            .joined(separator: "\n")

        XCTAssertFalse(source.contains("DispatchSemaphore"))
        XCTAssertFalse(source.contains("DispatchGroup"))
        XCTAssertFalse(source.contains(".wait("))
    }

    func testNavigationRespondersDoNotReferenceCleanupManagers() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let navigationDirectory = repoRoot
            .appendingPathComponent("Sumi/Models/Tab/Navigation")
        let sources = try FileManager.default
            .contentsOfDirectory(
                at: navigationDirectory,
                includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension == "swift" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")

        XCTAssertFalse(sources.contains("SumiWebsiteDataCleanupService"))
        XCTAssertFalse(sources.contains("CookieManager"))
        XCTAssertFalse(sources.contains("CacheManager"))
        XCTAssertFalse(sources.contains("removeData("))
        XCTAssertFalse(sources.contains("httpCookieStore"))
    }

    func testRuntimeCleanupPathsDoNotReferenceLegacyCookieCacheManagers() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let paths = [
            "Sumi/Services/BrowserPrivacyService.swift",
            "Sumi/Managers/BrowserManager/BrowserManager+Privacy.swift",
            "Sumi/Managers/BrowserManager/BrowserManager.swift",
            "Sumi/History/SumiBrowsingDataDialog.swift",
            "Sumi/Components/Settings/PrivacySettingsView.swift"
        ]

        let source = try paths
            .map { path in
                try String(contentsOf: repoRoot.appendingPathComponent(path), encoding: .utf8)
            }
            .joined(separator: "\n")

        XCTAssertFalse(source.contains("CookieManager"))
        XCTAssertFalse(source.contains("CacheManager"))
        XCTAssertFalse(source.contains("cookieManager"))
        XCTAssertFalse(source.contains("cacheManager"))
    }

    func testBrowsingDataFiniteRangeDeletesHistoryAndVisitedDomainData() async throws {
        let harness = try makeHistoryHarness()
        let cleanupService = FakeCleanupService()
        let service = SumiBrowsingDataCleanupService(
            websiteDataCleanupService: cleanupService,
            referenceDateProvider: { historyTestDate("2026-04-23T12:00:00Z") }
        )

        try await harness.historyManager.store.recordVisit(
            url: URL(string: "https://www.reddit.com/r/browsers")!,
            title: "Recent",
            visitedAt: historyTestDate("2026-04-23T11:45:00Z"),
            profileId: harness.profileID
        )
        try await harness.historyManager.store.recordVisit(
            url: URL(string: "https://old.example")!,
            title: "Old",
            visitedAt: historyTestDate("2026-04-23T09:00:00Z"),
            profileId: harness.profileID
        )
        await harness.historyManager.refresh()

        await service.clear(
            range: .lastHour,
            categories: [.history, .siteData, .cache],
            historyManager: harness.historyManager,
            dataStore: .nonPersistent()
        )

        let remaining = await harness.historyManager.historyPage(
            query: .rangeFilter(.all),
            limit: 10
        ).items
        XCTAssertEqual(remaining.map(\.domain), ["old.example"])
        XCTAssertEqual(cleanupService.removedDomainSets.count, 1)
        XCTAssertEqual(cleanupService.removedDomainSets[0].domains, ["reddit.com"])
        XCTAssertEqual(
            cleanupService.removedDomainSets[0].dataTypes,
            WKWebsiteDataStore.allWebsiteDataTypes()
        )
        XCTAssertTrue(cleanupService.removedDomainSets[0].includingCookies)
    }

    func testBrowsingDataAllTimeClearsCurrentProfileHistoryAndWebsiteData() async throws {
        let harness = try makeHistoryHarness()
        let cleanupService = FakeCleanupService()
        let service = SumiBrowsingDataCleanupService(
            websiteDataCleanupService: cleanupService,
            referenceDateProvider: { historyTestDate("2026-04-23T12:00:00Z") }
        )
        let otherProfileID = UUID()

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
        await harness.historyManager.refresh()

        await service.clear(
            range: .allTime,
            categories: [.history, .siteData],
            historyManager: harness.historyManager,
            dataStore: .nonPersistent()
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
        XCTAssertEqual(otherProfileVisits.map(\.domain), ["other.example"])
        XCTAssertEqual(cleanupService.clearedProfileStores, 1)
    }
}

@MainActor
private func makeHistoryHarness() throws -> (
    container: ModelContainer,
    historyManager: HistoryManager,
    profileID: UUID
) {
    let container = try ModelContainer(
        for: Schema([HistoryEntryEntity.self, HistoryVisitEntity.self]),
        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
    let context = ModelContext(container)
    let profileID = UUID()
    let historyManager = HistoryManager(context: context, profileId: profileID)
    return (container, historyManager, profileID)
}

private func historyTestDate(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
}

@MainActor
private final class FakeDDGWebsiteDataStore: DDGWebsiteDataStore {
    typealias Record = FakeDDGWebsiteDataRecord

    var httpCookieStore: any DDGHTTPCookieStore {
        cookieStore
    }

    var records: [FakeDDGWebsiteDataRecord]
    var modifiedSinceRemovals: [(types: Set<String>, date: Date)] = []
    var recordRemovals: [(types: Set<String>, records: [FakeDDGWebsiteDataRecord])] = []
    var fetchTypes: [Set<String>] = []
    var delayNanoseconds: UInt64 = 0

    private let cookieStore: FakeDDGCookieStore

    init(
        cookieStore: FakeDDGCookieStore? = nil,
        records: [FakeDDGWebsiteDataRecord] = []
    ) {
        self.cookieStore = cookieStore ?? FakeDDGCookieStore()
        self.records = records
    }

    func removeData(ofTypes types: Set<String>, modifiedSince date: Date) async {
        await delayIfNeeded()
        modifiedSinceRemovals.append((types, date))
    }

    func dataRecords(ofTypes types: Set<String>) async -> [FakeDDGWebsiteDataRecord] {
        fetchTypes.append(types)
        return records
    }

    func removeData(
        ofTypes types: Set<String>,
        for records: [FakeDDGWebsiteDataRecord]
    ) async {
        recordRemovals.append((types, records))
    }

    private func delayIfNeeded() async {
        guard delayNanoseconds > 0 else { return }
        try? await Task.sleep(nanoseconds: delayNanoseconds)
    }
}

@MainActor
private final class FakeDDGCookieStore: DDGHTTPCookieStore {
    var cookies: [HTTPCookie]
    private(set) var deletedCookies: [HTTPCookie] = []

    init(cookies: [HTTPCookie] = []) {
        self.cookies = cookies
    }

    func setCookie(_ cookie: HTTPCookie) async {
        cookies.append(cookie)
    }

    func allCookies() async -> [HTTPCookie] {
        cookies
    }

    func deleteCookie(_ cookie: HTTPCookie) async {
        deletedCookies.append(cookie)
        cookies.removeAll { $0.name == cookie.name && $0.domain == cookie.domain }
    }
}

private struct FakeDDGWebsiteDataRecord: DDGWebsiteDataRecord, Hashable {
    let displayName: String
}

@MainActor
private final class FakeCleanupService: SumiWebsiteDataCleanupServicing {
    var cookieResponses: [[HTTPCookie]] = []
    var cookieFetchDelays: [UInt64] = []
    var recordResponses: [[WKWebsiteDataRecord]] = []
    var recordFetchDelays: [UInt64] = []
    private(set) var cookieFetchCount = 0
    private(set) var recordFetchCount = 0
    private(set) var cookieRemovalSelections: [SumiCookieRemovalSelection] = []
    private(set) var removedWebsiteDataTypes: [Set<String>] = []
    private(set) var removedDomains: [(domain: String, includingCookies: Bool)] = []
    private(set) var removedExactHosts: [(
        host: String,
        dataTypes: Set<String>,
        includingCookies: Bool
    )] = []
    private(set) var removedDomainSets: [(
        domains: Set<String>,
        dataTypes: Set<String>,
        includingCookies: Bool
    )] = []
    private(set) var clearedProfileStores = 0

    func fetchCookies(in dataStore: WKWebsiteDataStore) async -> [HTTPCookie] {
        _ = dataStore
        let index = cookieFetchCount
        cookieFetchCount += 1
        await delay(cookieFetchDelays[safe: index] ?? 0)
        return cookieResponses[safe: index] ?? []
    }

    func fetchWebsiteDataRecords(
        ofTypes dataTypes: Set<String>,
        in dataStore: WKWebsiteDataStore
    ) async -> [WKWebsiteDataRecord] {
        _ = dataTypes
        _ = dataStore
        let index = recordFetchCount
        recordFetchCount += 1
        await delay(recordFetchDelays[safe: index] ?? 0)
        return recordResponses[safe: index] ?? []
    }

    func fetchSiteDataEntries(
        forDomain domain: String,
        ofTypes dataTypes: Set<String>,
        in dataStore: WKWebsiteDataStore
    ) async -> [SumiSiteDataEntry] {
        _ = domain
        _ = dataTypes
        _ = dataStore
        return []
    }

    func removeCookies(
        _ selection: SumiCookieRemovalSelection,
        in dataStore: WKWebsiteDataStore
    ) async {
        _ = dataStore
        cookieRemovalSelections.append(selection)
    }

    func removeWebsiteData(
        ofTypes dataTypes: Set<String>,
        modifiedSince date: Date,
        in dataStore: WKWebsiteDataStore
    ) async {
        _ = date
        _ = dataStore
        removedWebsiteDataTypes.append(dataTypes)
    }

    func removeWebsiteDataForDomain(
        _ domain: String,
        includingCookies: Bool,
        in dataStore: WKWebsiteDataStore
    ) async {
        _ = dataStore
        removedDomains.append((domain, includingCookies))
    }

    func removeWebsiteDataForExactHost(
        _ host: String,
        ofTypes dataTypes: Set<String>,
        includingCookies: Bool,
        in dataStore: WKWebsiteDataStore
    ) async {
        _ = dataStore
        removedExactHosts.append((host, dataTypes, includingCookies))
    }

    func removeWebsiteDataForDomains(
        _ domains: Set<String>,
        ofTypes dataTypes: Set<String>,
        includingCookies: Bool,
        in dataStore: WKWebsiteDataStore
    ) async {
        _ = dataStore
        removedDomainSets.append((domains, dataTypes, includingCookies))
    }

    func clearAllProfileWebsiteData(in dataStore: WKWebsiteDataStore) async {
        _ = dataStore
        clearedProfileStores += 1
    }

    private func delay(_ nanoseconds: UInt64) async {
        guard nanoseconds > 0 else { return }
        try? await Task.sleep(nanoseconds: nanoseconds)
    }
}

private final class FakeWKWebsiteDataRecord: WKWebsiteDataRecord {
    private let recordDisplayName: String
    private let recordDataTypes: Set<String>

    init(
        displayName: String,
        dataTypes: Set<String> = WKWebsiteDataStore.sumiCacheDataTypes
    ) {
        self.recordDisplayName = displayName
        self.recordDataTypes = dataTypes
    }

    override var displayName: String {
        recordDisplayName
    }

    override var dataTypes: Set<String> {
        recordDataTypes
    }
}

private extension HTTPCookie {
    static func make(
        name: String = "cookie",
        domain: String,
        path: String = "/",
        value: String = "value",
        expiresDate: Date? = nil
    ) -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path
        ]
        if let expiresDate {
            properties[.expires] = expiresDate
        }
        return HTTPCookie(properties: properties)!
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
