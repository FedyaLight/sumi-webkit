import Combine
import Foundation
import OSLog

struct SumiSiteDataPolicyState: Codable, Equatable, Sendable {
    var blockStorage: Bool = false
    var deleteWhenAllWindowsClosed: Bool = false

    var isEmpty: Bool {
        !blockStorage && !deleteWhenAllWindowsClosed
    }
}

struct SumiSiteDataPolicyStoreDiagnostics: Equatable, Sendable {
    enum LoadOutcome: Equatable, Sendable {
        case notLoaded
        case missing
        case loaded
        case failedDecode(String)
    }

    var loadOutcome: LoadOutcome = .notLoaded
    var lastPersistFailure: String?
}

@MainActor
final class SumiSiteDataPolicyStore {
    static let shared = SumiSiteDataPolicyStore()
    private static let log = Logger.sumi(category: "SiteDataPolicyStore")

    private let userDefaults: UserDefaults
    private let storageKey: String
    private var policies: [String: [String: SumiSiteDataPolicyState]]
    private let changesSubject = PassthroughSubject<Void, Never>()
    private(set) var diagnostics = SumiSiteDataPolicyStoreDiagnostics()

    var changesPublisher: AnyPublisher<Void, Never> {
        changesSubject.eraseToAnyPublisher()
    }

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "settings.siteDataPolicies"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        let loadResult = Self.loadPolicies(
            key: storageKey,
            userDefaults: userDefaults
        )
        self.policies = loadResult.policies
        self.diagnostics.loadOutcome = loadResult.outcome
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
        do {
            let data = try JSONEncoder().encode(policies)
            userDefaults.set(data, forKey: storageKey)
            diagnostics.lastPersistFailure = nil
        } catch {
            diagnostics.lastPersistFailure = error.localizedDescription
            Self.log.error(
                "Failed to persist site data policies: \(error.localizedDescription, privacy: .public)"
            )
        }
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
    ) -> (
        policies: [String: [String: SumiSiteDataPolicyState]],
        outcome: SumiSiteDataPolicyStoreDiagnostics.LoadOutcome
    ) {
        guard let data = userDefaults.data(forKey: key) else {
            return ([:], .missing)
        }

        do {
            let decoded = try JSONDecoder().decode(
                [String: [String: SumiSiteDataPolicyState]].self,
                from: data
            )
            return (decoded, .loaded)
        } catch {
            preserveUnreadablePayload(data, in: userDefaults, storageKey: key)
            log.error(
                "Failed to decode site data policies: \(error.localizedDescription, privacy: .public)"
            )
            return ([:], .failedDecode(error.localizedDescription))
        }
    }

    private static func preserveUnreadablePayload(
        _ data: Data,
        in userDefaults: UserDefaults,
        storageKey: String
    ) {
        let backupKey = "\(storageKey).unreadable"
        guard userDefaults.data(forKey: backupKey) == nil else { return }
        userDefaults.set(data, forKey: backupKey)
    }
}
