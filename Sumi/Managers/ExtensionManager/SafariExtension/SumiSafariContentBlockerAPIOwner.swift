import Foundation
import SwiftData
import WebKit

/// Thin façade over `SafariContentBlockerRuntimeOwner` that also marks live tabs
/// when content-blocker policy changes require a reload.
@MainActor
final class SumiSafariContentBlockerAPIOwner {
    typealias LiveTabsProvider = @MainActor () -> [Tab]

    private let runtimeOwner: SafariContentBlockerRuntimeOwner
    private let liveTabs: LiveTabsProvider

    init(
        runtimeOwner: SafariContentBlockerRuntimeOwner,
        liveTabs: @escaping LiveTabsProvider
    ) {
        self.runtimeOwner = runtimeOwner
        self.liveTabs = liveTabs
    }

    convenience init(
        context: ModelContext?,
        defaults: UserDefaults,
        isModuleEnabled: @escaping @MainActor () -> Bool,
        liveTabs: @escaping LiveTabsProvider
    ) {
        self.init(
            runtimeOwner: SafariContentBlockerRuntimeOwner(
                context: context,
                defaults: defaults,
                isModuleEnabled: isModuleEnabled
            ),
            liveTabs: liveTabs
        )
    }

    var runtime: SafariContentBlockerRuntimeOwner {
        runtimeOwner
    }

    func clearRuntime() {
        runtimeOwner.clearRuntime()
    }

    func installedContentBlockers() -> [InstalledSafariContentBlockerRecord] {
        runtimeOwner.installedContentBlockers()
    }

    func contentBlockerRecord(
        forBundleIdentifier bundleIdentifier: String
    ) -> InstalledSafariContentBlockerRecord? {
        runtimeOwner.contentBlockerRecord(forBundleIdentifier: bundleIdentifier)
    }

    func enableContentBlocker(
        from candidate: DiscoveredSafariExtensionCandidate
    ) async throws -> InstalledSafariContentBlockerRecord {
        let record = try await runtimeOwner.enableContentBlocker(from: candidate)
        markReloadRequiredForLiveTabs()
        return record
    }

    func setContentBlockerEnabled(
        _ enabled: Bool,
        bundleIdentifier: String
    ) async throws -> InstalledSafariContentBlockerRecord? {
        let record = try await runtimeOwner.setContentBlockerEnabled(
            enabled,
            bundleIdentifier: bundleIdentifier
        )
        markReloadRequiredForLiveTabs()
        return record
    }

    func enabledContentBlockingServices(
        for url: URL?,
        profileId: UUID?
    ) -> [SumiContentBlockingService] {
        runtimeOwner.enabledContentBlockingServices(for: url, profileId: profileId)
    }

    func attachmentState(for url: URL?) -> SumiSafariContentBlockerAttachmentState {
        runtimeOwner.attachmentState(for: url)
    }

    func siteState(for url: URL?) -> SumiSafariContentBlockerSiteState {
        runtimeOwner.siteState(for: url)
    }

    func attachedRuleListIdentifiers() -> [String] {
        runtimeOwner.attachedRuleListIdentifiers()
    }

    func setSiteOverride(
        _ override: SumiSafariContentBlockerSiteOverride,
        for url: URL?
    ) {
        runtimeOwner.setSiteOverride(override, for: url)
        markReloadRequiredForLiveTabs(afterChangingPolicyFor: url)
    }

    func markReloadRequiredForLiveTabs() {
        liveTabs().forEach {
            $0.updateSafariContentBlockerReloadRequirementForCurrentSite()
        }
    }

    private func markReloadRequiredForLiveTabs(afterChangingPolicyFor url: URL?) {
        liveTabs().forEach {
            $0.markSafariContentBlockerReloadRequiredIfNeeded(
                afterChangingPolicyFor: url
            )
        }
    }

    #if DEBUG
    func drainRuntimeForTests(cancel: Bool = false) async {
        await runtimeOwner.drainRuntimeForTests(cancel: cancel)
    }
    #endif
}
