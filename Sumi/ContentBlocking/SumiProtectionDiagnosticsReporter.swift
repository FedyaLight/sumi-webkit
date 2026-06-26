import Foundation

struct SumiProtectionCurrentTabDiagnostics: Equatable, Sendable {
    let urlString: String?
    let host: String?
    let normalizedSiteKey: String?
    let protectionLevel: SumiProtectionLevel
    let effectiveProtectionLevel: SumiProtectionLevel
    let activeGroups: [SumiProtectionGroupKind]
    let inactiveGroups: [SumiProtectionGroupKind]
    let desiredGroups: [SumiProtectionGroupKind]
    let perSiteProtectionEnabled: Bool
    let reloadRequired: Bool
    let reloadRequiredReason: String?
    let didManualReloadRebuildWebView: Bool
    let appliedAfterManualReload: Bool
    let contentBlockingServiceGenerationId: UInt64?
    let generationSource: AdblockRuleGenerationSource?
    let nativeRuleBundleId: String?
    let bundleProfileId: String?
    let requiredBundleProfileId: String?
    let trackingGroupActive: Bool
    let adblockGroupActive: Bool
    let ruleCountsByGroup: [SumiProtectionGroupKind: Int]
    let shardCountsByGroup: [SumiProtectionGroupKind: Int]
    let dedupeSummary: SumiProtectionDedupeSummary
    let overlapSummary: SumiProtectionOverlapSummary
    let expectedRuleListIdentifiers: [String]
    let lookupSucceededIdentifiers: [String]
    let lookupFailedIdentifiers: [String]
    let addedToUserContentControllerIdentifiers: [String]
    let recordedAppliedRuleListIdentifiers: [String]
    let actualAttachedRuleListIdentifiers: [String]
    let missingRuleListIdentifiers: [String]
    let missingAfterAttachmentIdentifiers: [String]
    let unexpectedOldRuleListIdentifiers: [String]
    let activeGenerationId: String?
    let appliedProtectionGenerationId: String?
    let appliedProtectionGroups: [SumiProtectionGroupKind]
    let previousGenerationId: String?
    let previousGenerationRetained: Bool
    let ruleListIdentifierSamplesByGroup: [SumiProtectionGroupKind: [String]]
    let eligibleSurfaceReason: String?
    let ineligibleSurfaceReason: String?
    let currentProcessResidentMemoryBytes: UInt64?
    let planComputeDuration: TimeInterval
    let bundleLookupDuration: TimeInterval?
    let ruleListLookupDuration: TimeInterval?
    let tabAttachmentDuration: TimeInterval?
    let webViewRebuildDuration: TimeInterval?
    let urlHubSummaryDuration: TimeInterval?
    let planningErrors: [String]

    var developerReport: String {
        [
            "Sumi Adblock & Protection current-tab diagnostics",
            "url=\(urlString ?? "nil")",
            "host=\(host ?? "nil")",
            "normalizedSiteKey=\(normalizedSiteKey ?? "nil")",
            "protectionLevel=\(protectionLevel.rawValue)",
            "effectiveProtectionLevel=\(effectiveProtectionLevel.rawValue)",
            "activeGroups=\(activeGroups.map(\.rawValue).joined(separator: ","))",
            "inactiveGroups=\(inactiveGroups.map(\.rawValue).joined(separator: ","))",
            "desiredGroups=\(desiredGroups.map(\.rawValue).joined(separator: ","))",
            "perSiteProtectionEnabled=\(perSiteProtectionEnabled)",
            "reloadRequired=\(reloadRequired)",
            "reloadRequiredReason=\(reloadRequiredReason ?? "nil")",
            "manualReloadRebuiltWebView=\(didManualReloadRebuildWebView)",
            "manualReloadMatchedDesiredState=\(appliedAfterManualReload)",
            "contentBlockingServiceGenerationId=\(contentBlockingServiceGenerationId.map(String.init) ?? "nil")",
            "generationSource=\(generationSource?.rawValue ?? "nil")",
            "nativeRuleBundleId=\(nativeRuleBundleId ?? "nil")",
            "bundleProfileId=\(bundleProfileId ?? "nil")",
            "requiredBundleProfileId=\(requiredBundleProfileId ?? "nil")",
            "trackingGroupActive=\(trackingGroupActive)",
            "adblockGroupActive=\(adblockGroupActive)",
            "ruleCountsByGroup=\(Self.renderCounts(ruleCountsByGroup))",
            "shardCountsByGroup=\(Self.renderCounts(shardCountsByGroup))",
            "dedupeSummary=\(dedupeSummary.reportLine)",
            "overlapSummary=\(overlapSummary.reportLine)",
            "expectedRuleListIdentifiers=\(expectedRuleListIdentifiers.joined(separator: ","))",
            "lookupSucceededIdentifiers=\(lookupSucceededIdentifiers.joined(separator: ","))",
            "lookupFailedIdentifiers=\(lookupFailedIdentifiers.joined(separator: ","))",
            "addedToUserContentControllerIdentifiers=\(addedToUserContentControllerIdentifiers.joined(separator: ","))",
            "recordedAppliedRuleListIdentifiers=\(recordedAppliedRuleListIdentifiers.joined(separator: ","))",
            "actualAttachedRuleListIdentifiers=\(actualAttachedRuleListIdentifiers.joined(separator: ","))",
            "missingRuleListIdentifiers=\(missingRuleListIdentifiers.joined(separator: ","))",
            "missingAfterAttachmentIdentifiers=\(missingAfterAttachmentIdentifiers.joined(separator: ","))",
            "unexpectedOldRuleListIdentifiers=\(unexpectedOldRuleListIdentifiers.joined(separator: ","))",
            "activeGenerationId=\(activeGenerationId ?? "nil")",
            "appliedProtectionGenerationId=\(appliedProtectionGenerationId ?? "nil")",
            "appliedProtectionGroups=\(appliedProtectionGroups.map(\.rawValue).joined(separator: ","))",
            "previousGenerationId=\(previousGenerationId ?? "nil")",
            "previousGenerationRetained=\(previousGenerationRetained)",
            "ruleListIdentifierSamplesByGroup=\(Self.renderIdentifierSamples(ruleListIdentifierSamplesByGroup))",
            "eligibleSurfaceReason=\(eligibleSurfaceReason ?? "nil")",
            "ineligibleSurfaceReason=\(ineligibleSurfaceReason ?? "nil")",
            "currentProcessResidentMemoryBytes=\(currentProcessResidentMemoryBytes.map(String.init) ?? "nil")",
            "planComputeDuration=\(Self.renderDuration(planComputeDuration))",
            "bundleLookupDuration=\(Self.renderOptionalDuration(bundleLookupDuration))",
            "ruleListLookupDuration=\(Self.renderOptionalDuration(ruleListLookupDuration))",
            "tabAttachmentDuration=\(Self.renderOptionalDuration(tabAttachmentDuration))",
            "webViewRebuildDuration=\(Self.renderOptionalDuration(webViewRebuildDuration))",
            "urlHubSummaryDuration=\(Self.renderOptionalDuration(urlHubSummaryDuration))",
            "planningErrors=\(planningErrors.joined(separator: " | "))",
        ].joined(separator: "\n")
    }

    static func renderCounts(_ counts: [SumiProtectionGroupKind: Int]) -> String {
        SumiProtectionGroupKind.allCases
            .compactMap { group in
                counts[group].map { "\(group.rawValue):\($0)" }
            }
            .joined(separator: ",")
    }

    static func renderIdentifierSamples(_ samples: [SumiProtectionGroupKind: [String]]) -> String {
        SumiProtectionGroupKind.allCases
            .compactMap { group in
                samples[group].map { "\(group.rawValue):\($0.joined(separator: "|"))" }
            }
            .joined(separator: ",")
    }

    static func renderDuration(_ duration: TimeInterval) -> String {
        String(format: "%.3fms", duration * 1000)
    }

    static func renderOptionalDuration(_ duration: TimeInterval?) -> String {
        duration.map(renderDuration) ?? "nil"
    }
}

struct SumiProtectionGlobalDiagnostics: Equatable, Sendable {
    let selectedProtectionLevel: SumiProtectionLevel
    let appliedProtectionLevel: SumiProtectionLevel
    let browserRestartRequired: Bool
    let generationSource: AdblockRuleGenerationSource?
    let nativeRuleBundleId: String?
    let bundleProfileId: String?
    let activeGenerationId: String?
    let remoteReleaseVersion: String?
    let remoteReleaseTag: String?
    let remoteReleaseURL: String?
    let remoteManifestSignatureRequired: Bool
    let remoteManifestSignatureVerified: Bool?
    let remoteSigningKeyId: String?
    let remoteSigningKeyVersion: Int?
    let lastRemoteUpdateError: String?
    let lastSignatureError: String?
    let downgradeRejected: Bool
    let bundleGeneratedDate: Date?
    let lastSuccessfulBundleInstallDate: Date?
    let requiredBundleProfileId: String?
    let preparedBundleAvailable: Bool
    let preparedBundleSource: SumiAdblockBundleInstallSource?
    let searchedBundlePaths: [SumiPreparedAdblockBundleSearchPath]
    let applyNeeded: Bool
    let lastApplySummary: String?
    let lastApplyError: String?
    let globalGroupsAvailable: [SumiProtectionGroupKind]
    let groupSourceDiagnostics: [SumiProtectionGroupKind: String]
    let trackingSourceAvailable: Bool
    let adblockBundleAvailable: Bool
    let strictOffActive: Bool
}

enum SumiProtectionDiagnosticsReporter {
    static func currentTabDiagnostics(
        for url: URL?,
        appliedState: SumiProtectionAttachmentState?,
        reloadRequired: Bool,
        reloadRequiredReason: String?,
        didManualReloadRebuildWebView: Bool,
        appliedAfterManualReload: Bool,
        actualAttachedRuleListIdentifiers: [String]?,
        contentBlockingAssetSummary: SumiNormalTabContentBlockingAssetSummary?,
        webViewRebuildDuration: TimeInterval?,
        urlHubSummaryDuration: TimeInterval?,
        plan: SumiProtectionRulePlan,
        planComputeDuration: TimeInterval,
        contentBlockingServiceGenerationId: UInt64?,
        bundleLookupDuration: TimeInterval?
    ) -> SumiProtectionCurrentTabDiagnostics {
        let recordedApplied = appliedState?.attachedRuleListIdentifiers ?? []
        let lookupSucceeded = contentBlockingAssetSummary?.lookupSucceededIdentifiers ?? []
        let lookupFailed = contentBlockingAssetSummary?.lookupFailedIdentifiers ?? []
        let added = contentBlockingAssetSummary?.addedToUserContentControllerIdentifiers ?? []
        let actual = (
            actualAttachedRuleListIdentifiers
                ?? contentBlockingAssetSummary?.globalRuleListIdentifiers
                ?? recordedApplied
        ).sorted()
        let expected = plan.expectedRuleListIdentifiers
        let expectedSet = Set(expected)
        let actualSet = Set(actual)
        let missing = expected.filter { !actualSet.contains($0) }
        let unexpected = actual.filter {
            !expectedSet.contains($0) && isSumiOwnedProtectionIdentifier($0)
        }

        return SumiProtectionCurrentTabDiagnostics(
            urlString: url?.absoluteString,
            host: url?.host,
            normalizedSiteKey: plan.siteHost,
            protectionLevel: plan.requestedLevel,
            effectiveProtectionLevel: plan.effectiveLevel,
            activeGroups: plan.activeGroups,
            inactiveGroups: plan.inactiveGroups,
            desiredGroups: plan.requestedLevel.requestedGroups,
            perSiteProtectionEnabled: plan.sitePolicyAllowsProtection,
            reloadRequired: reloadRequired,
            reloadRequiredReason: reloadRequired ? (reloadRequiredReason ?? "protection attachment plan changed") : nil,
            didManualReloadRebuildWebView: didManualReloadRebuildWebView,
            appliedAfterManualReload: appliedAfterManualReload,
            contentBlockingServiceGenerationId: contentBlockingServiceGenerationId,
            generationSource: plan.bundleSource,
            nativeRuleBundleId: plan.nativeRuleBundleId,
            bundleProfileId: plan.bundleProfileId,
            requiredBundleProfileId: plan.requiredBundleProfileId,
            trackingGroupActive: plan.trackingGroupActive,
            adblockGroupActive: plan.adblockGroupActive,
            ruleCountsByGroup: plan.ruleCountsByGroup,
            shardCountsByGroup: plan.shardCountsByGroup,
            dedupeSummary: plan.dedupeSummary,
            overlapSummary: plan.overlapSummary,
            expectedRuleListIdentifiers: expected,
            lookupSucceededIdentifiers: lookupSucceeded,
            lookupFailedIdentifiers: lookupFailed,
            addedToUserContentControllerIdentifiers: added,
            recordedAppliedRuleListIdentifiers: recordedApplied,
            actualAttachedRuleListIdentifiers: actual,
            missingRuleListIdentifiers: missing,
            missingAfterAttachmentIdentifiers: missing,
            unexpectedOldRuleListIdentifiers: unexpected,
            activeGenerationId: plan.activeGenerationId,
            appliedProtectionGenerationId: appliedState?.activeGenerationId,
            appliedProtectionGroups: appliedState?.activeGroups ?? [],
            previousGenerationId: plan.previousGenerationId,
            previousGenerationRetained: plan.previousGenerationRetained,
            ruleListIdentifierSamplesByGroup: ruleListIdentifierSamplesByGroup(for: plan),
            eligibleSurfaceReason: plan.ineligibleSurfaceReason == nil ? "eligible http(s) web surface" : nil,
            ineligibleSurfaceReason: plan.ineligibleSurfaceReason,
            currentProcessResidentMemoryBytes: currentProcessResidentMemoryBytes(),
            planComputeDuration: planComputeDuration,
            bundleLookupDuration: bundleLookupDuration,
            ruleListLookupDuration: contentBlockingAssetSummary?.ruleListLookupDuration,
            tabAttachmentDuration: contentBlockingAssetSummary?.tabAttachmentDuration,
            webViewRebuildDuration: webViewRebuildDuration,
            urlHubSummaryDuration: urlHubSummaryDuration,
            planningErrors: plan.planningErrors
        )
    }

    static func globalDiagnostics(
        selectedLevel: SumiProtectionLevel,
        appliedLevel: SumiProtectionLevel,
        browserRestartRequired: Bool,
        manifest: AdblockCompiledGenerationManifest?,
        bundleDiagnostics: SumiProtectionBundleLifecycleDiagnostics,
        requiredBundleProfileId: String?,
        applyNeeded: Bool,
        lastApplySummary: String?,
        lastApplyError: String?,
        availableGroups: [SumiProtectionGroupKind],
        trackingSourceAvailable: Bool,
        adblockBundleAvailable: Bool,
        strictOffActive: Bool
    ) -> SumiProtectionGlobalDiagnostics {
        SumiProtectionGlobalDiagnostics(
            selectedProtectionLevel: selectedLevel,
            appliedProtectionLevel: appliedLevel,
            browserRestartRequired: browserRestartRequired,
            generationSource: manifest?.generationSource,
            nativeRuleBundleId: manifest?.nativeRuleBundleId,
            bundleProfileId: SumiProtectionPreparedBundleIdentity.installedBundleProfileId(from: manifest),
            activeGenerationId: manifest?.activeGenerationId,
            remoteReleaseVersion: manifest?.remoteReleaseVersion,
            remoteReleaseTag: manifest?.remoteReleaseTag,
            remoteReleaseURL: manifest?.remoteReleaseURL,
            remoteManifestSignatureRequired: bundleDiagnostics.remoteManifestSignatureRequired,
            remoteManifestSignatureVerified: bundleDiagnostics.remoteManifestSignatureVerified,
            remoteSigningKeyId: bundleDiagnostics.remoteSigningKeyId,
            remoteSigningKeyVersion: bundleDiagnostics.remoteSigningKeyVersion,
            lastRemoteUpdateError: bundleDiagnostics.lastRemoteUpdateError,
            lastSignatureError: bundleDiagnostics.lastSignatureError,
            downgradeRejected: bundleDiagnostics.downgradeRejected,
            bundleGeneratedDate: manifest?.createdDate,
            lastSuccessfulBundleInstallDate: bundleDiagnostics.lastSuccessfulBundleInstallDate,
            requiredBundleProfileId: requiredBundleProfileId,
            preparedBundleAvailable: bundleDiagnostics.preparedBundleAvailable,
            preparedBundleSource: bundleDiagnostics.preparedBundleSource,
            searchedBundlePaths: bundleDiagnostics.searchedBundlePaths,
            applyNeeded: applyNeeded,
            lastApplySummary: lastApplySummary,
            lastApplyError: lastApplyError,
            globalGroupsAvailable: availableGroups,
            groupSourceDiagnostics: groupSourceDiagnostics(from: manifest),
            trackingSourceAvailable: trackingSourceAvailable,
            adblockBundleAvailable: adblockBundleAvailable,
            strictOffActive: strictOffActive
        )
    }

#if DEBUG
    static func copyDiagnosticsReport(
        global: SumiProtectionGlobalDiagnostics,
        plan: SumiProtectionRulePlan,
        url: URL?,
        currentTabDiagnostics: SumiProtectionCurrentTabDiagnostics?,
        targetDescription: String,
        requestingURL: URL?,
        contentBlockingServiceGenerationId: UInt64,
        bundleLookupDuration: TimeInterval?,
        startupSnapshot: SumiProtectionStartupRestoreDiagnosticsSnapshot?,
        timestamp: Date = Date()
    ) -> String {
        let targetURLString = url?.absoluteString ?? "nil"
        let actualAttachedIdentifiers = currentTabDiagnostics?.actualAttachedRuleListIdentifiers ?? []
        let missingIdentifiers = currentTabDiagnostics?.missingRuleListIdentifiers ?? []
        let lookupSucceededIdentifiers = currentTabDiagnostics?.lookupSucceededIdentifiers ?? []
        let lookupFailedIdentifiers = currentTabDiagnostics?.lookupFailedIdentifiers ?? []
        let addedIdentifiers = currentTabDiagnostics?.addedToUserContentControllerIdentifiers ?? []
        let unexpectedOldIdentifiers = currentTabDiagnostics?.unexpectedOldRuleListIdentifiers ?? []
        let reloadRequired = currentTabDiagnostics?.reloadRequired ?? false
        let reloadRequiredReason = currentTabDiagnostics?.reloadRequiredReason
        let didManualReloadRebuildWebView = currentTabDiagnostics?.didManualReloadRebuildWebView ?? false
        let appliedAfterManualReload = currentTabDiagnostics?.appliedAfterManualReload ?? false
        var lines = [
            "Sumi Adblock & Protection Copy Diagnostics",
            "timestamp=\(iso8601Timestamp(timestamp))",
            "",
            "Global protection state",
            "protectionLevel=\(global.selectedProtectionLevel.rawValue)",
            "appliedProtectionLevel=\(global.appliedProtectionLevel.rawValue)",
            "restartRequired=\(global.browserRestartRequired)",
            "browserRestartRequired=\(global.browserRestartRequired)",
            "generationSource=\(global.generationSource?.rawValue ?? "nil")",
            "nativeRuleBundleId=\(global.nativeRuleBundleId ?? "nil")",
            "bundleProfileId=\(global.bundleProfileId ?? "nil")",
            "activeGenerationId=\(global.activeGenerationId ?? "nil")",
            "remoteReleaseVersion=\(global.remoteReleaseVersion ?? "nil")",
            "remoteManifestSignatureRequired=\(global.remoteManifestSignatureRequired)",
            "remoteManifestSignatureVerified=\(global.remoteManifestSignatureVerified.map(String.init) ?? "nil")",
            "signingKeyId=\(global.remoteSigningKeyId ?? "nil")",
            "signingKeyVersion=\(global.remoteSigningKeyVersion.map(String.init) ?? "nil")",
            "lastRemoteUpdateError=\(global.lastRemoteUpdateError ?? "nil")",
            "lastSignatureError=\(global.lastSignatureError ?? "nil")",
            "downgradeRejected=\(global.downgradeRejected)",
            "requiredBundleProfileId=\(global.requiredBundleProfileId ?? "nil")",
            "preparedBundleAvailable=\(global.preparedBundleAvailable)",
            "preparedBundleSource=\(global.preparedBundleSource?.rawValue ?? "nil")",
            "searchedBundlePaths=\(renderSearchedBundlePaths(global.searchedBundlePaths))",
            "applyNeeded=\(global.applyNeeded)",
            "lastApplySummary=\(global.lastApplySummary ?? "nil")",
            "lastApplyError=\(global.lastApplyError ?? "nil")",
            "globalGroupsAvailable=\(global.globalGroupsAvailable.map(\.rawValue).joined(separator: ","))",
            "trackingNetworkSourceLicenseSummary=\(global.groupSourceDiagnostics[.trackingNetwork] ?? "nil")",
            "adblockAdsPrivacyNetworkSourceSummary=\(global.groupSourceDiagnostics[.adblockAdsPrivacyNetwork] ?? "nil")",
            "trackingSourceAvailable=\(global.trackingSourceAvailable)",
            "adblockBundleAvailable=\(global.adblockBundleAvailable)",
            "strictOffActive=\(global.strictOffActive)",
            "",
            "Target page plan",
            "targetSource=\(targetDescription)",
            "targetURL=\(targetURLString)",
            "requestingURL=\(requestingURL?.absoluteString ?? "nil")",
            "eligible=\(plan.ineligibleSurfaceReason == nil)",
            "ineligibleSurfaceReason=\(plan.ineligibleSurfaceReason ?? "nil")",
            "requestedProtectionLevelForPage=\(plan.requestedLevel.rawValue)",
            "effectiveProtectionLevel=\(plan.effectiveLevel.rawValue)",
            "activeGroups=\(plan.activeGroups.map(\.rawValue).joined(separator: ","))",
            "inactiveGroups=\(plan.inactiveGroups.map(\.rawValue).joined(separator: ","))",
            "desiredGroups=\(plan.requestedLevel.requestedGroups.map(\.rawValue).joined(separator: ","))",
            "trackingGroupActive=\(plan.trackingGroupActive)",
            "adblockGroupActive=\(plan.adblockGroupActive)",
            "ruleCountsByGroup=\(SumiProtectionCurrentTabDiagnostics.renderCounts(plan.ruleCountsByGroup))",
            "shardCountsByGroup=\(SumiProtectionCurrentTabDiagnostics.renderCounts(plan.shardCountsByGroup))",
            "expectedRuleListIdentifiers=\(plan.expectedRuleListIdentifiers.joined(separator: ","))",
            "lookupSucceededIdentifiers=\(lookupSucceededIdentifiers.joined(separator: ","))",
            "lookupFailedIdentifiers=\(lookupFailedIdentifiers.joined(separator: ","))",
            "addedToUserContentControllerIdentifiers=\(addedIdentifiers.joined(separator: ","))",
            "actualAttachedRuleListIdentifiers=\(actualAttachedIdentifiers.joined(separator: ","))",
            "missingIdentifiers=\(missingIdentifiers.joined(separator: ","))",
            "missingAfterAttachmentIdentifiers=\(missingIdentifiers.joined(separator: ","))",
            "unexpectedOldIdentifiers=\(unexpectedOldIdentifiers.joined(separator: ","))",
            "ruleListIdentifierSamplesByGroup=\(SumiProtectionCurrentTabDiagnostics.renderIdentifierSamples(ruleListIdentifierSamplesByGroup(for: plan)))",
            "reloadRequired=\(reloadRequired)",
            "reloadRequiredReason=\(reloadRequiredReason ?? "nil")",
            "manualReloadRebuiltWebView=\(didManualReloadRebuildWebView)",
            "manualReloadMatchedDesiredState=\(appliedAfterManualReload)",
            "contentBlockingServiceGenerationId=\(contentBlockingServiceGenerationId)",
            "planComputeDuration=\(currentTabDiagnostics.map { SumiProtectionCurrentTabDiagnostics.renderDuration($0.planComputeDuration) } ?? "nil")",
            "bundleLookupDuration=\(SumiProtectionCurrentTabDiagnostics.renderOptionalDuration(bundleLookupDuration))",
            "ruleListLookupDuration=\(SumiProtectionCurrentTabDiagnostics.renderOptionalDuration(currentTabDiagnostics?.ruleListLookupDuration))",
            "tabAttachmentDuration=\(SumiProtectionCurrentTabDiagnostics.renderOptionalDuration(currentTabDiagnostics?.tabAttachmentDuration))",
            "webViewRebuildDuration=\(SumiProtectionCurrentTabDiagnostics.renderOptionalDuration(currentTabDiagnostics?.webViewRebuildDuration))",
            "urlHubSummaryDuration=\(SumiProtectionCurrentTabDiagnostics.renderOptionalDuration(currentTabDiagnostics?.urlHubSummaryDuration))",
            "dedupeSummary=\(plan.dedupeSummary.reportLine)",
            "overlapSummary=\(plan.overlapSummary.reportLine)",
            "planningErrors=\(plan.planningErrors.joined(separator: " | "))",
            "currentTabDiagnosticsAvailable=\(currentTabDiagnostics != nil)",
        ]
        if let startupSnapshot {
            lines.append("")
            lines.append("Startup restore diagnostics")
            lines.append(contentsOf: startupSnapshot.reportLines)
        }
        if currentTabDiagnostics == nil {
            lines.append("Sumi Adblock & Protection current-tab diagnostics\ncurrentTab=nil")
        }
        return lines.joined(separator: "\n")
    }
#endif

    private static func groupSourceDiagnostics(
        from manifest: AdblockCompiledGenerationManifest?
    ) -> [SumiProtectionGroupKind: String] {
        guard let manifest else { return [:] }
        return (manifest.nativeLogicalGroups ?? []).reduce(into: [:]) { result, group in
            result[group.id] = group.reportLine
        }
    }

    private static func ruleListIdentifierSamplesByGroup(
        for plan: SumiProtectionRulePlan
    ) -> [SumiProtectionGroupKind: [String]] {
        var samples = [SumiProtectionGroupKind: [String]]()
        for group in plan.activeGroups {
            let identifiers: [String]
            switch group {
            case .trackingNetwork:
                identifiers = plan.expectedRuleListIdentifiers.filter {
                    !$0.hasPrefix("sumi.adblock.")
                }
            case .adblockAdsPrivacyNetwork:
                identifiers = plan.expectedRuleListIdentifiers.filter {
                    $0.hasPrefix("sumi.adblock.network.")
                }
            case .cosmetic:
                identifiers = []
            }
            samples[group] = identifiers
                .prefix(4)
                .map(redactedRuleListIdentifier)
        }
        return samples
    }

    private static func redactedRuleListIdentifier(_ identifier: String) -> String {
        let parts = identifier.split(separator: ".").map(String.init)
        guard parts.count > 6 else { return identifier }
        return (Array(parts.prefix(4)) + ["..."] + Array(parts.suffix(2))).joined(separator: ".")
    }

    private static func isSumiOwnedProtectionIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix("sumi.adblock.")
            || identifier.hasPrefix("sumi.tracking.")
    }

    private static func currentProcessResidentMemoryBytes() -> UInt64? {
#if DEBUG
        return AdblockProcessMemorySampler.residentMemoryBytes()
#else
        return nil
#endif
    }

    private static func renderSearchedBundlePaths(
        _ paths: [SumiPreparedAdblockBundleSearchPath]
    ) -> String {
        paths.map { path in
            "\(path.source.rawValue):path=\(path.path);exists=\(path.exists);rejected=\(path.rejectionReason ?? "nil")"
        }.joined(separator: " | ")
    }

    private static func iso8601Timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
