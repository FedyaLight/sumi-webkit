import Combine
import Foundation

struct SumiSiteDataPolicyState: Codable, Equatable, Sendable {
    var blockStorage: Bool = false
    var deleteWhenAllWindowsClosed: Bool = false

    var isEmpty: Bool {
        !blockStorage && !deleteWhenAllWindowsClosed
    }
}

@MainActor
final class SumiSiteDataPolicyStore {
    static let shared = SumiSiteDataPolicyStore()

    private let userDefaults: UserDefaults
    private let storageKey: String
    private var policies: [String: [String: SumiSiteDataPolicyState]]
    private let changesSubject = PassthroughSubject<Void, Never>()

    var changesPublisher: AnyPublisher<Void, Never> {
        changesSubject.eraseToAnyPublisher()
    }

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "settings.siteDataPolicies"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.policies = Self.loadPolicies(
            key: storageKey,
            userDefaults: userDefaults
        )
    }

    func state(forHost host: String, profileId: UUID?) -> SumiSiteDataPolicyState {
        guard
            let profileKey = normalizedProfileKey(profileId),
            let hostKey = normalizedHost(host)
        else {
            return SumiSiteDataPolicyState()
        }

        return policies[profileKey]?[hostKey] ?? SumiSiteDataPolicyState()
    }

    func setBlockStorage(
        _ isEnabled: Bool,
        forHost host: String,
        profileId: UUID?
    ) {
        update(host: host, profileId: profileId) { state in
            state.blockStorage = isEnabled
        }
    }

    func setDeleteWhenAllWindowsClosed(
        _ isEnabled: Bool,
        forHost host: String,
        profileId: UUID?
    ) {
        update(host: host, profileId: profileId) { state in
            state.deleteWhenAllWindowsClosed = isEnabled
        }
    }

    func hostsDeletingWhenAllWindowsClosed(profileId: UUID?) -> Set<String> {
        guard let profileKey = normalizedProfileKey(profileId) else { return [] }
        return Set(
            (policies[profileKey] ?? [:])
                .filter { $0.value.deleteWhenAllWindowsClosed }
                .map(\.key)
        )
    }

    func hostsBlockingStorage(profileId: UUID?) -> Set<String> {
        guard let profileKey = normalizedProfileKey(profileId) else { return [] }
        return Set(
            (policies[profileKey] ?? [:])
                .filter { $0.value.blockStorage }
                .map(\.key)
        )
    }

    func hostsWithPolicies(profileId: UUID?) -> Set<String> {
        guard let profileKey = normalizedProfileKey(profileId) else { return [] }
        return Set((policies[profileKey] ?? [:]).keys)
    }

    private func update(
        host: String,
        profileId: UUID?,
        mutate: (inout SumiSiteDataPolicyState) -> Void
    ) {
        guard
            let profileKey = normalizedProfileKey(profileId),
            let hostKey = normalizedHost(host)
        else {
            return
        }

        var profilePolicies = policies[profileKey] ?? [:]
        var state = profilePolicies[hostKey] ?? SumiSiteDataPolicyState()
        mutate(&state)

        if state.isEmpty {
            profilePolicies.removeValue(forKey: hostKey)
        } else {
            profilePolicies[hostKey] = state
        }

        if profilePolicies.isEmpty {
            policies.removeValue(forKey: profileKey)
        } else {
            policies[profileKey] = profilePolicies
        }

        persist()
        changesSubject.send(())
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(policies) else { return }
        userDefaults.set(data, forKey: storageKey)
    }

    private func normalizedProfileKey(_ profileId: UUID?) -> String? {
        profileId?.uuidString.lowercased()
    }

    private func normalizedHost(_ host: String) -> String? {
        let normalized = host.normalizedWebsiteDataDomain
        return normalized.isEmpty ? nil : normalized
    }

    private static func loadPolicies(
        key: String,
        userDefaults: UserDefaults
    ) -> [String: [String: SumiSiteDataPolicyState]] {
        guard
            let data = userDefaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode(
                [String: [String: SumiSiteDataPolicyState]].self,
                from: data
            )
        else {
            return [:]
        }
        return decoded
    }
}
