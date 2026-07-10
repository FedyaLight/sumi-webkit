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
            tab.claimDirectMainFrameLoadLease(on: authorityWebView)
        )
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
            on: authorityWebView,
            navigationID: authorityNavigationID,
            navigationLifetime: authorityNavigation,
            matching: authorityLease
        ))
        let submittedLease = try XCTUnwrap(
            tab.claimDirectMainFrameLoadLease(on: submittedWebView)
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

        let lease = try XCTUnwrap(tab.claimDirectMainFrameLoadLease(on: webView))
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
        XCTAssertNil(tab.currentMainFrameNavigationIntent(matching: failedURL))
        let rollbackIntent = try XCTUnwrap(
            tab.currentMainFrameNavigationIntent(matching: committedURL)
        )
        XCTAssertEqual(rollbackIntent.revision, failedIntent.revision + 1)
        XCTAssertNil(tab.mainFrameDocumentLease(for: webView))
    }

    func testSuccessfulSuccessorBindingConsumesExactRecoveryMarker() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/recovery"))
        let webView = WKWebView()
        let tab = Tab(url: targetURL, loadsCachedFaviconOnInit: false)
        let intent = tab.beginMainFrameNavigationIntent(to: targetURL)
        let crashedNavigation = NSObject()
        let crashedNavigationID = ObjectIdentifier(crashedNavigation)

        let crashedLease = try XCTUnwrap(tab.claimDirectMainFrameLoadLease(on: webView))
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
            tab.claimDirectMainFrameLoadLease(on: webView)
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
}
