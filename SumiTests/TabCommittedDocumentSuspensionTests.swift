import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabCommittedDocumentSuspensionTests: XCTestCase {
    func testAllCanonicalPhysicalReplicasMustReportAndAnyVetoBlocks() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/document"))
        let authorityWebView = WKWebView()
        let cloneWebView = WKWebView()
        let ledger = TabCommittedDocumentLedger(initialURL: url)
        let authority = evidence(
            webView: authorityWebView,
            url: url,
            revision: 4,
            generation: 7
        )
        let clone = evidence(
            webView: cloneWebView,
            url: url,
            revision: 4,
            generation: 7
        )
        ledger.recordReplica(clone)
        XCTAssertTrue(ledger.takePendingSuspensionActivations().isEmpty)
        ledger.adoptCanonicalDocument(authority)
        let activatedWebViewIDs = Set(
            ledger.takePendingSuspensionActivations().map {
                ObjectIdentifier($0.webView)
            }
        )
        XCTAssertEqual(
            activatedWebViewIDs,
            Set([
                ObjectIdentifier(authorityWebView),
                ObjectIdentifier(cloneWebView),
            ])
        )
        XCTAssertTrue(ledger.takePendingSuspensionActivations().isEmpty)
        let authorityLease = lease(authority, isAuthority: true)
        let cloneLease = lease(clone, isAuthority: false)
        let authorityToken = try XCTUnwrap(ledger.suspensionToken(
            for: authorityWebView,
            matching: authorityLease
        ))
        let cloneToken = try XCTUnwrap(ledger.suspensionToken(
            for: cloneWebView,
            matching: cloneLease
        ))

        XCTAssertEqual(ledger.suspensionDecision(), .awaitingEvidence)
        XCTAssertTrue(ledger.recordSuspensionReport(
            report(
                nonce: "authority",
                token: authorityToken,
                sequence: 1,
                allows: true
            ),
            from: authorityWebView,
            matching: authorityLease
        ))
        XCTAssertEqual(ledger.suspensionDecision(), .awaitingEvidence)

        XCTAssertTrue(ledger.recordSuspensionReport(
            report(
                nonce: "clone",
                token: cloneToken,
                sequence: 1,
                allows: false
            ),
            from: cloneWebView,
            matching: cloneLease
        ))
        XCTAssertEqual(
            ledger.suspensionDecision(),
            .vetoed(.pageReportedUnableToSuspend)
        )

        XCTAssertFalse(ledger.recordSuspensionReport(
            report(
                nonce: "clone",
                token: cloneToken,
                sequence: 1,
                allows: true
            ),
            from: cloneWebView,
            matching: cloneLease
        ))
        XCTAssertFalse(ledger.recordSuspensionReport(
            report(
                nonce: "different-document",
                token: cloneToken,
                sequence: 2,
                allows: true
            ),
            from: cloneWebView,
            matching: cloneLease
        ))
        XCTAssertEqual(
            ledger.suspensionDecision(),
            .vetoed(.pageReportedUnableToSuspend)
        )

        XCTAssertTrue(ledger.recordSuspensionReport(
            report(
                nonce: "clone",
                token: cloneToken,
                sequence: 2,
                allows: true
            ),
            from: cloneWebView,
            matching: cloneLease
        ))
        XCTAssertEqual(ledger.suspensionDecision(), .allowed)

        ledger.removeWebView(authorityWebView)
        XCTAssertEqual(ledger.suspensionDecision(), .allowed)
    }

    func testSameURLSuccessorDocumentRejectsOldLeaseAndOldSequenceState() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/same-url"))
        let webView = WKWebView()
        let untrackedWebView = WKWebView()
        let ledger = TabCommittedDocumentLedger(initialURL: url)
        let oldDocument = evidence(
            webView: webView,
            url: url,
            revision: 1,
            generation: 1
        )
        ledger.adoptCanonicalDocument(oldDocument)
        let oldActivation = try XCTUnwrap(
            ledger.takePendingSuspensionActivations().first
        )
        let oldLease = lease(oldDocument, isAuthority: true)
        let oldToken = try XCTUnwrap(ledger.suspensionToken(
            for: webView,
            matching: oldLease
        ))
        XCTAssertTrue(ledger.recordSuspensionReport(
            report(
                nonce: "old",
                token: oldToken,
                sequence: 9,
                allows: true
            ),
            from: webView,
            matching: oldLease
        ))
        XCTAssertEqual(ledger.suspensionDecision(), .allowed)

        let successor = evidence(
            webView: webView,
            url: url,
            revision: 2,
            generation: 2
        )
        ledger.adoptCanonicalDocument(successor)
        let successorActivation = try XCTUnwrap(
            ledger.takePendingSuspensionActivations().first
        )
        let successorLease = lease(successor, isAuthority: true)
        let successorToken = try XCTUnwrap(ledger.suspensionToken(
            for: webView,
            matching: successorLease
        ))
        XCTAssertNotEqual(oldToken, successorToken)
        XCTAssertGreaterThan(successorActivation.epoch, oldActivation.epoch)
        XCTAssertEqual(ledger.suspensionDecision(), .awaitingEvidence)
        XCTAssertFalse(ledger.recordSuspensionReport(
            report(
                nonce: "old",
                token: oldToken,
                sequence: 10,
                allows: false
            ),
            from: webView,
            matching: oldLease
        ))
        XCTAssertFalse(ledger.recordSuspensionReport(
            report(
                nonce: "old",
                token: oldToken,
                sequence: 10,
                allows: false
            ),
            from: webView,
            matching: successorLease
        ))
        XCTAssertFalse(ledger.recordSuspensionReport(
            report(
                nonce: "successor",
                token: successorToken,
                sequence: 1,
                allows: false
            ),
            from: untrackedWebView,
            matching: successorLease
        ))
        XCTAssertEqual(ledger.suspensionDecision(), .awaitingEvidence)

        XCTAssertTrue(ledger.recordSuspensionReport(
            report(
                nonce: "successor",
                token: successorToken,
                sequence: 1,
                allows: true
            ),
            from: webView,
            matching: successorLease
        ))
        XCTAssertEqual(ledger.suspensionDecision(), .allowed)
    }

    func testPDFDocumentVetoDoesNotDependOnMutablePageReport() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/report.pdf"))
        let webView = WKWebView()
        let ledger = TabCommittedDocumentLedger(initialURL: url)
        ledger.adoptCanonicalDocument(evidence(
            webView: webView,
            url: url,
            revision: 3,
            generation: 5,
            isPDF: true
        ))

        XCTAssertEqual(ledger.suspensionDecision(), .vetoed(.pdfDocument))
    }

    func testFailedSensorActivationRetriesOnlyForExactTokenAndIsBounded() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/retry"))
        let webView = WKWebView()
        let ledger = TabCommittedDocumentLedger(initialURL: url)
        let document = evidence(
            webView: webView,
            url: url,
            revision: 1,
            generation: 1
        )
        ledger.adoptCanonicalDocument(document)

        let first = try XCTUnwrap(
            ledger.takePendingSuspensionActivations().first
        )
        XCTAssertFalse(ledger.suspensionActivationDidFail(
            for: webView,
            token: "wrong-token",
            epoch: first.epoch
        ))
        XCTAssertFalse(ledger.suspensionActivationDidFail(
            for: webView,
            token: first.token,
            epoch: first.epoch &+ 1
        ))
        XCTAssertTrue(ledger.suspensionActivationDidFail(
            for: webView,
            token: first.token,
            epoch: first.epoch
        ))

        let second = try XCTUnwrap(
            ledger.takePendingSuspensionActivations().first
        )
        XCTAssertEqual(second.token, first.token)
        XCTAssertEqual(second.epoch, first.epoch)
        XCTAssertTrue(ledger.suspensionActivationDidFail(
            for: webView,
            token: second.token,
            epoch: second.epoch
        ))

        let third = try XCTUnwrap(
            ledger.takePendingSuspensionActivations().first
        )
        XCTAssertEqual(third.token, first.token)
        XCTAssertEqual(third.epoch, first.epoch)
        XCTAssertFalse(ledger.suspensionActivationDidFail(
            for: webView,
            token: third.token,
            epoch: third.epoch
        ))
        XCTAssertTrue(ledger.takePendingSuspensionActivations().isEmpty)
        XCTAssertEqual(ledger.suspensionDecision(), .awaitingEvidence)
    }

    func testSuccessorDocumentRejectsStaleActivationFailureEvidence() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/successor"))
        let webView = WKWebView()
        let ledger = TabCommittedDocumentLedger(initialURL: url)
        let firstDocument = evidence(
            webView: webView,
            url: url,
            revision: 1,
            generation: 1
        )
        ledger.adoptCanonicalDocument(firstDocument)
        let firstActivation = try XCTUnwrap(
            ledger.takePendingSuspensionActivations().first
        )

        let successor = evidence(
            webView: webView,
            url: url,
            revision: 2,
            generation: 2
        )
        ledger.adoptCanonicalDocument(successor)
        let successorActivation = try XCTUnwrap(
            ledger.takePendingSuspensionActivations().first
        )

        XCTAssertNotEqual(successorActivation.token, firstActivation.token)
        XCTAssertNotEqual(successorActivation.epoch, firstActivation.epoch)
        XCTAssertFalse(ledger.suspensionActivationDidFail(
            for: webView,
            token: firstActivation.token,
            epoch: firstActivation.epoch
        ))
        XCTAssertTrue(ledger.suspensionActivationDidFail(
            for: webView,
            token: successorActivation.token,
            epoch: successorActivation.epoch
        ))
    }

    func testLedgerDoesNotRetainReleasedWebViewThroughDocumentEvidence() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/released"))
        let ledger = TabCommittedDocumentLedger(initialURL: url)
        weak var releasedWebView: WKWebView?

        autoreleasepool {
            let webView = WKWebView()
            releasedWebView = webView
            ledger.adoptCanonicalDocument(evidence(
                webView: webView,
                url: url,
                revision: 1,
                generation: 1
            ))
        }

        XCTAssertNil(releasedWebView)
        XCTAssertEqual(ledger.suspensionDecision(), .awaitingEvidence)
        XCTAssertTrue(ledger.rollbackSnapshot().candidates.isEmpty)
    }

    func testPDFDocumentSkipsSensorActivationUntilNonPDFSuccessor() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/document.pdf"))
        let webView = WKWebView()
        let ledger = TabCommittedDocumentLedger(initialURL: url)
        ledger.adoptCanonicalDocument(evidence(
            webView: webView,
            url: url,
            revision: 1,
            generation: 1,
            isPDF: true
        ))

        XCTAssertEqual(ledger.suspensionDecision(), .vetoed(.pdfDocument))
        XCTAssertTrue(ledger.takePendingSuspensionActivations().isEmpty)

        ledger.adoptCanonicalDocument(evidence(
            webView: webView,
            url: url,
            revision: 2,
            generation: 2
        ))
        XCTAssertEqual(
            ledger.takePendingSuspensionActivations().count,
            1
        )
    }

    func testDocumentLeaseReadsDurablePresentationFromLedger() throws {
        let committedURL = try XCTUnwrap(
            URL(string: "https://example.com/document")
        )
        let presentationURL = try XCTUnwrap(
            URL(string: "https://example.com/document#reader")
        )
        let webView = WKWebView()
        let ledger = TabCommittedDocumentLedger(initialURL: committedURL)
        let document = evidence(
            webView: webView,
            url: committedURL,
            revision: 1,
            generation: 1
        )
        ledger.adoptCanonicalDocument(document)
        ledger.updatePresentation(presentationURL, on: webView)

        let documentLease = try XCTUnwrap(
            ledger.documentLease(matching: document, isAuthority: true)
        )
        XCTAssertEqual(documentLease.committedURL, committedURL)
        XCTAssertEqual(documentLease.presentationURL, presentationURL)
    }

    func testRollbackKeepsExactDocumentWhenPhysicalURLChangesWithoutCallback() throws {
        let committedURL = try XCTUnwrap(
            URL(string: "https://example.com/search?q=sumi")
        )
        let presentationURL = try XCTUnwrap(
            URL(string: "https://example.com/search?q=sumi&view=results")
        )
        let webView = SumiNavigationURLReportingWebView()
        webView.reportedURL = presentationURL
        webView.reportedCommittedURL = presentationURL
        let ledger = TabCommittedDocumentLedger(initialURL: committedURL)
        ledger.adoptCanonicalDocument(evidence(
            webView: webView,
            url: committedURL,
            revision: 1,
            generation: 1
        ))

        let snapshot = ledger.rollbackSnapshot()

        let candidate = try XCTUnwrap(snapshot.candidates.first)
        XCTAssertEqual(snapshot.candidates.count, 1)
        XCTAssertIdentical(candidate.webView, webView)
        XCTAssertEqual(candidate.committedURL, committedURL)
        XCTAssertEqual(candidate.presentationURL, committedURL)
        XCTAssertEqual(
            snapshot.preferredAuthorityWebViewID,
            ObjectIdentifier(webView)
        )
    }

    func testBatchDepartureRemovesVetoesWithoutDiscardingSurvivorReport() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/clones"))
        let authorityWebView = WKWebView()
        let vetoingWebView = WKWebView()
        let survivingWebView = WKWebView()
        let ledger = TabCommittedDocumentLedger(initialURL: url)
        let authority = evidence(
            webView: authorityWebView,
            url: url,
            revision: 8,
            generation: 13
        )
        let vetoing = evidence(
            webView: vetoingWebView,
            url: url,
            revision: 8,
            generation: 13
        )
        let surviving = evidence(
            webView: survivingWebView,
            url: url,
            revision: 8,
            generation: 13
        )
        ledger.recordReplica(vetoing)
        ledger.recordReplica(surviving)
        ledger.adoptCanonicalDocument(authority)

        for (item, nonce, allows, isAuthority) in [
            (authority, "authority", true, true),
            (vetoing, "veto", false, false),
            (surviving, "survivor", true, false),
        ] {
            let itemLease = lease(item, isAuthority: isAuthority)
            let token = try XCTUnwrap(ledger.suspensionToken(
                for: item.webView,
                matching: itemLease
            ))
            XCTAssertTrue(ledger.recordSuspensionReport(
                report(
                    nonce: nonce,
                    token: token,
                    sequence: 1,
                    allows: allows
                ),
                from: item.webView,
                matching: itemLease
            ))
        }
        XCTAssertEqual(
            ledger.suspensionDecision(),
            .vetoed(.pageReportedUnableToSuspend)
        )

        ledger.removeWebViews(
            [authorityWebView, vetoingWebView],
            preferredSourceWebView: survivingWebView
        )

        XCTAssertEqual(ledger.suspensionDecision(), .allowed)
        XCTAssertIdentical(ledger.sourceWebView(), survivingWebView)
    }

    private func evidence(
        webView: WKWebView,
        url: URL,
        revision: UInt64,
        generation: UInt64,
        isPDF: Bool = false
    ) -> TabCommittedDocumentEvidence {
        TabCommittedDocumentEvidence(
            webView: webView,
            revision: revision,
            documentGeneration: generation,
            participantID: UUID(),
            committedURL: url,
            presentationURL: url,
            isPDF: isPDF
        )
    }

    private func lease(
        _ evidence: TabCommittedDocumentEvidence,
        isAuthority: Bool
    ) -> TabMainFrameDocumentLease {
        TabMainFrameDocumentLease(
            revision: evidence.revision,
            documentGeneration: evidence.documentGeneration,
            webViewID: ObjectIdentifier(evidence.webView),
            participantID: evidence.participantID,
            committedURL: evidence.committedURL,
            presentationURL: evidence.presentationURL,
            isPDF: evidence.isPDF,
            isAuthority: isAuthority
        )
    }

    private func report(
        nonce: String,
        token: String,
        sequence: UInt64,
        allows: Bool
    ) -> TabDocumentSuspensionReport {
        TabDocumentSuspensionReport(
            documentNonce: nonce,
            documentLeaseToken: token,
            sequence: sequence,
            canBeSuspended: allows
        )
    }
}
