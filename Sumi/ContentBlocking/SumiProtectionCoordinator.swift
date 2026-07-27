import Combine
import Foundation
import SumiDomain
import OSLog

@MainActor
final class SumiProtectionCoordinator {
    let settings: SumiProtectionSettings
    private let adBlockingModule: SumiAdBlockingModule
    private let attachmentService: ProtectionAttachmentService
    private let bundleLifecycle: SumiProtectionBundleLifecycle
    #if DEBUG
        private let startupDiagnostics: any SumiProtectionStartupRestoreDiagnosticsRecording
    #endif

    var bundleUpdateStatusStore: SumiProtectionBundleUpdateStatusStore {
        bundleLifecycle.statusStore
    }

    private(set) var lastApplySummary: String?
    private(set) var lastApplyError: String?
    private var runtimeAppliedLevel: SumiProtectionLevel

    init(
        settings: SumiProtectionSettings,
        adBlockingModule: SumiAdBlockingModule,
        siteNormalizer: SumiProtectionSiteNormalizer = SumiProtectionSiteNormalizer(),
        bundleRemoteUpdater: any SumiProtectionBundleRemoteUpdating = SumiProtectionBundleRemoteUpdater(),
        bundleUpdateStatusStore: SumiProtectionBundleUpdateStatusStore,
        compiledRuleListCatalog: SumiCompiledContentRuleListCataloging,
        startupDiagnostics: (any SumiProtectionStartupRestoreDiagnosticsRecording)? = nil
    ) {
        self.settings = settings
        self.adBlockingModule = adBlockingModule
        #if DEBUG
            let startupDiagnostics = startupDiagnostics ?? SumiProtectionStartupRestoreDiagnosticsDefaults.recorder
            self.startupDiagnostics = startupDiagnostics
        #else
            _ = startupDiagnostics
        #endif
        #if DEBUG
        self.attachmentService = ProtectionAttachmentService(
            ruleProvider: adBlockingModule,
            siteNormalizer: siteNormalizer,
            startupDiagnostics: startupDiagnostics,
            compiledRuleListCatalog: compiledRuleListCatalog
        )
        #else
        self.attachmentService = ProtectionAttachmentService(
            ruleProvider: adBlockingModule,
            siteNormalizer: siteNormalizer,
            compiledRuleListCatalog: compiledRuleListCatalog
        )
        #endif
        self.bundleLifecycle = SumiProtectionBundleLifecycle(
            preparedBundleManager: adBlockingModule,
            remoteUpdater: bundleRemoteUpdater,
            statusStore: bundleUpdateStatusStore
        )
        self.runtimeAppliedLevel = settings.appliedLevel
        attachmentService.syncRuntime(for: runtimeAppliedLevel)
    }

    func setLevel(_ level: SumiProtectionLevel) {
        settings.setLevel(level)
    }

    var applyNeeded: Bool {
        attachmentService.applyNeeded(
            selectedLevel: settings.level,
            appliedLevel: settings.appliedLevel,
            browserRestartRequired: settings.browserRestartRequired
        )
    }

    func applySelectedLevel() async throws -> SumiProtectionApplyOutcome {
        let selectedLevel = settings.level
        let previousAppliedLevel = settings.appliedLevel
        let wasApplyNeeded = applyNeeded
        attachmentService.syncRuntime(for: selectedLevel)

        do {
            var installedBundleProfileId: String?
            if let requiredBundleProfileId = selectedLevel.preferredBundleProfileId {
                installedBundleProfileId = try await bundleLifecycle.ensurePreparedBundleInstalled(
                    profileId: requiredBundleProfileId
                )
                let readinessPlan = attachmentService.globalAttachmentPlan(
                    for: selectedLevel,
                    includeExpensiveDiagnostics: false,
                    loadRuleDefinitions: false
                )
                try attachmentService.validateRequiredGroupsReady(in: readinessPlan)
            } else {
                clearPreparedBundleLookupDiagnostics()
            }

            settings.setAppliedLevel(selectedLevel)
            if wasApplyNeeded || selectedLevel != previousAppliedLevel {
                settings.setBrowserRestartRequired(true)
            }
            runtimeAppliedLevel = selectedLevel
            attachmentService.syncRuntime(for: runtimeAppliedLevel)
            let summary = applySummary(
                selectedLevel: selectedLevel,
                installedBundleProfileId: installedBundleProfileId
            )
            lastApplySummary = summary
            lastApplyError = nil
            return SumiProtectionApplyOutcome(
                selectedLevel: selectedLevel,
                previousAppliedLevel: previousAppliedLevel,
                appliedLevel: settings.appliedLevel,
                installedBundleProfileId: installedBundleProfileId,
                summary: summary
            )
        } catch {
            attachmentService.syncRuntime(for: runtimeAppliedLevel)
            let message: String
            if let applyError = error as? SumiProtectionApplyError {
                message = applyError.localizedDescription
            } else {
                message = "Could not apply \(selectedLevel.displayTitle): \(error.localizedDescription)"
            }
            settings.setAppliedLevel(previousAppliedLevel)
            lastApplySummary = nil
            lastApplyError = message
            if selectedLevel == .off {
                attachmentService.clearCachedAttachmentService()
            }
            throw SumiProtectionApplyError.applyFailed(message)
        }
    }

    func updatePreparedBundlesManually() async throws -> SumiProtectionBundleManualUpdateOutcome {
        let appliedLevel = settings.appliedLevel
        attachmentService.syncRuntime(for: appliedLevel)
        return try await bundleLifecycle.updatePreparedBundlesManually(
            appliedLevel: appliedLevel,
            currentBrowserRestartRequired: settings.browserRestartRequired
        ) { summary in
            try await attachmentService.prepareCachedAttachmentService(for: appliedLevel)
            settings.setBrowserRestartRequired(true)
            lastApplySummary = summary
            lastApplyError = nil
        }
    }

    @discardableResult
    func restoreAppliedLevelForStartup() async throws -> AdblockCompiledGenerationManifest? {
        let appliedLevel = settings.appliedLevel
#if DEBUG
        let startupDiagnosticsToken = startupDiagnostics.begin(
            appliedLevel: appliedLevel,
            trackedGenerationId: nil
        )
        defer {
            let snapshot = startupDiagnostics.finish(startupDiagnosticsToken)
            Logger.sumi(category: "ProtectionStartupRestore").debug("\(snapshot.developerReport, privacy: .public)")
        }
#endif
        runtimeAppliedLevel = appliedLevel
        attachmentService.syncRuntime(for: appliedLevel)
        guard let requiredBundleProfileId = appliedLevel.preferredBundleProfileId else {
            clearPreparedBundleLookupDiagnostics()
            try await attachmentService.prepareCachedAttachmentService(for: appliedLevel)
            settings.setBrowserRestartRequired(false)
            lastApplyError = nil
            return nil
        }

        do {
            let manifest = try await bundleLifecycle.restorePreparedBundleForStartup(
                profileId: requiredBundleProfileId
            )
            try await attachmentService.prepareCachedAttachmentService(for: appliedLevel)
            settings.setBrowserRestartRequired(false)
            lastApplySummary = "Restored \(appliedLevel.displayTitle) using prepared bundle \(requiredBundleProfileId)."
            lastApplyError = nil
            return manifest
        } catch {
            let message: String
            if let applyError = error as? SumiProtectionApplyError {
                message = applyError.localizedDescription
            } else {
                message = "Could not restore \(appliedLevel.displayTitle) at startup: \(error.localizedDescription)"
            }
            lastApplySummary = nil
            lastApplyError = message
            throw SumiProtectionApplyError.applyFailed(message)
        }
    }

    func normalTabDecision(
        for url: URL?,
        profileId: UUID?
    ) -> SumiProtectionNormalTabDecision {
        attachmentService.normalTabDecision(
            for: url,
            profileId: profileId,
            requestedLevel: runtimeAppliedLevel
        )
    }

    func desiredAttachmentState(for url: URL?) -> SumiProtectionAttachmentState {
        attachmentService.desiredAttachmentState(
            for: url,
            requestedLevel: runtimeAppliedLevel
        )
    }

    func rulePlan(
        for url: URL?,
        profileId: UUID?,
        includeExpensiveDiagnostics: Bool = false
    ) -> SumiProtectionRulePlan {
        attachmentService.rulePlan(
            for: url,
            profileId: profileId,
            requestedLevel: runtimeAppliedLevel,
            includeExpensiveDiagnostics: includeExpensiveDiagnostics
        )
    }

    func cachedRulePlan(
        for url: URL?,
        profileId: UUID?
    ) -> SumiProtectionRulePlan {
        attachmentService.cachedRulePlan(
            for: url,
            profileId: profileId,
            requestedLevel: runtimeAppliedLevel
        )
    }

    private func clearPreparedBundleLookupDiagnostics() {
        bundleLifecycle.clearPreparedBundleLookupDiagnostics()
    }

    func currentTabDiagnostics(
        for url: URL?,
        appliedState: SumiProtectionAttachmentState?,
        reloadRequired: Bool,
        reloadRequiredReason: String? = nil,
        didManualReloadRebuildWebView: Bool = false,
        appliedAfterManualReload: Bool = false,
        actualAttachedRuleListIdentifiers: [String]? = nil,
        contentBlockingAssetSummary: SumiNormalTabContentBlockingAssetSummary? = nil,
        webViewRebuildDuration: TimeInterval? = nil,
        urlHubSummaryDuration: TimeInterval? = nil
    ) -> SumiProtectionCurrentTabDiagnostics {
        let planStart = Date()
        let plan = rulePlan(
            for: url,
            profileId: nil,
            includeExpensiveDiagnostics: true
        )
        let planComputeDuration = Date().timeIntervalSince(planStart)
        return SumiProtectionDiagnosticsReporter.currentTabDiagnostics(
            for: url,
            appliedState: appliedState,
            reloadRequired: reloadRequired,
            reloadRequiredReason: reloadRequiredReason,
            didManualReloadRebuildWebView: didManualReloadRebuildWebView,
            appliedAfterManualReload: appliedAfterManualReload,
            actualAttachedRuleListIdentifiers: actualAttachedRuleListIdentifiers,
            contentBlockingAssetSummary: contentBlockingAssetSummary,
            webViewRebuildDuration: webViewRebuildDuration,
            urlHubSummaryDuration: urlHubSummaryDuration,
            plan: plan,
            planComputeDuration: planComputeDuration,
            contentBlockingServiceGenerationId: attachmentService.contentBlockingServiceGenerationId,
            bundleLookupDuration: bundleLifecycle.lastBundleLookupDuration
        )
    }

    func globalDiagnostics() -> SumiProtectionGlobalDiagnostics {
        let selectedLevel = settings.level
        let appliedLevel = settings.appliedLevel
        let manifest = selectedLevel == .off && appliedLevel == .off
            ? nil
            : adBlockingModule.activeManifestIfLoaded()
        let activePreparedProfileId = manifest.flatMap {
            attachmentService.preparedBundleProfileId(in: $0)
        }
        let requiredBundleProfileId = selectedLevel.preferredBundleProfileId
        let bundleDiagnostics = bundleLifecycle.diagnostics(
            manifest: manifest,
            requiredBundleProfileId: requiredBundleProfileId,
            activePreparedBundleProfileId: activePreparedProfileId
        )
        let trackingSourceAvailable = attachmentService.trackingSourceAvailable(
            manifest: manifest
        )
        let availableGroups = attachmentService.globallyAvailableGroups(
            manifest: manifest,
            trackingSourceAvailable: trackingSourceAvailable
        )
        let adblockBundleAvailable = requiredBundleProfileId.map {
            activePreparedProfileId == $0
        } ?? true

        return SumiProtectionDiagnosticsReporter.globalDiagnostics(
            selectedLevel: selectedLevel,
            appliedLevel: appliedLevel,
            browserRestartRequired: settings.browserRestartRequired,
            manifest: manifest,
            bundleDiagnostics: bundleDiagnostics,
            requiredBundleProfileId: requiredBundleProfileId,
            applyNeeded: applyNeeded,
            lastApplySummary: lastApplySummary,
            lastApplyError: lastApplyError,
            availableGroups: availableGroups,
            trackingSourceAvailable: trackingSourceAvailable,
            adblockBundleAvailable: adblockBundleAvailable,
            strictOffActive: selectedLevel == .off
                && appliedLevel == .off
                && attachmentService.isCacheEmpty
                && !adBlockingModule.isEnabled
        )
    }

#if DEBUG
    func copyDiagnosticsReport(
        for url: URL?,
        currentTabDiagnostics: SumiProtectionCurrentTabDiagnostics?,
        targetDescription: String = "current tab",
        requestingURL: URL? = nil
    ) -> String {
        SumiProtectionDiagnosticsReporter.copyDiagnosticsReport(
            global: globalDiagnostics(),
            plan: rulePlan(
                for: url,
                profileId: nil,
                includeExpensiveDiagnostics: true
            ),
            url: url,
            currentTabDiagnostics: currentTabDiagnostics,
            targetDescription: targetDescription,
            requestingURL: requestingURL,
            contentBlockingServiceGenerationId: attachmentService.contentBlockingServiceGenerationId,
            bundleLookupDuration: bundleLifecycle.lastBundleLookupDuration,
            startupSnapshot: startupDiagnostics.latestSnapshot
        )
    }
#endif

    func setSiteOverride(_ override: SumiAdblockSiteOverride, for url: URL?) {
        adBlockingModule.setSiteOverride(override, for: url)
    }

    func sitePolicyChangesPublisher() -> AnyPublisher<Void, Never> {
        adBlockingModule.sitePolicyChangesPublisher()
    }

    func surfaceEligibility(for url: URL?) -> SumiAdblockSurfaceEligibility {
        attachmentService.surfaceEligibility(for: url)
    }

    private func applySummary(
        selectedLevel: SumiProtectionLevel,
        installedBundleProfileId: String?
    ) -> String {
        if let installedBundleProfileId {
            return "Saved \(selectedLevel.displayTitle) using prepared bundle \(installedBundleProfileId). Restart Sumi to apply global protection changes."
        }
        return "Saved \(selectedLevel.displayTitle). Restart Sumi to apply global protection changes."
    }
}
