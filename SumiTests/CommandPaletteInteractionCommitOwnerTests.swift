import AppKit
import XCTest

@testable import Sumi

@MainActor
final class CommandPaletteInteractionCommitOwnerTests: XCTestCase {
    func testCommitRequestSuppressesDuplicateUntilVisibilitySessionEnds() {
        let owner = CommandPaletteInteractionCommitOwner()
        let windowState = BrowserWindowState()
        windowState.presentationState.isCommandPaletteVisible = true
        owner.beginSession(windowID: windowState.id)
        var scheduled: [@MainActor () -> Void] = []
        var commitCount = 0

        XCTAssertTrue(owner.requestCommit(in: windowState, scheduler: { scheduled.append($0) }, perform: {
            commitCount += 1
        }))
        XCTAssertFalse(owner.requestCommit(in: windowState, scheduler: { scheduled.append($0) }, perform: {
            commitCount += 1
        }))

        XCTAssertEqual(scheduled.count, 1)
        XCTAssertEqual(commitCount, 0)

        scheduled[0]()

        XCTAssertEqual(commitCount, 1)
        XCTAssertFalse(owner.requestCommit(in: windowState, scheduler: { scheduled.append($0) }, perform: {
            commitCount += 1
        }))
    }

    func testDeferredCommitIsSuppressedAfterSessionEnds() {
        let owner = CommandPaletteInteractionCommitOwner()
        let windowState = BrowserWindowState()
        windowState.presentationState.isCommandPaletteVisible = true
        owner.beginSession(windowID: windowState.id)
        var scheduled: [@MainActor () -> Void] = []
        var commitCount = 0

        XCTAssertTrue(owner.requestCommit(in: windowState, scheduler: { scheduled.append($0) }, perform: {
            commitCount += 1
        }))

        owner.endSession()
        scheduled[0]()

        XCTAssertEqual(commitCount, 0)
    }

    func testDeferredDismissIsSuppressedIfBarIsHiddenBeforeFlush() {
        let owner = CommandPaletteInteractionCommitOwner()
        let windowState = BrowserWindowState()
        windowState.presentationState.isCommandPaletteVisible = true
        owner.beginSession(windowID: windowState.id)
        var scheduled: [@MainActor () -> Void] = []
        var dismissCount = 0

        XCTAssertTrue(owner.requestDismiss(in: windowState, scheduler: { scheduled.append($0) }, perform: {
            dismissCount += 1
        }))

        windowState.presentationState.isCommandPaletteVisible = false
        scheduled[0]()

        XCTAssertEqual(dismissCount, 0)
    }

    func testCardViewResolutionIsAvailableSynchronously() {
        let owner = CommandPaletteInteractionCommitOwner()
        let cardView = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 44))
        owner.updateCardView(cardView)

        XCTAssertTrue(
            owner.isLocationInsideCard(
                NSPoint(x: 12, y: 12)
            )
        )
        XCTAssertFalse(
            owner.isLocationInsideCard(
                NSPoint(x: 180, y: 90)
            )
        )
    }
}
