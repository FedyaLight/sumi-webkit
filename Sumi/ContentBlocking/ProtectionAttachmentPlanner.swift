import Foundation
import SumiDomain

@MainActor
final class ProtectionAttachmentPlanner {
    private let ruleProvider: any ProtectionAttachmentRuleProviding
    private let bundleProjection: ProtectionPreparedBundleProjection

    init(
        ruleProvider: any ProtectionAttachmentRuleProviding,
        bundleProjection: ProtectionPreparedBundleProjection
    ) {
        self.ruleProvider = ruleProvider
        self.bundleProjection = bundleProjection
    }

    func globalPlan(
        for level: SumiProtectionLevel,
        manifest: AdblockCompiledGenerationManifest?,
        cachedPlan: SumiProtectionGlobalAttachmentPlan?,
        includeExpensiveDiagnostics: Bool,
        loadRuleDefinitions: Bool
    ) -> SumiProtectionGlobalAttachmentPlan {
        if !loadRuleDefinitions,
           !includeExpensiveDiagnostics,
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
            includeExpensiveDiagnostics: includeExpensiveDiagnostics,
            loadRuleDefinitions: loadRuleDefinitions
        )

        return SumiProtectionGlobalAttachmentPlan(
            level: level,
            activeGroups: resolvedRules.activeGroups,
            inactiveGroups: level.requestedGroups.filter {
                !resolvedRules.activeGroups.contains($0)
            },
            ruleCountsByGroup: inputs.ruleCountsByGroup,
            shardCountsByGroup: inputs.shardCountsByGroup,
            expectedRuleListIdentifiers: resolvedRules.identifiers,
            dedupeSummary: resolvedRules.dedupeSummary,
            overlapSummary: resolvedRules.overlapSummary,
            planningErrors: inputs.planningErrors,
            ruleDefinitions: resolvedRules.definitions,
            bundleSource: manifest?.generationSource,
            nativeRuleBundleId: manifest?.nativeRuleBundleId,
            bundleProfileId: bundleProjection.installedProfileID(from: manifest),
            requiredBundleProfileId: level.preferredBundleProfileId,
            activeGenerationId: manifest?.activeGenerationId,
            previousGenerationId: manifest?.previousGenerationId,
            previousGenerationRetained: manifest?.previousGenerationId != nil
        )
    }

    func emptyPlan(
        for level: SumiProtectionLevel,
        manifest: AdblockCompiledGenerationManifest?
    ) -> SumiProtectionGlobalAttachmentPlan {
        SumiProtectionGlobalAttachmentPlan(
            level: level,
            activeGroups: [],
            inactiveGroups: [],
            ruleCountsByGroup: [:],
            shardCountsByGroup: [:],
            expectedRuleListIdentifiers: [],
            dedupeSummary: .empty,
            overlapSummary: .deferred,
            planningErrors: [],
            ruleDefinitions: [],
            bundleSource: manifest?.generationSource,
            nativeRuleBundleId: manifest?.nativeRuleBundleId,
            bundleProfileId: bundleProjection.installedProfileID(from: manifest),
            requiredBundleProfileId: level.preferredBundleProfileId,
            activeGenerationId: manifest?.activeGenerationId,
            previousGenerationId: manifest?.previousGenerationId,
            previousGenerationRetained: manifest?.previousGenerationId != nil
        )
    }

    func metadataOnlyPlan(
        _ plan: SumiProtectionGlobalAttachmentPlan
    ) -> SumiProtectionGlobalAttachmentPlan {
        SumiProtectionGlobalAttachmentPlan(
            level: plan.level,
            activeGroups: plan.activeGroups,
            inactiveGroups: plan.inactiveGroups,
            ruleCountsByGroup: plan.ruleCountsByGroup,
            shardCountsByGroup: plan.shardCountsByGroup,
            expectedRuleListIdentifiers: plan.expectedRuleListIdentifiers,
            dedupeSummary: plan.dedupeSummary,
            overlapSummary: .deferred,
            planningErrors: plan.planningErrors,
            ruleDefinitions: [],
            bundleSource: plan.bundleSource,
            nativeRuleBundleId: plan.nativeRuleBundleId,
            bundleProfileId: plan.bundleProfileId,
            requiredBundleProfileId: plan.requiredBundleProfileId,
            activeGenerationId: plan.activeGenerationId,
            previousGenerationId: plan.previousGenerationId,
            previousGenerationRetained: plan.previousGenerationRetained
        )
    }

    func matches(
        _ plan: SumiProtectionGlobalAttachmentPlan,
        level: SumiProtectionLevel,
        manifest: AdblockCompiledGenerationManifest?
    ) -> Bool {
        plan.level == level
            && plan.requiredBundleProfileId == level.preferredBundleProfileId
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
        let preparedProfileID = manifest.flatMap {
            bundleProjection.preparedProfileID(in: $0)
        }
        if preparedProfileID == requiredProfileID {
            if loadRuleDefinitions {
                do {
                    let definitions = try ruleProvider.contentRuleListDefinitions(
                        for: Set(level.requestedGroups)
                    )
                    for entry in groupPreparedDefinitions(
                        definitions,
                        level: level,
                        manifest: manifest
                    ) where !entry.definitions.isEmpty {
                        inputs.append(entry)
                    }
                } catch {
                    inputs.planningErrors.append(
                        "Prepared protection bundle rules unavailable: \(error.localizedDescription)"
                    )
                }
            } else if let manifest {
                for group in bundleProjection.groups(for: level, in: manifest)
                    where group.shardCount > 0 {
                    inputs.append(group)
                }
            }
        } else {
            inputs.planningErrors.append(
                "Required prepared bundle profile \(requiredProfileID) is not active."
            )
        }

        let availableGroups = manifest.map {
            Set(bundleProjection.groups(for: level, in: $0).map(\.group))
        } ?? []
        for group in level.requestedGroups where !availableGroups.contains(group) {
            inputs.planningErrors.append(
                "Prepared \(group.rawValue) group is unavailable in active bundle."
            )
        }
        return inputs
    }

    private func resolveRules(
        from inputs: ProtectionAttachmentPlanInputs,
        includeExpensiveDiagnostics: Bool,
        loadRuleDefinitions: Bool
    ) -> ProtectionAttachmentResolvedRules {
        guard loadRuleDefinitions else {
            return ProtectionAttachmentResolvedRules(
                activeGroups: inputs.activeGroups.uniqueSorted(),
                identifiers: Array(Set(inputs.expectedIdentifiers)).sorted(),
                dedupeSummary: .empty,
                overlapSummary: .deferred,
                definitions: []
            )
        }

        let deduped = ProtectionRuleDeduplication.deduplicate(
            inputs.plannedDefinitions
        )
        let groupsAfterDedupe = Set(deduped.definitions.map(\.group))
        return ProtectionAttachmentResolvedRules(
            activeGroups: inputs.activeGroups
                .filter(groupsAfterDedupe.contains)
                .uniqueSorted(),
            identifiers: deduped.definitions
                .map(\.definition.webKitStoreIdentifier)
                .sorted(),
            dedupeSummary: deduped.summary,
            overlapSummary: ProtectionOverlapDiagnostics.summarize(
                inputs.plannedDefinitions,
                includeExpensiveDiagnostics: includeExpensiveDiagnostics
            ),
            definitions: deduped.definitions.map(\.definition)
        )
    }

    private func groupPreparedDefinitions(
        _ definitions: [SumiContentRuleListDefinition],
        level: SumiProtectionLevel,
        manifest: AdblockCompiledGenerationManifest?
    ) -> [ProtectionPreparedDefinitionGroup] {
        guard let manifest,
              bundleProjection.preparedProfileID(in: manifest) != nil else {
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
            return ProtectionPreparedDefinitionGroup(
                group: cachedGroup.group,
                definitions: definitions,
                ruleCount: cachedGroup.ruleCount
            )
        }
    }
}

private struct ProtectionPreparedDefinitionGroup {
    let group: SumiProtectionGroupKind
    let definitions: [SumiContentRuleListDefinition]
    let ruleCount: Int
}

private struct ProtectionAttachmentPlanInputs {
    var activeGroups = [SumiProtectionGroupKind]()
    var ruleCountsByGroup = [SumiProtectionGroupKind: Int]()
    var shardCountsByGroup = [SumiProtectionGroupKind: Int]()
    var expectedIdentifiers = [String]()
    var plannedDefinitions = [ProtectionPlannedRuleDefinition]()
    var planningErrors = [String]()

    mutating func append(_ entry: ProtectionPreparedDefinitionGroup) {
        activeGroups.append(entry.group)
        ruleCountsByGroup[entry.group] = entry.ruleCount
        shardCountsByGroup[entry.group] = entry.definitions.count
        plannedDefinitions.append(
            contentsOf: entry.definitions.map { definition in
                ProtectionPlannedRuleDefinition(
                    group: entry.group,
                    source: entry.group == .trackingNetwork ? .tracking : .adblock,
                    definition: definition
                )
            }
        )
    }

    mutating func append(_ group: ProtectionPreparedGroup) {
        activeGroups.append(group.group)
        ruleCountsByGroup[group.group] = group.ruleCount
        shardCountsByGroup[group.group] = group.shardCount
        expectedIdentifiers.append(contentsOf: group.identifiers)
    }
}

private struct ProtectionAttachmentResolvedRules {
    let activeGroups: [SumiProtectionGroupKind]
    let identifiers: [String]
    let dedupeSummary: SumiProtectionDedupeSummary
    let overlapSummary: SumiProtectionOverlapSummary
    let definitions: [SumiContentRuleListDefinition]
}

private extension Array where Element == SumiProtectionGroupKind {
    func uniqueSorted() -> [SumiProtectionGroupKind] {
        Array(Set(self)).sorted { $0.rawValue < $1.rawValue }
    }
}
