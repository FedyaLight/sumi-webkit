import Foundation
import SumiDomain

@MainActor
final class ProtectionAttachmentPlanner {
    private let ruleProvider: any ProtectionAttachmentRuleProviding
    private let bundleProjection: AdblockGenerationProjection

    init(
        ruleProvider: any ProtectionAttachmentRuleProviding,
        bundleProjection: AdblockGenerationProjection
    ) {
        self.ruleProvider = ruleProvider
        self.bundleProjection = bundleProjection
    }

    func globalPlan(
        for level: SumiProtectionLevel,
        manifest: AdblockCompiledGenerationManifest?,
        cachedPlan: SumiProtectionGlobalAttachmentPlan?,
        loadRuleDefinitions: Bool
    ) -> SumiProtectionGlobalAttachmentPlan {
        if !loadRuleDefinitions,
           let cachedPlan,
           matches(cachedPlan, level: level, manifest: manifest) {
            return metadataOnlyPlan(cachedPlan)
        }

        let inputs = collectInputs(
            for: level,
            manifest: manifest,
            loadRuleDefinitions: loadRuleDefinitions
        )
        let resolvedRules = resolveRules(
            from: inputs,
            loadRuleDefinitions: loadRuleDefinitions
        )

        return SumiProtectionGlobalAttachmentPlan(
            level: level,
            activeGroups: resolvedRules.activeGroups,
            expectedRuleListIdentifiers: resolvedRules.identifiers,
            ruleDefinitions: resolvedRules.definitions,
            bundleProfileId: bundleProjection.installedProfileID(from: manifest),
            activeGenerationId: manifest?.activeGenerationId
        )
    }

    func emptyPlan(
        for level: SumiProtectionLevel,
        manifest: AdblockCompiledGenerationManifest?
    ) -> SumiProtectionGlobalAttachmentPlan {
        SumiProtectionGlobalAttachmentPlan(
            level: level,
            activeGroups: [],
            expectedRuleListIdentifiers: [],
            ruleDefinitions: [],
            bundleProfileId: bundleProjection.installedProfileID(from: manifest),
            activeGenerationId: manifest?.activeGenerationId
        )
    }

    func metadataOnlyPlan(
        _ plan: SumiProtectionGlobalAttachmentPlan
    ) -> SumiProtectionGlobalAttachmentPlan {
        SumiProtectionGlobalAttachmentPlan(
            level: plan.level,
            activeGroups: plan.activeGroups,
            expectedRuleListIdentifiers: plan.expectedRuleListIdentifiers,
            ruleDefinitions: [],
            bundleProfileId: plan.bundleProfileId,
            activeGenerationId: plan.activeGenerationId
        )
    }

    func matches(
        _ plan: SumiProtectionGlobalAttachmentPlan,
        level: SumiProtectionLevel,
        manifest: AdblockCompiledGenerationManifest?
    ) -> Bool {
        plan.level == level
            && plan.activeGenerationId == manifest?.activeGenerationId
            && plan.bundleProfileId
                == bundleProjection.installedProfileID(from: manifest)
    }

    private func collectInputs(
        for level: SumiProtectionLevel,
        manifest: AdblockCompiledGenerationManifest?,
        loadRuleDefinitions: Bool
    ) -> ProtectionAttachmentPlanInputs {
        var inputs = ProtectionAttachmentPlanInputs()
        guard let requiredProfileID = level.preferredBundleProfileId else {
            return inputs
        }
        let activeProfileID = manifest.flatMap {
            bundleProjection.profileID(in: $0)
        }
        if activeProfileID == requiredProfileID {
            if loadRuleDefinitions {
                do {
                    let definitions = try ruleProvider.contentRuleListDefinitions(
                        for: Set(level.requestedGroups)
                    )
                    for entry in groupedDefinitions(
                        definitions,
                        level: level,
                        manifest: manifest
                    ) where !entry.definitions.isEmpty {
                        inputs.append(entry)
                    }
                } catch { return inputs }
            } else if let manifest {
                for group in bundleProjection.groups(for: level, in: manifest)
                    where group.shardCount > 0 {
                    inputs.append(group)
                }
            }
        }
        return inputs
    }

    private func resolveRules(
        from inputs: ProtectionAttachmentPlanInputs,
        loadRuleDefinitions: Bool
    ) -> ProtectionAttachmentResolvedRules {
        guard loadRuleDefinitions else {
            return ProtectionAttachmentResolvedRules(
                activeGroups: inputs.activeGroups.uniqueSorted(),
                identifiers: Array(Set(inputs.expectedIdentifiers)).sorted(),
                definitions: []
            )
        }

        return ProtectionAttachmentResolvedRules(
            activeGroups: inputs.activeGroups.uniqueSorted(),
            identifiers: inputs.definitions
                .map(\.webKitStoreIdentifier)
                .sorted(),
            definitions: inputs.definitions
        )
    }

    private func groupedDefinitions(
        _ definitions: [SumiContentRuleListDefinition],
        level: SumiProtectionLevel,
        manifest: AdblockCompiledGenerationManifest?
    ) -> [AdblockGenerationDefinitionGroup] {
        guard let manifest,
              bundleProjection.profileID(in: manifest) != nil else {
            return []
        }
        let definitionsByIdentifier = definitions.reduce(
            into: [String: SumiContentRuleListDefinition]()
        ) { result, definition in
            result[definition.webKitStoreIdentifier] = definition
        }
        return bundleProjection.groups(for: level, in: manifest).compactMap { cachedGroup in
            let definitions = cachedGroup.identifiers.compactMap {
                definitionsByIdentifier[$0]
            }
            guard !definitions.isEmpty else { return nil }
            return AdblockGenerationDefinitionGroup(
                group: cachedGroup.group,
                definitions: definitions
            )
        }
    }
}

private struct AdblockGenerationDefinitionGroup {
    let group: SumiProtectionGroupKind
    let definitions: [SumiContentRuleListDefinition]
}

private struct ProtectionAttachmentPlanInputs {
    var activeGroups = [SumiProtectionGroupKind]()
    var expectedIdentifiers = [String]()
    var definitions = [SumiContentRuleListDefinition]()

    mutating func append(_ entry: AdblockGenerationDefinitionGroup) {
        activeGroups.append(entry.group)
        definitions.append(contentsOf: entry.definitions)
    }

    mutating func append(_ group: AdblockGenerationGroup) {
        activeGroups.append(group.group)
        expectedIdentifiers.append(contentsOf: group.identifiers)
    }
}

private struct ProtectionAttachmentResolvedRules {
    let activeGroups: [SumiProtectionGroupKind]
    let identifiers: [String]
    let definitions: [SumiContentRuleListDefinition]
}

private extension Array where Element == SumiProtectionGroupKind {
    func uniqueSorted() -> [SumiProtectionGroupKind] {
        Array(Set(self)).sorted { $0.rawValue < $1.rawValue }
    }
}
