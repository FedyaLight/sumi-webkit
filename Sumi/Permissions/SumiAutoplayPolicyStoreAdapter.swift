import Foundation
import SwiftData

@MainActor
final class SumiAutoplayPolicyStoreAdapter {
    static let shared = SumiAutoplayPolicyStoreAdapter(
        modelContainer: SumiStartupPersistence.shared.container
    )

    private let modelContainer: ModelContainer
    private let persistentStore: any SumiPermissionStore
    private var ephemeralPoliciesByIdentity: [String: SumiAutoplayPolicy] = [:]

    init(
        modelContainer: ModelContainer,
        persistentStore: (any SumiPermissionStore)? = nil
    ) {
        self.modelContainer = modelContainer
        self.persistentStore = persistentStore
            ?? SwiftDataPermissionStore(container: modelContainer)
    }

    func effectivePolicy(for url: URL?, profile: Profile?) -> SumiAutoplayPolicy {
        explicitPolicy(for: url, profile: profile) ?? .default
    }

    func explicitPolicy(for url: URL?, profile: Profile?) -> SumiAutoplayPolicy? {
        guard let key = key(for: url, profile: profile) else { return nil }
        return explicitPolicy(for: key)
    }

    func explicitPolicy(for key: SumiPermissionKey) -> SumiAutoplayPolicy? {
        guard key.permissionType == .autoplay else { return nil }
        if key.isEphemeralProfile {
            return ephemeralPoliciesByIdentity[key.persistentIdentity]
        }
        guard let record = persistentRecord(for: key) else { return nil }
        return SumiAutoplayDecisionMapper.policy(from: record.decision)
    }

    func hasExplicitPolicy(for url: URL?, profile: Profile?) -> Bool {
        guard let key = key(for: url, profile: profile) else { return false }
        if key.isEphemeralProfile {
            return ephemeralPoliciesByIdentity[key.persistentIdentity] != nil
        }
        return persistentRecord(for: key) != nil
    }

    func setPolicy(
        _ policy: SumiAutoplayPolicy,
        for url: URL?,
        profile: Profile?,
        source: SumiPermissionDecisionSource = .user,
        now: Date = Date()
    ) async throws {
        guard let key = key(for: url, profile: profile) else { return }
        try await setPolicy(policy, for: key, source: source, now: now)
    }

    func setPolicy(
        _ policy: SumiAutoplayPolicy,
        for key: SumiPermissionKey,
        source: SumiPermissionDecisionSource = .user,
        now: Date = Date()
    ) async throws {
        guard key.permissionType == .autoplay else {
            throw SumiPermissionSiteDecisionError.unsupportedPermission(key.permissionType.identity)
        }

        guard policy != .default else {
            try await resetPolicy(for: key)
            return
        }

        if key.isEphemeralProfile {
            ephemeralPoliciesByIdentity[key.persistentIdentity] = policy
            return
        }

        guard let decision = SumiAutoplayDecisionMapper.decision(
            for: policy,
            source: source,
            now: now
        ) else { return }

        try await persistentStore.setDecision(for: key, decision: decision)
    }

    func resetPolicy(for url: URL?, profile: Profile?) async throws {
        guard let key = key(for: url, profile: profile) else { return }
        try await resetPolicy(for: key)
    }

    func resetPolicy(for key: SumiPermissionKey) async throws {
        guard key.permissionType == .autoplay else {
            throw SumiPermissionSiteDecisionError.unsupportedPermission(key.permissionType.identity)
        }
        if key.isEphemeralProfile {
            ephemeralPoliciesByIdentity.removeValue(forKey: key.persistentIdentity)
            return
        }

        try await persistentStore.resetDecision(for: key)
    }

    func siteDecisionRecords(
        profilePartitionId: String,
        isEphemeralProfile: Bool
    ) async throws -> [SumiPermissionStoreRecord] {
        let normalizedProfileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        if isEphemeralProfile {
            return ephemeralPoliciesByIdentity.compactMap { identity, policy in
                guard identity.hasPrefix("\(normalizedProfileId)|"),
                      let record = ephemeralRecord(identity: identity, policy: policy)
                else { return nil }
                return record
            }
        }

        return try await persistentStore
            .listDecisions(profilePartitionId: normalizedProfileId)
            .filter { $0.key.permissionType == .autoplay }
    }

    func key(for url: URL?, profile: Profile?) -> SumiPermissionKey? {
        guard let profile else { return nil }
        let origin = SumiPermissionOrigin(url: url)
        guard origin.isWebOrigin else { return nil }

        return SumiPermissionKey(
            requestingOrigin: origin,
            topOrigin: origin,
            permissionType: .autoplay,
            profilePartitionId: profile.id.uuidString,
            isEphemeralProfile: profile.isEphemeral
        )
    }

    private func persistentRecord(for key: SumiPermissionKey) -> SumiPermissionStoreRecord? {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false

        let identity = key.persistentIdentity
        let predicate = #Predicate<PermissionDecisionEntity> { entity in
            entity.persistentIdentity == identity
        }
        var descriptor = FetchDescriptor<PermissionDecisionEntity>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first?.record()
    }

    private func ephemeralRecord(
        identity: String,
        policy: SumiAutoplayPolicy
    ) -> SumiPermissionStoreRecord? {
        let parts = identity.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4,
              let decision = SumiAutoplayDecisionMapper.decision(
                for: policy,
                source: .user,
                now: Date()
              )
        else { return nil }

        let key = SumiPermissionKey(
            requestingOrigin: SumiPermissionOrigin(identity: parts[1]),
            topOrigin: SumiPermissionOrigin(identity: parts[2]),
            permissionType: .autoplay,
            profilePartitionId: parts[0],
            isEphemeralProfile: true
        )
        return SumiPermissionStoreRecord(key: key, decision: decision)
    }
}
