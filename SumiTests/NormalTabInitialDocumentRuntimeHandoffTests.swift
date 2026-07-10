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
        let tab = Tab(url: targetURL, loadsCachedFaviconOnInit: false)
        let intent = tab.beginMainFrameNavigationIntent(to: targetURL)
        let navigation = NSObject()
        let navigationID = ObjectIdentifier(navigation)

        XCTAssertTrue(tab.claimDirectMainFrameLoad(on: webView))
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
            on: webView,
            navigationID: navigationID,
            navigationLifetime: navigation
        ))

        XCTAssertNil(tab.beginPreparedMainFrameLoad(on: webView, intent: intent))
        XCTAssertTrue(tab.shouldAcceptMainFrameLifecycle(
            from: webView,
            navigationID: navigationID,
            isCurrent: true
        ))
    }

    func testAuthorityMovesToActiveSiblingWhenAuthoritativeWebViewLeaves() throws {
        let initialURL = try XCTUnwrap(URL(string: "https://example.com/start"))
        let firstRedirectURL = try XCTUnwrap(URL(string: "https://example.com/first"))
        let siblingCommitURL = try XCTUnwrap(URL(string: "https://example.com/sibling"))
        let authoritativeWebView = WKWebView()
        let siblingWebView = WKWebView()
        let tab = Tab(url: initialURL, loadsCachedFaviconOnInit: false)
        _ = tab.beginMainFrameNavigationIntent(to: initialURL)
        let firstNavigation = NSObject()
        let siblingNavigation = NSObject()
        let firstNavigationID = ObjectIdentifier(firstNavigation)
        let siblingNavigationID = ObjectIdentifier(siblingNavigation)

        XCTAssertTrue(tab.claimDirectMainFrameLoad(on: authoritativeWebView))
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
            on: authoritativeWebView,
            navigationID: firstNavigationID,
            navigationLifetime: firstNavigation
        ))
        XCTAssertTrue(tab.claimDirectMainFrameLoad(on: siblingWebView))
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
            on: siblingWebView,
            navigationID: siblingNavigationID,
            navigationLifetime: siblingNavigation
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
        XCTAssertTrue(tab.shouldAcceptMainFrameLifecycle(
            from: siblingWebView,
            navigationID: siblingNavigationID,
            isCurrent: true
        ))
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
        let tab = Tab(url: targetURL, loadsCachedFaviconOnInit: false)
        _ = tab.beginMainFrameNavigationIntent(to: targetURL)
        tab.beginLoadingPresentationIfNeeded()
        let firstNavigation = NSObject()
        let secondNavigation = NSObject()
        let firstID = ObjectIdentifier(firstNavigation)
        let secondID = ObjectIdentifier(secondNavigation)
        XCTAssertTrue(tab.claimDirectMainFrameLoad(on: firstWebView))
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
            on: firstWebView,
            navigationID: firstID,
            navigationLifetime: firstNavigation
        ))
        XCTAssertTrue(tab.claimDirectMainFrameLoad(on: secondWebView))
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
            on: secondWebView,
            navigationID: secondID,
            navigationLifetime: secondNavigation
        ))

        tab.stopLoading(on: secondWebView)

        XCTAssertEqual(firstWebView.stopLoadingCount, 1)
        XCTAssertEqual(secondWebView.stopLoadingCount, 1)
        XCTAssertFalse(tab.loadingState.isLoading)
        XCTAssertFalse(tab.shouldAcceptMainFrameLifecycle(
            from: firstWebView,
            navigationID: firstID,
            isCurrent: true
        ))
        XCTAssertFalse(tab.shouldAcceptMainFrameLifecycle(
            from: secondWebView,
            navigationID: secondID,
            isCurrent: true
        ))
    }

    func testRedirectCanSupersedeActiveSiblingWithProtectedDeferredTarget() throws {
        let initialURL = try XCTUnwrap(URL(string: "https://example.com/start"))
        let redirectURL = try XCTUnwrap(URL(string: "https://example.com/redirect"))
        let authoritativeWebView = WKWebView()
        let protectedSibling = WKWebView()
        let tab = Tab(url: initialURL, loadsCachedFaviconOnInit: false)
        _ = tab.beginMainFrameNavigationIntent(to: initialURL)
        let authorityNavigation = NSObject()
        let siblingNavigation = NSObject()
        let authorityID = ObjectIdentifier(authorityNavigation)
        let siblingID = ObjectIdentifier(siblingNavigation)

        XCTAssertTrue(tab.claimDirectMainFrameLoad(on: authoritativeWebView))
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
            on: authoritativeWebView,
            navigationID: authorityID,
            navigationLifetime: authorityNavigation
        ))
        XCTAssertTrue(tab.claimDirectMainFrameLoad(on: protectedSibling))
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
            on: protectedSibling,
            navigationID: siblingID,
            navigationLifetime: siblingNavigation
        ))
        tab.applyAcceptedMainFrameLifecycleURL(
            redirectURL,
            from: authoritativeWebView,
            navigationID: authorityID
        )
        let redirectedIntent = try XCTUnwrap(
            tab.currentMainFrameNavigationIntent(matching: redirectURL)
        )

        XCTAssertTrue(tab.markDeferredMainFrameLoad(
            on: protectedSibling,
            intent: redirectedIntent
        ))
        XCTAssertFalse(tab.shouldAcceptMainFrameLifecycle(
            from: protectedSibling,
            navigationID: siblingID,
            isCurrent: true
        ))
        XCTAssertEqual(
            tab.claimDeferredMainFrameLoad(
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

        XCTAssertTrue(tab.markDeferredMainFrameLoad(on: webView, intent: intent))
        XCTAssertEqual(
            tab.claimDeferredMainFrameLoad(
                on: webView,
                revision: intent.revision,
                targetURL: targetURL
            ),
            .claimed
        )
        tab.restoreDeferredMainFrameLoadAfterFailedSubmission(
            on: webView,
            revision: intent.revision,
            targetURL: targetURL
        )
        XCTAssertEqual(
            tab.claimDeferredMainFrameLoad(
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
        let tab = Tab(url: targetURL, loadsCachedFaviconOnInit: false)
        let intent = tab.beginMainFrameNavigationIntent(to: targetURL)
        let siblingNavigation = NSObject()
        let siblingNavigationID = ObjectIdentifier(siblingNavigation)

        XCTAssertTrue(tab.markDeferredMainFrameLoad(
            on: failedDeferredWebView,
            intent: intent
        ))
        XCTAssertEqual(tab.claimDeferredMainFrameLoad(
            on: failedDeferredWebView,
            revision: intent.revision,
            targetURL: targetURL
        ), .claimed)
        tab.restoreDeferredMainFrameLoadAfterFailedSubmission(
            on: failedDeferredWebView,
            revision: intent.revision,
            targetURL: targetURL
        )

        XCTAssertTrue(tab.claimDirectMainFrameLoad(on: activeSibling))
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
            on: activeSibling,
            navigationID: siblingNavigationID,
            navigationLifetime: siblingNavigation
        ))
        XCTAssertTrue(tab.shouldAcceptMainFrameLifecycle(
            from: activeSibling,
            navigationID: siblingNavigationID,
            isCurrent: true
        ))
    }

    func testFailedAuthoritySubmissionPromotesAlreadyActiveSibling() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/shared"))
        let failedWebView = WKWebView()
        let activeSibling = WKWebView()
        let tab = Tab(url: targetURL, loadsCachedFaviconOnInit: false)
        _ = tab.beginMainFrameNavigationIntent(to: targetURL)
        let siblingNavigation = NSObject()
        let siblingNavigationID = ObjectIdentifier(siblingNavigation)

        XCTAssertTrue(tab.claimDirectMainFrameLoad(on: failedWebView))
        XCTAssertTrue(tab.claimDirectMainFrameLoad(on: activeSibling))
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
            on: activeSibling,
            navigationID: siblingNavigationID,
            navigationLifetime: siblingNavigation
        ))

        tab.failSubmittedMainFrameLoad(on: failedWebView)

        XCTAssertTrue(tab.shouldAcceptMainFrameLifecycle(
            from: activeSibling,
            navigationID: siblingNavigationID,
            isCurrent: true
        ))
    }

    func testCompletedIdentityIsRetiredAndNextLifecycleGetsNewRevision() throws {
        let firstURL = try XCTUnwrap(URL(string: "https://example.com/first"))
        let secondURL = try XCTUnwrap(URL(string: "https://example.com/second"))
        let webView = WKWebView()
        let tab = Tab(url: firstURL, loadsCachedFaviconOnInit: false)
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
        let firstIntent = try XCTUnwrap(tab.currentMainFrameNavigationIntent(matching: firstURL))
        tab.finishMainFrameLifecycle(from: webView, navigationID: firstID)
        XCTAssertFalse(tab.shouldAcceptMainFrameLifecycle(
            from: webView,
            navigationID: firstID,
            isCurrent: true
        ))

        XCTAssertEqual(tab.beginMainFrameLifecycle(
            from: webView,
            navigationID: secondID,
            navigationLifetime: secondNavigation,
            targetURL: secondURL,
            allowsUserInitiatedSupersession: false,
            continuationKind: nil
        ), .authority)
        let secondIntent = try XCTUnwrap(tab.currentMainFrameNavigationIntent(matching: secondURL))
        XCTAssertGreaterThan(secondIntent.revision, firstIntent.revision)
    }

    func testCompletedHiddenSiblingCannotStartUnboundTabWideNavigation() throws {
        let settledURL = try XCTUnwrap(URL(string: "https://example.com/settled"))
        let hiddenTargetURL = try XCTUnwrap(URL(string: "https://hidden.example/next"))
        let authorityWebView = WKWebView()
        let hiddenWebView = WKWebView()
        let tab = Tab(url: settledURL, loadsCachedFaviconOnInit: false)
        _ = tab.beginMainFrameNavigationIntent(to: settledURL)
        let authorityNavigation = NSObject()
        let hiddenNavigation = NSObject()
        let hiddenNextNavigation = NSObject()
        let authorityID = ObjectIdentifier(authorityNavigation)
        let hiddenID = ObjectIdentifier(hiddenNavigation)

        XCTAssertTrue(tab.claimDirectMainFrameLoad(on: authorityWebView))
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
            on: authorityWebView,
            navigationID: authorityID,
            navigationLifetime: authorityNavigation
        ))
        XCTAssertTrue(tab.claimDirectMainFrameLoad(on: hiddenWebView))
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
            on: hiddenWebView,
            navigationID: hiddenID,
            navigationLifetime: hiddenNavigation
        ))
        XCTAssertTrue(tab.recordMainFrameCommitSnapshot(
            from: authorityWebView,
            navigationID: authorityID,
            committedURL: settledURL,
            isPDF: false
        ).shouldPublishSharedEffects)
        XCTAssertEqual(tab.recordMainFrameCommitSnapshot(
            from: hiddenWebView,
            navigationID: hiddenID,
            committedURL: settledURL,
            isPDF: false
        ).role, .participant)
        tab.finishMainFrameLifecycle(
            from: authorityWebView,
            navigationID: authorityID
        )
        tab.finishMainFrameLifecycle(
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
        XCTAssertNotNil(tab.currentMainFrameNavigationIntent(matching: settledURL))

        let hiddenRedirectNavigation = NSObject()
        XCTAssertEqual(tab.beginMainFrameLifecycle(
            from: hiddenWebView,
            navigationID: ObjectIdentifier(hiddenRedirectNavigation),
            navigationLifetime: hiddenRedirectNavigation,
            targetURL: hiddenTargetURL,
            allowsUserInitiatedSupersession: false,
            continuationKind: .clientRedirect
        ), .participant)
        XCTAssertNotNil(tab.currentMainFrameNavigationIntent(matching: settledURL))
        XCTAssertTrue(tab.mainFrameDocumentLease(for: authorityWebView)?.isAuthority == true)
    }

    func testCancelledIntentRejectsLateUnboundLifecycle() throws {
        let settledURL = try XCTUnwrap(URL(string: "https://example.com/settled"))
        let cancelledURL = try XCTUnwrap(URL(string: "https://example.com/cancelled"))
        let webView = WKWebView()
        let tab = Tab(url: settledURL, loadsCachedFaviconOnInit: false)
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
        XCTAssertFalse(tab.shouldAcceptMainFrameLifecycle(
            from: webView,
            navigationID: ObjectIdentifier(lateNavigation),
            isCurrent: true
        ))
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
        XCTAssertNotNil(tab.currentMainFrameNavigationIntent(matching: settledURL))
    }

    func testRedirectCommitSnapshotSurvivesAuthorityDeparture() throws {
        let requestedURL = try XCTUnwrap(URL(string: "https://example.com/request"))
        let committedURL = try XCTUnwrap(URL(string: "https://example.com/final"))
        let authorityWebView = WKWebView()
        let siblingWebView = WKWebView()
        let tab = Tab(url: requestedURL, loadsCachedFaviconOnInit: false)
        _ = tab.beginMainFrameNavigationIntent(to: requestedURL)
        let authorityNavigation = NSObject()
        let siblingNavigation = NSObject()
        let authorityID = ObjectIdentifier(authorityNavigation)
        let siblingID = ObjectIdentifier(siblingNavigation)

        XCTAssertTrue(tab.claimDirectMainFrameLoad(on: authorityWebView))
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
            on: authorityWebView,
            navigationID: authorityID,
            navigationLifetime: authorityNavigation
        ))
        XCTAssertTrue(tab.claimDirectMainFrameLoad(on: siblingWebView))
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
            on: siblingWebView,
            navigationID: siblingID,
            navigationLifetime: siblingNavigation
        ))
        XCTAssertTrue(tab.recordMainFrameCommitSnapshot(
            from: authorityWebView,
            navigationID: authorityID,
            committedURL: committedURL,
            isPDF: false
        ).shouldPublishSharedEffects)
        XCTAssertEqual(tab.recordMainFrameCommitSnapshot(
            from: siblingWebView,
            navigationID: siblingID,
            committedURL: committedURL,
            isPDF: false
        ).role, .participant)
        tab.finishMainFrameLifecycle(
            from: siblingWebView,
            navigationID: siblingID
        )

        let departure = tab.webViewDidLeaveNavigationRuntime(authorityWebView)

        XCTAssertEqual(departure.continuation?.targetURL, committedURL)
        XCTAssertTrue(departure.hasReplacementAuthority)
        XCTAssertNotNil(tab.currentMainFrameNavigationIntent(matching: committedURL))
    }

    func testPromotedCommitIdentitySeparatesLaterIncompatibleDocument() throws {
        let firstURL = try XCTUnwrap(URL(string: "https://first.example/document"))
        let promotedURL = try XCTUnwrap(URL(string: "https://second.example/document"))
        let laterURL = try XCTUnwrap(URL(string: "https://third.example/document"))
        let firstWebView = WKWebView()
        let promotedWebView = WKWebView()
        let laterWebView = WKWebView()
        let tab = Tab(url: firstURL, loadsCachedFaviconOnInit: false)
        _ = tab.beginMainFrameNavigationIntent(to: firstURL)
        let firstNavigation = NSObject()
        let promotedNavigation = NSObject()
        let laterNavigation = NSObject()
        let firstID = ObjectIdentifier(firstNavigation)
        let promotedID = ObjectIdentifier(promotedNavigation)
        let laterID = ObjectIdentifier(laterNavigation)

        XCTAssertTrue(tab.claimDirectMainFrameLoad(on: firstWebView))
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
            on: firstWebView,
            navigationID: firstID,
            navigationLifetime: firstNavigation
        ))
        XCTAssertTrue(tab.claimDirectMainFrameLoad(on: promotedWebView))
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
            on: promotedWebView,
            navigationID: promotedID,
            navigationLifetime: promotedNavigation
        ))
        XCTAssertTrue(tab.recordMainFrameCommitSnapshot(
            from: firstWebView,
            navigationID: firstID,
            committedURL: firstURL,
            isPDF: false
        ).shouldPublishSharedEffects)
        XCTAssertEqual(tab.recordMainFrameCommitSnapshot(
            from: promotedWebView,
            navigationID: promotedID,
            committedURL: promotedURL,
            isPDF: false
        ).role, .participant)
        tab.finishMainFrameLifecycle(from: firstWebView, navigationID: firstID)
        tab.finishMainFrameLifecycle(
            from: promotedWebView,
            navigationID: promotedID
        )

        let firstDeparture = tab.webViewDidLeaveNavigationRuntime(firstWebView)
        XCTAssertEqual(firstDeparture.continuation?.targetURL, promotedURL)
        XCTAssertTrue(firstDeparture.continuation?.needsSharedCommitEffects == true)
        XCTAssertEqual(tab.url, promotedURL)

        XCTAssertTrue(tab.claimDirectMainFrameLoad(on: laterWebView))
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
            on: laterWebView,
            navigationID: laterID,
            navigationLifetime: laterNavigation
        ))
        XCTAssertEqual(tab.recordMainFrameCommitSnapshot(
            from: laterWebView,
            navigationID: laterID,
            committedURL: laterURL,
            isPDF: false
        ).role, .participant)
        tab.finishMainFrameLifecycle(from: laterWebView, navigationID: laterID)

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
        let tab = Tab(url: originalURL, loadsCachedFaviconOnInit: false)
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
            XCTAssertTrue(tab.claimDirectMainFrameLoad(on: webView))
            XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
                on: webView,
                navigationID: ObjectIdentifier(navigation),
                navigationLifetime: navigation
            ))
        }

        XCTAssertTrue(tab.recordMainFrameCommitSnapshot(
            from: originalWebView,
            navigationID: ObjectIdentifier(originalNavigation),
            committedURL: originalURL,
            isPDF: false
        ).shouldPublishSharedEffects)
        for (webView, navigation) in participants.dropFirst() {
            XCTAssertEqual(tab.recordMainFrameCommitSnapshot(
                from: webView,
                navigationID: ObjectIdentifier(navigation),
                committedURL: promotedURL,
                isPDF: false
            ).role, .participant)
        }
        for (webView, navigation) in participants {
            tab.finishMainFrameLifecycle(
                from: webView,
                navigationID: ObjectIdentifier(navigation)
            )
        }

        let firstDeparture = tab.webViewDidLeaveNavigationRuntime(originalWebView)
        let firstContinuation = try XCTUnwrap(firstDeparture.continuation)
        XCTAssertEqual(firstContinuation.targetURL, promotedURL)
        XCTAssertTrue(firstContinuation.needsSharedCommitEffects)

        let firstLease = try XCTUnwrap(
            tab.mainFrameDocumentLease(for: firstPromotedReplica)
        )
        let secondLease = try XCTUnwrap(
            tab.mainFrameDocumentLease(for: secondPromotedReplica)
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
            tab.mainFrameDocumentLease(for: remainingReplica)
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
        let tab = Tab(url: survivingURL, loadsCachedFaviconOnInit: false)
        _ = tab.beginMainFrameNavigationIntent(to: cancelledURL)
        tab.url = cancelledURL
        tab.beginLoadingPresentationIfNeeded()
        let navigation = NSObject()
        let navigationID = ObjectIdentifier(navigation)
        XCTAssertTrue(tab.claimDirectMainFrameLoad(on: webView))
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
            on: webView,
            navigationID: navigationID,
            navigationLifetime: navigation
        ))

        SumiTabLifecycleNavigationResponder(tab: tab).mainFrameNavigationDidTerminate(
            SumiMainFrameNavigationTermination(
                navigationID: navigationID,
                navigationLifetime: navigation,
                webView: webView,
                reason: .actionCancelled
            )
        )

        XCTAssertEqual(tab.url, survivingURL)
        XCTAssertNotNil(tab.currentMainFrameNavigationIntent(matching: survivingURL))
        XCTAssertFalse(tab.loadingState.isLoading)
        XCTAssertFalse(tab.shouldAcceptMainFrameLifecycle(
            from: webView,
            navigationID: navigationID,
            isCurrent: true
        ))
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
        XCTAssertTrue(tab.claimDirectMainFrameLoad(on: webView))
        let navigation = NSObject()

        SumiTabLifecycleNavigationResponder(tab: tab).mainFrameNavigationDidTerminate(
            SumiMainFrameNavigationTermination(
                navigationID: ObjectIdentifier(navigation),
                navigationLifetime: navigation,
                webView: webView,
                reason: .actionCancelled
            )
        )

        XCTAssertEqual(tab.url, cancelledURL)
        XCTAssertTrue(tab.loadingState.isLoading)
        XCTAssertFalse(tab.claimDirectMainFrameLoad(on: webView))
    }

    func testTerminalIdentityCannotAbortWithoutExactNavigationLifetime() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/target"))
        let webView = SumiNavigationURLReportingWebView(frame: .zero)
        let tab = Tab(url: targetURL, loadsCachedFaviconOnInit: false)
        _ = tab.beginMainFrameNavigationIntent(to: targetURL)
        let navigation = NSObject()
        let navigationID = ObjectIdentifier(navigation)
        XCTAssertTrue(tab.claimDirectMainFrameLoad(on: webView))
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
            on: webView,
            navigationID: navigationID,
            navigationLifetime: navigation
        ))

        let wrongLifetime = NSObject()
        SumiTabLifecycleNavigationResponder(tab: tab).mainFrameNavigationDidTerminate(
            SumiMainFrameNavigationTermination(
                navigationID: navigationID,
                navigationLifetime: wrongLifetime,
                webView: webView,
                reason: .actionCancelled
            )
        )

        XCTAssertTrue(tab.shouldAcceptMainFrameLifecycle(
            from: webView,
            navigationID: navigationID,
            isCurrent: true
        ))
        SumiTabLifecycleNavigationResponder(tab: tab).mainFrameNavigationDidTerminate(
            SumiMainFrameNavigationTermination(
                navigationID: navigationID,
                navigationLifetime: navigation,
                webView: webView,
                reason: .actionCancelled
            )
        )
        XCTAssertFalse(tab.shouldAcceptMainFrameLifecycle(
            from: webView,
            navigationID: navigationID,
            isCurrent: true
        ))
    }

    func testFailedAuthorityPromotesActiveSiblingWithoutPublishingSharedFailure() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/target"))
        let siblingCommitURL = try XCTUnwrap(URL(string: "https://example.com/sibling"))
        let failedWebView = SumiNavigationURLReportingWebView(frame: .zero)
        let activeSibling = SumiNavigationURLReportingWebView(frame: .zero)
        failedWebView.reportedURL = targetURL
        activeSibling.reportedURL = siblingCommitURL
        let tab = Tab(url: targetURL, loadsCachedFaviconOnInit: false)
        _ = tab.beginMainFrameNavigationIntent(to: targetURL)
        tab.beginLoadingPresentationIfNeeded()
        let failedNavigation = NSObject()
        let siblingNavigation = NSObject()
        let failedID = ObjectIdentifier(failedNavigation)
        let siblingID = ObjectIdentifier(siblingNavigation)
        XCTAssertTrue(tab.claimDirectMainFrameLoad(on: failedWebView))
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
            on: failedWebView,
            navigationID: failedID,
            navigationLifetime: failedNavigation
        ))
        XCTAssertTrue(tab.claimDirectMainFrameLoad(on: activeSibling))
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
            on: activeSibling,
            navigationID: siblingID,
            navigationLifetime: siblingNavigation
        ))

        SumiTabLifecycleNavigationResponder(tab: tab).navigationDidFail(
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

        XCTAssertTrue(tab.shouldAcceptMainFrameLifecycle(
            from: activeSibling,
            navigationID: siblingID,
            isCurrent: true
        ))
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
        let tab = Tab(url: targetURL, loadsCachedFaviconOnInit: false)
        _ = tab.beginMainFrameNavigationIntent(to: targetURL)
        tab.beginLoadingPresentationIfNeeded()
        let navigation = NSObject()
        let navigationID = ObjectIdentifier(navigation)
        XCTAssertTrue(tab.claimDirectMainFrameLoad(on: webView))
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
            on: webView,
            navigationID: navigationID,
            navigationLifetime: navigation
        ))

        let recoveryPlan = tab.beginWebContentProcessRecovery(on: webView)

        XCTAssertEqual(recoveryPlan.scope, .global(targetURL))
        XCTAssertNil(recoveryPlan.authorityContinuation)
        XCTAssertTrue(tab.requiresWebContentProcessRecovery(on: webView))
        XCTAssertFalse(tab.shouldAcceptMainFrameLifecycle(
            from: webView,
            navigationID: navigationID,
            isCurrent: true
        ))
    }

    func testCompletedReplicaCrashKeepsHealthyAuthorityAndRevision() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/process"))
        let authorityWebView = WKWebView()
        let crashedReplica = WKWebView()
        let tab = Tab(url: targetURL, loadsCachedFaviconOnInit: false)
        let intent = tab.beginMainFrameNavigationIntent(to: targetURL)
        let authorityNavigation = NSObject()
        let replicaNavigation = NSObject()
        let authorityID = ObjectIdentifier(authorityNavigation)
        let replicaID = ObjectIdentifier(replicaNavigation)
        XCTAssertTrue(tab.claimDirectMainFrameLoad(on: authorityWebView))
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
            on: authorityWebView,
            navigationID: authorityID,
            navigationLifetime: authorityNavigation
        ))
        XCTAssertTrue(tab.claimDirectMainFrameLoad(on: crashedReplica))
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
            on: crashedReplica,
            navigationID: replicaID,
            navigationLifetime: replicaNavigation
        ))
        XCTAssertTrue(tab.recordMainFrameCommitSnapshot(
            from: authorityWebView,
            navigationID: authorityID,
            committedURL: targetURL,
            isPDF: false
        ).shouldPublishSharedEffects)
        XCTAssertEqual(tab.recordMainFrameCommitSnapshot(
            from: crashedReplica,
            navigationID: replicaID,
            committedURL: targetURL,
            isPDF: false
        ).role, .participant)
        tab.finishMainFrameLifecycle(
            from: authorityWebView,
            navigationID: authorityID
        )
        tab.finishMainFrameLifecycle(
            from: crashedReplica,
            navigationID: replicaID
        )

        let recoveryPlan = tab.beginWebContentProcessRecovery(on: crashedReplica)

        XCTAssertEqual(recoveryPlan.scope, .replica(intent))
        XCTAssertNil(recoveryPlan.authorityContinuation)
        XCTAssertTrue(tab.mainFrameDocumentLease(for: authorityWebView)?.isAuthority == true)
        XCTAssertNil(tab.mainFrameDocumentLease(for: crashedReplica))
        XCTAssertTrue(tab.requiresWebContentProcessRecovery(on: crashedReplica))
        XCTAssertTrue(tab.isCurrentMainFrameNavigationIntent(intent))
    }

    func testLateTerminationFromUnownedWebViewCannotTriggerRecovery() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/process"))
        let webView = WKWebView()
        let tab = Tab(url: targetURL, loadsCachedFaviconOnInit: false)

        SumiTabLifecycleNavigationResponder(tab: tab)
            .webContentProcessDidTerminate(on: webView)

        XCTAssertFalse(tab.requiresWebContentProcessRecovery(on: webView))
        XCTAssertEqual(tab.currentMainFrameNavigationIntent().targetURL, targetURL)
    }

    func testTrustedContinuationTransfersExactAuthorityWithinRevision() throws {
        let initialURL = try XCTUnwrap(URL(string: "https://example.com/start"))
        let continuationURL = try XCTUnwrap(URL(string: "https://example.com/spa"))
        let webView = WKWebView()
        let tab = Tab(url: initialURL, loadsCachedFaviconOnInit: false)
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
            tab.currentMainFrameNavigationIntent(matching: initialURL)
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
            tab.currentMainFrameNavigationIntent(matching: continuationURL)?.revision,
            revision
        )
        XCTAssertFalse(tab.shouldAcceptMainFrameLifecycle(
            from: webView,
            navigationID: firstID,
            isCurrent: true
        ))
        XCTAssertTrue(tab.shouldAcceptMainFrameLifecycle(
            from: webView,
            navigationID: continuationID,
            isCurrent: true
        ))
    }

    func testPresentationURLWriteDoesNotInvalidateNavigationIntent() throws {
        let pendingURL = try XCTUnwrap(URL(string: "https://example.com/pending"))
        let presentationURL = try XCTUnwrap(URL(string: "https://example.com/old"))
        let tab = Tab(url: presentationURL, loadsCachedFaviconOnInit: false)
        let intent = tab.beginMainFrameNavigationIntent(to: pendingURL)

        tab.url = presentationURL

        XCTAssertTrue(tab.isCurrentMainFrameNavigationIntent(
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
            tab.beginPreparedMainFrameLoad(
                on: pendingSiblingWebView,
                intent: intent
            )
        )
        let navigation = NSObject()
        let navigationIdentity = ObjectIdentifier(navigation)
        XCTAssertTrue(tab.claimDirectMainFrameLoad(on: originatingWebView))
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
            on: originatingWebView,
            navigationID: navigationIdentity,
            navigationLifetime: navigation
        ))
        tab.applyAcceptedMainFrameLifecycleURL(
            redirectURL,
            from: originatingWebView,
            navigationID: navigationIdentity
        )

        XCTAssertTrue(tab.hasOutstandingMainFrameLoad(
            on: pendingSiblingWebView,
            targetURL: redirectURL
        ))
        XCTAssertFalse(tab.hasOutstandingMainFrameLoad(
            on: pendingSiblingWebView,
            targetURL: initialURL
        ))
        tab.finishPreparedMainFrameLoad(preparationTicket)
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
