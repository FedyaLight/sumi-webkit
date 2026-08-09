import Foundation
import SumiWebRuntime
import WebKit

/// Performs the single finite compensation allowed after website-data
/// deletion. A concrete WebKit submission transfers each residence back to
/// ordinary page lifecycle; every other disposition becomes an explicit
/// recoverable failure. There is deliberately no retry task or timeout.
@MainActor
final class WebsiteDataCleanupRestorer {
    typealias TabRestorer = @MainActor (
        Tab,
        URL
    ) -> WebsiteDataCleanupRestoreCommandReceipt

    private let navigationBarrier: WebsiteDataCleanupNavigationBarrier
    private let liveWebViews: @MainActor (Tab) -> [WKWebView]
    private let restoreTab: TabRestorer

    init(
        navigationBarrier: WebsiteDataCleanupNavigationBarrier,
        liveWebViews: @escaping @MainActor (Tab) -> [WKWebView],
        restoreTab: @escaping TabRestorer
    ) {
        self.navigationBarrier = navigationBarrier
        self.liveWebViews = liveWebViews
        self.restoreTab = restoreTab
    }

    func restore(
        _ participants: [WebsiteDataCleanupNavigationBarrier.Participant],
        in session: WebsiteDataCleanupNavigationBarrier.Session,
        isTerminallyShutDown: @escaping @MainActor () -> Bool
    ) async -> Bool {
        guard participants.isEmpty == false else { return true }

        var pendingByTabID: [UUID: [WebsiteDataCleanupNavigationBarrier.Participant]] = [:]
        for participant in participants {
            guard navigationBarrier.stillOwns(participant) else {
                navigationBarrier.abandon(participant)
                continue
            }
            pendingByTabID[participant.tab.id, default: []].append(participant)
        }

        guard isTerminallyShutDown() == false else {
            navigationBarrier.abandon(Array(pendingByTabID.values.joined()))
            return false
        }

        var allTransferred = true
        for originalParticipants in pendingByTabID.values {
            let owned = originalParticipants.filter(navigationBarrier.stillOwns)
            guard let tab = owned.first?.tab else {
                navigationBarrier.abandon(originalParticipants)
                continue
            }
            let currentBeforeSubmission = navigationBarrier.currentRestoreParticipants(
                for: tab,
                liveWebViews: liveWebViews(tab),
                in: session
            )
            let targetURL = tab.mainFrameLoads.currentIntent.targetURL
            navigationBarrier.beginRestoreSubmission(
                currentBeforeSubmission,
                targetURL: targetURL
            )
            guard isTerminallyShutDown() == false else {
                navigationBarrier.abandon(currentBeforeSubmission)
                return false
            }

            let receipt = restoreTab(tab, targetURL)
            let currentAfterSubmission = navigationBarrier.currentRestoreParticipants(
                for: tab,
                liveWebViews: liveWebViews(tab),
                in: session
            )
            // A synchronous submission can atomically replace the physical
            // residence. Register that successor under the same one-shot
            // obligation before consuming the concrete submission proof.
            navigationBarrier.beginRestoreSubmission(
                currentAfterSubmission,
                targetURL: targetURL
            )
            let submittedWebViewIDs = concreteSubmissionWebViewIDs(
                in: receipt.outcome,
                targetURL: targetURL,
                semanticRevision: receipt.semanticRevision
            )
            var failedParticipants: [WebsiteDataCleanupNavigationBarrier.Participant] = []
            for participant in currentAfterSubmission {
                let webViewID = ObjectIdentifier(participant.webView)
                guard submittedWebViewIDs.contains(webViewID),
                      navigationBarrier.transferRestoreSubmission(
                          for: participant,
                          targetURL: targetURL
                      ) else {
                    allTransferred = false
                    failedParticipants.append(participant)
                    continue
                }
            }
            if failedParticipants.count == currentAfterSubmission.count {
                tab.loadingState = .idle
            }
            failedParticipants.forEach { presentFailure(for: $0) }
            for participant in currentBeforeSubmission
            where navigationBarrier.stillOwns(participant)
                && currentAfterSubmission.contains(where: { $0 === participant }) == false {
                navigationBarrier.abandon(participant)
            }
        }
        return allTransferred
    }

    private func concreteSubmissionWebViewIDs(
        in outcome: PageReloadCommandOutcome,
        targetURL: URL,
        semanticRevision: UInt64?
    ) -> Set<ObjectIdentifier> {
        Set(outcome.dispositions.compactMap { disposition -> ObjectIdentifier? in
            let submission: PageReloadSubmission
            switch disposition {
            case .submitted(let proof), .submittedFallbackNavigation(let proof):
                submission = proof
            case .waiting, .coalesced, .failed:
                return nil
            }
            guard let semanticRevision,
                  submission.owner.intent.revision == semanticRevision,
                  WebRuntimeNavigationIdentity.matches(
                submission.owner.intent.targetURL,
                targetURL
            ) else {
                return nil
            }
            return submission.owner.webViewID
        })
    }

    private func presentFailure(
        for participant: WebsiteDataCleanupNavigationBarrier.Participant
    ) {
        guard navigationBarrier.stillOwns(participant) else {
            navigationBarrier.abandon(participant)
            return
        }
        let tab = participant.tab
        _ = tab.webContentRecoveryAdmission.beginRecovery(
            on: participant.webView,
            snapshot: nil
        )
        tab.webContentRecoveryAdmission.failRecoveryDelivery(
            on: participant.webView
        )
        tab.navigationRuntime.webViewRouting.pagePresentationDidChange(
            tab.id,
            participant.webView
        )
        navigationBarrier.abandon(participant)
    }
}
