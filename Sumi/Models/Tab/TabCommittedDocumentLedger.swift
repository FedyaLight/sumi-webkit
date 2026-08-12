import Foundation
import SumiWebRuntime
import WebKit

struct TabCommittedDocumentEvidence {
    let webView: WKWebView
    let revision: UInt64
    let documentGeneration: UInt64
    let participantID: UUID
    let committedURL: URL
    let presentationURL: URL
    let isPDF: Bool
}

struct TabCommittedDocumentCandidate {
    let webView: WKWebView
    let committedURL: URL
    let presentationURL: URL
    let isPDF: Bool
}

struct TabCommittedDocumentRollbackSnapshot {
    let targetURL: URL
    let candidates: [TabCommittedDocumentCandidate]
    let preferredAuthorityWebViewID: ObjectIdentifier?
}

/// Read-only value identity of the canonical committed document. Revision and
/// document generation are the exact monotonic authority; the navigation
/// identity of the committed URL disambiguates the pre-first-commit state.
struct TabCommittedDocumentAuthorityProof: Equatable {
    let revision: UInt64?
    let documentGeneration: UInt64?
    let identity: WebRuntimeNavigationIdentity
}

/// Owns the durable committed-document truth independently from transient
/// navigation authority. Replicas survive failed submissions and produce the
/// only Reader/permission document leases accepted by the Tab.
@MainActor
final class TabCommittedDocumentLedger {
    private typealias WeakWebViewReference = WebViewIdentityWitness

    private struct DocumentIdentity {
        let revision: UInt64
        let documentGeneration: UInt64
        let participantID: UUID
        let committedURL: URL
        let presentationURL: URL
        let isPDF: Bool

        init(_ evidence: TabCommittedDocumentEvidence) {
            revision = evidence.revision
            documentGeneration = evidence.documentGeneration
            participantID = evidence.participantID
            committedURL = evidence.committedURL
            presentationURL = evidence.presentationURL
            isPDF = evidence.isPDF
        }

        private init(
            revision: UInt64,
            documentGeneration: UInt64,
            participantID: UUID,
            committedURL: URL,
            presentationURL: URL,
            isPDF: Bool
        ) {
            self.revision = revision
            self.documentGeneration = documentGeneration
            self.participantID = participantID
            self.committedURL = committedURL
            self.presentationURL = presentationURL
            self.isPDF = isPDF
        }

        func updatingPresentation(_ presentationURL: URL) -> Self {
            Self(
                revision: revision,
                documentGeneration: documentGeneration,
                participantID: participantID,
                committedURL: committedURL,
                presentationURL: presentationURL,
                isPDF: isPDF
            )
        }
    }

    private struct Replica {
        let webViewReference: WeakWebViewReference
        var document: DocumentIdentity
        let suspensionToken: String
        let suspensionActivationEpoch: UInt64
        var suspensionActivationRequested: Bool
        var suspensionActivationAttemptCount: Int
        var suspensionReport: SuspensionReport?
    }

    private struct SuspensionReport {
        let revision: UInt64
        let documentGeneration: UInt64
        let participantID: UUID
        let value: TabDocumentSuspensionReport
    }

    private var committedPresentationURL: URL
    private var committedIdentityURL: URL
    private var committedIsPDF = false
    private var committedRevision: UInt64?
    private var committedDocumentGeneration: UInt64?
    private var sourceWebViewReference: WeakWebViewReference?
    private var replicasByWebViewID: [ObjectIdentifier: Replica] = [:]
    private var nextSuspensionActivationEpoch: UInt64 = 0

    init(initialURL: URL) {
        committedPresentationURL = initialURL
        committedIdentityURL = initialURL
    }

    func authorityProof() -> TabCommittedDocumentAuthorityProof {
        TabCommittedDocumentAuthorityProof(
            revision: committedRevision,
            documentGeneration: committedDocumentGeneration,
            identity: WebRuntimeNavigationIdentity(committedIdentityURL)
        )
    }

    func recordReplica(_ evidence: TabCommittedDocumentEvidence) {
        let webViewID = ObjectIdentifier(evidence.webView)
        let existing = replicasByWebViewID[webViewID]
        let preservesDocument = existing.map {
            $0.webViewReference.matches(evidence.webView)
                && Self.sameDocument($0.document, evidence)
        } ?? false
        let suspensionActivationEpoch: UInt64
        if preservesDocument, let existing {
            suspensionActivationEpoch = existing.suspensionActivationEpoch
        } else {
            nextSuspensionActivationEpoch &+= 1
            suspensionActivationEpoch = nextSuspensionActivationEpoch
        }
        replicasByWebViewID[webViewID] = Replica(
            webViewReference: WeakWebViewReference(evidence.webView),
            document: DocumentIdentity(evidence),
            suspensionToken: preservesDocument
                ? existing?.suspensionToken ?? UUID().uuidString
                : UUID().uuidString,
            suspensionActivationEpoch: suspensionActivationEpoch,
            suspensionActivationRequested: preservesDocument
                ? existing?.suspensionActivationRequested ?? false
                : false,
            suspensionActivationAttemptCount: preservesDocument
                ? existing?.suspensionActivationAttemptCount ?? 0
                : 0,
            suspensionReport: preservesDocument
                ? existing?.suspensionReport
                : nil
        )
    }

    func adoptCanonicalDocument(_ evidence: TabCommittedDocumentEvidence) {
        committedIdentityURL = evidence.committedURL
        committedPresentationURL = evidence.presentationURL
        committedIsPDF = evidence.isPDF
        committedRevision = evidence.revision
        committedDocumentGeneration = evidence.documentGeneration
        sourceWebViewReference = WeakWebViewReference(evidence.webView)
        recordReplica(evidence)
        replicasByWebViewID = replicasByWebViewID.filter { _, replica in
            guard replica.webViewReference.resolve() != nil else { return false }
            return isCanonicalReplica(replica.document)
        }
    }

    func updatePresentation(_ presentationURL: URL, on webView: WKWebView) {
        committedPresentationURL = presentationURL
        sourceWebViewReference = WeakWebViewReference(webView)
        let webViewID = ObjectIdentifier(webView)
        guard var replica = replicasByWebViewID[webViewID],
              replica.webViewReference.matches(webView) else {
            return
        }
        replica.document = replica.document.updatingPresentation(
            presentationURL
        )
        replicasByWebViewID[webViewID] = replica
    }

    func sourceWebView() -> WKWebView? {
        guard let webView = sourceWebViewReference?.resolve(),
              let replica = replicasByWebViewID[ObjectIdentifier(webView)],
              replica.webViewReference.matches(webView),
              isCanonicalReplica(replica.document) else {
            return nil
        }
        return webView
    }

    func hasCommittedDocument(on webView: WKWebView) -> Bool {
        guard let replica = replicasByWebViewID[ObjectIdentifier(webView)],
              replica.webViewReference.matches(webView) else {
            return false
        }
        return isCanonicalReplica(replica.document)
    }

    func documentLease(
        matching evidence: TabCommittedDocumentEvidence,
        isAuthority: Bool
    ) -> TabMainFrameDocumentLease? {
        let webViewID = ObjectIdentifier(evidence.webView)
        guard let replica = replicasByWebViewID[webViewID],
              replica.webViewReference.matches(evidence.webView),
              Self.sameDocument(replica.document, evidence),
              isCanonicalReplica(replica.document) else {
            return nil
        }
        return TabMainFrameDocumentLease(
            revision: replica.document.revision,
            documentGeneration: replica.document.documentGeneration,
            webViewID: webViewID,
            participantID: replica.document.participantID,
            committedURL: replica.document.committedURL,
            presentationURL: replica.document.presentationURL,
            isPDF: replica.document.isPDF,
            isAuthority: isAuthority
        )
    }

    func recordSuspensionReport(
        _ report: TabDocumentSuspensionReport,
        from webView: WKWebView,
        matching lease: TabMainFrameDocumentLease
    ) -> Bool {
        let webViewID = ObjectIdentifier(webView)
        guard lease.webViewID == webViewID,
              report.documentNonce.isEmpty == false,
              report.documentNonce.utf8.count <= 256,
              var replica = replicasByWebViewID[webViewID],
              replica.webViewReference.matches(webView),
              replica.document.revision == lease.revision,
              replica.document.documentGeneration == lease.documentGeneration,
              replica.document.participantID == lease.participantID,
              replica.suspensionToken == report.documentLeaseToken,
              WebRuntimeNavigationIdentity(replica.document.committedURL)
                == WebRuntimeNavigationIdentity(lease.committedURL),
              replica.document.isPDF == lease.isPDF,
              isCanonicalReplica(replica.document) else {
            return false
        }

        if let previous = replica.suspensionReport {
            guard previous.revision == lease.revision,
                  previous.documentGeneration == lease.documentGeneration,
                  previous.participantID == lease.participantID,
                  previous.value.documentNonce == report.documentNonce,
                  report.sequence > previous.value.sequence else {
                return false
            }
        }

        replica.suspensionReport = SuspensionReport(
            revision: lease.revision,
            documentGeneration: lease.documentGeneration,
            participantID: lease.participantID,
            value: report
        )
        replicasByWebViewID[webViewID] = replica
        return true
    }

    func suspensionToken(
        for webView: WKWebView,
        matching lease: TabMainFrameDocumentLease
    ) -> String? {
        let webViewID = ObjectIdentifier(webView)
        guard lease.webViewID == webViewID,
              let replica = replicasByWebViewID[webViewID],
              replica.webViewReference.matches(webView),
              replica.document.revision == lease.revision,
              replica.document.documentGeneration == lease.documentGeneration,
              replica.document.participantID == lease.participantID,
              isCanonicalReplica(replica.document) else {
            return nil
        }
        return replica.suspensionToken
    }

    func takePendingSuspensionActivations() -> [(
        webView: WKWebView,
        token: String,
        epoch: UInt64
    )] {
        guard committedIsPDF == false else { return [] }
        var activations: [(
            webView: WKWebView,
            token: String,
            epoch: UInt64
        )] = []
        var activatedWebViewIDs: [ObjectIdentifier] = []
        for (webViewID, replica) in replicasByWebViewID {
            guard replica.suspensionActivationRequested == false,
                  replica.suspensionActivationAttemptCount < 3,
                  isCanonicalReplica(replica.document),
                  let webView = replica.webViewReference.resolve() else {
                continue
            }
            activations.append((
                webView: webView,
                token: replica.suspensionToken,
                epoch: replica.suspensionActivationEpoch
            ))
            activatedWebViewIDs.append(webViewID)
        }
        for webViewID in activatedWebViewIDs {
            guard var replica = replicasByWebViewID[webViewID] else { continue }
            replica.suspensionActivationRequested = true
            replica.suspensionActivationAttemptCount += 1
            replicasByWebViewID[webViewID] = replica
        }
        return activations
    }

    func suspensionActivationDidFail(
        for webView: WKWebView,
        token: String,
        epoch: UInt64
    ) -> Bool {
        let webViewID = ObjectIdentifier(webView)
        guard var replica = replicasByWebViewID[webViewID],
              replica.webViewReference.matches(webView),
              replica.suspensionToken == token,
              replica.suspensionActivationEpoch == epoch,
              replica.suspensionReport == nil,
              replica.suspensionActivationRequested,
              replica.suspensionActivationAttemptCount < 3,
              isCanonicalReplica(replica.document) else {
            return false
        }
        replica.suspensionActivationRequested = false
        replicasByWebViewID[webViewID] = replica
        return true
    }

    func suspensionDecision() -> TabDocumentSuspensionDecision {
        if committedIsPDF {
            return .vetoed(.pdfDocument)
        }

        var hasCanonicalReplica = false
        var awaitsEvidence = false
        var pageVeto = false

        for replica in replicasByWebViewID.values {
            guard replica.webViewReference.resolve() != nil else { continue }
            guard isCanonicalReplica(replica.document) else { continue }
            hasCanonicalReplica = true
            guard let report = replica.suspensionReport,
                  report.revision == replica.document.revision,
                  report.documentGeneration == replica.document.documentGeneration,
                  report.participantID == replica.document.participantID else {
                awaitsEvidence = true
                continue
            }
            pageVeto = pageVeto || report.value.canBeSuspended == false
        }
        if pageVeto {
            return .vetoed(.pageReportedUnableToSuspend)
        }
        guard hasCanonicalReplica, awaitsEvidence == false else {
            return .awaitingEvidence
        }
        return .allowed
    }

    func removeWebView(_ webView: WKWebView) {
        removeWebViews([webView], preferredSourceWebView: nil)
    }

    /// Retires one physical generation as a single document-ledger change.
    /// Source selection happens only after every departing replica is gone, so
    /// an intermediate member of the same generation cannot temporarily become
    /// the durable-document source.
    func removeWebViews(
        _ webViews: [WKWebView],
        preferredSourceWebView: WKWebView?
    ) {
        var seen: Set<ObjectIdentifier> = []
        for webView in webViews {
            let webViewID = ObjectIdentifier(webView)
            guard seen.insert(webViewID).inserted,
                  replicasByWebViewID[webViewID]?.webViewReference.matches(
                      webView
                  ) == true else {
                continue
            }
            replicasByWebViewID.removeValue(forKey: webViewID)
        }

        guard sourceWebView() == nil else { return }
        sourceWebViewReference = canonicalReplicaSource(
            preferredWebView: preferredSourceWebView
        ).map(WeakWebViewReference.init)
    }

    func rollbackSnapshot() -> TabCommittedDocumentRollbackSnapshot {
        var candidates: [TabCommittedDocumentCandidate] = []
        var expiredWebViewIDs: [ObjectIdentifier] = []

        for (webViewID, replica) in replicasByWebViewID {
            guard let webView = replica.webViewReference.resolve(),
                  isCanonicalReplica(replica.document) else {
                expiredWebViewIDs.append(webViewID)
                continue
            }
            candidates.append(TabCommittedDocumentCandidate(
                webView: webView,
                committedURL: replica.document.committedURL,
                presentationURL: replica.document.presentationURL,
                isPDF: replica.document.isPDF
            ))
        }
        for webViewID in expiredWebViewIDs {
            replicasByWebViewID.removeValue(forKey: webViewID)
        }

        let preferredAuthorityWebViewID = sourceWebViewReference
            .flatMap { reference in
                reference.resolve().map(ObjectIdentifier.init)
            }
            .flatMap { sourceID in
                candidates.contains(where: {
                    ObjectIdentifier($0.webView) == sourceID
                }) ? sourceID : nil
            }

        return TabCommittedDocumentRollbackSnapshot(
            targetURL: committedPresentationURL,
            candidates: candidates,
            preferredAuthorityWebViewID: preferredAuthorityWebViewID
        )
    }

    func adoptRehydratedEvidence(
        _ evidence: [TabCommittedDocumentEvidence],
        authorityWebViewID: ObjectIdentifier?
    ) {
        for item in evidence {
            recordReplica(item)
        }
        guard let authorityWebViewID,
              let authority = replicasByWebViewID[authorityWebViewID],
              let authorityWebView = authority.webViewReference.resolve()
        else {
            return
        }
        committedIdentityURL = authority.document.committedURL
        committedPresentationURL = authority.document.presentationURL
        committedIsPDF = authority.document.isPDF
        committedRevision = authority.document.revision
        committedDocumentGeneration = authority.document.documentGeneration
        replicasByWebViewID = replicasByWebViewID.filter { _, replica in
            replica.webViewReference.resolve() != nil
                && isCanonicalReplica(replica.document)
        }
        sourceWebViewReference = WeakWebViewReference(authorityWebView)
    }

    private func canonicalReplicaSource(
        preferredWebView: WKWebView?
    ) -> WKWebView? {
        let canonicalIdentity = WebRuntimeNavigationIdentity(
            committedIdentityURL
        )
        func isCanonicalReplica(_ webView: WKWebView) -> Bool {
            guard let replica = replicasByWebViewID[ObjectIdentifier(webView)],
                  replica.webViewReference.matches(webView) else {
                return false
            }
            return WebRuntimeNavigationIdentity(replica.document.committedURL)
                    == canonicalIdentity
                && self.isCanonicalReplica(replica.document)
        }

        if let preferredWebView, isCanonicalReplica(preferredWebView) {
            return preferredWebView
        }
        return replicasByWebViewID
            .sorted { UInt(bitPattern: $0.key) < UInt(bitPattern: $1.key) }
            .lazy
            .compactMap { $0.value.webViewReference.resolve() }
            .first(where: isCanonicalReplica)
    }

    private func isCanonicalReplica(
        _ document: DocumentIdentity
    ) -> Bool {
        guard let committedRevision,
              let committedDocumentGeneration else {
            return false
        }
        return document.revision == committedRevision
            && document.documentGeneration == committedDocumentGeneration
            && WebRuntimeNavigationIdentity(document.committedURL)
                == WebRuntimeNavigationIdentity(committedIdentityURL)
            && document.isPDF == committedIsPDF
    }

    private static func sameDocument(
        _ lhs: DocumentIdentity,
        _ rhs: TabCommittedDocumentEvidence
    ) -> Bool {
        lhs.revision == rhs.revision
            && lhs.documentGeneration == rhs.documentGeneration
            && lhs.participantID == rhs.participantID
            && WebRuntimeNavigationIdentity(lhs.committedURL)
                == WebRuntimeNavigationIdentity(rhs.committedURL)
            && lhs.isPDF == rhs.isPDF
    }
}
