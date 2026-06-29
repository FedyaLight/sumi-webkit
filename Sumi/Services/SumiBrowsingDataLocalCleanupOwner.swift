import Foundation

@MainActor
final class SumiBrowsingDataLocalCleanupOwner {
    private let faviconCacheCleaner: any SumiBrowsingDataFaviconCleaning
    private let basicAuthCredentialStore: any SumiBasicAuthCredentialCleaning
    private let visitedLinkStore: any SumiVisitedLinkStoreReplacing

    init(
        faviconCacheCleaner: any SumiBrowsingDataFaviconCleaning,
        basicAuthCredentialStore: any SumiBasicAuthCredentialCleaning,
        visitedLinkStore: any SumiVisitedLinkStoreReplacing
    ) {
        self.faviconCacheCleaner = faviconCacheCleaner
        self.basicAuthCredentialStore = basicAuthCredentialStore
        self.visitedLinkStore = visitedLinkStore
    }

    func clearHistory(
        query: HistoryQuery,
        range: SumiBrowsingDataTimeRange,
        historyProfileId: UUID?,
        targetProfileIds: Set<UUID>,
        includeAllProfiles: Bool,
        historyManager: HistoryManager,
        referenceDate: Date,
        domains: Set<String>
    ) async {
        let historyVisitCount = await countVisits(
            matching: query,
            profileId: historyProfileId,
            referenceDate: referenceDate,
            historyManager: historyManager
        )
        guard historyVisitCount > 0 else { return }

        if !includeAllProfiles, historyProfileId == historyManager.currentProfileId {
            if range == .allTime {
                await historyManager.clearAll()
            } else {
                await historyManager.delete(query: query)
            }
            return
        }

        do {
            let deletedCount = try await historyManager.store.deleteVisits(
                matching: query,
                profileId: historyProfileId,
                referenceDate: referenceDate,
                calendar: .autoupdatingCurrent
            )
            guard deletedCount > 0 else { return }
        } catch {
            RuntimeDiagnostics.emit("Error clearing browsing history: \(error)")
            return
        }

        for profileId in targetProfileIds {
            do {
                try await reloadVisitedLinks(for: profileId, historyManager: historyManager)
            } catch {
                RuntimeDiagnostics.emit(
                    "Error reloading visited links after browsing history cleanup for profile \(profileId.uuidString): \(error)"
                )
            }
        }

        await clearHistoryFavicons(
            range: range,
            domains: domains,
            historyProfileId: historyProfileId,
            historyManager: historyManager
        )
        await historyManager.refreshAfterExternalMutation()
    }

    func clearSavedHTTPAuthCredentialsIfNeeded(
        range: SumiBrowsingDataTimeRange,
        categories: Set<SumiBrowsingDataCategory>,
        targetProfileIds: Set<UUID>
    ) {
        guard range == .allTime,
              categories == SumiBrowsingDataCategory.defaultSelection
        else { return }

        for profileId in targetProfileIds {
            let didDelete = basicAuthCredentialStore.deleteCredentials(
                profilePartitionId: profileId,
                isEphemeralProfile: false
            )
            if !didDelete {
                RuntimeDiagnostics.emit(
                    "Error clearing saved HTTP auth credentials for profile \(profileId.uuidString)"
                )
            }
        }
    }

    func clearFaviconCacheIfNeeded(
        range: SumiBrowsingDataTimeRange,
        categories: Set<SumiBrowsingDataCategory>,
        domains: Set<String>
    ) async {
        guard categories.contains(.cache) else { return }
        guard !categories.contains(.history) else { return }
        let savedLogins = basicAuthCredentialStore.allCredentialHosts()

        if range == .allTime {
            await faviconCacheCleaner.burnAfterHistoryClear(savedLogins: savedLogins)
        } else if !domains.isEmpty {
            await faviconCacheCleaner.burnDomains(
                domains,
                remainingHistoryHosts: [],
                savedLogins: savedLogins
            )
        }
    }

    func invalidateSiteDataFavicons(
        domains: Set<String>,
        partition: SumiFaviconPartition
    ) {
        for domain in domains {
            faviconCacheCleaner.invalidateSite(domain: domain, partition: partition)
        }
    }

    private func countVisits(
        matching query: HistoryQuery,
        profileId: UUID?,
        referenceDate: Date,
        historyManager: HistoryManager
    ) async -> Int {
        do {
            return try await historyManager.store.countVisits(
                matching: query,
                profileId: profileId,
                referenceDate: referenceDate,
                calendar: .autoupdatingCurrent
            )
        } catch {
            RuntimeDiagnostics.emit("Error counting browsing history: \(error)")
            return 0
        }
    }

    private func clearHistoryFavicons(
        range: SumiBrowsingDataTimeRange,
        domains: Set<String>,
        historyProfileId: UUID?,
        historyManager: HistoryManager
    ) async {
        let savedLogins = basicAuthCredentialStore.allCredentialHosts()

        if range == .allTime {
            await faviconCacheCleaner.burnAfterHistoryClear(savedLogins: savedLogins)
        } else if !domains.isEmpty {
            do {
                let remainingHosts = try await historyManager.store.remainingHistoryHosts(
                    forSiteDomains: domains,
                    profileId: historyProfileId
                )
                await faviconCacheCleaner.burnDomains(
                    domains,
                    remainingHistoryHosts: remainingHosts,
                    savedLogins: savedLogins
                )
            } catch {
                RuntimeDiagnostics.emit("Error clearing browsing history favicons: \(error)")
            }
        }
    }

    private func reloadVisitedLinks(
        for profileId: UUID,
        historyManager: HistoryManager
    ) async throws {
        let urls = try await historyManager.store.fetchVisitedURLs(profileId: profileId)
        visitedLinkStore.replaceVisitedLinks(urls, for: profileId)
    }
}
