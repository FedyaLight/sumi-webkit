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
        case completed
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

    private var entriesByWebViewID: [ObjectIdentifier: Entry] = [:]
    private var retiredNavigationIdentities: [
        ObjectIdentifier: WeakNavigationIdentityReference
    ] = [:]

    var entries: [ObjectIdentifier: Entry] {
        entriesByWebViewID
    }

    subscript(webViewID: ObjectIdentifier) -> Entry? {
        get { entriesByWebViewID[webViewID] }
        set { entriesByWebViewID[webViewID] = newValue }
    }

    func entry(for webViewID: ObjectIdentifier) -> Entry? {
        entriesByWebViewID[webViewID]
    }

    func exactEntry(for webView: WKWebView) -> Entry? {
        let entry = entriesByWebViewID[ObjectIdentifier(webView)]
        return entry?.webViewReference.matches(webView) == true ? entry : nil
    }

    func contains(_ webView: WKWebView, revision: UInt64) -> Bool {
        guard let entry = exactEntry(for: webView) else { return false }
        return entry.revision == revision
    }

    func activeEntry(
        webViewID: ObjectIdentifier,
        navigationID: ObjectIdentifier,
        revision: UInt64
    ) -> Entry? {
        guard let entry = entriesByWebViewID[webViewID],
              entry.revision == revision,
              entry.phase == .active(navigationID: navigationID) else {
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
        return InstallResult(replacedParticipantID: replacedParticipantID)
    }

    func remove(_ webView: WKWebView) -> Entry? {
        removeAll([webView]).first
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
        return removed
    }

    func remove(webViewID: ObjectIdentifier) -> Entry? {
        guard let entry = entriesByWebViewID[webViewID] else { return nil }
        retireNavigationIdentity(of: entry)
        return entriesByWebViewID.removeValue(forKey: webViewID)
    }

    func removeAllForNewIntent() -> [UUID] {
        let participantIDs = entriesByWebViewID.values.map(\.id)
        entriesByWebViewID.values.forEach(retireNavigationIdentity)
        entriesByWebViewID.removeAll()
        pruneRetiredNavigationIdentities()
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
        webViewID: ObjectIdentifier
    ) {
        guard var entry = entriesByWebViewID[webViewID],
              entry.phase == .active(navigationID: navigationID),
              attachNavigationIdentity(
                  navigationID: navigationID,
                  lifetime: lifetime,
                  to: &entry
              ) else {
            return
        }
        entriesByWebViewID[webViewID] = entry
    }

    func isRetiredNavigationIdentity(
        _ navigationID: ObjectIdentifier,
        lifetime: AnyObject?
    ) -> Bool {
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

    func recordCommit(
        webView: WKWebView,
        navigationID: ObjectIdentifier,
        revision: UInt64,
        committedURL: URL,
        isPDF: Bool
    ) -> Entry? {
        let webViewID = ObjectIdentifier(webView)
        guard var entry = activeEntry(
            webViewID: webViewID,
            navigationID: navigationID,
            revision: revision
        ) else {
            return nil
        }
        entry.targetURL = committedURL
        entry.hasCommittedDocument = true
        entry.committedDocumentURL = committedURL
        entry.isPDFResponse = isPDF
        entriesByWebViewID[webViewID] = entry
        return entry
    }

    func recordResponse(
        isPDF: Bool,
        webViewID: ObjectIdentifier,
        navigationID: ObjectIdentifier,
        revision: UInt64
    ) -> Entry? {
        guard var entry = activeEntry(
            webViewID: webViewID,
            navigationID: navigationID,
            revision: revision
        ) else {
            return nil
        }
        guard entry.hasCommittedDocument == false else { return entry }
        entry.isPDFResponse = isPDF
        entriesByWebViewID[webViewID] = entry
        return entry
    }

    func responseIsPDF(
        webViewID: ObjectIdentifier,
        navigationID: ObjectIdentifier,
        revision: UInt64
    ) -> Bool? {
        activeEntry(
            webViewID: webViewID,
            navigationID: navigationID,
            revision: revision
        )?.isPDFResponse
    }

    func markTerminalSuccess(
        webView: WKWebView,
        navigationID: ObjectIdentifier,
        revision: UInt64,
        terminalURL: URL?
    ) -> Entry? {
        let webViewID = ObjectIdentifier(webView)
        guard var entry = activeEntry(
            webViewID: webViewID,
            navigationID: navigationID,
            revision: revision
        ) else {
            return nil
        }
        entry.hasCommittedDocument = true
        entry.committedDocumentURL = entry.committedDocumentURL
            ?? terminalURL
            ?? entry.targetURL
        entry.targetURL = terminalURL ?? entry.targetURL
        entriesByWebViewID[webViewID] = entry
        return entry
    }

    func updateTarget(_ targetURL: URL, webViewID: ObjectIdentifier) -> Bool {
        guard var entry = entriesByWebViewID[webViewID] else { return false }
        entry.targetURL = targetURL
        entriesByWebViewID[webViewID] = entry
        return true
    }

    func finish(
        webViewID: ObjectIdentifier,
        navigationID: ObjectIdentifier,
        revision: UInt64
    ) -> Entry? {
        guard var entry = activeEntry(
            webViewID: webViewID,
            navigationID: navigationID,
            revision: revision
        ) else {
            return nil
        }
        retireNavigationIdentity(of: entry)
        entry.phase = .completed
        entry.navigationIdentityReference = nil
        entriesByWebViewID[webViewID] = entry
        return entry
    }

    func removeExactActiveNavigation(
        webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        revision: UInt64
    ) -> Entry? {
        let webViewID = ObjectIdentifier(webView)
        guard let entry = activeEntry(
            webViewID: webViewID,
            navigationID: navigationID,
            revision: revision
        ), ObjectIdentifier(navigationLifetime) == navigationID,
           entry.webViewReference.matches(webView),
           entry.navigationIdentityReference?.matches(navigationLifetime) == true else {
            return nil
        }
        retireNavigationIdentity(of: entry)
        entriesByWebViewID.removeValue(forKey: webViewID)
        return entry
    }

    func prepareContinuation(
        webViewID: ObjectIdentifier,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        revision: UInt64
    ) -> Entry? {
        guard var entry = entriesByWebViewID[webViewID],
              entry.revision == revision else {
            return nil
        }
        let previousNavigationID: ObjectIdentifier?
        switch entry.phase {
        case .active(let navigationID):
            previousNavigationID = navigationID
        case .completed:
            previousNavigationID = nil
        }
        let previousIdentity = entry.navigationIdentityReference
        guard attachNavigationIdentity(
            navigationID: navigationID,
            lifetime: navigationLifetime,
            to: &entry
        ) else {
            return nil
        }
        if let previousNavigationID {
            retireNavigationIdentity(
                previousNavigationID,
                reference: previousIdentity
            )
        }
        return entry
    }

    func storeContinuation(
        _ entry: Entry,
        webViewID: ObjectIdentifier,
        navigationID: ObjectIdentifier,
        targetURL: URL,
        kind: TabMainFrameContinuationKind
    ) -> Entry {
        var entry = entry
        entry.targetURL = targetURL
        entry.phase = .active(navigationID: navigationID)
        if kind == .clientRedirect {
            entry.hasCommittedDocument = false
            entry.committedDocumentURL = nil
            entry.isPDFResponse = nil
        }
        entriesByWebViewID[webViewID] = entry
        return entry
    }

    func migrateCommittedReplicas(
        revision: UInt64,
        from previousGeneration: UInt64,
        to documentGeneration: UInt64,
        matching identity: TabMainFrameEffectLedger.SharedCommitIdentity
    ) -> [TabCommittedDocumentEvidence] {
        let compatibleWebViewIDs = entriesByWebViewID.compactMap {
            webViewID, entry -> ObjectIdentifier? in
            guard entry.revision == revision,
                  entry.documentGeneration == previousGeneration,
                  entry.hasCommittedDocument,
                  entry.committedDocumentURL.map({
                      TabMainFrameEffectLedger.SharedCommitIdentity(
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
        sharedCommitIdentity: TabMainFrameEffectLedger.SharedCommitIdentity
    ) -> (entry: Entry, evidence: TabCommittedDocumentEvidence)? {
        let webViewID = ObjectIdentifier(webView)
        guard let entry = entriesByWebViewID[webViewID],
              entry.webViewReference.matches(webView),
              entry.revision == revision,
              entry.documentGeneration == documentGeneration,
              entry.hasCommittedDocument,
              let committedDocumentURL = entry.committedDocumentURL,
              let isPDF = entry.isPDFResponse,
              sharedCommitIdentity == TabMainFrameEffectLedger.SharedCommitIdentity(
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
                phase: .completed,
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
        guard case .active(let navigationID) = entry.phase,
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
