import AppKit
@testable import Sumi
import XCTest

@MainActor
final class SidebarDDGHoverTests: XCTestCase {
    func testFloatingBarLayoutPolicyCapsWideWindowsAndShrinksNarrowWindows() {
        XCTAssertEqual(
            FloatingBarLayoutPolicy.effectiveWidth(availableWindowWidth: 1_200),
            765
        )
        XCTAssertEqual(
            FloatingBarLayoutPolicy.effectiveWidth(availableWindowWidth: 785),
            765
        )
        XCTAssertEqual(
            FloatingBarLayoutPolicy.effectiveWidth(availableWindowWidth: 600),
            580
        )
        XCTAssertEqual(
            FloatingBarLayoutPolicy.effectiveWidth(availableWindowWidth: 120),
            200
        )
    }

    func testFloatingBarSuggestionHeightAdaptsBeforeZenScrollLimit() throws {
        XCTAssertEqual(FloatingBarLayoutPolicy.suggestionsVisibleRowLimit, 5)
        XCTAssertEqual(FloatingBarLayoutPolicy.suggestionsHeight(for: 0), 0)
        XCTAssertEqual(FloatingBarLayoutPolicy.suggestionsHeight(for: 2), 104)
        XCTAssertEqual(FloatingBarLayoutPolicy.resultsPanelHeight(for: 0), 0)
        XCTAssertEqual(FloatingBarLayoutPolicy.resultsPanelHeight(for: 2), 116.5)
        XCTAssertEqual(FloatingBarLayoutPolicy.layoutCount(forVisibleCount: 0), 0)
        XCTAssertEqual(FloatingBarLayoutPolicy.layoutCount(forVisibleCount: 2), 2)
        XCTAssertEqual(FloatingBarLayoutPolicy.layoutCount(forVisibleCount: 6), 5)
        XCTAssertTrue(
            FloatingBarLayoutPolicy.shouldWaitForSuggestionLayout(
                isDebouncing: false,
                isLoading: true,
                visibleLayoutCount: 4
            )
        )
        XCTAssertFalse(
            FloatingBarLayoutPolicy.shouldWaitForSuggestionLayout(
                isDebouncing: false,
                isLoading: true,
                visibleLayoutCount: 5
            )
        )
        XCTAssertEqual(
            FloatingBarLayoutPolicy.suggestionsHeight(for: 6),
            FloatingBarLayoutPolicy.suggestionsMaxHeight
        )
    }

    func testFloatingBarOutsideClickRoutingKeepsInsideCardEvent() throws {
        let event = try Self.mouseDownEvent()
        var closeCount = 0

        let result = FloatingBarOutsideClickRouting.monitorResult(
            for: event,
            isFloatingBarVisible: true,
            isEventInsideCard: true
        ) {
            closeCount += 1
        }

        XCTAssertIdentical(result, event)
        XCTAssertEqual(closeCount, 0)
    }

    func testFloatingBarOutsideClickRoutingClosesOutsideCardAndPreservesEvent() throws {
        let event = try Self.mouseDownEvent()
        var closeCount = 0

        let result = FloatingBarOutsideClickRouting.monitorResult(
            for: event,
            isFloatingBarVisible: true,
            isEventInsideCard: false
        ) {
            closeCount += 1
        }

        XCTAssertIdentical(result, event)
        XCTAssertEqual(closeCount, 1)
    }

    func testFloatingBarCardHitDetectionSeparatesInsideAndOutsideGeometry() {
        let cardView = Self.makeFloatingBarCardView()

        XCTAssertTrue(FloatingBarOutsideClickRouting.isLocationInsideCard(
            NSPoint(x: 32, y: 32),
            cardView: cardView
        ))
        XCTAssertFalse(FloatingBarOutsideClickRouting.isLocationInsideCard(
            NSPoint(x: 180, y: 90),
            cardView: cardView
        ))
    }

    func testDirectMouseOverMutationDoesNotReportSwiftUIHover() {
        let view = SidebarDDGHoverTrackingView(frame: NSRect(x: 0, y: 0, width: 120, height: 36))
        var reported: [Bool] = []
        view.onHoverChanged = { reported.append($0) }

        view.isMouseOver = true
        view.isMouseOver = false

        XCTAssertEqual(reported, [])
    }

    func testTrackingViewReportsEventHoverImmediately() {
        let view = SidebarDDGHoverTrackingView(frame: NSRect(x: 0, y: 0, width: 120, height: 36))
        var reported: [Bool] = []
        view.onHoverChanged = { reported.append($0) }

        view.mouseEntered(with: Self.enterExitEvent(.mouseEntered, timestamp: 1))
        view.mouseExited(with: Self.enterExitEvent(.mouseExited, timestamp: 2))

        XCTAssertEqual(reported, [true, false])
    }

    func testTrackingViewReconcilesHoverWhenMouseIsAlreadyInsideAfterReenable() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let view = SidebarDDGHoverTrackingView(frame: NSRect(x: 0, y: 0, width: 120, height: 36))
        window.contentView?.addSubview(view)
        view.setHoverTrackingEnabled(false)

        var reported: [Bool] = []
        view.onHoverChanged = { reported.append($0) }

        view.setHoverTrackingEnabled(true)
        view.reconcileHoverForLifecycle(mouseLocationInWindow: NSPoint(x: 220, y: 100))
        reported.removeAll()
        view.reconcileHoverForLifecycle(mouseLocationInWindow: NSPoint(x: 24, y: 18))

        XCTAssertEqual(reported, [true])
        XCTAssertTrue(view.currentEffectiveHover)
    }

    func testTrackingViewDoesNotPublishWhenDisabledThroughLifecycle() {
        let view = SidebarDDGHoverTrackingView(frame: NSRect(x: 0, y: 0, width: 120, height: 36))
        var reported: [Bool] = []
        view.onHoverChanged = { reported.append($0) }

        view.mouseEntered(with: Self.enterExitEvent(.mouseEntered, timestamp: 1))
        reported.removeAll()

        view.setHoverTrackingEnabled(false)

        XCTAssertEqual(reported, [])
        XCTAssertFalse(view.currentEffectiveHover)
        XCTAssertNil(view.hitTest(NSPoint(x: 12, y: 12)))
    }

    func testStaleMouseEnteredAfterNewerExitDoesNotPublishHover() {
        let view = SidebarDDGHoverTrackingView(frame: NSRect(x: 0, y: 0, width: 120, height: 36))
        var reported: [Bool] = []
        view.onHoverChanged = { reported.append($0) }

        view.mouseExited(with: Self.enterExitEvent(.mouseExited, timestamp: 10))
        view.mouseEntered(with: Self.enterExitEvent(.mouseEntered, timestamp: 9))

        XCTAssertEqual(reported, [])
        XCTAssertFalse(view.currentEffectiveHover)
    }

    func testStaleMouseExitedAfterNewerEnterDoesNotClearReportedHover() {
        let view = SidebarDDGHoverTrackingView(frame: NSRect(x: 0, y: 0, width: 120, height: 36))
        var reported: [Bool] = []
        view.onHoverChanged = { reported.append($0) }

        view.mouseEntered(with: Self.enterExitEvent(.mouseEntered, timestamp: 10))
        reported.removeAll()
        view.mouseExited(with: Self.enterExitEvent(.mouseExited, timestamp: 9))

        XCTAssertEqual(reported, [])
        XCTAssertTrue(view.currentEffectiveHover)
    }

    func testTrackingViewIsPaintlessNSViewNotAppKitControl() {
        let view = SidebarDDGHoverTrackingView(frame: NSRect(x: 0, y: 0, width: 120, height: 36))
        let nsView: NSView = view

        view.setHoverTrackingEnabled(false)

        XCTAssertFalse(nsView is NSControl)
        XCTAssertFalse(view.isOpaque)
        XCTAssertNil(view.backgroundLayer(createIfNeeded: true))
        XCTAssertNil(view.hitTest(NSPoint(x: 12, y: 12)))
    }

    func testSelectedStateWinsOverHoverState() {
        XCTAssertEqual(
            SidebarHoverChrome.visualState(isSelected: true, isHovered: true),
            .selected
        )
        XCTAssertEqual(
            SidebarHoverChrome.visualState(isSelected: false, isHovered: true),
            .hovered
        )
        XCTAssertEqual(
            SidebarHoverChrome.visualState(isSelected: false, isHovered: false),
            .idle
        )
    }

    func testActionVisibilityDoesNotChangeTrailingPaddingReservation() {
        let reservedPadding = SidebarHoverChrome.trailingPadding(showsTrailingAction: true)

        XCTAssertEqual(reservedPadding, SidebarRowLayout.trailingActionPadding)
        XCTAssertFalse(SidebarHoverChrome.showsTrailingAction(isHovered: false, isSelected: false))
        XCTAssertTrue(SidebarHoverChrome.showsTrailingAction(isHovered: true, isSelected: false))
        XCTAssertTrue(SidebarHoverChrome.showsTrailingAction(isHovered: false, isSelected: true))
        XCTAssertEqual(reservedPadding, SidebarHoverChrome.trailingPadding(showsTrailingAction: true))
    }

    private static func makeFloatingBarCardView() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 140))
        let view = NSView(frame: NSRect(x: 20, y: 20, width: 100, height: 60))
        container.addSubview(view)
        return view
    }

    private static func mouseDownEvent() throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }

    private static func enterExitEvent(_ type: NSEvent.EventType, timestamp: TimeInterval) -> NSEvent {
        guard let event = NSEvent.enterExitEvent(
            with: type,
            location: .zero,
            modifierFlags: [],
            timestamp: timestamp,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            trackingNumber: 1,
            userData: nil
        ) else {
            fatalError("Failed to create \(type) event")
        }
        return event
    }
}
