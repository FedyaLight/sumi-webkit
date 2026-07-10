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
    }

    private var committedPresentationURL: URL
    private var committedIdentityURL: URL
    private var committedIsPDF = false
    private var sourceWebViewReference: WeakWebViewReference?
    private var replicasByWebViewID: [ObjectIdentifier: Replica] = [:]

    init(initialURL: URL) {
        committedPresentationURL = initialURL
        committedIdentityURL = initialURL
    }

    var rollbackTargetURL: URL {
        committedPresentationURL
    }

    func recordReplica(_ evidence: TabCommittedDocumentEvidence) {
        replicasByWebViewID[ObjectIdentifier(evidence.webView)] = Replica(
            webViewReference: WeakWebViewReference(evidence.webView),
            evidence: evidence
        )
    }

    func adoptCanonicalDocument(_ evidence: TabCommittedDocumentEvidence) {
        committedIdentityURL = evidence.committedURL
        committedPresentationURL = evidence.presentationURL
        committedIsPDF = evidence.isPDF
        sourceWebViewReference = WeakWebViewReference(evidence.webView)
        recordReplica(evidence)
        replicasByWebViewID = replicasByWebViewID.filter { _, replica in
            guard replica.webViewReference.resolve() != nil else { return false }
            return WebRuntimeNavigationIdentity(replica.evidence.committedURL)
                    == WebRuntimeNavigationIdentity(evidence.committedURL)
                && replica.evidence.isPDF == evidence.isPDF
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
              replica.evidence.isPDF == committedIsPDF else {
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
              WebRuntimeNavigationIdentity(replica.evidence.committedURL)
                == WebRuntimeNavigationIdentity(committedIdentityURL),
              replica.evidence.isPDF == committedIsPDF else {
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
              WebRuntimeNavigationIdentity(evidence.committedURL)
                == WebRuntimeNavigationIdentity(committedIdentityURL),
              evidence.isPDF == committedIsPDF else {
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

    func removeWebView(_ webView: WKWebView) {
        replicasByWebViewID.removeValue(forKey: ObjectIdentifier(webView))
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
                  replica.evidence.isPDF == committedIsPDF else {
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
        sourceWebViewReference = WeakWebViewReference(authority.webView)
    }
}
