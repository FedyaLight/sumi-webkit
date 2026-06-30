import XCTest

@testable import Sumi

@MainActor
final class FloatingBarDeferredTextOwnerTests: XCTestCase {
    func testDeferredTextAppliesForCurrentVisibleSession() {
        let owner = FloatingBarDeferredTextOwner()
        let windowState = BrowserWindowState()
        windowState.isFloatingBarVisible = true
        var scheduled: [@MainActor () -> Void] = []
        var appliedTexts: [String] = []

        owner.beginSession(windowID: windowState.id)
        XCTAssertTrue(
            owner.scheduleTextChange(
                in: windowState,
                text: "swift",
                scheduler: { scheduled.append($0) },
                apply: { appliedTexts.append($0) }
            )
        )

        XCTAssertEqual(scheduled.count, 1)
        scheduled[0]()

        XCTAssertEqual(appliedTexts, ["swift"])
    }

    func testDeferredTextIsSuppressedAfterSessionEnds() {
        let owner = FloatingBarDeferredTextOwner()
        let windowState = BrowserWindowState()
        windowState.isFloatingBarVisible = true
        var scheduled: [@MainActor () -> Void] = []
        var appliedTexts: [String] = []

        owner.beginSession(windowID: windowState.id)
        XCTAssertTrue(
            owner.scheduleTextChange(
                in: windowState,
                text: "stale",
                scheduler: { scheduled.append($0) },
                apply: { appliedTexts.append($0) }
            )
        )

        owner.endSession()
        scheduled[0]()

        XCTAssertTrue(appliedTexts.isEmpty)
    }

    func testDeferredTextIsSuppressedWhenBarHidesBeforeFlush() {
        let owner = FloatingBarDeferredTextOwner()
        let windowState = BrowserWindowState()
        windowState.isFloatingBarVisible = true
        var scheduled: [@MainActor () -> Void] = []
        var appliedTexts: [String] = []

        owner.beginSession(windowID: windowState.id)
        XCTAssertTrue(
            owner.scheduleTextChange(
                in: windowState,
                text: "hidden",
                scheduler: { scheduled.append($0) },
                apply: { appliedTexts.append($0) }
            )
        )

        windowState.isFloatingBarVisible = false
        scheduled[0]()

        XCTAssertTrue(appliedTexts.isEmpty)
    }

    func testLatestPendingTextWinsWithinCurrentSession() {
        let owner = FloatingBarDeferredTextOwner()
        let windowState = BrowserWindowState()
        windowState.isFloatingBarVisible = true
        var scheduled: [@MainActor () -> Void] = []
        var appliedTexts: [String] = []

        owner.beginSession(windowID: windowState.id)
        XCTAssertTrue(
            owner.scheduleTextChange(
                in: windowState,
                text: "s",
                scheduler: { scheduled.append($0) },
                apply: { appliedTexts.append($0) }
            )
        )
        XCTAssertTrue(
            owner.scheduleTextChange(
                in: windowState,
                text: "sw",
                scheduler: { scheduled.append($0) },
                apply: { appliedTexts.append($0) }
            )
        )

        scheduled[0]()
        scheduled[1]()

        XCTAssertEqual(appliedTexts, ["sw"])
    }
}
