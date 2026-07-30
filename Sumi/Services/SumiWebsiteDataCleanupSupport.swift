import Foundation
import SumiDomain
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
    @discardableResult
    func removePersistentDataStore(forIdentifier identifier: UUID) async -> Bool
    @discardableResult
    func prunePersistentDataStores(keeping identifiersToKeep: Set<UUID>) async -> [UUID]
}

struct SumiSiteDataEntry: Identifiable, Hashable, Sendable {
    let domain: String
    let cookieCount: Int
    let recordCount: Int

    var id: String { domain }
    var hasData: Bool { cookieCount > 0 || recordCount > 0 }
}

enum SumiWebsiteDataDomain {
    private static let siteNormalizer = SumiSiteNormalizer()

    static func normalized(_ value: String) -> String {
        siteNormalizer.host(fromRawHost: value) ?? ""
    }

    static func belongs(_ value: String, to domain: String) -> Bool {
        let normalizedValue = normalized(value)
        let normalizedDomain = siteNormalizer.siteDomain(fromRawDomain: domain) ?? ""
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
    /// Constructive writes belong to `SumiProfileCookieInstallationService`;
    /// this store stays the sole owner of destructive mutation.
    func setCookie(_ cookie: HTTPCookie) async
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

    func setCookie(_ cookie: HTTPCookie) async {
        await wrapped.setCookie(cookie)
    }
}

extension WKWebsiteDataRecord: SumiWebsiteDataRecord {}
