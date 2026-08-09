import Foundation
import SumiWebRuntime
import WebKit

/// Owns semantic navigation intent and every load that has not yet acquired an
/// exact WKNavigation identity. Binding a submission consumes its ledger entry
/// and hands one immutable participant identity to the lifecycle machine.
@MainActor
final class TabMainFrameIntentLedger {
    struct SubmissionBinding {
        let webView: WKWebView
        let revision: UInt64
        let documentGeneration: UInt64
        let participantID: UUID
        let webViewID: ObjectIdentifier
        let targetURL: URL
        let becomesAuthority: Bool
    }

    struct SubmissionFailure {
        let removedSubmission: Bool
        let wasAuthorityCandidate: Bool
        let settlement: TabMainFramePendingAttemptSettlement?
    }

    struct PendingDeparture {
        let removedLoad: Bool
        let wasAuthorityCandidate: Bool
        let settlements: [TabMainFramePendingAttemptSettlement]
    }

    struct AuthorityState {
        let webViewID: ObjectIdentifier
        let isCompleted: Bool
    }

    private typealias WeakWebViewReference = WebViewIdentityWitness

    private enum PendingPhase: Equatable {
        case preparing(ticketID: UUID)
        case deferred
        case submitted
    }

    private struct PendingLoad {
        let participantID: UUID
        let webViewReference: WeakWebViewReference
        let revision: UInt64
        let documentGeneration: UInt64
        var targetURL: URL
        var phase: PendingPhase
    }

    private(set) var intent: TabMainFrameNavigationIntent
    private var requiresFreshUserActionForUnboundLifecycle = false
    private var pendingLoadsByWebViewID: [ObjectIdentifier: PendingLoad] = [:]
    private var authorityCandidateWebViewID: ObjectIdentifier?

    init(initialURL: URL) {
        intent = TabMainFrameNavigationIntent(revision: 0, targetURL: initialURL)
    }

    func beginExplicitIntent(
        to targetURL: URL,
        blankAdmission: BlankDocumentAdmission? = nil
    ) -> TabMainFrameNavigationIntent {
        replaceIntent(
            revision: intent.revision &+ 1,
            targetURL: targetURL,
            blankAdmission: blankAdmission
        )
        requiresFreshUserActionForUnboundLifecycle = true
        return intent
    }

    func beginLifecycleIntent(
        to targetURL: URL,
        blankAdmission: BlankDocumentAdmission? = nil
    ) -> TabMainFrameNavigationIntent {
        replaceIntent(
            revision: intent.revision &+ 1,
            targetURL: targetURL,
            blankAdmission: blankAdmission
        )
        requiresFreshUserActionForUnboundLifecycle = false
        return intent
    }

    func admitBlankDocument(_ admission: BlankDocumentAdmission) {
        guard intent.targetURL.isSumiBlankDocumentURL,
              intent.blankAdmission == nil else { return }
        intent = TabMainFrameNavigationIntent(
            revision: intent.revision,
            targetURL: intent.targetURL,
            blankAdmission: admission
        )
    }

    func admitsCommit(to committedURL: URL) -> Bool {
        guard committedURL.isSumiBlankDocumentURL else { return true }
        return intent.targetURL.isSumiBlankDocumentURL
            && intent.blankAdmission != nil
    }

    func beginRollbackIntent(to targetURL: URL) -> TabMainFrameNavigationIntent {
        replaceIntent(
            revision: intent.revision &+ 1,
            targetURL: targetURL,
            blankAdmission: nil
        )
        requiresFreshUserActionForUnboundLifecycle = true
        return intent
    }

    func canStartUnboundLifecycle(
        on webView: WKWebView,
        allowsUserInitiatedSupersession: Bool,
        lifecycleAuthority: AuthorityState?,
        hasLifecycleParticipant: Bool
    ) -> Bool {
        if let authority = lifecycleAuthority ?? pendingAuthorityState() {
            return allowsUserInitiatedSupersession
                || (authority.isCompleted && authority.webViewID == ObjectIdentifier(webView))
        }
        if hasLifecycleParticipant {
            return allowsUserInitiatedSupersession
        }
        return allowsUserInitiatedSupersession
            || requiresFreshUserActionForUnboundLifecycle == false
    }

    func updateTargetWithinRevision(_ targetURL: URL) {
        guard !Self.matchesNavigationTarget(intent.targetURL, targetURL) else {
            return
        }
        intent = TabMainFrameNavigationIntent(
            revision: intent.revision,
            targetURL: targetURL,
            blankAdmission: intent.blankAdmission
        )

        for (webViewID, var load) in pendingLoadsByWebViewID
        where load.revision == intent.revision {
            switch load.phase {
            case .preparing:
                load.targetURL = targetURL
                pendingLoadsByWebViewID[webViewID] = load
            case .submitted where authorityCandidateWebViewID == webViewID:
                load.targetURL = targetURL
                pendingLoadsByWebViewID[webViewID] = load
            case .deferred, .submitted:
                break
            }
        }
    }

    func current(matching targetURL: URL) -> TabMainFrameNavigationIntent? {
        Self.matchesNavigationTarget(intent.targetURL, targetURL) ? intent : nil
    }

    func current(revision: UInt64) -> TabMainFrameNavigationIntent? {
        intent.revision == revision ? intent : nil
    }

    func isCurrent(_ candidate: TabMainFrameNavigationIntent) -> Bool {
        intent == candidate
    }

    func isCurrent(revision: UInt64, targetURL: URL) -> Bool {
        intent.revision == revision
            && Self.matchesNavigationTarget(intent.targetURL, targetURL)
    }

    func beginPreparedLoad(
        on webView: WKWebView,
        intent candidate: TabMainFrameNavigationIntent,
        documentGeneration: UInt64,
        hasLifecycleParticipant: Bool
    ) -> TabMainFramePreparedLoadTicket? {
        guard intent == candidate else { return nil }
        let webViewID = ObjectIdentifier(webView)
        discardStalePendingLoad(for: webView)
        guard pendingLoadsByWebViewID[webViewID] == nil,
              hasLifecycleParticipant == false else {
            return nil
        }
        let ticket = TabMainFramePreparedLoadTicket(
            revision: candidate.revision,
            id: UUID(),
            webViewID: webViewID
        )
        pendingLoadsByWebViewID[webViewID] = PendingLoad(
            participantID: UUID(),
            webViewReference: WeakWebViewReference(webView),
            revision: candidate.revision,
            documentGeneration: documentGeneration,
            targetURL: candidate.targetURL,
            phase: .preparing(ticketID: ticket.id)
        )
        return ticket
    }

    func finishPreparedLoad(_ ticket: TabMainFramePreparedLoadTicket) {
        _ = cancelPreparedLoad(ticket)
    }

    func cancelPreparedLoad(
        _ ticket: TabMainFramePreparedLoadTicket
    ) -> TabMainFramePendingAttemptSettlement? {
        guard let load = pendingLoadsByWebViewID[ticket.webViewID],
              load.revision == ticket.revision,
              load.phase == .preparing(ticketID: ticket.id) else {
            return nil
        }
        pendingLoadsByWebViewID.removeValue(forKey: ticket.webViewID)
        return settlement(
            for: load,
            webViewID: ticket.webViewID,
            reason: .cancelled
        )
    }

    func claimPreparedSubmission(
        on webView: WKWebView,
        ticket: TabMainFramePreparedLoadTicket,
        hasLifecycleAuthority: Bool
    ) -> TabMainFrameSubmissionLease? {
        let webViewID = ObjectIdentifier(webView)
        guard ticket.webViewID == webViewID,
              var load = pendingLoadsByWebViewID[webViewID],
              load.webViewReference.matches(webView),
              load.revision == ticket.revision,
              load.phase == .preparing(ticketID: ticket.id),
              load.revision == intent.revision,
              Self.matchesNavigationTarget(load.targetURL, intent.targetURL) else {
            return nil
        }
        load.phase = .submitted
        pendingLoadsByWebViewID[webViewID] = load
        assignAuthorityCandidateIfNeeded(
            webViewID,
            hasLifecycleAuthority: hasLifecycleAuthority
        )
        return submissionLease(for: load, webViewID: webViewID)
    }

    func pendingAttemptStatus(
        on webView: WKWebView
    ) -> TabMainFramePendingAttemptStatus {
        let webViewID = ObjectIdentifier(webView)
        guard let load = pendingLoadsByWebViewID[webViewID],
              load.webViewReference.matches(webView),
              load.revision == intent.revision else {
            return .unsubmitted(intent)
        }
        let owner = pendingAttemptOwner(for: load, webViewID: webViewID)
        switch load.phase {
        case .preparing, .deferred:
            return .waiting(owner)
        case .submitted:
            return .submitted(owner)
        }
    }

    func markDeferredLoad(
        on webView: WKWebView,
        intent candidate: TabMainFrameNavigationIntent,
        documentGeneration: UInt64,
        isLifecycleAuthority: Bool
    ) -> Bool {
        switch deferAttempt(
            on: webView,
            intent: candidate,
            documentGeneration: documentGeneration,
            isLifecycleAuthority: isLifecycleAuthority
        ) {
        case .waiting, .coalesced:
            return true
        case .rejected:
            return false
        }
    }

    func deferAttempt(
        on webView: WKWebView,
        intent candidate: TabMainFrameNavigationIntent,
        documentGeneration: UInt64,
        isLifecycleAuthority: Bool
    ) -> TabMainFramePendingAttemptAdmission {
        guard intent == candidate else { return .rejected }
        let webViewID = ObjectIdentifier(webView)
        discardStalePendingLoad(for: webView)
        guard isLifecycleAuthority == false,
              authorityCandidateWebViewID != webViewID else {
            return .rejected
        }
        if let load = pendingLoadsByWebViewID[webViewID],
           load.revision == candidate.revision,
           Self.matchesNavigationTarget(load.targetURL, candidate.targetURL) {
            guard load.phase == .deferred else { return .rejected }
            return .coalesced(pendingAttemptOwner(
                for: load,
                webViewID: webViewID
            ))
        }
        let load = PendingLoad(
            participantID: UUID(),
            webViewReference: WeakWebViewReference(webView),
            revision: candidate.revision,
            documentGeneration: documentGeneration,
            targetURL: candidate.targetURL,
            phase: .deferred
        )
        pendingLoadsByWebViewID[webViewID] = load
        return .waiting(pendingAttemptOwner(
            for: load,
            webViewID: webViewID
        ))
    }

    func clearDeferredLoad(
        on webView: WKWebView,
        intent candidate: TabMainFrameNavigationIntent
    ) {
        let webViewID = ObjectIdentifier(webView)
        guard let load = pendingLoadsByWebViewID[webViewID],
              load.webViewReference.matches(webView),
              load.revision == candidate.revision,
              load.phase == .deferred,
              Self.matchesNavigationTarget(load.targetURL, candidate.targetURL) else {
            return
        }
        pendingLoadsByWebViewID.removeValue(forKey: webViewID)
    }

    func claimDirectSubmission(
        on webView: WKWebView,
        documentGeneration: UInt64,
        hasLifecycleAuthority: Bool
    ) -> TabMainFrameSubmissionLease? {
        let webViewID = ObjectIdentifier(webView)
        discardStalePendingLoad(for: webView)
        if let load = pendingLoadsByWebViewID[webViewID],
           load.revision == intent.revision,
           Self.matchesNavigationTarget(load.targetURL, intent.targetURL) {
            guard case .preparing = load.phase else { return nil }
        }

        let load = PendingLoad(
            participantID: UUID(),
            webViewReference: WeakWebViewReference(webView),
            revision: intent.revision,
            documentGeneration: documentGeneration,
            targetURL: intent.targetURL,
            phase: .submitted
        )
        pendingLoadsByWebViewID[webViewID] = load
        assignAuthorityCandidateIfNeeded(
            webViewID,
            hasLifecycleAuthority: hasLifecycleAuthority
        )
        return submissionLease(for: load, webViewID: webViewID)
    }

    func claimDeferredSubmission(
        on webView: WKWebView,
        revision: UInt64,
        targetURL: URL,
        hasLifecycleAuthority: Bool
    ) -> TabDeferredMainFrameLoadClaim {
        guard isCurrent(revision: revision, targetURL: targetURL) else {
            return .stale
        }
        let webViewID = ObjectIdentifier(webView)
        guard var load = pendingLoadsByWebViewID[webViewID],
              load.revision == revision,
              load.webViewReference.matches(webView),
              Self.matchesNavigationTarget(load.targetURL, targetURL) else {
            return .stale
        }
        guard load.phase == .deferred else { return .alreadyScheduled }
        load.phase = .submitted
        pendingLoadsByWebViewID[webViewID] = load
        assignAuthorityCandidateIfNeeded(
            webViewID,
            hasLifecycleAuthority: hasLifecycleAuthority
        )
        return .claimed
    }

    func submittedLease(
        on webView: WKWebView,
        revision: UInt64,
        targetURL: URL
    ) -> TabMainFrameSubmissionLease? {
        let webViewID = ObjectIdentifier(webView)
        guard let load = pendingLoadsByWebViewID[webViewID],
              load.webViewReference.matches(webView),
              load.revision == revision,
              load.phase == .submitted,
              Self.matchesNavigationTarget(load.targetURL, targetURL) else {
            return nil
        }
        return submissionLease(for: load, webViewID: webViewID)
    }

    func consumeSubmittedLoad(
        on webView: WKWebView,
        matching lease: TabMainFrameSubmissionLease?,
        hasLifecycleAuthority: Bool
    ) -> SubmissionBinding? {
        let webViewID = ObjectIdentifier(webView)
        guard let load = pendingLoadsByWebViewID[webViewID],
              load.webViewReference.matches(webView),
              load.revision == intent.revision,
              load.phase == .submitted,
              submissionLease(lease, matches: load, webViewID: webViewID) else {
            return nil
        }
        pendingLoadsByWebViewID.removeValue(forKey: webViewID)
        var becomesAuthority = authorityCandidateWebViewID == webViewID
        if becomesAuthority {
            authorityCandidateWebViewID = nil
        } else if hasLifecycleAuthority == false,
                  pendingAuthorityState() == nil {
            becomesAuthority = true
        }
        return SubmissionBinding(
            webView: webView,
            revision: load.revision,
            documentGeneration: load.documentGeneration,
            participantID: load.participantID,
            webViewID: webViewID,
            targetURL: load.targetURL,
            becomesAuthority: becomesAuthority
        )
    }

    func failSubmittedLoad(
        on webView: WKWebView,
        matching lease: TabMainFrameSubmissionLease?
    ) -> SubmissionFailure {
        let webViewID = ObjectIdentifier(webView)
        guard let load = pendingLoadsByWebViewID[webViewID],
              load.webViewReference.matches(webView),
              load.revision == intent.revision,
              load.phase == .submitted,
              submissionLease(lease, matches: load, webViewID: webViewID) else {
            return SubmissionFailure(
                removedSubmission: false,
                wasAuthorityCandidate: false,
                settlement: nil
            )
        }
        pendingLoadsByWebViewID.removeValue(forKey: webViewID)
        let wasAuthorityCandidate = authorityCandidateWebViewID == webViewID
        if wasAuthorityCandidate {
            authorityCandidateWebViewID = nil
        }
        return SubmissionFailure(
            removedSubmission: true,
            wasAuthorityCandidate: wasAuthorityCandidate,
            settlement: settlement(
                for: load,
                webViewID: webViewID,
                reason: .failed
            )
        )
    }

    func restoreDeferredLoadAfterFailedSubmission(
        on webView: WKWebView,
        revision: UInt64,
        targetURL: URL,
        matching lease: TabMainFrameSubmissionLease?
    ) -> Bool {
        let webViewID = ObjectIdentifier(webView)
        guard isCurrent(revision: revision, targetURL: targetURL),
              var load = pendingLoadsByWebViewID[webViewID],
              load.webViewReference.matches(webView),
              load.revision == revision,
              load.phase == .submitted,
              Self.matchesNavigationTarget(load.targetURL, targetURL),
              submissionLease(lease, matches: load, webViewID: webViewID) else {
            return false
        }
        load.phase = .deferred
        pendingLoadsByWebViewID[webViewID] = load
        let relinquishedAuthority = authorityCandidateWebViewID == webViewID
        if relinquishedAuthority {
            authorityCandidateWebViewID = nil
        }
        return relinquishedAuthority
    }

    func departure(of webView: WKWebView) -> PendingDeparture {
        departure(of: [webView])
    }

    func departure(of webViews: [WKWebView]) -> PendingDeparture {
        var removedLoad = false
        var wasAuthorityCandidate = false
        var settlements: [TabMainFramePendingAttemptSettlement] = []
        var seen: Set<ObjectIdentifier> = []
        for webView in webViews {
            let webViewID = ObjectIdentifier(webView)
            guard seen.insert(webViewID).inserted else { continue }
            if let load = pendingLoadsByWebViewID[webViewID],
               load.webViewReference.matches(webView) {
                pendingLoadsByWebViewID.removeValue(forKey: webViewID)
                removedLoad = true
                settlements.append(settlement(
                    for: load,
                    webViewID: webViewID,
                    reason: .departed
                ))
            }
            if authorityCandidateWebViewID == webViewID {
                authorityCandidateWebViewID = nil
                wasAuthorityCandidate = true
            }
        }
        return PendingDeparture(
            removedLoad: removedLoad,
            wasAuthorityCandidate: wasAuthorityCandidate,
            settlements: settlements
        )
    }

    func promoteSubmittedAuthority(
        preferredWebViewID: ObjectIdentifier? = nil
    ) -> TabMainFrameAuthorityContinuation? {
        let candidates = pendingLoadsByWebViewID.filter { _, load in
            load.revision == intent.revision
                && load.phase == .submitted
                && load.webViewReference.resolve() != nil
        }
        guard let candidate = candidates.min(by: { lhs, rhs in
            let lhsRank = (
                lhs.key == preferredWebViewID ? 0 : 1,
                UInt(bitPattern: lhs.key)
            )
            let rhsRank = (
                rhs.key == preferredWebViewID ? 0 : 1,
                UInt(bitPattern: rhs.key)
            )
            return lhsRank < rhsRank
        }), let webView = candidate.value.webViewReference.resolve() else {
            authorityCandidateWebViewID = nil
            return nil
        }
        authorityCandidateWebViewID = candidate.key
        return TabMainFrameAuthorityContinuation(
            webView: webView,
            navigationID: nil,
            targetURL: candidate.value.targetURL,
            isPDF: false,
            isCompleted: false,
            hasCommittedDocument: false,
            needsSharedCommitEffects: false,
            needsSharedFinishEffects: false,
            revision: candidate.value.revision,
            documentGeneration: candidate.value.documentGeneration,
            participantID: candidate.value.participantID,
            webViewID: candidate.key,
            source: .pendingSubmission
        )
    }

    func isCurrentPendingAuthority(
        _ continuation: TabMainFrameAuthorityContinuation
    ) -> Bool {
        guard continuation.source == .pendingSubmission,
              authorityCandidateWebViewID == continuation.webViewID,
              let load = pendingLoadsByWebViewID[continuation.webViewID],
              load.webViewReference.matches(continuation.webView),
              load.phase == .submitted else {
            return false
        }
        return continuation.navigationID == nil
            && continuation.isCompleted == false
            && continuation.revision == load.revision
            && continuation.documentGeneration == load.documentGeneration
            && continuation.participantID == load.participantID
            && continuation.webViewID == ObjectIdentifier(continuation.webView)
            && continuation.targetURL == load.targetURL
            && continuation.isPDF == false
            && continuation.needsSharedCommitEffects == false
            && continuation.needsSharedFinishEffects == false
    }

    func hasPendingAuthority() -> Bool {
        pendingAuthorityState() != nil
    }

    func hasOutstandingLoad(on webView: WKWebView, targetURL: URL) -> Bool {
        let webViewID = ObjectIdentifier(webView)
        guard let load = pendingLoadsByWebViewID[webViewID],
              load.webViewReference.matches(webView),
              load.revision == intent.revision,
              Self.matchesNavigationTarget(load.targetURL, targetURL) else {
            return false
        }
        return true
    }

    func submittedWebViews() -> [WKWebView] {
        pendingLoadsByWebViewID.values.compactMap { load in
            guard load.revision == intent.revision,
                  load.phase == .submitted else {
                return nil
            }
            return load.webViewReference.resolve()
        }
    }

    private func replaceIntent(
        revision: UInt64,
        targetURL: URL,
        blankAdmission: BlankDocumentAdmission?
    ) {
        intent = TabMainFrameNavigationIntent(
            revision: revision,
            targetURL: targetURL,
            blankAdmission: blankAdmission
        )
        pendingLoadsByWebViewID.removeAll()
        authorityCandidateWebViewID = nil
    }

    private func discardStalePendingLoad(for webView: WKWebView) {
        let webViewID = ObjectIdentifier(webView)
        guard let load = pendingLoadsByWebViewID[webViewID],
              load.webViewReference.matches(webView) == false else {
            return
        }
        pendingLoadsByWebViewID.removeValue(forKey: webViewID)
        if authorityCandidateWebViewID == webViewID {
            authorityCandidateWebViewID = nil
        }
    }

    private func assignAuthorityCandidateIfNeeded(
        _ webViewID: ObjectIdentifier,
        hasLifecycleAuthority: Bool
    ) {
        guard hasLifecycleAuthority == false,
              pendingAuthorityState() == nil else {
            return
        }
        authorityCandidateWebViewID = webViewID
    }

    private func pendingAuthorityState() -> AuthorityState? {
        guard let authorityCandidateWebViewID,
              let load = pendingLoadsByWebViewID[authorityCandidateWebViewID],
              load.phase == .submitted,
              load.webViewReference.resolve() != nil else {
            self.authorityCandidateWebViewID = nil
            return nil
        }
        return AuthorityState(
            webViewID: authorityCandidateWebViewID,
            isCompleted: false
        )
    }

    private func submissionLease(
        for load: PendingLoad,
        webViewID: ObjectIdentifier
    ) -> TabMainFrameSubmissionLease {
        TabMainFrameSubmissionLease(
            revision: load.revision,
            documentGeneration: load.documentGeneration,
            participantID: load.participantID,
            webViewID: webViewID
        )
    }

    private func pendingAttemptOwner(
        for load: PendingLoad,
        webViewID: ObjectIdentifier
    ) -> TabMainFramePendingAttemptOwner {
        let phase: TabMainFramePendingAttemptPhase
        switch load.phase {
        case .preparing(let ticketID):
            phase = .preparing(ticketID: ticketID)
        case .deferred:
            phase = .deferred
        case .submitted:
            phase = .submitted
        }
        return TabMainFramePendingAttemptOwner(
            intent: TabMainFrameNavigationIntent(
                revision: load.revision,
                targetURL: load.targetURL,
                blankAdmission: load.revision == intent.revision
                    ? intent.blankAdmission
                    : nil
            ),
            documentGeneration: load.documentGeneration,
            participantID: load.participantID,
            webViewID: webViewID,
            phase: phase
        )
    }

    private func settlement(
        for load: PendingLoad,
        webViewID: ObjectIdentifier,
        reason: TabMainFramePendingAttemptTerminalReason
    ) -> TabMainFramePendingAttemptSettlement {
        TabMainFramePendingAttemptSettlement(
            owner: pendingAttemptOwner(for: load, webViewID: webViewID),
            reason: reason
        )
    }

    private func submissionLease(
        _ lease: TabMainFrameSubmissionLease?,
        matches load: PendingLoad,
        webViewID: ObjectIdentifier
    ) -> Bool {
        guard let lease else { return true }
        return lease.revision == load.revision
            && lease.documentGeneration == load.documentGeneration
            && lease.participantID == load.participantID
            && lease.webViewID == webViewID
    }

    private static func matchesNavigationTarget(_ lhs: URL, _ rhs: URL) -> Bool {
        WebRuntimeNavigationIdentity.matches(lhs, rhs)
    }
}
