import AppKit
import XCTest

@testable import Sumi

@MainActor
final class CommandPaletteNativeInteractionTests: XCTestCase {
    func testFocusRunsOnlyForCurrentWindowSession() async {
        let interaction = CommandPaletteNativeInteraction()
        let windowID = UUID()
        var focusCount = 0

        interaction.beginSession(windowID: windowID)
        interaction.scheduleFocus(windowID: UUID()) {
            XCTFail("Another window must not receive palette focus")
        }
        interaction.scheduleFocus(windowID: windowID) {
            focusCount += 1
        }

        for _ in 0..<10 where focusCount == 0 {
            await Task.yield()
        }

        XCTAssertEqual(focusCount, 1)
    }

    func testLatestDeferredTextWinsWithinVisibleSession() {
        let interaction = CommandPaletteNativeInteraction()
        let windowState = BrowserWindowState()
        windowState.presentationState.isCommandPaletteVisible = true
        var scheduled: [@MainActor () -> Void] = []
        var applied: [String] = []

        interaction.beginSession(windowID: windowState.id)
        XCTAssertTrue(interaction.scheduleTextChange(
            in: windowState,
            text: "s",
            scheduler: { scheduled.append($0) },
            apply: { applied.append($0) }
        ))
        XCTAssertTrue(interaction.scheduleTextChange(
            in: windowState,
            text: "sumi",
            scheduler: { scheduled.append($0) },
            apply: { applied.append($0) }
        ))

        scheduled.forEach { $0() }

        XCTAssertEqual(applied, ["sumi"])
    }

    func testDeferredWorkCannotCrossSessionOrVisibilityBoundary() {
        let interaction = CommandPaletteNativeInteraction()
        let windowState = BrowserWindowState()
        windowState.presentationState.isCommandPaletteVisible = true
        var scheduled: [@MainActor () -> Void] = []
        var mutationCount = 0

        interaction.beginSession(windowID: windowState.id)
        XCTAssertTrue(interaction.requestCommit(
            in: windowState,
            scheduler: { scheduled.append($0) },
            perform: { mutationCount += 1 }
        ))

        interaction.endSession()
        scheduled.removeFirst()()
        interaction.beginSession(windowID: windowState.id)
        XCTAssertTrue(interaction.requestDismiss(
            in: windowState,
            scheduler: { scheduled.append($0) },
            perform: { mutationCount += 1 }
        ))
        windowState.presentationState.isCommandPaletteVisible = false
        scheduled.removeFirst()()

        XCTAssertEqual(mutationCount, 0)
    }

    func testOnlyOneTerminalMutationIsAcceptedPerSession() {
        let interaction = CommandPaletteNativeInteraction()
        let windowState = BrowserWindowState()
        windowState.presentationState.isCommandPaletteVisible = true
        var scheduled: [@MainActor () -> Void] = []
        var mutationCount = 0

        interaction.beginSession(windowID: windowState.id)
        XCTAssertTrue(interaction.requestCommit(
            in: windowState,
            scheduler: { scheduled.append($0) },
            perform: { mutationCount += 1 }
        ))
        XCTAssertFalse(interaction.requestDismiss(
            in: windowState,
            scheduler: { scheduled.append($0) },
            perform: { mutationCount += 1 }
        ))

        scheduled[0]()

        XCTAssertEqual(mutationCount, 1)
        XCTAssertFalse(interaction.requestCommit(
            in: windowState,
            scheduler: { scheduled.append($0) },
            perform: { mutationCount += 1 }
        ))
    }

    func testPaletteReplacementStartsFreshTerminalMutationSession() {
        let interaction = CommandPaletteNativeInteraction()
        let windowState = BrowserWindowState()
        windowState.presentationState.isCommandPaletteVisible = true
        var scheduled: [@MainActor () -> Void] = []

        interaction.beginSession(windowID: windowState.id)
        XCTAssertTrue(interaction.requestBrowserAction(
            in: windowState,
            canPerform: { true },
            perform: { .paletteReplaced },
            dismiss: { XCTFail("Replacement must keep the palette visible") },
            onPerformed: {},
            onRejected: { XCTFail("Available action must not be rejected") },
            scheduler: { scheduled.append($0) }
        ))
        scheduled.removeFirst()()

        XCTAssertTrue(interaction.requestCommit(
            in: windowState,
            scheduler: { scheduled.append($0) },
            perform: {}
        ))
    }

    func testOutsideClickDismissesWithoutConsumingEvent() throws {
        let interaction = CommandPaletteNativeInteraction()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 140),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let card = NSView(frame: NSRect(x: 20, y: 20, width: 100, height: 60))
        window.contentView?.addSubview(card)
        interaction.updateCardView(card)
        var dismissCount = 0

        let inside = try Self.mouseDown(
            at: NSPoint(x: 32, y: 32),
            in: window
        )
        XCTAssertIdentical(
            interaction.routeMouseEvent(
                inside,
                isCommandPaletteVisible: true,
                onOutsideClick: { dismissCount += 1 }
            ),
            inside
        )

        let outside = try Self.mouseDown(
            at: NSPoint(x: 180, y: 90),
            in: window
        )
        XCTAssertIdentical(
            interaction.routeMouseEvent(
                outside,
                isCommandPaletteVisible: true,
                onOutsideClick: { dismissCount += 1 }
            ),
            outside
        )
        XCTAssertEqual(dismissCount, 1)
    }

    private static func mouseDown(
        at location: NSPoint,
        in window: NSWindow
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: location,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }
}
