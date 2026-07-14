import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabMainFrameFinishSettlementTests: XCTestCase {
    func testFinishPublicationPermitIsConsumedOnce() throws {
        let fixture = try makeCommittedAuthorityFixture()

        guard case .publish(let publication) = fixture.transaction.settleFinish(
            from: fixture.webView,
            navigationID: fixture.navigationID,
            navigationLifetime: fixture.navigationLifetime,
            terminalURL: fixture.targetURL
        ) else {
            return XCTFail("Expected exact finish publication")
        }

        TabMainFrameLifecycleReducer.publishFinish(
            publication,
            tab: fixture.tab,
            lifecycle: fixture.transaction
        )
        TabMainFrameLifecycleReducer.publishFinish(
            publication,
            tab: fixture.tab,
            lifecycle: fixture.transaction
        )

        XCTAssertEqual(fixture.tab.loadingState, .didFinish)
        XCTAssertEqual(fixture.runtime.siteDataPolicyTabIds, [fixture.tab.id])
        XCTAssertEqual(
            fixture.runtime.documentSuspensionReconcileTabIds,
            [fixture.tab.id]
        )
    }

    func testExactDuplicateFinishRecoversUnconsumedPermitWithoutDuplicateEffects() throws {
        let fixture = try makeCommittedAuthorityFixture()

        guard case .publish(let abandoned) = fixture.transaction.settleFinish(
            from: fixture.webView,
            navigationID: fixture.navigationID,
            navigationLifetime: fixture.navigationLifetime,
            terminalURL: fixture.targetURL
        ) else {
            return XCTFail("Expected exact finish publication")
        }
        guard case .publish(let reissued) = fixture.transaction.settleFinish(
            from: fixture.webView,
            navigationID: fixture.navigationID,
            navigationLifetime: fixture.navigationLifetime,
            terminalURL: fixture.targetURL
        ) else {
            return XCTFail("Expected the duplicate to recover the reservation")
        }
        XCTAssertEqual(abandoned.permit, reissued.permit)

        TabMainFrameLifecycleReducer.publishFinish(
            reissued,
            tab: fixture.tab,
            lifecycle: fixture.transaction
        )

        XCTAssertFalse(fixture.transaction.consumeFinishPublication(abandoned))
        guard case .alreadyPublished = fixture.transaction.settleFinish(
            from: fixture.webView,
            navigationID: fixture.navigationID,
            navigationLifetime: fixture.navigationLifetime,
            terminalURL: fixture.targetURL
        ) else {
            return XCTFail("Published finish must not reissue a permit")
        }
        XCTAssertEqual(fixture.runtime.siteDataPolicyTabIds, [fixture.tab.id])
    }

    func testFinishRecoveryRejectsDifferentNavigationIdentityOrLifetime() throws {
        let fixture = try makeCommittedAuthorityFixture()
        guard case .publish(let abandoned) = fixture.transaction.settleFinish(
            from: fixture.webView,
            navigationID: fixture.navigationID,
            navigationLifetime: fixture.navigationLifetime,
            terminalURL: fixture.targetURL
        ) else {
            return XCTFail("Expected exact finish publication")
        }

        let foreignNavigation = NSObject()
        guard case .stale = fixture.transaction.settleFinish(
            from: fixture.webView,
            navigationID: ObjectIdentifier(foreignNavigation),
            navigationLifetime: foreignNavigation,
            terminalURL: fixture.targetURL
        ) else {
            return XCTFail("Different navigation identity must not recover permit")
        }
        guard case .stale = fixture.transaction.settleFinish(
            from: fixture.webView,
            navigationID: fixture.navigationID,
            navigationLifetime: foreignNavigation,
            terminalURL: fixture.targetURL
        ) else {
            return XCTFail("Different navigation lifetime must not recover permit")
        }
        guard case .publish(let reissued) = fixture.transaction.settleFinish(
            from: fixture.webView,
            navigationID: fixture.navigationID,
            navigationLifetime: fixture.navigationLifetime,
            terminalURL: fixture.targetURL
        ) else {
            return XCTFail("Exact duplicate must retain recoverability")
        }
        XCTAssertEqual(abandoned.permit, reissued.permit)
    }

    func testReissuedAbandonedFinishBecomesStaleAfterSuccessorIntent() throws {
        let fixture = try makeCommittedAuthorityFixture()
        guard case .publish(let abandoned) = fixture.transaction.settleFinish(
            from: fixture.webView,
            navigationID: fixture.navigationID,
            navigationLifetime: fixture.navigationLifetime,
            terminalURL: fixture.targetURL
        ) else {
            return XCTFail("Expected exact finish publication")
        }
        guard case .publish(let reissued) = fixture.transaction.settleFinish(
            from: fixture.webView,
            navigationID: fixture.navigationID,
            navigationLifetime: fixture.navigationLifetime,
            terminalURL: fixture.targetURL
        ) else {
            return XCTFail("Expected exact abandoned publication reissue")
        }
        XCTAssertEqual(abandoned.permit, reissued.permit)

        let successorURL = try XCTUnwrap(
            URL(string: "https://example.com/successor")
        )
        _ = fixture.tab.beginMainFrameNavigationIntent(to: successorURL)

        XCTAssertFalse(fixture.transaction.consumeFinishPublication(abandoned))
        XCTAssertFalse(fixture.transaction.consumeFinishPublication(reissued))
        guard case .stale = fixture.transaction.settleFinish(
            from: fixture.webView,
            navigationID: fixture.navigationID,
            navigationLifetime: fixture.navigationLifetime,
            terminalURL: fixture.targetURL
        ) else {
            return XCTFail("Successor intent must retire the exact old finish identity")
        }
    }

    func testSameDocumentPublicationIsOneShotAndCannotPublishFinishEffects() throws {
        let fixture = try makeCommittedAuthorityFixture()
        let presentationURL = try XCTUnwrap(
            URL(string: "https://example.com/target#section")
        )
        guard case .publish(let publication) =
                fixture.transaction.settleSameDocument(
                    from: fixture.webView,
                    navigationID: fixture.navigationID,
                    navigationLifetime: fixture.navigationLifetime,
                    presentationURL: presentationURL
                ) else {
            return XCTFail("Expected same-document publication")
        }

        TabMainFrameLifecycleReducer.publishSameDocument(
            publication,
            navigationType: .anchorNavigation,
            tab: fixture.tab,
            lifecycle: fixture.transaction
        )
        TabMainFrameLifecycleReducer.publishSameDocument(
            publication,
            navigationType: .anchorNavigation,
            tab: fixture.tab,
            lifecycle: fixture.transaction
        )

        XCTAssertEqual(fixture.tab.url, presentationURL)
        XCTAssertNotEqual(fixture.tab.loadingState, .didFinish)
        XCTAssertTrue(fixture.runtime.siteDataPolicyTabIds.isEmpty)
        XCTAssertFalse(
            fixture.transaction.consumeSameDocumentPublication(publication)
        )
    }

    func testPromotedSameDocumentReplicaDoesNotRequestFullFinishReplay() throws {
        let fixture = try makeCommittedAuthorityWithReplicaFixture()
        let presentationURL = try XCTUnwrap(
            URL(string: "https://example.com/document#replica")
        )
        guard case .participant = fixture.transaction.settleSameDocument(
            from: fixture.replicaWebView,
            navigationID: fixture.replicaNavigationID,
            navigationLifetime: fixture.replicaNavigationLifetime,
            presentationURL: presentationURL
        ) else {
            return XCTFail("Expected same-document replica completion")
        }

        let departure = fixture.transaction.webViewsDidLeaveRuntime(
            [fixture.authorityWebView],
            preferredAuthorityWebView: fixture.replicaWebView
        )
        let continuation = try XCTUnwrap(departure.continuation)
        XCTAssertTrue(continuation.isCompleted)
        XCTAssertFalse(continuation.needsSharedFinishEffects)
        XCTAssertEqual(continuation.targetURL, presentationURL)

        TabMainFrameLifecycleReducer.replayIfNeeded(
            continuation,
            tab: fixture.tab,
            promotion: fixture.transaction
        )
        XCTAssertNotEqual(fixture.tab.loadingState, .didFinish)
        XCTAssertEqual(fixture.tab.url, presentationURL)
        XCTAssertTrue(fixture.runtime.siteDataPolicyTabIds.isEmpty)
    }

    func testCompletionInvalidatesActiveLeaseAndIssuesValidCompletedLease() throws {
        let fixture = try makeCommittedAuthorityFixture()

        XCTAssertTrue(
            fixture.transaction.remainsCurrent(fixture.commitPublication.authority)
        )
        guard case .publish(let publication) = fixture.transaction.settleFinish(
            from: fixture.webView,
            navigationID: fixture.navigationID,
            navigationLifetime: fixture.navigationLifetime,
            terminalURL: fixture.targetURL
        ) else {
            return XCTFail("Expected exact finish publication")
        }

        XCTAssertFalse(
            fixture.transaction.remainsCurrent(fixture.commitPublication.authority)
        )
        XCTAssertTrue(fixture.transaction.remainsCurrent(publication.authority))
        XCTAssertTrue(fixture.transaction.consumeFinishPublication(publication))
    }

    func testPromotedExactAuthorityRecoversAbandonedFinishReservationOnce() throws {
        let fixture = try makeCommittedAuthorityWithReplicaFixture()

        guard case .participant = fixture.transaction.settleFinish(
            from: fixture.replicaWebView,
            navigationID: fixture.replicaNavigationID,
            navigationLifetime: fixture.replicaNavigationLifetime,
            terminalURL: fixture.targetURL
        ) else {
            return XCTFail("Replica finish must complete without shared effects")
        }
        guard case .publish(let abandoned) = fixture.transaction.settleFinish(
            from: fixture.authorityWebView,
            navigationID: fixture.authorityNavigationID,
            navigationLifetime: fixture.authorityNavigationLifetime,
            terminalURL: fixture.targetURL
        ) else {
            return XCTFail("Expected the authority finish publication")
        }
        XCTAssertTrue(fixture.runtime.siteDataPolicyTabIds.isEmpty)

        let departure = fixture.transaction.webViewsDidLeaveRuntime(
            [fixture.authorityWebView],
            preferredAuthorityWebView: fixture.replicaWebView
        )
        let continuation = try XCTUnwrap(departure.continuation)
        XCTAssertTrue(continuation.isCompleted)
        XCTAssertTrue(continuation.needsSharedFinishEffects)

        TabMainFrameLifecycleReducer.replayIfNeeded(
            continuation,
            tab: fixture.tab,
            promotion: fixture.transaction
        )

        XCTAssertEqual(fixture.tab.loadingState, .didFinish)
        XCTAssertEqual(fixture.runtime.siteDataPolicyTabIds, [fixture.tab.id])
        XCTAssertFalse(fixture.transaction.consumeFinishPublication(abandoned))

        TabMainFrameLifecycleReducer.replayIfNeeded(
            continuation,
            tab: fixture.tab,
            promotion: fixture.transaction
        )
        XCTAssertEqual(fixture.runtime.siteDataPolicyTabIds, [fixture.tab.id])
    }

    func testStalePromotionContinuationCannotPublishFinish() throws {
        let fixture = try makeCommittedAuthorityWithReplicaFixture()
        _ = fixture.transaction.settleFinish(
            from: fixture.replicaWebView,
            navigationID: fixture.replicaNavigationID,
            navigationLifetime: fixture.replicaNavigationLifetime,
            terminalURL: fixture.targetURL
        )
        _ = fixture.transaction.settleFinish(
            from: fixture.authorityWebView,
            navigationID: fixture.authorityNavigationID,
            navigationLifetime: fixture.authorityNavigationLifetime,
            terminalURL: fixture.targetURL
        )
        let departure = fixture.transaction.webViewsDidLeaveRuntime(
            [fixture.authorityWebView],
            preferredAuthorityWebView: fixture.replicaWebView
        )
        let continuation = try XCTUnwrap(departure.continuation)

        let foreignWitness = TabMainFrameAuthorityContinuation(
            webView: WKWebView(),
            navigationID: continuation.navigationID,
            targetURL: continuation.targetURL,
            isPDF: continuation.isPDF,
            isCompleted: continuation.isCompleted,
            needsSharedCommitEffects: continuation.needsSharedCommitEffects,
            needsSharedFinishEffects: continuation.needsSharedFinishEffects,
            revision: continuation.revision,
            documentGeneration: continuation.documentGeneration,
            participantID: continuation.participantID,
            webViewID: continuation.webViewID,
            source: continuation.source
        )
        TabMainFrameLifecycleReducer.replayIfNeeded(
            foreignWitness,
            tab: fixture.tab,
            promotion: fixture.transaction
        )
        XCTAssertTrue(fixture.runtime.siteDataPolicyTabIds.isEmpty)

        let activePhase = TabMainFrameAuthorityContinuation(
            webView: continuation.webView,
            navigationID: continuation.navigationID,
            targetURL: continuation.targetURL,
            isPDF: continuation.isPDF,
            isCompleted: false,
            needsSharedCommitEffects: continuation.needsSharedCommitEffects,
            needsSharedFinishEffects: continuation.needsSharedFinishEffects,
            revision: continuation.revision,
            documentGeneration: continuation.documentGeneration,
            participantID: continuation.participantID,
            webViewID: continuation.webViewID,
            source: continuation.source
        )
        TabMainFrameLifecycleReducer.replayIfNeeded(
            activePhase,
            tab: fixture.tab,
            promotion: fixture.transaction
        )
        XCTAssertTrue(fixture.runtime.siteDataPolicyTabIds.isEmpty)

        _ = fixture.tab.beginMainFrameNavigationIntent(
            to: try XCTUnwrap(URL(string: "https://example.com/successor"))
        )
        TabMainFrameLifecycleReducer.replayIfNeeded(
            continuation,
            tab: fixture.tab,
            promotion: fixture.transaction
        )
        XCTAssertTrue(fixture.runtime.siteDataPolicyTabIds.isEmpty)
        XCTAssertNotEqual(fixture.tab.loadingState, .didFinish)
    }

    func testReplicaFinishCompletesLifecycleWithoutSharedEffects() throws {
        let fixture = try makeCommittedAuthorityWithReplicaFixture()

        guard case .participant = fixture.transaction.settleFinish(
            from: fixture.replicaWebView,
            navigationID: fixture.replicaNavigationID,
            navigationLifetime: fixture.replicaNavigationLifetime,
            terminalURL: fixture.targetURL
        ) else {
            return XCTFail("Replica finish must complete without shared effects")
        }

        XCTAssertTrue(fixture.runtime.siteDataPolicyTabIds.isEmpty)
        XCTAssertTrue(fixture.runtime.documentSuspensionReconcileTabIds.isEmpty)
        XCTAssertNotEqual(fixture.tab.loadingState, .didFinish)

        // The completed replica is a recoverable promotion candidate, which
        // proves its lifecycle state settled instead of leaking an active
        // navigation.
        let departure = fixture.transaction.webViewsDidLeaveRuntime(
            [fixture.authorityWebView],
            preferredAuthorityWebView: fixture.replicaWebView
        )
        let continuation = try XCTUnwrap(departure.continuation)
        XCTAssertTrue(continuation.isCompleted)
        XCTAssertEqual(
            continuation.webViewID,
            ObjectIdentifier(fixture.replicaWebView)
        )
    }

    // MARK: - Fixtures

    private struct CommittedAuthorityFixture {
        let transaction: TabMainFrameRuntimeTransaction
        let tab: Tab
        let runtime: RecordingTabLifecycleNavigationRuntime
        let webView: WKWebView
        let navigationID: ObjectIdentifier
        let navigationLifetime: NSObject
        let targetURL: URL
        let commitPublication: TabMainFrameCommitPublication
    }

    private struct CommittedAuthorityWithReplicaFixture {
        let transaction: TabMainFrameRuntimeTransaction
        let tab: Tab
        let runtime: RecordingTabLifecycleNavigationRuntime
        let authorityWebView: WKWebView
        let authorityNavigationID: ObjectIdentifier
        let replicaWebView: WKWebView
        let replicaNavigationID: ObjectIdentifier
        let authorityNavigationLifetime: NSObject
        let replicaNavigationLifetime: NSObject
        let targetURL: URL
    }

    private func makeCommittedAuthorityFixture() throws -> CommittedAuthorityFixture {
        let initialURL = try XCTUnwrap(URL(string: "https://example.com/initial"))
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/target"))
        let transaction = TabMainFrameRuntimeTransaction(initialURL: initialURL)
        let tab = Tab(
            url: initialURL,
            loadsCachedFaviconOnInit: false,
            mainFrameRuntimeTransaction: transaction
        )
        let runtime = RecordingTabLifecycleNavigationRuntime()
        tab.navigationRuntime.lifecycleNavigationRuntime = runtime.runtime
        let webView = WKWebView()
        _ = tab.beginMainFrameNavigationIntent(to: targetURL)
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
        let commitDecision = transaction.settleCommit(
            from: webView,
            navigationID: navigationID,
            navigationLifetime: navigation,
            committedURL: targetURL
        )
        let commitPublication: TabMainFrameCommitPublication? = {
            guard case .publish(let publication) = commitDecision else { return nil }
            return publication
        }()
        let exactCommitPublication = try XCTUnwrap(commitPublication)
        TabMainFrameLifecycleReducer.publishCommit(
            exactCommitPublication,
            tab: tab,
            lifecycle: transaction
        )
        return CommittedAuthorityFixture(
            transaction: transaction,
            tab: tab,
            runtime: runtime,
            webView: webView,
            navigationID: navigationID,
            navigationLifetime: navigation,
            targetURL: targetURL,
            commitPublication: exactCommitPublication
        )
    }

    private func makeCommittedAuthorityWithReplicaFixture() throws
        -> CommittedAuthorityWithReplicaFixture {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/document"))
        let transaction = TabMainFrameRuntimeTransaction(initialURL: targetURL)
        let tab = Tab(
            url: targetURL,
            loadsCachedFaviconOnInit: false,
            mainFrameRuntimeTransaction: transaction
        )
        let runtime = RecordingTabLifecycleNavigationRuntime()
        tab.navigationRuntime.lifecycleNavigationRuntime = runtime.runtime
        let authorityWebView = WKWebView()
        let replicaWebView = WKWebView()
        let intent = tab.beginMainFrameNavigationIntent(to: targetURL)
        let authoritySubmission = try XCTUnwrap(
            tab.mainFrameLoads.claimDirectSubmission(on: authorityWebView)
        )
        XCTAssertTrue(tab.mainFrameLoads.markDeferredLoad(
            on: replicaWebView,
            intent: intent
        ))
        XCTAssertEqual(
            tab.mainFrameLoads.claimDeferredSubmission(
                on: replicaWebView,
                revision: intent.revision,
                targetURL: targetURL
            ),
            .claimed
        )
        let authorityNavigation = NSObject()
        let replicaNavigation = NSObject()
        XCTAssertTrue(transaction.bindSubmittedLoad(
            on: authorityWebView,
            navigationID: ObjectIdentifier(authorityNavigation),
            navigationLifetime: authorityNavigation,
            matching: authoritySubmission
        ))
        XCTAssertTrue(transaction.bindSubmittedLoad(
            on: replicaWebView,
            navigationID: ObjectIdentifier(replicaNavigation),
            navigationLifetime: replicaNavigation,
            matching: nil
        ))
        let commitDecision = transaction.settleCommit(
            from: authorityWebView,
            navigationID: ObjectIdentifier(authorityNavigation),
            navigationLifetime: authorityNavigation,
            committedURL: targetURL
        )
        let commitPublication: TabMainFrameCommitPublication? = {
            guard case .publish(let publication) = commitDecision else { return nil }
            return publication
        }()
        let exactCommitPublication = try XCTUnwrap(commitPublication)
        TabMainFrameLifecycleReducer.publishCommit(
            exactCommitPublication,
            tab: tab,
            lifecycle: transaction
        )
        let replicaDecision = transaction.settleCommit(
            from: replicaWebView,
            navigationID: ObjectIdentifier(replicaNavigation),
            navigationLifetime: replicaNavigation,
            committedURL: targetURL
        )
        guard case .participant = replicaDecision else {
            XCTFail("Expected committed replica")
            return try XCTUnwrap(nil as CommittedAuthorityWithReplicaFixture?)
        }
        return CommittedAuthorityWithReplicaFixture(
            transaction: transaction,
            tab: tab,
            runtime: runtime,
            authorityWebView: authorityWebView,
            authorityNavigationID: ObjectIdentifier(authorityNavigation),
            replicaWebView: replicaWebView,
            replicaNavigationID: ObjectIdentifier(replicaNavigation),
            authorityNavigationLifetime: authorityNavigation,
            replicaNavigationLifetime: replicaNavigation,
            targetURL: targetURL
        )
    }
}
