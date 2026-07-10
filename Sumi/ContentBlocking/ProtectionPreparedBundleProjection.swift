import Foundation
import SumiDomain

struct ProtectionPreparedBundleProjection {
    func preparedProfileID(
        in manifest: AdblockCompiledGenerationManifest
    ) -> String? {
        SumiProtectionPreparedBundleIdentity.preparedBundleProfileId(in: manifest)
    }

    func installedProfileID(
        from manifest: AdblockCompiledGenerationManifest?
    ) -> String? {
        SumiProtectionPreparedBundleIdentity.installedBundleProfileId(from: manifest)
    }

    func groups(
        for level: SumiProtectionLevel,
        in manifest: AdblockCompiledGenerationManifest
    ) -> [ProtectionPreparedGroup] {
        guard let bundleProfileID = preparedProfileID(in: manifest) else {
            return []
        }
        let groups = manifest.allNativeShards.reduce(
            into: [SumiProtectionGroupKind: ProtectionPreparedGroup]()
        ) { result, shard in
            guard let group = protectionGroup(
                for: shard,
                bundleProfileID: bundleProfileID,
                level: level
            ) else { return }
            let existing = result[group]
            result[group] = ProtectionPreparedGroup(
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

    func trackingSourceAvailable(
        in manifest: AdblockCompiledGenerationManifest?
    ) -> Bool {
        guard let manifest else { return false }
        return groups(for: .protection, in: manifest).contains {
            $0.group == .trackingNetwork && $0.shardCount > 0
        }
    }

    func globallyAvailableGroups(
        in manifest: AdblockCompiledGenerationManifest?,
        trackingSourceAvailable: Bool
    ) -> [SumiProtectionGroupKind] {
        var groups = trackingSourceAvailable
            ? [SumiProtectionGroupKind.trackingNetwork]
            : []
        if let manifest, preparedProfileID(in: manifest) != nil {
            groups.append(
                contentsOf: self.groups(for: .adblock, in: manifest)
                    .map(\.group)
            )
        }
        return Array(Set(groups)).sorted { $0.rawValue < $1.rawValue }
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

struct ProtectionPreparedGroup: Equatable, Sendable {
    let group: SumiProtectionGroupKind
    let identifiers: [String]
    let shardCount: Int
    let ruleCount: Int
}
