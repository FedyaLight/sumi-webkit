import XCTest

@testable import Sumi

@MainActor
final class CommandPaletteDeferredTextOwnerTests: XCTestCase {
    func testDeferredTextAppliesForCurrentVisibleSession() {
        let owner = CommandPaletteDeferredTextOwner()
        let windowState = BrowserWindowState()
        windowState.presentationState.isCommandPaletteVisible = true
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
        let owner = CommandPaletteDeferredTextOwner()
        let windowState = BrowserWindowState()
        windowState.presentationState.isCommandPaletteVisible = true
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
        let owner = CommandPaletteDeferredTextOwner()
        let windowState = BrowserWindowState()
        windowState.presentationState.isCommandPaletteVisible = true
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

        windowState.presentationState.isCommandPaletteVisible = false
        scheduled[0]()

        XCTAssertTrue(appliedTexts.isEmpty)
    }

    func testLatestPendingTextWinsWithinCurrentSession() {
        let owner = CommandPaletteDeferredTextOwner()
        let windowState = BrowserWindowState()
        windowState.presentationState.isCommandPaletteVisible = true
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
