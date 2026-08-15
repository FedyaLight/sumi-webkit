import Foundation
import SumiWebRuntime
import WebKit

/// Pure reducer for logical main-frame authority. It never stores state and
/// never reaches into participant or effect ledgers: callers provide one
/// immutable snapshot and atomically apply the returned next-state plan.
enum TabMainFrameAuthorityReducer {
    typealias Snapshot = TabMainFrameAuthoritySnapshot
    typealias Authority = Snapshot.Value
    typealias SharedCommitIdentity =
        TabMainFrameAuthorityEffectLedger.SharedCommitIdentity

    struct ContinuationReduction {
        var participant: TabMainFrameParticipantRegistry.Entry
        let becomesAuthority: Bool
        let beganNewDocumentGeneration: Bool
    }

    struct CandidateSelection {
        let webViewID: ObjectIdentifier
        let participant: TabMainFrameParticipantRegistry.Entry
    }

    struct PromotionPreparation {
        struct Migration {
            let previousGeneration: UInt64
            let identity: SharedCommitIdentity
        }

        let migration: Migration?
        let targetURLToAdopt: URL?
    }

    struct TerminalSuccessReduction {
        let role: TabMainFrameLifecycleRole
        let presentationURLToAdopt: URL?
    }

    static func reset(
        _ snapshot: Snapshot
    ) -> TabMainFrameAuthorityPlan<Void> {
        var next = replacingAuthority(in: snapshot, with: nil)
        next.documentGeneration = 0
        next.redirectGenerationByKey.removeAll()
        return TabMainFrameAuthorityPlan(nextSnapshot: next, output: ())
    }

    static func installAuthority(
        in snapshot: Snapshot,
        revision: UInt64,
        webViewID: ObjectIdentifier,
        documentGeneration: UInt64,
        navigationID: ObjectIdentifier?,
        hasCommittedDocument: Bool = false,
        isCompleted: Bool = false
    ) -> TabMainFrameAuthorityPlan<Void> {
        let authority = Authority(
            revision: revision,
            webViewID: webViewID,
            documentGeneration: documentGeneration,
            navigationID: navigationID,
            hasCommittedDocument: hasCommittedDocument,
            isCompleted: isCompleted
        )
        return TabMainFrameAuthorityPlan(
            nextSnapshot: replacingAuthority(in: snapshot, with: authority),
            output: ()
        )
    }

    static func clearAuthority(
        in snapshot: Snapshot
    ) -> TabMainFrameAuthorityPlan<Void> {
        TabMainFrameAuthorityPlan(
            nextSnapshot: replacingAuthority(in: snapshot, with: nil),
            output: ()
        )
    }

    static func removeAuthority(
        in snapshot: Snapshot,
        matching webViewIDs: Set<ObjectIdentifier>,
        revision: UInt64
    ) -> TabMainFrameAuthorityPlan<Bool> {
        guard snapshot.authority?.revision == revision,
              snapshot.authority.map({ webViewIDs.contains($0.webViewID) }) == true else {
            return TabMainFrameAuthorityPlan(
                nextSnapshot: snapshot,
                output: false
            )
        }
        return TabMainFrameAuthorityPlan(
            nextSnapshot: replacingAuthority(in: snapshot, with: nil),
            output: true
        )
    }

    static func hasLiveAuthority(
        in snapshot: Snapshot,
        revision: UInt64,
        participant: TabMainFrameParticipantRegistry.Entry?
    ) -> Bool {
        guard let authority = snapshot.authority,
              authority.revision == revision,
              authority.documentGeneration == snapshot.documentGeneration,
              let participant,
              participant.revision == revision,
              participant.documentGeneration == snapshot.documentGeneration,
              participant.webViewReference.resolve() != nil else {
            return false
        }
        return true
    }

    static func isExactAuthority(
        in snapshot: Snapshot,
        webViewID: ObjectIdentifier,
        navigationID: ObjectIdentifier,
        revision: UInt64
    ) -> Bool {
        guard let authority = snapshot.authority else { return false }
        return authority.revision == revision
            && authority.documentGeneration == snapshot.documentGeneration
            && authority.webViewID == webViewID
            && authority.navigationID == navigationID
    }

    static func ownsParticipant(
        in snapshot: Snapshot,
        _ participant: TabMainFrameParticipantRegistry.Entry,
        webViewID: ObjectIdentifier,
        previousNavigationID: ObjectIdentifier?
    ) -> Bool {
        guard let authority = snapshot.authority,
              authority.revision == participant.revision,
              authority.webViewID == webViewID else {
            return false
        }
        if let previousNavigationID {
            return authority.navigationID == previousNavigationID
        }
        return authority.navigationID == nil && authority.isCompleted
    }

    static func markCommitted(
        in snapshot: Snapshot
    ) -> TabMainFrameAuthorityPlan<Void> {
        guard var authority = snapshot.authority,
              authority.hasCommittedDocument == false else {
            return TabMainFrameAuthorityPlan(nextSnapshot: snapshot, output: ())
        }
        authority.hasCommittedDocument = true
        return TabMainFrameAuthorityPlan(
            nextSnapshot: replacingAuthority(in: snapshot, with: authority),
            output: ()
        )
    }

    static func markCompleted(
        in snapshot: Snapshot
    ) -> TabMainFrameAuthorityPlan<Void> {
        guard var authority = snapshot.authority else {
            return TabMainFrameAuthorityPlan(nextSnapshot: snapshot, output: ())
        }
        authority.navigationID = nil
        authority.isCompleted = true
        return TabMainFrameAuthorityPlan(
            nextSnapshot: replacingAuthority(in: snapshot, with: authority),
            output: ()
        )
    }

    static func noteTargetMutation(
        in snapshot: Snapshot,
        webViewID: ObjectIdentifier,
        revision: UInt64
    ) -> TabMainFrameAuthorityPlan<Void> {
        guard snapshot.authority?.webViewID == webViewID,
              snapshot.authority?.revision == revision else {
            return TabMainFrameAuthorityPlan(nextSnapshot: snapshot, output: ())
        }
        var next = snapshot
        next.authorityEpoch &+= 1
        return TabMainFrameAuthorityPlan(nextSnapshot: next, output: ())
    }

    static func lifecycleRole(
        in snapshot: Snapshot,
        for participant: TabMainFrameParticipantRegistry.Entry,
        webViewID: ObjectIdentifier,
        navigationID: ObjectIdentifier
    ) -> TabMainFrameLifecycleRole {
        isExactAuthority(
            in: snapshot,
            webViewID: webViewID,
            navigationID: navigationID,
            revision: participant.revision
        ) ? .authority : .participant
    }

    static func claimDocumentAuthority(
        in snapshot: Snapshot,
        for participant: TabMainFrameParticipantRegistry.Entry,
        webViewID: ObjectIdentifier,
        navigationID: ObjectIdentifier
    ) -> TabMainFrameAuthorityPlan<TabMainFrameLifecycleRole> {
        guard participant.documentGeneration == snapshot.documentGeneration else {
            return TabMainFrameAuthorityPlan(
                nextSnapshot: snapshot,
                output: .participant
            )
        }
        if isExactAuthority(
            in: snapshot,
            webViewID: webViewID,
            navigationID: navigationID,
            revision: participant.revision
        ) {
            let committed = participant.hasCommittedDocument
                ? markCommitted(in: snapshot).nextSnapshot
                : snapshot
            return TabMainFrameAuthorityPlan(
                nextSnapshot: committed,
                output: .authority
            )
        }
        if let authority = snapshot.authority,
           authority.revision == participant.revision,
           authority.hasCommittedDocument {
            return TabMainFrameAuthorityPlan(
                nextSnapshot: snapshot,
                output: .participant
            )
        }
        let installed = installAuthority(
            in: snapshot,
            revision: participant.revision,
            webViewID: webViewID,
            documentGeneration: participant.documentGeneration,
            navigationID: navigationID,
            hasCommittedDocument: participant.hasCommittedDocument
        )
        return TabMainFrameAuthorityPlan(
            nextSnapshot: installed.nextSnapshot,
            output: .authority
        )
    }

    static func reduceCommit(
        in snapshot: Snapshot,
        previousParticipant: TabMainFrameParticipantRegistry.Entry?,
        participant: TabMainFrameParticipantRegistry.Entry,
        webViewID: ObjectIdentifier,
        navigationID: ObjectIdentifier,
        revision: UInt64
    ) -> TabMainFrameAuthorityPlan<TabMainFrameLifecycleRole> {
        let claim = claimDocumentAuthority(
            in: snapshot,
            for: participant,
            webViewID: webViewID,
            navigationID: navigationID
        )
        let changedCommittedDocument = previousParticipant?.committedDocumentURL != participant.committedDocumentURL
            || previousParticipant?.targetURL != participant.targetURL
            || previousParticipant?.isPDFResponse != participant.isPDFResponse
        let next = claim.output.isAuthority
            && previousParticipant?.hasCommittedDocument == true
            && changedCommittedDocument
            ? noteTargetMutation(
                in: claim.nextSnapshot,
                webViewID: webViewID,
                revision: revision
            ).nextSnapshot
            : claim.nextSnapshot
        return TabMainFrameAuthorityPlan(
            nextSnapshot: next,
            output: claim.output
        )
    }

    static func reduceTerminalSuccess(
        in snapshot: Snapshot,
        participant: TabMainFrameParticipantRegistry.Entry,
        webViewID: ObjectIdentifier,
        navigationID: ObjectIdentifier,
        terminalURL: URL?,
        sharedFinishPublished: Bool
    ) -> TabMainFrameAuthorityPlan<TerminalSuccessReduction> {
        let terminalPlan: (Snapshot, TabMainFrameLifecycleRole) -> TabMainFrameAuthorityPlan<TerminalSuccessReduction> = {
            TabMainFrameAuthorityPlan(
                nextSnapshot: $0,
                output: TerminalSuccessReduction(role: $1, presentationURLToAdopt: nil)
            )
        }
        guard participant.documentGeneration == snapshot.documentGeneration else {
            return terminalPlan(snapshot, .participant)
        }
        if sharedFinishPublished {
            let role = lifecycleRole(
                in: snapshot,
                for: participant,
                webViewID: webViewID,
                navigationID: navigationID
            )
            let next = role.isAuthority
                ? markCompleted(in: snapshot).nextSnapshot
                : snapshot
            return terminalPlan(next, role)
        }
        if hasOtherCommittedAuthority(
            in: snapshot,
            than: webViewID,
            for: participant
        ) {
            return terminalPlan(snapshot, .participant)
        }
        var next: Snapshot
        if isExactAuthority(
            in: snapshot,
            webViewID: webViewID,
            navigationID: navigationID,
            revision: participant.revision
        ) {
            next = markCommitted(in: snapshot).nextSnapshot
        } else {
            next = installAuthority(
                in: snapshot,
                revision: participant.revision,
                webViewID: webViewID,
                documentGeneration: participant.documentGeneration,
                navigationID: navigationID,
                hasCommittedDocument: true
            ).nextSnapshot
        }
        next = markCompleted(in: next).nextSnapshot
        return TabMainFrameAuthorityPlan(
            nextSnapshot: next,
            output: TerminalSuccessReduction(
                role: .authority,
                presentationURLToAdopt: terminalURL
            )
        )
    }

    static func reduceSameDocumentSuccess(
        in snapshot: Snapshot,
        previousParticipant: TabMainFrameParticipantRegistry.Entry,
        participant: TabMainFrameParticipantRegistry.Entry,
        webViewID: ObjectIdentifier,
        navigationID: ObjectIdentifier
    ) -> TabMainFrameAuthorityPlan<TabMainFrameLifecycleRole> {
        let claim = claimDocumentAuthority(
            in: snapshot,
            for: participant,
            webViewID: webViewID,
            navigationID: navigationID
        )
        guard claim.output.isAuthority else {
            return claim
        }
        let targeted = previousParticipant.targetURL != participant.targetURL
            ? noteTargetMutation(
                in: claim.nextSnapshot,
                webViewID: webViewID,
                revision: participant.revision
            ).nextSnapshot
            : claim.nextSnapshot
        return TabMainFrameAuthorityPlan(
            nextSnapshot: markCompleted(in: targeted).nextSnapshot,
            output: .authority
        )
    }

    static func hasOtherCommittedAuthority(
        in snapshot: Snapshot,
        than webViewID: ObjectIdentifier,
        for participant: TabMainFrameParticipantRegistry.Entry
    ) -> Bool {
        guard let authority = snapshot.authority else { return false }
        return authority.revision == participant.revision
            && authority.documentGeneration == participant.documentGeneration
            && authority.webViewID != webViewID
            && authority.hasCommittedDocument
    }

    static func isCommittedDocumentAuthority(
        in snapshot: Snapshot,
        _ participant: TabMainFrameParticipantRegistry.Entry,
        webViewID: ObjectIdentifier
    ) -> Bool {
        guard let authority = snapshot.authority else { return false }
        return authority.revision == participant.revision
            && authority.documentGeneration == participant.documentGeneration
            && authority.webViewID == webViewID
            && authority.hasCommittedDocument
    }

    static func reduceContinuation(
        in snapshot: Snapshot,
        participant: TabMainFrameParticipantRegistry.Entry,
        webViewID: ObjectIdentifier,
        navigationID: ObjectIdentifier,
        targetURL: URL,
        kind: TabMainFrameContinuationKind,
        ownsAuthority: Bool
    ) -> TabMainFrameAuthorityPlan<ContinuationReduction> {
        var next = snapshot
        var participant = participant
        var becomesAuthority = kind != .clientRedirect && ownsAuthority
        var beganNewGeneration = false

        if kind == .clientRedirect {
            let key = Snapshot.RedirectGenerationKey(
                sourceGeneration: participant.documentGeneration,
                target: WebRuntimeNavigationIdentity(targetURL)
            )
            if let generation = next.redirectGenerationByKey[key] {
                participant.documentGeneration = generation
                becomesAuthority = generation == next.documentGeneration
                    && next.authority == nil
            } else if ownsAuthority,
                      participant.documentGeneration == next.documentGeneration {
                next.documentGeneration &+= 1
                next.redirectGenerationByKey[key] = next.documentGeneration
                participant.documentGeneration = next.documentGeneration
                becomesAuthority = true
                beganNewGeneration = true
            }
        } else if kind == .requestRewrite,
                  participant.hasCommittedDocument,
                  ownsAuthority,
                  participant.documentGeneration == next.documentGeneration {
            next.documentGeneration &+= 1
            participant.documentGeneration = next.documentGeneration
            becomesAuthority = true
            beganNewGeneration = true
        }
        participant.targetURL = targetURL
        participant.phase = .active(navigationID: navigationID)
        if kind == .clientRedirect || beganNewGeneration {
            participant.hasCommittedDocument = false
            participant.committedDocumentURL = nil
            participant.isPDFResponse = nil
        }
        if becomesAuthority,
           participant.documentGeneration == next.documentGeneration {
            next = installAuthority(
                in: next,
                revision: participant.revision,
                webViewID: webViewID,
                documentGeneration: participant.documentGeneration,
                navigationID: navigationID,
                hasCommittedDocument: participant.hasCommittedDocument
            ).nextSnapshot
        }
        return TabMainFrameAuthorityPlan(
            nextSnapshot: next,
            output: ContinuationReduction(
                participant: participant,
                becomesAuthority: becomesAuthority,
                beganNewDocumentGeneration: beganNewGeneration
            )
        )
    }

    static func preparePromotion(
        in snapshot: Snapshot,
        of participant: TabMainFrameParticipantRegistry.Entry,
        sharedCommitIdentity: SharedCommitIdentity?
    ) -> TabMainFrameAuthorityPlan<PromotionPreparation> {
        guard participant.hasCommittedDocument,
              let committedDocumentURL = participant.committedDocumentURL,
              let sharedCommitIdentity,
              sharedCommitIdentity != SharedCommitIdentity(
                  target: WebRuntimeNavigationIdentity(committedDocumentURL),
                  isPDF: participant.isPDFResponse ?? false
              ) else {
            return TabMainFrameAuthorityPlan(
                nextSnapshot: snapshot,
                output: PromotionPreparation(
                    migration: nil,
                    targetURLToAdopt: nil
                )
            )
        }
        let identity = SharedCommitIdentity(
            target: WebRuntimeNavigationIdentity(committedDocumentURL),
            isPDF: participant.isPDFResponse ?? false
        )
        var next = snapshot
        next.documentGeneration &+= 1
        return TabMainFrameAuthorityPlan(
            nextSnapshot: next,
            output: PromotionPreparation(
                migration: PromotionPreparation.Migration(
                    previousGeneration: participant.documentGeneration,
                    identity: identity
                ),
                targetURLToAdopt: participant.targetURL
            )
        )
    }

    static func installPromotion(
        in snapshot: Snapshot,
        candidate: CandidateSelection,
        participant: TabMainFrameParticipantRegistry.Entry,
        webView: WKWebView,
        targetURLToAdopt: URL?,
        migratedEvidence: [TabCommittedDocumentEvidence],
        hasPublishedSharedCommit: Bool,
        hasPublishedSharedFinish: Bool
    ) -> TabMainFrameAuthorityPlan<TabMainFrameTransitionOutput.AuthorityPromotion> {
        let navigationID: ObjectIdentifier?
        let isCompleted: Bool
        let completionKind: TabMainFrameCompletionKind?
        switch participant.phase {
        case .active(let candidateNavigationID):
            navigationID = candidateNavigationID
            isCompleted = false
            completionKind = nil
        case .completed(_, let kind):
            navigationID = nil
            isCompleted = true
            completionKind = kind
        }
        let installed = installAuthority(
            in: snapshot,
            revision: participant.revision,
            webViewID: candidate.webViewID,
            documentGeneration: participant.documentGeneration,
            navigationID: navigationID,
            hasCommittedDocument: participant.hasCommittedDocument,
            isCompleted: isCompleted
        )
        let continuation = TabMainFrameAuthorityContinuation(
            webView: webView,
            navigationID: navigationID,
            targetURL: participant.targetURL,
            isPDF: participant.isPDFResponse ?? false,
            isCompleted: isCompleted,
            hasCommittedDocument: participant.hasCommittedDocument,
            needsSharedCommitEffects: participant.hasCommittedDocument
                && hasPublishedSharedCommit == false,
            needsSharedFinishEffects: isCompleted
                && completionKind == .document
                && hasPublishedSharedFinish == false,
            revision: participant.revision,
            documentGeneration: participant.documentGeneration,
            participantID: participant.id,
            webViewID: candidate.webViewID,
            source: .lifecycle(
                authorityEpoch: installed.nextSnapshot.authorityEpoch
            )
        )
        return TabMainFrameAuthorityPlan(
            nextSnapshot: installed.nextSnapshot,
            output: TabMainFrameTransitionOutput.AuthorityPromotion(
                continuation: continuation,
                targetURLToAdopt: targetURLToAdopt,
                migratedEvidence: migratedEvidence
            )
        )
    }

    static func selectPromotionCandidate(
        in snapshot: Snapshot,
        from entries: [ObjectIdentifier: TabMainFrameParticipantRegistry.Entry],
        revision: UInt64,
        preferredWebViewID: ObjectIdentifier?
    ) -> CandidateSelection? {
        let candidates = entries.filter { _, participant in
            participant.revision == revision
                && participant.documentGeneration == snapshot.documentGeneration
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

    static func isCurrentAuthority(
        in snapshot: Snapshot,
        _ continuation: TabMainFrameAuthorityContinuation,
        revision: UInt64,
        participant: TabMainFrameParticipantRegistry.Entry?
    ) -> Bool {
        guard case .lifecycle(let continuationEpoch) = continuation.source,
              snapshot.authorityEpoch == continuationEpoch,
              continuation.revision == revision,
              continuation.documentGeneration == snapshot.documentGeneration,
              let participant,
              participant.id == continuation.participantID,
              participant.revision == continuation.revision,
              participant.documentGeneration == continuation.documentGeneration,
              participant.targetURL == continuation.targetURL,
              (participant.isPDFResponse ?? false) == continuation.isPDF,
              participant.webViewReference.matches(continuation.webView),
              continuationPhaseMatches(
                  continuation,
                  participant: participant
              ),
              let authority = snapshot.authority else {
            return false
        }
        return authority.revision == continuation.revision
            && authority.documentGeneration == continuation.documentGeneration
            && authority.webViewID == continuation.webViewID
            && authority.navigationID == continuation.navigationID
            && authority.isCompleted == continuation.isCompleted
    }

    private static func replacingAuthority(
        in snapshot: Snapshot,
        with replacement: Authority?
    ) -> Snapshot {
        var next = snapshot
        if snapshot.authority != replacement {
            next.authorityEpoch &+= 1
        }
        next.authority = replacement
        return next
    }

    private static func continuationPhaseMatches(
        _ continuation: TabMainFrameAuthorityContinuation,
        participant: TabMainFrameParticipantRegistry.Entry
    ) -> Bool {
        if continuation.isCompleted {
            guard case .completed = participant.phase else { return false }
            return continuation.navigationID == nil
        }
        guard let navigationID = continuation.navigationID else { return false }
        return participant.phase == .active(navigationID: navigationID)
    }

    private static func candidateRank(
        _ candidate: [ObjectIdentifier: TabMainFrameParticipantRegistry.Entry].Element,
        preferredWebViewID: ObjectIdentifier?
    ) -> (recoverability: Int, preference: Int, identity: UInt) {
        let recoverability: Int
        switch candidate.value.phase {
        case .completed(_, .document)
            where candidate.value.hasCommittedDocument:
            recoverability = 0
        case .completed(_, .sameDocument)
            where candidate.value.hasCommittedDocument:
            recoverability = 1
        case .active where candidate.value.hasCommittedDocument:
            recoverability = 2
        case .active:
            recoverability = 3
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
