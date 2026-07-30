import Foundation
import WebKit

@MainActor
final class SumiSiteDataPolicyEnforcementService {
    private let policyStore: SumiSiteDataPolicyStore
    private let cleanupService: any SumiWebsiteDataCleanupServicing
    var destructiveCleanupPreparer: (any SumiDestructiveBrowsingDataCleanupPreparing)?

    init(
        policyStore: SumiSiteDataPolicyStore,
        cleanupService: any SumiWebsiteDataCleanupServicing
    ) {
        self.policyStore = policyStore
        self.cleanupService = cleanupService
    }

    func replacingCleanupService(
        _ cleanupService: any SumiWebsiteDataCleanupServicing
    ) -> SumiSiteDataPolicyEnforcementService {
        let replacement = SumiSiteDataPolicyEnforcementService(
            policyStore: policyStore,
            cleanupService: cleanupService
        )
        replacement.destructiveCleanupPreparer = destructiveCleanupPreparer
        return replacement
    }

    func attachDestructiveCleanupPreparer(
        _ preparer: (any SumiDestructiveBrowsingDataCleanupPreparing)?
    ) {
        destructiveCleanupPreparer = preparer
    }

    func setBlockStorage(
        _ isEnabled: Bool,
        forHost host: String,
        profile: Profile?
    ) async {
        guard let profile else { return }
        let normalizedHost = host.normalizedWebsiteDataDomain
        guard !normalizedHost.isEmpty else { return }

        policyStore.setBlockStorage(
            isEnabled,
            forHost: normalizedHost,
            profileId: profile.id,
            isEphemeralProfile: profile.isEphemeral
        )

        if isEnabled {
            await removeAllData(forHost: normalizedHost, profile: profile)
        }
    }

    func setDeleteWhenAllWindowsClosed(
        _ isEnabled: Bool,
        forHost host: String,
        profile: Profile?
    ) {
        guard let profile else { return }
        policyStore.setDeleteWhenAllWindowsClosed(
            isEnabled,
            forHost: host,
            profileId: profile.id,
            isEphemeralProfile: profile.isEphemeral
        )
    }

    func enforceBlockStorageIfNeeded(for url: URL?, profile: Profile?) {
        guard
            let profile,
            let host = normalizedHost(for: url),
            policyStore.state(forHost: host, profileId: profile.id).blockStorage
        else {
            return
        }

        Task { @MainActor [weak self, weak profile] in
            guard let self, let profile else { return }
            await self.removeAllData(forHost: host, profile: profile)
        }
    }

    func performAllWindowsClosedCleanup(profiles: [Profile]) async {
        for profile in profiles where !profile.isEphemeral {
            let hosts = policyStore.hostsDeletingWhenAllWindowsClosed(
                profileId: profile.id
            )
            for host in hosts {
                await removeAllData(forHost: host, profile: profile)
            }
        }
    }

    private func removeAllData(forHost host: String, profile: Profile) async {
        guard let destructiveCleanupPreparer else { return }
        let didRemove = await destructiveCleanupPreparer.performDestructiveDataCleanup(
            profileIDs: [profile.id]
        ) {
            await self.cleanupService.removeWebsiteDataForExactHost(
                host,
                ofTypes: WKWebsiteDataStore.sumiManualFullCleanupDataTypes,
                includingCookies: true,
                in: profile.dataStore
            )
        }
        guard didRemove else { return }
        await profile.refreshDataStoreStats(cleanupService: cleanupService)
    }

    private func normalizedHost(for url: URL?) -> String? {
        guard let url else { return nil }
        let host = HistoryDomainResolver.normalizedDomain(for: url)
            .normalizedWebsiteDataDomain
        return host.isEmpty ? nil : host
    }
}
