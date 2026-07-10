import Foundation
import SumiWebRuntime
import WebKit

/// Coordinates one process-wide website-data mutation boundary. It owns the
/// admission gate, non-Tab participant registry, and live-document navigation
/// barrier; `WebViewCoordinator` only exposes narrow runtime ports.
@MainActor
final class WebsiteDataCleanupService: SumiDestructiveBrowsingDataCleanupPreparing {
    typealias RestoreSubmission = @MainActor (
        Tab,
        URL
    ) -> TabMainFrameReloadCommandOutcome

    private let admissionGate: WebsiteDataMutationGate
    private let participantRegistry: CleanupParticipantRegistry
    private let transaction: WebsiteDataCleanupTransaction

    init(
        browserRuntimeContext: @escaping @MainActor () -> WebViewCoordinatorBrowserRuntimeContext,
        liveWebViews: @escaping @MainActor (Tab) -> [WKWebView],
        waitForMutationPermission: @escaping @MainActor (WKWebView) async -> Bool,
        restoreSubmission: @escaping RestoreSubmission,
        abortOwnershipTransitions: @escaping @MainActor (Set<UUID>) -> Void,
        waitForOwnershipTransitions: @escaping @MainActor () async -> Bool,
        runtimeMutationGeneration: @escaping @MainActor () -> UInt64,
        runtimeTabs: @escaping @MainActor () -> [Tab]?
    ) {
        let admissionGate = WebsiteDataMutationGate()
        let participantRegistry = CleanupParticipantRegistry()
        self.admissionGate = admissionGate
        self.participantRegistry = participantRegistry
        transaction = WebsiteDataCleanupTransaction(
            browserRuntimeContext: browserRuntimeContext,
            liveWebViews: liveWebViews,
            waitForMutationPermission: waitForMutationPermission,
            restoreTab: { tab, targetURL in
                let outcome = admissionGate.withInternalSubmission {
                    restoreSubmission(tab, targetURL)
                }
                let semanticRevision = outcome == .failed
                    ? nil
                    : tab.currentMainFrameNavigationIntent().revision
                if let semanticRevision {
                    admissionGate.authorizeRestoreSubmission(
                        tabID: tab.id,
                        semanticRevision: semanticRevision
                    )
                }
                return .init(
                    outcome: outcome,
                    semanticRevision: semanticRevision
                )
            },
            mutationGate: admissionGate,
            waitForRetiringResidenceBarrier: waitForOwnershipTransitions,
            runtimeMutationGeneration: runtimeMutationGeneration,
            runtimeTabs: runtimeTabs,
            quiesceExternalParticipants: { profileIDs in
                await participantRegistry.quiesce(profileIDs: profileIDs)
            },
            abortOwnershipTransitions: abortOwnershipTransitions
        )
    }

    func registerExtensionRuntime(
        quiescer: @escaping CleanupParticipantRegistry.Quiescer
    ) {
        participantRegistry.register(.extensionRuntime, quiescer: quiescer)
    }

    func isSuppressingNavigation(
        on webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject
    ) -> Bool {
        transaction.isSuppressingNavigation(
            on: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime
        )
    }

    func navigationWillStart(
        on webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        targetURL: URL?,
        semanticRevision: UInt64?
    ) {
        transaction.navigationWillStart(
            on: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            targetURL: targetURL,
            semanticRevision: semanticRevision
        )
    }

    func navigationDidTerminate(
        on webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        succeeded: Bool
    ) {
        transaction.navigationDidTerminate(
            on: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            succeeded: succeeded
        )
    }

    func webViewDidLeaveRuntime(_ webView: WKWebView) {
        transaction.webViewDidLeaveRuntime(webView)
    }

    func webViewsDidLeaveRuntime(_ webViewIDs: [ObjectIdentifier]) {
        transaction.webViewsDidLeaveRuntime(webViewIDs)
    }

    func webContentProcessDidTerminate(on webView: WKWebView) -> Bool {
        transaction.webContentProcessDidTerminate(on: webView)
    }

    func performDestructiveDataCleanup(
        profileIDs: Set<UUID>,
        deletion: @escaping @MainActor () async -> Void
    ) async -> Bool {
        await transaction.performDestructiveDataCleanup(
            profileIDs: profileIDs,
            deletion: deletion
        )
    }

    func permitsInternalSubmission(tabID: UUID, semanticRevision: UInt64) -> Bool {
        admissionGate.permitsInternalSubmission(
            tabID: tabID,
            semanticRevision: semanticRevision
        )
    }

    func deferOrdinaryAdmission(
        profileID: UUID?,
        key: WebsiteDataMutationGate.DeferredAdmissionKey,
        replay: @escaping @MainActor () -> Void
    ) -> Bool {
        admissionGate.deferOrdinaryRuntimeAdmission(
            for: profileID,
            key: key,
            replay: replay
        )
    }

    @discardableResult
    func deferWebViewMaterialization(
        for tab: Tab,
        replay: @escaping @MainActor () -> Void
    ) -> Bool {
        let semanticRevision = tab.currentMainFrameNavigationIntent().revision
        guard permitsInternalSubmission(
            tabID: tab.id,
            semanticRevision: semanticRevision
        ) == false else {
            return false
        }
        return deferOrdinaryAdmission(
            profileID: tab.resolveProfile()?.id ?? tab.profileId,
            key: .webViewMaterialization(tabID: tab.id),
            replay: replay
        )
    }

    @discardableResult
    func deferMainFrameSubmission(
        for tab: Tab,
        on webView: WKWebView,
        semanticRevision: UInt64,
        replay: @escaping @MainActor () -> Void
    ) -> Bool {
        guard permitsInternalSubmission(
            tabID: tab.id,
            semanticRevision: semanticRevision
        ) == false else {
            return false
        }
        return deferOrdinaryAdmission(
            profileID: tab.resolveProfile()?.id ?? tab.profileId,
            key: .mainFrameSubmission(
                tabID: tab.id,
                webViewID: ObjectIdentifier(webView)
            ),
            replay: replay
        )
    }

    func waitForAdmission(profileID: UUID) async -> Bool {
        await admissionGate.waitForOrdinaryRuntimeAdmission(for: profileID)
    }

    func admissionIsBlocked(profileID: UUID) -> Bool {
        admissionGate.blocksOrdinaryRuntimeAdmission(for: profileID)
    }

    func resetForTerminalShutdown() {
        participantRegistry.removeAll()
        transaction.resetForTerminalShutdown()
    }
}
