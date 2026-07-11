import Foundation
import SumiWebRuntime
import WebKit

struct TabMainFrameAuthorityPromotion {
    let continuation: TabMainFrameAuthorityContinuation
    let targetURLToAdopt: URL?
    let migratedEvidence: [TabCommittedDocumentEvidence]
}

enum TabMainFrameLifecycleRoutingResult {
    case accepted(role: TabMainFrameLifecycleRole, targetURLToAdopt: URL?)
    case unmatched
    case retired
}

struct TabMainFrameLifecycleDeparture {
    let removedParticipant: Bool
    let wasAuthoritative: Bool
}

enum TabMainFrameLifecycleAbortTransition {
    case ignored
    case participant
    case authority(TabMainFrameAuthorityPromotion?)
}

struct TabMainFrameCommitTransition {
    let role: TabMainFrameLifecycleRole
    let evidence: TabCommittedDocumentEvidence?
    let publication: TabMainFrameCommitPublication?
}

struct TabMainFrameTerminalTransition {
    let role: TabMainFrameLifecycleRole
    let evidence: TabCommittedDocumentEvidence?
    let presentationURLToAdopt: URL?
}

struct TabMainFrameRehydrationResult {
    let evidence: [TabCommittedDocumentEvidence]
    let authorityWebViewID: ObjectIdentifier?
}

/// Coordinates exact-navigation lifecycle transitions across the participant
/// registry, authority state/reducer, and effect ledger. It owns no mutable
/// domain field itself and never reaches semantic
/// pending loads, durable rollback state, or WebContent recovery markers.
@MainActor
final class TabMainFrameLifecycleMachine {
    private typealias SharedCommitIdentity =
        TabMainFrameEffectLedger.SharedCommitIdentity

    private let participants = TabMainFrameParticipantRegistry()
    private let authorityState: TabMainFrameAuthorityState
    private let authorityReducer: TabMainFrameAuthorityReducer
    private let effectClaims = TabMainFrameEffectLedger()

    init() {
        let authorityState = TabMainFrameAuthorityState()
        self.authorityState = authorityState
        self.authorityReducer = TabMainFrameAuthorityReducer(
            authorityState: authorityState
        )
    }

    var documentGeneration: UInt64 {
        authorityReducer.documentGeneration
    }

    func resetForNewIntent() {
        participants.removeAllForNewIntent().forEach(
            effectClaims.removeParticipant
        )
        authorityReducer.resetForNewIntent()
        effectClaims.resetForDocumentGeneration()
    }

    func hasParticipant(on webView: WKWebView, revision: UInt64) -> Bool {
        participants.contains(webView, revision: revision)
    }

    func hasLiveAuthority(revision: UInt64) -> Bool {
        authorityReducer.hasLiveAuthority(
            revision: revision,
            participants: participants
        )
    }

    func authorityState(
        revision: UInt64
    ) -> TabMainFrameIntentLedger.AuthorityState? {
        guard hasLiveAuthority(revision: revision),
              let authority = authorityReducer.authority else {
            return nil
        }
        return TabMainFrameIntentLedger.AuthorityState(
            webViewID: authority.webViewID,
            isCompleted: authority.isCompleted
        )
    }

    func activateSubmission(
        _ binding: TabMainFrameIntentLedger.SubmissionBinding,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool {
        guard binding.revision == currentIntent.revision,
              let install = participants.installSubmission(
                  binding,
                  navigationID: navigationID,
                  navigationLifetime: navigationLifetime
              ) else {
            return false
        }
        if let replacedParticipantID = install.replacedParticipantID {
            effectClaims.removeParticipant(replacedParticipantID)
        }
        if binding.becomesAuthority {
            authorityReducer.installAuthority(
                revision: binding.revision,
                webViewID: binding.webViewID,
                documentGeneration: binding.documentGeneration,
                navigationID: navigationID
            )
        }
        return true
    }

    func semanticRevision(
        for webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject
    ) -> UInt64? {
        participants.semanticRevision(
            for: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime
        )
    }

    func loadingWebViews(revision: UInt64) -> [WKWebView] {
        participants.loadingWebViews(revision: revision)
    }

    func routeLifecycle(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        targetURL: URL,
        continuationKind: TabMainFrameContinuationKind?,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameLifecycleRoutingResult {
        guard participants.isRetiredNavigationIdentity(
            navigationID,
            lifetime: navigationLifetime
        ) == false else {
            return .retired
        }

        let webViewID = ObjectIdentifier(webView)
        let existingRole = lifecycleRole(
            webViewID: webViewID,
            navigationID: navigationID,
            currentIntent: currentIntent
        )
        if existingRole != .stale {
            participants.attachNavigationIdentityIfPossible(
                navigationID: navigationID,
                lifetime: navigationLifetime,
                webViewID: webViewID
            )
            return .accepted(role: existingRole, targetURLToAdopt: nil)
        }

        guard let continuationKind else { return .unmatched }
        let continuation = authorityReducer.transferToContinuation(
            webViewID: webViewID,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            targetURL: targetURL,
            kind: continuationKind,
            currentIntent: currentIntent,
            participants: participants,
            effectClaims: effectClaims
        )
        guard continuation.role != .stale else { return .unmatched }
        return .accepted(
            role: continuation.role,
            targetURLToAdopt: continuation.targetURLToAdopt
        )
    }

    func startLifecycleOwnedIntent(
        _ intent: TabMainFrameNavigationIntent,
        webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject
    ) {
        let webViewID = ObjectIdentifier(webView)
        let install = participants.installLifecycleOwnedEntry(
            intent: intent,
            webView: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            documentGeneration: documentGeneration
        )
        if let replacedParticipantID = install.replacedParticipantID {
            effectClaims.removeParticipant(replacedParticipantID)
        }
        authorityReducer.installAuthority(
            revision: intent.revision,
            webViewID: webViewID,
            documentGeneration: documentGeneration,
            navigationID: navigationID
        )
    }

    func lifecycleRole(
        from webView: WKWebView,
        navigationID: ObjectIdentifier?,
        isCurrent: Bool?,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameLifecycleRole {
        guard isCurrent != false, let navigationID else { return .stale }
        return lifecycleRole(
            webViewID: ObjectIdentifier(webView),
            navigationID: navigationID,
            currentIntent: currentIntent
        )
    }

    func prepareAuthorityForCommit(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameLifecycleRole {
        claimDocumentAuthority(
            from: webView,
            navigationID: navigationID,
            currentIntent: currentIntent
        )
    }

    func recordCommit(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        committedURL: URL,
        isPDF: Bool,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameCommitTransition {
        guard let record = authorityReducer.recordCommit(
            from: webView,
            navigationID: navigationID,
            committedURL: committedURL,
            isPDF: isPDF,
            currentIntent: currentIntent,
            participants: participants
        ) else {
            return TabMainFrameCommitTransition(
                role: .stale,
                evidence: nil,
                publication: nil
            )
        }
        guard record.role.isAuthority else {
            return TabMainFrameCommitTransition(
                role: record.role,
                evidence: record.evidence,
                publication: nil
            )
        }
        guard let authority = authorityLease(
            from: webView,
            navigationID: navigationID,
            currentIntent: currentIntent
        ) else {
            return TabMainFrameCommitTransition(
                role: .stale,
                evidence: record.evidence,
                publication: nil
            )
        }
        let identity = SharedCommitIdentity(
            target: WebRuntimeNavigationIdentity(committedURL),
            isPDF: isPDF
        )
        guard let permit = effectClaims.reserveSharedCommit(identity: identity) else {
            return TabMainFrameCommitTransition(
                role: .authority,
                evidence: record.evidence,
                publication: nil
            )
        }
        return TabMainFrameCommitTransition(
            role: .authority,
            evidence: record.evidence,
            publication: TabMainFrameCommitPublication(
                webView: webView,
                targetURL: committedURL,
                isPDF: isPDF,
                authority: authority,
                permit: permit
            )
        )
    }

    func consumeCommitPublication(
        _ publication: TabMainFrameCommitPublication,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool {
        guard remainsCurrent(
            publication.authority,
            currentIntent: currentIntent
        ),
        let participant = participants[publication.authority.webViewID],
        publication.webView === participant.webViewReference.resolve(),
        publication.targetURL == publication.authority.targetURL,
        participant.committedDocumentURL == publication.targetURL,
        (participant.isPDFResponse ?? false) == publication.isPDF else {
            return false
        }
        return effectClaims.consumeSharedCommit(
            publication.permit,
            identity: SharedCommitIdentity(
                target: WebRuntimeNavigationIdentity(publication.targetURL),
                isPDF: publication.isPDF
            )
        )
    }

    func recordResponse(
        isPDF: Bool,
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameLifecycleRole {
        let webViewID = ObjectIdentifier(webView)
        guard let participant = participants.recordResponse(
            isPDF: isPDF,
            webViewID: webViewID,
            navigationID: navigationID,
            revision: currentIntent.revision
        ) else {
            return .stale
        }
        return authorityReducer.lifecycleRole(
            for: participant,
            webViewID: webViewID,
            navigationID: navigationID
        )
    }

    func responseIsPDF(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool? {
        participants.responseIsPDF(
            webViewID: ObjectIdentifier(webView),
            navigationID: navigationID,
            revision: currentIntent.revision
        )
    }

    func claimTransactionStartEffects(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameEffectDecision<TabMainFrameActiveAuthorityLease> {
        guard let lease = authorityLease(
            from: webView,
            navigationID: navigationID,
            currentIntent: currentIntent
        ) else { return .stale }
        switch effectClaims.claimTransactionStart() {
        case .claimed: return .publish(lease)
        case .alreadyClaimed: return .alreadyClaimed(lease)
        }
    }

    func claimAuthorityTargetPreparation(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameEffectDecision<TabMainFrameActiveAuthorityLease> {
        guard let lease = authorityLease(
            from: webView,
            navigationID: navigationID,
            currentIntent: currentIntent
        ) else { return .stale }
        switch effectClaims.claimAuthorityTargetPreparation() {
        case .claimed: return .publish(lease)
        case .alreadyClaimed: return .alreadyClaimed(lease)
        }
    }

    func claimLocalStartEffects(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameEffectDecision<URL> {
        guard let participant = participants.exactEntry(for: webView),
              participant.revision == currentIntent.revision,
              participant.phase == .active(navigationID: navigationID) else {
            return .stale
        }
        switch effectClaims.claimLocalStart(participantID: participant.id) {
        case .claimed: return .publish(participant.targetURL)
        case .alreadyClaimed: return .alreadyClaimed(participant.targetURL)
        }
    }

    func remainsCurrent(
        _ lease: TabMainFrameActiveAuthorityLease,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool {
        guard lease.revision == currentIntent.revision,
              lease.documentGeneration == documentGeneration,
              let participant = participants[lease.webViewID],
              participant.id == lease.participantID,
              participant.revision == lease.revision,
              participant.documentGeneration == lease.documentGeneration,
              participant.phase == .active(navigationID: lease.navigationID),
              participant.targetURL == lease.targetURL,
              participant.webViewReference.resolve() != nil else {
            return false
        }
        return authorityState.matches(lease)
    }

    func claimAuthorityForTerminalSuccess(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        terminalURL: URL?,
        completesDocumentNavigation: Bool,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameTerminalTransition {
        authorityReducer.claimAuthorityForTerminalSuccess(
            from: webView,
            navigationID: navigationID,
            terminalURL: terminalURL,
            completesDocumentNavigation: completesDocumentNavigation,
            currentIntent: currentIntent,
            participants: participants,
            effectClaims: effectClaims
        )
    }

    func claimSharedFinishEffects(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool {
        let webViewID = ObjectIdentifier(webView)
        guard let participant = participants[webViewID] else { return false }
        return effectClaims.claimSharedFinish(
            isExactAuthority: isExactAuthority(
                webViewID: webViewID,
                navigationID: navigationID,
                currentIntent: currentIntent
            ),
            participantID: participant.id
        )
    }

    func claimPromotedSharedCommitEffects(
        matching continuation: TabMainFrameAuthorityContinuation,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabCommittedDocumentEvidence? {
        guard isCurrentAuthority(continuation, currentIntent: currentIntent),
              let participant = participants[continuation.webViewID],
              participant.hasCommittedDocument,
              let committedDocumentURL = participant.committedDocumentURL else {
            return nil
        }
        guard effectClaims.claimSharedCommit(identity: SharedCommitIdentity(
            target: WebRuntimeNavigationIdentity(committedDocumentURL),
            isPDF: continuation.isPDF
        )) else { return nil }
        return participant.committedEvidence(webView: continuation.webView)
    }

    func claimPromotedSharedFinishEffects(
        matching continuation: TabMainFrameAuthorityContinuation,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool {
        effectClaims.claimPromotedSharedFinish(
            isCurrentAuthority: isCurrentAuthority(
                continuation,
                currentIntent: currentIntent
            ),
            isCompleted: continuation.isCompleted
        )
    }

    func remainsCurrent(
        _ continuation: TabMainFrameAuthorityContinuation,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool {
        isCurrentAuthority(continuation, currentIntent: currentIntent)
    }

    func acceptPromotedTarget(
        _ targetURL: URL,
        matching continuation: TabMainFrameAuthorityContinuation,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool {
        guard isCurrentAuthority(continuation, currentIntent: currentIntent),
              updateAuthorityTarget(
                  targetURL,
                  webViewID: continuation.webViewID,
                  currentIntent: currentIntent
              ) else {
            return false
        }
        return true
    }

    func acceptLifecycleTarget(
        _ targetURL: URL,
        from webView: WKWebView,
        navigationID: ObjectIdentifier?,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool {
        guard let navigationID,
              isExactAuthority(
                  webViewID: ObjectIdentifier(webView),
                  navigationID: navigationID,
                  currentIntent: currentIntent
              ), updateAuthorityTarget(
                  targetURL,
                  webViewID: ObjectIdentifier(webView),
                  currentIntent: currentIntent
              ) else {
            return false
        }
        return true
    }

    func finishLifecycle(
        from webView: WKWebView,
        navigationID: ObjectIdentifier?,
        currentIntent: TabMainFrameNavigationIntent
    ) {
        guard let navigationID else { return }
        let webViewID = ObjectIdentifier(webView)
        guard participants.finish(
            webViewID: webViewID,
            navigationID: navigationID,
            revision: currentIntent.revision
        ) != nil else {
            return
        }
        if isExactAuthority(
            webViewID: webViewID,
            navigationID: navigationID,
            currentIntent: currentIntent
        ) {
            authorityReducer.markCompleted()
        }
    }

    func departure(
        of webView: WKWebView,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameLifecycleDeparture {
        departure(
            of: [webView],
            currentIntent: currentIntent
        )
    }

    func departure(
        of webViews: [WKWebView],
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameLifecycleDeparture {
        let departingWebViewIDs = Set(webViews.compactMap { webView in
            participants.exactEntry(for: webView).map { _ in
                ObjectIdentifier(webView)
            }
        })
        let removed = participants.removeAll(webViews)
        removed.forEach { effectClaims.removeParticipant($0.id) }
        guard authorityReducer.removeAuthorityIfMatching(
            webViewIDs: departingWebViewIDs,
            revision: currentIntent.revision
        ) else {
            return TabMainFrameLifecycleDeparture(
                removedParticipant: removed.isEmpty == false,
                wasAuthoritative: false
            )
        }
        return TabMainFrameLifecycleDeparture(
            removedParticipant: removed.isEmpty == false,
            wasAuthoritative: true
        )
    }

    func abortNavigation(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameLifecycleAbortTransition {
        let webViewID = ObjectIdentifier(webView)
        let isAuthoritative = isExactAuthority(
            webViewID: webViewID,
            navigationID: navigationID,
            currentIntent: currentIntent
        )
        guard let participant = participants.removeExactActiveNavigation(
            webView: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            revision: currentIntent.revision
        ) else {
            return .ignored
        }
        effectClaims.removeParticipant(participant.id)
        guard isAuthoritative else { return .participant }
        authorityReducer.clearAuthority()
        return .authority(promoteAuthorityCandidate(
            preferredWebViewID: nil,
            currentIntent: currentIntent
        ))
    }

    func promoteAuthorityCandidate(
        preferredWebViewID: ObjectIdentifier?,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameAuthorityPromotion? {
        authorityReducer.promoteAuthorityCandidate(
            participants: participants,
            effectClaims: effectClaims,
            preferredWebViewID: preferredWebViewID,
            currentIntent: currentIntent
        )
    }

    func documentEvidence(
        for webView: WKWebView,
        currentIntent: TabMainFrameNavigationIntent
    ) -> (evidence: TabCommittedDocumentEvidence, isAuthority: Bool)? {
        let webViewID = ObjectIdentifier(webView)
        guard let sharedCommitIdentity = effectClaims.sharedCommitIdentity,
              let proof = participants.committedDocumentProof(
                  webView: webView,
                  revision: currentIntent.revision,
                  documentGeneration: documentGeneration,
                  sharedCommitIdentity: sharedCommitIdentity
              ) else {
            return nil
        }
        return (
            proof.evidence,
            authorityReducer.isCommittedDocumentAuthority(
                proof.entry,
                webViewID: webViewID
            ),
        )
    }

    func rehydrate(
        _ candidates: [TabCommittedDocumentCandidate],
        preferredAuthorityWebViewID: ObjectIdentifier?,
        intent: TabMainFrameNavigationIntent
    ) -> TabMainFrameRehydrationResult {
        authorityReducer.rehydrate(
            candidates,
            preferredAuthorityWebViewID: preferredAuthorityWebViewID,
            intent: intent,
            participants: participants,
            effectClaims: effectClaims
        )
    }

    private func claimDocumentAuthority(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameLifecycleRole {
        let webViewID = ObjectIdentifier(webView)
        guard let participant = participants.activeEntry(
            webViewID: webViewID,
            navigationID: navigationID,
            revision: currentIntent.revision
        ) else {
            return .stale
        }
        return authorityReducer.claimDocumentAuthority(
            for: participant,
            webViewID: webViewID,
            navigationID: navigationID
        )
    }

    private func authorityLease(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameActiveAuthorityLease? {
        guard let participant = participants.exactEntry(for: webView),
        participant.revision == currentIntent.revision,
        participant.documentGeneration == documentGeneration,
        participant.phase == .active(navigationID: navigationID),
        isExactAuthority(
            webViewID: ObjectIdentifier(webView),
            navigationID: navigationID,
            currentIntent: currentIntent
        ) else {
            return nil
        }
        return authorityState.activeLease(
            participantID: participant.id,
            webViewID: ObjectIdentifier(webView),
            navigationID: navigationID,
            revision: participant.revision,
            documentGeneration: participant.documentGeneration,
            targetURL: participant.targetURL
        )
    }

    private func updateAuthorityTarget(
        _ targetURL: URL,
        webViewID: ObjectIdentifier,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool {
        guard let previousTarget = participants[webViewID]?.targetURL,
              participants.updateTarget(targetURL, webViewID: webViewID) else {
            return false
        }
        if previousTarget != targetURL {
            authorityState.noteTargetMutation(
                webViewID: webViewID,
                revision: currentIntent.revision
            )
        }
        return true
    }

    private func lifecycleRole(
        webViewID: ObjectIdentifier,
        navigationID: ObjectIdentifier,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameLifecycleRole {
        guard let participant = participants.activeEntry(
            webViewID: webViewID,
            navigationID: navigationID,
            revision: currentIntent.revision
        ) else {
            return .stale
        }
        return authorityReducer.lifecycleRole(
            for: participant,
            webViewID: webViewID,
            navigationID: navigationID
        )
    }

    private func isExactAuthority(
        webViewID: ObjectIdentifier,
        navigationID: ObjectIdentifier,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool {
        authorityReducer.isExactAuthority(
            webViewID: webViewID,
            navigationID: navigationID,
            revision: currentIntent.revision
        )
    }

    private func isCurrentAuthority(
        _ continuation: TabMainFrameAuthorityContinuation,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool {
        authorityReducer.isCurrentAuthority(
            continuation,
            revision: currentIntent.revision,
            participants: participants
        )
    }
}
