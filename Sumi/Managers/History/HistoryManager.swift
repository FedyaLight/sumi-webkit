//
//  HistoryManager.swift
//  Sumi
//

import Foundation
import SwiftData

@MainActor
final class HistoryManager: ObservableObject {
    @Published private(set) var revision: UInt = 0
    @Published private(set) var canClearHistory = false

    private static let cleanupDefaultsKey =
        "\(SumiAppIdentity.runtimeBundleIdentifier).history.lastCleanupAt"
    private static let cleanupInterval: TimeInterval = 24 * 60 * 60
    private static let deferredCleanupDelayNanoseconds: UInt64 = 10_000_000_000
    private static let recentMenuLimit = HistoryStore.defaultRecentMenuLimit

    let store: HistoryStore
    lazy var dataProvider = HistoryViewDataProvider(
        store: store,
        currentProfileIdProvider: { [weak self] in
            self?.currentProfileId
        }
    )

    private let maxHistoryDays = 100
    private var cleanupTask: Task<Void, Never>?
    private var changeTask: Task<Void, Never>?
    private var scheduledRefreshTask: Task<Void, Never>?
    private var visitedLinkPreloadTask: Task<Void, Never>?
    private var recentVisitedCache: [HistoryListItem] = []
    private static let changeRefreshDebounceNanoseconds: UInt64 = 120_000_000

    var currentProfileId: UUID?

    init(context: ModelContext, profileId: UUID? = nil) {
        self.store = HistoryStore(container: context.container)
        self.currentProfileId = profileId
        scheduleDeferredHistoryCleanupIfNeeded()
        preloadVisitedLinksForCurrentProfile()
        Task { [weak self] in
            await self?.refreshSummary(incrementRevision: false)
        }
    }

    deinit {
        cleanupTask?.cancel()
        changeTask?.cancel()
        scheduledRefreshTask?.cancel()
        visitedLinkPreloadTask?.cancel()
    }

    func switchProfile(_ profileId: UUID?) {
        currentProfileId = profileId
        preloadVisitedLinksForCurrentProfile()
        scheduledRefreshTask?.cancel()
        recentVisitedCache = []
        canClearHistory = false
        Task { [weak self] in
            await self?.refreshSummary(incrementRevision: true)
        }
    }

    @discardableResult
    func addVisit(
        url: URL,
        title: String,
        timestamp: Date = Date(),
        tabId: UUID?,
        profileId: UUID? = nil,
        isEphemeral: Bool = false
    ) -> UUID? {
        guard !isEphemeral else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }

        let visitID = UUID()
        let targetProfileId = profileId ?? currentProfileId
        scheduleHistoryChange { store in
            _ = try await store.recordVisit(
                id: visitID,
                url: url,
                title: title,
                visitedAt: timestamp,
                profileId: targetProfileId,
                tabId: tabId
            )
        }
        return visitID
    }

    func updateTitleIfNeeded(
        title: String,
        url: URL,
        profileId: UUID? = nil,
        isEphemeral: Bool = false
    ) {
        guard !isEphemeral else { return }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return
        }

        let targetProfileId = profileId ?? currentProfileId
        scheduleHistoryChange { store in
            try await store.updateTitleIfNeeded(
                title: title,
                url: url,
                profileId: targetProfileId
            )
        }
    }

    private func scheduleHistoryChange(
        _ operation: @escaping @Sendable (HistoryStore) async throws -> Void
    ) {
        let previousTask = changeTask
        changeTask = Task { [weak self] in
            await previousTask?.value
            guard let self else { return }
            do {
                try await operation(store)
                scheduleCoalescedSummaryRefresh()
            } catch {
                RuntimeDiagnostics.emit("Error updating history: \(error)")
            }
        }
    }

    private func scheduleCoalescedSummaryRefresh() {
        scheduledRefreshTask?.cancel()
        scheduledRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.changeRefreshDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.refreshSummary(incrementRevision: true)
        }
    }

    private func refreshSummary(incrementRevision: Bool) async {
        await dataProvider.refreshData()
        canClearHistory = await dataProvider.hasHistory()
        recentVisitedCache = await dataProvider.recentVisitedItems(maxCount: Self.recentMenuLimit)
        if incrementRevision {
            revision &+= 1
        }
    }

    func ranges() -> [HistoryRangeCount] {
        dataProvider.ranges
    }

    func recentVisitedItems(maxCount: Int = 12) -> [HistoryListItem] {
        Array(recentVisitedCache.prefix(maxCount))
    }

    func searchSuggestions(
        matching query: String,
        limit: Int = HistoryStore.defaultSuggestionLimit
    ) async -> [HistoryListItem] {
        await dataProvider.searchSuggestions(matching: query, limit: limit)
    }

    func topVisitedSites(limit: Int = HistoryStore.defaultRecentMenuLimit) async -> [HistoryListItem] {
        await dataProvider.topVisitedSites(limit: limit)
    }

    func historyPage(
        query: HistoryQuery,
        searchTerm: String? = nil,
        limit: Int = HistoryStore.defaultHistoryPageLimit,
        offset: Int = 0
    ) async -> HistoryListPage {
        await dataProvider.page(
            for: query,
            searchTerm: searchTerm,
            limit: limit,
            offset: offset
        )
    }

    func countVisits(matching query: HistoryQuery) async -> Int {
        do {
            return try await store.countVisits(
                matching: query,
                profileId: currentProfileId,
                referenceDate: Date(),
                calendar: .autoupdatingCurrent
            )
        } catch {
            RuntimeDiagnostics.emit("Error counting history visits: \(error)")
            return 0
        }
    }

    func visitDomains(matching query: HistoryQuery) async -> Set<String> {
        await dataProvider.visitDomains(for: query)
    }

    func delete(query: HistoryQuery) async {
        let faviconDomains = await faviconBurnDomains(for: query)
        await dataProvider.deleteVisits(matching: query)
        reloadVisitedLinksForCurrentProfile()
        if !faviconDomains.isEmpty {
            let remainingHosts = await dataProvider.remainingHistoryHosts(forSiteDomains: faviconDomains)
            await SumiFaviconSystem.shared.burnDomains(
                faviconDomains,
                remainingHistoryHosts: remainingHosts,
                savedLogins: BasicAuthCredentialStore().allCredentialHosts()
            )
        }
        await refreshSummary(incrementRevision: false)
        revision &+= 1
    }

    func deleteSelection(
        visitIDs: [VisitIdentifier],
        domains: Set<String>
    ) async {
        await dataProvider.deleteSelection(visitIDs: visitIDs, domains: domains)
        reloadVisitedLinksForCurrentProfile()
        if !domains.isEmpty {
            let remainingHosts = await dataProvider.remainingHistoryHosts(forSiteDomains: domains)
            await SumiFaviconSystem.shared.burnDomains(
                domains,
                remainingHistoryHosts: remainingHosts,
                savedLogins: BasicAuthCredentialStore().allCredentialHosts()
            )
        }
        await refreshSummary(incrementRevision: false)
        revision &+= 1
    }

    func clearAll() async {
        await dataProvider.clearAll()
        reloadVisitedLinksForCurrentProfile()
        await SumiFaviconSystem.shared.burnAfterHistoryClear(
            savedLogins: BasicAuthCredentialStore().allCredentialHosts()
        )
        await refreshSummary(incrementRevision: false)
        revision &+= 1
    }

    private func faviconBurnDomains(for query: HistoryQuery) async -> Set<String> {
        switch query {
        case .domainFilter(let domains):
            return domains
        case .dateFilter(_), .timeRange(_, _):
            return await dataProvider.visitDomains(for: query)
        case .rangeFilter(let range) where range != .all && range != .allSites:
            return await dataProvider.visitDomains(for: query)
        case .searchTerm, .rangeFilter, .visits:
            return []
        }
    }

    private func scheduleDeferredHistoryCleanupIfNeeded() {
        guard shouldRunHistoryCleanup() else { return }

        cleanupTask?.cancel()
        cleanupTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.deferredCleanupDelayNanoseconds)
            guard !Task.isCancelled else { return }
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
        let cutoffDate = Calendar.autoupdatingCurrent.date(
            byAdding: .day,
            value: -maxHistoryDays,
            to: Date()
        ) ?? .distantPast

        do {
            let deletedCount = try await store.deleteVisits(
                matching: .timeRange(start: .distantPast, end: cutoffDate),
                profileId: currentProfileId,
                referenceDate: Date(),
                calendar: .autoupdatingCurrent
            )
            if deletedCount > 0 {
                reloadVisitedLinksForCurrentProfile()
                await refreshSummary(incrementRevision: true)
            }
            UserDefaults.standard.set(Date(), forKey: Self.cleanupDefaultsKey)
        } catch {
            RuntimeDiagnostics.emit("Error during deferred history cleanup: \(error)")
        }
    }

    private func preloadVisitedLinksForCurrentProfile() {
        guard let profileId = currentProfileId else { return }
        visitedLinkPreloadTask?.cancel()
        visitedLinkPreloadTask = Task { [store] in
            do {
                let urls = try await store.fetchVisitedURLs(profileId: profileId)
                await MainActor.run {
                    SharedVisitedLinkStoreProvider.shared.preloadVisitedLinks(
                        urls,
                        for: profileId
                    )
                }
            } catch {
                await MainActor.run {
                    RuntimeDiagnostics.emit("Error preloading visited links: \(error)")
                }
            }
        }
    }

    private func reloadVisitedLinksForCurrentProfile() {
        guard let profileId = currentProfileId else { return }
        visitedLinkPreloadTask?.cancel()
        visitedLinkPreloadTask = Task { [store] in
            do {
                let urls = try await store.fetchVisitedURLs(profileId: profileId)
                await MainActor.run {
                    SharedVisitedLinkStoreProvider.shared.replaceVisitedLinks(
                        urls,
                        for: profileId
                    )
                }
            } catch {
                await MainActor.run {
                    RuntimeDiagnostics.emit("Error reloading visited links: \(error)")
                }
            }
        }
    }
}
