import XCTest

@testable import Sumi

@MainActor
final class FloatingBarFocusRequestOwnerTests: XCTestCase {
    func testSessionIdentityInvalidatesWhenWindowChanges() {
        let owner = FloatingBarFocusRequestOwner()
        let firstWindowID = UUID()
        let secondWindowID = UUID()

        let firstSession = owner.beginSession(windowID: firstWindowID)
        XCTAssertTrue(owner.isCurrent(firstSession))

        let secondSession = owner.beginSession(windowID: secondWindowID)
        XCTAssertFalse(owner.isCurrent(firstSession))
        XCTAssertTrue(owner.isCurrent(secondSession))
    }

    func testDeferredFocusRunsForCurrentSession() async throws {
        let owner = FloatingBarFocusRequestOwner()
        let windowID = UUID()
        let focusExpectation = expectation(description: "deferred focus runs")
        var didFocus = false

        owner.beginSession(windowID: windowID)
        owner.scheduleDeferredFocus(windowID: windowID) {
            didFocus = true
            focusExpectation.fulfill()
        }

        await fulfillment(of: [focusExpectation], timeout: 1.0)
        XCTAssertTrue(didFocus)
    }

    func testDeferredFocusIsCancelledWhenSessionEnds() async throws {
        let owner = FloatingBarFocusRequestOwner()
        let windowID = UUID()
        let focusExpectation = expectation(description: "deferred focus is cancelled")
        focusExpectation.isInverted = true
        var didFocus = false

        owner.beginSession(windowID: windowID)
        owner.scheduleDeferredFocus(windowID: windowID) {
            didFocus = true
            focusExpectation.fulfill()
        }
        owner.endSession()

        await fulfillment(of: [focusExpectation], timeout: 0.05)
        XCTAssertFalse(didFocus)
    }

    func testDeferredFocusIgnoresMismatchedWindow() async throws {
        let owner = FloatingBarFocusRequestOwner()
        let focusExpectation = expectation(description: "mismatched deferred focus is ignored")
        focusExpectation.isInverted = true
        var didFocus = false

        owner.beginSession(windowID: UUID())
        owner.scheduleDeferredFocus(windowID: UUID()) {
            didFocus = true
            focusExpectation.fulfill()
        }

        await fulfillment(of: [focusExpectation], timeout: 0.05)
        XCTAssertFalse(didFocus)
    }
}
