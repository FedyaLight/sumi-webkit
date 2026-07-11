import Foundation
import SumiWebRuntime
import WebKit

/// Sole owner of logical main-frame authority and document-generation state.
/// It reduces exact participant facts into authority transitions without
/// owning participant storage or effect publication claims.
@MainActor
final class TabMainFrameAuthorityReducer {
    private typealias SharedCommitIdentity =
        TabMainFrameEffectLedger.SharedCommitIdentity

    struct AuthorityState: Equatable {
        let revision: UInt64
        let webViewID: ObjectIdentifier
        var documentGeneration: UInt64
        var navigationID: ObjectIdentifier?
        var hasCommittedDocument: Bool
        var isCompleted: Bool
    }

    struct ContinuationReduction {
        var participant: TabMainFrameParticipantRegistry.Entry
        let becomesAuthority: Bool
        let beganNewDocumentGeneration: Bool
    }

    struct CandidateSelection {
        let webViewID: ObjectIdentifier
        let participant: TabMainFrameParticipantRegistry.Entry
    }

    private struct RedirectGenerationKey: Hashable {
        let sourceGeneration: UInt64
        let target: WebRuntimeNavigationIdentity
    }

    private(set) var documentGeneration: UInt64 = 0
    private(set) var authority: AuthorityState?
    private var redirectGenerationByKey: [RedirectGenerationKey: UInt64] = [:]

    func resetForNewIntent() {
        documentGeneration = 0
        authority = nil
        redirectGenerationByKey.removeAll()
    }

    func installAuthority(
        revision: UInt64,
        webViewID: ObjectIdentifier,
        documentGeneration: UInt64,
        navigationID: ObjectIdentifier?,
        hasCommittedDocument: Bool = false,
        isCompleted: Bool = false
    ) {
        authority = AuthorityState(
            revision: revision,
            webViewID: webViewID,
            documentGeneration: documentGeneration,
            navigationID: navigationID,
            hasCommittedDocument: hasCommittedDocument,
            isCompleted: isCompleted
        )
    }

    func clearAuthority() {
        authority = nil
    }

    func removeAuthorityIfMatching(
        webViewIDs: Set<ObjectIdentifier>,
        revision: UInt64
    ) -> Bool {
        guard authority?.revision == revision,
              authority.map({ webViewIDs.contains($0.webViewID) }) == true else {
            return false
        }
        authority = nil
        return true
    }

    func hasLiveAuthority(
        revision: UInt64,
        participants: TabMainFrameParticipantRegistry
    ) -> Bool {
        guard let authority,
              authority.revision == revision,
              authority.documentGeneration == documentGeneration,
              let participant = participants.entry(for: authority.webViewID),
              participant.revision == revision,
              participant.documentGeneration == documentGeneration,
              participant.webViewReference.resolve() != nil else {
            return false
        }
        return true
    }

    func isExactAuthority(
        webViewID: ObjectIdentifier,
        navigationID: ObjectIdentifier,
        revision: UInt64
    ) -> Bool {
        guard let authority else { return false }
        return authority.revision == revision
            && authority.documentGeneration == documentGeneration
            && authority.webViewID == webViewID
            && authority.navigationID == navigationID
    }

    func ownsParticipant(
        _ participant: TabMainFrameParticipantRegistry.Entry,
        webViewID: ObjectIdentifier,
        previousNavigationID: ObjectIdentifier?
    ) -> Bool {
        guard let authority,
              authority.revision == participant.revision,
              authority.webViewID == webViewID else {
            return false
        }
        if let previousNavigationID {
            return authority.navigationID == previousNavigationID
        }
        return authority.navigationID == nil && authority.isCompleted
    }

    func markCommitted() {
        authority?.hasCommittedDocument = true
    }

    func markCompleted() {
        authority?.navigationID = nil
        authority?.isCompleted = true
    }

    func lifecycleRole(
        for participant: TabMainFrameParticipantRegistry.Entry,
        webViewID: ObjectIdentifier,
        navigationID: ObjectIdentifier
    ) -> TabMainFrameLifecycleRole {
        isExactAuthority(
            webViewID: webViewID,
            navigationID: navigationID,
            revision: participant.revision
        ) ? .authority : .participant
    }

    func claimDocumentAuthority(
        for participant: TabMainFrameParticipantRegistry.Entry,
        webViewID: ObjectIdentifier,
        navigationID: ObjectIdentifier
    ) -> TabMainFrameLifecycleRole {
        guard participant.documentGeneration == documentGeneration else {
            return .participant
        }
        if isExactAuthority(
            webViewID: webViewID,
            navigationID: navigationID,
            revision: participant.revision
        ) {
            if participant.hasCommittedDocument {
                markCommitted()
            }
            return .authority
        }
        if let authority,
           authority.revision == participant.revision,
           authority.hasCommittedDocument {
            return .participant
        }
        installAuthority(
            revision: participant.revision,
            webViewID: webViewID,
            documentGeneration: participant.documentGeneration,
            navigationID: navigationID,
            hasCommittedDocument: participant.hasCommittedDocument
        )
        return .authority
    }

    func recordCommit(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        committedURL: URL,
        isPDF: Bool,
        currentIntent: TabMainFrameNavigationIntent,
        participants: TabMainFrameParticipantRegistry,
        effectClaims: TabMainFrameEffectLedger
    ) -> TabMainFrameCommitTransition {
        let webViewID = ObjectIdentifier(webView)
        guard let participant = participants.recordCommit(
            webView: webView,
            navigationID: navigationID,
            revision: currentIntent.revision,
            committedURL: committedURL,
            isPDF: isPDF
        ) else {
            return TabMainFrameCommitTransition(
                claim: TabMainFrameCommitSnapshotClaim(
                    role: .stale,
                    shouldPublishSharedEffects: false
                ),
                evidence: nil
            )
        }
        let evidence = participant.committedEvidence(webView: webView)
        let role = claimDocumentAuthority(
            for: participant,
            webViewID: webViewID,
            navigationID: navigationID
        )
        let didClaimSharedCommit = role.isAuthority
            && effectClaims.claimSharedCommit(
                identity: SharedCommitIdentity(
                    target: WebRuntimeNavigationIdentity(committedURL),
                    isPDF: isPDF
                )
            )
        return TabMainFrameCommitTransition(
            claim: TabMainFrameCommitSnapshotClaim(
                role: role,
                shouldPublishSharedEffects: didClaimSharedCommit
            ),
            evidence: evidence
        )
    }

    func claimAuthorityForTerminalSuccess(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        terminalURL: URL?,
        completesDocumentNavigation: Bool,
        currentIntent: TabMainFrameNavigationIntent,
        participants: TabMainFrameParticipantRegistry,
        effectClaims: TabMainFrameEffectLedger
    ) -> TabMainFrameTerminalTransition {
        let webViewID = ObjectIdentifier(webView)
        guard completesDocumentNavigation else {
            guard let participant = participants.activeEntry(
                webViewID: webViewID,
                navigationID: navigationID,
                revision: currentIntent.revision
            ) else {
                return TabMainFrameTerminalTransition(
                    role: .stale,
                    evidence: nil,
                    presentationURLToAdopt: nil
                )
            }
            let role = claimDocumentAuthority(
                for: participant,
                webViewID: webViewID,
                navigationID: navigationID
            )
            return TabMainFrameTerminalTransition(
                role: role,
                evidence: nil,
                presentationURLToAdopt: role.isAuthority ? terminalURL : nil
            )
        }

        guard let participant = participants.markTerminalSuccess(
            webView: webView,
            navigationID: navigationID,
            revision: currentIntent.revision,
            terminalURL: terminalURL
        ) else {
            return TabMainFrameTerminalTransition(
                role: .stale,
                evidence: nil,
                presentationURLToAdopt: nil
            )
        }
        let evidence = participant.committedEvidence(webView: webView)

        guard participant.documentGeneration == documentGeneration else {
            return TabMainFrameTerminalTransition(
                role: .participant,
                evidence: evidence,
                presentationURLToAdopt: nil
            )
        }
        if effectClaims.hasPublishedSharedFinish {
            return TabMainFrameTerminalTransition(
                role: lifecycleRole(
                    for: participant,
                    webViewID: webViewID,
                    navigationID: navigationID
                ),
                evidence: evidence,
                presentationURLToAdopt: nil
            )
        }
        if hasOtherCommittedAuthority(than: webViewID, for: participant) {
            return TabMainFrameTerminalTransition(
                role: .participant,
                evidence: evidence,
                presentationURLToAdopt: nil
            )
        }
        guard effectClaims.reserveTerminalSuccess(
            participantID: participant.id
        ) else {
            return TabMainFrameTerminalTransition(
                role: .participant,
                evidence: evidence,
                presentationURLToAdopt: nil
            )
        }
        installAuthority(
            revision: participant.revision,
            webViewID: webViewID,
            documentGeneration: participant.documentGeneration,
            navigationID: navigationID,
            hasCommittedDocument: true
        )
        return TabMainFrameTerminalTransition(
            role: .authority,
            evidence: evidence,
            presentationURLToAdopt: terminalURL
        )
    }

    func hasOtherCommittedAuthority(
        than webViewID: ObjectIdentifier,
        for participant: TabMainFrameParticipantRegistry.Entry
    ) -> Bool {
        guard let authority else { return false }
        return authority.revision == participant.revision
            && authority.documentGeneration == participant.documentGeneration
            && authority.webViewID != webViewID
            && authority.hasCommittedDocument
    }

    func isCommittedDocumentAuthority(
        _ participant: TabMainFrameParticipantRegistry.Entry,
        webViewID: ObjectIdentifier
    ) -> Bool {
        guard let authority else { return false }
        return authority.revision == participant.revision
            && authority.documentGeneration == participant.documentGeneration
            && authority.webViewID == webViewID
            && authority.hasCommittedDocument
    }

    func beginNewDocumentGeneration() {
        documentGeneration &+= 1
    }

    func reduceContinuation(
        participant: TabMainFrameParticipantRegistry.Entry,
        webViewID: ObjectIdentifier,
        targetURL: URL,
        kind: TabMainFrameContinuationKind,
        ownsAuthority: Bool
    ) -> ContinuationReduction {
        var participant = participant
        var becomesAuthority = kind != .clientRedirect && ownsAuthority
        var beganNewGeneration = false

        if kind == .clientRedirect {
            let key = RedirectGenerationKey(
                sourceGeneration: participant.documentGeneration,
                target: WebRuntimeNavigationIdentity(targetURL)
            )
            if let generation = redirectGenerationByKey[key] {
                participant.documentGeneration = generation
                becomesAuthority = generation == documentGeneration
                    && authority == nil
            } else if ownsAuthority,
                      participant.documentGeneration == documentGeneration {
                beginNewDocumentGeneration()
                redirectGenerationByKey[key] = documentGeneration
                participant.documentGeneration = documentGeneration
                becomesAuthority = true
                beganNewGeneration = true
            }
        }
        return ContinuationReduction(
            participant: participant,
            becomesAuthority: becomesAuthority,
            beganNewDocumentGeneration: beganNewGeneration
        )
    }

    func transferToContinuation(
        webViewID: ObjectIdentifier,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        targetURL: URL,
        kind: TabMainFrameContinuationKind,
        currentIntent: TabMainFrameNavigationIntent,
        participants: TabMainFrameParticipantRegistry,
        effectClaims: TabMainFrameEffectLedger
    ) -> (role: TabMainFrameLifecycleRole, targetURLToAdopt: URL?) {
        guard let existingParticipant = participants.entry(for: webViewID),
              existingParticipant.revision == currentIntent.revision else {
            return (.stale, nil)
        }
        let previousNavigationID: ObjectIdentifier?
        switch existingParticipant.phase {
        case .active(let navigationID):
            previousNavigationID = navigationID
        case .completed:
            previousNavigationID = nil
        }
        let ownsAuthority = ownsParticipant(
            existingParticipant,
            webViewID: webViewID,
            previousNavigationID: previousNavigationID
        )
        guard let preparedParticipant = participants.prepareContinuation(
            webViewID: webViewID,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            revision: currentIntent.revision
        ) else {
            return (.stale, nil)
        }

        let reduction = reduceContinuation(
            participant: preparedParticipant,
            webViewID: webViewID,
            targetURL: targetURL,
            kind: kind,
            ownsAuthority: ownsAuthority
        )
        if reduction.beganNewDocumentGeneration {
            effectClaims.resetForDocumentGeneration()
        }
        effectClaims.resetLocalStart(participantID: reduction.participant.id)
        let participant = participants.storeContinuation(
            reduction.participant,
            webViewID: webViewID,
            navigationID: navigationID,
            targetURL: targetURL,
            kind: kind
        )

        guard participant.documentGeneration == documentGeneration,
              reduction.becomesAuthority else {
            return (.participant, nil)
        }
        installAuthority(
            revision: participant.revision,
            webViewID: webViewID,
            documentGeneration: documentGeneration,
            navigationID: navigationID,
            hasCommittedDocument: participant.hasCommittedDocument
        )
        return (.authority, targetURL)
    }

    func promoteAuthorityCandidate(
        participants: TabMainFrameParticipantRegistry,
        effectClaims: TabMainFrameEffectLedger,
        preferredWebViewID: ObjectIdentifier?,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameAuthorityPromotion? {
        guard let candidate = selectPromotionCandidate(
            from: participants.entries,
            revision: currentIntent.revision,
            preferredWebViewID: preferredWebViewID
        ), let webView = candidate.participant.webViewReference.resolve() else {
            clearAuthority()
            return nil
        }

        var promotedParticipant = candidate.participant
        var targetURLToAdopt: URL?
        var migratedEvidence: [TabCommittedDocumentEvidence] = []
        if promotedParticipant.hasCommittedDocument,
           let committedDocumentURL = promotedParticipant.committedDocumentURL,
           let sharedCommitIdentity = effectClaims.sharedCommitIdentity,
           sharedCommitIdentity != SharedCommitIdentity(
               target: WebRuntimeNavigationIdentity(committedDocumentURL),
               isPDF: promotedParticipant.isPDFResponse ?? false
           ) {
            let previousGeneration = promotedParticipant.documentGeneration
            let promotedIdentity = SharedCommitIdentity(
                target: WebRuntimeNavigationIdentity(committedDocumentURL),
                isPDF: promotedParticipant.isPDFResponse ?? false
            )
            beginNewDocumentGeneration()
            effectClaims.resetForDocumentGeneration()
            migratedEvidence = participants.migrateCommittedReplicas(
                revision: currentIntent.revision,
                from: previousGeneration,
                to: documentGeneration,
                matching: promotedIdentity
            )
            promotedParticipant = participants.entry(for: candidate.webViewID)
                ?? promotedParticipant
            targetURLToAdopt = promotedParticipant.targetURL
        }

        let navigationID: ObjectIdentifier?
        let isCompleted: Bool
        switch promotedParticipant.phase {
        case .active(let candidateNavigationID):
            navigationID = candidateNavigationID
            isCompleted = false
        case .completed:
            navigationID = nil
            isCompleted = true
        }
        installAuthority(
            revision: currentIntent.revision,
            webViewID: candidate.webViewID,
            documentGeneration: promotedParticipant.documentGeneration,
            navigationID: navigationID,
            hasCommittedDocument: promotedParticipant.hasCommittedDocument,
            isCompleted: isCompleted
        )
        let continuation = TabMainFrameAuthorityContinuation(
            webView: webView,
            navigationID: navigationID,
            targetURL: promotedParticipant.targetURL,
            isPDF: promotedParticipant.isPDFResponse ?? false,
            isCompleted: isCompleted,
            needsSharedCommitEffects: promotedParticipant.hasCommittedDocument
                && effectClaims.hasPublishedSharedCommit == false,
            needsSharedFinishEffects: isCompleted
                && effectClaims.hasPublishedSharedFinish == false,
            revision: promotedParticipant.revision,
            documentGeneration: promotedParticipant.documentGeneration,
            participantID: promotedParticipant.id,
            webViewID: candidate.webViewID
        )
        return TabMainFrameAuthorityPromotion(
            continuation: continuation,
            targetURLToAdopt: targetURLToAdopt,
            migratedEvidence: migratedEvidence
        )
    }

    func rehydrate(
        _ candidates: [TabCommittedDocumentCandidate],
        preferredAuthorityWebViewID: ObjectIdentifier?,
        intent: TabMainFrameNavigationIntent,
        participants: TabMainFrameParticipantRegistry,
        effectClaims: TabMainFrameEffectLedger
    ) -> TabMainFrameRehydrationResult {
        let rehydration = participants.rehydrate(
            candidates,
            preferredAuthorityWebViewID: preferredAuthorityWebViewID,
            intent: intent,
            documentGeneration: documentGeneration
        )
        rehydration.replacedParticipantIDs.forEach(
            effectClaims.removeParticipant
        )
        for participant in rehydration.entries {
            _ = effectClaims.claimLocalStart(participantID: participant.id)
        }
        guard let authorityWebViewID = rehydration.authorityWebViewID,
              let participant = rehydration.authorityEntry,
              let committedURL = participant.committedDocumentURL else {
            return TabMainFrameRehydrationResult(
                evidence: rehydration.evidence,
                authorityWebViewID: nil
            )
        }
        installAuthority(
            revision: intent.revision,
            webViewID: authorityWebViewID,
            documentGeneration: documentGeneration,
            navigationID: nil,
            hasCommittedDocument: true,
            isCompleted: true
        )
        effectClaims.markRehydrated(identity: SharedCommitIdentity(
            target: WebRuntimeNavigationIdentity(committedURL),
            isPDF: participant.isPDFResponse ?? false
        ))
        return TabMainFrameRehydrationResult(
            evidence: rehydration.evidence,
            authorityWebViewID: authorityWebViewID
        )
    }

    func selectPromotionCandidate(
        from entries: [ObjectIdentifier: TabMainFrameParticipantRegistry.Entry],
        revision: UInt64,
        preferredWebViewID: ObjectIdentifier?
    ) -> CandidateSelection? {
        let candidates = entries.filter { _, participant in
            participant.revision == revision
                && participant.documentGeneration == documentGeneration
                && participant.webViewReference.resolve() != nil
        }
        guard let candidate = candidates.min(by: { lhs, rhs in
            candidateRank(lhs, preferredWebViewID: preferredWebViewID)
                < candidateRank(rhs, preferredWebViewID: preferredWebViewID)
        }) else {
            return nil
        }
        return CandidateSelection(
            webViewID: candidate.key,
            participant: candidate.value
        )
    }

    func isCurrentAuthority(
        _ continuation: TabMainFrameAuthorityContinuation,
        revision: UInt64,
        participants: TabMainFrameParticipantRegistry
    ) -> Bool {
        guard continuation.revision == revision,
              continuation.documentGeneration == documentGeneration,
              let participant = participants.entry(for: continuation.webViewID),
              participant.id == continuation.participantID,
              participant.documentGeneration == continuation.documentGeneration,
              let authority else {
            return false
        }
        return authority.revision == continuation.revision
            && authority.documentGeneration == continuation.documentGeneration
            && authority.webViewID == continuation.webViewID
            && authority.navigationID == continuation.navigationID
            && authority.isCompleted == continuation.isCompleted
    }

    private func candidateRank(
        _ candidate: Dictionary<
            ObjectIdentifier,
            TabMainFrameParticipantRegistry.Entry
        >.Element,
        preferredWebViewID: ObjectIdentifier?
    ) -> (recoverability: Int, preference: Int, identity: UInt) {
        let recoverability: Int
        switch candidate.value.phase {
        case .completed where candidate.value.hasCommittedDocument:
            recoverability = 0
        case .active where candidate.value.hasCommittedDocument:
            recoverability = 1
        case .active:
            recoverability = 2
        case .completed:
            recoverability = 4
        }
        return (
            recoverability,
            candidate.key == preferredWebViewID ? 0 : 1,
            UInt(bitPattern: candidate.key)
        )
    }
}
