import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabMainFrameRuntimeTransactionTests: XCTestCase {
    func testRejectedPromotionPublicationsCannotMutateTabPresentation() throws {
        let initialURL = try XCTUnwrap(URL(string: "https://example.com/initial"))
        let rejectedURL = try XCTUnwrap(URL(string: "https://example.com/rejected"))
        let tab = Tab(url: initialURL, loadsCachedFaviconOnInit: false)
        let webView = WKWebView()
        let continuation = TabMainFrameAuthorityContinuation(
            webView: webView,
            navigationID: nil,
            targetURL: rejectedURL,
            isPDF: false,
            isCompleted: true,
            needsSharedCommitEffects: true,
            needsSharedFinishEffects: true,
            revision: .max,
            documentGeneration: .max,
            participantID: UUID(),
            webViewID: ObjectIdentifier(webView)
        )

        TabMainFrameLifecycleReducer.publishCommit(
            .promotion(continuation),
            tab: tab
        )
        TabMainFrameLifecycleReducer.publishFinish(
            .promotion(continuation),
            tab: tab
        )

        XCTAssertEqual(tab.url, initialURL)
        XCTAssertEqual(tab.loadingState, .idle)
    }

    func testStaleCommitAndFinishPublicationsCannotMutateTabPresentation() throws {
        let initialURL = try XCTUnwrap(URL(string: "https://example.com/initial"))
        let committedURL = try XCTUnwrap(URL(string: "https://example.com/committed"))
        let successorURL = try XCTUnwrap(URL(string: "https://example.com/successor"))
        let transaction = TabMainFrameRuntimeTransaction(initialURL: initialURL)
        let tab = Tab(
            url: initialURL,
            loadsCachedFaviconOnInit: false,
            mainFrameRuntimeTransaction: transaction
        )
        let webView = WKWebView()
        _ = tab.beginMainFrameNavigationIntent(to: committedURL)
        let submission = try XCTUnwrap(
            tab.mainFrameLoads.claimDirectSubmission(on: webView)
        )
        let navigation = NSObject()
        let navigationID = ObjectIdentifier(navigation)
        XCTAssertTrue(transaction.bindSubmittedLoad(
            on: webView,
            navigationID: navigationID,
            navigationLifetime: navigation,
            matching: submission
        ))
        let decision = transaction.settleCommit(
            from: webView,
            navigationID: navigationID,
            committedURL: committedURL
        )
        guard case .publish(let publication) = decision else {
            return XCTFail("Expected exact commit publication")
        }

        _ = tab.beginMainFrameNavigationIntent(to: successorURL)
        TabMainFrameLifecycleReducer.publishCommit(
            .navigation(
                webView: publication.webView,
                navigationID: publication.navigationID,
                targetURL: publication.targetURL,
                isPDF: publication.isPDF
            ),
            tab: tab
        )
        TabMainFrameLifecycleReducer.publishFinish(
            .navigation(
                webView: publication.webView,
                navigationID: publication.navigationID,
                targetURL: publication.targetURL,
                isPDF: publication.isPDF
            ),
            tab: tab
        )

        XCTAssertEqual(tab.url, initialURL)
        XCTAssertEqual(tab.loadingState, .idle)
    }

    func testCommitDecisionOwnsExactMIMEEvidenceAndClaimsPublicationOnce() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/document"))
        let transaction = TabMainFrameRuntimeTransaction(initialURL: targetURL)
        let intent = transaction.beginExplicitIntent(to: targetURL)
        let authorityWebView = WKWebView()
        let replicaWebView = WKWebView()
        let authorityNavigation = NSObject()
        let replicaNavigation = NSObject()

        let authorityLease = try XCTUnwrap(
            transaction.mainFrameLoads.claimDirectSubmission(
                on: authorityWebView
            )
        )
        XCTAssertTrue(transaction.bindSubmittedLoad(
            on: authorityWebView,
            navigationID: ObjectIdentifier(authorityNavigation),
            navigationLifetime: authorityNavigation,
            matching: authorityLease
        ))
        XCTAssertTrue(
            transaction.mainFrameLoads.markDeferredLoad(
                on: replicaWebView,
                intent: intent
            )
        )
        XCTAssertEqual(
            transaction.mainFrameLoads.claimDeferredSubmission(
                on: replicaWebView,
                revision: intent.revision,
                targetURL: targetURL
            ),
            .claimed
        )
        XCTAssertTrue(transaction.bindSubmittedLoad(
            on: replicaWebView,
            navigationID: ObjectIdentifier(replicaNavigation),
            navigationLifetime: replicaNavigation,
            matching: nil
        ))
        transaction.noteResponse(
            isPDF: true,
            from: authorityWebView,
            navigationID: ObjectIdentifier(authorityNavigation)
        )

        let firstDecision = transaction.settleCommit(
            from: authorityWebView,
            navigationID: ObjectIdentifier(authorityNavigation),
            committedURL: targetURL
        )
        guard case .publish(let publication) = firstDecision else {
            return XCTFail("Expected the exact authority to publish its commit")
        }
        XCTAssertIdentical(publication.webView, authorityWebView)
        XCTAssertEqual(
            publication.navigationID,
            ObjectIdentifier(authorityNavigation)
        )
        XCTAssertEqual(publication.targetURL, targetURL)
        XCTAssertTrue(publication.isPDF)

        guard case .alreadyPublished = transaction.settleCommit(
            from: authorityWebView,
            navigationID: ObjectIdentifier(authorityNavigation),
            committedURL: targetURL
        ) else {
            return XCTFail("Duplicate authority commit must not republish")
        }
        guard case .recordedReplica = transaction.settleCommit(
            from: replicaWebView,
            navigationID: ObjectIdentifier(replicaNavigation),
            committedURL: targetURL
        ) else {
            return XCTFail("Compatible sibling must remain a replica")
        }
        guard case .stale = transaction.settleCommit(
            from: replicaWebView,
            navigationID: ObjectIdentifier(NSObject()),
            committedURL: targetURL
        ) else {
            return XCTFail("Foreign navigation identity must fail closed")
        }
    }

    func testAbortingLifecycleAuthorityPromotesSubmittedLedgerParticipant() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/document"))
        let authorityWebView = WKWebView()
        let submittedWebView = WKWebView()
        let transaction = TabMainFrameRuntimeTransaction(initialURL: targetURL)
        let tab = Tab(
            url: targetURL,
            loadsCachedFaviconOnInit: false,
            mainFrameRuntimeTransaction: transaction
        )
        let intent = tab.beginMainFrameNavigationIntent(to: targetURL)
        let authorityNavigation = NSObject()
        let authorityNavigationID = ObjectIdentifier(authorityNavigation)

        let authorityLease = try XCTUnwrap(
            tab.mainFrameLoads.claimDirectSubmission(on: authorityWebView)
        )
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: authorityWebView,
            navigationID: authorityNavigationID,
            navigationLifetime: authorityNavigation,
            matching: authorityLease
        ))
        let submittedLease = try XCTUnwrap(
            tab.mainFrameLoads.claimDirectSubmission(on: submittedWebView)
        )

        let abortResult = tab.abortMainFrameNavigation(
            from: authorityWebView,
            navigationID: authorityNavigationID,
            navigationLifetime: authorityNavigation,
            rollsBackWhenUnreplaced: false
        )
        guard case .authoritativeContinuation(let continuation) = abortResult else {
            return XCTFail("Expected the pending submitted load to inherit authority")
        }
        XCTAssertIdentical(continuation.webView, submittedWebView)
        XCTAssertNil(continuation.navigationID)
        XCTAssertEqual(continuation.revision, intent.revision)
        XCTAssertEqual(continuation.participantID, submittedLease.participantID)

        let promotedNavigation = NSObject()
        let promotedNavigationID = ObjectIdentifier(promotedNavigation)
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: submittedWebView,
            navigationID: promotedNavigationID,
            navigationLifetime: promotedNavigation,
            matching: submittedLease
        ))
        guard case .publish = transaction.settleCommit(
            from: submittedWebView,
            navigationID: promotedNavigationID,
            committedURL: targetURL
        ) else {
            return XCTFail("Promoted submitted participant must publish as authority")
        }
    }

    func testFailedIntentRollsBackToDurableCommittedDocumentWithoutReplica() throws {
        let initialURL = try XCTUnwrap(URL(string: "https://example.com/initial"))
        let committedURL = try XCTUnwrap(URL(string: "https://example.com/committed"))
        let failedURL = try XCTUnwrap(URL(string: "safari-web-extension://broken/page.html"))
        let webView = WKWebView()
        let transaction = TabMainFrameRuntimeTransaction(initialURL: initialURL)
        let tab = Tab(
            url: initialURL,
            loadsCachedFaviconOnInit: false,
            mainFrameRuntimeTransaction: transaction
        )
        _ = tab.beginMainFrameNavigationIntent(to: committedURL)
        let navigation = NSObject()
        let navigationID = ObjectIdentifier(navigation)

        let lease = try XCTUnwrap(tab.mainFrameLoads.claimDirectSubmission(on: webView))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: webView,
            navigationID: navigationID,
            navigationLifetime: navigation,
            matching: lease
        ))
        guard case .publish = transaction.settleCommit(
            from: webView,
            navigationID: navigationID,
            committedURL: committedURL
        ) else {
            return XCTFail("Expected the durable committed document to publish")
        }
        tab.url = committedURL

        let failedIntent = tab.beginMainFrameNavigationIntent(to: failedURL)
        tab.url = failedURL
        tab.rollbackMainFrameNavigationAfterFailedSubmission(on: nil)

        XCTAssertEqual(tab.url, committedURL)
        XCTAssertNil(tab.mainFrameLoads.currentIntent(matching: failedURL))
        let rollbackIntent = try XCTUnwrap(
            tab.mainFrameLoads.currentIntent(matching: committedURL)
        )
        XCTAssertEqual(rollbackIntent.revision, failedIntent.revision + 1)
        XCTAssertNil(tab.committedDocumentRuntime.lease(for: webView))
    }

    func testSuccessfulSuccessorBindingConsumesExactRecoveryMarker() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/recovery"))
        let webView = WKWebView()
        let tab = Tab(url: targetURL, loadsCachedFaviconOnInit: false)
        let intent = tab.beginMainFrameNavigationIntent(to: targetURL)
        let crashedNavigation = NSObject()
        let crashedNavigationID = ObjectIdentifier(crashedNavigation)

        let crashedLease = try XCTUnwrap(tab.mainFrameLoads.claimDirectSubmission(on: webView))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: webView,
            navigationID: crashedNavigationID,
            navigationLifetime: crashedNavigation,
            matching: crashedLease
        ))

        let firstPlan = tab.webContentRecovery.beginRecovery(on: webView)
        XCTAssertEqual(firstPlan.scope, .global(targetURL))
        XCTAssertTrue(tab.webContentRecovery.isRecoveryRequired(on: webView))

        let duplicatePlan = tab.webContentRecovery.beginRecovery(on: webView)
        XCTAssertEqual(duplicatePlan.scope, .replica(intent))
        XCTAssertNil(duplicatePlan.authorityContinuation)
        XCTAssertTrue(tab.webContentRecovery.isRecoveryRequired(on: webView))

        let successorLease = try XCTUnwrap(
            tab.mainFrameLoads.claimDirectSubmission(on: webView)
        )
        let successorNavigation = NSObject()
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: webView,
            navigationID: ObjectIdentifier(successorNavigation),
            navigationLifetime: successorNavigation,
            matching: successorLease
        ))
        XCTAssertFalse(tab.webContentRecovery.isRecoveryRequired(on: webView))
    }

    func testSiblingBindingCannotConsumeCrashedWebViewRecoveryMarker() throws {
        let targetURL = try XCTUnwrap(
            URL(string: "https://example.com/sibling-recovery")
        )
        let crashedWebView = WKWebView()
        let siblingWebView = WKWebView()
        let tab = Tab(url: targetURL, loadsCachedFaviconOnInit: false)
        _ = tab.beginMainFrameNavigationIntent(to: targetURL)
        let crashedNavigation = NSObject()
        let crashedLease = try XCTUnwrap(
            tab.mainFrameLoads.claimDirectSubmission(on: crashedWebView)
        )
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: crashedWebView,
            navigationID: ObjectIdentifier(crashedNavigation),
            navigationLifetime: crashedNavigation,
            matching: crashedLease
        ))
        let siblingLease = try XCTUnwrap(
            tab.mainFrameLoads.claimDirectSubmission(on: siblingWebView)
        )

        let plan = tab.webContentRecovery.beginRecovery(on: crashedWebView)

        XCTAssertIdentical(plan.authorityContinuation?.webView, siblingWebView)
        XCTAssertTrue(
            tab.webContentRecovery.isRecoveryRequired(on: crashedWebView)
        )
        let siblingNavigation = NSObject()
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: siblingWebView,
            navigationID: ObjectIdentifier(siblingNavigation),
            navigationLifetime: siblingNavigation,
            matching: siblingLease
        ))
        XCTAssertTrue(
            tab.webContentRecovery.isRecoveryRequired(on: crashedWebView)
        )
        XCTAssertFalse(
            tab.webContentRecovery.isRecoveryRequired(on: siblingWebView)
        )
    }

    func testAcceptedUnboundLifecycleConsumesOnlyItsExactRecoveryMarker() throws {
        let targetURL = try XCTUnwrap(
            URL(string: "https://example.com/unbound-recovery")
        )
        let recoveredWebView = WKWebView()
        let unrelatedWebView = WKWebView()
        let tab = Tab(url: targetURL, loadsCachedFaviconOnInit: false)
        _ = tab.webContentRecovery.beginRecovery(on: recoveredWebView)
        _ = tab.webContentRecovery.beginRecovery(on: unrelatedWebView)
        let navigation = NSObject()

        XCTAssertEqual(tab.beginMainFrameLifecycle(
            from: recoveredWebView,
            navigationID: ObjectIdentifier(navigation),
            navigationLifetime: navigation,
            targetURL: targetURL,
            allowsUserInitiatedSupersession: false,
            continuationKind: nil
        ), .authority)

        XCTAssertFalse(
            tab.webContentRecovery.isRecoveryRequired(on: recoveredWebView)
        )
        XCTAssertTrue(
            tab.webContentRecovery.isRecoveryRequired(on: unrelatedWebView)
        )
    }

    func testRecoveryMarkerDoesNotRetainReleasedWebView() {
        let markers = TabWebContentRecoveryMarkerLedger()
        weak var releasedWebView: WKWebView?

        autoreleasepool {
            let webView = WKWebView()
            releasedWebView = webView
            XCTAssertTrue(markers.markRequired(on: webView))
        }

        XCTAssertNil(releasedWebView)
    }

    func testProcessRecoveryPublishesOneSettledDecisionAfterLifecycleDeparture() throws {
        let targetURL = try XCTUnwrap(
            URL(string: "https://example.com/settled-recovery")
        )
        let webView = WKWebView()
        let transaction = TabMainFrameRuntimeTransaction(initialURL: targetURL)
        let effects = CommittedDocumentSuspensionEffectsProbe()
        transaction.committedDocumentRuntime.attachSuspensionEffects(effects)
        _ = transaction.beginExplicitIntent(to: targetURL)
        let submission = try XCTUnwrap(
            transaction.mainFrameLoads.claimDirectSubmission(on: webView)
        )
        let navigation = NSObject()
        let navigationID = ObjectIdentifier(navigation)
        XCTAssertTrue(transaction.bindSubmittedLoad(
            on: webView,
            navigationID: navigationID,
            navigationLifetime: navigation,
            matching: submission
        ))
        guard case .publish = transaction.settleCommit(
            from: webView,
            navigationID: navigationID,
            committedURL: targetURL
        ) else {
            return XCTFail("Expected recovery authority commit to publish")
        }

        let lease = try XCTUnwrap(
            transaction.committedDocumentRuntime.lease(for: webView)
        )
        let token = try XCTUnwrap(
            transaction.committedDocumentRuntime
                .suspensionActivationToken(for: webView)
        )
        XCTAssertTrue(
            transaction.committedDocumentRuntime.recordSuspensionReport(
                TabDocumentSuspensionReport(
                    documentNonce: "settled-recovery",
                    documentLeaseToken: token,
                    sequence: 1,
                    canBeSuspended: true,
                    hasPictureInPictureVideo: false
                ),
                from: webView,
                matching: lease
            )
        )
        XCTAssertEqual(
            transaction.committedDocumentRuntime.suspensionDecision,
            .allowed
        )
        effects.reset()

        var roleObservedByEffect: TabMainFrameLifecycleRole?
        effects.onDecisionChange = {
            roleObservedByEffect = transaction.role(
                from: webView,
                navigationID: navigationID,
                isCurrent: true
            )
        }
        let plan = transaction.beginRecovery(on: webView)

        XCTAssertEqual(plan.scope, .global(targetURL))
        XCTAssertEqual(effects.reasons, ["web-content-process-recovery"])
        XCTAssertEqual(roleObservedByEffect, .stale)
        XCTAssertEqual(
            transaction.committedDocumentRuntime.suspensionDecision,
            .awaitingEvidence
        )
        effects.reset()

        let duplicatePlan = transaction.beginRecovery(on: webView)

        XCTAssertEqual(
            duplicatePlan.scope,
            .replica(transaction.mainFrameLoads.currentIntent)
        )
        XCTAssertNil(duplicatePlan.authorityContinuation)
        XCTAssertTrue(effects.reasons.isEmpty)
        XCTAssertEqual(
            transaction.committedDocumentRuntime.suspensionDecision,
            .awaitingEvidence
        )
    }

    func testRejectedAndPictureInPictureReportsPublishOnlyRealDecisionChanges() throws {
        let targetURL = try XCTUnwrap(
            URL(string: "https://example.com/report-settlement")
        )
        let webView = WKWebView()
        let transaction = TabMainFrameRuntimeTransaction(initialURL: targetURL)
        let effects = CommittedDocumentSuspensionEffectsProbe()
        transaction.committedDocumentRuntime.attachSuspensionEffects(effects)
        _ = transaction.beginExplicitIntent(to: targetURL)
        let submission = try XCTUnwrap(
            transaction.mainFrameLoads.claimDirectSubmission(on: webView)
        )
        let navigation = NSObject()
        let navigationID = ObjectIdentifier(navigation)
        XCTAssertTrue(transaction.bindSubmittedLoad(
            on: webView,
            navigationID: navigationID,
            navigationLifetime: navigation,
            matching: submission
        ))
        guard case .publish = transaction.settleCommit(
            from: webView,
            navigationID: navigationID,
            committedURL: targetURL
        ) else {
            return XCTFail("Expected suspension-report authority commit to publish")
        }
        let lease = try XCTUnwrap(
            transaction.committedDocumentRuntime.lease(for: webView)
        )
        let token = try XCTUnwrap(
            transaction.committedDocumentRuntime
                .suspensionActivationToken(for: webView)
        )
        let allowedReport = TabDocumentSuspensionReport(
            documentNonce: "main-document",
            documentLeaseToken: token,
            sequence: 1,
            canBeSuspended: true,
            hasPictureInPictureVideo: false
        )
        XCTAssertTrue(
            transaction.committedDocumentRuntime.recordSuspensionReport(
                allowedReport,
                from: webView,
                matching: lease
            )
        )
        effects.reset()

        XCTAssertFalse(
            transaction.committedDocumentRuntime.recordSuspensionReport(
                allowedReport,
                from: webView,
                matching: lease
            )
        )
        XCTAssertTrue(effects.reasons.isEmpty)

        XCTAssertTrue(
            transaction.committedDocumentRuntime
                .recordSubframePictureInPictureReport(
                    TabSubframePictureInPictureReport(
                        documentNonce: "frame-document",
                        documentLeaseToken: token,
                        sequence: 1,
                        isActive: true
                    ),
                    from: webView,
                    matching: lease
                )
        )
        XCTAssertEqual(effects.reasons, ["subframe-picture-in-picture-state"])
        effects.reset()

        XCTAssertTrue(
            transaction.committedDocumentRuntime
                .recordSubframePictureInPictureReport(
                    TabSubframePictureInPictureReport(
                        documentNonce: "frame-document",
                        documentLeaseToken: token,
                        sequence: 2,
                        isActive: false
                    ),
                    from: webView,
                    matching: lease
                )
        )
        XCTAssertEqual(effects.reasons, ["subframe-picture-in-picture-state"])
    }
}

@MainActor
private final class CommittedDocumentSuspensionEffectsProbe:
    TabCommittedDocumentSuspensionEffects
{
    private(set) var reasons: [String] = []
    var onDecisionChange: (() -> Void)?

    func committedDocumentSuspensionDecisionDidChange(reason: String) {
        reasons.append(reason)
        onDecisionChange?()
    }

    func reset() {
        reasons = []
        onDecisionChange = nil
    }
}
