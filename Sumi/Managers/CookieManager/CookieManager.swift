//
//  CookieManager.swift
//  Sumi
//
//  Created by Jonathan Caudill on 15/08/2025.
//

import Foundation
import WebKit
import SwiftUI

@MainActor
class CookieManager: ObservableObject {
    // Active data store for cookie operations. Switchable per profile.
    private var dataStore: WKWebsiteDataStore?
    private let cleanupService: any SumiWebsiteDataCleanupServicing
    private var refreshGeneration: UInt64 = 0
    // Optional profile context for diagnostics and profiling
    var currentProfileId: UUID?
    @Published private(set) var cookies: [CookieInfo] = []
    @Published private(set) var domainGroups: [DomainCookieGroup] = []
    @Published private(set) var isLoading: Bool = false
    
    init(
        dataStore: WKWebsiteDataStore? = nil,
        cleanupService: (any SumiWebsiteDataCleanupServicing)? = nil
    ) {
        self.dataStore = dataStore
        self.cleanupService = cleanupService ?? SumiWebsiteDataCleanupService.shared
    }

    // MARK: - Profile Switching
    /// Switch the underlying data store to operate within a different profile boundary.
    /// Clears in-memory state and optionally reloads cookies from the new store.
    func switchDataStore(_ newDataStore: WKWebsiteDataStore, profileId: UUID? = nil, eagerLoad: Bool = true) {
        self.dataStore = newDataStore
        self.currentProfileId = profileId
        clearLoadedData()
        RuntimeDiagnostics.emit("🔁 [CookieManager] Switched data store -> profile: \(profileId?.uuidString ?? "nil"), persistent: \(newDataStore.isPersistent)")
        if eagerLoad {
            Task { [weak self] in await self?.loadCookies() }
        }
    }

    func clearLoadedData() {
        refreshGeneration &+= 1
        cookies.removeAll(keepingCapacity: false)
        domainGroups.removeAll(keepingCapacity: false)
        isLoading = false
    }
    
    // MARK: - Public Methods
    
    func loadCookies() async {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        isLoading = true
        defer {
            if refreshGeneration == generation && !Task.isCancelled {
                isLoading = false
            }
        }
        
        let dataStore = activeDataStore()
        let httpCookies = await cleanupService.fetchCookies(in: dataStore)
        guard refreshGeneration == generation, !Task.isCancelled else { return }
        let cookieInfos = httpCookies.map { CookieInfo(from: $0) }
        
        self.cookies = cookieInfos
        self.domainGroups = self.groupCookiesByDomain(cookieInfos)
    }
    
    func deleteCookie(_ cookie: CookieInfo) async {
        let dataStore = activeDataStore()
        await cleanupService.removeCookies(
            .exact(SumiCookieIdentifier(cookie: cookie)),
            in: dataStore
        )
        await loadCookies()
    }
    
    func deleteCookiesForDomain(_ domain: String) async {
        let dataStore = activeDataStore()
        await cleanupService.removeCookies(.domains([domain]), in: dataStore)
        await loadCookies()
    }
    
    func deleteAllCookies() async {
        let dataStore = activeDataStore()
        await cleanupService.removeCookies(.all, in: dataStore)
        await loadCookies()
    }
    
    func deleteExpiredCookies() async {
        let dataStore = activeDataStore()
        await cleanupService.removeCookies(
            .expired(referenceDate: Date()),
            in: dataStore
        )
        await loadCookies()
    }
    
    // MARK: - Privacy-Compliant Cookie Management
    
    func deleteHighRiskCookies() async {
        let dataStore = activeDataStore()
        await cleanupService.removeCookies(.highRisk, in: dataStore)
        await loadCookies()
    }
    
    func deleteThirdPartyCookies() async {
        let dataStore = activeDataStore()
        await cleanupService.removeCookies(.thirdParty, in: dataStore)
        await loadCookies()
    }
    
    func performPrivacyCleanup() async {
        let dataStore = activeDataStore()
        await cleanupService.removeCookies(
            .expired(referenceDate: Date()),
            in: dataStore
        )
        await cleanupService.removeCookies(.highRisk, in: dataStore)
        await loadCookies()
    }
    
    func searchCookies(_ query: String) -> [CookieInfo] {
        guard !query.isEmpty else { return cookies }
        
        let lowercaseQuery = query.lowercased()
        return cookies.filter { cookie in
            cookie.name.lowercased().contains(lowercaseQuery) ||
            cookie.domain.lowercased().contains(lowercaseQuery) ||
            cookie.value.lowercased().contains(lowercaseQuery)
        }
    }
    
    func filterCookies(_ filter: CookieFilter) -> [CookieInfo] {
        return cookies.filter { filter.matches($0) }
    }
    
    func sortCookies(_ cookies: [CookieInfo], by sortOption: CookieSortOption, ascending: Bool = true) -> [CookieInfo] {
        let sorted = cookies.sorted { lhs, rhs in
            switch sortOption {
            case .domain:
                return lhs.displayDomain < rhs.displayDomain
            case .name:
                return lhs.name < rhs.name
            case .size:
                return lhs.size < rhs.size
            case .expiration:
                // Handle nil expiration dates (session cookies)
                switch (lhs.expiresDate, rhs.expiresDate) {
                case (nil, nil):
                    return false // Equal
                case (nil, _):
                    return true // Session cookies first
                case (_, nil):
                    return false // Session cookies first
                case (let lhsDate?, let rhsDate?):
                    return lhsDate < rhsDate
                }
            }
        }
        
        return ascending ? sorted : sorted.reversed()
    }
    
    func getCookieStats() -> (total: Int, session: Int, persistent: Int, expired: Int, totalSize: Int) {
        let sessionCount = cookies.filter { $0.isSessionCookie }.count
        let persistentCount = cookies.count - sessionCount
        let expiredCount = cookies.filter { cookie in
            guard let expiresDate = cookie.expiresDate else { return false }
            return expiresDate < Date()
        }.count
        let totalSize = cookies.reduce(0) { $0 + $1.size }
        
        let stats = (
            total: cookies.count,
            session: sessionCount,
            persistent: persistentCount,
            expired: expiredCount,
            totalSize: totalSize
        )
        // Debug diagnostics with profile context
        RuntimeDiagnostics.emit("📊 [CookieManager] Stats for profile=\(currentProfileId?.uuidString ?? "nil"): total=\(stats.total), session=\(stats.session), persistent=\(stats.persistent), expired=\(stats.expired), size=\(stats.totalSize)")
        return stats
    }
    
    // MARK: - Private Methods

    private func activeDataStore() -> WKWebsiteDataStore {
        if let dataStore {
            return dataStore
        }

        let fallback = WKWebsiteDataStore.nonPersistent()
        dataStore = fallback
        return fallback
    }
    
    private func groupCookiesByDomain(_ cookies: [CookieInfo]) -> [DomainCookieGroup] {
        let grouped = Dictionary(grouping: cookies) { cookie in
            // Normalize domain for grouping
            cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
        }
        
        return grouped.map { domain, cookies in
            DomainCookieGroup(id: UUID(), domain: domain, cookies: cookies.sorted { $0.name < $1.name })
        }.sorted { $0.displayDomain < $1.displayDomain }
    }
}

// MARK: - Cookie Management Extensions

extension CookieManager {
    func getCookieDetails(_ cookie: CookieInfo) -> [String: String] {
        var details: [String: String] = [:]
        
        details["Name"] = cookie.name
        details["Value"] = cookie.value.count > 100 ? String(cookie.value.prefix(100)) + "..." : cookie.value
        details["Domain"] = cookie.domain
        details["Path"] = cookie.path
        details["Size"] = cookie.sizeDescription
        details["Secure"] = cookie.isSecure ? "Yes" : "No"
        details["HTTP Only"] = cookie.isHTTPOnly ? "Yes" : "No"
        details["Same Site"] = cookie.sameSitePolicy
        details["Expires"] = cookie.expirationStatus
        
        return details
    }
}
