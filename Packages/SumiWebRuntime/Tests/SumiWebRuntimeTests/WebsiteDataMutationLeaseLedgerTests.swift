import Foundation
import XCTest

@testable import SumiWebRuntime

@MainActor
final class WebsiteDataMutationLeaseLedgerTests: XCTestCase {
    func testExclusiveLeasesHandOffInFIFOOrder() async throws {
        let ledger = WebsiteDataMutationLeaseLedger()
        let acquiredFirst = await ledger.acquire(scopeIDs: [UUID()])
        let first = try XCTUnwrap(acquiredFirst)
        let secondScope = UUID()
        let thirdScope = UUID()

        let secondStarted = expectation(description: "second lease requested")
        let secondTask = Task { @MainActor in
            secondStarted.fulfill()
            return await ledger.acquire(scopeIDs: [secondScope])
        }
        await fulfillment(of: [secondStarted], timeout: 1)

        let thirdStarted = expectation(description: "third lease requested")
        let thirdTask = Task { @MainActor in
            thirdStarted.fulfill()
            return await ledger.acquire(scopeIDs: [thirdScope])
        }
        await fulfillment(of: [thirdStarted], timeout: 1)

        XCTAssertTrue(ledger.release(first))
        let acquiredSecond = await secondTask.value
        let second = try XCTUnwrap(acquiredSecond)
        XCTAssertTrue(ledger.blocksAdmission(for: secondScope))
        XCTAssertFalse(ledger.blocksAdmission(for: thirdScope))

        XCTAssertTrue(ledger.release(second))
        let acquiredThird = await thirdTask.value
        let third = try XCTUnwrap(acquiredThird)
        XCTAssertTrue(ledger.blocksAdmission(for: thirdScope))
        XCTAssertTrue(ledger.release(third))
    }

    func testCancelledLeaseWaiterCannotAcquireAfterRelease() async throws {
        let ledger = WebsiteDataMutationLeaseLedger()
        let acquiredFirst = await ledger.acquire(scopeIDs: [UUID()])
        let first = try XCTUnwrap(acquiredFirst)
        let waiterStarted = expectation(description: "lease waiter requested")
        let waiter = Task { @MainActor in
            waiterStarted.fulfill()
            return await ledger.acquire(scopeIDs: [UUID()])
        }
        await fulfillment(of: [waiterStarted], timeout: 1)

        waiter.cancel()
        let cancelledLease = await waiter.value
        XCTAssertNil(cancelledLease)
        XCTAssertTrue(ledger.release(first))

        let acquiredReplacement = await ledger.acquire(scopeIDs: [UUID()])
        let replacement = try XCTUnwrap(acquiredReplacement)
        XCTAssertTrue(ledger.release(replacement))
    }

    func testAdmissionWaitRemainsBlockedAcrossSameScopeLeaseHandoff()
        async throws {
        let ledger = WebsiteDataMutationLeaseLedger()
        let scopeID = UUID()
        let acquiredFirst = await ledger.acquire(scopeIDs: [scopeID])
        let first = try XCTUnwrap(acquiredFirst)

        let secondStarted = expectation(description: "replacement lease requested")
        let secondTask = Task { @MainActor in
            secondStarted.fulfill()
            return await ledger.acquire(scopeIDs: [scopeID])
        }
        await fulfillment(of: [secondStarted], timeout: 1)

        let admissionStarted = expectation(description: "admission wait requested")
        var admissionResult: Bool?
        let admissionTask = Task { @MainActor in
            admissionStarted.fulfill()
            let result = await ledger.waitForAdmission(for: scopeID)
            admissionResult = result
            return result
        }
        await fulfillment(of: [admissionStarted], timeout: 1)

        XCTAssertTrue(ledger.release(first))
        let acquiredSecond = await secondTask.value
        let second = try XCTUnwrap(acquiredSecond)
        XCTAssertNil(admissionResult)

        XCTAssertTrue(ledger.release(second))
        let resolvedAdmission = await admissionTask.value
        XCTAssertTrue(resolvedAdmission)
        XCTAssertEqual(admissionResult, true)
    }

    func testTerminalShutdownRejectsAndResumesEveryPendingOperation()
        async throws {
        let ledger = WebsiteDataMutationLeaseLedger()
        let scopeID = UUID()
        let acquiredLease = await ledger.acquire(scopeIDs: [scopeID])
        _ = try XCTUnwrap(acquiredLease)

        let leaseWaiterStarted = expectation(description: "lease waiter requested")
        let leaseWaiter = Task { @MainActor in
            leaseWaiterStarted.fulfill()
            return await ledger.acquire(scopeIDs: [UUID()])
        }
        let admissionWaiterStarted = expectation(description: "admission waiter requested")
        let admissionWaiter = Task { @MainActor in
            admissionWaiterStarted.fulfill()
            return await ledger.waitForAdmission(for: scopeID)
        }
        await fulfillment(
            of: [leaseWaiterStarted, admissionWaiterStarted],
            timeout: 1
        )

        ledger.resetForTerminalShutdown()

        let rejectedLease = await leaseWaiter.value
        let rejectedAdmission = await admissionWaiter.value
        let postShutdownLease = await ledger.acquire(scopeIDs: [UUID()])
        let postShutdownAdmission = await ledger.waitForAdmission(for: scopeID)
        XCTAssertNil(rejectedLease)
        XCTAssertFalse(rejectedAdmission)
        XCTAssertNil(postShutdownLease)
        XCTAssertFalse(postShutdownAdmission)
    }
}
