import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabMainFrameRuntimeTransactionTests: XCTestCase {
    func testCommitPublicationPermitIsConsumedOnce() throws {
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
        let intent = tab.beginMainFrameNavigationIntent(to: targetURL)
        let submission = try XCTUnwrap(tab.mainFrameLoads.claimDirectSubmission(on: webView))
        let navigation = NSObject()
        let navigationID = ObjectIdentifier(navigation)
        XCTAssertTrue(transaction.bindSubmittedLoad(
            on: webView,
            navigationID: navigationID,
            navigationLifetime: navigation,
            matching: submission
        ))
        guard case .publish(let publication) = transaction.settleCommit(
            from: webView,
            navigationID: navigationID,
            navigationLifetime: navigation,
            committedURL: targetURL
        ) else {
            return XCTFail("Expected exact commit publication")
        }

        TabMainFrameLifecycleReducer.publishCommit(
            publication,
            tab: tab,
            lifecycle: transaction
        )
        TabMainFrameLifecycleReducer.publishCommit(
            publication,
            tab: tab,
            lifecycle: transaction
        )

        XCTAssertEqual(runtime.markedEligibleTabIds, [tab.id])
    }

    func testPromotedReplicaRecoversUnconsumedCommitPermit() throws {
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
        guard case .publish(let abandonedPublication) = transaction.settleCommit(
            from: authorityWebView,
            navigationID: ObjectIdentifier(authorityNavigation),
            navigationLifetime: authorityNavigation,
            committedURL: targetURL
        ) else {
            return XCTFail("Expected authority commit reservation")
        }
        guard case .participant = transaction.settleCommit(
            from: replicaWebView,
            navigationID: ObjectIdentifier(replicaNavigation),
            navigationLifetime: replicaNavigation,
            committedURL: targetURL
        ) else {
            return XCTFail("Expected committed replica")
        }

        let departure = transaction.webViewsDidLeaveRuntime(
            [authorityWebView],
            preferredAuthorityWebView: replicaWebView
        )
        let continuation = try XCTUnwrap(departure.continuation)
        XCTAssertTrue(continuation.needsSharedCommitEffects)
        TabMainFrameLifecycleReducer.replayIfNeeded(
            continuation,
            tab: tab,
            promotion: transaction
        )

        XCTAssertEqual(runtime.markedEligibleTabIds, [tab.id])
        XCTAssertFalse(transaction.consumeCommitPublication(abandonedPublication))
    }

    func testDivergentReplicaPromotionMigratesGenerationAndResetsBothEffectLedgers() throws {
        let authorityURL = try XCTUnwrap(
            URL(string: "https://example.com/authority-document")
        )
        let replicaURL = try XCTUnwrap(
            URL(string: "https://example.com/replica-document")
        )
        let transaction = TabMainFrameRuntimeTransaction(initialURL: authorityURL)
        let tab = Tab(
            url: authorityURL,
            loadsCachedFaviconOnInit: false,
            mainFrameRuntimeTransaction: transaction
        )
        let authorityWebView = WKWebView()
        let replicaWebView = WKWebView()
        let intent = tab.beginMainFrameNavigationIntent(to: authorityURL)
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
                targetURL: authorityURL
            ),
            .claimed
        )
        let authorityNavigation = NSObject()
        let replicaNavigation = NSObject()
        let authorityNavigationID = ObjectIdentifier(authorityNavigation)
        let replicaNavigationID = ObjectIdentifier(replicaNavigation)
        XCTAssertTrue(transaction.bindSubmittedLoad(
            on: authorityWebView,
            navigationID: authorityNavigationID,
            navigationLifetime: authorityNavigation,
            matching: authoritySubmission
        ))
        XCTAssertTrue(transaction.bindSubmittedLoad(
            on: replicaWebView,
            navigationID: replicaNavigationID,
            navigationLifetime: replicaNavigation,
            matching: nil
        ))

        guard case .publish(let oldAuthorityLease) =
                transaction.claimTransactionStartEffects(
                    from: authorityWebView,
                    navigationID: authorityNavigationID,
                    navigationLifetime: authorityNavigation
                ) else {
            return XCTFail("Expected authority effects in the original generation")
        }
        guard case .publish = transaction.claimLocalStartEffects(
            from: replicaWebView,
            navigationID: replicaNavigationID,
            navigationLifetime: replicaNavigation
        ) else {
            return XCTFail("Expected replica-local effects in the original generation")
        }
        guard case .publish(let abandonedCommit) = transaction.settleCommit(
            from: authorityWebView,
            navigationID: authorityNavigationID,
            navigationLifetime: authorityNavigation,
            committedURL: authorityURL
        ) else {
            return XCTFail("Expected the original authority to reserve commit effects")
        }
        guard case .participant = transaction.settleCommit(
            from: replicaWebView,
            navigationID: replicaNavigationID,
            navigationLifetime: replicaNavigation,
            committedURL: replicaURL
        ) else {
            return XCTFail("Expected divergent committed replica evidence")
        }

        let departure = transaction.webViewsDidLeaveRuntime(
            [authorityWebView],
            preferredAuthorityWebView: replicaWebView
        )
        let continuation = try XCTUnwrap(departure.continuation)
        XCTAssertEqual(continuation.targetURL, replicaURL)
        XCTAssertEqual(
            continuation.documentGeneration,
            oldAuthorityLease.documentGeneration + 1
        )
        XCTAssertTrue(continuation.needsSharedCommitEffects)
        XCTAssertFalse(transaction.remainsCurrent(oldAuthorityLease))
        XCTAssertFalse(transaction.consumeCommitPublication(abandonedCommit))

        guard case .publish(let promotedLease) =
                transaction.claimTransactionStartEffects(
                    from: replicaWebView,
                    navigationID: replicaNavigationID,
                    navigationLifetime: replicaNavigation
                ) else {
            return XCTFail("Migrated authority effects must be claimable once")
        }
        XCTAssertEqual(
            promotedLease.documentGeneration,
            continuation.documentGeneration
        )
        guard case .publish(let promotedTarget) =
                transaction.claimLocalStartEffects(
                    from: replicaWebView,
                    navigationID: replicaNavigationID,
                    navigationLifetime: replicaNavigation
                ) else {
            return XCTFail("Migrated participant effects must be claimable once")
        }
        XCTAssertEqual(promotedTarget, replicaURL)
        guard case .alreadyPublished = transaction.claimTransactionStartEffects(
            from: replicaWebView,
            navigationID: replicaNavigationID,
            navigationLifetime: replicaNavigation
        ) else {
            return XCTFail("Migrated authority effects must remain one-shot")
        }
        guard case .alreadyPublished = transaction.claimLocalStartEffects(
            from: replicaWebView,
            navigationID: replicaNavigationID,
            navigationLifetime: replicaNavigation
        ) else {
            return XCTFail("Migrated participant effects must remain one-shot")
        }
    }

    func testRejectedPromotionPublicationsCannotMutateTabPresentation() throws {
        let initialURL = try XCTUnwrap(URL(string: "https://example.com/initial"))
        let rejectedURL = try XCTUnwrap(URL(string: "https://example.com/rejected"))
        let transaction = TabMainFrameRuntimeTransaction(initialURL: initialURL)
        let tab = Tab(
            url: initialURL,
            loadsCachedFaviconOnInit: false,
            mainFrameRuntimeTransaction: transaction
        )
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
            webViewID: ObjectIdentifier(webView),
            source: .lifecycle(authorityEpoch: .max)
        )

        TabMainFrameLifecycleReducer.replayIfNeeded(
            continuation,
            tab: tab,
            promotion: transaction
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
            navigationLifetime: navigation,
            committedURL: committedURL
        )
        guard case .publish(let publication) = decision else {
            return XCTFail("Expected exact commit publication")
        }
        guard case .publish(let finishPublication) = transaction.settleFinish(
            from: webView,
            navigationID: navigationID,
            navigationLifetime: navigation,
            terminalURL: committedURL
        ) else {
            return XCTFail("Expected exact finish publication")
        }

        _ = tab.beginMainFrameNavigationIntent(to: successorURL)
        TabMainFrameLifecycleReducer.publishCommit(
            publication,
            tab: tab,
            lifecycle: transaction
        )
        TabMainFrameLifecycleReducer.publishFinish(
            finishPublication,
            tab: tab,
            lifecycle: transaction
        )

        XCTAssertEqual(tab.url, initialURL)
        XCTAssertEqual(tab.loadingState, .idle)
    }

    func testContinuationOutputRetiresPreviousIdentityAndRejectsForeignLifetime() throws {
        let initialURL = try XCTUnwrap(URL(string: "https://example.com/initial"))
        let firstURL = try XCTUnwrap(URL(string: "https://example.com/first"))
        let rewrittenURL = try XCTUnwrap(URL(string: "https://example.com/rewritten"))
        let transaction = TabMainFrameRuntimeTransaction(initialURL: initialURL)
        let tab = Tab(
            url: initialURL,
            loadsCachedFaviconOnInit: false,
            mainFrameRuntimeTransaction: transaction
        )
        let webView = WKWebView()
        _ = tab.beginMainFrameNavigationIntent(to: firstURL)
        let submission = try XCTUnwrap(
            tab.mainFrameLoads.claimDirectSubmission(on: webView)
        )
        let firstNavigation = NSObject()
        let firstNavigationID = ObjectIdentifier(firstNavigation)
        XCTAssertTrue(transaction.bindSubmittedLoad(
            on: webView,
            navigationID: firstNavigationID,
            navigationLifetime: firstNavigation,
            matching: submission
        ))

        let continuation = NSObject()
        let continuationID = ObjectIdentifier(continuation)
        XCTAssertEqual(
            tab.beginMainFrameLifecycle(
                from: webView,
                navigationID: continuationID,
                navigationLifetime: continuation,
                targetURL: rewrittenURL,
                allowsUserInitiatedSupersession: false,
                continuationKind: .requestRewrite
            ),
            .authority
        )
        XCTAssertEqual(
            transaction.role(
                from: webView,
                navigationID: firstNavigationID,
                isCurrent: true
            ),
            .stale
        )
        let foreignLifetime = NSObject()
        XCTAssertEqual(
            tab.beginMainFrameLifecycle(
                from: webView,
                navigationID: firstNavigationID,
                navigationLifetime: foreignLifetime,
                targetURL: firstURL,
                allowsUserInitiatedSupersession: false,
                continuationKind: .requestRewrite
            ),
            .stale
        )
        XCTAssertEqual(
            tab.beginMainFrameLifecycle(
                from: webView,
                navigationID: firstNavigationID,
                navigationLifetime: firstNavigation,
                targetURL: firstURL,
                allowsUserInitiatedSupersession: false,
                continuationKind: .requestRewrite
            ),
            .stale
        )
        guard case .stale = transaction.settleCommit(
            from: webView,
            navigationID: firstNavigationID,
            navigationLifetime: firstNavigation,
            committedURL: firstURL
        ) else {
            return XCTFail("Malformed witness must not erase the exact tombstone")
        }
        XCTAssertEqual(
            transaction.role(
                from: webView,
                navigationID: continuationID,
                isCurrent: true
            ),
            .authority
        )
        guard case .publish = transaction.claimLocalStartEffects(
            from: webView,
            navigationID: continuationID,
            navigationLifetime: continuation
        ) else {
            return XCTFail("Exact continuation must retain its participant effects")
        }
        guard case .alreadyPublished = transaction.claimLocalStartEffects(
            from: webView,
            navigationID: continuationID,
            navigationLifetime: continuation
        ) else {
            return XCTFail("Participant-local effects must remain one-shot")
        }
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
            navigationID: ObjectIdentifier(authorityNavigation),
            navigationLifetime: authorityNavigation
        )

        let firstDecision = transaction.settleCommit(
            from: authorityWebView,
            navigationID: ObjectIdentifier(authorityNavigation),
            navigationLifetime: authorityNavigation,
            committedURL: targetURL
        )
        guard case .publish(let publication) = firstDecision else {
            return XCTFail("Expected the exact authority to publish its commit")
        }
        XCTAssertIdentical(publication.webView, authorityWebView)
        XCTAssertEqual(
            publication.authority.navigationID,
            ObjectIdentifier(authorityNavigation)
        )
        XCTAssertEqual(publication.targetURL, targetURL)
        XCTAssertTrue(publication.isPDF)

        guard case .publish(let retryPublication) = transaction.settleCommit(
            from: authorityWebView,
            navigationID: ObjectIdentifier(authorityNavigation),
            navigationLifetime: authorityNavigation,
            committedURL: targetURL
        ) else {
            return XCTFail("Unconsumed exact commit must reissue its permit")
        }
        XCTAssertEqual(retryPublication.permit, publication.permit)
        guard case .participant = transaction.settleCommit(
            from: replicaWebView,
            navigationID: ObjectIdentifier(replicaNavigation),
            navigationLifetime: replicaNavigation,
            committedURL: targetURL
        ) else {
            return XCTFail("Compatible sibling must remain a replica")
        }
        let foreignNavigation = NSObject()
        guard case .stale = transaction.settleCommit(
            from: replicaWebView,
            navigationID: ObjectIdentifier(foreignNavigation),
            navigationLifetime: foreignNavigation,
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
            navigationLifetime: promotedNavigation,
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
            navigationLifetime: navigation,
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
        let transaction = TabMainFrameRuntimeTransaction(initialURL: targetURL)
        let tab = Tab(
            url: targetURL,
            loadsCachedFaviconOnInit: false,
            mainFrameRuntimeTransaction: transaction
        )
        _ = tab.beginMainFrameNavigationIntent(to: targetURL)
        let crashedNavigation = NSObject()
        let crashedNavigationID = ObjectIdentifier(crashedNavigation)

        let crashedLease = try XCTUnwrap(tab.mainFrameLoads.claimDirectSubmission(on: webView))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: webView,
            navigationID: crashedNavigationID,
            navigationLifetime: crashedNavigation,
            matching: crashedLease
        ))

        let firstPlan = transaction.beginRecovery(on: webView)
        XCTAssertEqual(firstPlan.disposition, .deliver)
        XCTAssertTrue(tab.webContentRecoveryMarkers.isRecoveryRequired(on: webView))

        let duplicatePlan = transaction.beginRecovery(on: webView)
        XCTAssertEqual(duplicatePlan.disposition, .duplicate)
        XCTAssertNil(duplicatePlan.authorityContinuation)
        XCTAssertTrue(tab.webContentRecoveryMarkers.isRecoveryRequired(on: webView))

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
        XCTAssertFalse(tab.webContentRecoveryMarkers.isRecoveryRequired(on: webView))
    }

    func testSiblingBindingCannotConsumeCrashedWebViewRecoveryMarker() throws {
        let targetURL = try XCTUnwrap(
            URL(string: "https://example.com/sibling-recovery")
        )
        let crashedWebView = WKWebView()
        let siblingWebView = WKWebView()
        let transaction = TabMainFrameRuntimeTransaction(initialURL: targetURL)
        let tab = Tab(
            url: targetURL,
            loadsCachedFaviconOnInit: false,
            mainFrameRuntimeTransaction: transaction
        )
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

        let plan = transaction.beginRecovery(on: crashedWebView)

        XCTAssertIdentical(plan.authorityContinuation?.webView, siblingWebView)
        XCTAssertTrue(
            tab.webContentRecoveryMarkers.isRecoveryRequired(on: crashedWebView)
        )
        let siblingNavigation = NSObject()
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: siblingWebView,
            navigationID: ObjectIdentifier(siblingNavigation),
            navigationLifetime: siblingNavigation,
            matching: siblingLease
        ))
        XCTAssertTrue(
            tab.webContentRecoveryMarkers.isRecoveryRequired(on: crashedWebView)
        )
        XCTAssertFalse(
            tab.webContentRecoveryMarkers.isRecoveryRequired(on: siblingWebView)
        )
    }

    func testUnownedLifecycleCannotConsumeExactRecoveryEpoch() throws {
        let targetURL = try XCTUnwrap(
            URL(string: "https://example.com/unbound-recovery")
        )
        let recoveredWebView = WKWebView()
        let unrelatedWebView = WKWebView()
        let transaction = TabMainFrameRuntimeTransaction(initialURL: targetURL)
        let tab = Tab(
            url: targetURL,
            loadsCachedFaviconOnInit: false,
            mainFrameRuntimeTransaction: transaction
        )
        _ = transaction.beginRecovery(on: recoveredWebView)
        _ = transaction.beginRecovery(on: unrelatedWebView)
        let navigation = NSObject()

        XCTAssertEqual(tab.beginMainFrameLifecycle(
            from: recoveredWebView,
            navigationID: ObjectIdentifier(navigation),
            navigationLifetime: navigation,
            targetURL: targetURL,
            allowsUserInitiatedSupersession: false,
            continuationKind: nil
        ), .authority)

        XCTAssertTrue(
            tab.webContentRecoveryMarkers.isRecoveryRequired(on: recoveredWebView)
        )
        XCTAssertFalse(
            tab.webContentRecoveryMarkers.isRecoveryRequired(on: unrelatedWebView)
        )
        XCTAssertTrue(
            tab.webContentRecoveryMarkers.recoveryState(on: unrelatedWebView)?
                .isFailure == true
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

    func testRecoveryEpochRejectsSecondTerminationAfterConcreteBinding() throws {
        let targetURL = try XCTUnwrap(
            URL(string: "https://example.com/recovery-epoch")
        )
        let transaction = TabMainFrameRuntimeTransaction(initialURL: targetURL)
        let webView = WKWebView()

        XCTAssertEqual(
            transaction.beginRecovery(on: webView).disposition,
            .deliver
        )
        XCTAssertTrue(transaction.activatePendingRecovery(on: webView))
        let lease = try XCTUnwrap(
            transaction.mainFrameLoads.claimDirectSubmission(on: webView)
        )
        let navigation = NSObject()
        XCTAssertTrue(transaction.bindSubmittedLoad(
            on: webView,
            navigationID: ObjectIdentifier(navigation),
            navigationLifetime: navigation,
            matching: lease
        ))
        XCTAssertEqual(
            transaction.recoveryState(on: webView)?.phase,
            .recovering(navigationID: ObjectIdentifier(navigation))
        )

        XCTAssertEqual(
            transaction.beginRecovery(on: webView).disposition,
            .failed
        )
        XCTAssertTrue(transaction.recoveryState(on: webView)?.isFailure == true)
    }

    func testRecoveryEpochResetsOnlyAfterAuthorizedCandidateCommit() throws {
        let targetURL = try XCTUnwrap(
            URL(string: "https://example.com/recovery-reset")
        )
        let transaction = TabMainFrameRuntimeTransaction(initialURL: targetURL)
        let failed = WKWebView()
        _ = transaction.beginRecovery(on: failed)
        transaction.failRecoveryDelivery(on: failed)

        let candidate = WKWebView()
        let intent = transaction.beginExplicitIntent(to: targetURL)
        let lease = try XCTUnwrap(
            transaction.mainFrameLoads.claimDirectSubmission(on: candidate)
        )
        transaction.authorizeRecoveryEpochReset(onCommitFrom: candidate)
        let navigation = NSObject()
        let navigationID = ObjectIdentifier(navigation)
        XCTAssertTrue(transaction.bindSubmittedLoad(
            on: candidate,
            navigationID: navigationID,
            navigationLifetime: navigation,
            matching: lease
        ))
        let probeBeforeCommit = WKWebView()
        XCTAssertEqual(
            transaction.beginRecovery(on: probeBeforeCommit).disposition,
            .failed,
            "Authorization alone must not reset the failed epoch"
        )
        _ = transaction.settleCommit(
            from: candidate,
            navigationID: navigationID,
            navigationLifetime: navigation,
            committedURL: targetURL
        )
        XCTAssertEqual(transaction.mainFrameLoads.currentIntent, intent)

        let next = WKWebView()
        XCTAssertEqual(
            transaction.beginRecovery(on: next).disposition,
            .deliver
        )
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
            navigationLifetime: navigation,
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
                    canBeSuspended: true
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

        XCTAssertEqual(plan.disposition, .deliver)
        XCTAssertEqual(effects.reasons, ["web-content-process-recovery"])
        XCTAssertEqual(roleObservedByEffect, .stale)
        XCTAssertEqual(
            transaction.committedDocumentRuntime.suspensionDecision,
            .awaitingEvidence
        )
        effects.reset()

        let duplicatePlan = transaction.beginRecovery(on: webView)

        XCTAssertEqual(duplicatePlan.disposition, .duplicate)
        XCTAssertNil(duplicatePlan.authorityContinuation)
        XCTAssertTrue(effects.reasons.isEmpty)
        XCTAssertEqual(
            transaction.committedDocumentRuntime.suspensionDecision,
            .awaitingEvidence
        )
    }

    func testRejectedSuspensionReportsPublishOnlyRealDecisionChanges() throws {
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
            navigationLifetime: navigation,
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
            canBeSuspended: true
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
    }

    func testHeldAuthorityPlanCannotOverwriteNewerSnapshot() {
        let state = TabMainFrameAuthorityState()
        let firstWebView = WKWebView()
        let secondWebView = WKWebView()
        let firstNavigation = NSObject()
        let secondNavigation = NSObject()
        let snapshot = state.snapshot
        let firstPlan = TabMainFrameAuthorityReducer.installAuthority(
            in: snapshot,
            revision: 1,
            webViewID: ObjectIdentifier(firstWebView),
            documentGeneration: 0,
            navigationID: ObjectIdentifier(firstNavigation)
        )
        let stalePlan = TabMainFrameAuthorityReducer.installAuthority(
            in: snapshot,
            revision: 1,
            webViewID: ObjectIdentifier(secondWebView),
            documentGeneration: 0,
            navigationID: ObjectIdentifier(secondNavigation)
        )

        XCTAssertNotNil(state.apply(firstPlan))
        XCTAssertNil(state.apply(stalePlan))
        XCTAssertEqual(
            state.snapshot.authority?.webViewID,
            ObjectIdentifier(firstWebView)
        )
        XCTAssertEqual(
            state.snapshot.authority?.navigationID,
            ObjectIdentifier(firstNavigation)
        )
    }

    func testForeignPhysicalWebViewCannotReuseExactNavigationWitness() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/physical"))
        let transaction = TabMainFrameRuntimeTransaction(initialURL: targetURL)
        let exactWebView = WKWebView()
        let foreignWebView = WKWebView()
        _ = transaction.beginExplicitIntent(to: targetURL)
        let submission = try XCTUnwrap(
            transaction.mainFrameLoads.claimDirectSubmission(on: exactWebView)
        )
        let navigation = NSObject()
        let navigationID = ObjectIdentifier(navigation)
        XCTAssertTrue(transaction.bindSubmittedLoad(
            on: exactWebView,
            navigationID: navigationID,
            navigationLifetime: navigation,
            matching: submission
        ))

        guard case .stale = transaction.settleCommit(
            from: foreignWebView,
            navigationID: navigationID,
            navigationLifetime: navigation,
            committedURL: targetURL
        ) else {
            return XCTFail("ObjectIdentifier-only admission must fail closed")
        }
        guard case .publish = transaction.settleCommit(
            from: exactWebView,
            navigationID: navigationID,
            navigationLifetime: navigation,
            committedURL: targetURL
        ) else {
            return XCTFail("Foreign physical WebView must not consume exact commit")
        }
    }

    func testHeldRegistryMutationCannotPassCommitPreflight() throws {
        let fixture = try MainFrameAtomicFixture(path: "atomic")
        let held = try XCTUnwrap(fixture.registry.prepareCommit(
            webView: fixture.webView,
            navigationID: fixture.navigationID,
            navigationLifetime: fixture.navigation,
            revision: 1,
            committedURL: fixture.url,
            isPDF: false
        ))
        let frozen = fixture.revisions
        XCTAssertNotNil(fixture.registry.recordResponse(
            isPDF: true,
            webView: fixture.webView,
            navigationID: fixture.navigationID,
            navigationLifetime: fixture.navigation,
            revision: 1
        ))
        XCTAssertNotNil(TabMainFramePreparedTransition.document(
            participant: held.plan,
            source: held.previousEntry,
            state: fixture.authorityState,
            effects: fixture.authorityEffects
        ))
        XCTAssertFalse(fixture.registry.canApply(held.plan))
        XCTAssertEqual(fixture.authorityState.revision, frozen.authority)
        XCTAssertEqual(fixture.authorityEffects.revision, frozen.authorityEffects)
        XCTAssertEqual(fixture.participantEffects.revision, frozen.participantEffects)
    }

    func testDocumentPreparationRejectsSameIdentityAliasWithoutMutation() throws {
        let fixture = try MainFrameAtomicFixture(path: "document-alias")
        let prepared = try XCTUnwrap(fixture.registry.prepareCommit(
            webView: fixture.webView,
            navigationID: fixture.navigationID,
            navigationLifetime: fixture.navigation,
            revision: 1,
            committedURL: fixture.url,
            isPDF: false
        ))
        var alias = prepared.previousEntry
        alias.targetURL = try XCTUnwrap(URL(string: "https://alias.invalid/document"))
        let frozen = fixture.revisions

        XCTAssertNil(TabMainFramePreparedTransition.document(
            participant: prepared.plan,
            source: alias,
            state: fixture.authorityState,
            effects: fixture.authorityEffects
        ))
        fixture.assertUnchanged(frozen, source: prepared.previousEntry)
    }

    func testTerminalPreparationRejectsSameIdentityAliasWithoutMutation() throws {
        let fixture = try MainFrameAtomicFixture(path: "terminal-alias")
        let prepared = try XCTUnwrap(fixture.registry.prepareTerminalSuccess(
            webView: fixture.webView,
            navigationID: fixture.navigationID,
            navigationLifetime: fixture.navigation,
            revision: 1,
            terminalURL: fixture.url
        ))
        var alias = prepared.previousEntry
        alias.documentGeneration &+= 1
        let frozen = fixture.revisions

        XCTAssertNil(TabMainFramePreparedTransition.terminal(
            participant: prepared.plan,
            source: alias,
            terminalURL: fixture.url,
            state: fixture.authorityState,
            effects: fixture.authorityEffects
        ))
        fixture.assertUnchanged(frozen, source: prepared.previousEntry)
    }

    func testSameDocumentPreparationRejectsSameIdentityAliasWithoutMutation() throws {
        let fixture = try MainFrameAtomicFixture(path: "same-document-alias")
        let prepared = try XCTUnwrap(fixture.registry.prepareSameDocumentSuccess(
            webView: fixture.webView,
            navigationID: fixture.navigationID,
            navigationLifetime: fixture.navigation,
            revision: 1,
            presentationURL: fixture.url
        ))
        var alias = prepared.previousEntry
        alias.targetURL = try XCTUnwrap(URL(string: "https://alias.invalid/same"))
        let frozen = fixture.revisions

        XCTAssertNil(TabMainFramePreparedTransition.sameDocument(
            participant: prepared.plan,
            source: alias,
            state: fixture.authorityState,
            effects: fixture.participantEffects
        ))
        fixture.assertUnchanged(frozen, source: prepared.previousEntry)
    }

    func testContinuationPreparationRejectsSameIdentityAliasWithoutMutation() throws {
        let fixture = try MainFrameAtomicFixture(path: "continuation-alias")
        let nextNavigation = NSObject()
        let prepared = try XCTUnwrap(fixture.registry.prepareContinuation(
            webView: fixture.webView,
            navigationID: ObjectIdentifier(nextNavigation),
            navigationLifetime: nextNavigation,
            revision: 1
        ))
        var alias = prepared.previousEntry
        alias.targetURL = try XCTUnwrap(URL(string: "https://alias.invalid/continuation"))
        let frozen = fixture.revisions

        XCTAssertNil(TabMainFramePreparedTransition.continuation(
            participant: prepared.plan,
            source: alias,
            targetURL: fixture.url,
            kind: .requestRewrite,
            ownsAuthority: true,
            state: fixture.authorityState,
            effects: fixture.authorityEffects,
            participantEffects: fixture.participantEffects
        ))
        fixture.assertUnchanged(frozen, source: prepared.previousEntry)
    }

    func testMalformedLifetimeCannotEraseExactRegistryTombstoneOrMutateOwners() throws {
        let fixture = try MainFrameAtomicFixture(path: "closed-tombstone")
        let continuedURL = try XCTUnwrap(URL(string: "https://example.com/continued"))
        let poisonedURL = try XCTUnwrap(URL(string: "https://example.com/poisoned"))
        let continuation = NSObject()
        let prepared = try XCTUnwrap(fixture.registry.prepareContinuation(
            webView: fixture.webView,
            navigationID: ObjectIdentifier(continuation),
            navigationLifetime: continuation,
            revision: 1
        ))
        let initial = fixture.revisions
        let initialEpoch = fixture.authorityState.snapshot.authorityEpoch
        let receipt = try XCTUnwrap(fixture.committer.commitContinuation(
            prepared,
            targetURL: continuedURL,
            kind: .clientRedirect,
            ownsAuthority: true
        ))
        let current = try XCTUnwrap(fixture.registry[ObjectIdentifier(fixture.webView)])
        XCTAssertTrue(receipt.reduction.beganNewDocumentGeneration)
        XCTAssertTrue(receipt.reduction.becomesAuthority)
        XCTAssertEqual(current.targetURL, continuedURL)
        XCTAssertEqual(current.phase, .active(navigationID: ObjectIdentifier(continuation)))
        XCTAssertEqual(fixture.registry.mutationRevision, initial.registry + 1)
        XCTAssertEqual(fixture.authorityState.revision, initial.authority + 1)
        XCTAssertEqual(fixture.authorityEffects.revision, initial.authorityEffects + 1)
        XCTAssertEqual(fixture.participantEffects.revision, initial.participantEffects + 1)
        XCTAssertEqual(fixture.authorityState.snapshot.authorityEpoch, initialEpoch + 1)
        XCTAssertEqual(fixture.authorityState.snapshot.authority?.navigationID, ObjectIdentifier(continuation))
        XCTAssertEqual(fixture.authorityState.snapshot.authority?.documentGeneration, current.documentGeneration)
        XCTAssertTrue(fixture.registry.isRetiredNavigationIdentity(
            fixture.navigationID,
            lifetime: fixture.navigation
        ))

        let frozen = fixture.revisions
        let malformedLifetime = NSObject()
        let transitions = TabMainFrameContinuationTransitionApplier(
            participants: fixture.registry,
            authorityState: fixture.authorityState,
            committer: fixture.committer
        )
        let intent = TabMainFrameNavigationIntent(revision: 1, targetURL: continuedURL)

        guard case .unmatched = transitions.routeLifecycle(
            from: fixture.webView,
            navigationID: fixture.navigationID,
            navigationLifetime: malformedLifetime,
            targetURL: poisonedURL,
            continuationKind: .requestRewrite,
            currentIntent: intent
        ) else { return XCTFail("Malformed lifetime must fail closed without mutation") }
        XCTAssertFalse(fixture.registry.isRetiredNavigationIdentity(
            fixture.navigationID,
            lifetime: malformedLifetime
        ))
        fixture.assertUnchanged(frozen, source: current)

        guard case .retired = transitions.routeLifecycle(
            from: fixture.webView,
            navigationID: fixture.navigationID,
            navigationLifetime: fixture.navigation,
            targetURL: poisonedURL,
            continuationKind: .requestRewrite,
            currentIntent: intent
        ) else { return XCTFail("Late exact callback must remain retired") }
        XCTAssertTrue(fixture.registry.isRetiredNavigationIdentity(
            fixture.navigationID,
            lifetime: fixture.navigation
        ))
        fixture.assertUnchanged(frozen, source: current)

        guard case .unmatched = transitions.routeLifecycle(
            from: fixture.webView,
            navigationID: fixture.navigationID,
            navigationLifetime: malformedLifetime,
            targetURL: poisonedURL,
            continuationKind: .requestRewrite,
            currentIntent: intent
        ) else { return XCTFail("Repeated poison must not resurrect the retired identity") }
        XCTAssertTrue(fixture.registry.isRetiredNavigationIdentity(
            fixture.navigationID,
            lifetime: fixture.navigation
        ))
        fixture.assertUnchanged(frozen, source: current)
    }
}

@MainActor
private final class MainFrameAtomicFixture {
    struct Revisions {
        let registry: UInt64
        let authority: UInt64
        let authorityEffects: UInt64
        let participantEffects: UInt64
    }

    let url: URL
    let webView = WKWebView()
    let navigation = NSObject()
    let participantID = UUID()
    let registry = TabMainFrameParticipantRegistry()
    let authorityState = TabMainFrameAuthorityState()
    let authorityEffects = TabMainFrameAuthorityEffectLedger()
    let participantEffects = TabMainFrameParticipantEffectLedger()

    var navigationID: ObjectIdentifier { ObjectIdentifier(navigation) }
    var committer: TabMainFrameTransitionCommitter {
        .lifecycleComposition(
            participants: registry,
            authorityState: authorityState,
            authorityEffects: authorityEffects,
            participantEffects: participantEffects
        )
    }

    var revisions: Revisions {
        Revisions(
            registry: registry.mutationRevision,
            authority: authorityState.revision,
            authorityEffects: authorityEffects.revision,
            participantEffects: participantEffects.revision
        )
    }

    init(path: String) throws {
        url = try XCTUnwrap(URL(string: "https://example.com/\(path)"))
        XCTAssertNotNil(registry.installSubmission(
            TabMainFrameIntentLedger.SubmissionBinding(
                webView: webView,
                revision: 1,
                documentGeneration: 0,
                participantID: participantID,
                webViewID: ObjectIdentifier(webView),
                targetURL: url,
                becomesAuthority: true
            ),
            navigationID: ObjectIdentifier(navigation),
            navigationLifetime: navigation
        ))
    }

    func assertUnchanged(
        _ expected: Revisions,
        source: TabMainFrameParticipantRegistry.Entry,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(registry.mutationRevision, expected.registry, file: file, line: line)
        XCTAssertEqual(authorityState.revision, expected.authority, file: file, line: line)
        XCTAssertEqual(authorityEffects.revision, expected.authorityEffects, file: file, line: line)
        XCTAssertEqual(participantEffects.revision, expected.participantEffects, file: file, line: line)
        XCTAssertTrue(
            registry[ObjectIdentifier(webView)]?.hasSameFacts(as: source) == true,
            file: file,
            line: line
        )
    }
}

@MainActor
private final class CommittedDocumentSuspensionEffectsProbe:
    TabCommittedDocumentSuspensionEffects {
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
