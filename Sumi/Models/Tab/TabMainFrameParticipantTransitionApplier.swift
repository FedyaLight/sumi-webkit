import Foundation
import WebKit

/// Applies participant-local lifecycle plans. Authority decisions are produced
/// by the pure reducer; this object only commits a returned snapshot alongside
/// the exact registry/effect changes for that participant transition.
@MainActor
final class TabMainFrameParticipantTransitionApplier {
    private let participants: TabMainFrameParticipantRegistry
    private let authorityState: TabMainFrameAuthorityState
    private let authorityEffects: TabMainFrameAuthorityEffectLedger
    private let participantEffects: TabMainFrameParticipantEffectLedger

    init(
        participants: TabMainFrameParticipantRegistry,
        authorityState: TabMainFrameAuthorityState,
        authorityEffects: TabMainFrameAuthorityEffectLedger,
        participantEffects: TabMainFrameParticipantEffectLedger
    ) {
        self.participants = participants
        self.authorityState = authorityState
        self.authorityEffects = authorityEffects
        self.participantEffects = participantEffects
    }

    var documentGeneration: UInt64 {
        authorityState.snapshot.documentGeneration
    }

    func resetForNewIntent() {
        participants.removeAllForNewIntent().forEach(retireEffects)
        authorityState.apply(TabMainFrameAuthorityReducer.reset(
            authorityState.snapshot
        ))
        authorityEffects.resetForDocumentGeneration()
        participantEffects.resetForDocumentGeneration()
    }

    func hasParticipant(on webView: WKWebView, revision: UInt64) -> Bool {
        participants.contains(webView, revision: revision)
    }

    func hasLiveAuthority(revision: UInt64) -> Bool {
        let snapshot = authorityState.snapshot
        return TabMainFrameAuthorityReducer.hasLiveAuthority(
            in: snapshot,
            revision: revision,
            participant: snapshot.authority.flatMap {
                participants.entry(for: $0.webViewID)
            }
        )
    }

    func authority(
        revision: UInt64
    ) -> TabMainFrameIntentLedger.AuthorityState? {
        guard hasLiveAuthority(revision: revision),
              let authority = authorityState.snapshot.authority else {
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
            retireEffects(replacedParticipantID)
        }
        if binding.becomesAuthority {
            authorityState.apply(TabMainFrameAuthorityReducer.installAuthority(
                in: authorityState.snapshot,
                revision: binding.revision,
                webViewID: binding.webViewID,
                documentGeneration: binding.documentGeneration,
                navigationID: navigationID
            ))
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

    func activeAttemptOwner(
        on webView: WKWebView,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFramePendingAttemptOwner? {
        guard let entry = participants.entry(for: ObjectIdentifier(webView)),
              entry.webViewReference.matches(webView),
              entry.revision == currentIntent.revision,
              case .active = entry.phase else {
            return nil
        }
        return TabMainFramePendingAttemptOwner(
            intent: currentIntent,
            documentGeneration: entry.documentGeneration,
            participantID: entry.id,
            webViewID: ObjectIdentifier(webView),
            phase: .submitted
        )
    }

    func entry(for webViewID: ObjectIdentifier) -> TabMainFrameParticipantRegistry.Entry? {
        participants[webViewID]
    }

    func claimLocalStart(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameTransitionDecision<URL> {
        guard let participant = participants.exactActiveEntry(
            for: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            revision: currentIntent.revision
        ) else { return .stale }
        switch participantEffects.claimLocalStart(participantID: participant.id) {
        case .claimed: return .publish(participant.targetURL)
        case .alreadyClaimed: return .alreadyPublished(participant.targetURL)
        }
    }

    func acceptActiveTarget(
        _ targetURL: URL,
        webView: WKWebView,
        navigationID: ObjectIdentifier,
        revision: UInt64
    ) -> Bool {
        TabMainFrameTargetTransitionCommitter.commitActive(
            targetURL,
            webView: webView,
            navigationID: navigationID,
            revision: revision,
            participants: participants,
            state: authorityState
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
            retireEffects(replacedParticipantID)
        }
        authorityState.apply(TabMainFrameAuthorityReducer.installAuthority(
            in: authorityState.snapshot,
            revision: intent.revision,
            webViewID: webViewID,
            documentGeneration: documentGeneration,
            navigationID: navigationID
        ))
    }

    func lifecycleRole(
        from webView: WKWebView,
        navigationID: ObjectIdentifier?,
        isCurrent: Bool?,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameLifecycleRole {
        guard isCurrent != false, let navigationID else { return .stale }
        return lifecycleRole(
            webView: webView,
            navigationID: navigationID,
            currentIntent: currentIntent
        )
    }

    func prepareAuthorityForCommit(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameLifecycleRole {
        let webViewID = ObjectIdentifier(webView)
        guard let participant = participants.exactActiveEntry(
            for: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            revision: currentIntent.revision
        ) else { return .stale }
        return authorityState.apply(
            TabMainFrameAuthorityReducer.claimDocumentAuthority(
                in: authorityState.snapshot,
                for: participant,
                webViewID: webViewID,
                navigationID: navigationID
            )
        ) ?? .stale
    }

    func recordResponse(
        isPDF: Bool,
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameLifecycleRole {
        let webViewID = ObjectIdentifier(webView)
        guard let participant = participants.recordResponse(
            isPDF: isPDF,
            webView: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            revision: currentIntent.revision
        ) else { return .stale }
        return TabMainFrameAuthorityReducer.lifecycleRole(
            in: authorityState.snapshot,
            for: participant,
            webViewID: webViewID,
            navigationID: navigationID
        )
    }

    func responseIsPDF(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool? {
        participants.responseIsPDF(
            webView: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            revision: currentIntent.revision
        )
    }

    func departure(
        of webViews: [WKWebView],
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameTransitionOutput.LifecycleDeparture {
        let departingWebViewIDs = Set(webViews.compactMap { webView in
            participants.exactEntry(for: webView).map { _ in
                ObjectIdentifier(webView)
            }
        })
        let removed = participants.removeAll(webViews)
        removed.forEach { retireEffects($0.id) }
        let removedAuthority = authorityState.apply(
            TabMainFrameAuthorityReducer.removeAuthority(
                in: authorityState.snapshot,
                matching: departingWebViewIDs,
                revision: currentIntent.revision
            )
        ) ?? false
        return TabMainFrameTransitionOutput.LifecycleDeparture(
            removedParticipant: removed.isEmpty == false,
            wasAuthoritative: removedAuthority
        )
    }

    func abortNavigation(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameTransitionOutput.ParticipantAbort {
        let webViewID = ObjectIdentifier(webView)
        let isAuthoritative = TabMainFrameAuthorityReducer.isExactAuthority(
            in: authorityState.snapshot,
            webViewID: webViewID,
            navigationID: navigationID,
            revision: currentIntent.revision
        )
        guard let participant = participants.removeExactActiveNavigation(
            webView: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            revision: currentIntent.revision
        ) else { return .ignored }
        retireEffects(participant.id)
        guard isAuthoritative else { return .participant }
        authorityState.apply(TabMainFrameAuthorityReducer.clearAuthority(
            in: authorityState.snapshot
        ))
        return .authority
    }

    private func lifecycleRole(
        webView: WKWebView,
        navigationID: ObjectIdentifier,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameLifecycleRole {
        let webViewID = ObjectIdentifier(webView)
        guard let participant = participants.exactEntry(for: webView),
              participant.phase == .active(navigationID: navigationID),
              participant.revision == currentIntent.revision
        else { return .stale }
        return TabMainFrameAuthorityReducer.lifecycleRole(
            in: authorityState.snapshot,
            for: participant,
            webViewID: webViewID,
            navigationID: navigationID
        )
    }

    private func retireEffects(_ participantID: UUID) {
        participantEffects.removeParticipant(participantID)
        authorityEffects.removeParticipant(participantID)
    }
}
