//
//  PrivacySettingsView.swift
//  Sumi
//
//  Created by Jonathan Caudill on 15/08/2025.
//

import SwiftUI
import WebKit

struct PrivacySettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @StateObject private var cookieManager = CookieManager()
    @StateObject private var cacheManager = CacheManager()
    @State private var showingCookieManager = false
    @State private var showingCacheManager = false
    @State private var isClearing = false
    @State private var clearingTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Cookie Management Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Cookie Management")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    cookieStatsView
                    
                    HStack {
                        Button("Manage Cookies") {
                            showingCookieManager = true
                        }
                        .buttonStyle(.bordered)
                        
                        Menu("Clear Data") {
                            Button("Clear Expired Cookies") {
                                clearExpiredCookies()
                            }
                            
                            Button("Clear Third-Party Cookies") {
                                clearThirdPartyCookies()
                            }
                            
                            Button("Clear High-Risk Cookies") {
                                clearHighRiskCookies()
                            }
                            
                            Divider()
                            
                            Button("Clear All Cookies") {
                                clearAllCookies()
                            }
                            
                            Button("Privacy Cleanup") {
                                performCookiePrivacyCleanup()
                            }
                            
                            Divider()
                            
                            Button("Clear All Website Data", role: .destructive) {
                                clearAllWebsiteData()
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isClearing)
                        
                        if isClearing {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            
            Divider()
            
            // Cache Management Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Cache Management")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    cacheStatsView
                    
                    HStack {
                        Button("Manage Cache") {
                            showingCacheManager = true
                        }
                        .buttonStyle(.bordered)
                        
                        Menu("Clear Cache") {
                            Button("Clear Stale Cache") {
                                clearStaleCache()
                            }
                            
                            Button("Clear Personal Data Cache") {
                                clearPersonalDataCache()
                            }
                            
                            Button("Clear Disk Cache") {
                                clearDiskCache()
                            }
                            
                            Button("Clear Memory Cache") {
                                clearMemoryCache()
                            }
                            
                            Divider()
                            
                            Button("Privacy Cleanup") {
                                performCachePrivacyCleanup()
                            }
                            
                            Divider()
                            
                            Button("Clear All Cache", role: .destructive) {
                                clearAllCache()
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isClearing)
                        
                        if isClearing {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            
            Divider()
            
            // Website Data Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Website Data")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    Button("Clear Browsing History") {
                        clearBrowsingHistory()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Clear Cache") {
                        clearCache()
                    }
                    .buttonStyle(.bordered)
                    
                                    }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            
            Spacer()
        }
        .padding()
        .frame(minWidth: 520, minHeight: 360)
        .task(id: browserManager.currentProfile?.id) {
            await synchronizeManagersWithCurrentProfile()
        }
        .onDisappear {
            cancelSettingsWork()
        }
        .sheet(isPresented: $showingCookieManager) {
            CookieManagementPanel(
                cookieManager: cookieManager,
                clearsLoadedDataOnDisappear: false
            )
        }
        .sheet(isPresented: $showingCacheManager) {
            CacheManagementPanel(
                cacheManager: cacheManager,
                clearsLoadedDataOnDisappear: false
            )
        }
    }

    private func cancelSettingsWork() {
        clearingTask?.cancel()
        clearingTask = nil
        isClearing = false
        cookieManager.clearLoadedData()
        cacheManager.clearLoadedData()
    }

    private func runClearingOperation(_ operation: @escaping @MainActor () async -> Void) {
        clearingTask?.cancel()
        isClearing = true
        clearingTask = Task { @MainActor in
            await operation()
            guard !Task.isCancelled else { return }
            isClearing = false
            clearingTask = nil
        }
    }
    
    // MARK: - Cache Stats View
    
    private var cacheStatsView: some View {
        let stats = cacheManager.getCacheStats()
        
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "internaldrive")
                    .foregroundColor(.blue)
                Text("Stored Cache")
                    .fontWeight(.medium)
                Spacer()
                Text("\(stats.total)")
                    .foregroundColor(.secondary)
            }
            
            if stats.total > 0 {
                HStack {
                    Spacer().frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Disk: \(formatSize(stats.diskSize))")
                            Text("•")
                            Text("Memory: \(formatSize(stats.memorySize))")
                            if stats.staleCount > 0 {
                                Text("•")
                                Text("Stale: \(stats.staleCount)")
                                    .foregroundColor(.orange)
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        Text("Total size: \(formatSize(stats.totalSize))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }
    
    // MARK: - Cookie Stats View
    
    private var cookieStatsView: some View {
        let stats = cookieManager.getCookieStats()
        
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.blue)
                Text("Stored Cookies")
                    .fontWeight(.medium)
                Spacer()
                Text("\(stats.total)")
                    .foregroundColor(.secondary)
            }
            
            if stats.total > 0 {
                HStack {
                    Spacer().frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Session: \(stats.session)")
                            Text("•")
                            Text("Persistent: \(stats.persistent)")
                            if stats.expired > 0 {
                                Text("•")
                                Text("Expired: \(stats.expired)")
                                    .foregroundColor(.orange)
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        Text("Total size: \(formatSize(stats.totalSize))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func clearExpiredCookies() {
        runClearingOperation {
            await cookieManager.deleteExpiredCookies()
        }
    }
    
    private func clearAllCookies() {
        runClearingOperation {
            await cookieManager.deleteAllCookies()
        }
    }
    
    private func clearAllWebsiteData() {
        runClearingOperation {
            for profile in browserManager.profileManager.profiles {
                await SumiWebsiteDataCleanupService.shared
                    .clearAllProfileWebsiteData(in: profile.dataStore)
            }
            await SumiWebsiteDataCleanupService.shared
                .clearAllProfileWebsiteData(in: WKWebsiteDataStore.default())
            await synchronizeManagersWithCurrentProfile()
        }
    }
    
    private func clearBrowsingHistory() {
        browserManager.clearAllHistoryFromMenu()
    }
    
    private func clearCache() {
        runClearingOperation {
            let cacheTypes: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache]
            for profile in browserManager.profileManager.profiles {
                await SumiWebsiteDataCleanupService.shared.removeWebsiteData(
                    ofTypes: cacheTypes,
                    modifiedSince: .distantPast,
                    in: profile.dataStore
                )
            }
            await SumiWebsiteDataCleanupService.shared.removeWebsiteData(
                ofTypes: cacheTypes,
                modifiedSince: .distantPast,
                in: WKWebsiteDataStore.default()
            )
            await synchronizeManagersWithCurrentProfile()
        }
    }
    
        
    // MARK: - Helper Methods
    
    // MARK: - Cache Action Methods
    
    private func clearStaleCache() {
        runClearingOperation {
            await cacheManager.clearStaleCache()
        }
    }
    
    private func clearDiskCache() {
        runClearingOperation {
            await cacheManager.clearDiskCache()
        }
    }
    
    private func clearMemoryCache() {
        runClearingOperation {
            await cacheManager.clearMemoryCache()
        }
    }
    
    private func clearAllCache() {
        runClearingOperation {
            await cacheManager.clearAllCache()
        }
    }
    
    // MARK: - Privacy-Compliant Actions
    
    private func clearThirdPartyCookies() {
        runClearingOperation {
            await cookieManager.deleteThirdPartyCookies()
        }
    }
    
    private func clearHighRiskCookies() {
        runClearingOperation {
            await cookieManager.deleteHighRiskCookies()
        }
    }
    
    private func performCookiePrivacyCleanup() {
        runClearingOperation {
            await cookieManager.performPrivacyCleanup()
        }
    }
    
    private func clearPersonalDataCache() {
        runClearingOperation {
            await cacheManager.clearPersonalDataCache()
        }
    }
    
    private func performCachePrivacyCleanup() {
        runClearingOperation {
            await cacheManager.performPrivacyCompliantCleanup()
        }
    }

    @MainActor
    private func synchronizeManagersWithCurrentProfile() async {
        if let profile = browserManager.currentProfile ?? browserManager.profileManager.profiles.first {
            cookieManager.switchDataStore(profile.dataStore, profileId: profile.id, eagerLoad: false)
            cacheManager.switchDataStore(profile.dataStore, profileId: profile.id, eagerLoad: false)
        }
        await cookieManager.loadCookies()
        guard !Task.isCancelled else { return }
        await cacheManager.loadCacheData()
    }
    
    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) bytes"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }
    
    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

#Preview {
    PrivacySettingsView()
        .environmentObject(BrowserManager())
}
