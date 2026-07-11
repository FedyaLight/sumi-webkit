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
    let claim: TabMainFrameCommitSnapshotClaim
    let evidence: TabCommittedDocumentEvidence?
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

/// Coordinates exact-navigation lifecycle transitions across three exclusive
/// state owners: the participant registry, authority reducer, and effect
/// ledger. It owns no mutable domain field itself and never reaches semantic
/// pending loads, durable rollback state, or WebContent recovery markers.
@MainActor
final class TabMainFrameLifecycleMachine {
    private typealias SharedCommitIdentity =
        TabMainFrameEffectLedger.SharedCommitIdentity

    private let participants = TabMainFrameParticipantRegistry()
    private let authorityReducer = TabMainFrameAuthorityReducer()
    private let effectClaims = TabMainFrameEffectLedger()

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
        authorityReducer.recordCommit(
            from: webView,
            navigationID: navigationID,
            committedURL: committedURL,
            isPDF: isPDF,
            currentIntent: currentIntent,
            participants: participants,
            effectClaims: effectClaims
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
    ) -> Bool {
        effectClaims.claimTransactionStart(
            isExactAuthority: isExactAuthority(
                webViewID: ObjectIdentifier(webView),
                navigationID: navigationID,
                currentIntent: currentIntent
            )
        )
    }

    func claimAuthorityTargetPreparation(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool {
        effectClaims.claimAuthorityTargetPreparation(
            isExactAuthority: isExactAuthority(
                webViewID: ObjectIdentifier(webView),
                navigationID: navigationID,
                currentIntent: currentIntent
            )
        )
    }

    func claimLocalStartEffects(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool {
        let webViewID = ObjectIdentifier(webView)
        guard let participant = participants[webViewID],
              participant.revision == currentIntent.revision,
              participant.phase == .active(navigationID: navigationID) else {
            return false
        }
        return effectClaims.claimLocalStart(participantID: participant.id)
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

    func acceptPromotedTarget(
        _ targetURL: URL,
        matching continuation: TabMainFrameAuthorityContinuation,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool {
        guard isCurrentAuthority(continuation, currentIntent: currentIntent),
              participants.updateTarget(
                  targetURL,
                  webViewID: continuation.webViewID
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
              ), participants.updateTarget(
                  targetURL,
                  webViewID: ObjectIdentifier(webView)
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
