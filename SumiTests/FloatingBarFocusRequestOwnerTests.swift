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
        var didFocus = false

        owner.beginSession(windowID: windowID)
        owner.scheduleDeferredFocus(windowID: windowID) {
            didFocus = true
        }

        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(didFocus)
    }

    func testDeferredFocusIsCancelledWhenSessionEnds() async throws {
        let owner = FloatingBarFocusRequestOwner()
        let windowID = UUID()
        var didFocus = false

        owner.beginSession(windowID: windowID)
        owner.scheduleDeferredFocus(windowID: windowID) {
            didFocus = true
        }
        owner.endSession()

        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertFalse(didFocus)
    }

    func testDeferredFocusIgnoresMismatchedWindow() async throws {
        let owner = FloatingBarFocusRequestOwner()
        var didFocus = false

        owner.beginSession(windowID: UUID())
        owner.scheduleDeferredFocus(windowID: UUID()) {
            didFocus = true
        }

        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertFalse(didFocus)
    }
}
