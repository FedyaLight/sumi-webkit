import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabMainFrameLoadRuntimeTests: XCTestCase {
    func testStaleSubmissionLeaseCannotConsumeSameWebViewReplacement() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/load"))
        let lifecycle = TabMainFrameLifecycleMachine()
        let runtime = TabMainFrameLoadRuntime(
            initialURL: targetURL,
            lifecycle: lifecycle
        )
        let webView = WKWebView()
        _ = runtime.beginExplicitIntent(to: targetURL)

        let staleLease = try XCTUnwrap(
            runtime.claimDirectSubmission(on: webView)
        )
        let departure = runtime.departure(of: webView)
        XCTAssertTrue(departure.removedLoad)
        XCTAssertTrue(departure.wasAuthorityCandidate)

        let replacementLease = try XCTUnwrap(
            runtime.claimDirectSubmission(on: webView)
        )
        XCTAssertNotEqual(staleLease.participantID, replacementLease.participantID)
        XCTAssertNil(
            runtime.consumeSubmittedLoad(on: webView, matching: staleLease)
        )
        let replacement = try XCTUnwrap(
            runtime.consumeSubmittedLoad(on: webView, matching: replacementLease)
        )
        XCTAssertEqual(replacement.participantID, replacementLease.participantID)
    }

    func testSameURLSuccessorIntentRejectsStalePreparationTicket() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/same"))
        let lifecycle = TabMainFrameLifecycleMachine()
        let runtime = TabMainFrameLoadRuntime(
            initialURL: targetURL,
            lifecycle: lifecycle
        )
        let webView = WKWebView()
        let staleIntent = runtime.beginExplicitIntent(to: targetURL)
        let staleTicket = try XCTUnwrap(
            runtime.beginPreparedLoad(on: webView, intent: staleIntent)
        )

        let successorIntent = runtime.beginExplicitIntent(to: targetURL)
        XCTAssertGreaterThan(successorIntent.revision, staleIntent.revision)
        XCTAssertFalse(runtime.isCurrent(staleIntent))
        XCTAssertNil(runtime.beginPreparedLoad(on: webView, intent: staleIntent))
        let successorTicket = try XCTUnwrap(
            runtime.beginPreparedLoad(on: webView, intent: successorIntent)
        )

        runtime.finishPreparedLoad(staleTicket)
        XCTAssertTrue(runtime.hasOutstandingLoad(
            on: webView,
            targetURL: targetURL
        ))
        runtime.finishPreparedLoad(successorTicket)
        XCTAssertFalse(runtime.hasOutstandingLoad(
            on: webView,
            targetURL: targetURL
        ))
    }

    func testLiveLifecycleAuthorityCannotAlsoBecomeDeferredAuthority() throws {
        let targetURL = try XCTUnwrap(
            URL(string: "https://example.com/authority")
        )
        let lifecycle = TabMainFrameLifecycleMachine()
        let runtime = TabMainFrameLoadRuntime(
            initialURL: targetURL,
            lifecycle: lifecycle
        )
        let authorityWebView = WKWebView()
        let siblingWebView = WKWebView()
        let intent = runtime.beginExplicitIntent(to: targetURL)
        let lease = try XCTUnwrap(
            runtime.claimDirectSubmission(on: authorityWebView)
        )
        let binding = try XCTUnwrap(
            runtime.consumeSubmittedLoad(
                on: authorityWebView,
                matching: lease
            )
        )
        let navigation = NSObject()
        XCTAssertTrue(lifecycle.activateSubmission(
            binding,
            navigationID: ObjectIdentifier(navigation),
            navigationLifetime: navigation,
            currentIntent: intent
        ))

        XCTAssertFalse(runtime.markDeferredLoad(
            on: authorityWebView,
            intent: intent
        ))
        XCTAssertNil(runtime.beginPreparedLoad(
            on: authorityWebView,
            intent: intent
        ))
        XCTAssertTrue(runtime.markDeferredLoad(
            on: siblingWebView,
            intent: intent
        ))
        XCTAssertEqual(runtime.claimDeferredSubmission(
            on: siblingWebView,
            revision: intent.revision,
            targetURL: targetURL
        ), .claimed)
        XCTAssertFalse(runtime.hasPendingAuthority)
    }

    func testLoadingWebViewsDeduplicatesPendingAndActiveIdentity() throws {
        let targetURL = try XCTUnwrap(
            URL(string: "https://example.com/deduplication")
        )
        let lifecycle = TabMainFrameLifecycleMachine()
        let runtime = TabMainFrameLoadRuntime(
            initialURL: targetURL,
            lifecycle: lifecycle
        )
        let webView = WKWebView()
        let intent = runtime.beginExplicitIntent(to: targetURL)
        let firstLease = try XCTUnwrap(
            runtime.claimDirectSubmission(on: webView)
        )
        let binding = try XCTUnwrap(
            runtime.consumeSubmittedLoad(on: webView, matching: firstLease)
        )
        let navigation = NSObject()
        XCTAssertTrue(lifecycle.activateSubmission(
            binding,
            navigationID: ObjectIdentifier(navigation),
            navigationLifetime: navigation,
            currentIntent: intent
        ))
        XCTAssertNotNil(runtime.claimDirectSubmission(on: webView))

        let loadingWebViews = runtime.loadingWebViews()
        XCTAssertEqual(loadingWebViews.count, 1)
        XCTAssertIdentical(loadingWebViews.first, webView)
    }
}
