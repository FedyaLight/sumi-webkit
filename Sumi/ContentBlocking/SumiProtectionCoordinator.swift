import Combine
import Foundation
import SumiDomain

@MainActor
final class SumiProtectionCoordinator {
    let settings: SumiProtectionSettings
    let filterListCatalog: SumiFilterListCatalog?
    private let adBlockingModule: SumiAdBlockingModule
    private let attachmentService: ProtectionAttachmentService
    private let selectedFilterBundleBuilder: SumiSelectedFilterBundleBuilder
    private var legacyMigration: SumiAdblockLegacyMigration?
    private(set) var lastApplyError: String?
    private var runtimeAppliedLevel: SumiProtectionLevel

    init(
        settings: SumiProtectionSettings,
        adBlockingModule: SumiAdBlockingModule,
        siteNormalizer: SumiProtectionSiteNormalizer = SumiProtectionSiteNormalizer(),
        compiledRuleListCatalog: SumiCompiledContentRuleListCataloging,
        selectedFilterBundleBuilder: SumiSelectedFilterBundleBuilder =
            SumiSelectedFilterBundleBuilder(),
        legacyMigration: SumiAdblockLegacyMigration? = nil
    ) {
        self.settings = settings
        self.adBlockingModule = adBlockingModule
        self.filterListCatalog = adBlockingModule.filterListCatalog
        self.selectedFilterBundleBuilder = selectedFilterBundleBuilder
        self.legacyMigration = legacyMigration
        self.attachmentService = ProtectionAttachmentService(
            ruleProvider: adBlockingModule,
            siteNormalizer: siteNormalizer,
            compiledRuleListCatalog: compiledRuleListCatalog
        )
        self.runtimeAppliedLevel = settings.appliedLevel
        attachmentService.syncRuntime(for: runtimeAppliedLevel)
    }

    func setLevel(_ level: SumiProtectionLevel) {
        settings.setLevel(level)
    }

    var applyNeeded: Bool {
        let levelApplyNeeded = attachmentService.applyNeeded(
            selectedLevel: settings.level,
            appliedLevel: settings.appliedLevel
        )
        let listApplyNeeded = settings.level == .adblock
            && filterListCatalog.map {
                settings.filterListSelectionApplyNeeded(in: $0)
            } == true
        return levelApplyNeeded || listApplyNeeded
    }

    func setFilterList(_ id: String, enabled: Bool) {
        guard let filterListCatalog else { return }
        settings.setFilterList(
            id,
            enabled: enabled,
            catalog: filterListCatalog
        )
    }

    func resetFilterListsToDefaults() {
        settings.resetFilterListsToDefaults()
    }

    func applySelectedLevel() async throws {
        try await finishLegacyMigrationIfNeeded()
        let selectedLevel = settings.level
        let previousAppliedLevel = settings.appliedLevel
        attachmentService.syncRuntime(for: selectedLevel)

        do {
            if selectedLevel == .adblock {
                _ = try await installSelectedAdblockBundle()
                let readinessPlan = attachmentService.globalAttachmentPlan(
                    for: selectedLevel,
                    loadRuleDefinitions: false
                )
                try attachmentService.validateRequiredGroupsReady(in: readinessPlan)
                if let filterListCatalog {
                    settings.markFilterListSelectionApplied(
                        in: filterListCatalog
                    )
                }
            }

            settings.setAppliedLevel(selectedLevel)
            runtimeAppliedLevel = selectedLevel
            attachmentService.syncRuntime(for: runtimeAppliedLevel)
            lastApplyError = nil
        } catch {
            attachmentService.syncRuntime(for: runtimeAppliedLevel)
            let message: String
            if let applyError = error as? SumiProtectionApplyError {
                message = applyError.localizedDescription
            } else {
                message = "Could not apply \(selectedLevel.displayTitle): \(error.localizedDescription)"
            }
            settings.setAppliedLevel(previousAppliedLevel)
            lastApplyError = message
            if selectedLevel == .off {
                attachmentService.clearCachedAttachmentService()
            }
            throw SumiProtectionApplyError.applyFailed(message)
        }
    }

    @discardableResult
    func restoreAppliedLevelForStartup() async throws -> AdblockCompiledGenerationManifest? {
        try await finishLegacyMigrationIfNeeded()
        let appliedLevel = settings.appliedLevel
        runtimeAppliedLevel = appliedLevel
        attachmentService.syncRuntime(for: appliedLevel)
        guard appliedLevel == .adblock else {
            try await attachmentService.prepareCachedAttachmentService(for: appliedLevel)
            lastApplyError = nil
            return nil
        }

        do {
            guard let manifest = try await adBlockingModule
                .restoreLocalGenerationForStartup()
            else {
                throw SumiProtectionApplyError.requiredGenerationUnavailable(
                    profileId: SumiProtectionBundleProfile.adblock,
                    detail: "No locally generated filter cache is available. Apply Adblock once to create it."
                )
            }
            if let filterListCatalog {
                settings.setAppliedFilterListIDs(
                    Set(manifest.selectedFilterLists.map(\.id)),
                    catalog: filterListCatalog
                )
            }
            try await attachmentService.prepareCachedAttachmentService(for: appliedLevel)
            lastApplyError = nil
            return manifest
        } catch {
            let message: String
            if let applyError = error as? SumiProtectionApplyError {
                message = applyError.localizedDescription
            } else {
                message = "Could not restore \(appliedLevel.displayTitle) at startup: \(error.localizedDescription)"
            }
            lastApplyError = message
            throw SumiProtectionApplyError.applyFailed(message)
        }
    }

    func normalTabDecision(for url: URL?) -> SumiProtectionNormalTabDecision {
        attachmentService.normalTabDecision(
            for: url,
            requestedLevel: runtimeAppliedLevel
        )
    }

    func desiredAttachmentState(for url: URL?) -> SumiProtectionAttachmentState {
        attachmentService.desiredAttachmentState(
            for: url,
            requestedLevel: runtimeAppliedLevel
        )
    }

    func rulePlan(for url: URL?) -> SumiProtectionRulePlan {
        attachmentService.rulePlan(
            for: url,
            requestedLevel: runtimeAppliedLevel
        )
    }

    func cachedRulePlan(for url: URL?) -> SumiProtectionRulePlan {
        attachmentService.cachedRulePlan(
            for: url,
            requestedLevel: runtimeAppliedLevel
        )
    }

    private func installSelectedAdblockBundle() async throws -> AdblockCompiledGenerationManifest? {
        guard let filterListCatalog else {
            throw SumiProtectionApplyError.requiredGenerationUnavailable(
                profileId: SumiProtectionBundleProfile.adblock,
                detail: "The Adblock filter-list catalog is missing."
            )
        }
        let selectedIDs = settings.selectedFilterListIDs(
            in: filterListCatalog
        )
        let selectedLists = filterListCatalog.lists.filter {
            selectedIDs.contains($0.id)
        }
        let bundleURL = try await selectedFilterBundleBuilder.build(
            selectedLists: selectedLists
        )
        do {
            let manifest = try await adBlockingModule
                .installGeneratedRuleBundle(at: bundleURL)
            await selectedFilterBundleBuilder.discard(bundleURL)
            return manifest
        } catch {
            await selectedFilterBundleBuilder.discard(bundleURL)
            throw error
        }
    }

    private func finishLegacyMigrationIfNeeded() async throws {
        guard let legacyMigration else { return }
        try await legacyMigration.removeLegacyCompiledRulesIfNeeded()
        self.legacyMigration = nil
    }

    var lastSuccessfulUpdateDate: Date? {
        adBlockingModule.activeManifestIfLoaded()?.lastSuccessfulUpdateDate
    }

    func setSiteOverride(_ override: SumiAdblockSiteOverride, for url: URL?) {
        adBlockingModule.setSiteOverride(override, for: url)
    }

    func sitePolicyChangesPublisher() -> AnyPublisher<Void, Never> {
        adBlockingModule.sitePolicyChangesPublisher()
    }

    func surfaceEligibility(for url: URL?) -> SumiAdblockSurfaceEligibility {
        attachmentService.surfaceEligibility(for: url)
    }

}
