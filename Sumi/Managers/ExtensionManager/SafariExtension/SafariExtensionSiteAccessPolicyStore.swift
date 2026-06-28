//
//  SafariExtensionSiteAccessPolicyStore.swift
//  Sumi
//
//  Persistence owner for profile-scoped Safari Web Extension site-access policy.
//

import Foundation

@available(macOS 15.5, *)
@MainActor
final class SafariExtensionSiteAccessPolicyStore {
    struct SnapshotResult {
        let policiesByExtensionId: [String: SafariExtensionSiteAccessPolicy]
        let didPersistChanges: Bool
    }

    struct PolicyResult {
        let policy: SafariExtensionSiteAccessPolicy
        let didPersistChanges: Bool
    }

    nonisolated static let legacyPermissionDecisionsStorageKey =
        "\(SumiAppIdentity.bundleIdentifier).extensions.permissionDecisions.v1"
    nonisolated static let siteAccessStorageKey =
        "\(SumiAppIdentity.bundleIdentifier).extensions.siteAccess.v1"

    private enum LegacyPermissionTargetKind: String, Codable {
        case permission
        case matchPattern
    }

    private enum LegacyStoredPermissionState: String, Codable {
        case allowed
        case denied
    }

    private struct LegacyStoredPermissionDecision: Codable, Equatable {
        var profileId: String
        var extensionId: String
        var targetKind: LegacyPermissionTargetKind
        var target: String
        var state: LegacyStoredPermissionState
        var expiresAt: Date?
        var updatedAt: Date

        func isExpired(now: Date = Date()) -> Bool {
            guard let expiresAt else { return false }
            return expiresAt <= now
        }
    }

    private let preferences: UserDefaults

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
    }

    func policy(
        extensionId: String,
        profileId: UUID
    ) -> PolicyResult {
        let result = snapshot(
            extensionIds: [extensionId],
            profileId: profileId
        )
        return PolicyResult(
            policy: result.policiesByExtensionId[extensionId]
                ?? SafariExtensionSiteAccessPolicy.defaultPolicy(
                    extensionId: extensionId,
                    profileId: profileId
                ),
            didPersistChanges: result.didPersistChanges
        )
    }

    func snapshot(
        extensionIds: [String],
        profileId: UUID
    ) -> SnapshotResult {
        guard extensionIds.isEmpty == false else {
            return SnapshotResult(
                policiesByExtensionId: [:],
                didPersistChanges: false
            )
        }

        var snapshot: [String: SafariExtensionSiteAccessPolicy] = [:]
        var policies = loadPolicies()
        var shouldSave = false

        for extensionId in extensionIds {
            let key = policyKey(extensionId: extensionId, profileId: profileId)
            if let stored = policies[key] {
                let normalized = stored.normalized()
                if normalized != stored {
                    policies[key] = normalized
                    shouldSave = true
                }
                snapshot[extensionId] = normalized
                continue
            }

            let policy = SafariExtensionSiteAccessPolicy.defaultPolicy(
                extensionId: extensionId,
                profileId: profileId,
                seededRules: migratedRules(
                    extensionId: extensionId,
                    profileId: profileId
                )
            )
            policies[key] = policy
            snapshot[extensionId] = policy
            shouldSave = true
        }

        return SnapshotResult(
            policiesByExtensionId: snapshot,
            didPersistChanges: shouldSave && savePolicies(policies)
        )
    }

    @discardableResult
    func updatePolicy(
        extensionId: String,
        profileId: UUID,
        update: (inout SafariExtensionSiteAccessPolicy) -> Void
    ) -> Bool {
        let key = policyKey(extensionId: extensionId, profileId: profileId)
        var policies = loadPolicies()
        var policy = policies[key] ?? SafariExtensionSiteAccessPolicy.defaultPolicy(
            extensionId: extensionId,
            profileId: profileId,
            seededRules: migratedRules(
                extensionId: extensionId,
                profileId: profileId
            )
        )
        update(&policy)
        policies[key] = policy.normalized()
        return savePolicies(policies)
    }

    private func migratedRules(
        extensionId: String,
        profileId: UUID
    ) -> [SafariExtensionSiteAccessRule] {
        let profileKey = profileId.uuidString.lowercased()
        return loadLegacyPermissionDecisions().values.compactMap { record in
            guard record.profileId == profileKey,
                  record.extensionId == extensionId,
                  record.targetKind == .matchPattern,
                  record.isExpired() == false
            else {
                return nil
            }
            return SafariExtensionSiteAccessRule(
                matchPattern: record.target,
                access: record.state == .allowed ? .allow : .deny,
                expiresAt: record.expiresAt,
                updatedAt: record.updatedAt
            )
        }
    }

    private func policyKey(
        extensionId: String,
        profileId: UUID
    ) -> String {
        "\(profileId.uuidString.lowercased())|\(extensionId)"
    }

    private func loadPolicies() -> [String: SafariExtensionSiteAccessPolicy] {
        guard let data = preferences.data(forKey: Self.siteAccessStorageKey),
              let decoded = try? JSONDecoder().decode(
                  [String: SafariExtensionSiteAccessPolicy].self,
                  from: data
              )
        else {
            return [:]
        }
        return decoded
    }

    private func savePolicies(
        _ policies: [String: SafariExtensionSiteAccessPolicy]
    ) -> Bool {
        guard let data = try? JSONEncoder().encode(policies) else { return false }
        preferences.set(data, forKey: Self.siteAccessStorageKey)
        return true
    }

    private func loadLegacyPermissionDecisions()
        -> [String: LegacyStoredPermissionDecision]
    {
        guard let data = preferences.data(
            forKey: Self.legacyPermissionDecisionsStorageKey
        ),
              let decoded = try? JSONDecoder().decode(
                  [String: LegacyStoredPermissionDecision].self,
                  from: data
              )
        else {
            return [:]
        }
        return decoded
    }
}
