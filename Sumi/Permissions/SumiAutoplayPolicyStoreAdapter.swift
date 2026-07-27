import Foundation
import SumiDomain

/// Sync-readable autoplay policy façade over the canonical `SumiPermissionStore`.
///
/// Persistent reads use an in-memory cache seeded at composition / after writes.
/// The adapter never opens its own database transaction — that would bypass
/// the store actor and duplicate its query.
@MainActor
final class SumiAutoplayPolicyStoreAdapter {
    private let persistentStore: any SumiPermissionStore
    let profileAdmission: SumiPermissionProfileAdmission
    /// Persistent + ephemeral policies keyed by `SumiPermissionKey.persistentIdentity`.
    private var policiesByIdentity: [String: SumiAutoplayPolicy] = [:]
    private var retiredProfileIDs: Set<String> = []

    /// Canonical store shared with `SumiPermissionCoordinator` (same instance).
    var permissionStore: any SumiPermissionStore { persistentStore }

    init(
        persistentStore: any SumiPermissionStore,
        profileAdmission: SumiPermissionProfileAdmission = SumiPermissionProfileAdmission()
    ) {
        self.persistentStore = persistentStore
        self.profileAdmission = profileAdmission
    }

    /// Seeds the sync cache from canonical store records (composition-root / test harness).
    func seedCache(with records: [SumiPermissionStoreRecord]) {
        for record in records where record.key.permissionType == .autoplay {
            policiesByIdentity[record.key.persistentIdentity] =
                SumiAutoplayDecisionMapper.policy(from: record.decision)
        }
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
        guard retiredProfileIDs.contains(key.profilePartitionId) == false else {
            return nil
        }
        return policiesByIdentity[key.persistentIdentity]
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
        guard let lease = await profileAdmission.admit(
            profilePartitionId: key.profilePartitionId
        ) else {
            throw SumiPermissionSiteDecisionError.unavailable
        }
        do {
            try await setPolicyAdmitted(
                policy,
                for: key,
                source: source,
                now: now
            )
            await profileAdmission.release(lease)
        } catch {
            await profileAdmission.release(lease)
            throw error
        }
    }

    private func setPolicyAdmitted(
        _ policy: SumiAutoplayPolicy,
        for key: SumiPermissionKey,
        source: SumiPermissionDecisionSource,
        now: Date
    ) async throws {
        guard key.permissionType == .autoplay else {
            throw SumiPermissionSiteDecisionError.unsupportedPermission(key.permissionType.identity)
        }

        guard policy != .default else {
            try await resetPolicyAdmitted(for: key)
            return
        }

        if key.isEphemeralProfile {
            policiesByIdentity[key.persistentIdentity] = policy
            return
        }

        guard let decision = SumiAutoplayDecisionMapper.decision(
            for: policy,
            source: source,
            now: now
        ) else { return }

        try await persistentStore.setDecision(for: key, decision: decision)
        if await profileAdmission.isRetired(key.profilePartitionId) == false {
            policiesByIdentity[key.persistentIdentity] = policy
        }
    }

    func resetPolicy(for url: URL?, profile: Profile?) async throws {
        guard let key = key(for: url, profile: profile) else { return }
        try await resetPolicy(for: key)
    }

    func resetPolicy(for key: SumiPermissionKey) async throws {
        guard let lease = await profileAdmission.admit(
            profilePartitionId: key.profilePartitionId
        ) else {
            throw SumiPermissionSiteDecisionError.unavailable
        }
        do {
            try await resetPolicyAdmitted(for: key)
            await profileAdmission.release(lease)
        } catch {
            await profileAdmission.release(lease)
            throw error
        }
    }

    private func resetPolicyAdmitted(for key: SumiPermissionKey) async throws {
        guard key.permissionType == .autoplay else {
            throw SumiPermissionSiteDecisionError.unsupportedPermission(key.permissionType.identity)
        }
        policiesByIdentity.removeValue(forKey: key.persistentIdentity)
        if key.isEphemeralProfile {
            return
        }

        try await persistentStore.resetDecision(for: key)
    }

    func siteDecisionRecords(
        profilePartitionId: String,
        isEphemeralProfile: Bool
    ) async throws -> [SumiPermissionStoreRecord] {
        let normalizedProfileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        guard await profileAdmission.isRetired(normalizedProfileId) == false else {
            throw SumiPermissionSiteDecisionError.unavailable
        }
        if isEphemeralProfile {
            return policiesByIdentity.compactMap { identity, policy in
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

    func sealProfile(_ profilePartitionId: String) async -> String {
        let profileID = await profileAdmission.seal(
            profilePartitionId: profilePartitionId
        )
        retiredProfileIDs.insert(profileID)
        policiesByIdentity = policiesByIdentity.filter {
            $0.key.hasPrefix("\(profileID)|") == false
        }
        return profileID
    }

    func waitForProfileDrain(_ profilePartitionId: String) async {
        await profileAdmission.waitForDrain(
            profilePartitionId: profilePartitionId
        )
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

/// Composition-root helper: one-shot database read to seed the autoplay cache.
@MainActor
enum SumiAutoplayPolicyCacheBootstrap {
    static func loadAutoplayRecords(from database: SumiDatabase) -> [SumiPermissionStoreRecord] {
        do {
            return try database.read {
                try $0.permissions.all(
                    permissionType: SumiPermissionType.autoplay.identity
                )
            }.compactMap { row in
                do {
                    return try row.record()
                } catch {
                    return nil
                }
            }
        } catch {
            RuntimeDiagnostics.emit(
                "[Permissions] Failed to bootstrap autoplay cache: \(error.localizedDescription)"
            )
            return []
        }
    }
}
