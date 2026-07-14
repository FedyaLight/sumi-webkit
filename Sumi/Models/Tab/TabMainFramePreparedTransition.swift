/// Value-only transitions prepared from one exact registry source and one
/// authority snapshot. Reducer plans never cross this boundary from callers.
@MainActor
enum TabMainFramePreparedTransition {
    struct Settlement<Output, EffectPlan, Lease> {
        let participant: TabMainFrameParticipantRegistry.EntryMutationPlan
        let authority: TabMainFrameAuthorityPlan<Output>
        let effect: EffectPlan?
        let lease: Lease?

        fileprivate init(
            participant: TabMainFrameParticipantRegistry.EntryMutationPlan,
            authority: TabMainFrameAuthorityPlan<Output>,
            effect: EffectPlan?,
            lease: Lease?
        ) {
            self.participant = participant
            self.authority = authority
            self.effect = effect
            self.lease = lease
        }
    }

    typealias Document = Settlement<
        TabMainFrameLifecycleRole,
        TabMainFrameAuthorityEffectLedger.MutationPlan<TabMainFrameCommitPermit?>,
        TabMainFrameActiveAuthorityLease
    >
    typealias Terminal = Settlement<
        TabMainFrameAuthorityReducer.TerminalSuccessReduction,
        TabMainFrameAuthorityEffectLedger.MutationPlan<TabMainFrameFinishPermit?>,
        TabMainFrameCompletedAuthorityLease
    >
    typealias SameDocument = Settlement<
        TabMainFrameLifecycleRole,
        TabMainFrameParticipantEffectLedger.MutationPlan<TabMainFrameSameDocumentPermit?>,
        TabMainFrameCompletedAuthorityLease
    >

    struct Continuation {
        let participant: TabMainFrameParticipantRegistry.EntryMutationPlan
        let authority: TabMainFrameAuthorityPlan<TabMainFrameAuthorityReducer.ContinuationReduction>
        let authorityEffect: TabMainFrameAuthorityEffectLedger.MutationPlan<Void>?
        let participantEffect: TabMainFrameParticipantEffectLedger.MutationPlan<Void>
    }

    static func document(
        participant plan: TabMainFrameParticipantRegistry.EntryMutationPlan,
        source: TabMainFrameParticipantRegistry.Entry,
        state: TabMainFrameAuthorityState,
        effects: TabMainFrameAuthorityEffectLedger
    ) -> Document? {
        let entry = plan.nextEntry
        guard plan.hasSourceFacts(source),
              case .active(let navigationID) = entry.phase,
              entry.hasCommittedDocument,
              entry.committedDocumentURL == entry.targetURL,
              let isPDF = entry.isPDFResponse else { return nil }
        let authority = TabMainFrameAuthorityReducer.reduceCommit(
            in: state.snapshot,
            previousParticipant: source,
            participant: entry,
            webViewID: entry.webViewReference.identifier,
            navigationID: navigationID,
            revision: entry.revision
        )
        guard authority.output.isParticipant else { return nil }
        let lease = state.activeLease(in: authority.nextSnapshot, participant: entry)
        guard authority.output.isAuthority == (lease != nil) else { return nil }
        return Document(
            participant: plan,
            authority: authority,
            effect: authority.output.isAuthority
                ? effects.prepareSharedCommit(identity: .init(
                    target: .init(entry.targetURL),
                    isPDF: isPDF
                ))
                : nil,
            lease: lease
        )
    }

    static func terminal(
        participant plan: TabMainFrameParticipantRegistry.EntryMutationPlan,
        source: TabMainFrameParticipantRegistry.Entry,
        terminalURL: URL?,
        state: TabMainFrameAuthorityState,
        effects: TabMainFrameAuthorityEffectLedger
    ) -> Terminal? {
        let entry = plan.nextEntry
        guard plan.hasSourceFacts(source),
              case .completed(let navigationID?, .document) = entry.phase,
              entry.hasCommittedDocument else { return nil }
        let authority = TabMainFrameAuthorityReducer.reduceTerminalSuccess(
            in: state.snapshot,
            participant: entry,
            webViewID: entry.webViewReference.identifier,
            navigationID: navigationID,
            terminalURL: terminalURL,
            sharedFinishPublished: effects.hasPublishedSharedFinish
        )
        guard authority.output.role.isParticipant else { return nil }
        let lease = state.completedLease(in: authority.nextSnapshot, participant: entry)
        guard authority.output.role.isAuthority == (lease != nil) else { return nil }
        return Terminal(
            participant: plan,
            authority: authority,
            effect: authority.output.role.isAuthority
                ? effects.prepareSharedFinish(participantID: entry.id)
                : nil,
            lease: lease
        )
    }

    static func sameDocument(
        participant plan: TabMainFrameParticipantRegistry.EntryMutationPlan,
        source: TabMainFrameParticipantRegistry.Entry,
        state: TabMainFrameAuthorityState,
        effects: TabMainFrameParticipantEffectLedger
    ) -> SameDocument? {
        let entry = plan.nextEntry
        guard plan.hasSourceFacts(source),
              case .completed(let navigationID?, .sameDocument) = entry.phase else {
            return nil
        }
        let authority = TabMainFrameAuthorityReducer.reduceSameDocumentSuccess(
            in: state.snapshot,
            previousParticipant: source,
            participant: entry,
            webViewID: entry.webViewReference.identifier,
            navigationID: navigationID
        )
        guard authority.output.isParticipant else { return nil }
        let lease = state.completedLease(in: authority.nextSnapshot, participant: entry)
        guard authority.output.isAuthority == (lease != nil) else { return nil }
        return SameDocument(
            participant: plan,
            authority: authority,
            effect: authority.output.isAuthority
                ? effects.prepareSameDocument(participantID: entry.id)
                : nil,
            lease: lease
        )
    }

    static func continuation(
        participant plan: TabMainFrameParticipantRegistry.EntryMutationPlan,
        source: TabMainFrameParticipantRegistry.Entry,
        targetURL: URL,
        kind: TabMainFrameContinuationKind,
        ownsAuthority: Bool,
        state: TabMainFrameAuthorityState,
        effects: TabMainFrameAuthorityEffectLedger,
        participantEffects: TabMainFrameParticipantEffectLedger
    ) -> Continuation? {
        guard plan.hasSourceFacts(source),
              let navigationID = plan.nextEntry.navigationIdentityReference?.identifier,
              plan.nextEntry.navigationIdentityReference?.resolve() != nil else {
            return nil
        }
        let authority = TabMainFrameAuthorityReducer.reduceContinuation(
            in: state.snapshot,
            participant: plan.nextEntry,
            webViewID: plan.nextEntry.webViewReference.identifier,
            navigationID: navigationID,
            targetURL: targetURL,
            kind: kind,
            ownsAuthority: ownsAuthority
        )
        var participant = plan
        participant.nextEntry = authority.output.participant
        let reduction = authority.output
        guard participant.nextEntry.hasSameFacts(as: reduction.participant),
              TabMainFrameAuthorityReducer.isExactAuthority(
                  in: authority.nextSnapshot,
                  webViewID: reduction.participant.webViewReference.identifier,
                  navigationID: navigationID,
                  revision: reduction.participant.revision
              ) == reduction.becomesAuthority else { return nil }
        return Continuation(
            participant: participant,
            authority: authority,
            authorityEffect: reduction.beganNewDocumentGeneration
                ? effects.prepareReset()
                : nil,
            participantEffect: participantEffects.prepareContinuation(
                participantID: reduction.participant.id,
                resetsDocumentGeneration: reduction.beganNewDocumentGeneration
            )
        )
    }
}
