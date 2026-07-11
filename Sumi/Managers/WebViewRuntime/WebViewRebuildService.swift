import Foundation
import SumiWebRuntime

/// Owns rebuild admission and intent semantics above the atomic replacement
/// engine. A rebuild either uses the current intent, is deferred behind the
/// destructive-cleanup barrier, or enters the replacement transaction.
@MainActor
final class WebViewRebuildService {
    private let runtimeTabs: WebViewRuntimeTabRegistry
    private let websiteDataCleanup: WebsiteDataCleanupService
    private let engine: TabWebViewRebuildService

    init(
        runtimeTabs: WebViewRuntimeTabRegistry,
        websiteDataCleanup: WebsiteDataCleanupService,
        engine: TabWebViewRebuildService
    ) {
        self.runtimeTabs = runtimeTabs
        self.websiteDataCleanup = websiteDataCleanup
        self.engine = engine
    }

    @available(macOS 15.5, *)
    @discardableResult
    func rebuildLiveWebViews(
        for tab: Tab,
        preferredPrimaryWindowID: UUID? = nil,
        load url: URL? = nil,
        configuration: DeferredWebViewRebuildConfiguration = .normal,
        reason: String = "WebViewRebuildService.rebuildLiveWebViews",
        intentRevision: UInt64? = nil,
        rebuildKind: DeferredWebViewRebuildKind? = nil
    ) -> Bool {
        rebuildLiveWebViewsResult(
            for: tab,
            preferredPrimaryWindowID: preferredPrimaryWindowID,
            load: url,
            configuration: configuration,
            reason: reason,
            intentRevision: intentRevision,
            rebuildKind: rebuildKind
        ).didCommit
    }

    @available(macOS 15.5, *)
    func rebuildLiveWebViewsResult(
        for tab: Tab,
        preferredPrimaryWindowID: UUID? = nil,
        load url: URL? = nil,
        configuration: DeferredWebViewRebuildConfiguration = .normal,
        reason: String = "WebViewRebuildService.rebuildLiveWebViews",
        intentRevision existingIntentRevision: UInt64? = nil,
        rebuildKind existingRebuildKind: DeferredWebViewRebuildKind? = nil
    ) -> TabWebViewRebuildResult {
        runtimeTabs.bind(tab)
        let rebuildKind = existingRebuildKind
            ?? (url == nil ? .maintenance : .semanticNavigation)
        let targetURL = url ?? tab.url
        let intentRevision = existingIntentRevision
            ?? (rebuildKind == .semanticNavigation
                ? tab.beginWebViewRebuildIntent()
                : tab.currentWebViewRebuildIntentRevision)
        guard tab.isCurrentWebViewRebuildIntent(intentRevision) else {
            return .failed
        }

        let semanticRevision = tab.currentMainFrameNavigationIntent().revision
        if websiteDataCleanup.permitsInternalSubmission(
            tabID: tab.id,
            semanticRevision: semanticRevision
        ) == false,
        websiteDataCleanup.deferOrdinaryAdmission(
            profileID: tab.resolveProfile()?.id ?? tab.profileId,
            key: .webViewRebuild(tabID: tab.id),
            replay: { [weak self, weak tab] in
                guard let self, let tab else { return }
                _ = self.rebuildLiveWebViewsResult(
                    for: tab,
                    preferredPrimaryWindowID: preferredPrimaryWindowID,
                    load: url,
                    configuration: configuration,
                    reason: reason,
                    intentRevision: intentRevision,
                    rebuildKind: rebuildKind
                )
            }
        ) {
            return .deferred
        }

        return engine.rebuild(
            tab: tab,
            preferredPrimaryWindowID: preferredPrimaryWindowID,
            targetURL: targetURL,
            configuration: configuration,
            reason: reason,
            intentRevision: intentRevision,
            rebuildKind: rebuildKind
        )
    }
}
