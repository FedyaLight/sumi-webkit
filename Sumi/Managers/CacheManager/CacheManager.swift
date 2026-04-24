//
//  CacheManager.swift
//  Sumi
//
//  Created by Jonathan Caudill on 15/08/2025.
//

import Foundation
import WebKit
import SwiftUI

@MainActor
class CacheManager: ObservableObject {
    // Active data store for cache operations. Switchable per profile.
    private var dataStore: WKWebsiteDataStore?
    private let cleanupService: any SumiWebsiteDataCleanupServicing
    private var refreshGeneration: UInt64 = 0
    // Optional profile context for diagnostics and profiling
    var currentProfileId: UUID?
    @Published private(set) var cacheEntries: [CacheInfo] = []
    @Published private(set) var domainGroups: [DomainCacheGroup] = []
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
    /// Clears in-memory state and optionally reloads cache data from the new store.
    func switchDataStore(_ newDataStore: WKWebsiteDataStore, profileId: UUID? = nil, eagerLoad: Bool = true) {
        self.dataStore = newDataStore
        self.currentProfileId = profileId
        clearLoadedData()
        RuntimeDiagnostics.emit("🔁 [CacheManager] Switched data store -> profile: \(profileId?.uuidString ?? "nil"), persistent: \(newDataStore.isPersistent)")
        if eagerLoad {
            Task { [weak self] in await self?.loadCacheData() }
        }
    }

    func clearLoadedData() {
        refreshGeneration &+= 1
        cacheEntries.removeAll(keepingCapacity: false)
        domainGroups.removeAll(keepingCapacity: false)
        isLoading = false
    }
    
    // MARK: - Public Methods
    
    func loadCacheData() async {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        isLoading = true
        defer {
            if refreshGeneration == generation && !Task.isCancelled {
                isLoading = false
            }
        }
        
        let dataStore = activeDataStore()
        let records = await cleanupService.fetchWebsiteDataRecords(
            ofTypes: WKWebsiteDataStore.sumiCacheDataTypes,
            in: dataStore
        )
        guard refreshGeneration == generation, !Task.isCancelled else { return }
        let cacheInfos = records.map { CacheInfo(from: $0) }
        
        self.cacheEntries = cacheInfos
        self.domainGroups = self.groupCacheByDomain(cacheInfos)
    }
    
    func clearCacheForDomain(_ domain: String) async {
        let dataStore = activeDataStore()
        await cleanupService.removeWebsiteDataForDomain(
            domain,
            includingCookies: false,
            in: dataStore
        )
        await loadCacheData()
    }

    /// Clears site data for a specific domain, excluding cookies
    /// to support a "hard refresh" that does not sign the user out.
    func clearCacheForDomainExcludingCookies(_ domain: String) async {
        let dataStore = activeDataStore()
        await cleanupService.removeWebsiteDataForDomain(
            domain,
            includingCookies: false,
            in: dataStore
        )
        await loadCacheData()
    }
    
    func clearDiskCache() async {
        let dataStore = activeDataStore()
        await cleanupService.removeWebsiteData(
            ofTypes: [WKWebsiteDataTypeDiskCache],
            modifiedSince: .distantPast,
            in: dataStore
        )
        await loadCacheData()
    }
    
    func clearMemoryCache() async {
        let dataStore = activeDataStore()
        await cleanupService.removeWebsiteData(
            ofTypes: [WKWebsiteDataTypeMemoryCache],
            modifiedSince: .distantPast,
            in: dataStore
        )
        await loadCacheData()
    }
    
    func clearStaleCache() async {
        let dataStore = activeDataStore()
        // Clear cache older than 30 days
        let thirtyDaysAgo = Date().addingTimeInterval(-2592000) // 30 days
        await cleanupService.removeWebsiteData(
            ofTypes: WKWebsiteDataStore.sumiCacheDataTypes,
            modifiedSince: thirtyDaysAgo,
            in: dataStore
        )
        await loadCacheData()
    }
    
    // MARK: - Privacy-Compliant Cache Management
    
    func clearPersonalDataCache() async {
        let dataStore = activeDataStore()
        await cleanupService.removeWebsiteData(
            ofTypes: WKWebsiteDataStore.sumiPersonalDataCacheTypes,
            modifiedSince: .distantPast,
            in: dataStore
        )
        await loadCacheData()
    }
    
    func performPrivacyCompliantCleanup() async {
        let dataStore = activeDataStore()
        let ninetyDaysAgo = Date().addingTimeInterval(-7776000) // 90 days
        await cleanupService.removeWebsiteData(
            ofTypes: WKWebsiteDataStore.sumiCacheDataTypes,
            modifiedSince: ninetyDaysAgo,
            in: dataStore
        )

        let thirtyDaysAgo = Date().addingTimeInterval(-2592000)
        await cleanupService.removeWebsiteData(
            ofTypes: WKWebsiteDataStore.sumiPersonalDataCacheTypes,
            modifiedSince: thirtyDaysAgo,
            in: dataStore
        )
        await loadCacheData()
    }
    
    func clearAllCache() async {
        let dataStore = activeDataStore()
        await cleanupService.removeWebsiteData(
            ofTypes: WKWebsiteDataStore.sumiCacheDataTypes,
            modifiedSince: .distantPast,
            in: dataStore
        )
        await loadCacheData()
        
        // Also clear favicon cache
        Tab.clearFaviconCache()
    }
    
    func clearSpecificCache(_ cache: CacheInfo) async {
        let dataStore = activeDataStore()
        await cleanupService.removeWebsiteDataForDomain(
            cache.domain,
            includingCookies: false,
            in: dataStore
        )
        await loadCacheData()
    }

    // MARK: - Favicon Cache Management
    
    func clearFaviconCache() {
        // Favicon cache is global by design (shared across profiles for better reuse)
        // Only diagnostics include the current profile context.
        RuntimeDiagnostics.emit("🧹 [CacheManager] Clearing favicon cache for profile=\(currentProfileId?.uuidString ?? "nil") [global cache]")
        Tab.clearFaviconCache()
    }
    
    func getFaviconCacheStats() -> (count: Int, domains: [String]) {
        let stats = Tab.getFaviconCacheStats()
        RuntimeDiagnostics.emit("📊 [CacheManager] Favicon cache stats for profile=\(currentProfileId?.uuidString ?? "nil"): count=\(stats.count)")
        return stats
    }
    
    func searchCache(_ query: String) -> [CacheInfo] {
        guard !query.isEmpty else { return cacheEntries }
        
        let lowercaseQuery = query.lowercased()
        return cacheEntries.filter { cache in
            cache.domain.lowercased().contains(lowercaseQuery) ||
            cache.dataTypes.joined(separator: " ").lowercased().contains(lowercaseQuery)
        }
    }
    
    func filterCache(_ filter: CacheFilter) -> [CacheInfo] {
        return cacheEntries.filter { filter.matches($0) }
    }
    
    func sortCache(_ cacheEntries: [CacheInfo], by sortOption: CacheSortOption, ascending: Bool = true) -> [CacheInfo] {
        let sorted = cacheEntries.sorted { lhs, rhs in
            switch sortOption {
            case .domain:
                return lhs.displayDomain < rhs.displayDomain
            case .size:
                return lhs.size < rhs.size
            case .lastModified:
                // Handle nil dates
                switch (lhs.lastModified, rhs.lastModified) {
                case (nil, nil):
                    return false
                case (nil, _):
                    return false // Recent items first
                case (_, nil):
                    return true
                case (let lhsDate?, let rhsDate?):
                    return lhsDate < rhsDate
                }
            case .type:
                return lhs.primaryCacheType.rawValue < rhs.primaryCacheType.rawValue
            }
        }
        
        return ascending ? sorted : sorted.reversed()
    }
    
    func getCacheStats() -> (total: Int, totalSize: Int64, diskSize: Int64, memorySize: Int64, staleCount: Int) {
        let totalSize = cacheEntries.reduce(0) { $0 + $1.size }
        let diskSize = cacheEntries.reduce(0) { $0 + $1.diskUsage }
        let memorySize = cacheEntries.reduce(0) { $0 + $1.memoryUsage }
        let staleCount = cacheEntries.filter { $0.isStale }.count
        let stats = (
            total: cacheEntries.count,
            totalSize: totalSize,
            diskSize: diskSize,
            memorySize: memorySize,
            staleCount: staleCount
        )
        RuntimeDiagnostics.emit("📊 [CacheManager] Stats for profile=\(currentProfileId?.uuidString ?? "nil"): total=\(stats.total), size=\(stats.totalSize), disk=\(stats.diskSize), mem=\(stats.memorySize), stale=\(stats.staleCount)")
        return stats
    }
    
    func getLargestCacheDomains(limit: Int = 10) -> [DomainCacheGroup] {
        return domainGroups
            .sorted { $0.totalSize > $1.totalSize }
            .prefix(limit)
            .map { $0 }
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
    
    private func groupCacheByDomain(_ cacheEntries: [CacheInfo]) -> [DomainCacheGroup] {
        let grouped = Dictionary(grouping: cacheEntries) { cache in
            // Normalize domain for grouping
            cache.domain.hasPrefix(".") ? String(cache.domain.dropFirst()) : cache.domain
        }
        
        return grouped.map { domain, caches in
            DomainCacheGroup(
                id: UUID(),
                domain: domain,
                cacheEntries: caches.sorted { $0.size > $1.size }
            )
        }.sorted { $0.displayDomain < $1.displayDomain }
    }
}

// MARK: - Cache Management Extensions

extension CacheManager {
    func exportCacheData() -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        do {
            let data = try encoder.encode(cacheEntries)
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            RuntimeDiagnostics.emit("Error exporting cache data: \(error)")
            return ""
        }
    }
    
    func getCacheDetails(_ cache: CacheInfo) -> [String: String] {
        var details: [String: String] = [:]
        
        details["Domain"] = cache.domain
        details["Total Size"] = cache.sizeDescription
        details["Disk Usage"] = cache.diskUsageDescription
        details["Memory Usage"] = cache.memoryUsageDescription
        details["Cache Types"] = cache.cacheTypes.map { $0.rawValue }.joined(separator: ", ")
        details["Last Modified"] = cache.lastModifiedDescription
        details["Status"] = cache.isStale ? "Stale" : "Fresh"
        details["Primary Type"] = cache.primaryCacheType.rawValue
        
        return details
    }
    
    func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    func getCacheEfficiencyRecommendations() -> [String] {
        var recommendations: [String] = []
        
        let stats = getCacheStats()
        let stalePercentage = stats.total > 0 ? Double(stats.staleCount) / Double(stats.total) : 0.0
        
        if stalePercentage > 0.3 {
            recommendations.append("Consider clearing stale cache (>30% of cache is outdated)")
        }
        
        if stats.totalSize > 1073741824 { // 1GB
            recommendations.append("Cache size is large (\(formatSize(stats.totalSize))). Consider clearing old cache.")
        }
        
        let largeDomains = getLargestCacheDomains(limit: 3)
        if let largest = largeDomains.first, largest.totalSize > 104857600 { // 100MB
            recommendations.append("Largest cache domain: \(largest.displayDomain) (\(largest.totalSizeDescription))")
        }
        
        if recommendations.isEmpty {
            recommendations.append("Cache is efficiently managed!")
        }
        
        return recommendations
    }
}
