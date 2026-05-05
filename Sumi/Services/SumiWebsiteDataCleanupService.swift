import Foundation
import WebKit

@MainActor
protocol SumiWebsiteDataCleanupServicing: AnyObject {
    func fetchCookies(in dataStore: WKWebsiteDataStore) async -> [HTTPCookie]
    func fetchWebsiteDataRecords(
        ofTypes dataTypes: Set<String>,
        in dataStore: WKWebsiteDataStore
    ) async -> [WKWebsiteDataRecord]
    func fetchSiteDataEntries(
        forDomain domain: String,
        ofTypes dataTypes: Set<String>,
        in dataStore: WKWebsiteDataStore
    ) async -> [SumiSiteDataEntry]
    func removeCookies(
        _ selection: SumiCookieRemovalSelection,
        in dataStore: WKWebsiteDataStore
    ) async
    func removeWebsiteData(
        ofTypes dataTypes: Set<String>,
        modifiedSince date: Date,
        in dataStore: WKWebsiteDataStore
    ) async
    func removeWebsiteDataForDomain(
        _ domain: String,
        includingCookies: Bool,
        in dataStore: WKWebsiteDataStore
    ) async
    func removeWebsiteDataForExactHost(
        _ host: String,
        ofTypes dataTypes: Set<String>,
        includingCookies: Bool,
        in dataStore: WKWebsiteDataStore
    ) async
    func removeWebsiteDataForDomains(
        _ domains: Set<String>,
        ofTypes dataTypes: Set<String>,
        includingCookies: Bool,
        in dataStore: WKWebsiteDataStore
    ) async
    func clearAllProfileWebsiteData(in dataStore: WKWebsiteDataStore) async
}

struct SumiSiteDataEntry: Identifiable, Hashable, Sendable {
    let domain: String
    let cookieCount: Int
    let recordCount: Int

    var id: String { domain }
    var hasData: Bool { cookieCount > 0 || recordCount > 0 }
}

enum SumiWebsiteDataDomain {
    static func normalized(_ value: String) -> String {
        let trimmedValue = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutLeadingDot = trimmedValue.hasPrefix(".")
            ? String(trimmedValue.dropFirst())
            : trimmedValue
        return withoutLeadingDot.lowercased()
    }

    static func belongs(_ value: String, to domain: String) -> Bool {
        let normalizedValue = normalized(value)
        let normalizedDomain = normalized(domain)
        guard !normalizedValue.isEmpty, !normalizedDomain.isEmpty else {
            return false
        }
        if normalizedValue == normalizedDomain { return true }
        return normalizedValue.hasSuffix(".\(normalizedDomain)")
    }
}

enum SumiCookieRemovalSelection: Hashable, Sendable {
    case all
    case exactDomains(Set<String>)
    case domains(Set<String>)

    func matches(_ cookie: HTTPCookie) -> Bool {
        switch self {
        case .all:
            return true
        case .exactDomains(let domains):
            return domains.contains { cookie.belongsExactlyTo($0) }
        case .domains(let domains):
            return domains.contains { cookie.belongsTo($0) }
        }
    }
}

protocol SumiWebsiteDataPreservationPolicy: Sendable {
    func shouldPreserveCookie(_ cookie: HTTPCookie) -> Bool
    func shouldPreserveDataRecord(displayName: String) -> Bool
}

struct SumiEmptyWebsiteDataPreservationPolicy: SumiWebsiteDataPreservationPolicy {
    func shouldPreserveCookie(_ cookie: HTTPCookie) -> Bool {
        false
    }

    func shouldPreserveDataRecord(displayName: String) -> Bool {
        false
    }
}

@MainActor
protocol SumiWebsiteDataStore {
    associatedtype Record: SumiWebsiteDataRecord

    var httpCookieStore: any SumiHTTPCookieStore { get }

    func removeData(ofTypes types: Set<String>, modifiedSince: Date) async
    func dataRecords(ofTypes types: Set<String>) async -> [Record]
    func removeData(ofTypes types: Set<String>, for records: [Record]) async
}

@MainActor
protocol SumiHTTPCookieStore {
    func allCookies() async -> [HTTPCookie]
    func deleteCookie(_ cookie: HTTPCookie) async
}

@MainActor
protocol SumiWebsiteDataRecord {
    var displayName: String { get }
}

struct SumiWebsiteDataStoreWrapper: SumiWebsiteDataStore {
    let wrapped: WKWebsiteDataStore

    var httpCookieStore: any SumiHTTPCookieStore {
        SumiHTTPCookieStoreWrapper(wrapped: wrapped.httpCookieStore)
    }

    func removeData(ofTypes types: Set<String>, modifiedSince: Date) async {
        await wrapped.removeData(ofTypes: types, modifiedSince: modifiedSince)
    }

    func dataRecords(ofTypes types: Set<String>) async -> [WKWebsiteDataRecord] {
        await wrapped.dataRecords(ofTypes: types)
    }

    func removeData(ofTypes types: Set<String>, for records: [WKWebsiteDataRecord]) async {
        await wrapped.removeData(ofTypes: types, for: records)
    }
}

struct SumiHTTPCookieStoreWrapper: SumiHTTPCookieStore {
    let wrapped: WKHTTPCookieStore

    func allCookies() async -> [HTTPCookie] {
        await wrapped.allCookies()
    }

    func deleteCookie(_ cookie: HTTPCookie) async {
        await wrapped.deleteCookie(cookie)
    }
}

extension WKWebsiteDataRecord: SumiWebsiteDataRecord {}

@MainActor
final class SumiWebsiteDataCleanupService: SumiWebsiteDataCleanupServicing {
    static let shared = SumiWebsiteDataCleanupService()

    private let preservationPolicy: any SumiWebsiteDataPreservationPolicy
    private var inFlightCleanups: [CleanupKey: Task<Void, Never>] = [:]

    init(
        preservationPolicy: any SumiWebsiteDataPreservationPolicy =
            SumiEmptyWebsiteDataPreservationPolicy()
    ) {
        self.preservationPolicy = preservationPolicy
    }

    func fetchCookies(in dataStore: WKWebsiteDataStore) async -> [HTTPCookie] {
        await fetchCookies(
            using: SumiWebsiteDataStoreWrapper(wrapped: dataStore)
        )
    }

    func fetchCookies<Store: SumiWebsiteDataStore>(using store: Store) async -> [HTTPCookie] {
        await store.httpCookieStore.allCookies()
    }

    func fetchWebsiteDataRecords(
        ofTypes dataTypes: Set<String>,
        in dataStore: WKWebsiteDataStore
    ) async -> [WKWebsiteDataRecord] {
        await fetchWebsiteDataRecords(
            ofTypes: dataTypes,
            using: SumiWebsiteDataStoreWrapper(wrapped: dataStore)
        )
    }

    func fetchWebsiteDataRecords<Store: SumiWebsiteDataStore>(
        ofTypes dataTypes: Set<String>,
        using store: Store
    ) async -> [Store.Record] {
        await store.dataRecords(ofTypes: dataTypes)
    }

    func fetchSiteDataEntries(
        forDomain domain: String,
        ofTypes dataTypes: Set<String>,
        in dataStore: WKWebsiteDataStore
    ) async -> [SumiSiteDataEntry] {
        await fetchSiteDataEntries(
            forDomain: domain,
            ofTypes: dataTypes,
            using: SumiWebsiteDataStoreWrapper(wrapped: dataStore)
        )
    }

    func fetchSiteDataEntries<Store: SumiWebsiteDataStore>(
        forDomain domain: String,
        ofTypes dataTypes: Set<String>,
        using store: Store
    ) async -> [SumiSiteDataEntry] {
        let normalizedDomain = domain.normalizedWebsiteDataDomain
        guard !normalizedDomain.isEmpty else { return [] }

        let cookies = await store.httpCookieStore.allCookies()
        let records = await store.dataRecords(ofTypes: dataTypes)

        let cookieDomains = cookies
            .map { $0.domain.normalizedWebsiteDataDomain }
            .filter { $0.belongsToWebsiteDataDomain(normalizedDomain) }

        let recordDomains = records
            .map { $0.displayName.normalizedWebsiteDataDomain }
            .filter { $0.belongsToWebsiteDataDomain(normalizedDomain) }

        let domains = Set(cookieDomains + recordDomains).filter { !$0.isEmpty }
        return domains.map { entryDomain in
            SumiSiteDataEntry(
                domain: entryDomain,
                cookieCount: cookies.filter { $0.belongsExactlyTo(entryDomain) }.count,
                recordCount: records.filter {
                    $0.displayName.normalizedWebsiteDataDomain == entryDomain
                }.count
            )
        }
        .filter(\.hasData)
        .sorted { lhs, rhs in
            if lhs.domain == normalizedDomain { return true }
            if rhs.domain == normalizedDomain { return false }
            return lhs.domain.localizedStandardCompare(rhs.domain) == .orderedAscending
        }
    }

    func removeCookies(
        _ selection: SumiCookieRemovalSelection,
        in dataStore: WKWebsiteDataStore
    ) async {
        await removeCookies(
            selection,
            using: SumiWebsiteDataStoreWrapper(wrapped: dataStore),
            storeIdentifier: identifier(for: dataStore)
        )
    }

    func removeCookies<Store: SumiWebsiteDataStore>(
        _ selection: SumiCookieRemovalSelection,
        using store: Store,
        storeIdentifier: String
    ) async {
        await coalesced(
            operation: .removeCookies(selection),
            storeIdentifier: storeIdentifier
        ) {
            await self.performRemoveCookies(selection, using: store)
        }
    }

    func removeWebsiteData(
        ofTypes dataTypes: Set<String>,
        modifiedSince date: Date,
        in dataStore: WKWebsiteDataStore
    ) async {
        await removeWebsiteData(
            ofTypes: dataTypes,
            modifiedSince: date,
            using: SumiWebsiteDataStoreWrapper(wrapped: dataStore),
            storeIdentifier: identifier(for: dataStore)
        )
    }

    func removeWebsiteData<Store: SumiWebsiteDataStore>(
        ofTypes dataTypes: Set<String>,
        modifiedSince date: Date,
        using store: Store,
        storeIdentifier: String
    ) async {
        await coalesced(
            operation: .removeWebsiteData(types: dataTypes, modifiedSince: date),
            storeIdentifier: storeIdentifier
        ) {
            await store.removeData(ofTypes: dataTypes, modifiedSince: date)
        }
    }

    func removeWebsiteDataForDomain(
        _ domain: String,
        includingCookies: Bool,
        in dataStore: WKWebsiteDataStore
    ) async {
        await removeWebsiteDataForDomain(
            domain,
            includingCookies: includingCookies,
            using: SumiWebsiteDataStoreWrapper(wrapped: dataStore),
            storeIdentifier: identifier(for: dataStore)
        )
    }

    func removeWebsiteDataForDomains(
        _ domains: Set<String>,
        ofTypes dataTypes: Set<String>,
        includingCookies: Bool,
        in dataStore: WKWebsiteDataStore
    ) async {
        await removeWebsiteDataForDomains(
            domains,
            ofTypes: dataTypes,
            includingCookies: includingCookies,
            using: SumiWebsiteDataStoreWrapper(wrapped: dataStore),
            storeIdentifier: identifier(for: dataStore)
        )
    }

    func removeWebsiteDataForExactHost(
        _ host: String,
        ofTypes dataTypes: Set<String>,
        includingCookies: Bool,
        in dataStore: WKWebsiteDataStore
    ) async {
        await removeWebsiteDataForExactHost(
            host,
            ofTypes: dataTypes,
            includingCookies: includingCookies,
            using: SumiWebsiteDataStoreWrapper(wrapped: dataStore),
            storeIdentifier: identifier(for: dataStore)
        )
    }

    func removeWebsiteDataForDomains<Store: SumiWebsiteDataStore>(
        _ domains: Set<String>,
        ofTypes dataTypes: Set<String>,
        includingCookies: Bool,
        using store: Store,
        storeIdentifier: String
    ) async {
        let normalizedDomains = Set(
            domains
                .map(\.normalizedWebsiteDataDomain)
                .filter { !$0.isEmpty }
        )
        guard !normalizedDomains.isEmpty else { return }

        await coalesced(
            operation: .removeDomainsWebsiteData(
                domains: normalizedDomains,
                dataTypes: dataTypes,
                includingCookies: includingCookies
            ),
            storeIdentifier: storeIdentifier
        ) {
            await self.performRemoveWebsiteDataForDomains(
                normalizedDomains,
                ofTypes: dataTypes,
                includingCookies: includingCookies,
                using: store
            )
        }
    }

    func removeWebsiteDataForExactHost<Store: SumiWebsiteDataStore>(
        _ host: String,
        ofTypes dataTypes: Set<String>,
        includingCookies: Bool,
        using store: Store,
        storeIdentifier: String
    ) async {
        let normalizedHost = host.normalizedWebsiteDataDomain
        guard !normalizedHost.isEmpty else { return }

        await coalesced(
            operation: .removeExactHostWebsiteData(
                host: normalizedHost,
                dataTypes: dataTypes,
                includingCookies: includingCookies
            ),
            storeIdentifier: storeIdentifier
        ) {
            await self.performRemoveWebsiteDataForExactHost(
                normalizedHost,
                ofTypes: dataTypes,
                includingCookies: includingCookies,
                using: store
            )
        }
    }

    func removeWebsiteDataForDomain<Store: SumiWebsiteDataStore>(
        _ domain: String,
        includingCookies: Bool,
        using store: Store,
        storeIdentifier: String
    ) async {
        await coalesced(
            operation: .removeDomainWebsiteData(
                domain: domain.normalizedWebsiteDataDomain,
                includingCookies: includingCookies
            ),
            storeIdentifier: storeIdentifier
        ) {
            await self.performRemoveWebsiteDataForDomain(
                domain,
                includingCookies: includingCookies,
                using: store
            )
        }
    }

    func clearAllProfileWebsiteData(in dataStore: WKWebsiteDataStore) async {
        await clearAllProfileWebsiteData(
            using: SumiWebsiteDataStoreWrapper(wrapped: dataStore),
            storeIdentifier: identifier(for: dataStore)
        )
    }

    func clearAllProfileWebsiteData<Store: SumiWebsiteDataStore>(
        using store: Store,
        storeIdentifier: String
    ) async {
        await coalesced(
            operation: .clearAllProfileWebsiteData,
            storeIdentifier: storeIdentifier
        ) {
            await self.performClearAllProfileWebsiteData(using: store)
        }
    }

    private func performClearAllProfileWebsiteData<Store: SumiWebsiteDataStore>(
        using store: Store
    ) async {
        await store.removeData(
            ofTypes: WKWebsiteDataStore.safelyRemovableWebsiteDataTypes,
            modifiedSince: .distantPast
        )

        let records = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        let removableRecords = records.filter { record in
            !preservationPolicy.shouldPreserveDataRecord(displayName: record.displayName)
        }
        await store.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypesExceptCookies,
            for: removableRecords
        )

        await performRemoveCookies(.all, using: store)
    }

    private func performRemoveWebsiteDataForDomain<Store: SumiWebsiteDataStore>(
        _ domain: String,
        includingCookies: Bool,
        using store: Store
    ) async {
        let normalizedDomain = domain.normalizedWebsiteDataDomain
        guard !normalizedDomain.isEmpty else { return }

        let dataTypes = includingCookies
            ? WKWebsiteDataStore.allWebsiteDataTypes()
            : WKWebsiteDataStore.allWebsiteDataTypesExceptCookies
        await performRemoveWebsiteDataForDomains(
            [normalizedDomain],
            ofTypes: dataTypes,
            includingCookies: includingCookies,
            using: store
        )
    }

    private func performRemoveWebsiteDataForDomains<Store: SumiWebsiteDataStore>(
        _ normalizedDomains: Set<String>,
        ofTypes dataTypes: Set<String>,
        includingCookies: Bool,
        using store: Store
    ) async {
        let records = await store.dataRecords(ofTypes: dataTypes)
        let matchingRecords = records.filter { record in
            normalizedDomains.contains { domain in
                record.displayName.belongsToWebsiteDataDomain(domain)
            } && !preservationPolicy.shouldPreserveDataRecord(displayName: record.displayName)
        }

        await store.removeData(ofTypes: dataTypes, for: matchingRecords)

        if includingCookies {
            await performRemoveCookies(.domains(normalizedDomains), using: store)
        }
    }

    private func performRemoveWebsiteDataForExactHost<Store: SumiWebsiteDataStore>(
        _ normalizedHost: String,
        ofTypes dataTypes: Set<String>,
        includingCookies: Bool,
        using store: Store
    ) async {
        let records = await store.dataRecords(ofTypes: dataTypes)
        let matchingRecords = records.filter { record in
            record.displayName.normalizedWebsiteDataDomain == normalizedHost
                && !preservationPolicy.shouldPreserveDataRecord(displayName: record.displayName)
        }

        await store.removeData(ofTypes: dataTypes, for: matchingRecords)

        if includingCookies {
            await performRemoveCookies(.exactDomains([normalizedHost]), using: store)
        }
    }

    private func performRemoveCookies<Store: SumiWebsiteDataStore>(
        _ selection: SumiCookieRemovalSelection,
        using store: Store
    ) async {
        let cookieStore = store.httpCookieStore
        let cookies = await cookieStore.allCookies()
        let removableCookies = cookies.filter { cookie in
            selection.matches(cookie) && !preservationPolicy.shouldPreserveCookie(cookie)
        }

        for cookie in removableCookies {
            await cookieStore.deleteCookie(cookie)
        }
    }

    private func coalesced(
        operation: CleanupOperation,
        storeIdentifier: String,
        body: @escaping @MainActor () async -> Void
    ) async {
        let key = CleanupKey(storeIdentifier: storeIdentifier, operation: operation)
        if let inFlight = inFlightCleanups[key] {
            await inFlight.value
            return
        }

        let task = Task { @MainActor in
            await PerformanceTrace.withInterval("WebsiteDataCleanup.coalescedOperation") {
                await body()
            }
        }
        inFlightCleanups[key] = task
        await task.value
        inFlightCleanups[key] = nil
    }

    private func identifier(for dataStore: WKWebsiteDataStore) -> String {
        if let identifier = dataStore.identifier {
            return "identifier:\(identifier.uuidString)"
        }
        return "object:\(ObjectIdentifier(dataStore).hashValue)"
    }

    private struct CleanupKey: Hashable {
        let storeIdentifier: String
        let operation: CleanupOperation

        static func == (lhs: CleanupKey, rhs: CleanupKey) -> Bool {
            lhs.storeIdentifier == rhs.storeIdentifier
                && lhs.operation == rhs.operation
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(storeIdentifier)
            hasher.combine(operation)
        }
    }

    private enum CleanupOperation: Hashable {
        case clearAllProfileWebsiteData
        case removeCookies(SumiCookieRemovalSelection)
        case removeWebsiteData(types: Set<String>, modifiedSince: Date)
        case removeDomainWebsiteData(domain: String, includingCookies: Bool)
        case removeExactHostWebsiteData(
            host: String,
            dataTypes: Set<String>,
            includingCookies: Bool
        )
        case removeDomainsWebsiteData(
            domains: Set<String>,
            dataTypes: Set<String>,
            includingCookies: Bool
        )
    }
}

extension WKWebsiteDataStore {
    static var allWebsiteDataTypesExceptCookies: Set<String> {
        var types = Self.allWebsiteDataTypes()

        types.insert("_WKWebsiteDataTypeMediaKeys")
        types.insert("_WKWebsiteDataTypeHSTSCache")
        types.insert("_WKWebsiteDataTypeSearchFieldRecentSearches")
        types.insert("_WKWebsiteDataTypeResourceLoadStatistics")
        types.insert("_WKWebsiteDataTypeCredentials")
        types.insert("_WKWebsiteDataTypeAdClickAttributions")
        types.insert("_WKWebsiteDataTypePrivateClickMeasurements")
        types.insert("_WKWebsiteDataTypeAlternativeServices")

        types.remove(WKWebsiteDataTypeCookies)
        return types
    }

    static var safelyRemovableWebsiteDataTypes: Set<String> {
        var types = Self.allWebsiteDataTypesExceptCookies

        types.remove(WKWebsiteDataTypeLocalStorage)
        types.remove(WKWebsiteDataTypeIndexedDBDatabases)

        return types
    }

    static var sumiCacheDataTypes: Set<String> {
        [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeOfflineWebApplicationCache,
            WKWebsiteDataTypeWebSQLDatabases,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeSessionStorage,
            WKWebsiteDataTypeFetchCache,
            WKWebsiteDataTypeServiceWorkerRegistrations
        ]
    }

}

extension HTTPCookie {
    func belongsTo(_ eTLDPlus1Domain: String) -> Bool {
        let normalizedCookieDomain = domain.normalizedWebsiteDataDomain
        let normalizedDomain = eTLDPlus1Domain.normalizedWebsiteDataDomain
        guard !normalizedCookieDomain.isEmpty, !normalizedDomain.isEmpty else {
            return false
        }
        if normalizedCookieDomain == normalizedDomain { return true }
        return normalizedCookieDomain.hasSuffix(".\(normalizedDomain)")
    }

    func belongsExactlyTo(_ host: String) -> Bool {
        domain.normalizedWebsiteDataDomain == host.normalizedWebsiteDataDomain
    }
}

extension String {
    var normalizedWebsiteDataDomain: String {
        SumiWebsiteDataDomain.normalized(self)
    }

    func belongsToWebsiteDataDomain(_ domain: String) -> Bool {
        SumiWebsiteDataDomain.belongs(self, to: domain)
    }
}
