import Foundation
import SumiWebRuntime
import WebKit

/// Orchestrates the ordered website-data mutation protocol. Participant
/// discovery, exact-navigation barriers, and restore retries are delegated to
/// role-specific collaborators; this type owns only transaction admission and
/// phase ordering.
@MainActor
final class WebsiteDataCleanupTransaction {
    typealias CleanupNavigationIdentity = WebsiteDataCleanupNavigationBarrier.NavigationIdentity
    typealias RestoreCommandReceipt = WebsiteDataCleanupRestoreCommandReceipt
    typealias MutationPermissionWaiter = @MainActor (WKWebView) async -> Bool
    typealias BlankNavigationLoader = @MainActor (
        WKWebView
    ) -> CleanupNavigationIdentity?
    typealias TabRestorer = @MainActor (
        Tab,
        URL
    ) -> RestoreCommandReceipt
    typealias RetiringResidenceBarrier = @MainActor () async -> Bool
    typealias RuntimeMutationGeneration = @MainActor () -> UInt64
    typealias RuntimeTabProvider = @MainActor () -> [Tab]?
    typealias ExternalParticipantQuiescer = @MainActor (
        Set<UUID>
    ) async -> Bool
    typealias OwnershipTransitionAborter = @MainActor (Set<UUID>) -> Void

    private let mutationGate: WebsiteDataMutationGate
    private let navigationBarrier: WebsiteDataCleanupNavigationBarrier
    private let participantDiscovery: WebsiteDataCleanupParticipantDiscovery
    private let restoreLoop: WebsiteDataCleanupRestoreLoop
    private let quiesceExternalParticipants: ExternalParticipantQuiescer
    private let abortOwnershipTransitions: OwnershipTransitionAborter
    private let restoreCompensation = RestoreCompensation()

    private var isTerminallyShutDown = false

    init(
        runtimeTabs: @escaping RuntimeTabProvider,
        liveWebViews: @escaping @MainActor (Tab) -> [WKWebView],
        waitForMutationPermission: @escaping MutationPermissionWaiter,
        loadBlankNavigation: BlankNavigationLoader? = nil,
        restoreTab: @escaping TabRestorer,
        mutationGate: WebsiteDataMutationGate = WebsiteDataMutationGate(),
        waitForRetiringResidenceBarrier: @escaping RetiringResidenceBarrier = { true },
        runtimeMutationGeneration: @escaping RuntimeMutationGeneration = { 0 },
        quiesceExternalParticipants: @escaping ExternalParticipantQuiescer = { _ in true },
        abortOwnershipTransitions: @escaping OwnershipTransitionAborter = { _ in },
        blankAttemptTimeout: Duration = .seconds(30),
        restoreAttemptTimeout: Duration = .seconds(30),
        residenceBarrierTimeout: Duration = .seconds(30)
    ) {
        let navigationBarrier = WebsiteDataCleanupNavigationBarrier(
            waitForMutationPermission: waitForMutationPermission,
            loadBlankNavigation: loadBlankNavigation,
            blankAttemptTimeout: blankAttemptTimeout
        )
        self.mutationGate = mutationGate
        self.navigationBarrier = navigationBarrier
        participantDiscovery = WebsiteDataCleanupParticipantDiscovery(
            navigationBarrier: navigationBarrier,
            runtimeTabs: runtimeTabs,
            liveWebViews: liveWebViews,
            waitForRetiringResidenceBarrier: waitForRetiringResidenceBarrier,
            runtimeMutationGeneration: runtimeMutationGeneration,
            residenceBarrierTimeout: residenceBarrierTimeout
        )
        restoreLoop = WebsiteDataCleanupRestoreLoop(
            navigationBarrier: navigationBarrier,
            liveWebViews: liveWebViews,
            waitForMutationPermission: waitForMutationPermission,
            restoreTab: restoreTab,
            restoreAttemptTimeout: restoreAttemptTimeout
        )
        self.quiesceExternalParticipants = quiesceExternalParticipants
        self.abortOwnershipTransitions = abortOwnershipTransitions
    }

    @discardableResult
    func performDestructiveDataCleanup(
        profileIDs: Set<UUID>,
        deletion: @escaping @MainActor () async -> Void
    ) async -> Bool {
        guard profileIDs.isEmpty == false else {
            await deletion()
            return true
        }

        guard canEnterTransaction else { return false }

        guard let mutationLease = await mutationGate.acquire(
            profileIDs: profileIDs
        ) else {
            return false
        }
        defer { mutationGate.release(mutationLease) }

        // Ordering is part of the safety contract: close admission, abort
        // profile replacements, settle their repository residence, quiesce
        // external runtimes, then discover/blank Tabs to a fixed point.
        abortOwnershipTransitions(profileIDs)
        guard await participantDiscovery.waitForOwnershipSettlement(),
              await quiesceExternalParticipants(profileIDs),
              mutationGate.owns(mutationLease),
              canEnterTransaction else {
            return false
        }

        guard let session = navigationBarrier.beginSession() else {
            return false
        }
        defer { navigationBarrier.release(session) }

        let didSettleParticipants = await participantDiscovery.settleParticipants(
            profileIDs: profileIDs,
            session: session
        ) { [weak self] in
            guard let self else { return false }
            return self.navigationBarrier.isValid(session)
                && self.mutationGate.owns(mutationLease)
                && self.canEnterTransaction
        }
        guard didSettleParticipants,
              navigationBarrier.isValid(session),
              mutationGate.owns(mutationLease),
              canEnterTransaction else {
            return await rollbackAndFail(session)
        }

        await deletion()
        let restoreParticipants = navigationBarrier.ownedParticipants(in: session)
        let didRestore = await restoreCancellationShielded(
            restoreParticipants,
            in: session
        )

        RuntimeDiagnostics.debug(category: "WebsiteDataCleanupTransaction") {
            "Completed destructive data cleanup transaction for \(profileIDs.count) profile(s), quiescing \(self.navigationBarrier.participantCount(in: session)) live WebView(s); restore=\(didRestore)."
        }
        return didRestore
    }

    func isSuppressingNavigation(
        on webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject
    ) -> Bool {
        navigationBarrier.isSuppressingNavigation(
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
        semanticRevision: UInt64? = nil
    ) {
        navigationBarrier.navigationWillStart(
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
        navigationBarrier.navigationDidTerminate(
            on: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            succeeded: succeeded
        )
    }

    func webContentProcessDidTerminate(on webView: WKWebView) -> Bool {
        navigationBarrier.webContentProcessDidTerminate(on: webView)
    }

    func webViewDidLeaveRuntime(_ webView: WKWebView) {
        navigationBarrier.webViewDidLeaveRuntime(webView)
    }

    func webViewsDidLeaveRuntime(_ webViewIDs: [ObjectIdentifier]) {
        navigationBarrier.webViewsDidLeaveRuntime(webViewIDs)
    }

    func resetForTerminalShutdown() {
        isTerminallyShutDown = true
        mutationGate.resetForTerminalShutdown()
        navigationBarrier.resetForTerminalShutdown()
        restoreCompensation.cancelForTerminalShutdown()
    }

    private var canEnterTransaction: Bool {
        isTerminallyShutDown == false && Task.isCancelled == false
    }

    private func rollbackAndFail(
        _ session: WebsiteDataCleanupNavigationBarrier.Session
    ) async -> Bool {
        navigationBarrier.invalidate(session)
        _ = await restoreCancellationShielded(
            navigationBarrier.touchedOwnedParticipants(in: session),
            in: session
        )
        return false
    }

    private func restoreCancellationShielded(
        _ participants: [WebsiteDataCleanupNavigationBarrier.Participant],
        in session: WebsiteDataCleanupNavigationBarrier.Session
    ) async -> Bool {
        guard participants.isEmpty == false else { return true }
        return await restoreCompensation.run { [weak self] in
            guard let self else { return false }
            return await self.restoreLoop.restore(
                participants,
                in: session
            ) { [weak self] in
                self?.isTerminallyShutDown ?? true
            }
        }
    }

}
