import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabMainFrameLoadRuntimeTests: XCTestCase {
    func testBlankDestinationRequiresExactAdmissionProvenance() throws {
        let blankURL = try XCTUnwrap(URL(string: "about:blank"))
        let lifecycle = TabMainFrameLifecycleMachine()
        let runtime = TabMainFrameLoadRuntime(
            initialURL: blankURL,
            lifecycle: lifecycle
        )

        let unadmitted = runtime.beginExplicitIntent(to: blankURL)
        XCTAssertNil(unadmitted.blankAdmission)
        XCTAssertFalse(runtime.admitsCommit(to: blankURL))

        let admission = BlankDocumentAdmission(
            id: UUID(),
            source: .explicitUserCommand
        )
        let admitted = runtime.beginExplicitIntent(
            to: blankURL,
            blankAdmission: admission
        )
        XCTAssertEqual(admitted.blankAdmission, admission)
        XCTAssertGreaterThan(admitted.revision, unadmitted.revision)
        XCTAssertTrue(runtime.admitsCommit(to: blankURL))
    }

    func testPreparedAttemptTransfersOneExactOwnerIntoNativeLifecycle() throws {
        let targetURL = try XCTUnwrap(
            URL(string: "https://example.com/prepared-transfer")
        )
        let lifecycle = TabMainFrameLifecycleMachine()
        let runtime = TabMainFrameLoadRuntime(
            initialURL: targetURL,
            lifecycle: lifecycle
        )
        let webView = WKWebView()
        let intent = runtime.beginExplicitIntent(to: targetURL)
        let ticket = try XCTUnwrap(
            runtime.beginPreparedLoad(on: webView, intent: intent)
        )

        guard case .waiting(let waitingOwner) = runtime.attemptStatus(
            on: webView
        ) else {
            return XCTFail("Prepared work must expose its exact waiting owner")
        }
        XCTAssertEqual(waitingOwner.phase, .preparing(ticketID: ticket.id))
        XCTAssertEqual(waitingOwner.intent, intent)

        let submissionLease = try XCTUnwrap(
            runtime.claimPreparedSubmission(on: webView, ticket: ticket)
        )
        guard case .submitted(let submittedOwner) = runtime.attemptStatus(
            on: webView
        ) else {
            return XCTFail("Transferred work must expose its submitted owner")
        }
        XCTAssertEqual(submittedOwner.phase, .submitted)
        XCTAssertEqual(submittedOwner.participantID, waitingOwner.participantID)
        XCTAssertEqual(submissionLease.participantID, waitingOwner.participantID)

        let binding = try XCTUnwrap(
            runtime.consumeSubmittedLoad(
                on: webView,
                matching: submissionLease
            )
        )
        let navigation = NSObject()
        XCTAssertTrue(lifecycle.activateSubmission(
            binding,
            navigationID: ObjectIdentifier(navigation),
            navigationLifetime: navigation,
            currentIntent: intent
        ))
        XCTAssertEqual(runtime.attemptStatus(on: webView), .unsubmitted(intent))
    }

    func testPendingAttemptTerminalReceiptsPreserveExactOwner() throws {
        let targetURL = try XCTUnwrap(
            URL(string: "https://example.com/terminal-receipts")
        )
        let lifecycle = TabMainFrameLifecycleMachine()
        let runtime = TabMainFrameLoadRuntime(
            initialURL: targetURL,
            lifecycle: lifecycle
        )
        let cancelledWebView = WKWebView()
        let failedWebView = WKWebView()
        let departedWebView = WKWebView()
        let intent = runtime.beginExplicitIntent(to: targetURL)

        let cancelledTicket = try XCTUnwrap(
            runtime.beginPreparedLoad(on: cancelledWebView, intent: intent)
        )
        guard case .waiting(let cancelledOwner) = runtime.attemptStatus(
            on: cancelledWebView
        ) else {
            return XCTFail("Expected a cancellable waiting owner")
        }
        XCTAssertEqual(
            runtime.cancelPreparedLoad(cancelledTicket)?.owner,
            cancelledOwner
        )
        XCTAssertEqual(
            runtime.cancelPreparedLoad(cancelledTicket)?.reason,
            nil,
            "Cancellation must be exactly once"
        )

        let failedLease = try XCTUnwrap(
            runtime.claimDirectSubmission(on: failedWebView)
        )
        guard case .submitted(let failedOwner) = runtime.attemptStatus(
            on: failedWebView
        ) else {
            return XCTFail("Expected a submitted owner")
        }
        let failure = runtime.failSubmittedLoad(
            on: failedWebView,
            matching: failedLease
        )
        XCTAssertEqual(failure.settlement?.owner, failedOwner)
        XCTAssertEqual(failure.settlement?.reason, .failed)

        XCTAssertTrue(runtime.markDeferredLoad(
            on: departedWebView,
            intent: intent
        ))
        guard case .waiting(let departedOwner) = runtime.attemptStatus(
            on: departedWebView
        ) else {
            return XCTFail("Expected a deferred waiting owner")
        }
        let departure = runtime.departure(of: departedWebView)
        XCTAssertEqual(departure.settlements.map(\.owner), [departedOwner])
        XCTAssertEqual(departure.settlements.map(\.reason), [.departed])
    }

    func testDeferredDuplicateCoalescesBehindExactSameOwner() throws {
        let targetURL = try XCTUnwrap(
            URL(string: "https://example.com/coalesced-owner")
        )
        let runtime = TabMainFrameLoadRuntime(
            initialURL: targetURL,
            lifecycle: TabMainFrameLifecycleMachine()
        )
        let webView = WKWebView()
        let intent = runtime.beginExplicitIntent(to: targetURL)

        guard case .waiting(let firstOwner) = runtime.deferAttempt(
            on: webView,
            intent: intent
        ) else {
            return XCTFail("First deferral must create one exact waiting owner")
        }
        guard case .coalesced(let coalescedOwner) = runtime.deferAttempt(
            on: webView,
            intent: intent
        ) else {
            return XCTFail("Duplicate deferral must name the existing owner")
        }
        XCTAssertEqual(coalescedOwner, firstOwner)
    }

    func testPendingAuthorityContinuationExpiresAfterTargetUpdate() throws {
        let initialURL = try XCTUnwrap(URL(string: "https://example.com/initial"))
        let redirectedURL = try XCTUnwrap(URL(string: "https://example.com/redirected"))
        let ledger = TabMainFrameIntentLedger(initialURL: initialURL)
        let webView = WKWebView()
        _ = ledger.beginExplicitIntent(to: initialURL)
        XCTAssertNotNil(ledger.claimDirectSubmission(
            on: webView,
            documentGeneration: 0,
            hasLifecycleAuthority: false
        ))
        let staleContinuation = try XCTUnwrap(
            ledger.promoteSubmittedAuthority()
        )

        ledger.updateTargetWithinRevision(redirectedURL)

        XCTAssertFalse(ledger.isCurrentPendingAuthority(staleContinuation))
        XCTAssertEqual(
            ledger.promoteSubmittedAuthority()?.targetURL,
            redirectedURL
        )
    }

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

    func testLiveLifecycleAuthorityCoalescesDuplicateWithoutBecomingDeferred() throws {
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

        guard case .coalesced(let owner) = runtime.deferAttempt(
            on: authorityWebView,
            intent: intent
        ) else {
            return XCTFail("Duplicate delivery must name the active owner")
        }
        XCTAssertEqual(owner.phase, .submitted)
        XCTAssertEqual(owner.webViewID, ObjectIdentifier(authorityWebView))
        guard case .unsubmitted = runtime.attemptStatus(on: authorityWebView) else {
            return XCTFail("Coalescing must not create a second pending attempt")
        }
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
