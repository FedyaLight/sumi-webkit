//
//  HistoryManager.swift
//  Sumi
//

import Foundation
import History
import SwiftData

@MainActor
final class HistoryManager: ObservableObject {
    @Published private(set) var revision: UInt = 0

    private static let cleanupDefaultsKey =
        "\(SumiAppIdentity.runtimeBundleIdentifier).history.lastCleanupAt"
    private static let cleanupInterval: TimeInterval = 24 * 60 * 60
    private static let deferredCleanupDelayNanoseconds: UInt64 = 10_000_000_000

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

    var currentProfileId: UUID?

    init(context: ModelContext, profileId: UUID? = nil) {
        self.store = HistoryStore(container: context.container)
        self.currentProfileId = profileId
        scheduleDeferredHistoryCleanupIfNeeded()
        Task { [weak self] in
            await self?.refresh()
        }
    }

    deinit {
        cleanupTask?.cancel()
        changeTask?.cancel()
    }

    func switchProfile(_ profileId: UUID?) {
        currentProfileId = profileId
        Task { [weak self] in
            await self?.refresh()
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
                await refresh()
            } catch {
                RuntimeDiagnostics.emit("Error updating history: \(error)")
            }
        }
    }

    func refresh() async {
        await dataProvider.refreshData()
        revision &+= 1
    }

    func ranges() -> [HistoryRangeCount] {
        dataProvider.ranges
    }

    func recentVisitedItems(maxCount: Int = 12) -> [HistoryListItem] {
        dataProvider.recentVisitedItems(maxCount: maxCount)
    }

    func searchSuggestions(
        matching query: String,
        limit: Int = 20
    ) -> [HistoryListItem] {
        dataProvider.searchSuggestions(matching: query, limit: limit)
    }

    var canClearHistory: Bool {
        dataProvider.canClearHistory
    }

    func delete(query: HistoryQuery) async {
        await dataProvider.deleteVisits(matching: query)
        if case .domainFilter(let domains) = query, !domains.isEmpty {
            await SumiFaviconSystem.shared.burnDomains(
                domains,
                remainingHistory: currentBrowsingHistory(),
                savedLogins: BasicAuthCredentialStore().allCredentialHosts()
            )
        }
        revision &+= 1
    }

    func deleteSelection(
        visitIDs: [VisitIdentifier],
        domains: Set<String>
    ) async {
        await dataProvider.deleteSelection(visitIDs: visitIDs, domains: domains)
        if !domains.isEmpty {
            await SumiFaviconSystem.shared.burnDomains(
                domains,
                remainingHistory: currentBrowsingHistory(),
                savedLogins: BasicAuthCredentialStore().allCredentialHosts()
            )
        }
        revision &+= 1
    }

    func clearAll() async {
        await dataProvider.clearAll()
        await SumiFaviconSystem.shared.burnAfterHistoryClear(
            savedLogins: BasicAuthCredentialStore().allCredentialHosts()
        )
        revision &+= 1
    }

    private func currentBrowsingHistory() -> BrowsingHistory {
        let visits = dataProvider.rawVisits
        return visits.map { visit in
            HistoryEntry(
                identifier: visit.id,
                url: visit.url,
                title: visit.title,
                failedToLoad: false,
                numberOfTotalVisits: 1,
                lastVisit: visit.visitedAt,
                visits: [],
                numberOfTrackersBlocked: 0,
                blockedTrackingEntities: [],
                trackersFound: false
            )
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
        let visits = (try? await store.visits(profileId: currentProfileId)) ?? []
        let cutoffDate = Calendar.autoupdatingCurrent.date(
            byAdding: .day,
            value: -maxHistoryDays,
            to: Date()
        ) ?? .distantPast
        let ids = Set(visits.filter { $0.visitedAt < cutoffDate }.map(\.id))

        do {
            _ = try await store.deleteVisits(withIDs: ids, profileId: currentProfileId)
            await refresh()
            UserDefaults.standard.set(Date(), forKey: Self.cleanupDefaultsKey)
        } catch {
            RuntimeDiagnostics.emit("Error during deferred history cleanup: \(error)")
        }
    }
}
