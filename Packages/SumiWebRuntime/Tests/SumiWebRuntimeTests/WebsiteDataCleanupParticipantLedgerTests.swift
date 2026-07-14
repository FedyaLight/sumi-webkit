import Foundation
import WebKit
import XCTest

@testable import SumiWebRuntime

@MainActor
final class WebsiteDataCleanupParticipantLedgerTests: XCTestCase {
    func testSessionOwnsOneExactParticipantPerLiveWebView() throws {
        let ledger = WebsiteDataCleanupParticipantLedger()
        let webView = WKWebView()
        let firstSession = try XCTUnwrap(ledger.beginSession())

        XCTAssertNil(ledger.beginSession())
        let first = try XCTUnwrap(
            ledger.register(webView, in: firstSession)
        )
        let duplicate = try XCTUnwrap(
            ledger.register(webView, in: firstSession)
        )
        XCTAssertTrue(first === duplicate)
        XCTAssertTrue(ledger.participant(for: webView) === first)
        XCTAssertTrue(ledger.contains(webView, in: firstSession))
        XCTAssertEqual(ledger.participantCount(in: firstSession), 1)

        ledger.invalidate(firstSession)
        XCTAssertFalse(ledger.isValid(firstSession))
        ledger.release(firstSession)
        XCTAssertNil(ledger.participant(for: webView))

        let secondSession = try XCTUnwrap(ledger.beginSession())
        let second = try XCTUnwrap(
            ledger.register(webView, in: secondSession)
        )
        XCTAssertFalse(first === second)
        ledger.release(firstSession)
        XCTAssertTrue(ledger.isValid(secondSession))
        XCTAssertTrue(ledger.participant(for: webView) === second)
    }

    func testBlankWaitSettlesOnlyForExactNavigationIdentity() async throws {
        let ledger = WebsiteDataCleanupParticipantLedger()
        let webView = WKWebView()
        let session = try XCTUnwrap(ledger.beginSession())
        let participant = try XCTUnwrap(ledger.register(webView, in: session))
        let lifetime = NSObject()
        let identity = WebsiteDataCleanupParticipantLedger.NavigationIdentity(
            id: ObjectIdentifier(lifetime),
            lifetime: lifetime
        )
        ledger.beginBlankWait(
            for: participant,
            navigation: identity,
            deadline: ContinuousClock.now + .seconds(2)
        )

        XCTAssertTrue(ledger.isSuppressingNavigation(
            on: webView,
            navigationID: identity.id,
            navigationLifetime: lifetime
        ))
        let foreignLifetime = NSObject()
        XCTAssertFalse(ledger.isSuppressingNavigation(
            on: webView,
            navigationID: identity.id,
            navigationLifetime: foreignLifetime
        ))

        ledger.navigationDidTerminate(
            on: webView,
            navigationID: identity.id,
            navigationLifetime: foreignLifetime,
            succeeded: false
        )
        ledger.navigationDidTerminate(
            on: webView,
            navigationID: identity.id,
            navigationLifetime: lifetime,
            succeeded: true
        )
        let result = await ledger.awaitTerminalResult(for: participant)
        XCTAssertTrue(result)
    }

    func testRestoreTerminalEventCanArriveBeforeSemanticReceipt() async throws {
        let ledger = WebsiteDataCleanupParticipantLedger()
        let webView = WKWebView()
        let session = try XCTUnwrap(ledger.beginSession())
        let participant = try XCTUnwrap(
            ledger.register(webView, in: session, touchedAndBlanked: true)
        )
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/path"))
        ledger.beginRestoreAttempt(
            [participant],
            targetURL: targetURL,
            deadline: ContinuousClock.now + .seconds(2)
        )

        let lifetime = NSObject()
        let navigationID = ObjectIdentifier(lifetime)
        ledger.navigationWillStart(
            on: webView,
            navigationID: navigationID,
            navigationLifetime: lifetime,
            targetURL: targetURL,
            semanticRevision: 41
        )
        ledger.navigationDidTerminate(
            on: webView,
            navigationID: navigationID,
            navigationLifetime: lifetime,
            succeeded: true
        )
        ledger.bindRestoreSemanticRevision(41, to: participant)

        let result = await ledger.awaitTerminalResult(for: participant)
        XCTAssertTrue(result)
        ledger.finishRestoreAttempt([participant], succeeded: true)
        XCTAssertTrue(
            ledger.pendingRestoreParticipants(among: [participant]).isEmpty
        )
    }

    func testRestoreRejectsWrongURLAndSemanticRevision() async throws {
        let ledger = WebsiteDataCleanupParticipantLedger()
        let webView = WKWebView()
        let session = try XCTUnwrap(ledger.beginSession())
        let participant = try XCTUnwrap(
            ledger.register(webView, in: session, touchedAndBlanked: true)
        )
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/right"))
        let wrongURL = try XCTUnwrap(URL(string: "https://example.com/wrong"))
        ledger.beginRestoreAttempt(
            [participant],
            targetURL: targetURL,
            deadline: ContinuousClock.now + .seconds(2)
        )

        let wrongURLLifetime = NSObject()
        ledger.navigationWillStart(
            on: webView,
            navigationID: ObjectIdentifier(wrongURLLifetime),
            navigationLifetime: wrongURLLifetime,
            targetURL: wrongURL,
            semanticRevision: 7
        )
        let wrongRevisionLifetime = NSObject()
        ledger.navigationWillStart(
            on: webView,
            navigationID: ObjectIdentifier(wrongRevisionLifetime),
            navigationLifetime: wrongRevisionLifetime,
            targetURL: targetURL,
            semanticRevision: 8
        )
        ledger.bindRestoreSemanticRevision(7, to: participant)
        ledger.navigationDidTerminate(
            on: webView,
            navigationID: ObjectIdentifier(wrongRevisionLifetime),
            navigationLifetime: wrongRevisionLifetime,
            succeeded: true
        )
        ledger.rejectRestoreAttempt([participant])

        let result = await ledger.awaitTerminalResult(for: participant)
        XCTAssertFalse(result)
    }

    func testTerminalShutdownDiscardsWaitAndRejectsReplacementSession()
        async throws {
        let ledger = WebsiteDataCleanupParticipantLedger()
        let webView = WKWebView()
        let session = try XCTUnwrap(ledger.beginSession())
        let participant = try XCTUnwrap(ledger.register(webView, in: session))
        let lifetime = NSObject()
        ledger.beginBlankWait(
            for: participant,
            navigation: .init(
                id: ObjectIdentifier(lifetime),
                lifetime: lifetime
            ),
            deadline: ContinuousClock.now + .seconds(2)
        )
        let waiterStarted = expectation(description: "terminal wait started")
        let waiter = Task { @MainActor in
            waiterStarted.fulfill()
            return await ledger.awaitTerminalResult(for: participant)
        }
        await fulfillment(of: [waiterStarted], timeout: 1)

        ledger.resetForTerminalShutdown()

        let result = await waiter.value
        XCTAssertFalse(result)
        XCTAssertNil(ledger.participant(for: webView))
        XCTAssertNil(ledger.beginSession())
    }

    func testDiscardedReceiptCannotSettleReplacementReceipt() async {
        let first = WebsiteDataCleanupTerminalReceipt(
            deadline: ContinuousClock.now + .seconds(2)
        )
        let firstStarted = expectation(description: "first receipt wait started")
        let firstWaiter = Task { @MainActor in
            firstStarted.fulfill()
            return await first.awaitResult()
        }
        await fulfillment(of: [firstStarted], timeout: 1)
        first.discard()

        let replacement = WebsiteDataCleanupTerminalReceipt(
            deadline: ContinuousClock.now + .seconds(2)
        )
        let replacementStarted = expectation(
            description: "replacement receipt wait started"
        )
        let replacementWaiter = Task { @MainActor in
            replacementStarted.fulfill()
            return await replacement.awaitResult()
        }
        await fulfillment(of: [replacementStarted], timeout: 1)

        first.complete(with: true)
        replacement.complete(with: false)

        let firstResult = await firstWaiter.value
        let replacementResult = await replacementWaiter.value
        XCTAssertFalse(firstResult)
        XCTAssertFalse(replacementResult)
    }
}
