import Foundation
import WebKit
import WKAbstractions

@MainActor
protocol SumiWebsiteDataCleanupServicing: AnyObject {
    func fetchCookies(in dataStore: WKWebsiteDataStore) async -> [HTTPCookie]
    func fetchWebsiteDataRecords(
        ofTypes dataTypes: Set<String>,
        in dataStore: WKWebsiteDataStore
    ) async -> [WKWebsiteDataRecord]
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
    func clearAllProfileWebsiteData(in dataStore: WKWebsiteDataStore) async
}

struct SumiCookieIdentifier: Hashable, Sendable {
    let name: String
    let domain: String
    let path: String

    init(name: String, domain: String, path: String) {
        self.name = name
        self.domain = domain
        self.path = path
    }

    init(cookie: HTTPCookie) {
        self.init(name: cookie.name, domain: cookie.domain, path: cookie.path)
    }

    init(cookie: CookieInfo) {
        self.init(name: cookie.name, domain: cookie.domain, path: cookie.path)
    }

    func matches(_ cookie: HTTPCookie) -> Bool {
        cookie.name == name && cookie.domain == domain && cookie.path == path
    }
}

enum SumiCookieRemovalSelection: Hashable, Sendable {
    case all
    case exact(SumiCookieIdentifier)
    case domains(Set<String>)
    case expired(referenceDate: Date)
    case highRisk
    case thirdParty

    func matches(_ cookie: HTTPCookie) -> Bool {
        switch self {
        case .all:
            return true
        case .exact(let identifier):
            return identifier.matches(cookie)
        case .domains(let domains):
            return domains.contains { cookie.belongsTo($0) }
        case .expired(let referenceDate):
            guard let expiresDate = cookie.expiresDate else { return false }
            return expiresDate < referenceDate
        case .highRisk:
            return CookieInfo(from: cookie).privacyRisk == .high
        case .thirdParty:
            return cookie.domain.hasPrefix(".")
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
            using: WebsiteDataStoreWrapper(wrapped: dataStore)
        )
    }

    func fetchCookies<Store: DDGWebsiteDataStore>(using store: Store) async -> [HTTPCookie] {
        await store.httpCookieStore.allCookies()
    }

    func fetchWebsiteDataRecords(
        ofTypes dataTypes: Set<String>,
        in dataStore: WKWebsiteDataStore
    ) async -> [WKWebsiteDataRecord] {
        await fetchWebsiteDataRecords(
            ofTypes: dataTypes,
            using: WebsiteDataStoreWrapper(wrapped: dataStore)
        )
    }

    func fetchWebsiteDataRecords<Store: DDGWebsiteDataStore>(
        ofTypes dataTypes: Set<String>,
        using store: Store
    ) async -> [Store.Record] {
        await store.dataRecords(ofTypes: dataTypes)
    }

    func removeCookies(
        _ selection: SumiCookieRemovalSelection,
        in dataStore: WKWebsiteDataStore
    ) async {
        await removeCookies(
            selection,
            using: WebsiteDataStoreWrapper(wrapped: dataStore),
            storeIdentifier: identifier(for: dataStore)
        )
    }

    func removeCookies<Store: DDGWebsiteDataStore>(
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
            using: WebsiteDataStoreWrapper(wrapped: dataStore),
            storeIdentifier: identifier(for: dataStore)
        )
    }

    func removeWebsiteData<Store: DDGWebsiteDataStore>(
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
            using: WebsiteDataStoreWrapper(wrapped: dataStore),
            storeIdentifier: identifier(for: dataStore)
        )
    }

    func removeWebsiteDataForDomain<Store: DDGWebsiteDataStore>(
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
            using: WebsiteDataStoreWrapper(wrapped: dataStore),
            storeIdentifier: identifier(for: dataStore)
        )
    }

    func clearAllProfileWebsiteData<Store: DDGWebsiteDataStore>(
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

    private func performClearAllProfileWebsiteData<Store: DDGWebsiteDataStore>(
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

    private func performRemoveWebsiteDataForDomain<Store: DDGWebsiteDataStore>(
        _ domain: String,
        includingCookies: Bool,
        using store: Store
    ) async {
        let normalizedDomain = domain.normalizedWebsiteDataDomain
        guard !normalizedDomain.isEmpty else { return }

        let records = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        let matchingRecords = records.filter { record in
            record.displayName.belongsToWebsiteDataDomain(normalizedDomain)
                && !preservationPolicy.shouldPreserveDataRecord(displayName: record.displayName)
        }

        let dataTypes = includingCookies
            ? WKWebsiteDataStore.allWebsiteDataTypes()
            : WKWebsiteDataStore.allWebsiteDataTypesExceptCookies
        await store.removeData(ofTypes: dataTypes, for: matchingRecords)

        if includingCookies {
            await performRemoveCookies(.domains([normalizedDomain]), using: store)
        }
    }

    private func performRemoveCookies<Store: DDGWebsiteDataStore>(
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
            await body()
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
    }

    private enum CleanupOperation: Hashable {
        case clearAllProfileWebsiteData
        case removeCookies(SumiCookieRemovalSelection)
        case removeWebsiteData(types: Set<String>, modifiedSince: Date)
        case removeDomainWebsiteData(domain: String, includingCookies: Bool)
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
        if #available(macOS 12.2, *) {
            types.remove(WKWebsiteDataTypeIndexedDBDatabases)
        }

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

    static var sumiPersonalDataCacheTypes: Set<String> {
        [
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeSessionStorage,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeWebSQLDatabases
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
}

private extension String {
    var normalizedWebsiteDataDomain: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingPrefix(".")
            .lowercased()
    }

    func belongsToWebsiteDataDomain(_ domain: String) -> Bool {
        let normalizedSelf = normalizedWebsiteDataDomain
        let normalizedDomain = domain.normalizedWebsiteDataDomain
        guard !normalizedSelf.isEmpty, !normalizedDomain.isEmpty else {
            return false
        }
        if normalizedSelf == normalizedDomain { return true }
        return normalizedSelf.hasSuffix(".\(normalizedDomain)")
    }

    func trimmingPrefix(_ prefix: String) -> String {
        guard hasPrefix(prefix) else { return self }
        return String(dropFirst(prefix.count))
    }
}
