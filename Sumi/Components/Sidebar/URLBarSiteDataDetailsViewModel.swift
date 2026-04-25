import Combine
import Foundation
import WebKit

@MainActor
final class URLBarSiteDataDetailsViewModel: ObservableObject {
    @Published private(set) var entries: [SumiSiteDataEntry] = []
    @Published private(set) var policyStates: [String: SumiSiteDataPolicyState] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var deletingHosts: Set<String> = []
    @Published private(set) var errorMessage: String?

    private let cleanupService: any SumiWebsiteDataCleanupServicing
    private let policyStore: SumiSiteDataPolicyStore
    private let enforcementService: SumiSiteDataPolicyEnforcementService
    private var loadGeneration: UInt64 = 0

    init(
        cleanupService: (any SumiWebsiteDataCleanupServicing)? = nil,
        policyStore: SumiSiteDataPolicyStore? = nil,
        enforcementService: SumiSiteDataPolicyEnforcementService? = nil
    ) {
        self.cleanupService = cleanupService ?? SumiWebsiteDataCleanupService.shared
        self.policyStore = policyStore ?? .shared
        self.enforcementService = enforcementService ?? .shared
    }

    func load(url: URL?, profile: Profile?) async {
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        defer {
            if generation == loadGeneration {
                isLoading = false
            }
        }

        guard
            let profile,
            let rootDomain = rootDomain(for: url)
        else {
            entries = []
            policyStates = [:]
            return
        }

        let fetchedEntries = await cleanupService.fetchSiteDataEntries(
            forDomain: rootDomain,
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            in: profile.dataStore
        )
        guard generation == loadGeneration else { return }

        let currentHost = normalizedHost(for: url)
        let policyHosts = policyStore.hostsWithPolicies(profileId: profile.id)
            .filter { $0.belongsToWebsiteDataDomain(rootDomain) }

        var entriesByDomain = Dictionary(
            uniqueKeysWithValues: fetchedEntries.map { ($0.domain, $0) }
        )
        for host in policyHosts where entriesByDomain[host] == nil {
            entriesByDomain[host] = SumiSiteDataEntry(
                domain: host,
                cookieCount: 0,
                recordCount: 0
            )
        }

        let resolvedEntries = sort(
            Array(entriesByDomain.values),
            currentHost: currentHost,
            rootDomain: rootDomain
        )
        entries = resolvedEntries
        policyStates = Dictionary(
            uniqueKeysWithValues: resolvedEntries.map {
                ($0.domain, policyStore.state(forHost: $0.domain, profileId: profile.id))
            }
        )
    }

    func delete(entry: SumiSiteDataEntry, url: URL?, profile: Profile?) async {
        guard let profile else { return }
        let host = entry.domain.normalizedWebsiteDataDomain
        guard !host.isEmpty else { return }

        deletingHosts.insert(host)
        defer { deletingHosts.remove(host) }

        await cleanupService.removeWebsiteDataForExactHost(
            host,
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            includingCookies: true,
            in: profile.dataStore
        )
        await profile.refreshDataStoreStats()
        await load(url: url, profile: profile)
    }

    func setBlockStorage(
        _ isEnabled: Bool,
        for entry: SumiSiteDataEntry,
        url: URL?,
        profile: Profile?
    ) async {
        await enforcementService.setBlockStorage(
            isEnabled,
            forHost: entry.domain,
            profile: profile
        )
        await load(url: url, profile: profile)
    }

    func setDeleteWhenAllWindowsClosed(
        _ isEnabled: Bool,
        for entry: SumiSiteDataEntry,
        url: URL?,
        profile: Profile?
    ) async {
        enforcementService.setDeleteWhenAllWindowsClosed(
            isEnabled,
            forHost: entry.domain,
            profile: profile
        )
        await load(url: url, profile: profile)
    }

    func policyState(for entry: SumiSiteDataEntry) -> SumiSiteDataPolicyState {
        policyStates[entry.domain] ?? SumiSiteDataPolicyState()
    }

    func summary(for entry: SumiSiteDataEntry) -> String {
        var parts: [String] = []
        if entry.cookieCount > 0 {
            parts.append("\(entry.cookieCount) cookie\(entry.cookieCount == 1 ? "" : "s")")
        }
        if entry.recordCount > 0 {
            parts.append("\(entry.recordCount) site data record\(entry.recordCount == 1 ? "" : "s")")
        }
        let state = policyState(for: entry)
        if state.blockStorage {
            parts.append("storage blocked")
        }
        if state.deleteWhenAllWindowsClosed {
            parts.append("deletes on close")
        }
        return parts.isEmpty ? "No stored data" : parts.joined(separator: " • ")
    }

    private func sort(
        _ entries: [SumiSiteDataEntry],
        currentHost: String?,
        rootDomain: String
    ) -> [SumiSiteDataEntry] {
        entries.sorted { lhs, rhs in
            let lhsPriority = priority(lhs.domain, currentHost: currentHost, rootDomain: rootDomain)
            let rhsPriority = priority(rhs.domain, currentHost: currentHost, rootDomain: rootDomain)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return lhs.domain.localizedStandardCompare(rhs.domain) == .orderedAscending
        }
    }

    private func priority(
        _ host: String,
        currentHost: String?,
        rootDomain: String
    ) -> Int {
        if let currentHost, host == currentHost { return 0 }
        if host == rootDomain { return 1 }
        return 2
    }

    private func rootDomain(for url: URL?) -> String? {
        guard let url, isHTTPURL(url) else { return nil }
        return HistoryDomainResolver.siteDomain(for: url)?
            .normalizedWebsiteDataDomain
    }

    private func normalizedHost(for url: URL?) -> String? {
        guard let url, isHTTPURL(url) else { return nil }
        let host = HistoryDomainResolver.normalizedDomain(for: url)
            .normalizedWebsiteDataDomain
        return host.isEmpty ? nil : host
    }

    private func isHTTPURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }
}
