import CryptoKit
import Foundation

@MainActor
protocol SumiProtectionAttachmentRuleProviding: AnyObject {
    var isEnabled: Bool { get }

    func setEnabled(_ isEnabled: Bool)
    func setPreparedBundleRuntimeEnabled(_ isEnabled: Bool)
    func activeManifestIfLoaded() -> AdblockCompiledGenerationManifest?
    func contentRuleListDefinitions(for protectionGroups: Set<SumiProtectionGroupKind>) throws -> [SumiContentRuleListDefinition]
    func siteOverride(for url: URL?) -> SumiAdblockSiteOverride
}

extension SumiAdBlockingModule: SumiProtectionAttachmentRuleProviding {}

@MainActor
final class SumiProtectionAttachmentOwner {
    private let ruleProvider: any SumiProtectionAttachmentRuleProviding
    private let siteNormalizer: SumiProtectionSiteNormalizer
    private let rulePlanner: SumiProtectionRulePlanner
    private let contentBlockingServiceFactory: @MainActor () -> SumiContentBlockingService
    private let attachmentServiceCache = SumiProtectionAttachmentServiceCache()

    init(
        ruleProvider: any SumiProtectionAttachmentRuleProviding,
        siteNormalizer: SumiProtectionSiteNormalizer = SumiProtectionSiteNormalizer(),
        contentBlockingServiceFactory: @escaping @MainActor () -> SumiContentBlockingService = {
            SumiContentBlockingService(policy: .disabled)
        }
    ) {
        self.ruleProvider = ruleProvider
        self.siteNormalizer = siteNormalizer
        self.rulePlanner = SumiProtectionRulePlanner(siteNormalizer: siteNormalizer)
        self.contentBlockingServiceFactory = contentBlockingServiceFactory
    }

    var contentBlockingServiceGenerationId: UInt64 {
        attachmentServiceCache.generationId
    }

    var isCacheEmpty: Bool {
        attachmentServiceCache.isEmpty
    }

    func syncRuntime(for level: SumiProtectionLevel) {
        switch level {
        case .off:
            ruleProvider.setEnabled(false)
            ruleProvider.setPreparedBundleRuntimeEnabled(false)
        case .protection:
            ruleProvider.setPreparedBundleRuntimeEnabled(true)
            ruleProvider.setEnabled(false)
        case .adblock:
            ruleProvider.setPreparedBundleRuntimeEnabled(true)
            ruleProvider.setEnabled(true)
        }
    }

    func applyNeeded(
        selectedLevel: SumiProtectionLevel,
        appliedLevel: SumiProtectionLevel,
        browserRestartRequired: Bool
    ) -> Bool {
        guard selectedLevel == appliedLevel else { return true }
        guard !browserRestartRequired else { return false }
        guard let requiredBundleProfileId = selectedLevel.preferredBundleProfileId else {
            return false
        }
        guard activePreparedBundleProfileId == requiredBundleProfileId,
              let manifest = ruleProvider.activeManifestIfLoaded()
        else { return true }
        let availableGroups = Set(Self.cachedPreparedGroups(level: selectedLevel, manifest: manifest).map(\.group))
        return !Set(selectedLevel.requestedGroups).isSubset(of: availableGroups)
    }

    func normalTabDecision(
        for url: URL?,
        profileId: UUID?,
        requestedLevel: SumiProtectionLevel
    ) -> SumiProtectionNormalTabDecision {
        let plan = cachedRulePlan(for: url, profileId: profileId, requestedLevel: requestedLevel)
        return SumiProtectionNormalTabDecision(
            plan: plan,
            contentBlockingService: cachedContentBlockingService(for: plan)
        )
    }

    func desiredAttachmentState(
        for url: URL?,
        requestedLevel: SumiProtectionLevel
    ) -> SumiProtectionAttachmentState {
        cachedRulePlan(for: url, profileId: nil, requestedLevel: requestedLevel).attachmentState
    }

    func rulePlan(
        for url: URL?,
        profileId: UUID?,
        requestedLevel: SumiProtectionLevel,
        includeExpensiveDiagnostics: Bool = false
    ) -> SumiProtectionRulePlan {
        makeRulePlan(
            for: url,
            profileId: profileId,
            requestedLevel: requestedLevel,
            includeExpensiveDiagnostics: includeExpensiveDiagnostics,
            loadRuleDefinitions: true
        )
    }

    func cachedRulePlan(
        for url: URL?,
        profileId: UUID?,
        requestedLevel: SumiProtectionLevel
    ) -> SumiProtectionRulePlan {
        makeRulePlan(
            for: url,
            profileId: profileId,
            requestedLevel: requestedLevel,
            includeExpensiveDiagnostics: false,
            loadRuleDefinitions: false
        )
    }

    func globalAttachmentPlan(
        for level: SumiProtectionLevel,
        includeExpensiveDiagnostics: Bool,
        loadRuleDefinitions: Bool
    ) -> SumiProtectionGlobalAttachmentPlan {
        let manifest = ruleProvider.activeManifestIfLoaded()
        if !loadRuleDefinitions,
           !includeExpensiveDiagnostics,
           let cachedAttachmentPlan = attachmentServiceCache.attachmentPlan,
           cachedAttachmentPlanMatches(cachedAttachmentPlan, level: level, manifest: manifest) {
            return metadataOnlyGlobalAttachmentPlan(cachedAttachmentPlan)
        }

        var activeGroups = [SumiProtectionGroupKind]()
        var ruleCountsByGroup = [SumiProtectionGroupKind: Int]()
        var shardCountsByGroup = [SumiProtectionGroupKind: Int]()
        var expectedRuleListIdentifiers = [String]()
        var plannedDefinitions = [PlannedRuleDefinition]()
        var planningErrors = [String]()
        let preparedBundleProfileId = manifest.flatMap { Self.preparedBundleProfileId(in: $0) }

        if let requiredProfileId = level.preferredBundleProfileId {
            if preparedBundleProfileId == requiredProfileId {
                if loadRuleDefinitions {
                    do {
                        let definitions = try ruleProvider.contentRuleListDefinitions(
                            for: Set(level.requestedGroups)
                        )
                        let grouped = groupPreparedDefinitions(
                            definitions,
                            level: level,
                            manifest: manifest
                        )
                        for entry in grouped where !entry.definitions.isEmpty {
                            activeGroups.append(entry.group)
                            ruleCountsByGroup[entry.group] = entry.ruleCount
                            shardCountsByGroup[entry.group] = entry.definitions.count
                            plannedDefinitions.append(contentsOf: entry.definitions.map {
                                PlannedRuleDefinition(
                                    group: entry.group,
                                    source: entry.group == .trackingNetwork ? .tracking : .adblock,
                                    definition: $0
                                )
                            })
                        }
                    } catch {
                        planningErrors.append("Prepared protection bundle rules unavailable: \(error.localizedDescription)")
                    }
                } else if let manifest {
                    let grouped = Self.cachedPreparedGroups(
                        level: level,
                        manifest: manifest
                    )
                    for entry in grouped where entry.shardCount > 0 {
                        activeGroups.append(entry.group)
                        ruleCountsByGroup[entry.group] = entry.ruleCount
                        shardCountsByGroup[entry.group] = entry.shardCount
                        expectedRuleListIdentifiers.append(contentsOf: entry.identifiers)
                    }
                }
            } else {
                planningErrors.append("Required prepared bundle profile \(requiredProfileId) is not active.")
            }
            let availablePreparedGroups = manifest.map {
                Set(Self.cachedPreparedGroups(level: level, manifest: $0).map(\.group))
            } ?? []
            for group in level.requestedGroups where !availablePreparedGroups.contains(group) {
                planningErrors.append("Prepared \(group.rawValue) group is unavailable in active bundle.")
            }
        }

        let finalActiveGroups: [SumiProtectionGroupKind]
        let dedupeSummary: SumiProtectionDedupeSummary
        let overlapSummary: SumiProtectionOverlapSummary
        let ruleDefinitions: [SumiContentRuleListDefinition]
        if loadRuleDefinitions {
            let deduped = Self.deduped(plannedDefinitions)
            let activeGroupsAfterDedupe = Set(deduped.definitions.map(\.group))
            finalActiveGroups = activeGroups
                .filter { activeGroupsAfterDedupe.contains($0) }
                .uniqueSorted()
            expectedRuleListIdentifiers = deduped.definitions.map(\.definition.webKitStoreIdentifier).sorted()
            dedupeSummary = deduped.summary
            overlapSummary = Self.overlapSummary(
                for: plannedDefinitions,
                includeExpensiveDiagnostics: includeExpensiveDiagnostics
            )
            ruleDefinitions = deduped.definitions.map(\.definition)
        } else {
            finalActiveGroups = activeGroups.uniqueSorted()
            expectedRuleListIdentifiers = Array(Set(expectedRuleListIdentifiers)).sorted()
            dedupeSummary = .empty
            overlapSummary = .deferred
            ruleDefinitions = []
        }

        return SumiProtectionGlobalAttachmentPlan(
            level: level,
            activeGroups: finalActiveGroups,
            inactiveGroups: level.requestedGroups.filter { !finalActiveGroups.contains($0) },
            ruleCountsByGroup: ruleCountsByGroup,
            shardCountsByGroup: shardCountsByGroup,
            expectedRuleListIdentifiers: expectedRuleListIdentifiers,
            dedupeSummary: dedupeSummary,
            overlapSummary: overlapSummary,
            planningErrors: planningErrors,
            ruleDefinitions: ruleDefinitions,
            bundleSource: manifest?.generationSource,
            nativeRuleBundleId: manifest?.nativeRuleBundleId,
            bundleProfileId: Self.installedBundleProfileId(from: manifest),
            requiredBundleProfileId: level.preferredBundleProfileId,
            activeGenerationId: manifest?.activeGenerationId,
            previousGenerationId: manifest?.previousGenerationId,
            previousGenerationRetained: manifest?.previousGenerationId != nil
        )
    }

    func prepareCachedAttachmentService(
        for level: SumiProtectionLevel
    ) async throws {
        guard level != .off else {
            clearCachedAttachmentService()
            return
        }

        let metadataPlan = globalAttachmentPlan(
            for: level,
            includeExpensiveDiagnostics: false,
            loadRuleDefinitions: false
        )
#if DEBUG
        SumiProtectionStartupRestoreDiagnostics.shared.recordExpectedShardIdentifiers(
            metadataPlan.expectedRuleListIdentifiers
        )
#endif

        try validateRequiredGroupsReady(in: metadataPlan)

        guard metadataPlan.isAttachable else {
            attachmentServiceCache.replace(
                withMetadataOnlyPlan: metadataOnlyGlobalAttachmentPlan(metadataPlan),
                service: nil
            )
            return
        }

        let service = contentBlockingServiceFactory()

        let metadataOnlyDefinitions = metadataOnlyRuleDefinitions(
            matching: metadataPlan.expectedRuleListIdentifiers,
            manifest: ruleProvider.activeManifestIfLoaded()
        )
        if metadataOnlyDefinitions.map(\.webKitStoreIdentifier).sorted()
            == metadataPlan.expectedRuleListIdentifiers.sorted() {
            do {
                let preparedUpdate = try await service.prepareExistingRuleListUpdate(
                    ruleLists: metadataOnlyDefinitions
                )
                service.commitPreparedContentBlockingUpdate(preparedUpdate)
                attachmentServiceCache.replace(
                    withMetadataOnlyPlan: metadataOnlyGlobalAttachmentPlan(metadataPlan),
                    service: service
                )
#if DEBUG
                SumiProtectionStartupRestoreDiagnostics.shared.recordMetadataOnlyRestoreUsed()
#endif
                return
            } catch {
#if DEBUG
                let fallbackReason = "Protection attachment lookup-only restore failed: \(error.localizedDescription)"
                SumiProtectionStartupRestoreDiagnostics.shared.recordFallback(reason: fallbackReason)
                SumiProtectionStartupRestoreDiagnostics.shared.recordPayloadBackedRestoreUsed(reason: fallbackReason)
                SumiProtectionStartupRestoreDiagnostics.shared.recordRepairCompileUsed(reason: fallbackReason)
#endif
                // Repair-on-miss stays on the existing payload-backed path below.
            }
        }

        let plan = globalAttachmentPlan(
            for: level,
            includeExpensiveDiagnostics: false,
            loadRuleDefinitions: true
        )
        try validateRequiredGroupsReady(in: plan)

        guard plan.isAttachable else {
            attachmentServiceCache.replace(
                withMetadataOnlyPlan: metadataOnlyGlobalAttachmentPlan(plan),
                service: nil
            )
            return
        }

        let preparedUpdate = try await service.prepareRuleListUpdate(
            ruleLists: plan.ruleDefinitions,
            retainEncodedRuleListsInPreparedPolicy: false
        )
        service.commitPreparedContentBlockingUpdate(preparedUpdate)
        attachmentServiceCache.replace(
            withMetadataOnlyPlan: metadataOnlyGlobalAttachmentPlan(plan),
            service: service
        )
    }

    func validateRequiredGroupsReady(
        in plan: SumiProtectionGlobalAttachmentPlan
    ) throws {
        if let requiredProfileId = plan.requiredBundleProfileId,
           plan.bundleProfileId != requiredProfileId {
            throw SumiProtectionApplyError.requiredPreparedBundleUnavailable(
                profileId: requiredProfileId,
                detail: "The active prepared bundle after install is \(plan.bundleProfileId ?? "nil")."
            )
        }

        switch plan.level {
        case .off:
            return
        case .protection:
            guard plan.activeGroups.contains(.trackingNetwork) else {
                throw SumiProtectionApplyError.requiredPreparedBundleUnavailable(
                    profileId: SumiProtectionBundleProfile.unified,
                    detail: "No prepared trackingNetwork rule lists were available after install."
                )
            }
        case .adblock:
            guard plan.activeGroups.contains(.trackingNetwork) else {
                throw SumiProtectionApplyError.requiredPreparedBundleUnavailable(
                    profileId: SumiProtectionBundleProfile.unified,
                    detail: "No prepared trackingNetwork rule lists were available after install."
                )
            }
            guard plan.activeGroups.contains(.adblockAdsPrivacyNetwork) else {
                throw SumiProtectionApplyError.requiredPreparedBundleUnavailable(
                    profileId: SumiProtectionBundleProfile.adblock,
                    detail: "No adguardAdsPrivacy network rule lists were available after install."
                )
            }
        }
    }

    func clearCachedAttachmentService() {
        attachmentServiceCache.clear()
    }

    func trackingSourceAvailable(manifest: AdblockCompiledGenerationManifest?) -> Bool {
        guard let manifest else { return false }
        return Self.cachedPreparedGroups(level: .protection, manifest: manifest)
            .contains { $0.group == .trackingNetwork && $0.shardCount > 0 }
    }

    func globallyAvailableGroups(
        manifest: AdblockCompiledGenerationManifest?,
        trackingSourceAvailable: Bool
    ) -> [SumiProtectionGroupKind] {
        var groups = [SumiProtectionGroupKind]()
        if trackingSourceAvailable {
            groups.append(.trackingNetwork)
        }

        if let manifest,
           Self.preparedBundleProfileId(in: manifest) != nil {
            groups.append(contentsOf: Self.cachedPreparedGroups(level: .adblock, manifest: manifest).map(\.group))
        }

        return groups.uniqueSorted()
    }

    func surfaceEligibility(for url: URL?) -> SumiAdblockSurfaceEligibility {
        SumiAdblockSurfaceEligibility.evaluate(url: url, normalizer: siteNormalizer)
    }

    func preparedBundleProfileId(in manifest: AdblockCompiledGenerationManifest) -> String? {
        Self.preparedBundleProfileId(in: manifest)
    }

    private var activePreparedBundleProfileId: String? {
        let manifest = ruleProvider.activeManifestIfLoaded()
        return manifest.flatMap { Self.preparedBundleProfileId(in: $0) }
    }

    private func makeRulePlan(
        for url: URL?,
        profileId: UUID?,
        requestedLevel: SumiProtectionLevel,
        includeExpensiveDiagnostics: Bool,
        loadRuleDefinitions: Bool
    ) -> SumiProtectionRulePlan {
        _ = profileId
        let activeManifest = requestedLevel == .off
            ? nil
            : ruleProvider.activeManifestIfLoaded()
        return rulePlanner.makeRulePlan(
            for: url,
            requestedLevel: requestedLevel,
            activeManifest: activeManifest,
            includeExpensiveDiagnostics: includeExpensiveDiagnostics,
            loadRuleDefinitions: loadRuleDefinitions,
            siteOverrideProvider: { [ruleProvider] url in
                ruleProvider.siteOverride(for: url)
            },
            globalAttachmentPlanProvider: { [self] level, includeExpensiveDiagnostics, loadRuleDefinitions in
                globalAttachmentPlan(
                    for: level,
                    includeExpensiveDiagnostics: includeExpensiveDiagnostics,
                    loadRuleDefinitions: loadRuleDefinitions
                )
            },
            emptyGlobalAttachmentPlanProvider: { level, manifest in
                Self.emptyGlobalAttachmentPlan(for: level, manifest: manifest)
            }
        )
    }

    private func cachedContentBlockingService(
        for plan: SumiProtectionRulePlan
    ) -> SumiContentBlockingService? {
        let manifest = ruleProvider.activeManifestIfLoaded()
        let cachedPlanMatchesActiveManifest = attachmentServiceCache.attachmentPlan.map {
            cachedAttachmentPlanMatches(
                $0,
                level: plan.requestedLevel,
                manifest: manifest
            )
        } ?? false
        return attachmentServiceCache.cachedContentBlockingService(
            for: plan,
            cachedPlanMatchesActiveManifest: cachedPlanMatchesActiveManifest
        )
    }

    private static func emptyGlobalAttachmentPlan(
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
            bundleProfileId: installedBundleProfileId(from: manifest),
            requiredBundleProfileId: level.preferredBundleProfileId,
            activeGenerationId: manifest?.activeGenerationId,
            previousGenerationId: manifest?.previousGenerationId,
            previousGenerationRetained: manifest?.previousGenerationId != nil
        )
    }

    private func metadataOnlyGlobalAttachmentPlan(
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

    private func cachedAttachmentPlanMatches(
        _ plan: SumiProtectionGlobalAttachmentPlan,
        level: SumiProtectionLevel,
        manifest: AdblockCompiledGenerationManifest?
    ) -> Bool {
        guard plan.level == level else { return false }
        guard plan.requiredBundleProfileId == level.preferredBundleProfileId else { return false }
        guard plan.activeGenerationId == manifest?.activeGenerationId else { return false }
        guard plan.bundleProfileId == Self.installedBundleProfileId(from: manifest) else { return false }
        return true
    }

    private func groupPreparedDefinitions(
        _ definitions: [SumiContentRuleListDefinition],
        level: SumiProtectionLevel,
        manifest: AdblockCompiledGenerationManifest?
    ) -> [(group: SumiProtectionGroupKind, definitions: [SumiContentRuleListDefinition], ruleCount: Int)] {
        guard let manifest,
              Self.preparedBundleProfileId(in: manifest) != nil
        else { return [] }
        let definitionsByIdentifier = definitions.reduce(into: [String: SumiContentRuleListDefinition]()) { result, definition in
            result[definition.webKitStoreIdentifier] = definition
        }
        return Self.cachedPreparedGroups(level: level, manifest: manifest)
            .compactMap { cachedGroup in
                let definitions = cachedGroup.identifiers.compactMap { definitionsByIdentifier[$0] }
                guard !definitions.isEmpty else { return nil }
                return (
                    group: cachedGroup.group,
                    definitions: definitions,
                    ruleCount: cachedGroup.ruleCount
                )
            }
    }

    private func metadataOnlyRuleDefinitions(
        matching identifiers: [String],
        manifest: AdblockCompiledGenerationManifest?
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

    private static func cachedPreparedGroups(
        level: SumiProtectionLevel,
        manifest: AdblockCompiledGenerationManifest
    ) -> [CachedAdblockGroup] {
        guard let bundleProfileId = preparedBundleProfileId(in: manifest) else { return [] }
        let groups = manifest.allNativeShards.reduce(into: [SumiProtectionGroupKind: CachedAdblockGroup]()) { result, shard in
            guard let group = protectionGroup(
                for: shard,
                bundleProfileId: bundleProfileId,
                level: level
            ) else { return }
            let existing = result[group]
            result[group] = CachedAdblockGroup(
                group: group,
                identifiers: (existing?.identifiers ?? []) + [shard.webKitIdentifier],
                shardCount: (existing?.shardCount ?? 0) + 1,
                ruleCount: (existing?.ruleCount ?? 0) + shard.approximateRuleCount
            )
        }
        return groups.values.sorted { $0.group.rawValue < $1.group.rawValue }
    }

    private static func protectionGroup(
        for shard: NativeContentBlockingShardDescriptor,
        bundleProfileId: String,
        level: SumiProtectionLevel
    ) -> SumiProtectionGroupKind? {
        guard shard.kind == .network else { return nil }
        if let protectionGroup = shard.protectionGroup {
            return level.requestedGroups.contains(protectionGroup) ? protectionGroup : nil
        }
        switch (bundleProfileId, level) {
        case (SumiProtectionBundleProfile.adblock, .adblock):
            return .adblockAdsPrivacyNetwork
        default:
            return nil
        }
    }

    private static func preparedBundleProfileId(
        in manifest: AdblockCompiledGenerationManifest
    ) -> String? {
        SumiProtectionPreparedBundleIdentity.preparedBundleProfileId(in: manifest)
    }

    private static func installedBundleProfileId(
        from manifest: AdblockCompiledGenerationManifest?
    ) -> String? {
        SumiProtectionPreparedBundleIdentity.installedBundleProfileId(from: manifest)
    }

    private static func deduped(
        _ plannedDefinitions: [PlannedRuleDefinition]
    ) -> (definitions: [PlannedRuleDefinition], summary: SumiProtectionDedupeSummary) {
        var seenIdentifiers = Set<String>()
        var seenCanonicalHashes = [String: PlannedRuleDefinition]()
        var seenGroupHashes = Set<String>()
        var output = [PlannedRuleDefinition]()
        var duplicateIdentifierCount = 0
        var duplicateCanonicalCount = 0
        var duplicateGroupHashCount = 0
        var canonicalUnavailableCount = 0
        var removedIdentifiers = [String]()

        for planned in plannedDefinitions {
            let identifier = planned.definition.webKitStoreIdentifier
            guard seenIdentifiers.insert(identifier).inserted else {
                duplicateIdentifierCount += 1
                removedIdentifiers.append(identifier)
                continue
            }

            let groupHashKey = "\(planned.group.rawValue):\(planned.definition.contentHash)"
            guard seenGroupHashes.insert(groupHashKey).inserted else {
                duplicateGroupHashCount += 1
                removedIdentifiers.append(identifier)
                continue
            }

            if let canonicalHash = canonicalWebKitJSONHash(planned.definition.encodedContentRuleList) {
                if seenCanonicalHashes[canonicalHash] != nil {
                    duplicateCanonicalCount += 1
                    removedIdentifiers.append(identifier)
                    continue
                }
                seenCanonicalHashes[canonicalHash] = planned
            } else {
                canonicalUnavailableCount += 1
            }

            output.append(planned)
        }

        return (
            output,
            SumiProtectionDedupeSummary(
                inputRuleListCount: plannedDefinitions.count,
                finalRuleListCount: output.count,
                duplicateIdentifierCountRemoved: duplicateIdentifierCount,
                duplicateCanonicalJSONCountRemoved: duplicateCanonicalCount,
                duplicateGroupContentHashCountRemoved: duplicateGroupHashCount,
                canonicalJSONUnavailableCount: canonicalUnavailableCount,
                removedIdentifiers: removedIdentifiers.sorted()
            )
        )
    }

    private static func overlapSummary(
        for plannedDefinitions: [PlannedRuleDefinition],
        includeExpensiveDiagnostics: Bool
    ) -> SumiProtectionOverlapSummary {
        let tracking = plannedDefinitions.filter { $0.source == .tracking }
        let adblock = plannedDefinitions.filter { $0.source == .adblock }
        guard !tracking.isEmpty, !adblock.isEmpty else {
            return SumiProtectionOverlapSummary(
                exactCanonicalOverlapCount: 0,
                domainResourceOverlapCount: 0,
                exactComparisonAvailable: false,
                notes: ["Tracking and Adblock are not both active in this plan."]
            )
        }
        guard includeExpensiveDiagnostics else {
            return .deferred
        }

        let trackingCanonical = Set(tracking.compactMap {
            canonicalWebKitJSONHash($0.definition.encodedContentRuleList)
        })
        let adblockCanonical = Set(adblock.compactMap {
            canonicalWebKitJSONHash($0.definition.encodedContentRuleList)
        })
        let exactComparisonAvailable = trackingCanonical.count == tracking.count
            && adblockCanonical.count == adblock.count

        let trackingDomains = Set(tracking.flatMap {
            urlFilterTokens(in: $0.definition.encodedContentRuleList)
        })
        let adblockDomains = Set(adblock.flatMap {
            urlFilterTokens(in: $0.definition.encodedContentRuleList)
        })
        var notes = [String]()
        if !exactComparisonAvailable {
            notes.append("Exact cross-source dedupe is unavailable for rule lists that cannot be safely canonicalized.")
        }
        if trackingDomains.isEmpty || adblockDomains.isEmpty {
            notes.append("Domain/resource overlap is heuristic because not every WebKit trigger exposes a host token.")
        }

        return SumiProtectionOverlapSummary(
            exactCanonicalOverlapCount: trackingCanonical.intersection(adblockCanonical).count,
            domainResourceOverlapCount: trackingDomains.intersection(adblockDomains).count,
            exactComparisonAvailable: exactComparisonAvailable,
            notes: notes
        )
    }

    private static func canonicalWebKitJSONHash(_ encodedContentRuleList: String) -> String? {
        guard let data = encodedContentRuleList.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let canonicalData = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys]
              )
        else { return nil }
        return sha256Hex(canonicalData)
    }

    private static func urlFilterTokens(in encodedContentRuleList: String) -> [String] {
        guard let data = encodedContentRuleList.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        return array.compactMap { rule in
            guard let trigger = rule["trigger"] as? [String: Any],
                  let filter = trigger["url-filter"] as? String
            else { return nil }
            return domainToken(from: filter)
        }
    }

    private static func domainToken(from filter: String) -> String? {
        let lowercased = filter.lowercased()
        let pieces = lowercased.split { character in
            !(character.isLetter || character.isNumber || character == "." || character == "-")
        }
        return pieces
            .map(String.init)
            .first { token in
                token.contains(".")
                    && !token.hasPrefix(".")
                    && !token.hasSuffix(".")
                    && token.count > 3
            }
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

@MainActor
private final class SumiProtectionAttachmentServiceCache {
    private(set) var attachmentPlan: SumiProtectionGlobalAttachmentPlan?
    private var contentBlockingService: SumiContentBlockingService?
    private(set) var generationId: UInt64 = 0

    var isEmpty: Bool {
        attachmentPlan == nil && contentBlockingService == nil
    }

    func cachedContentBlockingService(
        for plan: SumiProtectionRulePlan,
        cachedPlanMatchesActiveManifest: Bool
    ) -> SumiContentBlockingService? {
        guard plan.sitePolicyAllowsProtection,
              !plan.expectedRuleListIdentifiers.isEmpty,
              cachedPlanMatchesActiveManifest,
              let contentBlockingService,
              contentBlockingService.latestRuleListIdentifiers == plan.expectedRuleListIdentifiers
        else { return nil }
        return contentBlockingService
    }

    func replace(
        withMetadataOnlyPlan plan: SumiProtectionGlobalAttachmentPlan,
        service: SumiContentBlockingService?
    ) {
        attachmentPlan = plan
        contentBlockingService = service
        generationId &+= 1
    }

    func clear() {
        attachmentPlan = nil
        contentBlockingService = nil
        generationId &+= 1
    }
}

private enum PlannedRuleSource: Sendable {
    case tracking
    case adblock
}

private struct PlannedRuleDefinition: Equatable, Sendable {
    let group: SumiProtectionGroupKind
    let source: PlannedRuleSource
    let definition: SumiContentRuleListDefinition
}

private struct CachedAdblockGroup: Equatable, Sendable {
    let group: SumiProtectionGroupKind
    let identifiers: [String]
    let shardCount: Int
    let ruleCount: Int
}

private extension Array where Element == SumiProtectionGroupKind {
    func uniqueSorted() -> [SumiProtectionGroupKind] {
        Array(Set(self)).sorted { $0.rawValue < $1.rawValue }
    }
}
