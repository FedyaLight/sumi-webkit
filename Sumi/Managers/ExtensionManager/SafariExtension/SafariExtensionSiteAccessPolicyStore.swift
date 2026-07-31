//
//  SafariExtensionSiteAccessPolicyStore.swift
//  Sumi
//
//  Persistence owner for profile-scoped Safari Web Extension site-access policy.
//

import Foundation
import OSLog

@available(macOS 15.5, *)
@MainActor
final class SafariExtensionSiteAccessPolicyStore {
    private static let log = Logger.sumi(category: "Extensions")

    struct SnapshotResult {
        let policiesByExtensionId: [String: SafariExtensionSiteAccessPolicy]
        let didPersistChanges: Bool
    }

    struct PolicyResult {
        let policy: SafariExtensionSiteAccessPolicy
        let didPersistChanges: Bool
    }

    private static let documentKey = "extensions.site-access"
    private let database: SumiDatabase

    init(database: SumiDatabase) {
        self.database = database
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
                seededRules: []
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

    func seedSafariAppExtensionDefaultAccessIfNeeded(
        extensionId: String,
        profileId: UUID
    ) -> PolicyResult {
        let key = policyKey(extensionId: extensionId, profileId: profileId)
        var policies = loadPolicies()
        var shouldSave = false

        let policy: SafariExtensionSiteAccessPolicy
        if let stored = policies[key] {
            var normalized = stored.normalized()
            if shouldSeedSafariAppExtensionDefaultAccess(normalized) {
                normalized.defaultAccess = .allow
                normalized.updatedAt = Date()
                shouldSave = true
            } else if normalized != stored {
                shouldSave = true
            }
            policy = normalized
        } else {
            // Migrated per-site prompt decisions stay as rules; they override
            // the seeded default by specificity, so the Safari-appex product
            // default of Allow is safe to apply alongside them.
            policy = SafariExtensionSiteAccessPolicy.defaultPolicy(
                extensionId: extensionId,
                profileId: profileId,
                seededRules: [],
                defaultAccess: .allow
            )
            shouldSave = true
        }

        policies[key] = policy
        return PolicyResult(
            policy: policy,
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
            seededRules: []
        )
        update(&policy)
        policies[key] = policy.normalized()
        return savePolicies(policies)
    }

    @discardableResult
    func removePolicies(for extensionId: String) -> Bool {
        let policies = loadPolicies()
        let retained = policies.filter {
            $0.value.extensionId != extensionId
        }
        guard retained.count != policies.count else { return true }
        return savePolicies(retained)
    }

    private func shouldSeedSafariAppExtensionDefaultAccess(
        _ policy: SafariExtensionSiteAccessPolicy
    ) -> Bool {
        // An `.ask` default the user never explicitly chose in settings is
        // an auto-created placeholder (store auto-creation, permission-prompt
        // rule persistence, or the private-browsing toggle can all write the
        // policy record before seeding runs). Per-site rules are kept and
        // still override the seeded default by specificity, so explicit
        // denies keep winning.
        policy.defaultAccess == .ask
            && policy.defaultAccessConfiguredByUser == false
    }

    private func policyKey(
        extensionId: String,
        profileId: UUID
    ) -> String {
        "\(profileId.uuidString.lowercased())|\(extensionId)"
    }

    private func loadPolicies() -> [String: SafariExtensionSiteAccessPolicy] {
        do {
            return try database.read {
                try $0.documents.value(
                    [String: SafariExtensionSiteAccessPolicy].self,
                    forKey: Self.documentKey
                ) ?? [:]
            }
        } catch {
            Self.log.error("Failed to load Safari extension site-access policies: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

    private func savePolicies(
        _ policies: [String: SafariExtensionSiteAccessPolicy]
    ) -> Bool {
        do {
            try database.transaction {
                try $0.documents.save(policies, forKey: Self.documentKey)
            }
        } catch {
            Self.log.error("Failed to persist Safari extension site-access policies: \(error.localizedDescription, privacy: .public)")
            return false
        }
        return true
    }
}
