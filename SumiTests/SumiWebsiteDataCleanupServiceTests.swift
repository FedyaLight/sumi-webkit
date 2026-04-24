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

    func testCookieManagerIgnoresStaleRefreshResults() async {
        let service = FakeCleanupService()
        service.cookieResponses = [
            [.make(name: "old", domain: "old.example")],
            [.make(name: "new", domain: "new.example")]
        ]
        service.cookieFetchDelays = [50_000_000, 0]
        let manager = CookieManager(
            dataStore: .nonPersistent(),
            cleanupService: service
        )

        let first = Task { @MainActor in await manager.loadCookies() }
        await Task.yield()
        let second = Task { @MainActor in await manager.loadCookies() }
        await first.value
        await second.value

        XCTAssertEqual(manager.cookies.map(\.name), ["new"])
        XCTAssertFalse(manager.isLoading)
    }

    func testCookieDeleteRefreshesOncePerOperation() async {
        let service = FakeCleanupService()
        service.cookieResponses = [
            [.make(name: "remaining", domain: "example.com")]
        ]
        let manager = CookieManager(
            dataStore: .nonPersistent(),
            cleanupService: service
        )

        await manager.deleteCookiesForDomain("example.com")

        XCTAssertEqual(service.cookieRemovalSelections, [.domains(["example.com"])])
        XCTAssertEqual(service.cookieFetchCount, 1)
    }

    func testCacheManagerIgnoresStaleRefreshResults() async {
        let service = FakeCleanupService()
        service.recordResponses = [
            [FakeWKWebsiteDataRecord(displayName: "old.example")],
            [FakeWKWebsiteDataRecord(displayName: "new.example")]
        ]
        service.recordFetchDelays = [50_000_000, 0]
        let manager = CacheManager(
            dataStore: .nonPersistent(),
            cleanupService: service
        )

        let first = Task { @MainActor in await manager.loadCacheData() }
        await Task.yield()
        let second = Task { @MainActor in await manager.loadCacheData() }
        await first.value
        await second.value

        XCTAssertEqual(manager.cacheEntries.map(\.domain), ["new.example"])
        XCTAssertFalse(manager.isLoading)
    }

    func testNoSynchronousWaitsRemainInCleanupPaths() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let paths = [
            "Sumi/Services/SumiWebsiteDataCleanupService.swift",
            "Sumi/Managers/CookieManager/CookieManager.swift",
            "Sumi/Managers/CacheManager/CacheManager.swift",
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
