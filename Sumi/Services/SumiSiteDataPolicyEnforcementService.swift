import Foundation
import WebKit

@MainActor
final class SumiSiteDataPolicyEnforcementService {
    static let shared = SumiSiteDataPolicyEnforcementService()

    private let policyStore: SumiSiteDataPolicyStore
    private let cleanupService: any SumiWebsiteDataCleanupServicing

    init(
        policyStore: SumiSiteDataPolicyStore? = nil,
        cleanupService: (any SumiWebsiteDataCleanupServicing)? = nil
    ) {
        self.policyStore = policyStore ?? .shared
        self.cleanupService = cleanupService ?? SumiWebsiteDataCleanupService.shared
    }

    func state(forHost host: String, profile: Profile?) -> SumiSiteDataPolicyState {
        policyStore.state(forHost: host, profileId: profile?.id)
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
            profileId: profile.id
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
            profileId: profile.id
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
        await cleanupService.removeWebsiteDataForExactHost(
            host,
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            includingCookies: true,
            in: profile.dataStore
        )
        await profile.refreshDataStoreStats()
    }

    private func normalizedHost(for url: URL?) -> String? {
        guard let url else { return nil }
        let host = HistoryDomainResolver.normalizedDomain(for: url)
            .normalizedWebsiteDataDomain
        return host.isEmpty ? nil : host
    }
}
