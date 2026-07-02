import AppKit
@testable import Sumi
import XCTest

@MainActor
final class WebKitGlanceCursorStabilizationOwnerTests: XCTestCase {
    func testRestoresCursorBeforeMoveWhenWebKitFallsBackToArrow() throws {
        let event = try Self.mouseMovedEvent(timestamp: 1)
        var currentCursor = NSCursor.pointingHand
        var setCursors: [NSCursor] = []
        let owner = makeOwner(
            currentCursor: { currentCursor },
            setCursor: { setCursors.append($0) },
            performDefaultMouseMoved: { _ in currentCursor = .arrow }
        )

        owner.mouseMoved(with: event)

        XCTAssertEqual(setCursors.count, 1)
        XCTAssertIdentical(setCursors[0], NSCursor.pointingHand)
    }

    func testReusesRecentlyCapturedPageCursorNearLastPoint() throws {
        let firstEvent = try Self.mouseMovedEvent(location: CGPoint(x: 10, y: 10), timestamp: 1)
        let secondEvent = try Self.mouseMovedEvent(location: CGPoint(x: 30, y: 24), timestamp: 1.1)
        var currentCursor = NSCursor.pointingHand
        var setCursors: [NSCursor] = []
        let owner = makeOwner(
            currentCursor: { currentCursor },
            setCursor: { setCursors.append($0) },
            performDefaultMouseMoved: { _ in currentCursor = .arrow }
        )

        owner.cursorUpdated(with: firstEvent)
        currentCursor = .arrow
        owner.mouseMoved(with: secondEvent)

        XCTAssertEqual(setCursors.count, 1)
        XCTAssertIdentical(setCursors[0], NSCursor.pointingHand)
    }

    func testDoesNotReuseCapturedCursorAfterReuseInterval() throws {
        let firstEvent = try Self.mouseMovedEvent(location: CGPoint(x: 10, y: 10), timestamp: 1)
        let secondEvent = try Self.mouseMovedEvent(location: CGPoint(x: 30, y: 24), timestamp: 1.3)
        var currentCursor = NSCursor.pointingHand
        var setCursors: [NSCursor] = []
        let owner = makeOwner(
            currentCursor: { currentCursor },
            setCursor: { setCursors.append($0) },
            performDefaultMouseMoved: { _ in currentCursor = .arrow }
        )

        owner.cursorUpdated(with: firstEvent)
        currentCursor = .arrow
        owner.mouseMoved(with: secondEvent)

        XCTAssertTrue(setCursors.isEmpty)
    }

    private func makeOwner(
        isEnabled: @escaping @MainActor () -> Bool = { true },
        pointInView: @escaping @MainActor (NSEvent) -> CGPoint? = { $0.locationInWindow },
        currentMousePointInView: @escaping @MainActor () -> CGPoint? = { CGPoint(x: 10, y: 10) },
        containsPoint: @escaping @MainActor (CGPoint) -> Bool = { point in
            CGRect(x: 0, y: 0, width: 100, height: 100).contains(point)
        },
        currentCursor: @escaping @MainActor () -> NSCursor = { .arrow },
        setCursor: @escaping @MainActor (NSCursor) -> Void = { _ in },
        performDefaultMouseMoved: @escaping @MainActor (NSEvent) -> Void = { _ in },
        scheduleSettleCapture: @escaping @MainActor (DispatchWorkItem) -> Void = { _ in },
        currentTimestamp: @escaping @MainActor () -> TimeInterval = { 1 }
    ) -> WebKitGlanceCursorStabilizationOwner {
        WebKitGlanceCursorStabilizationOwner(
            dependencies: WebKitGlanceCursorStabilizationOwner.Dependencies(
                isEnabled: isEnabled,
                pointInView: pointInView,
                currentMousePointInView: currentMousePointInView,
                containsPoint: containsPoint,
                currentCursor: currentCursor,
                setCursor: setCursor,
                performDefaultMouseMoved: performDefaultMouseMoved,
                scheduleSettleCapture: scheduleSettleCapture,
                currentTimestamp: currentTimestamp
            )
        )
    }

    private static func mouseMovedEvent(
        location: CGPoint = CGPoint(x: 10, y: 10),
        timestamp: TimeInterval
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .mouseMoved,
                location: location,
                modifierFlags: [],
                timestamp: timestamp,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 0,
                pressure: 0
            )
        )
    }
}
