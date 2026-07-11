import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabMainFrameRuntimeTransactionTests: XCTestCase {
    func testAbortingLifecycleAuthorityPromotesSubmittedLedgerParticipant() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/document"))
        let authorityWebView = WKWebView()
        let submittedWebView = WKWebView()
        let tab = Tab(url: targetURL, loadsCachedFaviconOnInit: false)
        let intent = tab.beginMainFrameNavigationIntent(to: targetURL)
        let authorityNavigation = NSObject()
        let authorityNavigationID = ObjectIdentifier(authorityNavigation)

        let authorityLease = try XCTUnwrap(
            tab.mainFrameLoads.claimDirectSubmission(on: authorityWebView)
        )
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
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
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
            on: submittedWebView,
            navigationID: promotedNavigationID,
            navigationLifetime: promotedNavigation,
            matching: submittedLease
        ))
        XCTAssertEqual(tab.recordMainFrameCommitSnapshot(
            from: submittedWebView,
            navigationID: promotedNavigationID,
            committedURL: targetURL,
            isPDF: false
        ).role, .authority)
    }

    func testFailedIntentRollsBackToDurableCommittedDocumentWithoutReplica() throws {
        let initialURL = try XCTUnwrap(URL(string: "https://example.com/initial"))
        let committedURL = try XCTUnwrap(URL(string: "https://example.com/committed"))
        let failedURL = try XCTUnwrap(URL(string: "safari-web-extension://broken/page.html"))
        let webView = WKWebView()
        let tab = Tab(url: initialURL, loadsCachedFaviconOnInit: false)
        _ = tab.beginMainFrameNavigationIntent(to: committedURL)
        let navigation = NSObject()
        let navigationID = ObjectIdentifier(navigation)

        let lease = try XCTUnwrap(tab.mainFrameLoads.claimDirectSubmission(on: webView))
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
            on: webView,
            navigationID: navigationID,
            navigationLifetime: navigation,
            matching: lease
        ))
        XCTAssertTrue(tab.recordMainFrameCommitSnapshot(
            from: webView,
            navigationID: navigationID,
            committedURL: committedURL,
            isPDF: false
        ).shouldPublishSharedEffects)
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
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
            on: webView,
            navigationID: crashedNavigationID,
            navigationLifetime: crashedNavigation,
            matching: crashedLease
        ))

        let firstPlan = tab.beginWebContentProcessRecovery(on: webView)
        XCTAssertEqual(firstPlan.scope, .global(targetURL))
        XCTAssertTrue(tab.requiresWebContentProcessRecovery(on: webView))

        let duplicatePlan = tab.beginWebContentProcessRecovery(on: webView)
        XCTAssertEqual(duplicatePlan.scope, .replica(intent))
        XCTAssertNil(duplicatePlan.authorityContinuation)
        XCTAssertTrue(tab.requiresWebContentProcessRecovery(on: webView))

        let successorLease = try XCTUnwrap(
            tab.mainFrameLoads.claimDirectSubmission(on: webView)
        )
        let successorNavigation = NSObject()
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
            on: webView,
            navigationID: ObjectIdentifier(successorNavigation),
            navigationLifetime: successorNavigation,
            matching: successorLease
        ))
        XCTAssertFalse(tab.requiresWebContentProcessRecovery(on: webView))
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
        XCTAssertTrue(transaction.recordCommit(
            from: webView,
            navigationID: navigationID,
            committedURL: targetURL,
            isPDF: false
        ).shouldPublishSharedEffects)

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
            roleObservedByEffect = transaction.lifecycleRole(
                from: webView,
                navigationID: navigationID,
                isCurrent: true
            )
        }
        let plan = transaction.beginWebContentProcessRecovery(on: webView)

        XCTAssertEqual(plan.scope, .global(targetURL))
        XCTAssertEqual(effects.reasons, ["web-content-process-recovery"])
        XCTAssertEqual(roleObservedByEffect, .stale)
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
        _ = transaction.recordCommit(
            from: webView,
            navigationID: navigationID,
            committedURL: targetURL,
            isPDF: false
        )
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
