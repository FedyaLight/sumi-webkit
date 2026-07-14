import Foundation
import SumiWebRuntime
import WebKit

/// Exact physical main-frame participants keyed by WebView identity. This is
/// the sole owner of participant records and retired WKNavigation lifetimes.
@MainActor
final class TabMainFrameParticipantRegistry {
    typealias WeakWebViewReference = WebViewIdentityWitness
    typealias WeakNavigationIdentityReference = WeakIdentityWitness<AnyObject>

    enum Phase: Equatable {
        case active(navigationID: ObjectIdentifier)
        case completed(
            navigationID: ObjectIdentifier?,
            kind: TabMainFrameCompletionKind
        )
    }

    struct Entry {
        let id: UUID
        let webViewReference: WeakWebViewReference
        let revision: UInt64
        var documentGeneration: UInt64
        var targetURL: URL
        var phase: Phase
        var hasCommittedDocument = false
        var committedDocumentURL: URL?
        var isPDFResponse: Bool?
        var navigationIdentityReference: WeakNavigationIdentityReference?

        func hasSameFacts(as other: Entry) -> Bool {
            id == other.id
                && webViewReference.identifier == other.webViewReference.identifier
                && webViewReference.resolve() === other.webViewReference.resolve()
                && revision == other.revision
                && documentGeneration == other.documentGeneration
                && targetURL == other.targetURL
                && phase == other.phase
                && hasCommittedDocument == other.hasCommittedDocument
                && committedDocumentURL == other.committedDocumentURL
                && isPDFResponse == other.isPDFResponse
                && navigationIdentityReference?.identifier == other.navigationIdentityReference?.identifier
                && navigationIdentityReference?.resolve() === other.navigationIdentityReference?.resolve()
        }

        func matches(_ lease: TabMainFrameActiveAuthorityLease) -> Bool {
            id == lease.participantID
                && revision == lease.revision
                && documentGeneration == lease.documentGeneration
                && phase == .active(navigationID: lease.navigationID)
                && targetURL == lease.targetURL
                && webViewReference.resolve() != nil
        }

        func matches(_ lease: TabMainFrameCompletedAuthorityLease) -> Bool {
            id == lease.participantID
                && revision == lease.revision
                && documentGeneration == lease.documentGeneration
                && phase == .completed(
                    navigationID: lease.navigationID,
                    kind: lease.completionKind
                )
                && hasCommittedDocument == lease.hasCommittedDocument
                && committedDocumentURL == lease.committedDocumentURL
                && targetURL == lease.presentationURL
                && (isPDFResponse ?? false) == lease.isPDF
                && webViewReference.resolve() != nil
        }

        func committedEvidence(webView: WKWebView) -> TabCommittedDocumentEvidence? {
            guard let committedDocumentURL else { return nil }
            return TabCommittedDocumentEvidence(
                webView: webView,
                revision: revision,
                documentGeneration: documentGeneration,
                participantID: id,
                committedURL: committedDocumentURL,
                presentationURL: targetURL,
                isPDF: isPDFResponse ?? false
            )
        }
    }

    struct InstallResult {
        let replacedParticipantID: UUID?
    }

    struct Rehydration {
        let entries: [Entry]
        let evidence: [TabCommittedDocumentEvidence]
        let authorityWebViewID: ObjectIdentifier?
        let authorityEntry: Entry?
        let replacedParticipantIDs: [UUID]
    }

    struct EntryMutationPlan {
        fileprivate let sourceEntry: Entry
        fileprivate let expectedRevision: UInt64
        fileprivate let webViewID: ObjectIdentifier
        fileprivate let expectedParticipantID: UUID
        fileprivate let expectedWebViewReference: WeakWebViewReference
        var nextEntry: Entry
        fileprivate let retiredNavigationID: ObjectIdentifier?
        fileprivate let retiredNavigationReference: WeakNavigationIdentityReference?

        func hasSourceFacts(_ entry: Entry) -> Bool {
            sourceEntry.hasSameFacts(as: entry)
        }
    }

    struct PreparedEntryMutation {
        let plan: EntryMutationPlan
        var previousEntry: Entry { plan.sourceEntry }

        fileprivate init(plan: EntryMutationPlan) {
            self.plan = plan
        }
    }

    private var entriesByWebViewID: [ObjectIdentifier: Entry] = [:]
    private var retiredNavigationIdentities: [
        ObjectIdentifier: WeakNavigationIdentityReference
    ] = [:]
    private(set) var mutationRevision: UInt64 = 0

    var entries: [ObjectIdentifier: Entry] {
        entriesByWebViewID
    }

    subscript(webViewID: ObjectIdentifier) -> Entry? {
        entriesByWebViewID[webViewID]
    }

    func entry(for webViewID: ObjectIdentifier) -> Entry? {
        entriesByWebViewID[webViewID]
    }

    func exactEntry(for webView: WKWebView) -> Entry? {
        let entry = entriesByWebViewID[ObjectIdentifier(webView)]
        return entry?.webViewReference.matches(webView) == true ? entry : nil
    }

    func canApply(_ plan: EntryMutationPlan) -> Bool {
        let next = plan.nextEntry
        guard plan.expectedRevision == mutationRevision,
              plan.webViewID == next.webViewReference.identifier,
              plan.expectedParticipantID == next.id,
              plan.expectedWebViewReference.identifier == plan.webViewID,
              let expectedWebView = plan.expectedWebViewReference.resolve(),
              next.webViewReference.matches(expectedWebView),
              plan.retiredNavigationID
                == plan.retiredNavigationReference?.identifier,
              let current = entriesByWebViewID[plan.webViewID] else {
            return false
        }
        return current.id == plan.expectedParticipantID
            && current.webViewReference.matches(expectedWebView)
            && current.hasSameFacts(as: plan.sourceEntry)
    }

    func applyPrevalidated(_ plan: EntryMutationPlan) -> Entry {
        precondition(canApply(plan), "participant plan must be prevalidated")
        if let retiredNavigationID = plan.retiredNavigationID {
            retireNavigationIdentity(
                retiredNavigationID,
                reference: plan.retiredNavigationReference
            )
        }
        entriesByWebViewID[plan.webViewID] = plan.nextEntry
        mutationRevision &+= 1
        return plan.nextEntry
    }

    func contains(_ webView: WKWebView, revision: UInt64) -> Bool {
        guard let entry = exactEntry(for: webView) else { return false }
        return entry.revision == revision
    }

    func exactActiveEntry(
        for webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        revision: UInt64
    ) -> Entry? {
        guard ObjectIdentifier(navigationLifetime) == navigationID,
              let entry = exactEntry(for: webView),
              entry.revision == revision,
              entry.phase == .active(navigationID: navigationID),
              entry.navigationIdentityReference?.matches(
                  navigationLifetime
              ) == true else {
            return nil
        }
        return entry
    }

    func exactCompletedEntry(
        for webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        revision: UInt64
    ) -> Entry? {
        guard ObjectIdentifier(navigationLifetime) == navigationID,
              let entry = exactEntry(for: webView),
              entry.revision == revision,
              case .completed(let completedNavigationID, _) = entry.phase,
              completedNavigationID == navigationID,
              entry.navigationIdentityReference?.matches(
                  navigationLifetime
              ) == true else {
            return nil
        }
        return entry
    }

    func installSubmission(
        _ binding: TabMainFrameIntentLedger.SubmissionBinding,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject
    ) -> InstallResult? {
        guard ObjectIdentifier(binding.webView) == binding.webViewID else {
            return nil
        }
        var entry = Entry(
            id: binding.participantID,
            webViewReference: WeakWebViewReference(binding.webView),
            revision: binding.revision,
            documentGeneration: binding.documentGeneration,
            targetURL: binding.targetURL,
            phase: .active(navigationID: navigationID)
        )
        guard attachNavigationIdentity(
            navigationID: navigationID,
            lifetime: navigationLifetime,
            to: &entry
        ) else {
            return nil
        }
        return install(entry, for: binding.webViewID)
    }

    func installLifecycleOwnedEntry(
        intent: TabMainFrameNavigationIntent,
        webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        documentGeneration: UInt64
    ) -> InstallResult {
        var entry = Entry(
            id: UUID(),
            webViewReference: WeakWebViewReference(webView),
            revision: intent.revision,
            documentGeneration: documentGeneration,
            targetURL: intent.targetURL,
            phase: .active(navigationID: navigationID)
        )
        precondition(attachNavigationIdentity(
            navigationID: navigationID,
            lifetime: navigationLifetime,
            to: &entry
        ))
        return install(entry, for: ObjectIdentifier(webView))
    }

    func install(
        _ entry: Entry,
        for webViewID: ObjectIdentifier
    ) -> InstallResult {
        var replacedParticipantID: UUID?
        if let replaced = entriesByWebViewID[webViewID],
           replaced.id != entry.id {
            retireNavigationIdentity(of: replaced)
            replacedParticipantID = replaced.id
        }
        entriesByWebViewID[webViewID] = entry
        mutationRevision &+= 1
        return InstallResult(replacedParticipantID: replacedParticipantID)
    }

    func removeAll(_ webViews: [WKWebView]) -> [Entry] {
        var removed: [Entry] = []
        var seen: Set<ObjectIdentifier> = []
        for webView in webViews {
            let webViewID = ObjectIdentifier(webView)
            guard seen.insert(webViewID).inserted,
                  let entry = entriesByWebViewID[webViewID],
                  entry.webViewReference.matches(webView) else {
                continue
            }
            retireNavigationIdentity(of: entry)
            entriesByWebViewID.removeValue(forKey: webViewID)
            removed.append(entry)
        }
        pruneRetiredNavigationIdentities()
        if removed.isEmpty == false { mutationRevision &+= 1 }
        return removed
    }

    func removeAllForNewIntent() -> [UUID] {
        let participantIDs = entriesByWebViewID.values.map(\.id)
        entriesByWebViewID.values.forEach(retireNavigationIdentity)
        entriesByWebViewID.removeAll()
        pruneRetiredNavigationIdentities()
        mutationRevision &+= 1
        return participantIDs
    }

    func attachNavigationIdentity(
        navigationID: ObjectIdentifier,
        lifetime: AnyObject?,
        to entry: inout Entry
    ) -> Bool {
        guard let lifetime else { return true }
        guard ObjectIdentifier(lifetime) == navigationID else { return false }
        entry.navigationIdentityReference = WeakNavigationIdentityReference(lifetime)
        return true
    }

    func attachNavigationIdentityIfPossible(
        navigationID: ObjectIdentifier,
        lifetime: AnyObject?,
        webView: WKWebView
    ) -> Bool {
        let webViewID = ObjectIdentifier(webView)
        guard var entry = exactEntry(for: webView),
              entry.phase == .active(navigationID: navigationID),
              entry.navigationIdentityReference.map({ reference in
                  lifetime.map(reference.matches) ?? true
              }) ?? true,
              attachNavigationIdentity(
                  navigationID: navigationID,
                  lifetime: lifetime,
                  to: &entry
              ) else {
            return false
        }
        entriesByWebViewID[webViewID] = entry
        mutationRevision &+= 1
        return true
    }

    func isRetiredNavigationIdentity(
        _ navigationID: ObjectIdentifier,
        lifetime: AnyObject?
    ) -> Bool {
        if let lifetime, ObjectIdentifier(lifetime) != navigationID {
            return false
        }
        pruneRetiredNavigationIdentities()
        guard let reference = retiredNavigationIdentities[navigationID],
              let retiredLifetime = reference.resolve() else {
            return false
        }
        guard let lifetime else { return true }
        if retiredLifetime === lifetime { return true }
        retiredNavigationIdentities.removeValue(forKey: navigationID)
        return false
    }

    func semanticRevision(
        for webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject
    ) -> UInt64? {
        guard ObjectIdentifier(navigationLifetime) == navigationID,
              let entry = exactEntry(for: webView),
              entry.phase == .active(navigationID: navigationID),
              entry.navigationIdentityReference?.matches(
                  navigationLifetime
              ) == true else {
            return nil
        }
        return entry.revision
    }

    func loadingWebViews(revision: UInt64) -> [WKWebView] {
        entriesByWebViewID.values.compactMap { entry in
            guard entry.revision == revision,
                  case .active = entry.phase else {
                return nil
            }
            return entry.webViewReference.resolve()
        }
    }

    func prepareCommit(
        webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        revision: UInt64,
        committedURL: URL,
        isPDF: Bool
    ) -> PreparedEntryMutation? {
        guard let previousEntry = exactActiveEntry(
            for: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            revision: revision
        ) else { return nil }
        var nextEntry = previousEntry
        nextEntry.targetURL = committedURL
        nextEntry.hasCommittedDocument = true
        nextEntry.committedDocumentURL = committedURL
        nextEntry.isPDFResponse = isPDF
        return preparedMutation(
            previousEntry: previousEntry,
            nextEntry: nextEntry,
            webView: webView
        )
    }

    func prepareTerminalSuccess(
        webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        revision: UInt64,
        terminalURL: URL?
    ) -> PreparedEntryMutation? {
        guard let previousEntry = exactActiveEntry(
            for: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            revision: revision
        ) else { return nil }
        var nextEntry = previousEntry
        nextEntry.hasCommittedDocument = true
        nextEntry.committedDocumentURL = nextEntry.committedDocumentURL
            ?? terminalURL
            ?? nextEntry.targetURL
        nextEntry.targetURL = terminalURL ?? nextEntry.targetURL
        nextEntry.phase = .completed(
            navigationID: navigationID,
            kind: .document
        )
        return preparedMutation(
            previousEntry: previousEntry,
            nextEntry: nextEntry,
            webView: webView
        )
    }

    func prepareSameDocumentSuccess(
        webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        revision: UInt64,
        presentationURL: URL
    ) -> PreparedEntryMutation? {
        guard let previousEntry = exactActiveEntry(
            for: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            revision: revision
        ) else { return nil }
        var nextEntry = previousEntry
        nextEntry.targetURL = presentationURL
        nextEntry.phase = .completed(
            navigationID: navigationID,
            kind: .sameDocument
        )
        return preparedMutation(
            previousEntry: previousEntry,
            nextEntry: nextEntry,
            webView: webView
        )
    }

    func prepareTargetMutation(
        _ targetURL: URL,
        webView: WKWebView
    ) -> PreparedEntryMutation? {
        guard let previousEntry = exactEntry(for: webView) else { return nil }
        var nextEntry = previousEntry
        nextEntry.targetURL = targetURL
        return preparedMutation(
            previousEntry: previousEntry,
            nextEntry: nextEntry,
            webView: webView
        )
    }

    func prepareContinuation(
        webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        revision: UInt64
    ) -> PreparedEntryMutation? {
        guard ObjectIdentifier(navigationLifetime) == navigationID,
              let previousEntry = exactEntry(for: webView),
              previousEntry.revision == revision else {
            return nil
        }
        var nextEntry = previousEntry
        guard attachNavigationIdentity(
            navigationID: navigationID,
            lifetime: navigationLifetime,
            to: &nextEntry
        ) else { return nil }
        let previousNavigationID: ObjectIdentifier?
        switch previousEntry.phase {
        case .active(let navigationID): previousNavigationID = navigationID
        case .completed(let navigationID, _): previousNavigationID = navigationID
        }
        let prepared = preparedMutation(
            previousEntry: previousEntry,
            nextEntry: nextEntry,
            webView: webView
        )
        return PreparedEntryMutation(plan: EntryMutationPlan(
            sourceEntry: prepared.previousEntry,
            expectedRevision: prepared.plan.expectedRevision,
            webViewID: prepared.plan.webViewID,
            expectedParticipantID: prepared.plan.expectedParticipantID,
            expectedWebViewReference: prepared.plan.expectedWebViewReference,
            nextEntry: prepared.plan.nextEntry,
            retiredNavigationID: previousNavigationID,
            retiredNavigationReference: previousEntry.navigationIdentityReference
        ))
    }

    private func preparedMutation(
        previousEntry: Entry,
        nextEntry: Entry,
        webView: WKWebView
    ) -> PreparedEntryMutation {
        PreparedEntryMutation(plan: EntryMutationPlan(
            sourceEntry: previousEntry,
            expectedRevision: mutationRevision,
            webViewID: ObjectIdentifier(webView),
            expectedParticipantID: previousEntry.id,
            expectedWebViewReference: WeakWebViewReference(webView),
            nextEntry: nextEntry,
            retiredNavigationID: nil,
            retiredNavigationReference: nil
        ))
    }

    func recordResponse(
        isPDF: Bool,
        webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        revision: UInt64
    ) -> Entry? {
        let webViewID = ObjectIdentifier(webView)
        guard var entry = exactActiveEntry(
            for: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            revision: revision
        ) else {
            return nil
        }
        guard entry.hasCommittedDocument == false else { return entry }
        entry.isPDFResponse = isPDF
        entriesByWebViewID[webViewID] = entry
        mutationRevision &+= 1
        return entry
    }

    func responseIsPDF(
        webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        revision: UInt64
    ) -> Bool? {
        exactActiveEntry(
            for: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            revision: revision
        )?.isPDFResponse
    }

    func removeExactActiveNavigation(
        webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        revision: UInt64
    ) -> Entry? {
        let webViewID = ObjectIdentifier(webView)
        guard let entry = exactActiveEntry(
            for: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            revision: revision
        ) else {
            return nil
        }
        retireNavigationIdentity(of: entry)
        entriesByWebViewID.removeValue(forKey: webViewID)
        mutationRevision &+= 1
        return entry
    }

    func migrateCommittedReplicas(
        revision: UInt64,
        from previousGeneration: UInt64,
        to documentGeneration: UInt64,
        matching identity: TabMainFrameAuthorityEffectLedger.SharedCommitIdentity
    ) -> [TabCommittedDocumentEvidence] {
        let compatibleWebViewIDs = entriesByWebViewID.compactMap {
            webViewID, entry -> ObjectIdentifier? in
            guard entry.revision == revision,
                  entry.documentGeneration == previousGeneration,
                  entry.hasCommittedDocument,
                  entry.committedDocumentURL.map({
                      TabMainFrameAuthorityEffectLedger.SharedCommitIdentity(
                          target: WebRuntimeNavigationIdentity($0),
                          isPDF: entry.isPDFResponse ?? false
                      )
                  }) == identity else {
                return nil
            }
            return webViewID
        }
        var migratedEvidence: [TabCommittedDocumentEvidence] = []
        for webViewID in compatibleWebViewIDs {
            guard var entry = entriesByWebViewID[webViewID] else { continue }
            entry.documentGeneration = documentGeneration
            entriesByWebViewID[webViewID] = entry
            mutationRevision &+= 1
            guard let webView = entry.webViewReference.resolve(),
                  let evidence = entry.committedEvidence(webView: webView) else {
                continue
            }
            migratedEvidence.append(evidence)
        }
        return migratedEvidence
    }

    func committedDocumentProof(
        webView: WKWebView,
        revision: UInt64,
        documentGeneration: UInt64,
        sharedCommitIdentity: TabMainFrameAuthorityEffectLedger.SharedCommitIdentity
    ) -> (entry: Entry, evidence: TabCommittedDocumentEvidence)? {
        let webViewID = ObjectIdentifier(webView)
        guard let entry = entriesByWebViewID[webViewID],
              entry.webViewReference.matches(webView),
              entry.revision == revision,
              entry.documentGeneration == documentGeneration,
              entry.hasCommittedDocument,
              let committedDocumentURL = entry.committedDocumentURL,
              let isPDF = entry.isPDFResponse,
              sharedCommitIdentity == TabMainFrameAuthorityEffectLedger.SharedCommitIdentity(
                  target: WebRuntimeNavigationIdentity(committedDocumentURL),
                  isPDF: isPDF
              ), let evidence = entry.committedEvidence(webView: webView) else {
            return nil
        }
        return (entry, evidence)
    }

    func rehydrate(
        _ candidates: [TabCommittedDocumentCandidate],
        preferredAuthorityWebViewID: ObjectIdentifier?,
        intent: TabMainFrameNavigationIntent,
        documentGeneration: UInt64
    ) -> Rehydration {
        var installedEntries: [Entry] = []
        var evidence: [TabCommittedDocumentEvidence] = []
        var replacedParticipantIDs: [UUID] = []
        for candidate in candidates {
            let webViewID = ObjectIdentifier(candidate.webView)
            let entry = Entry(
                id: UUID(),
                webViewReference: WeakWebViewReference(candidate.webView),
                revision: intent.revision,
                documentGeneration: documentGeneration,
                targetURL: candidate.presentationURL,
                phase: .completed(navigationID: nil, kind: .document),
                hasCommittedDocument: true,
                committedDocumentURL: candidate.committedURL,
                isPDFResponse: candidate.isPDF
            )
            let install = install(entry, for: webViewID)
            if let replacedParticipantID = install.replacedParticipantID {
                replacedParticipantIDs.append(replacedParticipantID)
            }
            installedEntries.append(entry)
            if let item = entry.committedEvidence(webView: candidate.webView) {
                evidence.append(item)
            }
        }

        let authorityWebViewID = preferredAuthorityWebViewID.flatMap { preferred in
            entriesByWebViewID[preferred] == nil ? nil : preferred
        } ?? entriesByWebViewID.keys.first
        return Rehydration(
            entries: installedEntries,
            evidence: evidence,
            authorityWebViewID: authorityWebViewID,
            authorityEntry: authorityWebViewID.flatMap { entriesByWebViewID[$0] },
            replacedParticipantIDs: replacedParticipantIDs
        )
    }

    func retireNavigationIdentity(of entry: Entry) {
        let navigationID: ObjectIdentifier?
        switch entry.phase {
        case .active(let activeNavigationID):
            navigationID = activeNavigationID
        case .completed(let completedNavigationID, _):
            navigationID = completedNavigationID
        }
        guard let navigationID,
              let reference = entry.navigationIdentityReference,
              reference.resolve() != nil else {
            return
        }
        retiredNavigationIdentities[navigationID] = reference
    }

    func retireNavigationIdentity(
        _ navigationID: ObjectIdentifier,
        reference: WeakNavigationIdentityReference?
    ) {
        guard let reference, reference.resolve() != nil else { return }
        retiredNavigationIdentities[navigationID] = reference
    }

    private func pruneRetiredNavigationIdentities() {
        retiredNavigationIdentities = retiredNavigationIdentities.filter {
            $0.value.resolve() != nil
        }
    }
}
