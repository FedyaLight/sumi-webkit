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

/// Owns the durable committed-document truth independently from transient
/// navigation authority. Replicas survive failed submissions and produce the
/// only Reader/permission document leases accepted by the Tab.
@MainActor
final class TabCommittedDocumentLedger {
    private typealias WeakWebViewReference = WebViewIdentityWitness

    private struct Replica {
        let webViewReference: WeakWebViewReference
        var evidence: TabCommittedDocumentEvidence
        let suspensionToken: String
        let suspensionActivationEpoch: UInt64
        var suspensionActivationRequested: Bool
        var suspensionActivationAttemptCount: Int
        var suspensionReport: SuspensionReport?
        var subframePictureInPictureReports: [
            String: TabSubframePictureInPictureReport
        ]
        var hasSubframePictureInPictureOverflowVeto: Bool
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

    var rollbackTargetURL: URL {
        committedPresentationURL
    }

    func recordReplica(_ evidence: TabCommittedDocumentEvidence) {
        let webViewID = ObjectIdentifier(evidence.webView)
        let existing = replicasByWebViewID[webViewID]
        let preservesDocument = existing.map {
            $0.webViewReference.matches(evidence.webView)
                && Self.sameDocument($0.evidence, evidence)
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
            evidence: evidence,
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
                : nil,
            subframePictureInPictureReports: preservesDocument
                ? existing?.subframePictureInPictureReports ?? [:]
                : [:],
            hasSubframePictureInPictureOverflowVeto: preservesDocument
                ? existing?.hasSubframePictureInPictureOverflowVeto ?? false
                : false
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
            return isCanonicalReplica(replica.evidence)
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
        let evidence = replica.evidence
        replica.evidence = TabCommittedDocumentEvidence(
            webView: webView,
            revision: evidence.revision,
            documentGeneration: evidence.documentGeneration,
            participantID: evidence.participantID,
            committedURL: evidence.committedURL,
            presentationURL: presentationURL,
            isPDF: evidence.isPDF
        )
        replicasByWebViewID[webViewID] = replica
    }

    func noteSurvivingDocument(on webView: WKWebView, committedURL: URL) {
        let webViewID = ObjectIdentifier(webView)
        guard var replica = replicasByWebViewID[webViewID],
              replica.webViewReference.matches(webView),
              WebRuntimeNavigationIdentity(committedURL)
                == WebRuntimeNavigationIdentity(replica.evidence.committedURL),
              WebRuntimeNavigationIdentity(committedURL)
                == WebRuntimeNavigationIdentity(committedIdentityURL),
              isCanonicalReplica(replica.evidence) else {
            return
        }
        let evidence = replica.evidence
        replica.evidence = TabCommittedDocumentEvidence(
            webView: webView,
            revision: evidence.revision,
            documentGeneration: evidence.documentGeneration,
            participantID: evidence.participantID,
            committedURL: evidence.committedURL,
            presentationURL: committedPresentationURL,
            isPDF: evidence.isPDF
        )
        replicasByWebViewID[webViewID] = replica
        if sourceWebViewReference?.resolve() == nil {
            sourceWebViewReference = WeakWebViewReference(webView)
        }
    }

    func sourceWebView() -> WKWebView? {
        guard let webView = sourceWebViewReference?.resolve(),
              let replica = replicasByWebViewID[ObjectIdentifier(webView)],
              replica.webViewReference.matches(webView),
              isCanonicalReplica(replica.evidence) else {
            return nil
        }
        return webView
    }

    func documentLease(
        matching evidence: TabCommittedDocumentEvidence,
        isAuthority: Bool
    ) -> TabMainFrameDocumentLease? {
        let webViewID = ObjectIdentifier(evidence.webView)
        guard let replica = replicasByWebViewID[webViewID],
              replica.webViewReference.matches(evidence.webView),
              replica.evidence.revision == evidence.revision,
              replica.evidence.documentGeneration == evidence.documentGeneration,
              replica.evidence.participantID == evidence.participantID,
              isCanonicalReplica(evidence) else {
            return nil
        }
        return TabMainFrameDocumentLease(
            revision: evidence.revision,
            documentGeneration: evidence.documentGeneration,
            webViewID: webViewID,
            participantID: evidence.participantID,
            committedURL: evidence.committedURL,
            presentationURL: evidence.presentationURL,
            isPDF: evidence.isPDF,
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
              replica.evidence.revision == lease.revision,
              replica.evidence.documentGeneration == lease.documentGeneration,
              replica.evidence.participantID == lease.participantID,
              replica.suspensionToken == report.documentLeaseToken,
              WebRuntimeNavigationIdentity(replica.evidence.committedURL)
                == WebRuntimeNavigationIdentity(lease.committedURL),
              replica.evidence.isPDF == lease.isPDF,
              isCanonicalReplica(replica.evidence) else {
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

    func recordSubframePictureInPictureReport(
        _ report: TabSubframePictureInPictureReport,
        from webView: WKWebView,
        matching lease: TabMainFrameDocumentLease
    ) -> Bool {
        let webViewID = ObjectIdentifier(webView)
        guard lease.webViewID == webViewID,
              report.documentNonce.isEmpty == false,
              report.documentNonce.utf8.count <= 256,
              var replica = replicasByWebViewID[webViewID],
              replica.webViewReference.matches(webView),
              replica.evidence.revision == lease.revision,
              replica.evidence.documentGeneration == lease.documentGeneration,
              replica.evidence.participantID == lease.participantID,
              replica.suspensionToken == report.documentLeaseToken,
              isCanonicalReplica(replica.evidence) else {
            return false
        }

        if let previous = replica.subframePictureInPictureReports[
            report.documentNonce
        ] {
            guard report.sequence > previous.sequence else { return false }
        }

        if report.isActive {
            if replica.subframePictureInPictureReports[report.documentNonce]
                == nil,
               replica.subframePictureInPictureReports.count >= 64 {
                replica.hasSubframePictureInPictureOverflowVeto = true
            } else {
                replica.subframePictureInPictureReports[
                    report.documentNonce
                ] = report
            }
        } else {
            replica.subframePictureInPictureReports.removeValue(
                forKey: report.documentNonce
            )
        }
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
              replica.evidence.revision == lease.revision,
              replica.evidence.documentGeneration == lease.documentGeneration,
              replica.evidence.participantID == lease.participantID,
              isCanonicalReplica(replica.evidence) else {
            return nil
        }
        return replica.suspensionToken
    }

    func takePendingSuspensionActivations() -> [(
        webView: WKWebView,
        token: String,
        epoch: UInt64
    )] {
        var activations: [(
            webView: WKWebView,
            token: String,
            epoch: UInt64
        )] = []
        var activatedWebViewIDs: [ObjectIdentifier] = []
        for (webViewID, replica) in replicasByWebViewID {
            guard replica.suspensionActivationRequested == false,
                  replica.suspensionActivationAttemptCount < 3,
                  isCanonicalReplica(replica.evidence),
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
        token: String
    ) -> Bool {
        let webViewID = ObjectIdentifier(webView)
        guard var replica = replicasByWebViewID[webViewID],
              replica.webViewReference.matches(webView),
              replica.suspensionToken == token,
              replica.suspensionReport == nil,
              replica.suspensionActivationRequested,
              replica.suspensionActivationAttemptCount < 3,
              isCanonicalReplica(replica.evidence) else {
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

        var expiredWebViewIDs: [ObjectIdentifier] = []
        var hasCanonicalReplica = false
        var awaitsEvidence = false
        var pageVeto = false
        var pictureInPictureVeto = false

        for (webViewID, replica) in replicasByWebViewID {
            guard replica.webViewReference.resolve() != nil else {
                expiredWebViewIDs.append(webViewID)
                continue
            }
            guard isCanonicalReplica(replica.evidence) else { continue }
            hasCanonicalReplica = true
            guard let report = replica.suspensionReport,
                  report.revision == replica.evidence.revision,
                  report.documentGeneration == replica.evidence.documentGeneration,
                  report.participantID == replica.evidence.participantID else {
                awaitsEvidence = true
                continue
            }
            pageVeto = pageVeto || report.value.canBeSuspended == false
            pictureInPictureVeto = pictureInPictureVeto
                || report.value.hasPictureInPictureVideo
                || replica.hasSubframePictureInPictureOverflowVeto
                || replica.subframePictureInPictureReports.values.contains(
                    where: \.isActive
                )
        }
        expiredWebViewIDs.forEach {
            replicasByWebViewID.removeValue(forKey: $0)
        }

        if pictureInPictureVeto {
            return .vetoed(.pictureInPicture)
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
        let committedIdentity = WebRuntimeNavigationIdentity(committedIdentityURL)
        var candidates: [TabCommittedDocumentCandidate] = []
        var expiredWebViewIDs: [ObjectIdentifier] = []

        for (webViewID, replica) in replicasByWebViewID {
            guard let webView = replica.webViewReference.resolve(),
                  let physicalCommittedURL = webView.committedURL,
                  WebRuntimeNavigationIdentity(physicalCommittedURL)
                    == WebRuntimeNavigationIdentity(replica.evidence.committedURL),
                  WebRuntimeNavigationIdentity(replica.evidence.committedURL)
                    == committedIdentity,
                  isCanonicalReplica(replica.evidence) else {
                expiredWebViewIDs.append(webViewID)
                continue
            }
            candidates.append(TabCommittedDocumentCandidate(
                webView: webView,
                committedURL: replica.evidence.committedURL,
                presentationURL: replica.evidence.presentationURL,
                isPDF: replica.evidence.isPDF
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
              let authority = replicasByWebViewID[authorityWebViewID]?.evidence else {
            return
        }
        committedIdentityURL = authority.committedURL
        committedPresentationURL = authority.presentationURL
        committedIsPDF = authority.isPDF
        committedRevision = authority.revision
        committedDocumentGeneration = authority.documentGeneration
        replicasByWebViewID = replicasByWebViewID.filter { _, replica in
            replica.webViewReference.resolve() != nil
                && isCanonicalReplica(replica.evidence)
        }
        sourceWebViewReference = WeakWebViewReference(authority.webView)
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
            return WebRuntimeNavigationIdentity(replica.evidence.committedURL)
                    == canonicalIdentity
                && self.isCanonicalReplica(replica.evidence)
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
        _ evidence: TabCommittedDocumentEvidence
    ) -> Bool {
        guard let committedRevision,
              let committedDocumentGeneration else {
            return false
        }
        return evidence.revision == committedRevision
            && evidence.documentGeneration == committedDocumentGeneration
            && WebRuntimeNavigationIdentity(evidence.committedURL)
                == WebRuntimeNavigationIdentity(committedIdentityURL)
            && evidence.isPDF == committedIsPDF
    }

    private static func sameDocument(
        _ lhs: TabCommittedDocumentEvidence,
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
