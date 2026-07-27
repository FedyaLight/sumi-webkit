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

enum SumiSiteDataPolicyStoreError: Error, Equatable {
    case unreadablePayload
    case persistenceVerificationFailed
}

@MainActor
final class SumiSiteDataPolicyStore {
    private static let log = Logger.sumi(category: "SiteDataPolicyStore")

    private static let documentKey = "site-data.policies"
    private let database: SumiDatabase?
    private var policies: [String: [String: SumiSiteDataPolicyState]]
    private let changesSubject = PassthroughSubject<Void, Never>()
    private(set) var diagnostics = SumiSiteDataPolicyStoreDiagnostics()

    var changesPublisher: AnyPublisher<Void, Never> {
        changesSubject.eraseToAnyPublisher()
    }

    init(
        database: SumiDatabase? = nil
    ) {
        self.database = database
        let loadResult = Self.loadPolicies(database: database)
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

    func deletePolicies(profileId: UUID) throws {
        guard case .failedDecode = diagnostics.loadOutcome else {
            let profileKey = profileId.uuidString.lowercased()
            guard policies[profileKey] != nil else { return }

            var candidate = policies
            candidate.removeValue(forKey: profileKey)
            if let database {
                try database.transaction {
                    try $0.documents.save(
                        candidate,
                        forKey: Self.documentKey
                    )
                }
            }
            policies = candidate
            diagnostics.lastPersistFailure = nil
            changesSubject.send(())
            return
        }
        throw SumiSiteDataPolicyStoreError.unreadablePayload
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

        var candidate = policies
        var profilePolicies = candidate[profileKey] ?? [:]
        var state = profilePolicies[hostKey] ?? SumiSiteDataPolicyState()
        mutate(&state)

        if state.isEmpty {
            profilePolicies.removeValue(forKey: hostKey)
        } else {
            profilePolicies[hostKey] = state
        }

        if profilePolicies.isEmpty {
            candidate.removeValue(forKey: profileKey)
        } else {
            candidate[profileKey] = profilePolicies
        }

        guard candidate != policies, persist(candidate) else { return }
        policies = candidate
        changesSubject.send(())
    }

    private func persist(
        _ candidate: [String: [String: SumiSiteDataPolicyState]]
    ) -> Bool {
        do {
            try database?.transaction {
                try $0.documents.save(
                    candidate,
                    forKey: Self.documentKey
                )
            }
            diagnostics.lastPersistFailure = nil
            return true
        } catch {
            diagnostics.lastPersistFailure = error.localizedDescription
            Self.log.error(
                "Failed to persist site data policies: \(error.localizedDescription, privacy: .public)"
            )
            return false
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
        database: SumiDatabase?
    ) -> (
        policies: [String: [String: SumiSiteDataPolicyState]],
        outcome: SumiSiteDataPolicyStoreDiagnostics.LoadOutcome
    ) {
        guard let database else {
            return ([:], .missing)
        }
        do {
            let decoded = try database.read {
                try $0.documents.value(
                    [String: [String: SumiSiteDataPolicyState]].self,
                    forKey: Self.documentKey
                )
            }
            guard let decoded else { return ([:], .missing) }
            return (decoded, .loaded)
        } catch {
            log.error(
                "Failed to decode site data policies: \(error.localizedDescription, privacy: .public)"
            )
            return ([:], .failedDecode(error.localizedDescription))
        }
    }
}
