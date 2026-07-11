import Combine
@testable import Sumi
import SumiWebRuntime
import WebKit
import XCTest

@MainActor
final class InitialDocumentRuntimeHandoffTests: XCTestCase {
    func testDuplicateReadinessReservationCannotReplaceActiveNavigation() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/active"))
        let webView = WKWebView()
        let (tab, mainFrameRuntimeTransaction) = makeTab(
            url: targetURL
        )
        let intent = tab.beginMainFrameNavigationIntent(to: targetURL)
        let navigation = NSObject()
        let navigationID = ObjectIdentifier(navigation)

        XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: webView))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: webView,
            navigationID: navigationID,
            navigationLifetime: navigation,
            matching: nil
        ))

        XCTAssertNil(tab.mainFrameLoads.beginPreparedLoad(on: webView, intent: intent))
        XCTAssertTrue(mainFrameRuntimeTransaction.role(
            from: webView,
            navigationID: navigationID,
            isCurrent: true
        ).isAuthority)
    }

    func testAuthorityMovesToActiveSiblingWhenAuthoritativeWebViewLeaves() throws {
        let initialURL = try XCTUnwrap(URL(string: "https://example.com/start"))
        let firstRedirectURL = try XCTUnwrap(URL(string: "https://example.com/first"))
        let siblingCommitURL = try XCTUnwrap(URL(string: "https://example.com/sibling"))
        let authoritativeWebView = WKWebView()
        let siblingWebView = WKWebView()
        let (tab, mainFrameRuntimeTransaction) = makeTab(
            url: initialURL
        )
        _ = tab.beginMainFrameNavigationIntent(to: initialURL)
        let firstNavigation = NSObject()
        let siblingNavigation = NSObject()
        let firstNavigationID = ObjectIdentifier(firstNavigation)
        let siblingNavigationID = ObjectIdentifier(siblingNavigation)

        XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: authoritativeWebView))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: authoritativeWebView,
            navigationID: firstNavigationID,
            navigationLifetime: firstNavigation,
            matching: nil
        ))
        XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: siblingWebView))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: siblingWebView,
            navigationID: siblingNavigationID,
            navigationLifetime: siblingNavigation,
            matching: nil
        ))
        tab.applyAcceptedMainFrameLifecycleURL(
            firstRedirectURL,
            from: authoritativeWebView,
            navigationID: firstNavigationID
        )

        tab.applyAcceptedMainFrameLifecycleURL(
            siblingCommitURL,
            from: siblingWebView,
            navigationID: siblingNavigationID
        )
        XCTAssertEqual(tab.url, firstRedirectURL)

        tab.webViewDidLeaveNavigationRuntime(authoritativeWebView)
        XCTAssertTrue(mainFrameRuntimeTransaction.role(
            from: siblingWebView,
            navigationID: siblingNavigationID,
            isCurrent: true
        ).isAuthority)
        tab.applyAcceptedMainFrameLifecycleURL(
            siblingCommitURL,
            from: siblingWebView,
            navigationID: siblingNavigationID
        )
        XCTAssertEqual(tab.url, siblingCommitURL)
    }

    func testStopLoadingStopsEveryActiveCloneBeforeRetiringSharedIntent() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/loading"))
        let firstWebView = StopTrackingWebView(frame: .zero)
        let secondWebView = StopTrackingWebView(frame: .zero)
        let (tab, mainFrameRuntimeTransaction) = makeTab(
            url: targetURL
        )
        _ = tab.beginMainFrameNavigationIntent(to: targetURL)
        tab.beginLoadingPresentationIfNeeded()
        let firstNavigation = NSObject()
        let secondNavigation = NSObject()
        let firstID = ObjectIdentifier(firstNavigation)
        let secondID = ObjectIdentifier(secondNavigation)
        XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: firstWebView))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: firstWebView,
            navigationID: firstID,
            navigationLifetime: firstNavigation,
            matching: nil
        ))
        XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: secondWebView))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: secondWebView,
            navigationID: secondID,
            navigationLifetime: secondNavigation,
            matching: nil
        ))

        tab.stopLoading(on: secondWebView)

        XCTAssertEqual(firstWebView.stopLoadingCount, 1)
        XCTAssertEqual(secondWebView.stopLoadingCount, 1)
        XCTAssertFalse(tab.loadingState.isLoading)
        XCTAssertFalse(mainFrameRuntimeTransaction.role(
            from: firstWebView,
            navigationID: firstID,
            isCurrent: true
        ).isAuthority)
        XCTAssertFalse(mainFrameRuntimeTransaction.role(
            from: secondWebView,
            navigationID: secondID,
            isCurrent: true
        ).isAuthority)
    }

    func testRedirectCanSupersedeActiveSiblingWithProtectedDeferredTarget() throws {
        let initialURL = try XCTUnwrap(URL(string: "https://example.com/start"))
        let redirectURL = try XCTUnwrap(URL(string: "https://example.com/redirect"))
        let authoritativeWebView = WKWebView()
        let protectedSibling = WKWebView()
        let (tab, mainFrameRuntimeTransaction) = makeTab(
            url: initialURL
        )
        _ = tab.beginMainFrameNavigationIntent(to: initialURL)
        let authorityNavigation = NSObject()
        let siblingNavigation = NSObject()
        let authorityID = ObjectIdentifier(authorityNavigation)
        let siblingID = ObjectIdentifier(siblingNavigation)

        XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: authoritativeWebView))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: authoritativeWebView,
            navigationID: authorityID,
            navigationLifetime: authorityNavigation,
            matching: nil
        ))
        XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: protectedSibling))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: protectedSibling,
            navigationID: siblingID,
            navigationLifetime: siblingNavigation,
            matching: nil
        ))
        tab.applyAcceptedMainFrameLifecycleURL(
            redirectURL,
            from: authoritativeWebView,
            navigationID: authorityID
        )
        let redirectedIntent = try XCTUnwrap(
            tab.mainFrameLoads.currentIntent(matching: redirectURL)
        )

        XCTAssertTrue(tab.mainFrameLoads.markDeferredLoad(
            on: protectedSibling,
            intent: redirectedIntent
        ))
        XCTAssertFalse(mainFrameRuntimeTransaction.role(
            from: protectedSibling,
            navigationID: siblingID,
            isCurrent: true
        ).isAuthority)
        XCTAssertEqual(
            tab.mainFrameLoads.claimDeferredSubmission(
                on: protectedSibling,
                revision: redirectedIntent.revision,
                targetURL: redirectURL
            ),
            .claimed
        )
    }

    func testFailedDeferredSubmissionRestoresExactRetryClaim() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/protected"))
        let webView = WKWebView()
        let tab = Tab(url: targetURL, loadsCachedFaviconOnInit: false)
        let intent = tab.beginMainFrameNavigationIntent(to: targetURL)

        XCTAssertTrue(tab.mainFrameLoads.markDeferredLoad(on: webView, intent: intent))
        XCTAssertEqual(
            tab.mainFrameLoads.claimDeferredSubmission(
                on: webView,
                revision: intent.revision,
                targetURL: targetURL
            ),
            .claimed
        )
        tab.mainFrameSubmission.restoreDeferredLoadAfterFailedSubmission(
            on: webView,
            revision: intent.revision,
            targetURL: targetURL,
            matching: nil
        )
        XCTAssertEqual(
            tab.mainFrameLoads.claimDeferredSubmission(
                on: webView,
                revision: intent.revision,
                targetURL: targetURL
            ),
            .claimed
        )
    }

    func testFailedDeferredAuthorityYieldsToActiveSibling() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/protected"))
        let failedDeferredWebView = WKWebView()
        let activeSibling = WKWebView()
        let (tab, mainFrameRuntimeTransaction) = makeTab(
            url: targetURL
        )
        let intent = tab.beginMainFrameNavigationIntent(to: targetURL)
        let siblingNavigation = NSObject()
        let siblingNavigationID = ObjectIdentifier(siblingNavigation)

        XCTAssertTrue(tab.mainFrameLoads.markDeferredLoad(
            on: failedDeferredWebView,
            intent: intent
        ))
        XCTAssertEqual(tab.mainFrameLoads.claimDeferredSubmission(
            on: failedDeferredWebView,
            revision: intent.revision,
            targetURL: targetURL
        ), .claimed)
        tab.mainFrameSubmission.restoreDeferredLoadAfterFailedSubmission(
            on: failedDeferredWebView,
            revision: intent.revision,
            targetURL: targetURL,
            matching: nil
        )

        XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: activeSibling))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: activeSibling,
            navigationID: siblingNavigationID,
            navigationLifetime: siblingNavigation,
            matching: nil
        ))
        XCTAssertTrue(mainFrameRuntimeTransaction.role(
            from: activeSibling,
            navigationID: siblingNavigationID,
            isCurrent: true
        ).isAuthority)
    }

    func testFailedAuthoritySubmissionPromotesAlreadyActiveSibling() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/shared"))
        let failedWebView = WKWebView()
        let activeSibling = WKWebView()
        let (tab, mainFrameRuntimeTransaction) = makeTab(
            url: targetURL
        )
        _ = tab.beginMainFrameNavigationIntent(to: targetURL)
        let siblingNavigation = NSObject()
        let siblingNavigationID = ObjectIdentifier(siblingNavigation)

        XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: failedWebView))
        XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: activeSibling))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: activeSibling,
            navigationID: siblingNavigationID,
            navigationLifetime: siblingNavigation,
            matching: nil
        ))

        tab.mainFrameSubmission.failSubmittedLoad(on: failedWebView, matching: nil)

        XCTAssertTrue(mainFrameRuntimeTransaction.role(
            from: activeSibling,
            navigationID: siblingNavigationID,
            isCurrent: true
        ).isAuthority)
    }

    func testCompletedIdentityIsRetiredAndNextLifecycleGetsNewRevision() throws {
        let firstURL = try XCTUnwrap(URL(string: "https://example.com/first"))
        let secondURL = try XCTUnwrap(URL(string: "https://example.com/second"))
        let webView = WKWebView()
        let (tab, mainFrameRuntimeTransaction) = makeTab(
            url: firstURL
        )
        let firstNavigation = NSObject()
        let secondNavigation = NSObject()
        let firstID = ObjectIdentifier(firstNavigation)
        let secondID = ObjectIdentifier(secondNavigation)

        XCTAssertEqual(tab.beginMainFrameLifecycle(
            from: webView,
            navigationID: firstID,
            navigationLifetime: firstNavigation,
            targetURL: firstURL,
            allowsUserInitiatedSupersession: false,
            continuationKind: nil
        ), .authority)
        let firstIntent = try XCTUnwrap(tab.mainFrameLoads.currentIntent(matching: firstURL))
        mainFrameRuntimeTransaction.finish(from: webView, navigationID: firstID)
        XCTAssertFalse(mainFrameRuntimeTransaction.role(
            from: webView,
            navigationID: firstID,
            isCurrent: true
        ).isAuthority)

        XCTAssertEqual(tab.beginMainFrameLifecycle(
            from: webView,
            navigationID: secondID,
            navigationLifetime: secondNavigation,
            targetURL: secondURL,
            allowsUserInitiatedSupersession: false,
            continuationKind: nil
        ), .authority)
        let secondIntent = try XCTUnwrap(tab.mainFrameLoads.currentIntent(matching: secondURL))
        XCTAssertGreaterThan(secondIntent.revision, firstIntent.revision)
    }

    func testCompletedHiddenSiblingCannotStartUnboundTabWideNavigation() throws {
        let settledURL = try XCTUnwrap(URL(string: "https://example.com/settled"))
        let hiddenTargetURL = try XCTUnwrap(URL(string: "https://hidden.example/next"))
        let authorityWebView = WKWebView()
        let hiddenWebView = WKWebView()
        let (tab, mainFrameRuntimeTransaction) = makeTab(
            url: settledURL
        )
        _ = tab.beginMainFrameNavigationIntent(to: settledURL)
        let authorityNavigation = NSObject()
        let hiddenNavigation = NSObject()
        let hiddenNextNavigation = NSObject()
        let authorityID = ObjectIdentifier(authorityNavigation)
        let hiddenID = ObjectIdentifier(hiddenNavigation)

        XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: authorityWebView))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: authorityWebView,
            navigationID: authorityID,
            navigationLifetime: authorityNavigation,
            matching: nil
        ))
        XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: hiddenWebView))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: hiddenWebView,
            navigationID: hiddenID,
            navigationLifetime: hiddenNavigation,
            matching: nil
        ))
        assertPublishedCommit(
            mainFrameRuntimeTransaction.settleCommit(
                from: authorityWebView,
                navigationID: authorityID,
                committedURL: settledURL
            ),
            from: authorityWebView,
            navigationID: authorityID,
            targetURL: settledURL
        )
        assertRecordedReplica(
            mainFrameRuntimeTransaction.settleCommit(
                from: hiddenWebView,
                navigationID: hiddenID,
                committedURL: settledURL
            )
        )
        mainFrameRuntimeTransaction.finish(
            from: authorityWebView,
            navigationID: authorityID
        )
        mainFrameRuntimeTransaction.finish(
            from: hiddenWebView,
            navigationID: hiddenID
        )

        XCTAssertEqual(tab.beginMainFrameLifecycle(
            from: hiddenWebView,
            navigationID: ObjectIdentifier(hiddenNextNavigation),
            navigationLifetime: hiddenNextNavigation,
            targetURL: hiddenTargetURL,
            allowsUserInitiatedSupersession: false,
            continuationKind: nil
        ), .stale)
        XCTAssertNotNil(tab.mainFrameLoads.currentIntent(matching: settledURL))

        let hiddenRedirectNavigation = NSObject()
        XCTAssertEqual(tab.beginMainFrameLifecycle(
            from: hiddenWebView,
            navigationID: ObjectIdentifier(hiddenRedirectNavigation),
            navigationLifetime: hiddenRedirectNavigation,
            targetURL: hiddenTargetURL,
            allowsUserInitiatedSupersession: false,
            continuationKind: .clientRedirect
        ), .participant)
        XCTAssertNotNil(tab.mainFrameLoads.currentIntent(matching: settledURL))
        XCTAssertTrue(
            tab.committedDocumentRuntime.lease(for: authorityWebView)?.isAuthority
                == true
        )
    }

    func testCancelledIntentRejectsLateUnboundLifecycle() throws {
        let settledURL = try XCTUnwrap(URL(string: "https://example.com/settled"))
        let cancelledURL = try XCTUnwrap(URL(string: "https://example.com/cancelled"))
        let webView = WKWebView()
        let (tab, mainFrameRuntimeTransaction) = makeTab(
            url: settledURL
        )
        _ = tab.beginMainFrameNavigationIntent(to: cancelledURL)
        tab.cancelMainFrameNavigationIntent()
        let lateNavigation = NSObject()

        XCTAssertEqual(tab.beginMainFrameLifecycle(
            from: webView,
            navigationID: ObjectIdentifier(lateNavigation),
            navigationLifetime: lateNavigation,
            targetURL: cancelledURL,
            allowsUserInitiatedSupersession: false,
            continuationKind: nil
        ), .stale)
        XCTAssertFalse(mainFrameRuntimeTransaction.role(
            from: webView,
            navigationID: ObjectIdentifier(lateNavigation),
            isCurrent: true
        ).isAuthority)
    }

    func testCancelledUserNavigationRejectsLateDidStartForSameLifetime() throws {
        let settledURL = try XCTUnwrap(URL(string: "https://example.com/settled"))
        let cancelledURL = try XCTUnwrap(URL(string: "https://example.com/cancelled"))
        let webView = WKWebView()
        let tab = Tab(url: settledURL, loadsCachedFaviconOnInit: false)
        let navigation = NSObject()
        let navigationID = ObjectIdentifier(navigation)
        XCTAssertEqual(tab.beginMainFrameLifecycle(
            from: webView,
            navigationID: navigationID,
            navigationLifetime: navigation,
            targetURL: cancelledURL,
            allowsUserInitiatedSupersession: true,
            continuationKind: nil
        ), .authority)

        tab.cancelMainFrameNavigationIntent()

        XCTAssertEqual(tab.beginMainFrameLifecycle(
            from: webView,
            navigationID: navigationID,
            navigationLifetime: navigation,
            targetURL: cancelledURL,
            allowsUserInitiatedSupersession: true,
            continuationKind: nil
        ), .stale)
        XCTAssertNotNil(tab.mainFrameLoads.currentIntent(matching: settledURL))
    }

    func testRedirectCommitSnapshotSurvivesAuthorityDeparture() throws {
        let requestedURL = try XCTUnwrap(URL(string: "https://example.com/request"))
        let committedURL = try XCTUnwrap(URL(string: "https://example.com/final"))
        let authorityWebView = WKWebView()
        let siblingWebView = WKWebView()
        let (tab, mainFrameRuntimeTransaction) = makeTab(
            url: requestedURL
        )
        _ = tab.beginMainFrameNavigationIntent(to: requestedURL)
        let authorityNavigation = NSObject()
        let siblingNavigation = NSObject()
        let authorityID = ObjectIdentifier(authorityNavigation)
        let siblingID = ObjectIdentifier(siblingNavigation)

        XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: authorityWebView))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: authorityWebView,
            navigationID: authorityID,
            navigationLifetime: authorityNavigation,
            matching: nil
        ))
        XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: siblingWebView))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: siblingWebView,
            navigationID: siblingID,
            navigationLifetime: siblingNavigation,
            matching: nil
        ))
        assertPublishedCommit(
            mainFrameRuntimeTransaction.settleCommit(
                from: authorityWebView,
                navigationID: authorityID,
                committedURL: committedURL
            ),
            from: authorityWebView,
            navigationID: authorityID,
            targetURL: committedURL
        )
        assertRecordedReplica(
            mainFrameRuntimeTransaction.settleCommit(
                from: siblingWebView,
                navigationID: siblingID,
                committedURL: committedURL
            )
        )
        mainFrameRuntimeTransaction.finish(
            from: siblingWebView,
            navigationID: siblingID
        )

        let departure = tab.webViewDidLeaveNavigationRuntime(authorityWebView)

        XCTAssertEqual(departure.continuation?.targetURL, committedURL)
        XCTAssertTrue(departure.hasReplacementAuthority)
        XCTAssertNotNil(tab.mainFrameLoads.currentIntent(matching: committedURL))
    }

    func testPromotedCommitIdentitySeparatesLaterIncompatibleDocument() throws {
        let firstURL = try XCTUnwrap(URL(string: "https://first.example/document"))
        let promotedURL = try XCTUnwrap(URL(string: "https://second.example/document"))
        let laterURL = try XCTUnwrap(URL(string: "https://third.example/document"))
        let firstWebView = WKWebView()
        let promotedWebView = WKWebView()
        let laterWebView = WKWebView()
        let (tab, mainFrameRuntimeTransaction) = makeTab(
            url: firstURL
        )
        _ = tab.beginMainFrameNavigationIntent(to: firstURL)
        let firstNavigation = NSObject()
        let promotedNavigation = NSObject()
        let laterNavigation = NSObject()
        let firstID = ObjectIdentifier(firstNavigation)
        let promotedID = ObjectIdentifier(promotedNavigation)
        let laterID = ObjectIdentifier(laterNavigation)

        XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: firstWebView))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: firstWebView,
            navigationID: firstID,
            navigationLifetime: firstNavigation,
            matching: nil
        ))
        XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: promotedWebView))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: promotedWebView,
            navigationID: promotedID,
            navigationLifetime: promotedNavigation,
            matching: nil
        ))
        assertPublishedCommit(
            mainFrameRuntimeTransaction.settleCommit(
                from: firstWebView,
                navigationID: firstID,
                committedURL: firstURL
            ),
            from: firstWebView,
            navigationID: firstID,
            targetURL: firstURL
        )
        assertRecordedReplica(
            mainFrameRuntimeTransaction.settleCommit(
                from: promotedWebView,
                navigationID: promotedID,
                committedURL: promotedURL
            )
        )
        mainFrameRuntimeTransaction.finish(from: firstWebView, navigationID: firstID)
        mainFrameRuntimeTransaction.finish(
            from: promotedWebView,
            navigationID: promotedID
        )

        let firstDeparture = tab.webViewDidLeaveNavigationRuntime(firstWebView)
        XCTAssertEqual(firstDeparture.continuation?.targetURL, promotedURL)
        XCTAssertTrue(firstDeparture.continuation?.needsSharedCommitEffects == true)
        XCTAssertEqual(tab.url, promotedURL)

        XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: laterWebView))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: laterWebView,
            navigationID: laterID,
            navigationLifetime: laterNavigation,
            matching: nil
        ))
        assertRecordedReplica(
            mainFrameRuntimeTransaction.settleCommit(
                from: laterWebView,
                navigationID: laterID,
                committedURL: laterURL
            )
        )
        mainFrameRuntimeTransaction.finish(from: laterWebView, navigationID: laterID)

        let secondDeparture = tab.webViewDidLeaveNavigationRuntime(promotedWebView)
        XCTAssertEqual(secondDeparture.continuation?.targetURL, laterURL)
        XCTAssertTrue(secondDeparture.continuation?.needsSharedCommitEffects == true)
        XCTAssertEqual(tab.url, laterURL)
    }

    func testDivergentPromotionMovesEveryCompatibleReplicaIntoOneGeneration() throws {
        let originalURL = try XCTUnwrap(URL(string: "https://first.example/document"))
        let promotedURL = try XCTUnwrap(URL(string: "https://second.example/document"))
        let originalWebView = WKWebView()
        let firstPromotedReplica = WKWebView()
        let secondPromotedReplica = WKWebView()
        let (tab, mainFrameRuntimeTransaction) = makeTab(
            url: originalURL
        )
        _ = tab.beginMainFrameNavigationIntent(to: originalURL)

        let originalNavigation = NSObject()
        let firstReplicaNavigation = NSObject()
        let secondReplicaNavigation = NSObject()
        let participants = [
            (originalWebView, originalNavigation),
            (firstPromotedReplica, firstReplicaNavigation),
            (secondPromotedReplica, secondReplicaNavigation),
        ]
        for (webView, navigation) in participants {
            XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: webView))
            XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
                on: webView,
                navigationID: ObjectIdentifier(navigation),
                navigationLifetime: navigation,
                matching: nil
            ))
        }

        assertPublishedCommit(
            mainFrameRuntimeTransaction.settleCommit(
                from: originalWebView,
                navigationID: ObjectIdentifier(originalNavigation),
                committedURL: originalURL
            ),
            from: originalWebView,
            navigationID: ObjectIdentifier(originalNavigation),
            targetURL: originalURL
        )
        for (webView, navigation) in participants.dropFirst() {
            assertRecordedReplica(
                mainFrameRuntimeTransaction.settleCommit(
                    from: webView,
                    navigationID: ObjectIdentifier(navigation),
                    committedURL: promotedURL
                )
            )
        }
        for (webView, navigation) in participants {
            mainFrameRuntimeTransaction.finish(
                from: webView,
                navigationID: ObjectIdentifier(navigation)
            )
        }

        let firstDeparture = tab.webViewDidLeaveNavigationRuntime(originalWebView)
        let firstContinuation = try XCTUnwrap(firstDeparture.continuation)
        XCTAssertEqual(firstContinuation.targetURL, promotedURL)
        XCTAssertTrue(firstContinuation.needsSharedCommitEffects)

        let firstLease = try XCTUnwrap(
            tab.committedDocumentRuntime.lease(for: firstPromotedReplica)
        )
        let secondLease = try XCTUnwrap(
            tab.committedDocumentRuntime.lease(for: secondPromotedReplica)
        )
        XCTAssertEqual(firstLease.revision, secondLease.revision)
        XCTAssertEqual(firstLease.documentGeneration, secondLease.documentGeneration)
        XCTAssertEqual([firstLease, secondLease].filter(\.isAuthority).count, 1)

        let promotedAuthority = firstContinuation.webView
        let remainingReplica = promotedAuthority === firstPromotedReplica
            ? secondPromotedReplica
            : firstPromotedReplica
        let secondDeparture = tab.webViewDidLeaveNavigationRuntime(promotedAuthority)
        let secondContinuation = try XCTUnwrap(secondDeparture.continuation)
        XCTAssertIdentical(secondContinuation.webView, remainingReplica)
        XCTAssertEqual(secondContinuation.targetURL, promotedURL)
        XCTAssertFalse(secondContinuation.needsSharedCommitEffects)
        let survivingLease = try XCTUnwrap(
            tab.committedDocumentRuntime.lease(for: remainingReplica)
        )
        XCTAssertTrue(survivingLease.isAuthority)
        XCTAssertEqual(survivingLease.revision, firstLease.revision)
        XCTAssertEqual(
            survivingLease.documentGeneration,
            firstLease.documentGeneration
        )
    }

    func testCancelledExpectedNavigationRollsBackToSurvivingDocument() throws {
        let survivingURL = try XCTUnwrap(URL(string: "https://example.com/current"))
        let cancelledURL = try XCTUnwrap(URL(string: "https://example.com/cancelled"))
        let webView = SumiNavigationURLReportingWebView(frame: .zero)
        webView.reportedURL = survivingURL
        let (tab, mainFrameRuntimeTransaction) = makeTab(
            url: survivingURL
        )
        _ = tab.beginMainFrameNavigationIntent(to: cancelledURL)
        tab.url = cancelledURL
        tab.beginLoadingPresentationIfNeeded()
        let navigation = NSObject()
        let navigationID = ObjectIdentifier(navigation)
        XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: webView))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: webView,
            navigationID: navigationID,
            navigationLifetime: navigation,
            matching: nil
        ))

        tab.makeMainFrameLifecycleResponder().mainFrameNavigationDidTerminate(
            SumiMainFrameNavigationTermination(
                navigationID: navigationID,
                navigationLifetime: navigation,
                webView: webView,
                reason: .actionCancelled
            )
        )

        XCTAssertEqual(tab.url, survivingURL)
        XCTAssertNotNil(tab.mainFrameLoads.currentIntent(matching: survivingURL))
        XCTAssertFalse(tab.loadingState.isLoading)
        XCTAssertFalse(mainFrameRuntimeTransaction.role(
            from: webView,
            navigationID: navigationID,
            isCurrent: true
        ).isAuthority)
    }

    func testUnboundTerminalIdentityCannotAbortSubmittedAuthority() throws {
        let survivingURL = try XCTUnwrap(URL(string: "https://example.com/current"))
        let cancelledURL = try XCTUnwrap(URL(string: "https://example.com/cancelled"))
        let webView = SumiNavigationURLReportingWebView(frame: .zero)
        webView.reportedURL = survivingURL
        let tab = Tab(url: survivingURL, loadsCachedFaviconOnInit: false)
        _ = tab.beginMainFrameNavigationIntent(to: cancelledURL)
        tab.url = cancelledURL
        tab.beginLoadingPresentationIfNeeded()
        XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: webView))
        let navigation = NSObject()

        tab.makeMainFrameLifecycleResponder().mainFrameNavigationDidTerminate(
            SumiMainFrameNavigationTermination(
                navigationID: ObjectIdentifier(navigation),
                navigationLifetime: navigation,
                webView: webView,
                reason: .actionCancelled
            )
        )

        XCTAssertEqual(tab.url, cancelledURL)
        XCTAssertTrue(tab.loadingState.isLoading)
        XCTAssertNil(tab.mainFrameLoads.claimDirectSubmission(on: webView))
    }

    func testTerminalIdentityCannotAbortWithoutExactNavigationLifetime() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/target"))
        let webView = SumiNavigationURLReportingWebView(frame: .zero)
        let (tab, mainFrameRuntimeTransaction) = makeTab(
            url: targetURL
        )
        _ = tab.beginMainFrameNavigationIntent(to: targetURL)
        let navigation = NSObject()
        let navigationID = ObjectIdentifier(navigation)
        XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: webView))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: webView,
            navigationID: navigationID,
            navigationLifetime: navigation,
            matching: nil
        ))

        let wrongLifetime = NSObject()
        tab.makeMainFrameLifecycleResponder().mainFrameNavigationDidTerminate(
            SumiMainFrameNavigationTermination(
                navigationID: navigationID,
                navigationLifetime: wrongLifetime,
                webView: webView,
                reason: .actionCancelled
            )
        )

        XCTAssertTrue(mainFrameRuntimeTransaction.role(
            from: webView,
            navigationID: navigationID,
            isCurrent: true
        ).isAuthority)
        tab.makeMainFrameLifecycleResponder().mainFrameNavigationDidTerminate(
            SumiMainFrameNavigationTermination(
                navigationID: navigationID,
                navigationLifetime: navigation,
                webView: webView,
                reason: .actionCancelled
            )
        )
        XCTAssertFalse(mainFrameRuntimeTransaction.role(
            from: webView,
            navigationID: navigationID,
            isCurrent: true
        ).isAuthority)
    }

    func testFailedAuthorityPromotesActiveSiblingWithoutPublishingSharedFailure() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/target"))
        let siblingCommitURL = try XCTUnwrap(URL(string: "https://example.com/sibling"))
        let failedWebView = SumiNavigationURLReportingWebView(frame: .zero)
        let activeSibling = SumiNavigationURLReportingWebView(frame: .zero)
        failedWebView.reportedURL = targetURL
        activeSibling.reportedURL = siblingCommitURL
        let (tab, mainFrameRuntimeTransaction) = makeTab(
            url: targetURL
        )
        _ = tab.beginMainFrameNavigationIntent(to: targetURL)
        tab.beginLoadingPresentationIfNeeded()
        let failedNavigation = NSObject()
        let siblingNavigation = NSObject()
        let failedID = ObjectIdentifier(failedNavigation)
        let siblingID = ObjectIdentifier(siblingNavigation)
        XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: failedWebView))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: failedWebView,
            navigationID: failedID,
            navigationLifetime: failedNavigation,
            matching: nil
        ))
        XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: activeSibling))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: activeSibling,
            navigationID: siblingID,
            navigationLifetime: siblingNavigation,
            matching: nil
        ))

        tab.makeMainFrameLifecycleResponder().navigationDidFail(
            WKError(.unknown),
            context: SumiNavigationContext(
                navigationID: failedID,
                navigationLifetime: failedNavigation,
                action: nil,
                url: targetURL,
                isCurrent: true,
                isMainFrame: true,
                webView: failedWebView
            )
        )

        XCTAssertTrue(mainFrameRuntimeTransaction.role(
            from: activeSibling,
            navigationID: siblingID,
            isCurrent: true
        ).isAuthority)
        XCTAssertFalse({
            if case .didFail = tab.loadingState { return true }
            return false
        }())
        tab.applyAcceptedMainFrameLifecycleURL(
            siblingCommitURL,
            from: activeSibling,
            navigationID: siblingID
        )
        XCTAssertEqual(tab.url, siblingCommitURL)
    }

    func testProcessTerminationWithoutSurvivorRequiresGlobalRecovery() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/process"))
        let webView = WKWebView()
        let (tab, mainFrameRuntimeTransaction) = makeTab(
            url: targetURL
        )
        _ = tab.beginMainFrameNavigationIntent(to: targetURL)
        tab.beginLoadingPresentationIfNeeded()
        let navigation = NSObject()
        let navigationID = ObjectIdentifier(navigation)
        XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: webView))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: webView,
            navigationID: navigationID,
            navigationLifetime: navigation,
            matching: nil
        ))

        let recoveryPlan = tab.webContentRecovery.beginRecovery(on: webView)

        XCTAssertEqual(recoveryPlan.scope, .global(targetURL))
        XCTAssertNil(recoveryPlan.authorityContinuation)
        XCTAssertTrue(tab.webContentRecovery.isRecoveryRequired(on: webView))
        XCTAssertFalse(mainFrameRuntimeTransaction.role(
            from: webView,
            navigationID: navigationID,
            isCurrent: true
        ).isAuthority)
    }

    func testCompletedReplicaCrashKeepsHealthyAuthorityAndRevision() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/process"))
        let authorityWebView = WKWebView()
        let crashedReplica = WKWebView()
        let (tab, mainFrameRuntimeTransaction) = makeTab(
            url: targetURL
        )
        let intent = tab.beginMainFrameNavigationIntent(to: targetURL)
        let authorityNavigation = NSObject()
        let replicaNavigation = NSObject()
        let authorityID = ObjectIdentifier(authorityNavigation)
        let replicaID = ObjectIdentifier(replicaNavigation)
        XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: authorityWebView))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: authorityWebView,
            navigationID: authorityID,
            navigationLifetime: authorityNavigation,
            matching: nil
        ))
        XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: crashedReplica))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: crashedReplica,
            navigationID: replicaID,
            navigationLifetime: replicaNavigation,
            matching: nil
        ))
        assertPublishedCommit(
            mainFrameRuntimeTransaction.settleCommit(
                from: authorityWebView,
                navigationID: authorityID,
                committedURL: targetURL
            ),
            from: authorityWebView,
            navigationID: authorityID,
            targetURL: targetURL
        )
        assertRecordedReplica(
            mainFrameRuntimeTransaction.settleCommit(
                from: crashedReplica,
                navigationID: replicaID,
                committedURL: targetURL
            )
        )
        mainFrameRuntimeTransaction.finish(
            from: authorityWebView,
            navigationID: authorityID
        )
        mainFrameRuntimeTransaction.finish(
            from: crashedReplica,
            navigationID: replicaID
        )

        let recoveryPlan = tab.webContentRecovery.beginRecovery(on: crashedReplica)

        XCTAssertEqual(recoveryPlan.scope, .replica(intent))
        XCTAssertNil(recoveryPlan.authorityContinuation)
        XCTAssertTrue(
            tab.committedDocumentRuntime.lease(for: authorityWebView)?.isAuthority
                == true
        )
        XCTAssertNil(tab.committedDocumentRuntime.lease(for: crashedReplica))
        XCTAssertTrue(tab.webContentRecovery.isRecoveryRequired(on: crashedReplica))
        XCTAssertTrue(tab.mainFrameLoads.isCurrent(intent))
    }

    func testLateTerminationFromUnownedWebViewCannotTriggerRecovery() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/process"))
        let webView = WKWebView()
        let tab = Tab(url: targetURL, loadsCachedFaviconOnInit: false)

        tab.makeMainFrameLifecycleResponder()
            .webContentProcessDidTerminate(on: webView)

        XCTAssertFalse(tab.webContentRecovery.isRecoveryRequired(on: webView))
        XCTAssertEqual(tab.mainFrameLoads.currentIntent.targetURL, targetURL)
    }

    func testTrustedContinuationTransfersExactAuthorityWithinRevision() throws {
        let initialURL = try XCTUnwrap(URL(string: "https://example.com/start"))
        let continuationURL = try XCTUnwrap(URL(string: "https://example.com/spa"))
        let webView = WKWebView()
        let (tab, mainFrameRuntimeTransaction) = makeTab(
            url: initialURL
        )
        let firstNavigation = NSObject()
        let continuationNavigation = NSObject()
        let firstID = ObjectIdentifier(firstNavigation)
        let continuationID = ObjectIdentifier(continuationNavigation)

        XCTAssertEqual(tab.beginMainFrameLifecycle(
            from: webView,
            navigationID: firstID,
            navigationLifetime: firstNavigation,
            targetURL: initialURL,
            allowsUserInitiatedSupersession: false,
            continuationKind: nil
        ), .authority)
        let revision = try XCTUnwrap(
            tab.mainFrameLoads.currentIntent(matching: initialURL)
        ).revision

        XCTAssertEqual(tab.beginMainFrameLifecycle(
            from: webView,
            navigationID: continuationID,
            navigationLifetime: continuationNavigation,
            targetURL: continuationURL,
            allowsUserInitiatedSupersession: false,
            continuationKind: .clientRedirect
        ), .authority)
        XCTAssertEqual(
            tab.mainFrameLoads.currentIntent(matching: continuationURL)?.revision,
            revision
        )
        XCTAssertFalse(mainFrameRuntimeTransaction.role(
            from: webView,
            navigationID: firstID,
            isCurrent: true
        ).isAuthority)
        XCTAssertTrue(mainFrameRuntimeTransaction.role(
            from: webView,
            navigationID: continuationID,
            isCurrent: true
        ).isAuthority)
    }

    func testPresentationURLWriteDoesNotInvalidateNavigationIntent() throws {
        let pendingURL = try XCTUnwrap(URL(string: "https://example.com/pending"))
        let presentationURL = try XCTUnwrap(URL(string: "https://example.com/old"))
        let tab = Tab(url: presentationURL, loadsCachedFaviconOnInit: false)
        let intent = tab.beginMainFrameNavigationIntent(to: pendingURL)

        tab.url = presentationURL

        XCTAssertTrue(tab.mainFrameLoads.isCurrent(
            revision: intent.revision,
            targetURL: pendingURL
        ))
    }

    func testReadinessLeaseTracksRedirectTargetWithinSameSemanticRevision() throws {
        let initialURL = URL(string: "https://example.com/start")!
        let redirectURL = URL(string: "https://example.com/redirected")!
        let originatingWebView = WKWebView()
        let pendingSiblingWebView = WKWebView()
        let tab = Tab(url: initialURL, loadsCachedFaviconOnInit: false)
        let intent = tab.beginMainFrameNavigationIntent(to: initialURL)

        let preparationTicket = try XCTUnwrap(
            tab.mainFrameLoads.beginPreparedLoad(
                on: pendingSiblingWebView,
                intent: intent
            )
        )
        let navigation = NSObject()
        let navigationIdentity = ObjectIdentifier(navigation)
        XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: originatingWebView))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: originatingWebView,
            navigationID: navigationIdentity,
            navigationLifetime: navigation,
            matching: nil
        ))
        tab.applyAcceptedMainFrameLifecycleURL(
            redirectURL,
            from: originatingWebView,
            navigationID: navigationIdentity
        )

        XCTAssertTrue(tab.mainFrameLoads.hasOutstandingLoad(
            on: pendingSiblingWebView,
            targetURL: redirectURL
        ))
        XCTAssertFalse(tab.mainFrameLoads.hasOutstandingLoad(
            on: pendingSiblingWebView,
            targetURL: initialURL
        ))
        tab.mainFrameLoads.finishPreparedLoad(preparationTicket)
    }

    func testPerformRunsUserContentWarmupRegisterBeforeLoadInOrder() async {
        var events: [String] = []

        await NormalTabInitialDocumentRuntimeHandoff.perform {
            events.append("waitUserContent")
        } warmInitialDocumentContexts: {
            events.append("warmInitialDocumentContexts")
        } isStillValid: {
            true
        } register: {
            events.append("register")
        } load: {
            events.append("load")
        }

        XCTAssertEqual(
            events,
            [
                "waitUserContent",
                "warmInitialDocumentContexts",
                "register",
                "load",
            ]
        )
    }

    func testPerformSkipsWarmupWhenCommandIsNoLongerValidAfterUserContent() async {
        var events: [String] = []

        await NormalTabInitialDocumentRuntimeHandoff.perform {
            events.append("waitUserContent")
        } warmInitialDocumentContexts: {
            events.append("warmInitialDocumentContexts")
        } isStillValid: {
            false
        } register: {
            events.append("register")
        } load: {
            events.append("load")
        }

        XCTAssertEqual(
            events,
            [
                "waitUserContent",
            ]
        )
    }

    func testPerformStopsAfterWarmupWhenCommandIsNoLongerValidBeforeLoad() async {
        var events: [String] = []
        var isValid = true

        await NormalTabInitialDocumentRuntimeHandoff.perform {
            events.append("waitUserContent")
        } warmInitialDocumentContexts: {
            events.append("warmInitialDocumentContexts")
            isValid = false
        } isStillValid: {
            isValid
        } register: {
            events.append("register")
        } load: {
            events.append("load")
        }

        XCTAssertEqual(
            events,
            [
                "waitUserContent",
                "warmInitialDocumentContexts",
            ]
        )
    }

    func testTabSetupInitialLoadWaitsForInitialUserContent() async {
        let targetURL = URL(string: "https://example.com/deferred")!
        let controller = DelayedNormalTabUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = InitialDocumentRecordingWebView(
            frame: .zero,
            configuration: configuration
        )
        let tab = Tab(
            url: targetURL,
            existingWebView: webView,
            loadsCachedFaviconOnInit: false
        )
        tab.replaceUntrackedWebView(webView)
        tab.clearParkedExistingWebView()
        _ = tab.installNavigationDelegate(on: webView)

        NormalTabInitialDocumentRuntimeHandoff.scheduleTabSetupInitialLoad(
            tab: tab,
            webView: webView,
            targetURL: targetURL,
            profileId: nil,
            registrationReason: "InitialDocumentRuntimeHandoffTests"
        )

        for _ in 0..<20 {
            await Task.yield()
            if controller.waitCallCount > 0 {
                break
            }
        }

        XCTAssertEqual(controller.waitCallCount, 1)
        XCTAssertTrue(webView.loadedRequests.isEmpty)

        controller.finishInitialUserContentInstallation()

        for _ in 0..<20 {
            await Task.yield()
            if webView.loadedRequests.isEmpty == false {
                break
            }
        }

        XCTAssertEqual(webView.loadedRequests.compactMap(\.url), [targetURL])
        XCTAssertEqual(tab.url, targetURL)
    }

    func testTabSetupInitialLoadDoesNotOverwriteNewerNavigationOnSameWebView() async {
        let initialURL = URL(string: "https://example.com/initial")!
        let newerURL = URL(string: "https://example.com/newer")!
        let controller = DelayedNormalTabUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = InitialDocumentRecordingWebView(
            frame: .zero,
            configuration: configuration
        )
        let tab = Tab(
            url: initialURL,
            existingWebView: webView,
            loadsCachedFaviconOnInit: false
        )
        tab.replaceUntrackedWebView(webView)
        tab.clearParkedExistingWebView()
        _ = tab.installNavigationDelegate(on: webView)

        NormalTabInitialDocumentRuntimeHandoff.scheduleTabSetupInitialLoad(
            tab: tab,
            webView: webView,
            targetURL: initialURL,
            profileId: nil,
            registrationReason: "InitialDocumentRuntimeHandoffTests.stale"
        )

        for _ in 0..<20 {
            await Task.yield()
            if controller.waitCallCount > 0 {
                break
            }
        }
        XCTAssertEqual(controller.waitCallCount, 1)

        webView.returnsConcreteNavigation = true
        tab.loadURL(newerURL)
        XCTAssertEqual(tab.url, newerURL)
        XCTAssertEqual(webView.loadedRequests.compactMap(\.url), [newerURL])

        controller.finishInitialUserContentInstallation()
        for _ in 0..<20 {
            await Task.yield()
        }

        XCTAssertEqual(tab.url, newerURL)
        XCTAssertEqual(webView.loadedRequests.compactMap(\.url), [newerURL])
    }

    func testDelayedInitialLoadSurvivesUntrackedToWindowAdoption() async {
        let targetURL = URL(string: "https://example.com/adopted")!
        let controller = DelayedNormalTabUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = InitialDocumentRecordingWebView(
            frame: .zero,
            configuration: configuration
        )
        let sessions = WebViewSessionRepository()
        let tab = Tab(
            url: targetURL,
            webViewSessions: sessions,
            loadsCachedFaviconOnInit: false
        )
        tab.replaceUntrackedWebView(webView)
        _ = tab.beginMainFrameNavigationIntent(to: targetURL)
        _ = tab.installNavigationDelegate(on: webView)

        NormalTabInitialDocumentRuntimeHandoff.scheduleTabSetupInitialLoad(
            tab: tab,
            webView: webView,
            targetURL: targetURL,
            profileId: nil,
            registrationReason: "InitialDocumentRuntimeHandoffTests.adopted"
        )
        for _ in 0..<20 where controller.waitCallCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(controller.waitCallCount, 1)

        let owner = TrackedWebViewOwner(tabID: tab.id, windowID: UUID())
        WebViewTrackingLifecycleOwner().registerTrackedWebView(
            webView,
            for: owner,
            in: sessions,
            removeFromContainers: { _ in /* No-op. */ },
            installRuntimeObservations: { _ in /* No-op. */ },
            uninstallRuntimeObservationsIfUntracked: { _ in /* No-op. */ },
            pruneInvalidDeferredCommands: { _ in /* No-op. */ },
            canDisplaceWebView: { _ in true },
            removeRecentVisibility: { _ in /* No-op. */ },
            cleanupDisplacedWebView: { _, _ in /* No-op. */ }
        )
        XCTAssertEqual(sessions.residence(of: webView), .window(owner))

        controller.finishInitialUserContentInstallation()
        for _ in 0..<20 where webView.loadedRequests.isEmpty {
            await Task.yield()
        }

        XCTAssertEqual(webView.loadedRequests.compactMap(\.url), [targetURL])
    }

    func testStopLoadingInvalidatesDelayedInitialDocumentBeforeItCanLoad() async {
        let targetURL = URL(string: "https://example.com/cancelled-initial")!
        let controller = DelayedNormalTabUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = InitialDocumentRecordingWebView(
            frame: .zero,
            configuration: configuration
        )
        let tab = Tab(
            url: targetURL,
            existingWebView: webView,
            loadsCachedFaviconOnInit: false
        )
        tab.replaceUntrackedWebView(webView)
        tab.clearParkedExistingWebView()
        _ = tab.installNavigationDelegate(on: webView)

        NormalTabInitialDocumentRuntimeHandoff.scheduleTabSetupInitialLoad(
            tab: tab,
            webView: webView,
            targetURL: targetURL,
            profileId: nil,
            registrationReason: "InitialDocumentRuntimeHandoffTests.cancelled"
        )

        for _ in 0..<20 {
            await Task.yield()
            if controller.waitCallCount > 0 { break }
        }
        XCTAssertEqual(controller.waitCallCount, 1)

        tab.stopLoading(on: webView)
        controller.finishInitialUserContentInstallation()
        for _ in 0..<20 {
            await Task.yield()
        }

        XCTAssertTrue(webView.loadedRequests.isEmpty)
        XCTAssertTrue(webView.loadedFileURLs.isEmpty)
    }

    func testTabSetupInitialLoadUsesFileURLLoadingForNonHTTPDocument() async {
        let targetURL = URL(fileURLWithPath: "/tmp/sumi-initial-document/index.html")
        let controller = DelayedNormalTabUserContentController()
        controller.hasInstalledInitialUserContent = true
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = InitialDocumentRecordingWebView(
            frame: .zero,
            configuration: configuration
        )
        let tab = Tab(
            url: targetURL,
            existingWebView: webView,
            loadsCachedFaviconOnInit: false
        )
        tab.replaceUntrackedWebView(webView)
        tab.clearParkedExistingWebView()
        _ = tab.installNavigationDelegate(on: webView)

        NormalTabInitialDocumentRuntimeHandoff.scheduleTabSetupInitialLoad(
            tab: tab,
            webView: webView,
            targetURL: targetURL,
            profileId: nil,
            registrationReason: "InitialDocumentRuntimeHandoffTests.file"
        )

        for _ in 0..<20 {
            await Task.yield()
            if webView.loadedFileURLs.isEmpty == false { break }
        }

        XCTAssertTrue(webView.loadedRequests.isEmpty)
        XCTAssertEqual(webView.loadedFileURLs.map(\.url), [targetURL])
        XCTAssertEqual(
            webView.loadedFileURLs.map(\.readAccessURL),
            [targetURL.deletingLastPathComponent()]
        )
    }

    func testTabSetupInitialLoadWarmsInitialDocumentContextsThroughInjectedRuntime() async {
        let profileId = UUID()
        let targetURL = URL(string: "https://example.com/deferred")!
        let controller = DelayedNormalTabUserContentController()
        controller.hasInstalledInitialUserContent = true
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        let tab = Tab(
            url: targetURL,
            existingWebView: webView,
            loadsCachedFaviconOnInit: false
        )
        tab.replaceUntrackedWebView(webView)
        tab.clearParkedExistingWebView()
        _ = tab.installNavigationDelegate(on: webView)

        var warmedProfileIds: [UUID] = []
        tab.navigationRuntime.normalWebViewExtensionRuntime = TabNormalWebViewExtensionRuntime(
            registerTabWithExtensionRuntimeIfNeeded: { _, _ in /* No-op. */ },
            prepareWebViewForExtensionRuntime: { _, _, _ in /* No-op. */ },
            ensureInitialExtensionContextsIfNeeded: { warmedProfileId in
                warmedProfileIds.append(warmedProfileId)
            }
        )

        NormalTabInitialDocumentRuntimeHandoff.scheduleTabSetupInitialLoad(
            tab: tab,
            webView: webView,
            targetURL: targetURL,
            profileId: profileId,
            registrationReason: "InitialDocumentRuntimeHandoffTests"
        )

        for _ in 0..<20 {
            await Task.yield()
            if warmedProfileIds.isEmpty == false {
                break
            }
        }

        XCTAssertFalse(tab.hasBrowserRuntime)
        XCTAssertEqual(warmedProfileIds, [profileId])
    }

    private func makeTab(
        url: URL
    ) -> (Tab, TabMainFrameRuntimeTransaction) {
        let transaction = TabMainFrameRuntimeTransaction(initialURL: url)
        return (
            Tab(
                url: url,
                loadsCachedFaviconOnInit: false,
                mainFrameRuntimeTransaction: transaction
            ),
            transaction
        )
    }

    private func assertPublishedCommit(
        _ decision: TabMainFrameCommitDecision,
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        targetURL: URL,
        isPDF: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .publish(let publication) = decision else {
            return XCTFail("Expected commit publication, got \(decision)", file: file, line: line)
        }

        XCTAssertTrue(publication.webView === webView, file: file, line: line)
        XCTAssertEqual(
            publication.authority.navigationID,
            navigationID,
            file: file,
            line: line
        )
        XCTAssertEqual(publication.targetURL, targetURL, file: file, line: line)
        XCTAssertEqual(publication.isPDF, isPDF, file: file, line: line)
    }

    private func assertRecordedReplica(
        _ decision: TabMainFrameCommitDecision,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .recordedReplica = decision else {
            return XCTFail("Expected replica commit, got \(decision)", file: file, line: line)
        }
    }
}

@MainActor
private final class StopTrackingWebView: WKWebView {
    private(set) var stopLoadingCount = 0

    override func stopLoading() {
        stopLoadingCount += 1
    }
}

@MainActor
private final class InitialDocumentRecordingWebView: WKWebView {
    private(set) var loadedRequests: [URLRequest] = []
    private(set) var loadedFileURLs: [(url: URL, readAccessURL: URL)] = []
    var returnsConcreteNavigation = false

    override func load(_ request: URLRequest) -> WKNavigation? {
        loadedRequests.append(request)
        return returnsConcreteNavigation ? super.load(request) : nil
    }

    override func loadFileURL(
        _ fileURL: URL,
        allowingReadAccessTo readAccessURL: URL
    ) -> WKNavigation? {
        loadedFileURLs.append((fileURL, readAccessURL))
        return nil
    }
}

@MainActor
private final class DelayedNormalTabUserContentController:
    WKUserContentController,
    SumiNormalTabUserContentControlling {
    var normalTabUserScriptsProvider: SumiNormalTabUserScripts?
    var contentBlockingAssetSummary = SumiNormalTabContentBlockingAssetSummary(
        isInstalled: false,
        globalRuleListCount: 0,
        updateRuleCount: 0,
        isContentBlockingFeatureEnabled: false
    )
    var hasInstalledInitialUserContent = false
    private(set) var waitCallCount = 0
    private var continuation: CheckedContinuation<Void, Never>?

    var wkUserContentController: WKUserContentController {
        self
    }

    #if DEBUG
        var contentBlockingAssetSummaryPublisher: AnyPublisher<SumiNormalTabContentBlockingAssetSummary, Never> {
            Just(contentBlockingAssetSummary).eraseToAnyPublisher()
        }
    #endif

    func replaceNormalTabUserScripts(with provider: SumiNormalTabUserScripts) async {
        normalTabUserScriptsProvider = provider
    }

    func waitForContentBlockingAssetsInstalled() async {
        waitCallCount += 1
        guard hasInstalledInitialUserContent == false else { return }

        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finishInitialUserContentInstallation() {
        hasInstalledInitialUserContent = true
        continuation?.resume()
        continuation = nil
    }

    func cleanUpBeforeClosing() { /* No-op. */ }
}
