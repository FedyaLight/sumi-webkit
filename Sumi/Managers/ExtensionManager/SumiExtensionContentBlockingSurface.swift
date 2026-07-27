import Foundation

@MainActor
final class SumiExtensionContentBlockingSurface {
    private let database: SumiDatabase?
    private let compiledRuleListCatalog: SumiCompiledContentRuleListCataloging
    private let lifetime: SumiExtensionManagerLifetime
    private var owner: SumiSafariContentBlockerAPIOwner?

    init(
        database: SumiDatabase?,
        compiledRuleListCatalog: SumiCompiledContentRuleListCataloging,
        moduleRegistry: SumiModuleRegistry,
        lifetime: SumiExtensionManagerLifetime
    ) {
        self.database = database
        self.compiledRuleListCatalog = compiledRuleListCatalog
        self.lifetime = lifetime
    }

    func installedContentBlockers() -> [InstalledSafariContentBlockerRecord] {
        resolvedOwner().installedContentBlockers()
    }

    func contentBlockerRecord(forBundleIdentifier id: String) -> InstalledSafariContentBlockerRecord? {
        resolvedOwner().contentBlockerRecord(forBundleIdentifier: id)
    }

    func enableContentBlocker(from candidate: DiscoveredSafariExtensionCandidate) async throws -> InstalledSafariContentBlockerRecord {
        try await resolvedOwner().enableContentBlocker(from: candidate)
    }

    func setContentBlockerEnabled(_ enabled: Bool, bundleIdentifier: String) async throws -> InstalledSafariContentBlockerRecord? {
        try await resolvedOwner().setContentBlockerEnabled(
            enabled,
            bundleIdentifier: bundleIdentifier
        )
    }

    func enabledServices(for url: URL?, profileID: UUID?) -> [SumiContentBlockingService] {
        resolvedOwner().enabledContentBlockingServices(for: url, profileId: profileID)
    }

    func attachmentState(for url: URL?) -> SumiSafariContentBlockerAttachmentState {
        resolvedOwner().attachmentState(for: url)
    }

    func siteState(for url: URL?) -> SumiSafariContentBlockerSiteState {
        resolvedOwner().siteState(for: url)
    }

    func attachedRuleListIdentifiers() -> [String] {
        resolvedOwner().attachedRuleListIdentifiers()
    }

    func setSiteOverride(_ override: SumiSafariContentBlockerSiteOverride, for url: URL?) {
        resolvedOwner().setSiteOverride(override, for: url)
    }

    func markReloadRequiredForLiveTabs() {
        lifetime.liveTabs.forEach {
            $0.updateSafariContentBlockerReloadRequirementForCurrentSite()
        }
    }

    func clearRuntimeIfMaterialized() {
        owner?.clearRuntime()
    }

    private func resolvedOwner() -> SumiSafariContentBlockerAPIOwner {
        if let owner { return owner }
        let owner = SumiSafariContentBlockerAPIOwner(
            database: database,
            compiledRuleListCatalog: compiledRuleListCatalog,
            isModuleEnabled: { [weak lifetime] in lifetime?.isEnabled ?? false },
            liveTabs: { [weak lifetime] in lifetime?.liveTabs ?? [] }
        )
        self.owner = owner
        return owner
    }

    #if DEBUG
        func drainRuntimeForTests(cancel: Bool = false) async {
            await owner?.drainRuntimeForTests(cancel: cancel)
        }
    #endif
}

@MainActor
extension SumiExtensionsModule {
    func installedSafariContentBlockers() -> [InstalledSafariContentBlockerRecord] {
        contentBlocking.installedContentBlockers()
    }

    func safariContentBlockerRecord(
        forBundleIdentifier bundleIdentifier: String
    ) -> InstalledSafariContentBlockerRecord? {
        contentBlocking.contentBlockerRecord(forBundleIdentifier: bundleIdentifier)
    }

    func enableSafariContentBlocker(
        from candidate: DiscoveredSafariExtensionCandidate
    ) async throws -> InstalledSafariContentBlockerRecord {
        try await contentBlocking.enableContentBlocker(from: candidate)
    }

    func setSafariContentBlockerEnabled(
        _ enabled: Bool,
        bundleIdentifier: String
    ) async throws -> InstalledSafariContentBlockerRecord? {
        try await contentBlocking.setContentBlockerEnabled(
            enabled,
            bundleIdentifier: bundleIdentifier
        )
    }

    func enabledSafariContentBlockingServices(
        for url: URL?,
        profileId: UUID?
    ) -> [SumiContentBlockingService] {
        contentBlocking.enabledServices(for: url, profileID: profileId)
    }

    func safariContentBlockerAttachmentState(
        for url: URL?
    ) -> SumiSafariContentBlockerAttachmentState {
        contentBlocking.attachmentState(for: url)
    }

    func safariContentBlockerSiteState(
        for url: URL?
    ) -> SumiSafariContentBlockerSiteState {
        contentBlocking.siteState(for: url)
    }

    func safariContentBlockerAttachedRuleListIdentifiers() -> [String] {
        contentBlocking.attachedRuleListIdentifiers()
    }

    func setSafariContentBlockerSiteOverride(
        _ override: SumiSafariContentBlockerSiteOverride,
        for url: URL?
    ) {
        contentBlocking.setSiteOverride(override, for: url)
    }

    #if DEBUG
        func drainSafariContentBlockerRuntimeForTests(cancel: Bool = false) async {
            await contentBlocking.drainRuntimeForTests(cancel: cancel)
        }
    #endif
}
