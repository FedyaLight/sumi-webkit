//
//  HistoryManager.swift
//  Sumi
//
//  Created by Jonathan Caudill on 09/08/2025.
//

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
class HistoryManager {
    private static let cleanupDefaultsKey =
        "\(SumiAppIdentity.runtimeBundleIdentifier).history.lastCleanupAt"
    private static let cleanupInterval: TimeInterval = 24 * 60 * 60
    private static let deferredCleanupDelayNanoseconds: UInt64 = 10_000_000_000

    private let context: ModelContext
    private let backgroundWriter: HistoryBackgroundWriter
    private let maxHistoryDays: Int = 100
    @ObservationIgnored private var cleanupTask: Task<Void, Never>?
    var currentProfileId: UUID?
    
    init(context: ModelContext, profileId: UUID? = nil) {
        self.context = context
        self.backgroundWriter = HistoryBackgroundWriter(container: context.container)
        self.currentProfileId = profileId
        scheduleDeferredHistoryCleanupIfNeeded()
    }

    deinit {
        cleanupTask?.cancel()
    }

    // MARK: - Profile Switching
    func switchProfile(_ profileId: UUID?) {
        self.currentProfileId = profileId
        RuntimeDiagnostics.emit("🔁 [HistoryManager] Switched to profile: \(profileId?.uuidString ?? "nil")")
    }
    
    // MARK: - Public Methods
    
    func addVisit(url: URL, title: String, timestamp: Date = Date(), tabId: UUID?, profileId: UUID? = nil, isEphemeral: Bool = false) {
        guard !isEphemeral else { return }
        guard url.scheme == "http" || url.scheme == "https" else { return }

        let skipPatterns = ["about:", "webkit-extension:", "safari-web-extension:"]
        if skipPatterns.contains(where: { url.absoluteString.hasPrefix($0) }) {
            return
        }

        let targetProfileId = profileId ?? currentProfileId
        Task.detached { [backgroundWriter] in
            await backgroundWriter.recordVisit(
                urlString: url.absoluteString,
                title: title,
                timestamp: timestamp,
                tabId: tabId,
                profileId: targetProfileId,
                fallbackHost: url.host
            )
        }
    }
    
    func getHistory(days: Int = 7, page: Int = 0, pageSize: Int = 50) -> (entries: [HistoryEntry], hasMore: Bool) {
        do {
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            let profileFilter = currentProfileId
            // Fetch by date only; apply profile filtering in-memory for stability
            let basePredicate = #Predicate<HistoryEntity> { e in e.lastVisited >= cutoffDate }
            // First get total count by date
            let countDescriptor = FetchDescriptor<HistoryEntity>(predicate: basePredicate)
            let totalCount = (try? context.fetchCount(countDescriptor)) ?? 0
            // Then get paginated results by date, sorted by recency
            var descriptor = FetchDescriptor<HistoryEntity>(
                predicate: basePredicate,
                sortBy: [SortDescriptor(\.lastVisited, order: .reverse)]
            )
            descriptor.fetchLimit = pageSize
            descriptor.fetchOffset = page * pageSize
            
            let entities = try context.fetch(descriptor)
            let filteredByProfile: [HistoryEntity]
            if let pf = profileFilter {
                filteredByProfile = entities.filter { $0.profileId == pf || $0.profileId == nil }
            } else {
                filteredByProfile = entities
            }
            let entries = filteredByProfile.map { HistoryEntry(from: $0) }
            let hasMore = (page + 1) * pageSize < totalCount
            
            return (entries: entries, hasMore: hasMore)
        } catch {
            RuntimeDiagnostics.emit("Error fetching paginated history: \(error)")
            return (entries: [], hasMore: false)
        }
    }
    
    func searchHistory(query: String, page: Int = 0, pageSize: Int = 50) -> (entries: [HistoryEntry], hasMore: Bool) {
        guard !query.isEmpty else { return getHistory(page: page, pageSize: pageSize) }
        
        do {
            // For search, we need to fetch more than needed and filter in memory
            // This is a limitation of SwiftData's predicate system for complex text searches
            let profileFilter = currentProfileId
            var descriptor = FetchDescriptor<HistoryEntity>(
                sortBy: [SortDescriptor(\.lastVisited, order: .reverse)]
            )
            // Limit memory usage for search - fetch reasonable subset for filtering
            descriptor.fetchLimit = min(5000, maxResults)
            
            let entities = try context.fetch(descriptor)
            // Apply text filtering and profile filtering
            let filteredEntities = entities.filter { entity in
                entity.title.localizedCaseInsensitiveContains(query) ||
                entity.url.localizedCaseInsensitiveContains(query)
            }.filter { entity in
                guard let pf = profileFilter else { return true }
                return entity.profileId == pf || entity.profileId == nil
            }
            
            // Apply pagination to filtered results
            let startIndex = page * pageSize
            let endIndex = min(startIndex + pageSize, filteredEntities.count)
            
            guard startIndex < filteredEntities.count else {
                return (entries: [], hasMore: false)
            }
            
            let pageEntries = Array(filteredEntities[startIndex..<endIndex])
            let hasMore = endIndex < filteredEntities.count
            
            return (entries: pageEntries.map { HistoryEntry(from: $0) }, hasMore: hasMore)
        } catch {
            RuntimeDiagnostics.emit("Error searching history: \(error)")
            return (entries: [], hasMore: false)
        }
    }
    
    private let maxResults: Int = 10000
    
    func clearHistory(olderThan days: Int = 0, profileId: UUID? = nil) {
        do {
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            let pf = profileId ?? currentProfileId
            // Fetch by date only; profile filtering in-memory for stability
            let datePredicate = #Predicate<HistoryEntity> { e in e.visitDate < cutoffDate }
            let descriptor = FetchDescriptor<HistoryEntity>(predicate: datePredicate)
            var entitiesToDelete = try context.fetch(descriptor)
            if let p = pf {
                entitiesToDelete = entitiesToDelete.filter { $0.profileId == p }
            }
            for entity in entitiesToDelete {
                context.delete(entity)
            }
            
            try context.save()
            if let p = pf {
                RuntimeDiagnostics.emit("Cleared \(entitiesToDelete.count) history entries older than \(days) days for profile=\(p.uuidString)")
            } else {
                RuntimeDiagnostics.emit("Cleared \(entitiesToDelete.count) history entries older than \(days) days (all profiles)")
            }
        } catch {
            RuntimeDiagnostics.emit("Error clearing history: \(error)")
        }
    }
    
    func deleteHistoryEntry(_ entryId: UUID) {
        do {
            let eid = entryId
            let predicate = #Predicate<HistoryEntity> { e in e.id == eid }
            let descriptor = FetchDescriptor<HistoryEntity>(predicate: predicate)
            
            if let entity = try context.fetch(descriptor).first {
                context.delete(entity)
                try context.save()
            }
        } catch {
            RuntimeDiagnostics.emit("Error deleting history entry: \(error)")
        }
    }
    
    // MARK: - Private Methods

    private func scheduleDeferredHistoryCleanupIfNeeded() {
        guard shouldRunHistoryCleanup() else { return }

        cleanupTask?.cancel()
        cleanupTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: Self.deferredCleanupDelayNanoseconds
            )
            guard Task.isCancelled == false else { return }
            await self?.runDeferredHistoryCleanupIfNeeded()
        }
    }

    private func shouldRunHistoryCleanup(referenceDate: Date = Date()) -> Bool {
        guard let lastCleanup = UserDefaults.standard.object(
            forKey: Self.cleanupDefaultsKey
        ) as? Date else {
            return true
        }

        return referenceDate.timeIntervalSince(lastCleanup) >= Self.cleanupInterval
    }

    private func runDeferredHistoryCleanupIfNeeded() async {
        guard shouldRunHistoryCleanup() else { return }

        await cleanupOldHistory()
        UserDefaults.standard.set(Date(), forKey: Self.cleanupDefaultsKey)
    }
    
    private func cleanupOldHistory() async {
        clearHistory(olderThan: maxHistoryDays)
    }

}

// MARK: - HistoryEntry Model

struct HistoryEntry: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let title: String
    let visitCount: Int
    let lastVisited: Date
    
    init(from entity: HistoryEntity) {
        self.id = entity.id
        self.url = URL(string: entity.url) ?? SumiSurface.emptyTabURL
        self.title = entity.title
        self.visitCount = entity.visitCount
        self.lastVisited = entity.lastVisited
    }
    
    var displayTitle: String {
        return title.isEmpty ? (url.host ?? "Unknown") : title
    }
    
    var displayURL: String {
        return url.absoluteString
    }
    
}

// MARK: - Background Writer

/// Performs history write operations (addVisit) off the main actor to avoid
/// blocking the UI with SwiftData fetches during page navigation.
actor HistoryBackgroundWriter {
    private let container: ModelContainer
    private var pendingSaveTask: Task<Void, Never>?

    init(container: ModelContainer) {
        self.container = container
    }

    func recordVisit(
        urlString: String,
        title: String,
        timestamp: Date,
        tabId: UUID?,
        profileId: UUID?,
        fallbackHost: String?
    ) {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false

        do {
            let predicate = #Predicate<HistoryEntity> { entity in
                entity.url == urlString
            }
            let existing = try ctx.fetch(FetchDescriptor<HistoryEntity>(predicate: predicate))

            let existingEntrySameProfile = existing.first(where: { $0.profileId == profileId })
            let existingEntryNilProfile = existing.first(where: { $0.profileId == nil })
            let existingEntry = existingEntrySameProfile ?? existingEntryNilProfile

            if let existingEntry {
                existingEntry.visitCount += 1
                existingEntry.lastVisited = timestamp
                existingEntry.title = title.isEmpty ? existingEntry.title : title
                existingEntry.tabId = tabId
                if existingEntry.profileId == nil {
                    existingEntry.profileId = profileId
                }
            } else {
                let newEntry = HistoryEntity(
                    url: urlString,
                    title: title.isEmpty ? (fallbackHost ?? "Unknown") : title,
                    visitDate: timestamp,
                    tabId: tabId,
                    visitCount: 1,
                    lastVisited: timestamp,
                    profileId: profileId
                )
                ctx.insert(newEntry)
            }

            scheduleSave(ctx: ctx)
        } catch {
            RuntimeDiagnostics.emit("Error saving history entry: \(error)")
        }
    }

    private func scheduleSave(ctx: ModelContext) {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, self != nil else { return }
            do {
                try ctx.save()
            } catch {
                RuntimeDiagnostics.emit("Error flushing history changes: \(error)")
            }
        }
    }
}
