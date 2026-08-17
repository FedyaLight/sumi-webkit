import Foundation
import SumiDomain

struct AdblockGenerationProjection {
    func profileID(
        in manifest: AdblockCompiledGenerationManifest
    ) -> String? {
        manifest.bundleProfileId
    }

    func installedProfileID(
        from manifest: AdblockCompiledGenerationManifest?
    ) -> String? {
        manifest?.bundleProfileId
    }

    func groups(
        for level: SumiProtectionLevel,
        in manifest: AdblockCompiledGenerationManifest
    ) -> [AdblockGenerationGroup] {
        guard let bundleProfileID = profileID(in: manifest) else {
            return []
        }
        let groups = manifest.networkShards.reduce(
            into: [SumiProtectionGroupKind: AdblockGenerationGroup]()
        ) { result, shard in
            guard let group = protectionGroup(
                for: shard,
                bundleProfileID: bundleProfileID,
                level: level
            ) else { return }
            let existing = result[group]
            result[group] = AdblockGenerationGroup(
                group: group,
                identifiers: (existing?.identifiers ?? [])
                    + [shard.webKitIdentifier],
                shardCount: (existing?.shardCount ?? 0) + 1,
                ruleCount: (existing?.ruleCount ?? 0)
                    + shard.approximateRuleCount
            )
        }
        return groups.values.sorted { $0.group.rawValue < $1.group.rawValue }
    }

    func metadataOnlyRuleDefinitions(
        matching identifiers: [String],
        in manifest: AdblockCompiledGenerationManifest?
    ) -> [SumiContentRuleListDefinition] {
        guard let manifest else { return [] }
        let expectedIdentifiers = Set(identifiers)
        return manifest.networkShards
            .filter { expectedIdentifiers.contains($0.webKitIdentifier) }
            .sorted { lhs, rhs in
                lhs.kind == rhs.kind
                    ? lhs.id < rhs.id
                    : lhs.kind.rawValue < rhs.kind.rawValue
            }
            .map { shard in
                SumiContentRuleListDefinition(
                    name: shard.webKitIdentifier,
                    encodedContentRuleList: "",
                    storeIdentifierOverride: shard.webKitIdentifier,
                    contentHashOverride: shard.contentHash
                )
            }
    }

    func globallyAvailableGroups(
        in manifest: AdblockCompiledGenerationManifest?
    ) -> [SumiProtectionGroupKind] {
        guard let manifest, profileID(in: manifest) != nil else {
            return []
        }
        return Array(Set(groups(for: .adblock, in: manifest).map(\.group)))
            .sorted { $0.rawValue < $1.rawValue }
    }

    private func protectionGroup(
        for shard: NativeContentBlockingShardDescriptor,
        bundleProfileID: String,
        level: SumiProtectionLevel
    ) -> SumiProtectionGroupKind? {
        guard shard.kind == .network else { return nil }
        if let group = shard.protectionGroup {
            return level.requestedGroups.contains(group) ? group : nil
        }
        switch (bundleProfileID, level) {
        case (SumiProtectionBundleProfile.adblock, .adblock):
            return .adblockAdsPrivacyNetwork
        default:
            return nil
        }
    }
}

struct AdblockGenerationGroup: Equatable, Sendable {
    let group: SumiProtectionGroupKind
    let identifiers: [String]
    let shardCount: Int
    let ruleCount: Int
}
